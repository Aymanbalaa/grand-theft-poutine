extends SceneTree
# Headless smoke test: main scene loads, tiles instantiate.
# Run: tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd

const _player_preload = preload("res://scripts/player.gd")
const _car_preload = preload("res://scripts/car.gd")

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("FAIL: main.tscn did not load")
		quit(1)
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame
	var loader := root.get_node("TileLoader") as TileLoader
	if loader == null or loader.loaded_tile_count() <= 100:
		var n := -1 if loader == null else loader.loaded_tile_count()
		push_error("FAIL: expected >100 tiles, got %d" % n)
		quit(1)
		return
	var cam := root.get_node_or_null("Camera") as Camera3D
	if cam == null:
		push_error("FAIL: Camera3D node named 'Camera' missing from main scene")
		quit(1)
		return
	var player := root.get_node_or_null("Player") as Player
	if player == null:
		push_error("FAIL: Player missing from main scene")
		quit(1)
		return
	if not InputMap.has_action("move_forward") or not InputMap.has_action("toggle_fly"):
		push_error("FAIL: player input actions not registered")
		quit(1)
		return
	var pcam := player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D
	if pcam == null or not pcam.current:
		push_error("FAIL: player camera missing or not current")
		quit(1)
		return
	print("PLAYER OK")
	var landed := false
	for i in 900:
		await process_frame
		if player.is_on_floor():
			landed = true
			break
	if not landed or player.global_position.y < -5.0:
		push_error("FAIL: player did not land (y=%f, vy=%f)"
				% [player.global_position.y, player.velocity.y])
		quit(1)
		return
	print("LANDED OK y=%.1f" % player.global_position.y)
	var car_scene: PackedScene = load("res://scenes/car.tscn")
	if car_scene == null:
		push_error("FAIL: car.tscn did not load")
		quit(1)
		return
	var test_car := car_scene.instantiate() as Car
	get_root().add_child(test_car)
	test_car.park()
	await process_frame
	if not InputMap.has_action("enter_exit"):
		push_error("FAIL: enter_exit action not registered")
		quit(1)
		return
	await process_frame
	var vis := test_car.get_node("Visual") as Node3D
	if vis.get_child_count() == 0:
		push_error("FAIL: car visual is empty")
		quit(1)
		return
	print("CARVIS %s" % ("model" if vis.get("_model_mode") else "procedural"))
	test_car.queue_free()
	print("CAR OK")
	var cars := root.get_node_or_null("Cars")
	if cars == null or cars.get_child_count() < 20:
		var nc := -1 if cars == null else cars.get_child_count()
		push_error("FAIL: expected >=20 parked cars, got %d" % nc)
		quit(1)
		return
	print("CARS OK: %d" % cars.get_child_count())
	var pool := root.get_node_or_null("LightPool")
	if pool == null or pool.call("lamp_count") < 400 or pool.get_child_count() != 24:
		var lc: int = -1 if pool == null else pool.call("lamp_count")
		push_error("FAIL: light pool missing or lamps not loaded (lamps=%d)" % lc)
		quit(1)
		return
	print("LIGHTS OK: %d lamps" % pool.call("lamp_count"))
	var drive_car := cars.get_child(0) as Car
	player.global_position = drive_car.global_position + Vector3(2.5, 1.0, 0)
	await physics_frame
	root.call("_enter_car", drive_car)
	await process_frame
	var car_cam := drive_car.get_node("CamPivot/SpringArm3D/CarCamera") as Camera3D
	if not car_cam.current or player.visible:
		push_error("FAIL: entering car did not swap camera / hide player")
		quit(1)
		return
	print("ENTER OK")
	var start_pos := drive_car.global_position
	Input.action_press("move_forward")
	var moving := false
	for i in 900:
		await process_frame
		if drive_car.speed > 3.0 and start_pos.distance_to(drive_car.global_position) >= 1.0:
			moving = true
			break
	Input.action_release("move_forward")
	if not moving:
		push_error("FAIL: car did not drive (speed=%f, dist=%f)"
				% [drive_car.speed, start_pos.distance_to(drive_car.global_position)])
		quit(1)
		return
	print("DRIVE OK v=%.1f" % drive_car.speed)
	root.call("_exit_car")
	await process_frame
	var pcam2 := player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D
	if not player.visible or not pcam2.current:
		push_error("FAIL: exiting car did not restore player")
		quit(1)
		return
	print("EXIT OK")
	print("SMOKE OK: %d tiles" % loader.loaded_tile_count())
	quit(0)
