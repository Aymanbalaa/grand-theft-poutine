class_name SlicePlayer
extends CharacterBody3D
# Third-person on-foot controller for the slice: camera-relative WASD, Shift
# to run, Space to roll, left mouse to punch, E to wave. The camera rig is an
# orbiting SpringArm so walls never clip between player and lens.

const WALK := 1.9
const RUN := 5.2
const ROLL := 6.5
const GRAVITY := 18.0

var person: SlicePerson
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var cam_yaw := PI
var cam_pitch := -0.18
var active := true
var _roll_dir := Vector3.ZERO
var _roll_t := 0.0

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3
	person = SlicePerson.new()
	add_child(person)
	person.setup("casual_man", 1.78)
	pivot = Node3D.new()
	pivot.position.y = 1.55
	pivot.top_level = true
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 3.4
	arm.margin = 0.15
	arm.position = Vector3(0.45, 0, 0)  # over-the-shoulder offset
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	arm.shape = sph
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 600.0
	arm.add_child(camera)

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= e.relative.x * 0.0028
		cam_pitch = clampf(cam_pitch - e.relative.y * 0.0022, -1.1, 0.5)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if not person.busy() and is_on_floor():
			person.play("punch", 0.08, 1.4)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE and is_on_floor() and _roll_t <= 0.0:
			var f := -global_transform.basis.z
			f = Vector3(sin(person.rotation.y), 0, cos(person.rotation.y))
			_roll_dir = f
			_roll_t = 0.75
			person.play("roll", 0.05, 1.3)
		elif e.keycode == KEY_E and not person.busy():
			person.play("wave", 0.15)

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if active:
		input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): input.x -= 1
		if Input.is_key_pressed(KEY_D): input.x += 1
		if Input.is_key_pressed(KEY_W): input.y -= 1
		if Input.is_key_pressed(KEY_S): input.y += 1
		input = input.limit_length(1.0)
	var basis_y := Basis(Vector3.UP, cam_yaw)
	var dir := basis_y * Vector3(input.x, 0, input.y)
	var running := Input.is_key_pressed(KEY_SHIFT)
	var speed := RUN if running else WALK
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var hv := Vector3.ZERO
	if _roll_t > 0.0:
		_roll_t -= delta
		hv = _roll_dir * ROLL * clampf(_roll_t / 0.75 + 0.3, 0.0, 1.0)
	elif person.busy():
		hv = Vector3.ZERO
	else:
		hv = dir * speed
	velocity.x = lerpf(velocity.x, hv.x, clampf(delta * 10.0, 0, 1))
	velocity.z = lerpf(velocity.z, hv.z, clampf(delta * 10.0, 0, 1))
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3 and _roll_t <= 0.0 and not person.busy():
		var target := atan2(flat.x, flat.y)
		person.rotation.y = lerp_angle(person.rotation.y, target, clampf(delta * 12.0, 0, 1))
	if _roll_t <= 0.0 and not person.busy():
		var sp := flat.length()
		if sp > 3.2:
			person.play("run", 0.2, sp / RUN)
		elif sp > 0.3:
			person.play("walk", 0.2, sp / WALK * 0.9)
		else:
			person.play("idle", 0.25)

func _process(delta: float) -> void:
	pivot.global_position = pivot.global_position.lerp(global_position + Vector3.UP * 1.55, clampf(delta * 14.0, 0, 1))
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
