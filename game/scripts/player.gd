extends CharacterBody3D
class_name Player
# Third-person on-foot movement. cam_yaw is fed by the camera rig so input
# is camera-relative; until a rig exists it stays 0 (world-aligned).

const WALK_SPEED := 4.5
const SPRINT_SPEED := 8.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 14.0

var cam_yaw := 0.0

static func ensure_actions() -> void:
	var defs := [["move_forward", KEY_W], ["move_back", KEY_S], ["move_left", KEY_A],
			["move_right", KEY_D], ["jump", KEY_SPACE], ["sprint", KEY_SHIFT],
			["toggle_fly", KEY_F], ["enter_exit", KEY_E]]
	for d in defs:
		if not InputMap.has_action(d[0]):
			InputMap.add_action(d[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = d[1]
			InputMap.action_add_event(d[0], ev)

func _ready() -> void:
	ensure_actions()

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
