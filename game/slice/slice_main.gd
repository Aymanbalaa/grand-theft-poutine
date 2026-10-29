extends Node3D
# Rue Saint-Paul vertical slice: one hand-dressed Old-Montréal street at blue
# hour, just after rain. Everything is built from code at startup (deterministic
# seed): wet cobbles, procedural greystone/brick/French-regime facades with real
# window openings, wall lanterns, string lights, a café terrace, and the
# Marché Bonsecours dome closing the vista.
#
# Controls: WASD + mouse to walk (Shift run, Space roll, LMB punch, E wave),
# V = free fly-cam (Q/E down/up), Tab = cinematic tour, R = rain on/off,
# 1/2/3 = blue hour / night / overcast day, F12 = screenshot.

const TEX := "res://assets/slice/tex/"
const MOD := "res://assets/slice/models/"
const FACE_X := 5.6           # facade line, both sides
const ROAD_HALF := 3.7
const CURB_H := 0.15
const CROSS_Z := Vector2(-46.0, -58.0)   # cross street (z range)
const END_Z := -112.0                     # street end (T with the market)
const MARKET_Z := -124.0

var mats := {}
var rng := RandomNumberGenerator.new()
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var rain: GPUParticles3D
var _yaw := 0.0
var _pitch := 0.0
var _tour := false
var _tour_t := 0.0
var _wet_mats: Array[ShaderMaterial] = []
var _glass_mat: ShaderMaterial
var _lamp_lights: Array[Light3D] = []
var _emissive_mats: Array[StandardMaterial3D] = []
var mood := 0
var _shadow_lights: Array[OmniLight3D] = []
var _shadow_t := 0.0
var shadow_budget := 5
var quality := 1
var _sky_mat: ShaderMaterial
var _backdrop_mat: ShaderMaterial
var player: SlicePlayer
var game: SliceGame
var peds: SlicePedestrians
var fly_mode := false
var _idle_spots: Array = []

const SHOPS := [
	{"name": "Boulangerie Saint-Paul", "blade": "Pain chaud", "sign": Color(0.12, 0.22, 0.16), "awning": true},
	{"name": "Chocolats Ville-Marie", "blade": "", "sign": Color(0.25, 0.09, 0.07)},
	{"name": "Galerie Lumière", "blade": "Galerie", "sign": Color(0.05, 0.05, 0.06), "font": "res://assets/slice/fonts/JosefinSans.ttf", "text_col": Color(0.95, 0.95, 0.92)},
	{"name": "Café des Voûtes", "blade": "Café", "sign": Color(0.1, 0.16, 0.28), "awning": true, "terrace": true},
	{"name": "Fromagerie du Marché", "blade": "", "sign": Color(0.3, 0.2, 0.08)},
	{"name": "Les Sucreries de l'Érable", "blade": "Érable", "sign": Color(0.32, 0.08, 0.06), "awning": true},
	{"name": "Librairie Bonsecours", "blade": "Livres", "sign": Color(0.07, 0.17, 0.12)},
	{"name": "Brasserie 1642", "blade": "Bières", "sign": Color(0.06, 0.06, 0.07), "awning": true, "terrace": true},
	{"name": "Bijouterie Fleur de Lys", "blade": "", "sign": Color(0.1, 0.1, 0.24)},
	{"name": "Poutinerie La Ruelle", "blade": "Poutine", "sign": Color(0.42, 0.1, 0.06), "font": "res://assets/slice/fonts/JosefinSans.ttf"},
	{"name": "Atelier de Verre", "blade": "", "sign": Color(0.14, 0.2, 0.2), "font": "res://assets/slice/fonts/JosefinSans.ttf", "text_col": Color(0.92, 0.95, 0.95)},
	{"name": "Taverne du Port", "blade": "Taverne", "sign": Color(0.2, 0.1, 0.06), "awning": true},
	{"name": "Dépanneur Saint-Paul", "blade": "", "sign": Color(0.5, 0.06, 0.05), "font": "res://assets/slice/fonts/JosefinSans.ttf", "text_col": Color(1.0, 0.95, 0.85)},
	{"name": "Antiquités Calvet", "blade": "Antiquités", "sign": Color(0.08, 0.12, 0.1)},
]
const FRAME_COLS := [Color(0.92, 0.9, 0.84), Color(0.1, 0.18, 0.13), Color(0.32, 0.08, 0.07), Color(0.06, 0.06, 0.07), Color(0.75, 0.68, 0.55)]
const CORNICE_COLS := [Color(0.12, 0.16, 0.13), Color(0.2, 0.2, 0.21), Color(0.7, 0.66, 0.58), Color(0.28, 0.12, 0.08), Color(0.08, 0.09, 0.1)]

func _ready() -> void:
	rng.seed = 1642
	_make_materials()
	_make_environment()
	_build_ground()
	_build_buildings()
	_build_market()
	_build_backdrop()
	_build_pole_lamps()
	_build_string_lights(Vector2(18.0, -42.0))
	_build_rain()
	_build_post()
	_setup_camera()
	_spawn_people()
	_build_street_extras()
	_build_audio()
	_build_hud()
	_fade_lights()
	set_quality(1)
	_set_mood(0)
	# `-- --tour` starts the cinematic tour (used for the Movie Maker capture)
	game = SliceGame.new()
	game.name = "Game"
	add_child(game)
	game.setup(self)
	_help.visible = false
	# `-- --tour` starts the cinematic tour (used for the Movie Maker capture)
	if OS.get_cmdline_user_args().has("--tour"):
		game.start_free()
		game.hud.visible = false
		_tour = true
		_tour_t = 0.0
		set_fly(true)
	else:
		_title.visible = false

# ================================================================= materials

func _tex(name: String) -> Texture2D:
	return load(TEX + name) as Texture2D

func _wall_mat(slot: String, tile: float, rough := 1.0, grime := 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://slice/shaders/wall.gdshader")
	m.set_shader_parameter("alb_tex", _tex(slot + "_alb.jpg"))
	m.set_shader_parameter("nrm_tex", _tex(slot + "_nrm.jpg"))
	m.set_shader_parameter("arm_tex", _tex(slot + "_arm.jpg"))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("rough_mul", rough)
	m.set_shader_parameter("grime", grime)
	_wet_mats.append(m)
	return m

func _paint(c: Color, rough := 0.45, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.roughness_texture = _tex("wood_arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.normal_enabled = true
	m.normal_texture = _tex("wood_nrm.jpg")
	m.normal_scale = 0.5
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.6
	return m

func _make_materials() -> void:
	mats["wall_greystone"] = _wall_mat("greystone", 2.6, 1.0, 0.45)
	mats["wall_brick"] = _wall_mat("redbrick", 1.6, 1.0, 0.5)
	mats["wall_french"] = _wall_mat("rubble", 2.2, 1.0, 0.55)
	mats["wall_victorian"] = _wall_mat("sandstone", 2.4, 1.0, 0.5)
	mats["trim"] = _wall_mat("greystone", 4.0, 0.9, 0.3)
	mats["trim"].set_shader_parameter("normal_strength", 0.4)
	mats["trim_brick"] = _wall_mat("sandstone", 3.0, 0.9, 0.35)
	mats["trim_brick"].set_shader_parameter("normal_strength", 0.4)
	mats["rubble"] = _wall_mat("rubble", 2.2, 1.0, 0.6)
	mats["slate"] = _wall_mat("slate", 1.4, 0.8, 0.2)
	mats["roofflat"] = _wall_mat("slate", 3.0, 1.0, 0.0)
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = load("res://slice/shaders/window_interior.gdshader")
	mats["glass"] = _glass_mat
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.05, 0.05, 0.055)
	metal.metallic = 0.8
	metal.roughness = 0.35
	mats["metal"] = metal
	var pots := StandardMaterial3D.new()
	pots.albedo_color = Color(0.45, 0.22, 0.14)
	pots.roughness = 0.8
	mats["pots"] = pots
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1, 0.9, 0.8)
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.85, 0.65)
	bulb.emission_energy_multiplier = 4.0
	mats["bulb_cool"] = bulb
	_emissive_mats.append(bulb)
	var awn := ShaderMaterial.new()
	awn.shader = load("res://slice/shaders/awning.gdshader")
	mats["awning_base"] = awn

