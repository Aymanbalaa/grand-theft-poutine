extends SceneTree
# tools/godot/godot_console.exe --headless --path game --script res://tests/nav_test.gd
# Pure-data checks on the exported nav graph + a seeded walker that must not dead-end.

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _init() -> void:
	var g := NavGraph.load_from("res://world/nav.json")
	if g.nodes.size() < 10000 or g.roads.size() < 1000 or g.walks.size() < 1000 or g.signals.size() < 500:
		_fail("graph too small: nodes=%d roads=%d walks=%d signals=%d" % [g.nodes.size(), g.roads.size(), g.walks.size(), g.signals.size()])
		return
	# endpoints: t=0 / t=len map onto the end nodes, both directions
	var road: Dictionary = g.roads[0]
	var n: PackedInt32Array = road["n"]
	var L := g.road_length(0)
	if g.road_point(0, 1, 0.0, 0.0).distance_to(g.nodes[n[0]]) > 0.01 \
			or g.road_point(0, 1, 0.0, L).distance_to(g.nodes[n[n.size() - 1]]) > 0.01 \
			or g.road_point(0, -1, 0.0, 0.0).distance_to(g.nodes[n[n.size() - 1]]) > 0.01:
		_fail("road_point endpoints wrong")
		return
	# lateral offset is to the RIGHT of travel: forward -Z => +X
	var d := Vector3(0, 0, -1)
	if absf(NavGraph.yaw_for(d)) > 1e-6:
		_fail("yaw_for(-Z) must be 0")
		return
	# seeded road walker: 200 m without dead-ending, only legal transitions
	var ri := 0
	var dir := 1
	var t := 0.0
	var travelled := 0.0
	var hops := 0
	while travelled < 200.0 and hops < 200:
		var step := minf(5.0, g.road_length(ri) - t)
		t += step
		travelled += step
		if t >= g.road_length(ri) - 1e-4:
			var ex := g.exits(g.end_node(ri, dir), ri, dir)
			if ex.is_empty():
				ex = g.exits(g.end_node(ri, dir), ri, dir, true)
			if ex.is_empty():
				_fail("road walker dead-ended at road %d" % ri)
				return
			var e: Array = ex[NavGraph.pick(hops * 7 + 1, ex.size())]
			if g.roads[e[0]]["oneway"] == 1 and e[1] != 1:
				_fail("exit drives a oneway backwards")
				return
			ri = e[0]; dir = e[1]; t = e[2]
			hops += 1
	if travelled < 200.0:
		_fail("road walker only travelled %.1f m" % travelled)
		return
	# seeded walk walker (sidewalks/paths/crossings) 200 m
	var wi := 0
	dir = 1; t = 0.0; travelled = 0.0; hops = 0
	while travelled < 200.0 and hops < 400:
		var step := minf(3.0, g.walk_length(wi) - t)
		t += step
		travelled += step
		if t >= g.walk_length(wi) - 1e-4:
			var ex := g.walk_exits(g.walk_end_node(wi, dir), wi, dir)
			if ex.is_empty():
				ex = g.walk_exits(g.walk_end_node(wi, dir), wi, dir, true)
			if ex.is_empty():
				_fail("walk walker dead-ended at walk %d" % wi)
				return
			var e: Array = ex[NavGraph.pick(hops * 13 + 5, ex.size())]
			wi = e[0]; dir = e[1]; t = e[2]
			hops += 1
	if travelled < 200.0:
		_fail("walk walker only travelled %.1f m" % travelled)
		return
	# lane offsets: two-way = clamp(w/4, 1, 1.75); oneway spreads lanes, lane 0 rightmost
	var two_way := -1
	var one_way := -1
	for i in g.roads.size():
		if two_way < 0 and g.roads[i]["oneway"] == 0:
			two_way = i
		if one_way < 0 and g.roads[i]["oneway"] == 1 and int(g.roads[i]["lanes"]) >= 2:
			one_way = i
		if two_way >= 0 and one_way >= 0:
			break
	if two_way < 0 or one_way < 0:
		_fail("graph lacks a two-way road or a multi-lane oneway road")
		return
	var w2: float = g.roads[two_way]["w"]
	if absf(g.lane_offset(two_way, 0) - clampf(w2 / 4.0, 1.0, 1.75)) > 1e-6:
		_fail("two-way lane_offset wrong")
		return
	var w1: float = g.roads[one_way]["w"]
	var lanes1: int = g.roads[one_way]["lanes"]
	if g.lane_offset(one_way, 0) <= g.lane_offset(one_way, lanes1 - 1) \
			or absf(g.lane_offset(one_way, 0) - (w1 / 2.0 - w1 * 0.5 / float(lanes1))) > 1e-6:
		_fail("oneway lane_offset wrong (lane 0 must be rightmost)")
		return
	# lateral offset lies to the RIGHT of travel and flips with dir
	var mid := g.road_length(two_way) * 0.5
	var c := g.road_point(two_way, 1, 0.0, mid)
	var tan := g.road_tangent(two_way, 1, mid)
	var right := Vector3(-tan.z, 0.0, tan.x)
	if (g.road_point(two_way, 1, 1.5, mid) - c).dot(right) < 1.4:
		_fail("road_point lateral offset is not to the right of travel")
		return
	if (g.road_point(two_way, -1, 1.5, g.road_length(two_way) - mid) - c).dot(right) > -1.4:
		_fail("road_point lateral offset does not flip for dir=-1")
		return
	# next_stop: first stop ahead at t=0 in both directions; nothing past the end
	var stop_road := -1
	for i in g.roads.size():
		if not (g.roads[i]["stops"] as Array).is_empty():
			stop_road = i
			break
	if stop_road < 0:
		_fail("no road carries a stop node")
		return
	var stops: Array = g.roads[stop_road]["stops"]
	var st := g.next_stop(stop_road, 1, 0.0)
	if st.is_empty() or absf(st[0] - stops[0][0]) > 1e-4 or st[1] != stops[0][1]:
		_fail("next_stop forward wrong: %s" % str(st))
		return
	var last_stop: Array = stops[stops.size() - 1]
	var st_b := g.next_stop(stop_road, -1, 0.0)
	if st_b.is_empty() or absf(st_b[0] - (g.road_length(stop_road) - last_stop[0])) > 1e-4 or st_b[1] != last_stop[1]:
		_fail("next_stop reverse wrong: %s" % str(st_b))
		return
	if not g.next_stop(stop_road, 1, g.road_length(stop_road) + 5.0).is_empty():
		_fail("next_stop reports a stop behind the agent")
		return
	# signals: some node has two non-empty groups (a real cross street), and the
	# two groups are never green together over a 16 s sweep
	var probe := -1
	for node in g.signals:
		var heads: Array = g.exits(node, -1, 0, true)
		var g0 := 0
		var g1 := 0
		for e in heads:
			if g.signal_group(node, g.road_tangent(e[0], e[1], e[2])) == 0: g0 += 1
			else: g1 += 1
		if g0 > 0 and g1 > 0:
			probe = node
			break
	if probe < 0:
		_fail("no signal node with two approach groups")
		return
	var a_green := false; var a_red := false; var b_green := false; var b_red := false
	var tt := 0.0
	while tt < NavGraph.SIGNAL_PERIOD:
		var ga := g.signal_green(probe, 0, tt)
		var gb := g.signal_green(probe, 1, tt)
		if ga and gb:
			_fail("both signal groups green at t=%.1f" % tt)
			return
		a_green = a_green or ga; a_red = a_red or not ga
		b_green = b_green or gb; b_red = b_red or not gb
		tt += 0.5
	if not (a_green and a_red and b_green and b_red):
		_fail("signal phases do not alternate")
		return
	print("NAV GRAPH OK: nodes=%d roads=%d walks=%d signals=%d" % [g.nodes.size(), g.roads.size(), g.walks.size(), g.signals.size()])
	quit(0)
