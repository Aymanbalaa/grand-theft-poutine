extends SceneTree
# Gameplay screenshots with the HUD (GPU, not headless):
#   SLICE_SAVE=user://shots_save.json tools/godot/godot_console.exe --path game --resolution 1920x1080 --script res://slice/game_shots.gd
var scene: Node
var game: Node
var player: Node3D

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/game_%s.png" % name))
	print("SHOT ", name)

# Stand on the same sidewalk, `dist` metres along the facade from the door,
# looking at it (orders are random, so never path straight through buildings).
func face_door(door: Dictionary, dist: float) -> void:
	var out: Vector3 = door["outward"]
	var u := Vector3.UP.cross(out)
	var to: Vector3 = door["pos"]
	var from := to + u * dist + out * 0.6
	player.global_position = from + Vector3.UP * 0.1
	_aim(from, to)

func face(from: Vector3, to: Vector3, dist: float) -> void:
	var d := (to - from)
	d.y = 0
	d = d.normalized()
	player.global_position = to - d * dist + Vector3.UP * 0.1
	_aim(to - d * dist, to)

func _aim(from: Vector3, to: Vector3) -> void:
	var d := (to - from)
	d.y = 0
	d = d.normalized()
	player.set("velocity", Vector3.ZERO)
	player.set("cam_yaw", atan2(-d.x, -d.z))
	player.set("cam_pitch", -0.12)
	(player.get("person") as Node3D).rotation.y = atan2(d.x, d.z)
	player.set("_facing_yaw", atan2(d.x, d.z))

func _init() -> void:
	if FileAccess.file_exists("user://shots_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shots_save.json"))
	scene = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	await frames(200)
	game = scene.get("game")
	player = scene.get("player")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await shot("title")
	game.call("start_shift")
	for i in 400:
		await process_frame
		if (game.get("offers") as Array).size() == 2:
			break
	var offers: Array = game.get("offers")
	face_door(offers[0]["shop"], 13.0)
	await frames(160)
	await shot("pickup")
	player.global_position = offers[0]["shop"]["pos"] + Vector3.UP * 0.1
	await frames(5)
	var order: Dictionary = game.get("order")
	# turn around so the drop-off is off-screen: shows the edge pointer
	var hp: Vector3 = order["home"]["pos"]
	var away := (player.global_position - hp)
	away.y = 0
	player.set("cam_yaw", atan2(-away.normalized().x, -away.normalized().z) + 0.6)
	order["t"] = order["limit"] * 0.45
	await frames(140)
	await shot("carry")
	face_door(order["home"], 10.0)
	await frames(120)
	await shot("dropoff")
	player.global_position = hp + Vector3.UP * 0.1
	await frames(14)
	await shot("delivered")
	# pickpocket chase
	var peds: Node = scene.get("peds")
	player.global_position = Vector3(0.0, 0.2, -10.0)
	game.set("_thief_t", 0.0)
	for i in 600:
		await process_frame
		if not (peds.get("thief") as Dictionary).is_empty():
			break
	await frames(50)
	var tp: Vector3 = peds.call("thief_pos")
	face(player.global_position, tp, 8.0)
	await frames(8)
	await shot("thief")
	game.set("shift_t", 0.02)
	await frames(60)
	await shot("summary")
	quit()
