extends Node3D
class_name TileLoader

@export var view_distance := 800.0
var _tiles: Array[Dictionary] = []   # {node: Node3D, center: Vector3}
var _tile_size := 256.0
var _camera: Camera3D

func _ready() -> void:
	var meta_file := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	assert(meta_file != null, "city_metadata.json missing — run the pipeline first")
	var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
	_tile_size = meta["tile_size"]
	for t in meta["tiles"]:
		var path := "res://world/%s" % t["file"]
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("missing tile scene: " + path)
			continue
		var node := scene.instantiate() as Node3D
		add_child(node)
		var cx := (float(t["tx"]) + 0.5) * _tile_size
		var cz := (float(t["tz"]) + 0.5) * _tile_size
		_tiles.append({"node": node, "center": Vector3(cx, 0.0, cz)})

func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	var cam_pos := _camera.global_position
	for t in _tiles:
		var visible_now: bool = t["center"].distance_to(cam_pos) < view_distance + _tile_size
		(t["node"] as Node3D).visible = visible_now

func loaded_tile_count() -> int:
	return _tiles.size()
