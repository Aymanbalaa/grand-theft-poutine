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
	{"name": "driving_day",   "car": Vector3(-60, 0, -80),  "drive": true, "time": 0.4},
	{"name": "driving_night", "car": Vector3(30, 0, 40),  "time": 0.95},
	{"name": "uphill_facade", "pos": Vector3(-1500, 34, -560), "look": Vector3(-1530, 36, -625), "time": 0.4},
	{"name": "credits", "pos": Vector3(0, 600, 400), "look": Vector3(0, 0, 0), "time": 0.4, "credits": true},
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
			for i in 900:  # fall onto collision: poll, never fixed-frame waits
				await process_frame
				if i > 5 and player.call("is_on_floor"):
					break
			for i in 10:  # settle animation + HUD
				await process_frame
		elif pose.has("car"):
			var cars := root.get_node("Cars")
			var best: Node3D = null
			var best_d := 1e9
			for c in cars.get_children():
				var d: float = (c as Node3D).global_position.distance_to(pose["car"])
				if d < best_d:
					best_d = d
					best = c
			root.call("_enter_car", best)
			for i in 900:  # car falls 0.4 m onto road collision: poll, never fixed waits
				await process_frame
				if i > 5 and best.call("is_on_floor"):
					break
			if pose.get("drive", false):
				Input.action_press("move_forward")
				for i in 45:
					await process_frame
				Input.action_release("move_forward")
			for i in 10:  # settle camera + HUD
				await process_frame
		else:
			fly_cam.current = true
			fly_cam.position = pose["pos"]
			fly_cam.look_at(pose["look"])
			for i in 15:
				await process_frame
		var credits := root.get_node_or_null("Credits") as CanvasLayer
		if credits != null:
			credits.visible = pose.get("credits", false)
			await process_frame
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://shot_%s.png" % pose["name"])
		print("saved shot_%s.png" % pose["name"])
		if pose.has("car"):
			root.call("_exit_car")
			await process_frame
	quit(0)