func _building_mats(frame_col: Color, cornice_col: Color, sign_col: Color, awning_col: Color) -> Dictionary:
	var d := mats.duplicate()
	d["frame"] = _paint(frame_col, 0.4)
	d["door"] = _paint(frame_col.darkened(0.15) if frame_col.v < 0.6 else Color(0.12, 0.2, 0.15), 0.45)
	d["shutter"] = _paint(Color(0.12, 0.25, 0.17) if rng.randf() < 0.6 else Color(0.35, 0.1, 0.08), 0.6)
	d["cornice"] = _paint(cornice_col, 0.5, 0.2)
	d["sign"] = _paint(sign_col, 0.35)
	var awn := (mats["awning_base"] as ShaderMaterial).duplicate() as ShaderMaterial
	awn.set_shader_parameter("base_col", awning_col)
	_wet_mats.append(awn)
	d["awning"] = awn
	return d

# ================================================================= environment

func _make_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://slice/shaders/sky.gdshader")
	_sky_mat.set_shader_parameter("pano", load("res://assets/slice/hdri/sky.hdr"))
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(200.0), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 1.5
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.12
	env.sdfgi_energy = 0.9
	env.sdfgi_bounce_feedback = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.set_glow_level(5, 0.3)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0035
	env.fog_light_color = Color(0.28, 0.32, 0.45)
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.7, 0.75, 0.85)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_sky_affect = 0.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = false
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sky light"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.light_angular_distance = 1.5
	add_child(sun)

	var vp := get_viewport()
	vp.positional_shadow_atlas_size = 4096
	vp.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	vp.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
	vp.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
	vp.use_taa = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if Viewport.SCREEN_SPACE_AA_MAX > 2 else Viewport.SCREEN_SPACE_AA_FXAA
	vp.mesh_lod_threshold = 0.5
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	RenderingServer.environment_set_volumetric_fog_volume_size(192, 96)
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, true, 0.5, 2, 50, 300)

func _set_mood(m: int) -> void:
	mood = m
	var night := 1.0
	match m:
		0:  # blue hour after rain
			sun.light_color = Color(0.55, 0.62, 0.95)
			sun.light_energy = 0.12
			sun.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(160.0), 0)
			_sky_mat.set_shader_parameter("energy", 0.85)
			_sky_mat.set_shader_parameter("day", 0.0)
			env.ambient_light_energy = 0.55
			env.fog_light_color = Color(0.22, 0.27, 0.42)
			env.volumetric_fog_density = 0.016
			night = 0.9
		1:  # deep night
			sun.light_color = Color(0.45, 0.55, 0.9)
			sun.light_energy = 0.04
			sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(120.0), 0)
			_sky_mat.set_shader_parameter("energy", 0.4)
			_sky_mat.set_shader_parameter("day", 0.0)
			env.ambient_light_energy = 0.4
			env.fog_light_color = Color(0.08, 0.1, 0.16)
			env.volumetric_fog_density = 0.02
			night = 1.0
		2:  # overcast day
			sun.light_color = Color(1.0, 0.96, 0.9)
			sun.light_energy = 1.4
			sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(150.0), 0)
			_sky_mat.set_shader_parameter("energy", 1.0)
			_sky_mat.set_shader_parameter("day", 1.0)
			env.ambient_light_energy = 1.0
			env.fog_light_color = Color(0.6, 0.65, 0.72)
			env.volumetric_fog_density = 0.002
			night = 0.0
	_glass_mat.set_shader_parameter("night", night)
	_backdrop_mat.set_shader_parameter("night", night)
	for l in _lamp_lights:
		l.visible = night > 0.2
	for em in _emissive_mats:
		em.emission_energy_multiplier = 4.0 * night + 0.05
	RenderingServer.global_shader_parameter_set("night_amount", night)

# ================================================================= ground

