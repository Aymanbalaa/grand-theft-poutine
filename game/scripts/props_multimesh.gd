extends Node3D
## Builds one MultiMeshInstance3D per prop model from metadata positions.
## GPU instancing carries all instances resident; Godot culls by MultiMesh AABB.

const SPECS := [
	{"key": "trees", "models": ["res://assets/models/props/tree0.glb",
			"res://assets/models/props/tree1.glb", "res://assets/models/props/tree2.glb"],
		"scale_min": 0.85, "scale_max": 1.3},
	{"key": "lamps", "models": ["res://assets/models/props/lamp_post.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
	{"key": "benches", "models": ["res://assets/models/props/bench.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
	{"key": "hydrants", "models": ["res://assets/models/props/hydrant.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
]

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

func _build(spec: Dictionary, positions: Array) -> void:
	if positions.is_empty():
		return
	var meshes: Array[Mesh] = []
	for path in spec["models"]:
		var m := _first_mesh(path)
		if m != null:
			meshes.append(m)
	if meshes.is_empty():
		return
	# bucket positions by model variant (hash of position)
	var buckets: Array = []
	for i in meshes.size():
		buckets.append(PackedVector3Array())
	for p in positions:
		var v := Vector3(p[0], p[1], p[2])
		var mi := int(_hash01(v.x, v.z, 7.7) * meshes.size()) % meshes.size()
		buckets[mi].append(v)
	var total := 0
	for i in meshes.size():
		if buckets[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = buckets[i].size()
		for j in buckets[i].size():
			var v: Vector3 = buckets[i][j]
			var yaw := _hash01(v.x, v.z, 3.1) * TAU
			var s: float = lerp(spec["scale_min"], spec["scale_max"], _hash01(v.x, v.z, 5.3))
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), v)
			mm.set_instance_transform(j, xf)
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.name = "%s_%d" % [spec["key"], i]
		add_child(inst)
		total += buckets[i].size()
	_counts[spec["key"]] = total

static func _first_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var scene = load(path)
	if scene == null:
		return null
	var root = scene.instantiate()
	var mesh := _find_mesh(root)
	root.free()
	return mesh

static func _find_mesh(node: Node) -> Mesh:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var m := mi.mesh
		# bake the importer's surface materials into the mesh so MultiMesh keeps them
		for s in m.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat != null:
				m.surface_set_material(s, mat)
		return m
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
