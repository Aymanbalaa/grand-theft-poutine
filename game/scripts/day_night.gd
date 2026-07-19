extends DirectionalLight3D
# Day/night: rotates the sun, blends the procedural sky, and feeds the
# night_amount shader global that lights building windows. 0 = midnight, 0.5 = noon.

@export var day_length_sec := 600.0
@export var time_of_day := 0.35

const DAY_TOP := Color(0.35, 0.55, 0.8)
const DAY_HOR := Color(0.75, 0.82, 0.9)
const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_HOR := Color(0.08, 0.1, 0.18)
const DUSK_HOR := Color(1.0, 0.45, 0.2)

var _env: Environment
var _sky_mat: ProceduralSkyMaterial

func _ready() -> void:
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
	light_energy = 0.02 + 1.55 * daylight
	light_color = Color(1.0, 0.72 + 0.28 * daylight, 0.5 + 0.5 * daylight)
	RenderingServer.global_shader_parameter_set("night_amount", 1.0 - daylight)
	var horizon := NIGHT_HOR.lerp(DAY_HOR, daylight).lerp(DUSK_HOR, dusk)
	if _sky_mat != null:
		_sky_mat.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, daylight)
		_sky_mat.sky_horizon_color = horizon
		_sky_mat.ground_horizon_color = horizon
	if _env != null:
		_env.fog_light_color = horizon
		_env.ambient_light_energy = 0.2 + 0.3 * daylight
