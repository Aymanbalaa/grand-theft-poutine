extends SceneTree
# Slice screenshot gate (needs a GPU, not headless):
#   tools/godot/godot.exe --path game --resolution 1920x1080 --script res://slice/shots.gd
# Writes docs/screenshots/slice_<name>.png for each pose.

const POSES := [
	{"name": "onfoot", "player": Vector3(0.6, 0.2, 14.0), "yaw": 0.25, "pitch": -0.12, "walk": true, "mood": 0},
	{"name": "hero", "pos": Vector3(0.6, 1.7, 30.0), "look": Vector3(0.0, 4.5, -60.0), "mood": 0},
	{"name": "cafe", "pos": Vector3(-2.2, 1.65, 8.0), "look": Vector3(1.0, 3.5, -40.0), "mood": 0},
	{"name": "storefront", "pos": Vector3(-1.5, 1.6, -18.0), "look": Vector3(5.6, 2.8, -28.0), "mood": 0},
	{"name": "dome", "pos": Vector3(0.0, 1.8, -70.0), "look": Vector3(0.0, 15.0, -135.0), "mood": 0},
	{"name": "puddles", "pos": Vector3(1.0, 0.55, -30.0), "look": Vector3(-0.5, 1.8, -70.0), "mood": 0},
	{"name": "night", "pos": Vector3(0.6, 1.7, 30.0), "look": Vector3(0.0, 4.5, -60.0), "mood": 1},
	{"name": "roofs", "pos": Vector3(3.0, 22.0, 40.0), "look": Vector3(0.0, 8.0, -60.0), "mood": 0},
	{"name": "market", "pos": Vector3(6.0, 2.0, -100.0), "look": Vector3(0.0, 8.0, -124.0), "mood": 0},
	{"name": "vincent", "pos": Vector3(8.0, 1.7, -51.0), "look": Vector3(90.0, 4.0, -53.0), "mood": 0},
	{"name": "commune", "pos": Vector3(-30.0, 1.7, -117.0), "look": Vector3(10.0, 6.0, -122.0), "mood": 0},
	{"name": "corner", "pos": Vector3(-3.0, 7.0, -36.0), "look": Vector3(4.0, 2.0, -60.0), "mood": 0},
	{"name": "day", "pos": Vector3(0.6, 1.7, 30.0), "look": Vector3(0.0, 4.5, -60.0), "mood": 2},
]

func _init() -> void:
	var only := OS.get_environment("SLICE_SHOT")
	var root: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 30:
		await process_frame
	(root.get("game") as Node).call("start_free")
	root.call("show_hud", false)
	for pose in POSES:
		if only != "" and not only.split(",").has(pose["name"]):
			continue
		root.call("_set_mood", pose["mood"])
		if pose.has("player"):
			root.call("set_fly", false)
			var pl: Node3D = root.get("player")
			pl.global_position = pose["player"]
			pl.set("cam_yaw", pose["yaw"])
			pl.set("cam_pitch", pose["pitch"])
			if pose.get("walk", false):
				Input.action_press("ui_up")
		else:
			root.call("set_view", pose["pos"], pose["look"])
		for i in 200:  # SDFGI / TAA / volumetric fog convergence
			await process_frame
		Input.action_release("ui_up")
		print("FPS ", pose["name"], " ", Engine.get_frames_per_second(), " ms=", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		var img := get_root().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/slice_%s.png" % pose["name"])
		img.save_png(path)
		print("SHOT ", pose["name"])
	quit()
