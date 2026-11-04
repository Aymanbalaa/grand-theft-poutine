class_name SliceTraffic
extends Node3D
# A few cars nosing through the quarter at Old-Montréal pace. Saint-Paul and
# Saint-Vincent are one-way (centre lane, clear of the parked cars); la Commune
# is two-way. Each car follows a fixed route from one street end to another,
# brakes for anyone in its path (finite deceleration: step out too late and it
# clips you), honks at a courier blocking it, and re-enters at a street end
# out of the player's sight. Headlights + tail lamps light the wet cobbles.

signal hit_player(dir: Vector3, speed: float)

const MODEL_SCALE := {0: 1.55, 1: 1.55, 2: 1.5, 3: 1.45, 4: 1.45, 5: 1.5}
const PAINT := [Color(0.55, 0.08, 0.07), Color(0.08, 0.16, 0.3), Color(0.82, 0.82, 0.84), Color(0.06, 0.06, 0.07),
	Color(0.2, 0.3, 0.22), Color(0.45, 0.42, 0.38)]
const CRUISE := 7.5            # m/s (27 km/h)
const BRAKE := 7.0             # m/s² comfortable deceleration
const ACCEL := 2.6
const LOOK := 9.0              # metres of road scanned ahead
const LANE_HALF := 1.25        # lateral half-width of the scan
const HALF_LEN := 2.1
const HALF_W := 0.95
# One-way routes along road centre lines; la Commune lanes sit 1.6 m right
# of its centre line.
const ROUTES := [
	[Vector3(0, 0, 46), Vector3(0, 0, -52), Vector3(0, 0, -116.4), Vector3(50, 0, -116.4)],      # Saint-Paul -> la Commune est
	[Vector3(99, 0, -52), Vector3(-99, 0, -52)],                                                  # Saint-Vincent, westbound
	[Vector3(99, 0, -52), Vector3(0, 0, -52), Vector3(0, 0, -119.6), Vector3(-50, 0, -119.6)],     # Saint-Vincent -> Saint-Paul -> la Commune ouest
	[Vector3(0, 0, 46), Vector3(0, 0, -52), Vector3(-99, 0, -52)],                                # Saint-Paul -> Saint-Vincent ouest
	[Vector3(-50, 0, -116.4), Vector3(50, 0, -116.4)],                                           # la Commune est
	[Vector3(50, 0, -119.6), Vector3(-50, 0, -119.6)],                                           # la Commune ouest
]

var player: CharacterBody3D
var peds: Node                 # SlicePedestrians (walkers to brake for)
var cars: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var lights_on := true
var _honk: AudioStream
var _engine: AudioStream

var enabled := true

# Park every car out of sight (tests that only exercise walking geometry).
func set_enabled(on: bool) -> void:
	enabled = on
	for c in cars:
		c["active"] = false
		c["wait"] = 0.5
		(c["node"] as Node3D).visible = false
		(c["node"] as Node3D).global_position = Vector3(0, -50, 0)
		(c["eng"] as AudioStreamPlayer3D).stop()

func positions() -> Array:
	var out := []
	for c in cars:
		if c["active"]:
			out.append((c["node"] as Node3D).global_position)
	return out

