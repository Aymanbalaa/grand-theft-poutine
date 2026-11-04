extends SceneTree
# Walking bot: drives the player with real input (no teleports) across the
# quarter, including stepping up sidewalk ends at intersections.
#   tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/walk_test.gd
const ROUTE := [
	Vector3(4.6, 0.15, 10.0),     # onto the east sidewalk of Saint-Paul (kerb ramp)
	Vector3(4.6, 0.0, -52.0),     # down the sidewalk end into the crossroads
	Vector3(4.6, 0.15, -64.0),    # UP the next sidewalk end (south block)
	Vector3(4.6, 0.0, -52.0),
	Vector3(30.0, 0.15, -47.2),   # along Saint-Vincent's north sidewalk
	Vector3(2.0, 0.0, -56.0),     # back to the crossroads
	Vector3(0.0, 0.0, -117.0),    # down the crown of Saint-Paul (parked car on the right) to la Commune
	Vector3(-30.0, 0.15, -113.6), # up onto the Commune north sidewalk from its end
]

func _init() -> void:
	var scene: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	for i in 5:
		await process_frame
	scene.get("game").call("start_free")
	scene.get("traffic").call("set_enabled", false)
	var player: Node3D = scene.get("player")
	player.global_position = Vector3(1.2, 0.2, 24.0)
	var fails := 0
	for wp in ROUTE:
		var ok := false
		for f in 60 * 40:
			var d: Vector3 = wp - player.global_position
			d.y = 0
			if d.length() < 0.8:
				ok = true
				break
			player.set("cam_yaw", atan2(-d.x, -d.z))
			Input.action_press("ui_up")
			await process_frame
		Input.action_release("ui_up")
		var y := player.global_position.y
		var y_ok: bool = abs(y - wp.y) < 0.08
		print(("PASS " if ok and y_ok else "FAIL ") + "reach %s (at %s, y=%.2f)" % [wp, player.global_position.snapped(Vector3.ONE * 0.1), y])
		if not (ok and y_ok):
			fails += 1
	print("WALK OK" if fails == 0 else "WALK FAIL: %d" % fails)
	quit(1 if fails else 0)
