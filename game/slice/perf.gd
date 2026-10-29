extends SceneTree
# Frame-time probe: hero pose, toggles one feature at a time, prints avg ms.
func _avg_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n

func _init() -> void:
	var root: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in 30:
		await process_frame
	root.call("set_view", Vector3(0.6, 1.7, 30.0), Vector3(0.0, 4.5, -60.0))
	for i in 120:
		await process_frame
	var env: Environment = root.get("env")
	var lights: Array = root.get("_lamp_lights")
	for q in [1, 0, 2]:
		root.call("set_quality", q)
		for i in 30:
			await process_frame
		print("PERF quality=", q, " ", await _avg_ms(150))
	quit()
