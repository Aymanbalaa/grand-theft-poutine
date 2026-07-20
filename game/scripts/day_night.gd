extends DirectionalLight3D
# Day/night: rotates the sun, blends the procedural sky, and feeds the
# night_amount shader global that lights building windows. 0 = midnight, 0.5 = noon.

@export var day_length_sec := 600.0
@export var time_of_day := 0.35

const DAY_TOP := Color(0.32, 0.55, 0.85)
const DAY_HOR := Color(0.78, 0.86, 0.94)
const NIGHT_TOP := Color(0.015, 0.025, 0.07)
const NIGHT_HOR := Color(0.07, 0.09, 0.16)
const DUSK_HOR := Color(1.0, 0.5, 0.22)

var night_amount := 0.0

var _env: Environment
var _sky_mat: ProceduralSkyMaterial

func _ready() -> void:
	add_to_group("sun")
	var we := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
		if _env != null and _env.sky != null:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / day_length_sec, 1.0)
	if Input.is_key_pressed(KEY_T):
		time_of_day = fposmod(time_of_day + delta * 0.05, 1.0)
	var s := sin((time_of_day - 0.25) * TAU)
	var daylight := clampf(s * 1.5, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(s) * 2.5, 0.0, 1.0)
	rotation_degrees = Vector3(-6.0 - 78.0 * maxf(s, 0.0), 40.0 + 360.0 * time_of_day, 0.0)
	light_energy = 0.02 + 2.7 * daylight
	light_color = Color(1.0, 0.82 + 0.16 * daylight, 0.62 + 0.33 * daylight)
	night_amount = 1.0 - daylight
	RenderingServer.global_shader_parameter_set("night_amount", night_amount)
	var horizon := NIGHT_HOR.lerp(DAY_HOR, daylight).lerp(DUSK_HOR, dusk)
	if _sky_mat != null:
		_sky_mat.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, daylight)
		_sky_mat.sky_horizon_color = horizon
		_sky_mat.ground_horizon_color = horizon
	if _env != null:
		_env.fog_light_color = horizon
		_env.ambient_light_energy = 0.18 + 0.62 * daylight
