extends Node3D
class_name LightPool
# Recycles a fixed pool of OmniLights onto the nearest street-lamp heads
# around the active camera at night. 499 lamps, 24 lights, zero shadows.

const POOL_SIZE := 24
const RADIUS := 140.0
const HEAD_Y := 4.8
const REASSIGN_SEC := 0.25

var _lamps: PackedVector3Array = PackedVector3Array()
var _lights: Array[OmniLight3D] = []
var _accum := 1.0

func lamp_count() -> int:
	return _lamps.size()

func _ready() -> void:
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			for p in meta.get("lamps", []):
				_lamps.append(Vector3(p[0], p[1] + HEAD_Y, p[2]))
	for i in POOL_SIZE:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 20.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 6.0
		add_child(l)
		_lights.append(l)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < REASSIGN_SEC:
		return
	_accum = 0.0
	var sun := get_tree().get_first_node_in_group("sun")
	var night: float = 0.0 if sun == null else sun.night_amount
	if night < 0.5 or _lamps.is_empty():
		for l in _lights:
			l.light_energy = 0.0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		for l in _lights:
			l.light_energy = 0.0
		return
	var cp := cam.global_position
	var near: Array = []  # [dist2, Vector3]
	for lp in _lamps:
		var d2 := cp.distance_squared_to(lp)
		if d2 < RADIUS * RADIUS:
			near.append([d2, lp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var energy := 9.0 * smoothstep(0.5, 0.9, night)
	for i in POOL_SIZE:
		var l := _lights[i]
		if i < near.size():
			l.global_position = near[i][1]
			l.light_energy = energy
		else:
			l.light_energy = 0.0
