class_name NavGraph
extends RefCounted
# Road + sidewalk navigation graph exported by pipeline/nav.py (world/nav.json).
# Pure data + pure queries: no scene nodes, no physics, no raycasts. Node y is
# baked from the pipeline heightmap, so polyline followers sit on the road /
# sidewalk ribbons even outside the 280 m tile-collision ring.
#
# Conventions: t is measured along the TRAVEL direction of a polyline
# (dir = 1 follows n[] forward, -1 backward). Right of travel = (-d.z, 0, d.x).
# Car forward is -Z: yaw = atan2(-d.x, -d.z) (pipeline/cars.py convention).

const SIGNAL_PERIOD := 16.0
const GREEN_A_END := 7.5
const GREEN_B_START := 8.0
const GREEN_B_END := 15.5
const LANE_MIN := 1.0
const LANE_MAX := 1.75

var nodes := PackedVector3Array()
var roads: Array = []        # {n: PackedInt32Array, cum: PackedFloat32Array, cls, w, oneway, lanes, speed, stops: Array[[t_fwd, node]]}
var walks: Array = []        # {n, cum, kind}
var signals: Dictionary = {} # node -> true
var _road_out: Dictionary = {}  # node -> Array of [road_idx, dir, t_start]
var _walk_out: Dictionary = {}  # node -> Array of [walk_idx, dir, t_start]
var _arms: Dictionary = {}      # node -> road arms touching (endpoint = 1, interior = 2)
var _axis: Dictionary = {}      # signal node -> reference tangent for group split

static func load_from(path: String) -> NavGraph:
	var g := NavGraph.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("NavGraph: %s missing" % path)
		return g
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		g._build(data)
	return g

static func yaw_for(d: Vector3) -> float:
	return atan2(-d.x, -d.z)

static func pick(seed: int, n: int) -> int:
	if n <= 0:
		return -1
	return int((absi(seed) * 2654435761) % 2147483647) % n

# ---- build ---------------------------------------------------------------

func _build(data: Dictionary) -> void:
	for p in data.get("nodes", []):
		nodes.append(Vector3(p[0], p[1], p[2]))
	for s in data.get("signals", []):
		signals[int(s)] = true
	for rd in data.get("roads", []):
		var n := _ints(rd["n"])
		var cum := _cumulative(n)
		var ri := roads.size()
		var oneway := int(rd["oneway"])
		roads.append({"n": n, "cum": cum, "cls": rd["cls"], "w": float(rd["w"]),
			"oneway": oneway, "lanes": maxi(1, int(rd["lanes"])), "speed": float(rd["speed"]), "stops": []})
		var length := cum[cum.size() - 1]
		var last := n.size() - 1
		for k in n.size():
			var node := n[k]
			_arms[node] = int(_arms.get(node, 0)) + (1 if (k == 0 or k == last) else 2)
			if k < last:
				_push(_road_out, node, [ri, 1, cum[k]])
			if k > 0 and oneway == 0:
				_push(_road_out, node, [ri, -1, length - cum[k]])
	for wd in data.get("walks", []):
		var n := _ints(wd["n"])
		var cum := _cumulative(n)
		var wi := walks.size()
		walks.append({"n": n, "cum": cum, "kind": wd["kind"]})
		var length := cum[cum.size() - 1]
		var last := n.size() - 1
		for k in n.size():
			if k < last:
				_push(_walk_out, n[k], [wi, 1, cum[k]])
			if k > 0:
				_push(_walk_out, n[k], [wi, -1, length - cum[k]])
	# stop nodes per road (signals + junctions), in forward t order
	for road in roads:
		var n: PackedInt32Array = road["n"]
		var cum: PackedFloat32Array = road["cum"]
		var stops: Array = road["stops"]
		for k in n.size():
			if signals.has(n[k]) or is_junction(n[k]):
				stops.append([cum[k], n[k]])
	# signal axis: tangent of the first road leaving the node (deterministic)
	for node in signals:
		var outs: Array = _road_out.get(node, [])
		_axis[node] = road_tangent(outs[0][0], outs[0][1], outs[0][2]) if not outs.is_empty() else Vector3(0, 0, -1)

