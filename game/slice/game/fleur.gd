class_name SliceFleur
extends Node3D
# Hidden collectible: a spinning gilt fleur-de-lys (extruded from 2D outlines),
# with a faint glow so a sharp eye spots it down an alley.

var id := 0
var _t := 0.0
var _body: MeshInstance3D

const SHAPES := [
	# centre petal
	[Vector2(0, 1.0), Vector2(0.13, 0.78), Vector2(0.15, 0.55), Vector2(0.1, 0.3), Vector2(0, 0.22), Vector2(-0.1, 0.3), Vector2(-0.15, 0.55), Vector2(-0.13, 0.78)],
	# right petal curling out and down
	[Vector2(0.1, 0.34), Vector2(0.24, 0.5), Vector2(0.38, 0.7), Vector2(0.5, 0.72), Vector2(0.52, 0.6), Vector2(0.44, 0.44), Vector2(0.3, 0.3), Vector2(0.14, 0.24)],
	# right foot
	[Vector2(0.05, 0.17), Vector2(0.2, 0.08), Vector2(0.3, -0.1), Vector2(0.2, -0.06), Vector2(0.05, 0.04)],
	# band
	[Vector2(-0.24, 0.27), Vector2(0.24, 0.27), Vector2(0.24, 0.16), Vector2(-0.24, 0.16)],
]

static func _mirror(poly: Array) -> Array:
	var out := []
	for i in range(poly.size() - 1, -1, -1):
		var v: Vector2 = poly[i]
		out.append(Vector2(-v.x, v.y))
	return out

static func build_mesh(scale: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polys := []
	for p in SHAPES:
		polys.append(p)
	polys.append(_mirror(SHAPES[1]))
	polys.append(_mirror(SHAPES[2]))
	for poly in polys:
		var pts := PackedVector2Array()
		for v in poly:
			pts.append((v as Vector2) * scale)
		var tris := Geometry2D.triangulate_polygon(pts)
		for side in [1.0, -1.0]:
			var n := Vector3(0, 0, side)
			for i in range(0, tris.size(), 3):
				var ids := [tris[i], tris[i + 1], tris[i + 2]] if side < 0 else [tris[i], tris[i + 2], tris[i + 1]]
				for k in ids:
					st.set_normal(n)
					st.add_vertex(Vector3(pts[k].x, pts[k].y, side * depth * 0.5))
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var e := (b - a).normalized()
			var n2 := Vector3(e.y, -e.x, 0)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + Vector2(n2.x, n2.y) * 0.002, pts):
				n2 = -n2
			var q := [Vector3(a.x, a.y, depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(a.x, a.y, -depth * 0.5)]
			for ids in [[0, 1, 2], [0, 2, 3]]:
				var tri := [q[ids[0]], q[ids[1]], q[ids[2]]]
				if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(n2) > 0.0:
					tri = [tri[0], tri[2], tri[1]]
				for v in tri:
					st.set_normal(n2)
					st.add_vertex(v)
	return st.commit()

func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = build_mesh(0.42, 0.05)
	_body.position.y = -0.2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.78, 0.32)
	m.metallic = 1.0
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.25)
	m.emission_energy_multiplier = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body.material_override = m
	add_child(_body)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 0.7
	l.omni_range = 2.2
	add_child(l)

func _process(delta: float) -> void:
	_t += delta
	rotation.y += delta * 1.6
	_body.position.y = -0.2 + sin(_t * 2.0) * 0.06