func spawn(count: int) -> void:
	rng.seed = 7311
	_honk = load("res://assets/slice/audio/sfx_honk.wav") if ResourceLoader.exists("res://assets/slice/audio/sfx_honk.wav") else null
	if ResourceLoader.exists("res://assets/audio/engine.wav"):
		var st := (load("res://assets/audio/engine.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = int(st.get_length() * st.mix_rate)
		_engine = st
	for i in count:
		var c := _make_car(i)
		cars.append(c)
		# stagger along their routes so the street isn't empty at start
		_start(c, rng.randf_range(0.15, 0.8))

func _make_car(i: int) -> Dictionary:
	var root := AnimatableBody3D.new()
	root.sync_to_physics = false
	root.name = "Car%d" % i
	add_child(root)
	var idx := i % 6
	var model := (load("res://assets/models/cars/car%d.glb" % idx) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * float(MODEL_SCALE[idx])
	model.rotation.y = PI
	model.position.y = 0.3 * float(MODEL_SCALE[idx])   # wheels sit below the glTF origin
	root.add_child(model)
	var paint: Color = PAINT[i % PAINT.size()]
	var wheels: Array[Node3D] = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).begins_with("wheel"):
			# re-pivot the wheel on its own centre so it can spin
			var ctr := m.get_aabb().get_center()
			var pv := Node3D.new()
			m.get_parent().add_child(pv)
			pv.position = m.position + ctr
			m.reparent(pv, false)
			m.position = -ctr
			wheels.append(pv)
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var d := mat.duplicate() as BaseMaterial3D
			if d.albedo_texture == null:
				d.albedo_texture = load("res://assets/models/cars/Textures/colormap.png")
			d.clearcoat_enabled = true
			d.clearcoat = 0.8
			d.clearcoat_roughness = 0.12
			d.metallic = 0.3
			d.roughness = 0.3
			if String(m.name) == "body":
				d.albedo_color = paint.lightened(0.15) if idx != 2 and idx != 3 else Color.WHITE
			m.set_surface_override_material(s, d)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(HALF_W * 2.0, 1.3, HALF_LEN * 2.0)
	cs.shape = bx
	cs.position.y = 0.75
	root.add_child(cs)
	# lamps: one shadowless spot for the pair of headlights, emissive lenses
	var head := SpotLight3D.new()
	head.light_color = Color(1.0, 0.92, 0.78)
	head.light_energy = 6.0
	head.spot_range = 24.0
	head.spot_angle = 32.0
	head.spot_attenuation = 0.8
	head.light_volumetric_fog_energy = 1.0
	head.shadow_enabled = false
	head.position = Vector3(0, 0.75, -HALF_LEN - 0.05)
	head.rotation.x = deg_to_rad(-8.0)
	root.add_child(head)
	var lens_mat := StandardMaterial3D.new()
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.95, 0.85)
	lens_mat.emission_energy_multiplier = 6.0
	lens_mat.albedo_color = Color(1, 1, 1)
	var tail_mat := StandardMaterial3D.new()
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.06, 0.04)
	tail_mat.emission_energy_multiplier = 3.0
	tail_mat.albedo_color = Color(0.5, 0.02, 0.02)
	for sx in [-1.0, 1.0]:
		for spec in [[lens_mat, -HALF_LEN + 0.02, 0.72], [tail_mat, HALF_LEN - 0.02, 0.78]]:
			var lm := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.09
			sm.height = 0.12
			sm.radial_segments = 8
			sm.rings = 4
			sm.material = spec[0]
			lm.mesh = sm
			lm.position = Vector3(sx * 0.55, spec[2], spec[1])
			lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(lm)
	var tail_glow := OmniLight3D.new()
	tail_glow.light_color = Color(1.0, 0.1, 0.05)
	tail_glow.light_energy = 0.6
	tail_glow.omni_range = 3.0
	tail_glow.position = Vector3(0, 0.7, HALF_LEN + 0.3)
	root.add_child(tail_glow)
	var eng := AudioStreamPlayer3D.new()
	eng.stream = _engine
	eng.volume_db = -14.0
	eng.unit_size = 4.0
	eng.max_distance = 45.0
	root.add_child(eng)
	var horn := AudioStreamPlayer3D.new()
	horn.stream = _honk
	horn.volume_db = -2.0
	horn.unit_size = 8.0
	root.add_child(horn)
	return {"node": root, "route": 0, "seg": 0, "s": 0.0, "speed": CRUISE, "active": false, "wait": 0.0,
		"wheels": wheels, "head": head, "tail": tail_mat, "eng": eng, "horn": horn, "blocked_t": 0.0, "honk_cd": 0.0,
		"cruise": CRUISE * rng.randf_range(0.85, 1.1), "hit_cd": 0.0, "id": i, "stuck_t": 0.0, "yield_t": 0.0}

func _route_len(r: Array) -> float:
	var l := 0.0
	for i in r.size() - 1:
		l += (r[i] as Vector3).distance_to(r[i + 1])
	return l

