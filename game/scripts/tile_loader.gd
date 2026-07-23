extends Node3D
class_name TileLoader

@export var view_distance := 800.0
const COLLISION_RADIUS := 280.0
var _tiles: Array[Dictionary] = []   # {node: Node3D, center: Vector3}
var _collision: Dictionary = {}  # Node3D -> StaticBody3D
var _landmark_bodies := 0
var _tile_size := 256.0
var _camera: Camera3D
var _city_mat := _make_city_material()
var _building_mat := _make_building_material()
var _water_mat := _make_shader_material("res://shaders/water.gdshader")
var _road_mat := _make_road_material()
var _sidewalk_mat := _make_triplanar_material("paving", 0.5, 1.8)
var _marks_mat := _make_marks_material()
var _terrain_mat := _make_terrain_material()
var _path_mat := _make_triplanar_material("ground", 0.35, 1.15)

static func _make_city_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m

static func _make_shader_material(path: String) -> ShaderMaterial:
	if not ResourceLoader.exists(path):
		return null
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m

static func _make_building_material() -> ShaderMaterial:
	var m := _make_shader_material("res://shaders/building_windows.gdshader")
	if m == null:
		return null
	for slot in ["brick", "stone", "concrete", "roof"]:
		var path := "res://assets/textures/pbr/%s_alb.jpg" % slot
		if ResourceLoader.exists(path):
			m.set_shader_parameter(slot + "_tex", load(path))
	return m

static func _make_triplanar_material(slot: String, uv_scale: float, brighten: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(brighten, brighten, brighten)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	var alb := "res://assets/textures/pbr/%s_alb.jpg" % slot
	if ResourceLoader.exists(alb):
		m.albedo_texture = load(alb)
	# no normal maps: tiles carry no tangents, and triplanar normal mapping
	# without them renders streak artifacts (tangent-frame garbage)
	m.roughness = 0.92
	return m

static func _make_marks_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(1.4, 1.4, 1.4)
	m.roughness = 0.55
	return m

static func _make_road_material() -> ShaderMaterial:
	var m := _make_shader_material("res://shaders/road.gdshader")
	if m == null:
		return null
	var path := "res://assets/textures/pbr/asphalt_alb.jpg"
	if ResourceLoader.exists(path):
		m.set_shader_parameter("asphalt_tex", load(path))
	return m

static func _make_terrain_material() -> ShaderMaterial:
	var m := _make_shader_material("res://shaders/terrain.gdshader")
	if m == null:
		return null
	var slots := {"grass_tex": "grass", "dirt_tex": "ground", "rock_tex": "rock"}
	for p in slots:
		var path := "res://assets/textures/pbr/%s_alb.jpg" % slots[p]
		if ResourceLoader.exists(path):
			m.set_shader_parameter(p, load(path))
	return m

func _apply_city_material(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var n := inst.name.to_lower()
		if _building_mat != null and n.begins_with("buildings"):
			inst.material_override = _building_mat
		elif _water_mat != null and n.begins_with("water"):
			inst.material_override = _water_mat
		elif n.begins_with("roadmarks"):
			inst.material_override = _marks_mat
		elif _road_mat != null and n.begins_with("roads"):
			inst.material_override = _road_mat
		elif n.begins_with("sidewalks"):
			inst.material_override = _sidewalk_mat
		elif n.begins_with("paths"):
			inst.material_override = _path_mat
		elif _terrain_mat != null and n.begins_with("terrain"):
			inst.material_override = _terrain_mat
		else:
			inst.material_override = _city_mat

func _ready() -> void:
	var meta_file := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if meta_file == null:
		push_error("city_metadata.json missing - run the pipeline first")
		return
	var parsed: Variant = JSON.parse_string(meta_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("city_metadata.json is malformed (expected top-level object)")
		return
	var meta: Dictionary = parsed
	_tile_size = meta["tile_size"]
	for t in meta["tiles"]:
		var path := "res://world/%s" % t["file"]
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("missing tile scene: " + path)
			continue
		var node := scene.instantiate() as Node3D
		add_child(node)
		_apply_city_material(node)
		var cx := (float(t["tx"]) + 0.5) * _tile_size
		var cz := (float(t["tz"]) + 0.5) * _tile_size
		_tiles.append({"node": node, "center": Vector3(cx, 0.0, cz)})
	for lm in meta.get("landmarks", []):
		var lm_scene := load("res://world/%s" % lm["file"]) as PackedScene
		if lm_scene == null:
			push_warning("missing landmark: " + str(lm["file"]))
			continue
		var lm_node := lm_scene.instantiate() as Node3D
		add_child(lm_node)
		_apply_city_material(lm_node)
		_build_collision(lm_node)
		_landmark_bodies += 1

func _process(_delta: float) -> void:
	# re-fetch every frame so F-toggling cameras retargets streaming + collision
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	var cam_pos := _camera.global_position
	var cam_xz := Vector2(cam_pos.x, cam_pos.z)
	for t in _tiles:
		var center: Vector3 = t["center"]
		var visible_now: bool = Vector2(center.x, center.z).distance_to(cam_xz) < view_distance + _tile_size
		(t["node"] as Node3D).visible = visible_now
	for t in _tiles:
		var center: Vector3 = t["center"]
		var near: bool = Vector2(center.x, center.z).distance_to(cam_xz) < COLLISION_RADIUS
		var node := t["node"] as Node3D
		if near and not _collision.has(node):
			_collision[node] = _build_collision(node)
		elif not near and _collision.has(node):
			(_collision[node] as StaticBody3D).queue_free()
			_collision.erase(node)

func _build_collision(tile: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	for mi in tile.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var n := inst.name.to_lower()
		if n.begins_with("water") or n.begins_with("props") or n.begins_with("roadmarks"):
			continue
		if inst.mesh == null:
			continue
		var shape := inst.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	tile.add_child(body)
	return body

func loaded_tile_count() -> int:
	return _tiles.size()

func landmark_body_count() -> int:
	return _landmark_bodies
