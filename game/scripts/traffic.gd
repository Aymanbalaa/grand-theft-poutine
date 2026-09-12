extends Node3D
class_name Traffic
# Pooled traffic on the nav graph's lane centerlines (right-hand traffic).
# ONE manager, parallel state arrays, no per-agent scripts, no raycasts:
# heights ride the graph so agents stay valid outside the 280 m collision
# ring. Bodies are AnimatableBody3D (sync_to_physics) so the player's
# kinematic car collides with them; agents only ever brake, never react.
# Update runs in _physics_process (like car.gd) so the physics server sees
# consistent kinematic motion.

const SCENE := preload("res://scenes/traffic_car.tscn")
const POOL_SIZE := 40
const SPAWN_MIN := 80.0
const SPAWN_MAX := 220.0
const DESPAWN := 280.0
const SPAWN_INTERVAL := 0.5
const SPAWN_PER_TICK := 4          # burst-fill an empty pool in ~2.5 s
const SPAWN_GAP := 15.0
const SPAWN_CELL := 64.0
const CONE_LEN := 15.0
const CONE_HALF_W := 2.5
const CAR_LEN := 4.3
const HEADWAY_SEC := 2.0
const HEADWAY_MIN := 6.0
const ACCEL := 9.0                 # mirrors car.gd so traffic reads like the player's car
const BRAKE := 16.0
const SOFT_BRAKE := 4.0            # comfortable stop at lines/junctions
const STOP_LINE := 6.0
const JUNCTION_R := 8.0
const JUNCTION_SLOW := 15.0
const TURN_CHANCE := 0.35
const STUCK_SEC := 20.0
const PASS_AHEAD := 12.0
const PASS_NUDGE := 1.0
const LAT_RATE := 3.0
const CURVE_LOOKAHEAD := 8.0
const HEADLIGHTS := 8
const HEADLIGHT_REASSIGN := 0.25
const INACTIVE_POS := Vector3(0, -9999, 0)

@export var enabled := true

var graph: NavGraph
var obstacles := PackedVector3Array()   # extra brake points (10b pedestrians)