# Place a car on a route at fraction `f` of its length.
func _start(c: Dictionary, f: float) -> void:
	var ri := rng.randi() % ROUTES.size()
	c["route"] = ri
	var r: Array = ROUTES[ri]
	var want := _route_len(r) * f
	c["seg"] = 0
	c["s"] = 0.0
	while c["seg"] < r.size() - 2 and want > (r[c["seg"]] as Vector3).distance_to(r[c["seg"] + 1]):
		want -= (r[c["seg"]] as Vector3).distance_to(r[c["seg"] + 1])
		c["seg"] += 1
	c["s"] = want
	c["speed"] = c["cruise"] * 0.6
	c["active"] = true
	(c["node"] as Node3D).visible = true
	(c["eng"] as AudioStreamPlayer3D).play(randf() * 1.0)
	_pose(c, 0.0)

func _pos_on(c: Dictionary, ahead: float) -> Vector3:
	var r: Array = ROUTES[c["route"]]
	var seg: int = c["seg"]
	var s: float = c["s"] + ahead
	while seg < r.size() - 1:
		var l := (r[seg] as Vector3).distance_to(r[seg + 1])
		if s <= l or seg == r.size() - 2:
			return (r[seg] as Vector3).lerp(r[seg + 1], clampf(s / l, 0.0, 1.0))
		s -= l
		seg += 1
	return r[r.size() - 1]

func _pose(c: Dictionary, delta: float) -> void:
	var n := c["node"] as Node3D
	var p := _pos_on(c, 0.0)
	# steer toward a point a little ahead: rounds the corners
	var look := _pos_on(c, 3.2)
	var fwd := look - p
	fwd.y = 0
	var y := 0.0
	if fwd.length() > 0.05:
		y = atan2(-fwd.x, -fwd.z)
	var cur := n.rotation.y if delta > 0.0 else y
	n.global_position = Vector3(p.x, 0.0, p.z)
	n.rotation.y = lerp_angle(cur, y, clampf(delta * 6.0, 0, 1)) if delta > 0.0 else y

func _hidden_from_player(p: Vector3) -> bool:
	if player == null:
		return true
	var cam := get_viewport().get_camera_3d()
	var far := p.distance_to(player.global_position) > 38.0
	if cam == null:
		return far
	var behind := cam.is_position_behind(p + Vector3.UP)
	return far or (behind and p.distance_to(player.global_position) > 14.0)

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	for c in cars:
		if not c["active"]:
			c["wait"] -= delta
			if c["wait"] <= 0.0:
				var ri := rng.randi() % ROUTES.size()
				var start: Vector3 = ROUTES[ri][0]
				if _hidden_from_player(start) and not _occupied(start):
					_start(c, 0.0)
					c["route"] = ri
					c["seg"] = 0
					c["s"] = 0.0
					_pose(c, 0.0)
				else:
					c["wait"] = 0.5
			continue
		_drive(c, delta)

func _occupied(p: Vector3) -> bool:
	for o in cars:
		if o["active"] and (o["node"] as Node3D).global_position.distance_to(p) < 9.0:
			return true
	return false

