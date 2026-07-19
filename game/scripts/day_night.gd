extends DirectionalLight3D
# Day/night: rotates the sun and blends sky/ambient/fog. 0 = midnight, 0.5 = noon.

@export var day_length_sec := 600.0
@export var time_of_day := 0.35

const NIGHT_SKY := Color(0.05, 0.07, 0.12)
const DAY_SKY := Color(0.75, 0.82, 0.9)
const NIGHT_AMB := Color(0.12, 0.14, 0.22)
const DAY_AMB := Color(0.8, 0.8, 0.85)

var _env: Environment

func _ready() -> void:
	var we := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / day_length_sec, 1.0)
	if Input.is_key_pressed(KEY_T):
		time_of_day = fposmod(time_of_day + delta * 0.05, 1.0)
	var s := sin((time_of_day - 0.25) * TAU)      # >0 during day, 1 at noon
	var daylight := clampf(s * 1.5, 0.0, 1.0)
	rotation_degrees = Vector3(-15.0 - 60.0 * maxf(s, 0.0), 40.0 + 360.0 * time_of_day, 0.0)
	light_energy = 0.05 + 1.15 * daylight
	light_color = Color(1.0, 0.75 + 0.25 * daylight, 0.55 + 0.45 * daylight)
	if _env == null:
		return
	_env.background_color = NIGHT_SKY.lerp(DAY_SKY, daylight)
	_env.ambient_light_color = NIGHT_AMB.lerp(DAY_AMB, daylight)
	_env.ambient_light_energy = 0.15 + 0.45 * daylight
	if _env.fog_enabled:
		_env.fog_light_color = _env.background_color
