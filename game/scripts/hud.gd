extends Label
# Street + district readout for the active camera position.

var _names: Array = []
var _grid: Dictionary = {}
var _cell := 64.0
var _districts: Array = []  # {name, pv: PackedVector2Array}

func _ready() -> void:
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f == null:
		return
	var meta: Variant = JSON.parse_string(f.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY:
		return
	if meta.has("streets"):
		_names = meta["streets"]["names"]
		_grid = meta["streets"]["grid"]
		_cell = meta["streets"]["cell"]
	for d in meta.get("districts", []):
		var pv := PackedVector2Array()
		for pt in d["poly"]:
			pv.append(Vector2(pt[0], pt[1]))
		_districts.append({"name": d["name"], "pv": pv})

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var key := "%d,%d" % [floori(p.x / _cell), floori(p.z / _cell)]
	var street := ""
	if _grid.has(key):
		street = str(_names[int(_grid[key])])
	var district := ""
	for d in _districts:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), d["pv"]):
			district = d["name"]
			break
	if street != "" and district != "":
		text = street + "  —  " + district
	else:
		text = street + district
