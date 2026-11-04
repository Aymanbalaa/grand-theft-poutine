extends SceneTree
# Movement-feel gate: drives the courier with real input events and measures
# jog/sprint speeds, stamina, jump height, dive burst and reversal time.
#   tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/move_test.gd

var player: CharacterBody3D
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func hspeed() -> float:
	var v: Vector3 = player.velocity
	return Vector2(v.x, v.z).length()

func _init() -> void:
	var scene: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	await frames(5)
	scene.get("game").call("start_free")
	player = scene.get("player")
	# a long clear run down the crown of Saint-Paul, heading south (-Z)
	player.global_position = Vector3(0.0, 0.2, 30.0)
	player.set("cam_yaw", 0.0)
	await frames(10)

	Input.action_press("ui_up")
	await frames(30)
	var jog := hspeed()
	check(jog > 4.0 and jog < 4.6, "jog speed %.2f m/s" % jog)
	key(KEY_SHIFT, true)
	await frames(30)
	var spr := hspeed()
	check(spr > 6.6, "sprint speed %.2f m/s" % spr)
	var st: float = player.get("stamina")
	check(st < 0.95, "sprinting drains stamina (%.2f)" % st)
	# stop before the crossroads, turn around and keep sprinting north to empty the bar
	Input.action_release("ui_up")
	player.global_position = Vector3(0.0, 0.2, -100.0)
	player.set("velocity", Vector3.ZERO)
	player.set("cam_yaw", PI)
	Input.action_press("ui_up")
	await frames(60 * 5)
	check(bool(player.get("_winded")), "stamina runs out (winded)")
	await frames(10)
	check(hspeed() < 4.8, "winded courier drops to a jog (%.2f)" % hspeed())
	key(KEY_SHIFT, false)
	Input.action_release("ui_up")
	await frames(60 * 3)
	check(float(player.get("stamina")) > 0.6, "stamina regenerates (%.2f)" % float(player.get("stamina")))

	# jump from rest
	player.global_position = Vector3(0.0, 0.2, 0.0)
	player.set("velocity", Vector3.ZERO)
	await frames(20)
	var y0: float = player.global_position.y
	key(KEY_SPACE, true)
	await frames(1)
	key(KEY_SPACE, false)
	var top := y0
	var air := 0
	for i in 90:
		await physics_frame
		top = maxf(top, player.global_position.y)
		if not player.is_on_floor():
			air += 1
	check(top - y0 > 0.75 and top - y0 < 1.1, "jump apex %.2f m" % (top - y0))
	check(air > 20 and air < 50, "air time %d frames" % air)
	check(player.is_on_floor(), "lands again")

	# dive burst
	player.set("cam_yaw", 0.0)
	Input.action_press("ui_up")
	await frames(30)
	key(KEY_C, true)
	await frames(1)
	key(KEY_C, false)
	var peak := 0.0
	var rolled := false
	for i in 20:
		await physics_frame
		peak = maxf(peak, hspeed())
		rolled = rolled or bool(player.call("rolling"))
	check(rolled and peak > 7.5, "dive burst %.2f m/s" % peak)
	await frames(40)

	# reversal: running south, then pull back
	player.global_position = Vector3(0.0, 0.2, 30.0)
	player.set("velocity", Vector3.ZERO)
	await frames(40)
	Input.action_release("ui_up")
	Input.action_press("ui_down")
	var t := 0
	for i in 60:
		await physics_frame
		t += 1
		if player.velocity.z > 3.0:
			break
	check(t < 24, "reverses to a 3 m/s jog in %d frames" % t)
	Input.action_release("ui_down")
	await frames(30)
	check(hspeed() < 0.2, "stops cleanly (%.2f)" % hspeed())
	print("MOVE OK" if fails == 0 else "MOVE FAIL: %d" % fails)
	quit(1 if fails else 0)
