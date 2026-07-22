extends Node3D
# Root wiring: spawn player + parked cars from metadata, own the enter/exit
# state machine, the fly-cam toggle and the drive HUD (prompt + speedometer).

const CAR_SCENE := preload("res://scenes/car.tscn")
const ENTER_RADIUS := 3.5
const KILL_Y := -50.0

@onready var _player := $Player as Player
@onready var _fly_cam := $Camera as Camera3D
@onready var _cars := $Cars as Node3D
@onready var _prompt := $HUD/PromptLabel as Label
@onready var _speed_label := $HUD/SpeedLabel as Label

var _driving: Car = null
var _spawn := Vector3.ZERO

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
				car.global_position = Vector3(cs["x"], cs["y"] + 0.05, cs["z"])
				car.rotation.y = cs["yaw"]
				car.park()
				i += 1
	_spawn = Vector3(sx, 80.0, sz)
	_player.global_position = _spawn
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var amb := get_node_or_null("Ambient") as AudioStreamPlayer
	if amb != null:
		var s := load("res://assets/audio/ambient.wav") as AudioStreamWAV
		if s != null:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = s.data.size() / 2
			amb.stream = s
			amb.play()

func _process(_delta: float) -> void:
	if _driving != null:
		if _driving.is_physics_processing() and _driving.global_position.y < KILL_Y:
			_driving.speed = 0.0
			_driving.velocity = Vector3.ZERO
			_driving.global_position = _spawn
		_speed_label.text = "%d km/h" % absi(roundi(_driving.speed * 3.6))
		return
	if _player.is_physics_processing() and _player.global_position.y < KILL_Y:
		_player.velocity = Vector3.ZERO
		_player.global_position = _spawn
	_prompt.visible = _player.visible and not _fly_cam.current and _nearest_car() != null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter_exit"):
		if _fly_cam.current:
			return  # E doubles as fly-cam ascend; never enter/exit from debug cam
		if _driving != null:
			_exit_car()
		else:
			var car := _nearest_car()
			if car != null:
				_enter_car(car)
	elif event.is_action_pressed("toggle_fly"):
		_set_flycam(_active_game_camera().current)

func _set_flycam(on: bool) -> void:
	if on:
		_fly_cam.current = true
	else:
		_active_game_camera().current = true
	if _driving != null:
		_driving.set_physics_process(not on)
	else:
		_player.set_physics_process(not on)
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
