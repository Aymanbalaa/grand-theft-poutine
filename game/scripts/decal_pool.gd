extends Node3D
class_name DecalPool
# Recycles a fixed pool of Decals onto the nearest manhole covers around the
# active camera. Mirrors light_pool.gd's pooled-nearest-N structure.

const POOL_SIZE := 32
const RADIUS := 120.0
const REASSIGN_SEC := 0.25

var _manholes: PackedVector3Array = PackedVector3Array()
var _decals: Array[Decal] = []
var _accum := 1.0

func manhole_count() -> int:
	return _manholes.size()

static func _hash01(x: float, z: float, salt: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + salt) * 43758.5453, 1.0)

func _ready() -> void:
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			for p in meta.get("manholes", []):
				_manholes.append(Vector3(p[0], p[1], p[2]))
	var tex := load("res://assets/textures/pbr/manhole_alb.png")
	for i in POOL_SIZE:
		var d := Decal.new()
		d.size = Vector3(0.9, 0.6, 0.9)
		d.texture_albedo = tex
		d.visible = false
		add_child(d)
		_decals.append(d)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < REASSIGN_SEC:
		return
	_accum = 0.0
	if _manholes.is_empty():
		for d in _decals:
			d.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		for d in _decals:
			d.visible = false
		return
	var cp := cam.global_position
	var near: Array = []  # [dist2, Vector3]
	for mp in _manholes:
		var d2 := cp.distance_squared_to(mp)
		if d2 < RADIUS * RADIUS:
			near.append([d2, mp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in POOL_SIZE:
		var d := _decals[i]
		if i < near.size():
			var mp: Vector3 = near[i][1]
			d.global_position = mp + Vector3(0, 0.3, 0)
			d.rotation.y = _hash01(mp.x, mp.z, 3.1) * TAU
			d.visible = true
		else:
			d.visible = false
