class_name MeshKit
extends RefCounted
# Procedural mesh helpers for the Rue Saint-Paul slice. One SurfaceTool per
# material slot; geometry is emitted in a "facade frame" (u along the facade,
# y up, d outward toward the street) or in world space, then committed to a
# single multi-surface ArrayMesh.

const UP := Vector3.UP

var _tools := {}
var origin := Vector3.ZERO
var axis_u := Vector3.RIGHT
var axis_n := Vector3.BACK

func st(slot: String) -> SurfaceTool:
	if not _tools.has(slot):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[slot] = s
	return _tools[slot]

func set_frame(o: Vector3, outward: Vector3) -> void:
	origin = o
	axis_n = outward.normalized()
	axis_u = UP.cross(axis_n).normalized()

func p(u: float, y: float, d: float) -> Vector3:
	return origin + axis_u * u + UP * y + axis_n * d

# Godot treats clockwise triangles as front-facing; orient to the given normal.
func tri(slot: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var s := st(slot)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	s.set_normal(n)
	s.add_vertex(a)
	s.set_normal(n)
	s.add_vertex(b)
	s.set_normal(n)
	s.add_vertex(c)

func quad(slot: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	tri(slot, a, b, c, n)
	tri(slot, a, c, d, n)

# Quad with full vertex data (glass panes, emissive strips): corners a..d go
# top-left, top-right, bottom-right, bottom-left as seen from the front.
func quad_uv(slot: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		uv2: Vector2, col: Color) -> void:
	var s := st(slot)
	var verts := [a, b, c, a, c, d]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	if (b - a).cross(c - a).dot(n) > 0.0:
		verts = [a, c, b, a, d, c]
		uvs = [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
	for i in 6:
		s.set_normal(n)
		s.set_uv(uvs[i])
		s.set_uv2(uv2)
		s.set_color(col)
		s.add_vertex(verts[i])

# Axis-aligned box in the facade frame. `back` = also emit the -n face.
func fbox(slot: String, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, back := false) -> void:
	var U := axis_u
	var N := axis_n
	quad(slot, p(u0, y1, d1), p(u1, y1, d1), p(u1, y0, d1), p(u0, y0, d1), N)            # front
	quad(slot, p(u0, y1, d0), p(u1, y1, d0), p(u1, y1, d1), p(u0, y1, d1), UP)           # top
	quad(slot, p(u0, y0, d0), p(u1, y0, d0), p(u1, y0, d1), p(u0, y0, d1), -UP)          # bottom
	quad(slot, p(u0, y0, d0), p(u0, y1, d0), p(u0, y1, d1), p(u0, y0, d1), -U)           # left
	quad(slot, p(u1, y0, d0), p(u1, y1, d0), p(u1, y1, d1), p(u1, y0, d1), U)            # right
	if back:
		quad(slot, p(u0, y1, d0), p(u1, y1, d0), p(u1, y0, d0), p(u0, y0, d0), -N)

# Oriented world box (props, poles, wires).
func wbox(slot: String, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var bx := xf.basis.x.normalized()
	var by := xf.basis.y.normalized()
	var bz := xf.basis.z.normalized()
	quad(slot, c.call(-1, 1, 1), c.call(1, 1, 1), c.call(1, -1, 1), c.call(-1, -1, 1), bz)
	quad(slot, c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, -1, -1), c.call(-1, -1, -1), -bz)
	quad(slot, c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(-1, 1, 1), by)
	quad(slot, c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, -1, 1), c.call(-1, -1, 1), -by)
	quad(slot, c.call(1, -1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(1, -1, 1), bx)
	quad(slot, c.call(-1, -1, -1), c.call(-1, 1, -1), c.call(-1, 1, 1), c.call(-1, -1, 1), -bx)

# Surface of revolution around xf's local Y. profile: Array of Vector2(radius, y).
# ribs > 0 adds `ribs` raised vertical ribs (dome ribs, fluted columns).
func lathe(slot: String, xf: Transform3D, profile: Array, segments := 32, ribs := 0, rib_amp := 0.0) -> void:
	var s := st(slot)
	var rad := func(r: float, ang: float) -> float:
		if ribs <= 0:
			return r
		return r * (1.0 + rib_amp * pow(abs(cos(ang * ribs * 0.5)), 24.0))
	for k in profile.size() - 1:
		var a2: Vector2 = profile[k]
		var b2: Vector2 = profile[k + 1]
		var dr := b2.x - a2.x
		var dy := b2.y - a2.y
		var n2 := Vector2(dy, -dr).normalized()
		for i in segments:
			var t0 := TAU * float(i) / segments
			var t1 := TAU * float(i + 1) / segments
			var pa0 := xf * Vector3(cos(t0) * rad.call(a2.x, t0), a2.y, sin(t0) * rad.call(a2.x, t0))
			var pa1 := xf * Vector3(cos(t1) * rad.call(a2.x, t1), a2.y, sin(t1) * rad.call(a2.x, t1))
			var pb0 := xf * Vector3(cos(t0) * rad.call(b2.x, t0), b2.y, sin(t0) * rad.call(b2.x, t0))
			var pb1 := xf * Vector3(cos(t1) * rad.call(b2.x, t1), b2.y, sin(t1) * rad.call(b2.x, t1))
			var n0 := (xf.basis * Vector3(cos(t0) * n2.x, n2.y, sin(t0) * n2.x)).normalized()
			var n1 := (xf.basis * Vector3(cos(t1) * n2.x, n2.y, sin(t1) * n2.x)).normalized()
			var nm := (n0 + n1).normalized()
			# keep winding consistent with the outward normal
			var flip := (pa1 - pa0).cross(pb0 - pa0).dot(nm) > 0.0
			var tris := [[pa0, n0, pa1, n1, pb1, n1], [pa0, n0, pb1, n1, pb0, n0]]
			for tr in tris:
				var order := [0, 2, 4] if not flip else [0, 4, 2]
				for o in order:
					s.set_normal(tr[o + 1])
					s.add_vertex(tr[o])

func commit(materials: Dictionary, only: Array = [], exclude: Array = []) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for slot in _tools.keys():
		if (not only.is_empty() and not only.has(slot)) or exclude.has(slot):
			continue
		var s: SurfaceTool = _tools[slot]
		s.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(slot))
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)
	return mesh

func is_empty() -> bool:
	return _tools.is_empty()
