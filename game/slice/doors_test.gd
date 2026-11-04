extends SceneTree
# Reachability gate: for every registered door, start on the street centre
# line opposite it and walk up to it with real input (hopping if blocked).
# Every address must be deliverable (within the game's REACH).
#   tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/doors_test.gd

const REACH := 2.4

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _init() -> void:
	var scene: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	for i in 5:
		await physics_frame
	scene.get("game").call("start_free")
	scene.get("traffic").call("set_enabled", false)
	var player: CharacterBody3D = scene.get("player")
	var game: Node = scene.get("game")
	var doors: Array = scene.get("doors")
	var fails := 0
	for d in doors:
		var target: Vector3 = d["pos"]
		# street centre line opposite the door (nearest point of the street graph)
		var nodes: Dictionary = game.get("NODES")
		var edges: Array = game.get("EDGES")
		var best := Vector3.ZERO
		var bd := INF
		for e in edges:
			var a: Vector3 = nodes[e[0]]
			var b: Vector3 = nodes[e[1]]
			var q: Vector3 = game.call("_project", Vector3(target.x, 0, target.z), a, b)
			if q.distance_to(Vector3(target.x, 0, target.z)) < bd:
				bd = q.distance_to(Vector3(target.x, 0, target.z))
				best = q
		player.global_position = best + Vector3.UP * 0.2
		player.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		var ok := false
		var stuck := 0.0
		var last := player.global_position
		var side := 1.0
		var unstick := 0.0
		for f in 60 * 14:
			var rel: Vector3 = target - player.global_position
			if Vector2(rel.x, rel.z).length() < REACH * 0.8 and abs(rel.y) < 1.5:
				ok = true
				break
			var dir := Vector3(rel.x, 0, rel.z)
			if unstick > 0.0:
				unstick -= 1.0 / 60.0
				dir = dir.rotated(Vector3.UP, side * 1.3)
			player.set("cam_yaw", atan2(-dir.x, -dir.z))
			Input.action_press("ui_up")
			await physics_frame
			var moved := player.global_position.distance_to(last)
			last = player.global_position
			stuck = stuck + 1.0 / 60.0 if moved < 0.015 else 0.0
			if stuck > 0.35:
				_key(KEY_SPACE, true)
				_key(KEY_SPACE, false)
				unstick = 0.6
				side = -side
				stuck = 0.0
		Input.action_release("ui_up")
		if not ok:
			fails += 1
			print("FAIL door %s at %s (got to %s)" % [d["name"], target.snapped(Vector3.ONE * 0.1), player.global_position.snapped(Vector3.ONE * 0.1)])
	print("checked %d doors" % doors.size())
	print("DOORS OK" if fails == 0 else "DOORS FAIL: %d" % fails)
	quit(1 if fails else 0)
