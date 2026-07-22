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

@onready var _headlights := [$HeadlightL as SpotLight3D, $HeadlightR as SpotLight3D]
@onready var _engine := get_node_or_null("EngineAudio") as AudioStreamPlayer3D

func _ready() -> void:
	if _engine != null:
		var s := load("res://assets/audio/engine.wav") as AudioStreamWAV
		if s != null:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = s.data.size() / 2  # 16-bit mono: bytes -> frames
			_engine.stream = s

func park() -> void:
	driven = false
	speed = 0.0
	set_physics_process(false)
	$CamPivot.process_mode = Node.PROCESS_MODE_DISABLED
	($Visual as Node3D).set_process(false)
	if _engine != null:
		_engine.stop()

func start_driving() -> void:
	driven = true
	set_physics_process(true)
	$CamPivot.process_mode = Node.PROCESS_MODE_INHERIT
	($Visual as Node3D).set_process(true)
	if _engine != null and _engine.stream != null:
		_engine.play()

func stop_driving() -> void:
	driven = false
	if _engine != null: _engine.stop()

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
	var sun := get_tree().get_first_node_in_group("sun")
	var night: float = 0.0 if sun == null else sun.night_amount
	var glow: float = smoothstep(0.4, 0.55, night) if driven else 0.0
	for h in _headlights:
		(h as SpotLight3D).light_energy = 30.0 * glow
	if _engine != null and _engine.playing:
		_engine.pitch_scale = 0.75 + 1.5 * absf(speed) / MAX_SPEED