func _drive(c: Dictionary, delta: float) -> void:
	var n := c["node"] as Node3D
	var pos := n.global_position
	var fwd := -n.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	# nearest obstacle ahead in the lane: player, walkers, other cars
	var gap := INF
	var player_gap := INF
	if player != null:
		var pg := _gap(pos, fwd, right, player.global_position, 0.4)
		player_gap = pg
		gap = pg
	if peds != null:
		for w in peds.get("walkers"):
			gap = minf(gap, _gap(pos, fwd, right, (w["p"] as Node3D).global_position, 0.35))
	var car_gap := INF
	if c["yield_t"] <= 0.0:
		for o in cars:
			if o != c and o["active"]:
				car_gap = minf(car_gap, _gap(pos, fwd, right, (o["node"] as Node3D).global_position, HALF_LEN))
	gap = minf(gap, car_gap)
	# two cars nose to nose at the crossroads: after a moment one creeps through
	c["yield_t"] -= delta
	if car_gap < 3.0 and c["speed"] < 0.3:
		c["stuck_t"] += delta
		if c["stuck_t"] > 2.5 + 0.7 * c["id"]:
			c["yield_t"] = 2.0
			c["stuck_t"] = 0.0
	else:
		c["stuck_t"] = 0.0
	var want: float = c["cruise"]
	# slow for corners: compare heading now and a few metres on
	var a := _pos_on(c, 0.0)
	var b := _pos_on(c, 6.0)
	var d2 := _pos_on(c, 12.0)
	var turn := 0.0
	if (b - a).length() > 0.1 and (d2 - b).length() > 0.1:
		turn = 1.0 - (b - a).normalized().dot((d2 - b).normalized())
	want *= lerpf(1.0, 0.45, clampf(turn * 3.0, 0.0, 1.0))
	if gap < INF:
		# stop 1.4 m short of the obstacle
		var room := maxf(0.0, gap - 1.4)
		want = minf(want, sqrt(2.0 * BRAKE * room))
	var sp: float = c["speed"]
	if want < sp:
		sp = maxf(want, sp - BRAKE * 1.4 * delta)
	else:
		sp = minf(want, sp + ACCEL * delta)
	c["speed"] = sp
	# honk at a courier standing in the road
	c["honk_cd"] -= delta
	if player_gap < 7.0 and sp < 1.0:
		c["blocked_t"] += delta
		if c["blocked_t"] > 1.2 and c["honk_cd"] <= 0.0 and c["horn"].stream != null:
			(c["horn"] as AudioStreamPlayer3D).play()
			c["honk_cd"] = 3.5
	else:
		c["blocked_t"] = 0.0
	# contact with the player while still rolling
	c["hit_cd"] -= delta
	if player != null and c["hit_cd"] <= 0.0 and sp > 1.8:
		var rel: Vector3 = player.global_position - pos
		var lx := rel.dot(right)
		var lz := rel.dot(fwd)
		if abs(lx) < HALF_W + 0.3 and lz > -HALF_LEN and lz < HALF_LEN + 0.45 and abs(rel.y) < 1.5:
			c["hit_cd"] = 1.5
			var push := fwd * 0.6 + right * (signf(lx) if abs(lx) > 0.05 else 1.0)
			hit_player.emit(push.normalized(), sp)
			c["speed"] = sp * 0.3
	# advance
	c["s"] += sp * delta
	var r: Array = ROUTES[c["route"]]
	while c["seg"] < r.size() - 1 and c["s"] > (r[c["seg"]] as Vector3).distance_to(r[c["seg"] + 1]):
		c["s"] -= (r[c["seg"]] as Vector3).distance_to(r[c["seg"] + 1])
		c["seg"] += 1
	if c["seg"] >= r.size() - 1:
		# reached the street end: park out of sight and come back later
		c["active"] = false
		c["wait"] = rng.randf_range(1.0, 5.0)
		n.visible = false
		n.global_position = Vector3(0, -50, 0)
		(c["eng"] as AudioStreamPlayer3D).stop()
		return
	_pose(c, delta)
	for wv in c["wheels"]:
		(wv as Node3D).rotation.x -= sp / 0.45 * delta
	var eng := c["eng"] as AudioStreamPlayer3D
	eng.pitch_scale = 0.55 + 0.6 * sp / CRUISE
	(c["head"] as SpotLight3D).visible = lights_on
	var braking := want < sp - 0.2 or sp < 0.4
	(c["tail"] as StandardMaterial3D).emission_energy_multiplier = 10.0 if braking else 3.0

# Distance along `fwd` to `p` if it sits in the lane ahead, else INF.
func _gap(pos: Vector3, fwd: Vector3, right: Vector3, p: Vector3, radius: float) -> float:
	var rel := p - pos
	rel.y = 0
	var ahead := rel.dot(fwd) - HALF_LEN
	if ahead < -0.6 or ahead > LOOK:
		return INF
	if abs(rel.dot(right)) > LANE_HALF + radius:
		return INF
	return maxf(ahead - radius, 0.0)
