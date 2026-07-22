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
		var st: Variant = meta["streets"]
		if typeof(st) == TYPE_DICTIONARY and st.has("names") and st.has("grid") and st.has("cell"):
			_names = st["names"]
			_grid = st["grid"]
			_cell = st["cell"]
	for d in meta.get("districts", []):
		var pv := PackedVector2Array()
		for pt in d["poly"]:
			pv.append(Vector2(pt[0], pt[1]))
		_districts.append({"name": d["name"], "pv": pv})

func lookup(x: float, z: float) -> String:
	var key := "%d,%d" % [floori(x / _cell), floori(z / _cell)]
	var street := ""
	if _grid.has(key):
		street = str(_names[int(_grid[key])])
	var district := ""
	for d in _districts:
		if Geometry2D.is_point_in_polygon(Vector2(x, z), d["pv"]):
			district = d["name"]
			break
	if street != "" and district != "":
		return street + "  —  " + district
	return street + district

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	text = lookup(cam.global_position.x, cam.global_position.z)
