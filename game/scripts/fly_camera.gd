extends Camera3D

const SPEED := 30.0
const FAST_MULT := 4.0
const MOUSE_SENS := 0.002

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * MOUSE_SENS)
		rotation.x = clampf(rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += transform.basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	var speed := SPEED * (FAST_MULT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	position += dir.normalized() * speed * delta if dir != Vector3.ZERO else Vector3.ZERO
