extends CharacterBody3D
class_name Car
# Arcade car: signed forward speed + yaw steering on a kinematic body.
# Parked cars are physics-frozen (park()) — tile collision only exists in a
# ring around the active camera, so a far-away simulated car would fall
# through the world. start_driving() thaws it; after stop_driving() it
# coasts to a stop and refreezes itself.

const MAX_SPEED := 24.0        # m/s ~ 86 km/h
const MAX_REVERSE := 7.0
const ACCEL := 9.0
const BRAKE := 16.0
const COAST_DRAG := 3.0
const HANDBRAKE_DRAG := 12.0
const STEER_RATE := 1.9        # rad/s at crawl, tightens down at speed
const GRAVITY := 14.0

var driven := false
var speed := 0.0
var steer_input := 0.0

func park() -> void:
	driven = false
	speed = 0.0
	set_physics_process(false)

func start_driving() -> void:
	driven = true
	set_physics_process(true)

func stop_driving() -> void:
	driven = false

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var handbrake := false
	if driven:
		throttle = Input.get_action_strength("move_forward") \
				- Input.get_action_strength("move_back")
		steer_input = Input.get_action_strength("move_left") \
				- Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("jump")
	else:
		steer_input = 0.0
	if throttle > 0.0:
		speed = minf(speed + ACCEL * throttle * delta, MAX_SPEED)
	elif throttle < 0.0:
		if speed > 0.5:
			speed = maxf(speed + BRAKE * throttle * delta, 0.0)
		else:
			speed = maxf(speed + ACCEL * throttle * delta, -MAX_REVERSE)
	else:
		var drag := HANDBRAKE_DRAG if handbrake else COAST_DRAG
		speed = move_toward(speed, 0.0, drag * delta)
	if absf(speed) > 0.5:
		var agility := STEER_RATE * (1.0 - 0.55 * absf(speed) / MAX_SPEED)
		rotation.y += steer_input * agility * delta * signf(speed)
	var forward := -transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if not driven and absf(speed) < 0.3 and is_on_floor():
		park()
