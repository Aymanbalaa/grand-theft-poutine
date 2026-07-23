extends DirectionalLight3D
# Day/night: rotates the sun, blends the procedural sky, and feeds the
# night_amount shader global that lights building windows. 0 = midnight, 0.5 = noon.

@export var day_length_sec := 600.0
@export var time_of_day := 0.35

const DAY_HOR := Color(0.78, 0.86, 0.94)
const NIGHT_HOR := Color(0.07, 0.09, 0.16)
const DUSK_HOR := Color(1.0, 0.5, 0.22)

var night_amount := 0.0

var _env: Environment

func _ready() -> void:
	add_to_group("sun")
	var we := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / day_length_sec, 1.0)
	if Input.is_key_pressed(KEY_T):
		time_of_day = fposmod(time_of_day + delta * 0.05, 1.0)
	var s := sin((time_of_day - 0.25) * TAU)
	var daylight := clampf(s * 1.5, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(s) * 2.5, 0.0, 1.0)
	rotation_degrees = Vector3(-6.0 - 78.0 * maxf(s, 0.0), 40.0 + 360.0 * time_of_day, 0.0)
	light_energy = 0.02 + 2.3 * daylight
	light_color = Color(1.0, 0.82 + 0.16 * daylight, 0.62 + 0.33 * daylight)
	night_amount = 1.0 - daylight
	RenderingServer.global_shader_parameter_set("night_amount", night_amount)
	var horizon := NIGHT_HOR.lerp(DAY_HOR, daylight).lerp(DUSK_HOR, dusk)
	if _env != null:
		_env.fog_light_color = horizon
		_env.ambient_light_energy = 0.45 + 0.6 * daylight
		var amb := Color(0.17, 0.19, 0.30).lerp(Color(0.92, 0.90, 0.86), daylight)
		_env.ambient_light_color = amb.lerp(Color(1.0, 0.72, 0.5), dusk * 0.6)