func _ground_mat(slot: String, tile: float, height: bool, puddles: float, tint := Color(1, 1, 1)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://slice/shaders/ground_wet.gdshader")
	m.set_shader_parameter("alb_tex", _tex(slot + "_alb.jpg"))
	m.set_shader_parameter("nrm_tex", _tex(slot + "_nrm.jpg"))
	m.set_shader_parameter("arm_tex", _tex(slot + "_arm.jpg"))
	if height:
		m.set_shader_parameter("hgt_tex", _tex(slot + "_hgt.png"))
		m.set_shader_parameter("has_height", true)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("puddles", puddles)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_wet_mats.append(m)
	return m

# The quarter: rue Saint-Paul (north-south), rue Saint-Vincent crossing it,
# rue de la Commune along the market. Closing buildings seal every street end.
const CROSS_C := -52.0                    # cross street centre line (z)
const CROSS_X := 95.0                     # cross street half-length
const COMMUNE_Z := Vector2(-114.3, -121.7)  # market-street kerb lines (z)
const COMMUNE_X := 46.0

# Doors for the delivery game: {pos, kind ("shop"/"home"), name, street, number, item}
var doors: Array[Dictionary] = []
var _street_numbers := {}
var _bollard_kit := MeshKit.new()

func _in_cross(z: float) -> bool:
	return z < CROSS_Z.x and z > CROSS_Z.y

# True where the ground is roadway (pedestrians step down, cars could drive).
func on_road(p: Vector3) -> bool:
	if abs(p.x) < ROAD_HALF and p.z < 45.0 and p.z > COMMUNE_Z.y:
		return true
	if abs(p.z - CROSS_C) < ROAD_HALF and abs(p.x) < CROSS_X:
		return true
	return p.z < COMMUNE_Z.x and p.z > COMMUNE_Z.y and abs(p.x) < COMMUNE_X

# Crowned cobble strip. along_z: strip runs along Z (crown across X).
func _road_strip(st: SurfaceTool, a0: float, a1: float, c: float, half: float, along_z: bool, skip: Vector2) -> void:
	var step := 0.5
	var n_a := int(abs(a1 - a0) / step)
	var n_c := int(half * 2.0 / step) + 1
	var cstep := half * 2.0 / (n_c - 1)
	var sgn := signf(a1 - a0)
	for j in n_a:
		var aa := a0 + sgn * j * step
		var ab := aa + sgn * step
		if (aa > skip.x and aa < skip.y) or (ab > skip.x and ab < skip.y):
			continue
		for i in n_c - 1:
			var ca := c - half + i * cstep
			var cb := ca + cstep
			var quad := []
			for q in [[aa, ca], [ab, ca], [ab, cb], [aa, cb]]:
				var off: float = abs(q[1] - c) / half
				var y := 0.07 * (1.0 - off * off)
				var g := smoothstep(0.75, 1.0, off)
				var v := Vector3(q[1], y, q[0]) if along_z else Vector3(q[0], y, q[1])
				quad.append([v, g])
			for idx in [[0, 1, 2], [0, 2, 3]]:
				var pa: Vector3 = quad[idx[0]][0]
				var pb: Vector3 = quad[idx[1]][0]
				var pc: Vector3 = quad[idx[2]][0]
				var nrm := (pb - pa).cross(pc - pa).normalized()
				if nrm.y < 0:
					nrm = -nrm
				var order: Array = idx if (pb - pa).cross(pc - pa).dot(nrm) < 0 else [idx[0], idx[2], idx[1]]
				for k in order:
					st.set_normal(nrm)
					st.set_color(Color(quad[k][1], 0, 0))
					st.add_vertex(quad[k][0])

# Raised sidewalk slab [x0,x1]x[z0,z1]; `to_road` points from the slab toward the
# kerb edge. Granite kerb face + ramped collision so bodies can step up.
func _sidewalk(kit: MeshKit, x0: float, x1: float, z0: float, z1: float, to_road: Vector2) -> void:
	var lo := Vector2(minf(x0, x1), minf(z0, z1))
	var hi := Vector2(maxf(x0, x1), maxf(z0, z1))
	var y := CURB_H
	kit.quad("walk", Vector3(lo.x, y, hi.y), Vector3(hi.x, y, hi.y), Vector3(hi.x, y, lo.y), Vector3(lo.x, y, lo.y), Vector3.UP)
	# all four side faces (granite), the kerb one gets a top edge strip
	kit.quad("curb", Vector3(lo.x, y, lo.y), Vector3(hi.x, y, lo.y), Vector3(hi.x, 0, lo.y), Vector3(lo.x, 0, lo.y), Vector3.FORWARD)
	kit.quad("curb", Vector3(lo.x, y, hi.y), Vector3(hi.x, y, hi.y), Vector3(hi.x, 0, hi.y), Vector3(lo.x, 0, hi.y), Vector3.BACK)
	kit.quad("curb", Vector3(lo.x, y, lo.y), Vector3(lo.x, y, hi.y), Vector3(lo.x, 0, hi.y), Vector3(lo.x, 0, lo.y), Vector3.LEFT)
	kit.quad("curb", Vector3(hi.x, y, lo.y), Vector3(hi.x, y, hi.y), Vector3(hi.x, 0, hi.y), Vector3(hi.x, 0, lo.y), Vector3.RIGHT)
	var e := 0.28
	var strip: Array
	if to_road.x > 0: strip = [hi.x - e, hi.x, lo.y, hi.y]
	elif to_road.x < 0: strip = [lo.x, lo.x + e, lo.y, hi.y]
	elif to_road.y > 0: strip = [lo.x, hi.x, hi.y - e, hi.y]
	else: strip = [lo.x, hi.x, lo.y, lo.y + e]
	kit.quad("curb", Vector3(strip[0], y + 0.002, strip[3]), Vector3(strip[1], y + 0.002, strip[3]), Vector3(strip[1], y + 0.002, strip[2]), Vector3(strip[0], y + 0.002, strip[2]), Vector3.UP)
	var cb := StaticBody3D.new()
	var ccs := CollisionShape3D.new()
	var shp := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	var r := 0.35
	for cx in [lo.x, hi.x]:
		for cz in [lo.y, hi.y]:
			pts.append(Vector3(cx, y, cz))
			var gx: float = cx + (r if to_road.x > 0 and cx == hi.x else (-r if to_road.x < 0 and cx == lo.x else 0.0))
			var gz: float = cz + (r if to_road.y > 0 and cz == hi.y else (-r if to_road.y < 0 and cz == lo.y else 0.0))
			pts.append(Vector3(gx, 0, gz))
	shp.points = pts
	ccs.shape = shp
	cb.add_child(ccs)
	add_child(cb)

func _build_ground() -> void:
	var road := _ground_mat("cobble", 2.2, true, 0.55)
	var walk := _ground_mat("sidewalk", 1.6, false, 0.25, Color(0.85, 0.85, 0.88))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_road_strip(st, 45.0, END_Z, 0.0, ROAD_HALF, true, Vector2(CROSS_C - ROAD_HALF, CROSS_C + ROAD_HALF))
	_road_strip(st, -CROSS_X, -ROAD_HALF, CROSS_C, ROAD_HALF, false, Vector2(INF, -INF))
	_road_strip(st, ROAD_HALF, CROSS_X, CROSS_C, ROAD_HALF, false, Vector2(INF, -INF))
	# flat cobbles everywhere else (intersections, market street), just below the strips
	var y := -0.004
	for q in [[Vector3(-130, y, 70), Vector3(130, y, 70), Vector3(130, y, -170), Vector3(-130, y, -170)]]:
		for idx in [[0, 2, 1], [0, 3, 2]]:
			for k in idx:
				st.set_normal(Vector3.UP)
				st.set_color(Color(0, 0, 0))
				st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = st.commit()
	mi.material_override = road
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)

	var kit := MeshKit.new()
	var fx := FACE_X + 0.3
	for side in [-1.0, 1.0]:
		# rue Saint-Paul, both sides, broken by the cross street
		for r in [[45.0, CROSS_Z.x], [CROSS_Z.y, END_Z]]:
			_sidewalk(kit, side * ROAD_HALF, side * fx, r[0], r[1], Vector2(-side, 0))
		# rue Saint-Vincent, north and south kerbs, each half
		_sidewalk(kit, side * ROAD_HALF, side * CROSS_X, CROSS_Z.x + 0.3, CROSS_C + ROAD_HALF, Vector2(0, -1))
		_sidewalk(kit, side * ROAD_HALF, side * CROSS_X, CROSS_C - ROAD_HALF, CROSS_Z.y - 0.3, Vector2(0, 1))
		# rue de la Commune: north kerb (each half) and along the market
		_sidewalk(kit, side * ROAD_HALF, side * COMMUNE_X, END_Z, COMMUNE_Z.x, Vector2(0, -1))
	_sidewalk(kit, -COMMUNE_X, COMMUNE_X, COMMUNE_Z.y, MARKET_Z + 0.2, Vector2(0, 1))
	var smi := MeshInstance3D.new()
	smi.name = "Sidewalks"
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smi.mesh = kit.commit({"walk": walk, "curb": mats["trim"]})
	add_child(smi)

# ================================================================= buildings

const SHOPS_B := [
	{"name": "Bagels du Vieux", "blade": "Bagels", "sign": Color(0.2, 0.12, 0.05), "awning": true, "item": "une douzaine de bagels"},
	{"name": "Fleuriste Les Pivoines", "blade": "Fleurs", "sign": Color(0.3, 0.1, 0.2), "item": "un bouquet de pivoines", "fragile": true},
	{"name": "Crêperie Bretonne", "blade": "Crêpes", "sign": Color(0.05, 0.15, 0.3), "awning": true, "terrace": true, "item": "des crêpes au sucre d'érable"},
	{"name": "Pizzeria Napoli", "blade": "Pizza", "sign": Color(0.08, 0.25, 0.1), "font": "res://assets/slice/fonts/JosefinSans.ttf", "item": "deux pizzas"},
	{"name": "Disquaire 33 Tours", "blade": "Vinyles", "sign": Color(0.06, 0.06, 0.06), "font": "res://assets/slice/fonts/JosefinSans.ttf", "text_col": Color(0.95, 0.4, 0.3), "item": "une caisse de vinyles", "fragile": true},
	{"name": "Pharmacie du Port", "blade": "+", "sign": Color(0.05, 0.3, 0.15), "font": "res://assets/slice/fonts/JosefinSans.ttf", "text_col": Color(0.95, 1.0, 0.95), "item": "une ordonnance"},
	{"name": "Bar à Vin Le Cep", "blade": "Vins", "sign": Color(0.3, 0.05, 0.1), "awning": true, "item": "trois bouteilles de vin", "fragile": true},
	{"name": "Smoked Meat Chez Ben", "blade": "Smoked meat", "sign": Color(0.45, 0.25, 0.05), "font": "res://assets/slice/fonts/JosefinSans.ttf", "item": "deux smoked meat"},
	{"name": "Salon de Thé Marguerite", "blade": "Thé", "sign": Color(0.15, 0.2, 0.25), "item": "une boîte de thés"},
	{"name": "Quincaillerie Bonsecours", "blade": "", "sign": Color(0.25, 0.25, 0.27), "font": "res://assets/slice/fonts/JosefinSans.ttf", "item": "un coffre à outils"},
]
# what each Saint-Paul shop sends out
const ITEMS := {
	"Boulangerie Saint-Paul": "des croissants chauds", "Chocolats Ville-Marie": "une boîte de truffes",
	"Galerie Lumière": "un tableau encadré", "Café des Voûtes": "quatre cafés au lait",
	"Fromagerie du Marché": "un plateau de fromages", "Les Sucreries de l'Érable": "de la tire d'érable",
	"Librairie Bonsecours": "des livres rares", "Brasserie 1642": "une caisse de bières",
	"Bijouterie Fleur de Lys": "un écrin", "Poutinerie La Ruelle": "trois poutines",
	"Atelier de Verre": "un vase soufflé", "Taverne du Port": "deux tourtières",
	"Dépanneur Saint-Paul": "un sac d'épicerie", "Antiquités Calvet": "une lampe ancienne",
}
const FRAGILE := ["Galerie Lumière", "Atelier de Verre", "Antiquités Calvet", "Café des Voûtes", "Brasserie 1642"]

var _shop_i := 0
var _lantern_alt := 0

