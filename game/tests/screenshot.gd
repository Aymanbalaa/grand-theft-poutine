extends SceneTree
# Capture screenshots from fixed camera poses. NOT headless — needs a GPU.
# Run: tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd
# Poses with "player" teleport the Player there and shoot through its camera.

const POSES := [
	{"name": "overview",  "pos": Vector3(0, 600, 400),      "look": Vector3(0, 0, 0),          "time": 0.4},
	{"name": "street",    "pos": Vector3(50, 40, 100),      "look": Vector3(0, 10, -200),      "time": 0.4},
	{"name": "oldport",   "pos": Vector3(800, 120, 900),    "look": Vector3(400, 0, 400),      "time": 0.33},
	{"name": "mountain",  "pos": Vector3(-1200, 250, -200), "look": Vector3(-2200, 150, -250), "time": 0.4},
	{"name": "biosphere", "pos": Vector3(1250, 120, -800),  "look": Vector3(1600, 30, -1117),  "time": 0.4},
	{"name": "dusk",      "pos": Vector3(600, 200, 700),    "look": Vector3(0, 60, 0),         "time": 0.285},
	{"name": "night",     "pos": Vector3(-100, 80, -150),   "look": Vector3(-450, 90, -550),   "time": 0.95},
	{"name": "onfoot_day",   "player": Vector3(-273, 40, -60), "time": 0.4},
	{"name": "onfoot_night", "player": Vector3(30, 40, 40),    "time": 0.95},
]

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	var fly_cam := root.get_node("Camera") as Camera3D
	fly_cam.set_script(null)  # disable fly controls
	await process_frame
	var player := root.get_node_or_null("Player")
	var player_cam: Camera3D = null
	if player != null:
		player_cam = player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D
	for pose in POSES:
		var sun := root.get_node_or_null("Sun")
		if sun != null:
			sun.set("time_of_day", pose["time"])
		if pose.has("player") and player != null:
			(player as Node3D).global_position = pose["player"]
			player.set("velocity", Vector3.ZERO)
			player_cam.current = true
			for i in 60:  # fall onto collision + settle + HUD update
				await process_frame
		else:
			fly_cam.current = true
			fly_cam.position = pose["pos"]
			fly_cam.look_at(pose["look"])
			for i in 15:
				await process_frame
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://shot_%s.png" % pose["name"])
		print("saved shot_%s.png" % pose["name"])
	quit(0)
