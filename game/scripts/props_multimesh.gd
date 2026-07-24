extends Node3D
## Builds one MultiMeshInstance3D per prop model from metadata positions.
## GPU instancing carries all instances resident; Godot culls by MultiMesh AABB.

const SPECS := [
	# scales compensate small native model sizes (trees ~1.2-1.7 m, lamp 0.6 m, bench 0.47 m)
	{"key": "trees", "models": ["res://assets/models/props/tree0.glb",
			"res://assets/models/props/tree1.glb", "res://assets/models/props/tree2.glb"],
		"scale_min": 3.0, "scale_max": 4.6},
	{"key": "lamps", "models": ["res://assets/models/props/lamp_post.glb"],
		"scale_min": 7.5, "scale_max": 7.5},
	{"key": "benches", "models": ["res://assets/models/props/bench.glb"],
		"scale_min": 2.6, "scale_max": 2.6},
	{"key": "hydrants", "models": ["res://assets/models/props/hydrant.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
]

# the Kenney tree/bench GLBs carry KHR_materials_unlit + metallic=1 + pastel
# base colors (mint-teal foliage); replace known materials with shaded naturals
const MAT_COLORS := {
	"leafsGreen": Color(0.16, 0.40, 0.15),
	"woodBark": Color(0.35, 0.24, 0.15),
	"wood": Color(0.45, 0.30, 0.18),
	"_defaultMat": Color(0.34, 0.32, 0.29),
}

var _counts := {}

func _ready() -> void:
	add_to_group("props")
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f == null:
		return
	var meta = JSON.parse_string(f.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY:
		return
	for spec in SPECS:
		_build(spec, meta.get(spec["key"], []))

func instance_count(key: String) -> int:
	return _counts.get(key, 0)

static func _hash01(x: float, z: float, salt: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + salt) * 43758.5453, 1.0)

# props chunked into cells with distance culling so they disappear with the
# tile streaming radius (a single global MultiMesh drew trees floating over
# hidden far tiles); cell size matches the tile grid, cull just past view_distance
const CHUNK := 256.0
const CULL_DIST := 1000.0

func _build(spec: Dictionary, positions: Array) -> void:
	if positions.is_empty():
		return
	var meshes: Array[Dictionary] = []
	for path in spec["models"]:
		var entry := _first_mesh(path)
		if not entry.is_empty():
			meshes.append(entry)
	if meshes.is_empty():
		return
	# bucket positions by (model variant via position hash, chunk cell)
	var buckets := {}
	for p in positions:
		var v := Vector3(p[0], p[1], p[2])
		var mi := int(_hash01(v.x, v.z, 7.7) * meshes.size()) % meshes.size()
		var cell := Vector2i(floori(v.x / CHUNK), floori(v.z / CHUNK))
		var key := [mi, cell]
		if not buckets.has(key):
			buckets[key] = PackedVector3Array()
		buckets[key].append(v)
	var total := 0
	for key in buckets:
		var pts: PackedVector3Array = buckets[key]
		var cell: Vector2i = key[1]
		var center := Vector3((cell.x + 0.5) * CHUNK, 0.0, (cell.y + 0.5) * CHUNK)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key[0]]["mesh"]
		var model_xf: Transform3D = meshes[key[0]]["xform"]
		mm.instance_count = pts.size()
		for j in pts.size():
			var v: Vector3 = pts[j]
			var yaw := _hash01(v.x, v.z, 3.1) * TAU
			var s: float = lerp(spec["scale_min"], spec["scale_max"], _hash01(v.x, v.z, 5.3))
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), v - center) * model_xf
			mm.set_instance_transform(j, xf)
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.position = center
		inst.visibility_range_end = CULL_DIST
		inst.name = "%s_%d_%d_%d" % [spec["key"], key[0], cell.x, cell.y]
		add_child(inst)
		total += pts.size()
	_counts[spec["key"]] = total

# returns {"mesh": Mesh, "xform": Transform3D} — the accumulated node transform
# matters: some packs carry meaning in it (the hydrant is mm-scale vertices
# under a scale-100 node; trees sink their root flare via a -0.05 translation)
static func _first_mesh(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var scene = load(path)
	if scene == null:
		return {}
	var root = scene.instantiate()
	var found := _find_mesh(root, Transform3D.IDENTITY)
	root.free()
	return found

static func _find_mesh(node: Node, xform: Transform3D) -> Dictionary:
	var n3d := node as Node3D
	if n3d != null:
		xform = xform * n3d.transform
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var m := mi.mesh
		# bake the importer's surface materials into the mesh so MultiMesh keeps them
		for s in m.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null:
				continue
			if MAT_COLORS.has(mat.resource_name):
				var fixed := StandardMaterial3D.new()
				fixed.albedo_color = MAT_COLORS[mat.resource_name]
				fixed.roughness = 1.0
				m.surface_set_material(s, fixed)
			else:
				# colormap safety net (white-car-bug class): a fresh import can drop
				# the external-URI colormap.png, leaving the kept material untextured
				# white. Re-assign it when no albedo texture survived.
				var bmat := mat as BaseMaterial3D
				if bmat != null and bmat.albedo_texture == null:
					var tex := load("res://assets/models/props/Textures/colormap.png") as Texture2D
					if tex != null:
						bmat.albedo_texture = tex
				m.surface_set_material(s, mat)
		return {"mesh": m, "xform": xform}
	for child in node.get_children():
		var found := _find_mesh(child, xform)
		if not found.is_empty():
			return found
	return {}