func _pick_style() -> Dictionary:
	var r := rng.randf()
	if r < 0.4:
		return {"style": "greystone", "roof": "mansard" if rng.randf() < 0.55 else "flat", "floors": rng.randi_range(3, 4)}
	if r < 0.62:
		return {"style": "brick", "roof": "flat", "floors": rng.randi_range(3, 4)}
	if r < 0.8:
		return {"style": "french", "roof": "gable", "floors": rng.randi_range(2, 3)}
	return {"style": "victorian", "roof": "flat", "floors": rng.randi_range(4, 5)}

func _next_shop(pool: Array):
	if pool.is_empty():
		return null
	var sh: Dictionary = pool.pop_front().duplicate()
	if not sh.has("item"):
		sh["item"] = ITEMS.get(sh["name"], "un colis")
	if FRAGILE.has(sh["name"]):
		sh["fragile"] = true
	return sh

# Fill a facade line with buildings. `from`/`to` are points on the facade line
# (ground level), `outward` faces the street. ww = sidewalk width (furniture).
func _build_row(from: Vector3, to: Vector3, outward: Vector3, street: String, shop_pool: Array,
		shop_p: float, ww: float, lanterns := true, wmin := 7.5, wmax := 13.5, style_override := {}) -> void:
	var dir := (to - from).normalized()
	var total := from.distance_to(to)
	var axis_u := Vector3.UP.cross(outward)
	var done := 0.0
	while total - done > 4.0:
		var w := rng.randf_range(wmin, wmax)
		if total - done - w < 6.0:
			w = total - done
		var cur := from + dir * done
		var origin := cur if dir.dot(axis_u) > 0 else cur + dir * w
		var s := _pick_style()
		s.merge(style_override, true)
		s["origin"] = origin
		s["outward"] = outward
		s["width"] = w
		s["seed"] = rng.randi()
		s["depth"] = 12.0
		var tint := Vector3.ONE * rng.randf_range(0.85, 1.1)
		tint.x *= rng.randf_range(0.96, 1.04)
		tint.z *= rng.randf_range(0.94, 1.03)
		s["tint"] = tint
		var shop = _next_shop(shop_pool) if rng.randf() < shop_p else null
		s["shop"] = shop
		var b := SliceBuilding.new(s)
		b.build()
		var awn_col := Color(0.1, 0.24, 0.15)
		if shop != null:
			awn_col = (shop["sign"] as Color).lightened(0.15)
		var bm := _building_mats(FRAME_COLS[rng.randi() % FRAME_COLS.size()],
			CORNICE_COLS[rng.randi() % CORNICE_COLS.size()],
			shop["sign"] if shop != null else Color(0.1, 0.1, 0.1), awn_col)
		add_child(b.make_node(bm, "Bldg_%d" % get_child_count()))
		for l in b.lights:
			_lamp_lights.append(l as Light3D)
		if lanterns:
			_lantern_alt += 1
			if _lantern_alt % 2 == 0 or w > 11.0:
				var u := w * (0.15 if rng.randf() < 0.5 else 0.85)
				_wall_lantern(origin + b.kit.axis_u * u + Vector3.UP * 4.85, outward)
		if ww > 0.0:
			_dress_frontage(b, shop, ww)
		# street number + door for deliveries
		var num: int = _street_numbers.get(street, 100 + rng.randi_range(0, 30) * 2) + 2 * rng.randi_range(1, 4)
		_street_numbers[street] = num
		if b.anchors.has("door"):
			var dp: Vector3 = b.anchors["door"]
			dp = Vector3(dp.x, CURB_H, dp.z) + outward * 0.5
			var d := {"pos": dp, "outward": outward, "street": street, "number": num,
				"kind": "shop" if shop != null else "home",
				"name": shop["name"] if shop != null else "%d, %s" % [num, street]}
			if shop != null:
				d["item"] = shop["item"]
				d["fragile"] = shop.get("fragile", false)
			doors.append(d)
			_door_number(b, num, outward)
		done += w

# Small enamel house-number plaque beside the door (Montréal blue).
func _door_number(b: SliceBuilding, num: int, outward: Vector3) -> void:
	var dp: Vector3 = b.anchors["door"]
	var lab := Label3D.new()
	lab.text = str(num)
	lab.font = load("res://assets/slice/fonts/JosefinSans.ttf")
	lab.font_size = 48
	lab.pixel_size = 0.004
	lab.modulate = Color(0.95, 0.95, 1.0)
	lab.outline_modulate = Color(0.08, 0.2, 0.55)
	lab.outline_size = 22
	lab.shaded = false
	lab.double_sided = false
	var u := Vector3.UP.cross(outward)
	lab.transform = Transform3D(Basis(u, Vector3.UP, outward), Vector3(dp.x, 2.75, dp.z) + u * 0.95 + outward * 0.02)
	add_child(lab)

func _build_buildings() -> void:
	var pool_a: Array = SHOPS.duplicate()
	var pool_b: Array = SHOPS_B.duplicate()
	var sp := "rue Saint-Paul Est"
	var sv := "rue Saint-Vincent"
	var co := "rue de la Commune"
	var cn := CROSS_Z.x
	var cs := CROSS_Z.y
	# rue Saint-Paul: west then east, north block then south block
	_build_row(Vector3(-FACE_X, 0, 44.0), Vector3(-FACE_X, 0, cn), Vector3.RIGHT, sp, pool_a, 0.8, FACE_X - ROAD_HALF)
	_build_row(Vector3(FACE_X, 0, 44.0), Vector3(FACE_X, 0, cn), Vector3.LEFT, sp, pool_a, 0.8, FACE_X - ROAD_HALF)
	_build_row(Vector3(-FACE_X, 0, cs), Vector3(-FACE_X, 0, END_Z), Vector3.RIGHT, sp, pool_a, 0.75, FACE_X - ROAD_HALF)
	_build_row(Vector3(FACE_X, 0, cs), Vector3(FACE_X, 0, END_Z), Vector3.LEFT, sp, pool_a, 0.75, FACE_X - ROAD_HALF)
	# rue Saint-Vincent: corners are owned by the Saint-Paul rows (12 m deep)
	var c0 := FACE_X + 12.0
	var ww := CROSS_Z.x - (CROSS_C + ROAD_HALF)
	for side in [-1.0, 1.0]:
		_build_row(Vector3(side * c0, 0, cn), Vector3(side * CROSS_X, 0, cn), Vector3.FORWARD, sv, pool_b, 0.5, ww)
		_build_row(Vector3(side * c0, 0, cs), Vector3(side * CROSS_X, 0, cs), Vector3.BACK, sv, pool_b, 0.5, ww)
		# rue de la Commune, north side
		_build_row(Vector3(side * c0, 0, END_Z), Vector3(side * COMMUNE_X, 0, END_Z), Vector3.FORWARD, co, [], 0.0, END_Z - COMMUNE_Z.x)
	# closing buildings: north end of Saint-Paul, both ends of Saint-Vincent and of la Commune
	_build_row(Vector3(-17.6, 0, 45.6), Vector3(17.6, 0, 45.6), Vector3.FORWARD, sp, [], 0.0, 0.0, true, 11.0, 13.0)
	for side in [-1.0, 1.0]:
		_build_row(Vector3(side * (CROSS_X + 0.2), 0, cn + 12.0), Vector3(side * (CROSS_X + 0.2), 0, cs - 12.0), Vector3(-side, 0, 0), sv, [], 0.0, 0.0, true, 11.0, 13.0)
		_build_row(Vector3(side * (COMMUNE_X + 0.2), 0, END_Z), Vector3(side * (COMMUNE_X + 0.2), 0, MARKET_Z), Vector3(-side, 0, 0), co, [], 0.0, 0.0, false, 12.0, 12.0)
	_ghost_signs()
	var bmi := MeshInstance3D.new()
	bmi.name = "Bollards"
	bmi.mesh = _bollard_kit.commit({"metal": mats["metal"]})
	add_child(bmi)

