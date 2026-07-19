extends Node3D
# Mouse-orbit rig: yaw on this pivot, pitch clamped; Esc releases the mouse.

@export var sensitivity := 0.003

var _yaw := 0.0
var _pitch := -0.2
@onready var _player = get_parent()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.2, 0.5)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	if _player != null:
		_player.cam_yaw = _yaw