func _ints(arr: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in arr:
		out.append(int(v))
	return out

func _cumulative(n: PackedInt32Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.append(0.0)
	for k in range(1, n.size()):
		cum.append(cum[k - 1] + nodes[n[k - 1]].distance_to(nodes[n[k]]))
	return cum

func _push(map: Dictionary, node: int, entry: Array) -> void:
	if not map.has(node):
		map[node] = []
	(map[node] as Array).append(entry)

# ---- polyline sampling ---------------------------------------------------

func _poly_point(poly: Dictionary, s: float) -> Vector3:
	var n: PackedInt32Array = poly["n"]
	var cum: PackedFloat32Array = poly["cum"]
	var k := clampi(cum.bsearch(s, true) - 1, 0, n.size() - 2)
	var seg := cum[k + 1] - cum[k]
	var f := 0.0 if seg <= 0.0 else clampf((s - cum[k]) / seg, 0.0, 1.0)
	return nodes[n[k]].lerp(nodes[n[k + 1]], f)

func _poly_tangent(poly: Dictionary, s: float) -> Vector3:
	var n: PackedInt32Array = poly["n"]
	var cum: PackedFloat32Array = poly["cum"]
	var k := clampi(cum.bsearch(s, true) - 1, 0, n.size() - 2)
	var d := nodes[n[k + 1]] - nodes[n[k]]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-8 else Vector3(0, 0, -1)

func _length(poly: Dictionary) -> float:
	var cum: PackedFloat32Array = poly["cum"]
	return cum[cum.size() - 1]

func _travel_s(poly: Dictionary, dir: int, t: float) -> float:
	return t if dir == 1 else _length(poly) - t

func road_length(ri: int) -> float:
	return _length(roads[ri])

func road_tangent(ri: int, dir: int, t: float) -> Vector3:
	var poly: Dictionary = roads[ri]
	return _poly_tangent(poly, _travel_s(poly, dir, t)) * float(dir)

func road_point(ri: int, dir: int, lat: float, t: float) -> Vector3:
	var poly: Dictionary = roads[ri]
	var s := _travel_s(poly, dir, t)
	var d := _poly_tangent(poly, s) * float(dir)
	return _poly_point(poly, s) + Vector3(-d.z, 0.0, d.x) * lat

func end_node(ri: int, dir: int) -> int:
	var n: PackedInt32Array = roads[ri]["n"]
	return n[n.size() - 1] if dir == 1 else n[0]

func walk_length(wi: int) -> float:
	return _length(walks[wi])

func walk_tangent(wi: int, dir: int, t: float) -> Vector3:
	var poly: Dictionary = walks[wi]
	return _poly_tangent(poly, _travel_s(poly, dir, t)) * float(dir)

func walk_point(wi: int, dir: int, t: float) -> Vector3:
	var poly: Dictionary = walks[wi]
	return _poly_point(poly, _travel_s(poly, dir, t))

func walk_end_node(wi: int, dir: int) -> int:
	var n: PackedInt32Array = walks[wi]["n"]
	return n[n.size() - 1] if dir == 1 else n[0]

# ---- topology ------------------------------------------------------------

func _exits_from(map: Dictionary, node: int, idx: int, dir: int, allow_reverse: bool) -> Array:
	var out: Array = []
	for e in map.get(node, []):
		if not allow_reverse and e[0] == idx and e[1] == -dir:
			continue   # U-turn onto the polyline we arrived on
		out.append(e)
	return out

func exits(node: int, ri: int, dir: int, allow_reverse := false) -> Array:
	return _exits_from(_road_out, node, ri, dir, allow_reverse)

func walk_exits(node: int, wi: int, dir: int, allow_reverse := false) -> Array:
	return _exits_from(_walk_out, node, wi, dir, allow_reverse)

func is_junction(node: int) -> bool:
	return int(_arms.get(node, 0)) >= 3

func next_stop(ri: int, dir: int, t: float) -> Array:
	# [distance_ahead, node] of the next signal/junction node (a node just
	# passed within 1 m is still reported with a small negative distance), or [].
	var road: Dictionary = roads[ri]
	var stops: Array = road["stops"]
	if dir == 1:
		for st in stops:
			var d: float = st[0] - t
			if d > -1.0:
				return [d, st[1]]
	else:
		var s := road_length(ri) - t
		for k in range(stops.size() - 1, -1, -1):
			var d: float = s - stops[k][0]
			if d > -1.0:
				return [d, stops[k][1]]
	return []

# ---- lanes & signals -----------------------------------------------------

func lane_offset(ri: int, lane: int) -> float:
	var road: Dictionary = roads[ri]
	var w: float = road["w"]
	if road["oneway"] == 0:
		return clampf(w / 4.0, LANE_MIN, LANE_MAX)      # one lane per direction, right of centerline
	var lanes: int = road["lanes"]
	return w / 2.0 - w * (float(lane) + 0.5) / float(lanes)   # lane 0 = rightmost

func signal_group(node: int, heading: Vector3) -> int:
	var axis: Vector3 = _axis.get(node, Vector3(0, 0, -1))
	return 0 if absf(heading.dot(axis)) > 0.7071 else 1

func signal_green(node: int, group: int, time: float) -> bool:
	var t := fposmod(time + float(node) * 5.3, SIGNAL_PERIOD)   # per-node offset: the city is not synchronized
	if group == 0:
		return t < GREEN_A_END
	return t >= GREEN_B_START and t < GREEN_B_END