# Faded painted advertisements on the blank party walls facing rue Saint-Vincent.
func _ghost_signs() -> void:
	var texts := [["SAVON CASTOR", "DEPUIS 1898"], ["FARINE DU PORT", "MOULUE À MONTRÉAL"], ["TABAC & JOURNAUX", "OUVERT TARD"], ["CHAPEAUX LAVOIE", "ET FOURRURES"]]
	var k := 0
	for sx in [-1.0, 1.0]:
		for sz in [1.0, -1.0]:
			var z := CROSS_Z.x if sz > 0 else CROSS_Z.y
			var outward := Vector3(0, 0, -sz)
			var u := Vector3.UP.cross(outward)
			var center := Vector3(sx * (FACE_X + 6.0), 6.5, z + outward.z * 0.03)
			for line in 2:
				var lab := Label3D.new()
				lab.text = texts[k][line]
				lab.font = load("res://assets/slice/fonts/JosefinSans.ttf" if line == 0 else "res://assets/slice/fonts/PlayfairDisplay.ttf")
				lab.font_size = 160 if line == 0 else 96
				lab.pixel_size = 0.0075
				lab.modulate = Color(0.85, 0.82, 0.72, 0.42)
				lab.shaded = true
				lab.double_sided = false
				lab.transparency = 0.0
				lab.alpha_cut = Label3D.ALPHA_CUT_DISABLED
				lab.transform = Transform3D(Basis(u, Vector3.UP, outward), center + Vector3.UP * (0.9 - line * 1.8))
				add_child(lab)
			k += 1

func _wall_lantern(pos: Vector3, outward: Vector3) -> void:
	var inst := _model("street_lamp_02")
	inst.transform = Transform3D(Basis.looking_at(-outward, Vector3.UP), pos)
	add_child(inst)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.68, 0.38)
	l.light_energy = 4.0
	l.omni_range = 16.0
	l.omni_attenuation = 1.1
	l.shadow_enabled = true
	l.shadow_blur = 1.5
	l.shadow_bias = 0.05
	l.light_volumetric_fog_energy = 1.4
	l.position = Vector3(0, 0.67, 0.61)
	inst.add_child(l)
	_lamp_lights.append(l)
	_make_glow(inst)

func _make_glow(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			if m.resource_name.ends_with("_bulb") or m.resource_name.ends_with("_glass"):
				var e := m.duplicate() as StandardMaterial3D
				e.emission_enabled = true
				e.emission = Color(1.0, 0.72, 0.42)
				e.emission_energy_multiplier = 6.0 if m.resource_name.ends_with("_bulb") else 2.0
				if m.resource_name.ends_with("_glass"):
					e.albedo_color = Color(1.0, 0.85, 0.6, 0.55)
				mi.set_surface_override_material(s, e)
				_emissive_mats.append(e)
	for c in n.get_children():
		_make_glow(c)

func _model(id: String, keep := "") -> Node3D:
	var packed: PackedScene = load(MOD + id + "/" + id + ".gltf")
	var inst := packed.instantiate() as Node3D
	if keep != "":
		for c in inst.get_children():
			if not String(c.name).match(keep):
				c.queue_free()
			else:
				(c as Node3D).position.x = 0.0
	return inst

func _place(id: String, pos: Vector3, yaw: float, keep := "", scale := 1.0) -> Node3D:
	var m := _model(id, keep)
	m.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	add_child(m)
	return m

func _dress_frontage(b: SliceBuilding, shop, ww: float) -> void:
	var o: Vector3 = b.spec["origin"]
	var U := b.kit.axis_u
	var N := b.kit.axis_n
	var yaw_out := atan2(N.x, N.z)
	var w := b.W
	var y := CURB_H
	if shop != null and rng.randf() < 0.45:
		var sp := o + U * rng.randf_range(1.2, w - 1.2) + N * rng.randf_range(0.7, 1.1) + Vector3.UP * y
		_idle_spots.append([sp, atan2(-N.x, -N.z) + rng.randf_range(-0.5, 0.5)])
	if shop != null and shop.get("terrace", false):
		for k in 3:
			var u := w * (0.2 + 0.3 * k)
			var p := o + U * u + N * 1.25 + Vector3.UP * y
			_place("round_wooden_table_01", p, rng.randf() * TAU, "", 0.55)
			for a in [0.0, PI]:
				var cp := p + (U.rotated(Vector3.UP, a) * 0.55)
				_place("bar_chair_round_01", cp, yaw_out + a + rng.randf_range(-0.4, 0.4))
			var lp := p + Vector3.UP * 0.55
			var lan := _place("Lantern_01", lp, 0.0, "", 0.9)
			_make_glow(lan)
		_place("planter_box_01", o + U * 0.15 + N * 1.25 + Vector3.UP * y, yaw_out + PI * 0.5)
		_place("planter_box_01", o + U * (w - 0.15) + N * 1.25 + Vector3.UP * y, yaw_out + PI * 0.5)
	else:
		var r := rng.randf()
		if r < 0.35:
			_place("potted_plant_02", o + U * rng.randf_range(0.6, w - 0.6) + N * 0.45 + Vector3.UP * y, rng.randf() * TAU)
		elif r < 0.5:
			_place("wine_barrel_01", o + U * rng.randf_range(0.6, w - 0.6) + N * 0.5 + Vector3.UP * y, rng.randf() * TAU)
		elif r < 0.6:
			_place("painted_wooden_bench", o + U * rng.randf_range(1.0, w - 1.0) + N * 0.35 + Vector3.UP * y, yaw_out)
		elif r < 0.68:
			_place("wooden_crate_02", o + U * rng.randf_range(0.6, w - 0.6) + N * 0.4 + Vector3.UP * y, yaw_out + PI * 0.5)
	# planters under ground-floor windows of residential fronts
	if shop == null and rng.randf() < 0.5:
		_place("planter_box_01", o + U * (w * 0.5) + N * 0.25 + Vector3.UP * y, yaw_out + PI * 0.5)
	# curb-side street furniture
	var cr := rng.randf()
	var curb_p := o + U * rng.randf_range(1.0, w - 1.0) + N * (ww - 0.45) + Vector3.UP * y
	if cr < 0.18:
		_place("fire_hydrant", curb_p, yaw_out, "fire_hydrant*")
		for c in get_child(get_child_count() - 1).get_children():
			if String(c.name).contains("aged"):
				c.queue_free()
	elif cr < 0.32:
		_place("metal_trash_can", curb_p, rng.randf() * TAU, "metal_trash_can")
	elif cr < 0.4:
		_place("utility_box_01", curb_p, yaw_out)
	# bollards
	if rng.randf() < 0.6:
		for k in 2:
			_bollard(o + U * (w * (0.3 + 0.4 * k)) + N * (ww - 0.3) + Vector3.UP * y)

func _bollard(p: Vector3) -> void:
	var prof := [Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.13, 0.06), Vector2(0.1, 0.1), Vector2(0.09, 0.75),
		Vector2(0.11, 0.78), Vector2(0.11, 0.84), Vector2(0.08, 0.88), Vector2(0.06, 0.95), Vector2(0.0, 0.98)]
	_bollard_kit.lathe("metal", Transform3D(Basis(), p), prof, 14)

# ================================================================= string lights

func _build_string_lights(zr: Vector2) -> void:
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.045
	bulb_mesh.height = 0.11
	bulb_mesh.radial_segments = 10
	bulb_mesh.rings = 6
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.9, 0.7)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.75, 0.45)
	bm.emission_energy_multiplier = 9.0
	bulb_mesh.material = bm
	_emissive_mats.append(bm)
	var positions: Array[Vector3] = []
	var wire := MeshKit.new()
	var z := zr.x
	var flip := 1.0
	while z > zr.y:
		var a := Vector3(-FACE_X, 6.6 + rng.randf_range(-0.2, 0.3), z)
		var b := Vector3(FACE_X, 6.6 + rng.randf_range(-0.2, 0.3), z - 5.5)
		if flip < 0:
			var t := a
			a = Vector3(-FACE_X, b.y, b.z)
			b = Vector3(FACE_X, t.y, t.z)
		var segs := 40
		var prev := a
		for i in range(1, segs + 1):
			var t := float(i) / segs
			var pt := a.lerp(b, t) + Vector3.DOWN * (4.0 * t * (1.0 - t) * 0.9)
			var mid := (prev + pt) * 0.5
			var dir := (pt - prev)
			wire.wbox("wire", Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), mid), Vector3(0.012, 0.012, dir.length()))
			if i % 2 == 0 and i < segs:
				positions.append(pt + Vector3.DOWN * 0.07)
			prev = pt
		# a few real lights along each strand (cheap, unshadowed)
		for t in [0.5]:
			var lp: Vector3 = a.lerp(b, t) + Vector3.DOWN * (4.0 * t * (1.0 - t) * 0.9 + 0.2)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.7, 0.4)
			l.light_energy = 1.8
			l.omni_range = 8.0
			l.omni_attenuation = 1.4
			l.light_volumetric_fog_energy = 0.8
			l.position = lp
			add_child(l)
			_lamp_lights.append(l)
		z -= 7.5
		flip = -flip
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.02, 0.02, 0.02)
	wm.roughness = 0.6
	var wmi := MeshInstance3D.new()
	wmi.mesh = wire.commit({"wire": wm})
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wmi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb_mesh
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ================================================================= market & dome

