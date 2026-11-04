extends SceneTree
# Frame-time probe: hero pose, each quality preset, then with traffic parked.
#   tools/godot/godot_console.exe --path game --resolution 1920x1080 --script res://slice/perf.gd
# (vsync caps the floor at ~16.7 ms on a 60 Hz panel)
func _avg_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n

func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var root: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in 30:
		await process_frame
	(root.get("game") as Node).call("start_free")
	root.call("set_view", Vector3(0.6, 1.7, 30.0), Vector3(0.0, 4.5, -60.0))
	for i in 120:
		await process_frame
	for q in [1, 0, 2]:
		root.call("set_quality", q)
		for i in 30:
			await process_frame
		print("PERF quality=", q, " ", await _avg_ms(150))
	root.call("set_quality", 1)
	root.call("set_fly", false)
	for i in 60:
		await process_frame
	print("PERF on-foot high ", await _avg_ms(150))
	(root.get("traffic") as Node).call("set_enabled", false)
	for i in 30:
		await process_frame
	print("PERF on-foot high, no traffic ", await _avg_ms(150))
	quit()
