extends SceneTree
# Capture screenshots from fixed camera poses. NOT headless — needs a GPU.
# Run: tools/godot/godot.exe --path game --script res://tests/screenshot.gd

const POSES := [
	{"name": "overview", "pos": Vector3(0, 600, 400), "look": Vector3(0, 0, 0)},
	{"name": "street",   "pos": Vector3(50, 40, 100),  "look": Vector3(0, 10, -200)},
	{"name": "oldport",  "pos": Vector3(800, 120, 900), "look": Vector3(400, 0, 400)},
]

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	var cam := root.get_node("Camera") as Camera3D
	cam.set_script(null)  # disable fly controls
	await process_frame
	for pose in POSES:
		cam.position = pose["pos"]
		cam.look_at(pose["look"])
		for i in 15:
			await process_frame
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://shot_%s.png" % pose["name"])
		print("saved shot_%s.png" % pose["name"])
	quit(0)