var _bodies: Array[AnimatableBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _active := PackedByteArray()
var _road := PackedInt32Array()
var _dir := PackedInt32Array()
var _lane := PackedInt32Array()
var _t := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _seed := PackedInt32Array()
var _stuck := PackedFloat32Array()
var _lat := PackedFloat32Array()
var _pos := PackedVector3Array()
var _fwd := PackedVector3Array()
var _hold := PackedInt32Array()        # junction node this agent occupies, or -1
var _occupant: Dictionary = {}         # junction node -> agent idx
var _parked := PackedVector3Array()    # all 120 parked cars (metadata)
var _parked_near := PackedVector3Array()
var _cells: Dictionary = {}            # Vector2i -> Array of [road_idx, t_forward]
var _lights: Array[SpotLight3D] = []
var _light_agent := PackedInt32Array()
var _spawn_accum := 0.0
var _light_accum := 1.0
var _rng := 20260911
var _time := 0.0

# ---- accessors (smoke test / 10b) -----------------------------------------

func graph_counts() -> Dictionary:
	if graph == null:
		return {}
	return {"nodes": graph.nodes.size(), "roads": graph.roads.size(),
		"walks": graph.walks.size(), "signals": graph.signals.size()}

func active_count() -> int:
	var c := 0
	for i in POOL_SIZE:
		if _active[i] == 1:
			c += 1
	return c

func agent_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in POOL_SIZE:
		out.append(_pos[i] if _active[i] == 1 else INACTIVE_POS)
	return out

func agent_forward(i: int) -> Vector3:
	return _fwd[i]

func agent_speed(i: int) -> float:
	return _speed[i] if _active[i] == 1 else 0.0

func clear_all() -> void:
	for i in POOL_SIZE:
		if _active[i] == 1:
			_deactivate(i)

# ---- setup ------------------------------------------------------------------

func _ready() -> void:
	add_to_group("traffic")
	graph = NavGraph.load_from("res://world/nav.json")
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			for cs in meta.get("car_spawns", []):
				_parked.append(Vector3(cs["x"], cs["y"], cs["z"]))
	_active.resize(POOL_SIZE); _road.resize(POOL_SIZE); _dir.resize(POOL_SIZE)
	_lane.resize(POOL_SIZE); _t.resize(POOL_SIZE); _speed.resize(POOL_SIZE)
	_seed.resize(POOL_SIZE); _stuck.resize(POOL_SIZE); _lat.resize(POOL_SIZE)
	_pos.resize(POOL_SIZE); _fwd.resize(POOL_SIZE); _hold.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var body := SCENE.instantiate() as AnimatableBody3D
		(body.get_node("Visual") as Node3D).set("color_index", i % 6)
		add_child(body)
		body.visible = false
		var shape := body.get_node("CollisionShape3D") as CollisionShape3D
		shape.disabled = true
		(body.get_node("Visual") as Node3D).set_process(false)   # model mode never needs it
		_bodies.append(body)
		_shapes.append(shape)
		_active[i] = 0
		_hold[i] = -1
		_pos[i] = INACTIVE_POS
	_build_spawn_cells()
	for k in HEADLIGHTS:
		var l := SpotLight3D.new()
		l.light_color = Color(1, 0.93, 0.8)
		l.light_energy = 0.0
		l.spot_range = 32.0
		l.spot_angle = 45.0
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 1.5
		add_child(l)
		_lights.append(l)
		_light_agent.append(-1)

func _build_spawn_cells() -> void:
	# Bucket every road node (as [road, t_forward]) into 64 m cells so spawning
	# can sample the ring around the camera instead of the whole 4.4 km world.
	for ri in graph.roads.size():
		var n: PackedInt32Array = graph.roads[ri]["n"]
		var cum: PackedFloat32Array = graph.roads[ri]["cum"]
		for k in n.size():
			var p := graph.nodes[n[k]]
			var cell := Vector2i(floori(p.x / SPAWN_CELL), floori(p.z / SPAWN_CELL))
			if not _cells.has(cell):
				_cells[cell] = []
			(_cells[cell] as Array).append([ri, cum[k]])

func _rand01() -> float:
	_rng = int((_rng * 1103515245 + 12345) % 2147483648)
	return float(_rng) / 2147483648.0

func _rand_int(n: int) -> int:
	return int(_rand01() * float(n)) % maxi(n, 1)

# ---- frame ------------------------------------------------------------------

func _context() -> Dictionary:
	var main := get_parent()
	if main != null and main.has_method("agents_context"):
		return main.call("agents_context")
	return {}

func _physics_process(delta: float) -> void:
	_time += delta
	if not enabled or graph == null or graph.roads.is_empty():
		for l in _lights:
			l.light_energy = 0.0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	var ctx := _context()
	_spawn_accum += delta
	if _spawn_accum >= SPAWN_INTERVAL:
		_spawn_accum = 0.0
		_refresh_parked_near(cam_pos)
		_spawn_some(cam, ctx)
	for i in POOL_SIZE:
		if _active[i] == 0:
			continue
		_step_agent(i, delta, ctx)
		if _active[i] == 1 and (_pos[i].distance_to(cam_pos) > DESPAWN or _stuck[i] > STUCK_SEC):
			_deactivate(i)
	_update_headlights(delta, cam_pos)

# ---- spawning ----------------------------------------------------------------

func _refresh_parked_near(cam_pos: Vector3) -> void:
	_parked_near.clear()
	for p in _parked:
		if p.distance_to(cam_pos) < DESPAWN + 50.0:
			_parked_near.append(p)

func _free_slot() -> int:
	for i in POOL_SIZE:
		if _active[i] == 0:
			return i
	return -1

func _clear_of_others(pos: Vector3, ctx: Dictionary) -> bool:
	for j in POOL_SIZE:
		if _active[j] == 1 and _pos[j].distance_to(pos) < SPAWN_GAP:
			return false
	for p in _parked_near:
		if p.distance_to(pos) < SPAWN_GAP:
			return false
	if ctx.has("car") and (ctx["car"] as Vector3).distance_to(pos) < SPAWN_GAP:
		return false
	return true

func _spawn_some(cam: Camera3D, ctx: Dictionary) -> void:
	var cam_pos := cam.global_position
	var cam_fwd := -cam.global_transform.basis.z
	var spawned := 0
	var attempts := 0
	while spawned < SPAWN_PER_TICK and attempts < 24:
		attempts += 1
		var slot := _free_slot()
		if slot < 0:
			return
		var ang := _rand01() * TAU
		var rad := SPAWN_MIN + _rand01() * (SPAWN_MAX - SPAWN_MIN)
		var probe := cam_pos + Vector3(cos(ang), 0.0, sin(ang)) * rad
		var cands: Array = _cells.get(Vector2i(floori(probe.x / SPAWN_CELL), floori(probe.z / SPAWN_CELL)), [])
		if cands.is_empty():
			continue
		var c: Array = cands[_rand_int(cands.size())]
		var ri: int = c[0]
		var road: Dictionary = graph.roads[ri]
		var length := graph.road_length(ri)
		if length < 10.0:
			continue
		var dir := 1 if (road["oneway"] == 1 or _rand01() < 0.5) else -1
		var t: float = c[1] if dir == 1 else length - c[1]
		t = clampf(t, 0.0, length - 0.1)
		var lane := _rand_int(road["lanes"]) if road["oneway"] == 1 else 0
		var lat := graph.lane_offset(ri, lane)
		var pos := graph.road_point(ri, dir, lat, t)
		var d := pos.distance_to(cam_pos)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		if attempts < 12 and (pos - cam_pos).normalized().dot(cam_fwd) > 0.3:
			continue   # first tries prefer spawning behind the camera
		if not _clear_of_others(pos, ctx):
			continue
		_activate(slot, ri, dir, lane, t, lat)
		spawned += 1

func _activate(i: int, ri: int, dir: int, lane: int, t: float, lat: float) -> void:
	_active[i] = 1
	_road[i] = ri; _dir[i] = dir; _lane[i] = lane; _t[i] = t; _lat[i] = lat
	_speed[i] = float(graph.roads[ri]["speed"]) * 0.5
	_seed[i] = int((_rng + i * 7919) % 2147483647)
	_stuck[i] = 0.0
	_hold[i] = -1
	_fwd[i] = graph.road_tangent(ri, dir, t)
	_pos[i] = graph.road_point(ri, dir, lat, t)
	var body := _bodies[i]
	body.global_transform = Transform3D(Basis.from_euler(Vector3(0.0, NavGraph.yaw_for(_fwd[i]), 0.0)), _pos[i])
	body.visible = true
	_shapes[i].set_deferred("disabled", false)

func _deactivate(i: int) -> void:
	_active[i] = 0
	_release(i)
	_bodies[i].visible = false
	_shapes[i].set_deferred("disabled", true)
	_pos[i] = INACTIVE_POS

# ---- agent step ----------------------------------------------------------------

func _stop_speed(gap: float) -> float:
	return sqrt(maxf(0.0, 2.0 * SOFT_BRAKE * gap))

func _cone_gap(pos: Vector3, fwd: Vector3, right: Vector3, o: Vector3) -> float:
	var rel := o - pos
	if absf(rel.y) > 4.0:
		return INF   # overpass / underpass
	var f := rel.dot(fwd)
	if f <= 0.0 or f > CONE_LEN + CAR_LEN or absf(rel.dot(right)) > CONE_HALF_W:
		return INF
	return f - CAR_LEN

func _nearest_gap(i: int, pos: Vector3, fwd: Vector3, right: Vector3, ctx: Dictionary) -> float:
	var best := INF
	for j in POOL_SIZE:
		if j != i and _active[j] == 1:
			best = minf(best, _cone_gap(pos, fwd, right, _pos[j]))
	if ctx.has("car"):
		best = minf(best, _cone_gap(pos, fwd, right, ctx["car"]))
	if ctx.get("player_on_foot", false):
		best = minf(best, _cone_gap(pos, fwd, right, ctx["player"]))
	for o in obstacles:
		best = minf(best, _cone_gap(pos, fwd, right, o))
	return best

func _parked_ahead(pos: Vector3, fwd: Vector3, right: Vector3) -> bool:
	for p in _parked_near:
		var rel := p - pos
		var f := rel.dot(fwd)
		if f > -2.0 and f < PASS_AHEAD and absf(rel.dot(right)) < 2.0 and absf(rel.y) < 4.0:
			return true
	return false

func _release(i: int) -> void:
	var node := _hold[i]
	if node >= 0:
		if _occupant.get(node, -1) == i:
			_occupant.erase(node)
		_hold[i] = -1

func _stop_rules(i: int, fwd: Vector3, pos_now: Vector3, target: float) -> float:
	# Signals: stop at a red's stop line unless the bumper is already past it.
	# Unsignalized junctions: slow to half within 15 m; the first agent inside
	# the 8 m radius owns the node, others hold at the stop line until it leaves.
	var stop := graph.next_stop(_road[i], _dir[i], _t[i])
	if stop.is_empty():
		if _hold[i] >= 0 and pos_now.distance_to(graph.nodes[_hold[i]]) > JUNCTION_R + 2.0:
			_release(i)
		return target
	var d: float = stop[0]
	var node: int = stop[1]
	if graph.signals.has(node):
		var grp := graph.signal_group(node, graph.road_tangent(_road[i], _dir[i], _t[i] + d))
		if not graph.signal_green(node, grp, _time) and d > STOP_LINE - 1.0:
			target = minf(target, _stop_speed(d - STOP_LINE))
	else:
		if d < JUNCTION_SLOW:
			target = minf(target, float(graph.roads[_road[i]]["speed"]) * 0.5)
		if d < JUNCTION_R:
			var owner: int = _occupant.get(node, -1)
			if owner < 0 or _active[owner] == 0:
				if _hold[i] >= 0 and _hold[i] != node:
					_release(i)
				_occupant[node] = i
				_hold[i] = node
			elif owner != i and d > STOP_LINE - 1.0:
				target = minf(target, _stop_speed(d - STOP_LINE))
	if _hold[i] >= 0 and _hold[i] != node and pos_now.distance_to(graph.nodes[_hold[i]]) > JUNCTION_R + 2.0:
		_release(i)
	return target

func _maybe_turn(i: int, node: int) -> void:
	# Passing an interior junction: with TURN_CHANCE take a side exit
	# (never the continuation, never the reverse).
	if not graph.is_junction(node):
		return
	_seed[i] = int((_seed[i] * 1103515245 + 12345) % 2147483648)
	if float(_seed[i] % 1000) / 1000.0 >= TURN_CHANCE:
		return
	var options: Array = []
	for e in graph.exits(node, _road[i], _dir[i]):
		if not (e[0] == _road[i] and e[1] == _dir[i]):
			options.append(e)
	if options.is_empty():
		return
	var e: Array = options[NavGraph.pick(_seed[i], options.size())]
	_release(i)
	_enter_road(i, e[0], e[1], e[2])

func signal_probe() -> Dictionary:
	# Sweep one 16 s cycle on the first signal node that has two approach groups.
	var out := {"a_green": false, "a_red": false, "b_green": false, "b_red": false, "both": false}
	if graph == null:
		return out
	var probe := -1
	for node in graph.signals:
		var g0 := 0
		var g1 := 0
		for e in graph.exits(node, -1, 0, true):
			if graph.signal_group(node, graph.road_tangent(e[0], e[1], e[2])) == 0:
				g0 += 1
			else:
				g1 += 1
		if g0 > 0 and g1 > 0:
			probe = node
			break
	if probe < 0:
		return out
	var tt := 0.0
	while tt < NavGraph.SIGNAL_PERIOD:
		var ga := graph.signal_green(probe, 0, tt)
		var gb := graph.signal_green(probe, 1, tt)
		out["both"] = out["both"] or (ga and gb)
		out["a_green"] = out["a_green"] or ga
		out["a_red"] = out["a_red"] or not ga
		out["b_green"] = out["b_green"] or gb
		out["b_red"] = out["b_red"] or not gb
		tt += 0.5
	return out

func _step_agent(i: int, delta: float, ctx: Dictionary) -> void:
	var ri := _road[i]
	var dir := _dir[i]
	var t := _t[i]
	var road: Dictionary = graph.roads[ri]
	var length := graph.road_length(ri)
	var fwd := graph.road_tangent(ri, dir, t)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var pos := graph.road_point(ri, dir, _lat[i], t)
	var target: float = road["speed"]
	# curve ahead on this road
	var turn := fwd.angle_to(graph.road_tangent(ri, dir, minf(t + CURVE_LOOKAHEAD, length)))
	target *= clampf(1.0 - turn / 1.2, 0.35, 1.0)
	# turn onto the (single) exit at the road end
	if length - t < CURVE_LOOKAHEAD:
		var ex := graph.exits(graph.end_node(ri, dir), ri, dir)
		if ex.size() == 1:
			target *= clampf(1.0 - fwd.angle_to(graph.road_tangent(ex[0][0], ex[0][1], ex[0][2])) / 1.2, 0.35, 1.0)
		elif ex.is_empty():
			target = minf(target, 2.0)
	target = _stop_rules(i, fwd, pos, target)
	# anything in the cone ahead
	var gap := _nearest_gap(i, pos, fwd, right, ctx)
	if gap < INF:
		target = minf(target, maxf(0.0, (gap - HEADWAY_MIN) / HEADWAY_SEC))
	# parked car in the lane: nudge toward the centerline while passing
	var lane_off := graph.lane_offset(ri, _lane[i])
	var want := lane_off
	if _parked_ahead(pos, fwd, right):
		want = lane_off - PASS_NUDGE               # always shift LEFT, away from the curb-parked car
		if road["oneway"] == 0:
			want = maxf(0.6, want)                  # two-way: never cross into the oncoming lane
	_lat[i] = move_toward(_lat[i], want, LAT_RATE * delta)
	# integrate
	var sp := clampf(target, _speed[i] - BRAKE * delta, _speed[i] + ACCEL * delta)
	_speed[i] = sp
	_stuck[i] = _stuck[i] + delta if sp < 0.2 else 0.0
	var stop := graph.next_stop(ri, dir, t)
	var t_new := t + sp * delta
	if not stop.is_empty() and stop[0] > 0.0 and t_new - t >= stop[0] and t + stop[0] < length - 0.5:
		_maybe_turn(i, stop[1])          # may rewrite _road/_dir/_t
		if _road[i] != ri or _dir[i] != dir:
			_settle(i)
			return
	t = t_new
	if t >= length:
		var node := graph.end_node(ri, dir)
		var ex := graph.exits(node, ri, dir)
		if ex.is_empty():
			ex = graph.exits(node, ri, dir, true)
		if ex.is_empty():
			_deactivate(i)
			return
		_seed[i] = int((_seed[i] * 1103515245 + 12345) % 2147483648)
		var e: Array = ex[NavGraph.pick(_seed[i], ex.size())]
		_release(i)
		_enter_road(i, e[0], e[1], e[2] + (t - length))
		return
	_t[i] = t
	_settle(i)

func _enter_road(i: int, ri: int, dir: int, t: float) -> void:
	var road: Dictionary = graph.roads[ri]
	_road[i] = ri
	_dir[i] = dir
	_t[i] = clampf(t, 0.0, graph.road_length(ri))
	_lane[i] = (_seed[i] % int(road["lanes"])) if road["oneway"] == 1 else 0
	_settle(i)

func _settle(i: int) -> void:
	# write pose from (road, dir, lat, t) to the body
	var ri := _road[i]
	var dir := _dir[i]
	var t := _t[i]
	_fwd[i] = graph.road_tangent(ri, dir, t)
	_pos[i] = graph.road_point(ri, dir, _lat[i], t)
	_bodies[i].global_transform = Transform3D(Basis.from_euler(Vector3(0.0, NavGraph.yaw_for(_fwd[i]), 0.0)), _pos[i])

# ---- pooled headlights ------------------------------------------------------------

func _update_headlights(delta: float, cam_pos: Vector3) -> void:
	_light_accum += delta
	var sun := get_tree().get_first_node_in_group("sun")
	var night: float = 0.0 if sun == null else sun.night_amount
	var energy := 20.0 * smoothstep(0.4, 0.55, night)
	if _light_accum >= HEADLIGHT_REASSIGN:
		_light_accum = 0.0
		var near: Array = []
		for i in POOL_SIZE:
			if _active[i] == 1:
				near.append([_pos[i].distance_squared_to(cam_pos), i])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for k in HEADLIGHTS:
			_light_agent[k] = near[k][1] if k < near.size() else -1
	for k in HEADLIGHTS:
		var a := _light_agent[k]
		var l := _lights[k]
		if a < 0 or _active[a] == 0 or energy <= 0.0:
			l.light_energy = 0.0
			continue
		l.light_energy = energy
		var yaw := NavGraph.yaw_for(_fwd[a])
		l.global_transform = Transform3D(Basis.from_euler(Vector3(-0.13, yaw, 0.0)), _pos[a] + _fwd[a] * 2.0 + Vector3(0, 0.72, 0))
