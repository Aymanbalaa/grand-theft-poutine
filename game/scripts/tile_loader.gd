extends Node3D
class_name TileLoader

@export var view_distance := 800.0
var _tiles: Array[Dictionary] = []   # {node: Node3D, center: Vector3}
var _tile_size := 256.0
var _camera: Camera3D
var _city_mat := _make_city_material()

static func _make_city_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m

func _apply_city_material(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _city_mat

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

func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	var cam_pos := _camera.global_position
	var cam_xz := Vector2(cam_pos.x, cam_pos.z)
	for t in _tiles:
		var center: Vector3 = t["center"]
		var visible_now: bool = Vector2(center.x, center.z).distance_to(cam_xz) < view_distance + _tile_size
		(t["node"] as Node3D).visible = visible_now

func loaded_tile_count() -> int:
	return _tiles.size()
