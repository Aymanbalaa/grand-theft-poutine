extends Node3D
# Chase cam: this pivot is a child of the Car, so it inherits the car's yaw.
# Mouse adds a temporary look-around offset that eases back behind the car
# while moving. Esc releases the mouse, click recaptures.

@export var sensitivity := 0.003

var _offset_yaw := 0.0
var _pitch := -0.18
@onready var _car := get_parent() as Car
@onready var _cam := $SpringArm3D/CarCamera as Camera3D

func _unhandled_input(event: InputEvent) -> void:
	if not _cam.current: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_offset_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.0, 0.4)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if _car != null and absf(_car.speed) > 1.0:
		_offset_yaw = lerp_angle(_offset_yaw, 0.0, 2.5 * delta)
	rotation = Vector3(_pitch, _offset_yaw, 0.0)
