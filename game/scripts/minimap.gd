extends TextureRect
# Bottom-left minimap: full-map texture + marker tracking the active camera.

var _origin := Vector2.ZERO
var _world := Vector2.ONE
@onready var _marker: ColorRect = $Marker

func _ready() -> void:
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f == null:
		return
	var meta: Variant = JSON.parse_string(f.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY or not meta.has("minimap"):
		return
	var mm: Dictionary = meta["minimap"]
	_origin = Vector2(mm["world_origin"][0], mm["world_origin"][1])
	_world = Vector2(mm["world_size"][0], mm["world_size"][1])

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var uv := (Vector2(cam.global_position.x, cam.global_position.z) - _origin) / _world
	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	_marker.position = uv * size - _marker.size / 2.0