func _build_market() -> void:
	# Long neoclassical market hall closing the street, dome over the centre.
	var spec := {"origin": Vector3(-46.0, 0, MARKET_Z), "outward": Vector3.BACK, "width": 92.0,
		"floors": 3, "style": "greystone", "roof": "flat", "seed": 1847, "depth": 22.0,
		"tint": Vector3(0.95, 0.95, 0.97), "shop": null}
	var b := SliceBuilding.new(spec)
	b.build()
	var bm := _building_mats(Color(0.9, 0.88, 0.82), Color(0.6, 0.6, 0.6), Color.BLACK, Color.BLACK)
	add_child(b.make_node(bm, "Market"))
	var top := b.H + 0.34
	var kit := MeshKit.new()
	var c := Vector3(0, top, MARKET_Z - 11.0)
	var X := Transform3D(Basis(), c)
	# portico: six columns + pediment in front of the centre
	kit.set_frame(Vector3(-8.0, 0, MARKET_Z), Vector3.BACK)
	kit.fbox("trim", -0.5, 16.5, 0.0, 0.6, 0.0, 3.4)
	for i in 6:
		var u := 0.6 + i * 2.96
		var col := [Vector2(0.55, 0.6), Vector2(0.55, 0.9), Vector2(0.45, 1.0), Vector2(0.42, 8.6), Vector2(0.55, 8.9), Vector2(0.55, 9.2)]
		kit.lathe("trim", Transform3D(Basis(), kit.p(u, 0.0, 2.6)), col, 20, 20, 0.04)
	kit.fbox("trim", -0.5, 16.5, 9.2, 10.4, -0.2, 3.3)
	kit.fbox("cornice", -0.7, 16.7, 10.4, 10.65, -0.2, 3.55)
	var pa := kit.p(-0.7, 10.65, 3.55)
	var pb := kit.p(16.7, 10.65, 3.55)
	var pc := kit.p(8.0, 13.4, 3.55)
	kit.tri("trim", pa, pb, pc, Vector3.BACK)
	kit.quad("slate", pa, pc, kit.p(8.0, 13.4, -0.2), kit.p(-0.7, 10.65, -0.2), Vector3(-0.3, 1, 0).normalized())
	kit.quad("slate", pc, pb, kit.p(16.7, 10.65, -0.2), kit.p(8.0, 13.4, -0.2), Vector3(0.3, 1, 0).normalized())
	# drum
	kit.lathe("trim", X, [Vector2(0, 0), Vector2(7.2, 0), Vector2(7.2, 1.2), Vector2(6.6, 1.3), Vector2(6.6, 6.8), Vector2(7.1, 7.0), Vector2(7.1, 7.6), Vector2(6.4, 7.7)], 64, 24, 0.035)
	# drum windows (warm)
	for i in 12:
		var a := TAU * (i + 0.5) / 12.0
		var dir := Vector3(cos(a), 0, sin(a))
		var p := c + dir * 6.62 + Vector3.UP * 4.0
		kit.wbox("dome_win", Transform3D(Basis.looking_at(-dir, Vector3.UP), p), Vector3(1.1, 3.4, 0.1))
	# ribbed silver dome
	var prof := []
	for i in 15:
		var t := float(i) / 14.0 * PI * 0.5
		prof.append(Vector2(6.5 * cos(t) + 0.0001, 7.7 + 6.4 * sin(t)))
	kit.lathe("dome", X, prof, 72, 16, 0.025)
	# lantern + cupola + finial
	kit.lathe("trim", X, [Vector2(1.6, 13.9), Vector2(1.6, 14.4), Vector2(1.3, 14.5), Vector2(1.3, 16.6), Vector2(1.6, 16.8), Vector2(1.6, 17.1)], 32, 8, 0.12)
	kit.lathe("dome_win", X, [Vector2(1.22, 14.6), Vector2(1.22, 16.5)], 24)
	var cup := []
	for i in 9:
		var t := float(i) / 8.0 * PI * 0.5
		cup.append(Vector2(1.55 * cos(t) + 0.0001, 17.1 + 1.6 * sin(t)))
	kit.lathe("dome", X, cup, 32, 8, 0.03)
	kit.lathe("metal", X, [Vector2(0.12, 18.6), Vector2(0.2, 19.0), Vector2(0.05, 20.2), Vector2(0.0, 20.3)], 12)
	var dome := StandardMaterial3D.new()
	dome.albedo_color = Color(0.78, 0.8, 0.83)
	dome.metallic = 0.95
	dome.roughness = 0.28
	var dwin := StandardMaterial3D.new()
	dwin.albedo_color = Color(0.1, 0.08, 0.05)
	dwin.emission_enabled = true
	dwin.emission = Color(1.0, 0.75, 0.45)
	dwin.emission_energy_multiplier = 2.5
	_emissive_mats.append(dwin)
	var mm := mats.duplicate()
	mm["dome"] = dome
	mm["dome_win"] = dwin
	mm["cornice"] = _paint(Color(0.55, 0.55, 0.55), 0.5, 0.3)
	var mi := MeshInstance3D.new()
	mi.name = "Dome"
	mi.mesh = kit.commit(mm)
	add_child(mi)
	# floodlights washing the dome and the portico
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0 + 0.3
		var s := SpotLight3D.new()
		var from := c + Vector3(cos(a) * 11.0, -0.5, sin(a) * 11.0)
		s.transform = Transform3D(Basis.looking_at((c + Vector3.UP * 9.0 - from).normalized(), Vector3.UP), from)
		s.light_color = Color(1.0, 0.86, 0.7)
		s.light_energy = 40.0
		s.spot_range = 30.0
		s.spot_angle = 32.0
		s.light_volumetric_fog_energy = 0.4
		add_child(s)
		_lamp_lights.append(s)
	for k in 3:
		var s2 := SpotLight3D.new()
		var fp := Vector3(-5.0 + k * 5.0, 0.3, MARKET_Z + 6.0)
		s2.transform = Transform3D(Basis.looking_at((Vector3(fp.x, 9.0, MARKET_Z + 1.0) - fp).normalized(), Vector3.UP), fp)
		s2.light_color = Color(1.0, 0.82, 0.62)
		s2.light_energy = 30.0
		s2.spot_range = 20.0
		s2.spot_angle = 30.0
		add_child(s2)
		_lamp_lights.append(s2)

# ================================================================= backdrop

func _build_backdrop() -> void:
	# Dark city blocks filling everything beyond the dressed street.
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = load("res://slice/shaders/backdrop.gdshader")
	var kit := MeshKit.new()
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var x := -170.0
	while x < 170.0:
		var z := -280.0
		var bw := r.randf_range(14.0, 26.0)
		while z < 150.0:
			var bd := r.randf_range(14.0, 26.0)
			var cx := x + bw * 0.5
			var cz := z + bd * 0.5
			var reserved := [Rect2(-19, -114, 38, 174), Rect2(-110, -72, 220, 40), Rect2(-50, -127, 100, 30), Rect2(-52, -152, 104, 30)]
			var me := Rect2(cx - bw * 0.5, cz - bd * 0.5, bw, bd)
			var free := true
			for rr in reserved:
				if (rr as Rect2).grow(1.0).intersects(me):
					free = false
			if free:
				var h := r.randf_range(11.0, 20.0)
				if r.randf() < 0.06 and abs(cx) > 60.0:
					h = r.randf_range(26.0, 40.0)
				kit.wbox("bd", Transform3D(Basis(), Vector3(cx, h * 0.5, cz)), Vector3(bw - 4.0, h, bd - 4.0))
			z += bd
		x += bw
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = kit.commit({"bd": _backdrop_mat})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ================================================================= pole lamps

