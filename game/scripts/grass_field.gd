extends Node3D
class_name GrassField

const GREEN_MIN := 0.06   # (g - r) must exceed this (mid of shader's 0.03..0.10 band)
const WET_MAX := 0.04     # (b - g) at/above this reads as water-bottom, not grass

static func is_grass(c: Color) -> bool:
	return (c.g - c.r) >= GREEN_MIN and (c.b - c.g) < WET_MAX

const CELL := 2.0          # green-mask cell size (m)
const STRIDE := 3.0        # grass grid spacing (m)
const RING := 70.0         # camera-near radius (m)
const MAX_BLADES := 1400
const REGEN_SEC := 0.25

var _green := {}           # Vector2i -> true (green cells discovered so far)
var _scanned := {}         # terrain tile instance_id -> true (scanned once)
var _scanned_roots := {}   # tile root instance_id -> true (fully walked, skip find_children)
var _mm := MultiMesh.new()
var _accum := 1.0
var _last_cell := Vector2i(2147483647, 0)

func _ready() -> void:
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.6)
	q.center_offset = Vector3(0.0, 0.3, 0.0)   # base at y=0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	q.surface_set_material(0, mat)
	_mm.mesh = q
	_mm.instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.name = "GrassMM"
	inst.multimesh = _mm
	add_child(inst)

func green_cell_count() -> int:
	return _green.size()

func blade_count() -> int:
	return _mm.instance_count

static func _hash01(x: float, z: float, salt: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + salt) * 43758.5453, 1.0)

func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))

func _scan_near_terrain(cam: Vector3) -> void:
	var loader := get_node_or_null("/root/Main/TileLoader")
	if loader == null:
		return
	# tile roots are direct children of TileLoader; each tile's actual geometry
	# (a "terrain" MeshInstance3D among others) is nested a couple of levels
	# down (tile_root/world/terrain), and vertex positions are baked in world
	# space already (tiles carry no per-tile transform), so distance is taken
	# from the terrain mesh's own world AABB, not a (always-zero) node position.
	for tile_root in loader.get_children():
		var root3d := tile_root as Node3D
		if root3d == null or not root3d.visible:
			continue
		var root_id := root3d.get_instance_id()
		if _scanned_roots.has(root_id):
			continue
		var fully_scanned := true
		for child in root3d.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if not mi.name.to_lower().begins_with("terrain"):
				continue
			if not mi.is_visible_in_tree():
				continue
			var id := mi.get_instance_id()
			if _scanned.has(id):
				continue
			# tiles are far larger than RING, so test the AABB's nearest point
			# to the camera rather than its (potentially distant) center
			var world_aabb: AABB = mi.global_transform * mi.get_aabb()
			var closest: Vector3 = cam.clamp(world_aabb.position, world_aabb.position + world_aabb.size)
			if closest.distance_to(cam) > RING * 2.0:
				fully_scanned = false
				continue
			_scanned[id] = true
			var arr := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols: Variant = arr[Mesh.ARRAY_COLOR]
			if typeof(cols) != TYPE_PACKED_COLOR_ARRAY or cols.is_empty():
				continue
			var xf := mi.global_transform
			for i in verts.size():
				if not is_grass(cols[i]):
					continue
				var w: Vector3 = xf * verts[i]
				_green[_cell_of(w.x, w.z)] = true
		if fully_scanned:
			_scanned_roots[root_id] = true

func _process(delta: float) -> void:
	_accum += delta
	if _accum < REGEN_SEC:
		return
	_accum = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	_scan_near_terrain(cp)
	var cc := Vector2i(floori(cp.x / STRIDE), floori(cp.z / STRIDE))
	if cc == _last_cell:
		return
	_last_cell = cc
	var xforms: Array[Transform3D] = []
	var n := int(RING / STRIDE)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var gx := (cc.x + ix) * STRIDE
			var gz := (cc.y + iz) * STRIDE
			var jx := gx + (_hash01(gx, gz, 1.3) - 0.5) * STRIDE
			var jz := gz + (_hash01(gx, gz, 4.7) - 0.5) * STRIDE
			if Vector2(jx - cp.x, jz - cp.z).length() > RING:
				continue
			if not _green.has(_cell_of(jx, jz)):
				continue
			# skip a fraction for sparseness
			if _hash01(gx, gz, 9.1) > 0.6:
				continue
			var y := _green_y(cp, jx, jz)
			var yaw := _hash01(gx, gz, 2.2) * TAU
			var s: float = lerp(0.7, 1.3, _hash01(gx, gz, 6.6))
			xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(jx, y, jz)))
			if xforms.size() >= MAX_BLADES:
				break
		if xforms.size() >= MAX_BLADES:
			break
	_mm.instance_count = xforms.size()
	for j in xforms.size():
		_mm.set_instance_transform(j, xforms[j])

# grass y: raycast down onto terrain collision; fall back to camera-relative ground
func _green_y(cp: Vector3, x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, cp.y + 50.0, z)
	var to := Vector3(x, cp.y - 200.0, z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	return (hit.position.y if hit.has("position") else 0.0)
