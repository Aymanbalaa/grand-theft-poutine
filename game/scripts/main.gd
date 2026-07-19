extends Node3D
# Root wiring: spawn player + parked cars from metadata, own the enter/exit
# state machine, the fly-cam toggle and the drive HUD (prompt + speedometer).

const CAR_SCENE := preload("res://scenes/car.tscn")
const ENTER_RADIUS := 3.5

@onready var _player := $Player as Player
@onready var _fly_cam := $Camera as Camera3D
@onready var _cars := $Cars as Node3D
@onready var _prompt := $HUD/PromptLabel as Label
@onready var _speed_label := $HUD/SpeedLabel as Label

var _driving: Car = null

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

func _process(_delta: float) -> void:
	if _driving != null:
		_speed_label.text = "%d km/h" % absi(roundi(_driving.speed * 3.6))
		return
	_prompt.visible = _player.visible and _nearest_car() != null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter_exit"):
		if _driving != null:
			_exit_car()
		else:
			var car := _nearest_car()
			if car != null:
				_enter_car(car)
	elif event.is_action_pressed("toggle_fly"):
		var game_cam := _active_game_camera()
		if game_cam.current:
			_fly_cam.current = true
		else:
			game_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _active_game_camera() -> Camera3D:
	if _driving != null:
		return _driving.get_node("CamPivot/SpringArm3D/CarCamera") as Camera3D
	return _player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D

func _nearest_car() -> Car:
	var best: Car = null
	var best_d := ENTER_RADIUS
	for c in _cars.get_children():
		var d := (c as Node3D).global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = c as Car
	return best

func _enter_car(car: Car) -> void:
	if _driving != null:
		return
	_driving = car
	_player.visible = false
	_player.set_physics_process(false)
	(_player.get_node("CollisionShape3D") as CollisionShape3D).set_deferred("disabled", true)
	car.start_driving()
	(car.get_node("CamPivot/SpringArm3D/CarCamera") as Camera3D).current = true
	_prompt.visible = false
	_speed_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_car() -> void:
	if _driving == null:
		return
	var car := _driving
	_driving = null
	car.stop_driving()
	_player.global_position = car.global_position \
			- car.global_transform.basis.x * 2.2 + Vector3(0, 0.5, 0)
	_player.velocity = Vector3.ZERO
	_player.visible = true
	_player.set_physics_process(true)
	(_player.get_node("CollisionShape3D") as CollisionShape3D).set_deferred("disabled", false)
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true
	_speed_label.visible = false