func _build_pole_lamps() -> void:
	# Cast-iron lamp posts on the kerb, alternating sides, lighting the cobbles.
	var kit := MeshKit.new()
	var prof := [Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.2, 0.12), Vector2(0.16, 0.2), Vector2(0.16, 0.55),
		Vector2(0.12, 0.62), Vector2(0.075, 0.75), Vector2(0.06, 3.5), Vector2(0.09, 3.6), Vector2(0.09, 3.7), Vector2(0.05, 3.78), Vector2(0.05, 4.3), Vector2(0.0, 4.35)]
	var spots: Array = []   # [base, toward-road]
	var z := 34.0
	var side := 1.0
	while z > END_Z + 4.0:
		if abs(z - CROSS_C) > 8.0:
			spots.append([Vector3(side * (ROAD_HALF + 0.42), CURB_H, z), Vector3(-side, 0, 0)])
		z -= 17.0
		side = -side
	for hx in [-1.0, 1.0]:
		var x := 14.0
		var north := true
		while x < CROSS_X - 6.0:
			var kz := (CROSS_C + ROAD_HALF + 0.42) if north else (CROSS_C - ROAD_HALF - 0.42)
			spots.append([Vector3(hx * x, CURB_H, kz), Vector3(0, 0, -1.0 if north else 1.0)])
			x += 17.0
			north = not north
	for x in [-38.0, -22.0, 22.0, 38.0]:
		spots.append([Vector3(x, CURB_H, COMMUNE_Z.x + 0.42), Vector3(0, 0, -1)])
	for x in [-30.0, -14.0, 14.0, 30.0]:
		spots.append([Vector3(x, CURB_H, COMMUNE_Z.y - 0.42), Vector3(0, 0, 1)])
	for sp in spots:
		var base: Vector3 = sp[0]
		var outward: Vector3 = sp[1] * -1.0
		kit.lathe("metal", Transform3D(Basis(), base), prof, 16, 12, 0.08)
		var head := _model("street_lamp_02")
		head.transform = Transform3D(Basis.looking_at(-outward, Vector3.UP), base + Vector3.UP * 4.15 - outward * 0.05)
		add_child(head)
		_make_glow(head)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.42)
		l.light_energy = 4.5
		l.omni_range = 15.0
		l.omni_attenuation = 1.15
		l.shadow_enabled = true
		l.shadow_blur = 1.5
		l.light_volumetric_fog_energy = 1.4
		l.position = Vector3(0, 0.67, 0.61)
		head.add_child(l)
		_lamp_lights.append(l)
	var mi := MeshInstance3D.new()
	mi.name = "LampPosts"
	mi.mesh = kit.commit({"metal": mats["metal"]})
	add_child(mi)
	var body := StaticBody3D.new()
	add_child(body)

func _fade_lights() -> void:
	for l in _lamp_lights:
		if l is OmniLight3D and l.shadow_enabled:
			_shadow_lights.append(l)
			(l as OmniLight3D).omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		l.distance_fade_enabled = true
		l.distance_fade_begin = 70.0
		l.distance_fade_length = 20.0
		l.distance_fade_shadow = 45.0

# 0 = medium, 1 = high (default), 2 = ultra.
func set_quality(q: int) -> void:
	quality = q
	shadow_budget = [2, 5, 10][q]
	env.sdfgi_enabled = q >= 1
	env.ssil_enabled = q >= 2
	env.volumetric_fog_enabled = true
	RenderingServer.environment_set_volumetric_fog_volume_size([96, 160, 192][q], [48, 80, 96][q])
	env.ssr_max_steps = [48, 72, 96][q]
	_shadow_t = 0.0

# Only the lamps nearest the camera pay for shadow maps.
func _assign_shadows(from: Vector3) -> void:
	var sorted := _shadow_lights.duplicate()
	sorted.sort_custom(func(a, b): return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	for i in sorted.size():
		(sorted[i] as OmniLight3D).shadow_enabled = i < shadow_budget

# ================================================================= extras

func _build_street_extras() -> void:
	# Steaming manholes (it's Montréal) and cars under tarps along the kerb.
	var mtex := load("res://assets/textures/pbr/manhole_alb.png") as Texture2D
	for mp in [Vector3(1.1, 0.07, -6.0), Vector3(-1.3, 0.07, -84.0)]:
		var dec := Decal.new()
		dec.texture_albedo = mtex
		dec.size = Vector3(0.9, 0.4, 0.9)
		dec.position = mp
		add_child(dec)
		var steam := GPUParticles3D.new()
		steam.amount = 48
		steam.lifetime = 5.0
		steam.preprocess = 5.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.3
		pm.direction = Vector3(0.15, 1, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 0.35
		pm.initial_velocity_max = 0.7
		pm.gravity = Vector3(0.05, 0.12, 0)
		pm.damping_min = 0.05
		pm.damping_max = 0.1
		var sc := Curve.new()
		sc.max_value = 3.0
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 2.6))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.0))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		grad.add_point(0.15, Color(1, 1, 1, 1))
		grad.add_point(0.6, Color(1, 1, 1, 0.5))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		steam.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.1, 1.1)
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.albedo_color = Color(0.8, 0.82, 0.86, 0.09)
		var puff := GradientTexture2D.new()
		var pg := Gradient.new()
		pg.set_color(0, Color(1, 1, 1, 1))
		pg.set_color(1, Color(1, 1, 1, 0))
		puff.gradient = pg
		puff.fill = GradientTexture2D.FILL_RADIAL
		puff.fill_from = Vector2(0.5, 0.5)
		puff.fill_to = Vector2(0.5, 0.0)
		sm.albedo_texture = puff
		sm.proximity_fade_enabled = true
		sm.proximity_fade_distance = 0.6
		sm.disable_receive_shadows = true
		q.material = sm
		steam.draw_pass_1 = q
		steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		steam.position = mp
		add_child(steam)
	for cz in [-17.5, -36.0, -95.0]:
		var side := 1.0 if cz != -36.0 else -1.0
		var car := _place("covered_car", Vector3(side * (ROAD_HALF - 1.05), 0.0, cz), rng.randf_range(-0.03, 0.03))
		var cb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.8, 1.4, 4.4)
		cs.shape = bx
		cs.position = Vector3(0, 0.7, 0)
		cb.add_child(cs)
		car.add_child(cb)

# ================================================================= audio & HUD

func _loop_wav(path: String) -> AudioStreamWAV:
	var st := load(path) as AudioStreamWAV
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)
	return st

func _build_audio() -> void:
	var r := AudioStreamPlayer.new()
	r.stream = _loop_wav("res://assets/slice/audio/rain.wav")
	r.volume_db = -9.0
	r.autoplay = true
	r.name = "RainAudio"
	add_child(r)
	var d := AudioStreamPlayer.new()
	d.stream = _loop_wav("res://assets/slice/audio/drips.wav")
	d.volume_db = -15.0
	d.autoplay = true
	add_child(d)
	var c := AudioStreamPlayer.new()
	c.stream = _loop_wav("res://assets/audio/ambient.wav")
	c.volume_db = -20.0
	c.autoplay = true
	add_child(c)

var _hud: CanvasLayer
var _title: Control
var _help: Label
var _hud_t := 0.0

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = box
	var t1 := Label.new()
	t1.text = "Rue Saint-Paul"
	t1.add_theme_font_override("font", load("res://assets/slice/fonts/PlayfairDisplay.ttf"))
	t1.add_theme_font_size_override("font_size", 84)
	t1.add_theme_color_override("font_color", Color(1.0, 0.93, 0.8))
	t1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t1.add_theme_constant_override("shadow_offset_y", 3)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t2 := Label.new()
	t2.text = "VIEUX-MONTRÉAL  ·  19 H 42  ·  PLUIE"
	t2.add_theme_font_override("font", load("res://assets/slice/fonts/JosefinSans.ttf"))
	t2.add_theme_font_size_override("font_size", 24)
	t2.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.9))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t1)
	box.add_child(t2)
	_hud.add_child(box)
	_help = Label.new()
	_help.text = "WASD walk  ·  Shift run  ·  Space roll  ·  LMB punch  ·  E wave\nV fly-cam  ·  Tab tour  ·  1/2/3 mood  ·  R rain  ·  F5 quality  ·  H help"
	_help.add_theme_font_override("font", load("res://assets/slice/fonts/JosefinSans.ttf"))
	_help.add_theme_font_size_override("font_size", 17)
	_help.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92, 0.75))
	_help.position = Vector2(28, 28)
	_hud.add_child(_help)

