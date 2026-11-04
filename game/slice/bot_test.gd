extends SceneTree
# Shift bot: plays a whole shift with real input only (no teleports), picking
# offers, following the street-graph route, sprinting on stamina, hopping
# when stuck. Proves every door it is sent to is reachable on foot with
# traffic and pedestrians live, and gives a score for medal calibration.
#   SLICE_SAVE=user://bot_save.json tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/bot_test.gd
# Optional: BOT_SHIFT=<seconds> to shorten the shift.

var scene: Node
var game: Node
var player: CharacterBody3D
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var unstick := 0.0
var side := 1.0
var target_name := ""
var target_t := 0.0
var failures: Array = []

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _init() -> void:
	if FileAccess.file_exists("user://bot_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bot_save.json"))
	scene = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	for i in 5:
		await physics_frame
	game = scene.get("game")
	player = scene.get("player")
	game.call("start_shift")
	var shift := float(OS.get_environment("BOT_SHIFT")) if OS.get_environment("BOT_SHIFT") != "" else 360.0
	game.set("shift_t", shift)
	var frames := 0
	while game.get("state") == "shift":
		await physics_frame
		frames += 1
		_drive(1.0 / 60.0)
	Input.action_release("ui_up")
	_key(KEY_SHIFT, false)
	var st: Dictionary = game.get("stats")
	var cash: float = game.get("cash")
	print("BOT shift %.0f s: %d deliveries (%d on time, %d late), %.2f $, grazes %d, damage %d, medal %s" % [
		shift, st["deliveries"], st["on_time"], st["late"], cash, st["grazes"], st["damage"],
		(st.get("medal", []) as Array)[1] if not (st.get("medal", []) as Array).is_empty() else "-"])
	for f in failures:
		print("UNREACHED ", f)
	var ok: bool = st["deliveries"] >= int(shift / 40.0) and failures.is_empty()
	print("BOT OK" if ok else "BOT FAIL")
	quit(0 if ok else 1)

func _drive(dt: float) -> void:
	var order: Dictionary = game.get("order")
	var offers: Array = game.get("offers")
	var target := Vector3.INF
	var name := ""
	if not order.is_empty():
		target = order["home"]["pos"]
		name = "drop %s" % order["home"]["name"]
	elif not offers.is_empty():
		# best pay per metre of total walk
		var best := -1.0
		for o in offers:
			var d: float = game.call("route_len", player.global_position, o["shop"]["pos"]) + o["route"]
			var v: float = o["pay_est"] / maxf(d, 1.0)
			if v > best:
				best = v
				target = o["shop"]["pos"]
				name = "pick %s" % o["shop"]["name"]
	if target == Vector3.INF:
		Input.action_release("ui_up")
		return
	if name != target_name:
		target_name = name
		target_t = 0.0
	target_t += dt
	if target_t > 75.0:
		failures.append("%s at %s (stuck near %s)" % [name, target.snapped(Vector3.ONE * 0.1), player.global_position.snapped(Vector3.ONE * 0.1)])
		target_t = -INF   # report once
	var pts: PackedVector3Array = game.call("route_points", player.global_position, target)
	var wp: Vector3 = pts[1] if pts.size() > 1 else target
	var flat := Vector3(player.global_position.x, 0, player.global_position.z)
	if flat.distance_to(Vector3(wp.x, 0, wp.z)) < 1.6 and pts.size() > 2:
		wp = pts[2]
	var d := Vector3(wp.x, 0, wp.z) - flat
	if unstick > 0.0:
		unstick -= dt
		d = d.rotated(Vector3.UP, side * 1.2)
	player.set("cam_yaw", atan2(-d.x, -d.z))
	Input.action_press("ui_up")
	var stamina: float = player.get("stamina")
	var far := d.length() > 10.0
	_key(KEY_SHIFT, far and stamina > 0.25 and not bool(player.get("_winded")))
	# stuck: hop, then sidestep for a moment
	var moved := player.global_position.distance_to(last_pos)
	last_pos = player.global_position
	stuck_t = stuck_t + dt if moved < 0.02 else maxf(0.0, stuck_t - dt)
	if stuck_t > 0.4:
		_key(KEY_SPACE, true)
		_key(KEY_SPACE, false)
		unstick = 0.7
		side = -side
		stuck_t = 0.0
