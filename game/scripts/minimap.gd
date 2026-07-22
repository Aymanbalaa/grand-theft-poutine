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
	var mm: Variant = meta["minimap"]
	if typeof(mm) != TYPE_DICTIONARY:
		return
	var wo: Variant = mm.get("world_origin")
	var ws: Variant = mm.get("world_size")
	if typeof(wo) != TYPE_ARRAY or wo.size() < 2 or typeof(ws) != TYPE_ARRAY or ws.size() < 2:
		return
	_origin = Vector2(wo[0], wo[1])
	_world = Vector2(ws[0], ws[1])

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var uv := (Vector2(cam.global_position.x, cam.global_position.z) - _origin) / _world
	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	_marker.position = uv * size - _marker.size / 2.0