func show_hud(on: bool) -> void:
	if game != null:
		game.hud.visible = on
	_hud.visible = on

func _update_hud(delta: float) -> void:
	_hud_t += delta
	_title.modulate.a = clampf(1.0 - (_hud_t - 4.5) / 2.0, 0.0, 1.0) * clampf(_hud_t / 1.2, 0.0, 1.0)
	if _hud_t > 20.0:
		_help.modulate.a = lerpf(_help.modulate.a, 0.0, delta * 0.8)

# ================================================================= rain & post

func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 9000
	rain.lifetime = 1.4
	rain.preprocess = 1.4
	rain.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 1, 16)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3(0, -2, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.009, 0.5)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.75, 0.8, 0.9, 0.09)
	rm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	rm.distance_fade_min_distance = 0.8
	rm.distance_fade_max_distance = 6.0
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.billboard_keep_scale = true
	q.material = rm
	rain.draw_pass_1 = q
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.local_coords = false
	rain.position = Vector3(0, 12, 0)
	add_child(rain)

func _build_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://slice/shaders/post.gdshader")
	rect.material = sm
	layer.add_child(rect)
	add_child(layer)

# ================================================================= camera

# Cinematic tour keyframes [camera, look-at], played as a Catmull-Rom spline.
const TOUR := [
	[Vector3(0.4, 9.0, 44.0), Vector3(0.0, 3.0, -40.0)],
	[Vector3(0.2, 2.2, 32.0), Vector3(0.0, 3.6, -50.0)],
	[Vector3(-2.4, 1.7, 16.0), Vector3(-0.5, 2.8, -20.0)],
	[Vector3(-2.0, 1.6, 2.0), Vector3(3.0, 2.4, -14.0)],
	[Vector3(1.6, 1.6, -10.0), Vector3(5.6, 2.4, -24.0)],
	[Vector3(0.6, 0.45, -24.0), Vector3(0.0, 2.2, -70.0)],
	[Vector3(-0.4, 0.8, -40.0), Vector3(0.0, 6.0, -110.0)],
	[Vector3(0.0, 2.0, -66.0), Vector3(0.0, 14.0, -135.0)],
	[Vector3(-1.5, 3.5, -92.0), Vector3(0.0, 17.0, -135.0)],
	[Vector3(2.0, 16.0, -100.0), Vector3(0.0, 15.0, -135.0)],
	[Vector3(4.0, 26.0, -88.0), Vector3(0.0, 4.0, -20.0)],
]
const TOUR_SEG := 6.0

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.05
	cam.far = 600.0
	add_child(cam)
	cam.global_position = TOUR[0][0]
	cam.look_at(TOUR[0][1], Vector3.UP)
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _spawn_people() -> void:
	player = SlicePlayer.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(1.2, 0.2, 24.0)
	player.cam_yaw = 0.0
	player.camera.current = true
	peds = SlicePedestrians.new()
	peds.player = player
	peds.on_road = on_road
	var wx := (ROAD_HALF + FACE_X) * 0.5
	var nz := (CROSS_Z.x + CROSS_C + ROAD_HALF) * 0.5
	var sz := (CROSS_Z.y + CROSS_C - ROAD_HALF) * 0.5
	var cn := (END_Z + COMMUNE_Z.x) * 0.5
	var cs := (COMMUNE_Z.y + MARKET_Z) * 0.5
	peds.segments = [
		[Vector3(-wx, 0, 43.0), Vector3(-wx, 0, -110.0)], [Vector3(wx, 0, 43.0), Vector3(wx, 0, -110.0)],
		[Vector3(-92.0, 0, nz), Vector3(92.0, 0, nz)], [Vector3(-92.0, 0, sz), Vector3(92.0, 0, sz)],
		[Vector3(-44.0, 0, cn), Vector3(44.0, 0, cn)],
		[Vector3(-44.0, 0, cs), Vector3(-10.0, 0, cs)], [Vector3(10.0, 0, cs), Vector3(44.0, 0, cs)],
	]
	peds.graph = {"N": Vector3(0, 0, 40), "X": Vector3(0, 0, CROSS_C), "S": Vector3(0, 0, -118),
		"W": Vector3(-92, 0, CROSS_C), "E": Vector3(92, 0, CROSS_C), "CW": Vector3(-43, 0, -118), "CE": Vector3(43, 0, -118)}
	peds.edges = {"N": ["X"], "X": ["N", "S", "W", "E"], "S": ["X", "CW", "CE"], "W": ["X"], "E": ["X"], "CW": ["S"], "CE": ["S"]}
	add_child(peds)
	peds.spawn(34, _idle_spots)

func set_fly(on: bool) -> void:
	fly_mode = on
	player.active = not on
	if on:
		cam.current = true
	else:
		player.camera.current = true

func active_camera() -> Camera3D:
	return cam if fly_mode else player.camera

func set_view(pos: Vector3, look: Vector3) -> void:
	set_fly(true)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and fly_mode:
		_yaw -= e.relative.x * 0.0025
		_pitch = clampf(_pitch - e.relative.y * 0.0025, -1.4, 1.4)
		_tour = false
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_TAB:
				_tour = not _tour
				_tour_t = 0.0
				if _tour:
					set_fly(true)
			KEY_V:
				set_fly(not fly_mode)
				_tour = false
			KEY_R:
				rain.emitting = not rain.emitting
				(get_node("RainAudio") as AudioStreamPlayer).volume_db = -9.0 if rain.emitting else -40.0
				for m in _wet_mats:
					m.set_shader_parameter("rain", 1.0 if rain.emitting else 0.0)
			KEY_1:
				_set_mood(0)
			KEY_2:
				_set_mood(1)
			KEY_3:
				_set_mood(2)
			KEY_H:
				_help.visible = true
				_help.modulate.a = 1.0 if _help.modulate.a < 0.5 else 0.0
				_hud_t = 0.0
			KEY_F5:
				set_quality((quality + 1) % 3)
			KEY_F12:
				var img := get_viewport().get_texture().get_image()
				img.save_png("user://shot_%d.png" % Time.get_ticks_msec())

func _process(delta: float) -> void:
	if _tour:
		_tour_t += delta / TOUR_SEG
		var n := TOUR.size()
		var t := fmod(_tour_t, float(n - 1))
		var i := int(t)
		var f := t - i
		var i0 := maxi(i - 1, 0)
		var i2 := mini(i + 1, n - 1)
		var i3 := mini(i + 2, n - 1)
		var pos: Vector3 = (TOUR[i][0] as Vector3).cubic_interpolate(TOUR[i2][0], TOUR[i0][0], TOUR[i3][0], f)
		var look: Vector3 = (TOUR[i][1] as Vector3).cubic_interpolate(TOUR[i2][1], TOUR[i0][1], TOUR[i3][1], f)
		cam.global_position = pos
		cam.look_at(look, Vector3.UP)
	elif fly_mode:
		cam.rotation = Vector3(_pitch, _yaw, 0)
		var v := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): v.z -= 1
		if Input.is_key_pressed(KEY_S): v.z += 1
		if Input.is_key_pressed(KEY_A): v.x -= 1
		if Input.is_key_pressed(KEY_D): v.x += 1
		if Input.is_key_pressed(KEY_E): v.y += 1
		if Input.is_key_pressed(KEY_Q): v.y -= 1
		var sp := 14.0 if Input.is_key_pressed(KEY_SHIFT) else 4.0
		cam.global_position += cam.global_transform.basis * v * sp * delta
	_update_hud(delta)
	var ac := active_camera()
	_shadow_t -= delta
	if _shadow_t <= 0.0:
		_shadow_t = 0.2
		_assign_shadows(ac.global_position)
	rain.global_position = ac.global_position + Vector3(0, 10, 0) - ac.global_transform.basis.z * 6.0
