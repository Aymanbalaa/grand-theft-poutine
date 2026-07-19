extends Node3D
# Root wiring: spawn the player from metadata, own the fly/player camera toggle.

const CAR_SCENE := preload("res://scenes/car.tscn")

@onready var _player := $Player as Player
@onready var _fly_cam := $Camera as Camera3D
@onready var _cars := $Cars as Node3D

func _ready() -> void:
	var sx := 0.0
	var sz := 0.0
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			if meta.has("spawn"):
				sx = meta["spawn"]["x"]
				sz = meta["spawn"]["z"]
			var i := 0
			for cs in meta.get("car_spawns", []):
				var car := CAR_SCENE.instantiate() as Car
				(car.get_node("Visual") as Node3D).set("color_index", i)
				_cars.add_child(car)
				car.global_position = Vector3(cs["x"], cs["y"] + 0.4, cs["z"])
				car.rotation.y = cs["yaw"]
				car.park()
				i += 1
	_player.global_position = Vector3(sx, 80.0, sz)
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fly"):
		var pc := _player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D
		if pc.current:
			_fly_cam.current = true
		else:
			pc.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
