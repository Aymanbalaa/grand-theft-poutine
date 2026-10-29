class_name SliceBuilding
extends RefCounted
# One Old-Montréal row building from a spec dictionary:
#   origin (Vector3 on the facade line at ground), outward (Vector3), width,
#   floors, style ("greystone" | "brick" | "french" | "victorian"),
#   roof ("flat" | "mansard" | "gable"), seed, depth,
#   shop (null or {name, font, sign, kind, awning}), frame_col, cornice_col
# Emits one MeshInstance3D (multi-surface) + collision + sign labels + shop
# light into `parent`. Windows are real openings with reveals, frames,
# muntins and interior-mapped glass.

const GF_H := 4.3
const FL_H := 3.35

var kit := MeshKit.new()
var spec: Dictionary
var rng := RandomNumberGenerator.new()
var W := 10.0
var H := 12.0           # top of the wall (cornice line)
var depth := 12.0
var labels: Array[Node3D] = []
var lights: Array[Node3D] = []
var anchors := {}       # named points for props (door, lantern spots, ...)

func _init(s: Dictionary) -> void:
	spec = s
	rng.seed = int(s.get("seed", 1))
	W = s["width"]
	depth = s.get("depth", 12.0)
	kit.set_frame(s["origin"], s["outward"])
	H = GF_H + FL_H * (int(s["floors"]) - 1) + 0.5

func style() -> String:
	return spec["style"]

func wall_slot() -> String:
	return "wall_" + style()

func trim_slot() -> String:
	return "trim_brick" if style() == "brick" else "trim"

# ---------------------------------------------------------------- facade

func build() -> void:
	var openings: Array = []   # [u0, u1, y0, y1, depth, kind, seed]
	var nb := maxi(2, int(round(W / (2.6 if style() != "french" else 3.0))))
	var bw := W / nb
	var shop = spec.get("shop")
	var win_w := 1.05 if style() != "french" else 0.95
	var win_h := 2.05 if style() != "french" else 1.55
	if style() == "victorian":
		win_w = 1.15
		win_h = 2.2

	# Ground floor
	if shop != null:
		var door_bay := int(rng.randi_range(0, nb - 1))
		for b in nb:
			var c := bw * (b + 0.5)
			var hw := bw * 0.5 - 0.32
			if b == door_bay:
				openings.append([c - 0.65, c + 0.65, 0.0, 3.05, 0.55, "door_shop", rng.randf()])
			else:
				openings.append([c - hw, c + hw, 0.55, 3.05, 0.32, "shopwin", rng.randf()])
	else:
		var door_bay := int(rng.randi_range(0, nb - 1))
		for b in nb:
			var c := bw * (b + 0.5)
			if b == door_bay:
				openings.append([c - 0.62, c + 0.62, 0.0, 3.2, 0.45, "door", rng.randf()])
			else:
				openings.append([c - win_w * 0.5, c + win_w * 0.5, 1.15, 1.15 + win_h, 0.3, "win", rng.randf()])
	anchors["door_bay_u"] = 0.0
	# Upper floors
	for f in range(1, int(spec["floors"])):
		var base := GF_H + FL_H * (f - 1)
		var wh := win_h * (0.92 if f == int(spec["floors"]) - 1 else 1.0)
		for b in nb:
			var c := bw * (b + 0.5)
			openings.append([c - win_w * 0.5, c + win_w * 0.5, base + 0.95, base + 0.95 + wh, 0.3, "win", rng.randf()])

	_wall_with_openings(openings)
	for o in openings:
		_opening(o)
	_string_course()
	_cornice()
	_party_walls()
	match spec["roof"]:
		"mansard":
			_mansard(nb, bw)
		"gable":
			_gable(nb, bw)
		_:
			_flat_roof()
	if shop != null:
		_storefront_dressing(shop)

func _wall_with_openings(openings: Array) -> void:
	var us := [0.0, W]
	var ys := [0.0, H]
	for o in openings:
		us.append_array([o[0], o[1]])
		ys.append_array([o[2], o[3]])
	us.sort()
	ys.sort()
	for i in us.size() - 1:
		if us[i + 1] - us[i] < 1e-4:
			continue
		for j in ys.size() - 1:
			if ys[j + 1] - ys[j] < 1e-4:
				continue
			var cu: float = (us[i] + us[i + 1]) * 0.5
			var cy: float = (ys[j] + ys[j + 1]) * 0.5
			var hole := false
			for o in openings:
				if cu > o[0] and cu < o[1] and cy > o[2] and cy < o[3]:
					hole = true
					break
			if hole:
				continue
			var slot := wall_slot()
			if cy < 0.55 and spec.get("shop") != null:
				slot = trim_slot()  # stone plinth under the shop windows
			kit.quad(slot, kit.p(us[i], ys[j + 1], 0), kit.p(us[i + 1], ys[j + 1], 0),
				kit.p(us[i + 1], ys[j], 0), kit.p(us[i], ys[j], 0), kit.axis_n)

func _opening(o: Array) -> void:
	var u0: float = o[0]
	var u1: float = o[1]
	var y0: float = o[2]
	var y1: float = o[3]
	var dd: float = o[4]
	var kind: String = o[5]
	var sd: float = o[6]
	var U := kit.axis_u
	var N := kit.axis_n
	var rev := trim_slot() if style() != "french" else wall_slot()
	# reveals
	kit.quad(rev, kit.p(u0, y0, 0), kit.p(u0, y1, 0), kit.p(u0, y1, -dd), kit.p(u0, y0, -dd), U)
	kit.quad(rev, kit.p(u1, y0, 0), kit.p(u1, y1, 0), kit.p(u1, y1, -dd), kit.p(u1, y0, -dd), -U)
	kit.quad(rev, kit.p(u0, y1, 0), kit.p(u1, y1, 0), kit.p(u1, y1, -dd), kit.p(u0, y1, -dd), -Vector3.UP)
	if y0 > 0.01:
		kit.quad(rev, kit.p(u0, y0, 0), kit.p(u1, y0, 0), kit.p(u1, y0, -dd), kit.p(u0, y0, -dd), Vector3.UP)
	var gd := -dd
	var shop := kind.begins_with("shop") or kind == "door_shop"
	if kind == "door":
		_door(u0, u1, y0, y1, gd)
		return
	if kind == "door_shop":
		# glazed door: wood lower panel, glass above, transom
		kit.fbox("frame", u0, u1, 0.0, 1.0, gd, gd + 0.06, false)
		_glass(u0 + 0.08, u1 - 0.08, 1.0, y1 - 0.5, gd + 0.02, sd, true)
		_glass(u0 + 0.08, u1 - 0.08, y1 - 0.42, y1 - 0.06, gd + 0.02, sd + 0.3, true)
		_frame_bars(u0, u1, 1.0, y1, gd, 0.08, [y1 - 0.46], [], 0.06)
		anchors["door"] = kit.p((u0 + u1) * 0.5, 0.0, 0.2)
		return
	_glass(u0, u1, y0, y1, gd + 0.02, sd, shop)
	if shop:
		_frame_bars(u0, u1, y0, y1, gd, 0.09, [y1 - 0.55], [(u0 + u1) * 0.5], 0.07)
	else:
		# casement: centre mullion, transom, 2 muntins per leaf
		var hs := [y1 - 0.42, y0 + (y1 - 0.42 - y0) * 0.5]
		_frame_bars(u0, u1, y0, y1, gd, 0.07, hs, [(u0 + u1) * 0.5], 0.05)
	_window_trim(u0, u1, y0, y1, shop)

func _glass(u0: float, u1: float, y0: float, y1: float, d: float, sd: float, shop: bool) -> void:
	kit.quad_uv("glass", kit.p(u0, y1, d), kit.p(u1, y1, d), kit.p(u1, y0, d), kit.p(u0, y0, d),
		kit.axis_n, Vector2(u1 - u0, y1 - y0), Color(sd, 1.0 if shop else 0.0, 0.0))

func _frame_bars(u0: float, u1: float, y0: float, y1: float, d: float, t: float, hs: Array, vs: Array, mt: float) -> void:
	var f0 := d
	var f1 := d + 0.07
	kit.fbox("frame", u0, u1, y1 - t, y1, f0, f1)
	kit.fbox("frame", u0, u1, y0, y0 + t, f0, f1 + 0.02)
	kit.fbox("frame", u0, u0 + t, y0, y1, f0, f1)
	kit.fbox("frame", u1 - t, u1, y0, y1, f0, f1)
	for h in hs:
		kit.fbox("frame", u0, u1, h - mt * 0.5, h + mt * 0.5, f0, f1)
	for v in vs:
		kit.fbox("frame", v - mt * 0.5, v + mt * 0.5, y0, y1, f0, f1)

func _door(u0: float, u1: float, y0: float, y1: float, gd: float) -> void:
	var top := y1 - 0.7
	# two wooden leaves with raised panels + fanlight
	var mid := (u0 + u1) * 0.5
	kit.fbox("door", u0, mid - 0.01, 0.0, top, gd, gd + 0.06)
	kit.fbox("door", mid + 0.01, u1, 0.0, top, gd, gd + 0.06)
	for leaf in [[u0, mid], [mid, u1]]:
		var a: float = leaf[0] + 0.1
		var b: float = leaf[1] - 0.1
		kit.fbox("door", a, b, 0.25, top * 0.45, gd + 0.06, gd + 0.09)
		kit.fbox("door", a, b, top * 0.52, top - 0.2, gd + 0.06, gd + 0.09)
	_glass(u0, u1, top + 0.06, y1, gd + 0.02, rng.randf(), false)
	_frame_bars(u0, u1, top, y1, gd, 0.07, [], [mid], 0.04)
	kit.fbox(trim_slot(), u0 - 0.1, u1 + 0.1, -0.02, 0.18, -0.5, 0.25)  # stone step
	anchors["door"] = kit.p(mid, 0.0, 0.4)

func _window_trim(u0: float, u1: float, y0: float, y1: float, shop: bool) -> void:
	var t := trim_slot()
	if shop:
		return
	match style():
		"greystone":
			kit.fbox(t, u0 - 0.16, u0, y0, y1, 0.0, 0.06)
			kit.fbox(t, u1, u1 + 0.16, y0, y1, 0.0, 0.06)
			kit.fbox(t, u0 - 0.22, u1 + 0.22, y1, y1 + 0.3, 0.0, 0.09)
			kit.fbox(t, (u0 + u1) * 0.5 - 0.13, (u0 + u1) * 0.5 + 0.13, y1 - 0.06, y1 + 0.38, 0.0, 0.13)
			kit.fbox(t, u0 - 0.14, u1 + 0.14, y0 - 0.14, y0, 0.0, 0.16)
		"brick":
			kit.fbox(t, u0 - 0.12, u1 + 0.12, y1, y1 + 0.26, 0.0, 0.05)
			kit.fbox(t, u0 - 0.12, u1 + 0.12, y0 - 0.12, y0, 0.0, 0.13)
		"victorian":
			kit.fbox(t, u0 - 0.15, u0, y0, y1, 0.0, 0.07)
			kit.fbox(t, u1, u1 + 0.15, y0, y1, 0.0, 0.07)
			kit.fbox(t, u0 - 0.3, u1 + 0.3, y1 + 0.02, y1 + 0.2, 0.0, 0.1)
			kit.fbox("cornice", u0 - 0.34, u1 + 0.34, y1 + 0.2, y1 + 0.32, 0.0, 0.24)
			kit.fbox(t, u0 - 0.15, u1 + 0.15, y0 - 0.13, y0, 0.0, 0.15)
			for uu in [u0 - 0.24, u1 + 0.12]:
				kit.fbox(t, uu, uu + 0.12, y0 - 0.35, y0 - 0.13, 0.0, 0.11)
		"french":
			# open wooden shutters folded against the wall
			var hw := (u1 - u0) * 0.5
			kit.fbox("shutter", u0 - hw - 0.04, u0 - 0.04, y0, y1, 0.0, 0.04)
			kit.fbox("shutter", u1 + 0.04, u1 + hw + 0.04, y0, y1, 0.0, 0.04)
			for k in 4:
				var yy := y0 + (y1 - y0) * (k + 0.5) / 4.0
				kit.fbox("shutter", u0 - hw - 0.02, u0 - 0.06, yy - 0.03, yy + 0.03, 0.04, 0.06)
				kit.fbox("shutter", u1 + 0.06, u1 + hw + 0.02, yy - 0.03, yy + 0.03, 0.04, 0.06)
			kit.fbox(t, u0 - 0.06, u1 + 0.06, y0 - 0.08, y0, 0.0, 0.1)

func _string_course() -> void:
	var t := trim_slot()
	if style() == "french":
		return
	kit.fbox(t, 0.0, W, GF_H - 0.3, GF_H - 0.05, 0.0, 0.08)

func _cornice() -> void:
	match style():
		"french":
			kit.fbox("cornice", -0.05, W + 0.05, H - 0.2, H, 0.0, 0.28)
			return
		"brick", "victorian", "greystone":
			pass
	var c := "cornice"
	kit.fbox(trim_slot(), 0.0, W, H - 0.62, H - 0.1, 0.0, 0.05)      # frieze
	kit.fbox(c, 0.0, W, H - 0.1, H + 0.02, 0.0, 0.14)
	var n := int(W / 0.55)
	for i in n:
		var u := (i + 0.5) * W / n
		kit.fbox(c, u - 0.06, u + 0.06, H - 0.42, H + 0.02, 0.0, 0.42)  # modillions
	if style() == "victorian":
		var nb := int(W / 2.2)
		for i in nb + 1:
			var u := clampf(i * W / nb, 0.2, W - 0.2)
			kit.fbox(c, u - 0.14, u + 0.14, H - 0.9, H + 0.02, 0.0, 0.5)  # big brackets
	kit.fbox(c, -0.05, W + 0.05, H + 0.02, H + 0.26, 0.0, 0.55)        # corona
	kit.fbox(c, -0.08, W + 0.08, H + 0.26, H + 0.34, 0.0, 0.64)        # cap

func _party_walls() -> void:
	var top := H + 0.34
	var U := kit.axis_u
	kit.quad("rubble", kit.p(0, top, 0), kit.p(0, top, -depth), kit.p(0, 0, -depth), kit.p(0, 0, 0), -U)
	kit.quad("rubble", kit.p(W, top, 0), kit.p(W, top, -depth), kit.p(W, 0, -depth), kit.p(W, 0, 0), U)

func _flat_roof() -> void:
	var top := H + 0.34
	kit.quad("roofflat", kit.p(0, top, 0), kit.p(W, top, 0), kit.p(W, top, -depth), kit.p(0, top, -depth), Vector3.UP)
	_chimneys(top)

func _chimneys(top: float) -> void:
	for u in [0.45, W - 0.45]:
		if rng.randf() < 0.75:
			var d0 := -rng.randf_range(2.0, depth - 3.0)
			kit.fbox("rubble", u - 0.45, u + 0.45, top - 0.5, top + 1.6, d0 - 1.3, d0, true)
			kit.fbox("trim", u - 0.52, u + 0.52, top + 1.6, top + 1.72, d0 - 1.37, d0 + 0.07, true)
			for k in 3:
				var cu: float = u - 0.3 + k * 0.3
				kit.fbox("pots", cu - 0.07, cu + 0.07, top + 1.72, top + 2.0, d0 - 0.72, d0 - 0.58, true)

func _mansard(nb: int, bw: float) -> void:
	var y0 := H + 0.34
	var rise := 3.3
	var run := 1.5
	var y1 := y0 + rise
	var U := kit.axis_u
	var N := kit.axis_n
	var sn := (N * rise + Vector3.UP * run).normalized()
	kit.quad("slate", kit.p(0, y0, 0.1), kit.p(W, y0, 0.1), kit.p(W, y1, -run), kit.p(0, y1, -run), sn)
	kit.quad("roofflat", kit.p(0, y1, -run), kit.p(W, y1, -run), kit.p(W, y1, -depth), kit.p(0, y1, -depth), Vector3.UP)
	# side gables of the mansard
	for side in [[0.0, -U], [W, U]]:
		var u: float = side[0]
		var sdn: Vector3 = side[1]
		kit.quad("rubble", kit.p(u, y1, -run), kit.p(u, y1, -depth), kit.p(u, y0, -depth), kit.p(u, y0, 0.1), sdn)
	kit.fbox("cornice", -0.05, W + 0.05, y1 - 0.05, y1 + 0.12, -run - 0.1, -run + 0.12)  # curb roll
	# dormers
	for b in nb:
		var c := bw * (b + 0.5)
		var dw := 1.25
		var a := c - dw * 0.5
		var e := c + dw * 0.5
		var dy0 := y0 + 0.45
		var dy1 := y0 + 2.35
		var front := -0.25
		var gw := 0.82
		kit.fbox("cornice", a, e, dy0, dy1, -1.6, front)
		# window opening rendered as an inset pane + frame
		_glass(c - gw * 0.5, c + gw * 0.5, dy0 + 0.22, dy1 - 0.18, front + 0.005, rng.randf(), false)
		_frame_bars(c - gw * 0.5, c + gw * 0.5, dy0 + 0.22, dy1 - 0.18, front + 0.005, 0.06, [dy0 + 0.22 + (dy1 - dy0 - 0.4) * 0.55], [c], 0.04)
		# little pediment roof
		var r0 := kit.p(a - 0.12, dy1, front + 0.12)
		var r1 := kit.p(e + 0.12, dy1, front + 0.12)
		var rp := kit.p(c, dy1 + 0.55, front + 0.12)
		kit.tri("cornice", r0, r1, rp, N)
		var back := -1.6
		var l0 := kit.p(a - 0.12, dy1, back)
		var l1 := kit.p(e + 0.12, dy1, back)
		var lp := kit.p(c, dy1 + 0.55, back)
		var ln := (kit.p(c, dy1 + 0.55, 0) - kit.p(a, dy1, 0)).cross(N).normalized()
		if ln.dot(Vector3.UP) < 0:
			ln = -ln
		kit.quad("cornice", r0, rp, lp, l0, (ln - U * 0.0).normalized())
		var rn := (kit.p(e, dy1, 0) - kit.p(c, dy1 + 0.55, 0)).cross(N).normalized()
		if rn.dot(Vector3.UP) < 0:
			rn = -rn
		kit.quad("cornice", rp, r1, l1, lp, rn)
		kit.quad("cornice", r0, r1, l1, l0, -Vector3.UP)
	_chimneys(y1)

func _gable(nb: int, bw: float) -> void:
	var y0 := H
	var half := depth * 0.5
	var rise := half * 1.05
	var U := kit.axis_u
	var N := kit.axis_n
	var sn := (N * rise + Vector3.UP * half).normalized()
	kit.quad("slate", kit.p(-0.05, y0, 0.3), kit.p(W + 0.05, y0, 0.3), kit.p(W + 0.05, y0 + rise, -half), kit.p(-0.05, y0 + rise, -half), sn)
	var bn := (-N * rise + Vector3.UP * half).normalized()
	kit.quad("slate", kit.p(-0.05, y0 + rise, -half), kit.p(W + 0.05, y0 + rise, -half), kit.p(W + 0.05, y0, -depth), kit.p(-0.05, y0, -depth), bn)
	# firewalls (coupe-feu): gable end walls standing proud of the roof
	for side in [[0.0, -1.0], [W, 1.0]]:
		var u: float = side[0]
		var s: float = side[1]
		var ui := u - s * 0.45
		for uu in [u, ui]:
			var nn := U * (s if uu == u else -s)
			kit.quad("rubble", kit.p(uu, y0 + 0.35, 0.05), kit.p(uu, y0 + rise + 0.35, -half), kit.p(uu, y0 + rise + 0.35, -half - 0.01), kit.p(uu, y0, 0.05), nn)
			kit.tri("rubble", kit.p(uu, y0 + 0.35, 0.05), kit.p(uu, y0 + rise + 0.35, -half), kit.p(uu, y0, -depth + 0.05), nn)
			kit.tri("rubble", kit.p(uu, y0 + 0.35, 0.05), kit.p(uu, y0, 0.05), kit.p(uu, y0, -depth + 0.05), nn)
		# coping along the firewall slope
		var a := kit.p(minf(u, ui), y0 + 0.35, 0.05)
		var steps := 6
		for k in steps:
			var t0 := float(k) / steps
			var t1 := float(k + 1) / steps
			var dd0 := lerpf(0.05, -half, t0)
			var dd1 := lerpf(0.05, -half, t1)
			var yy := lerpf(y0 + 0.35, y0 + rise + 0.35, t1)
			kit.fbox("trim", minf(u, ui) - 0.04, maxf(u, ui) + 0.04, yy - 0.1, yy + 0.05, dd1, dd0, true)
		# chimney at the top of each firewall
		kit.fbox("rubble", minf(u, ui) - 0.1, maxf(u, ui) + 0.1, y0 + rise - 0.4, y0 + rise + 1.7, -half - 0.7, -half + 0.7, true)
		kit.fbox("trim", minf(u, ui) - 0.16, maxf(u, ui) + 0.16, y0 + rise + 1.7, y0 + rise + 1.82, -half - 0.76, -half + 0.76, true)
	# small roof dormers
	for b in nb:
		if rng.randf() < 0.3:
			continue
		var c := bw * (b + 0.5)
		var t := 0.3
		var dy0 := y0 + rise * t
		var df := lerpf(0.3, -half, t) + 0.3
		kit.fbox("cornice", c - 0.55, c + 0.55, dy0, dy0 + 1.35, df - 1.6, df)
		_glass(c - 0.35, c + 0.35, dy0 + 0.15, dy0 + 1.15, df + 0.005, rng.randf(), false)
		_frame_bars(c - 0.35, c + 0.35, dy0 + 0.15, dy0 + 1.15, df + 0.005, 0.05, [dy0 + 0.65], [c], 0.035)
		var r0 := kit.p(c - 0.65, dy0 + 1.35, df + 0.1)
		var r1 := kit.p(c + 0.65, dy0 + 1.35, df + 0.1)
		var rp := kit.p(c, dy0 + 1.8, df + 0.1)
		kit.tri("slate", r0, r1, rp, N)
		var l0 := kit.p(c - 0.65, dy0 + 1.35, df - 1.6)
		var l1 := kit.p(c + 0.65, dy0 + 1.35, df - 1.6)
		var lp := kit.p(c, dy0 + 1.8, df - 1.6)
		kit.quad("slate", r0, rp, lp, l0, (Vector3.UP - U).normalized())
		kit.quad("slate", rp, r1, l1, lp, (Vector3.UP + U).normalized())

# ---------------------------------------------------------------- shop

func _storefront_dressing(shop: Dictionary) -> void:
	# sign band (fascia) with moulded cap, across the ground floor
	var y0 := 3.2
	var y1 := 3.95
	kit.fbox("sign", 0.25, W - 0.25, y0, y1, 0.0, 0.14)
	kit.fbox("cornice", 0.15, W - 0.15, y1, y1 + 0.1, 0.0, 0.24)
	kit.fbox("cornice", 0.2, W - 0.2, y0 - 0.08, y0, 0.0, 0.18)
	# pilasters framing the storefront
	for u in [0.0, W - 0.3]:
		kit.fbox("sign", u, u + 0.3, 0.0, y0 - 0.08, 0.0, 0.1)
	var lab := Label3D.new()
	lab.text = shop["name"]
	lab.font = load(shop.get("font", "res://assets/slice/fonts/PlayfairDisplay.ttf"))
	lab.font_size = 96
	lab.outline_size = 0
	lab.pixel_size = 0.0042
	lab.modulate = shop.get("text_col", Color(1.0, 0.86, 0.55))
	lab.shaded = false
	lab.double_sided = false
	lab.width = (W - 0.9) / lab.pixel_size
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	var lab_pos := kit.p(W * 0.5, (y0 + y1) * 0.5, 0.15)
	lab.transform = Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n), lab_pos)
	var fit: float = clampf((W - 1.2) / (0.55 * float(String(shop["name"]).length()) * 0.42), 0.6, 1.0)
	lab.scale = Vector3.ONE * fit
	labels.append(lab)
	# warm interior glow spilling onto the sidewalk
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.74, 0.46)
	l.light_energy = 2.6
	l.omni_range = 6.5
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	l.position = kit.p(W * 0.5, 2.0, -0.9)
	lights.append(l)
	# sign lamps: two gooseneck spots washing the fascia
	for u in [W * 0.28, W * 0.72]:
		kit.wbox("metal", Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n), kit.p(u, y1 + 0.18, 0.35)), Vector3(0.05, 0.05, 0.7))
		kit.wbox("bulb_cool", Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n), kit.p(u, y1 + 0.12, 0.68)), Vector3(0.12, 0.05, 0.12))
	if shop.get("awning", false):
		_awning(shop)
	if shop.get("blade", "") != "":
		_blade_sign(shop)

func _awning(shop: Dictionary) -> void:
	var a := kit.p(0.4, 3.15, 0.05)
	var b := kit.p(W - 0.4, 3.15, 0.05)
	var c := kit.p(W - 0.4, 2.55, 1.7)
	var d := kit.p(0.4, 2.55, 1.7)
	var n := (b - a).cross(d - a).normalized()
	if n.dot(Vector3.UP) < 0:
		n = -n
	kit.quad_uv("awning", a, b, c, d, n, Vector2(W - 0.8, 1.8), Color(1, 1, 1))
	kit.quad_uv("awning", a, d, c, b, -n, Vector2(W - 0.8, 1.8), Color(1, 1, 1))
	# valance
	var e := kit.p(W - 0.4, 2.3, 1.7)
	var f := kit.p(0.4, 2.3, 1.7)
	kit.quad_uv("awning", d, c, e, f, kit.axis_n, Vector2(W - 0.8, 0.25), Color(1, 1, 1))
	kit.quad_uv("awning", c, d, f, e, -kit.axis_n, Vector2(W - 0.8, 0.25), Color(1, 1, 1))
	for u in [0.4, W - 0.4]:
		kit.wbox("metal", Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n), kit.p(u, 2.85, 0.85)), Vector3(0.03, 0.03, 1.75))

func _blade_sign(shop: Dictionary) -> void:
	var u := 0.6 if rng.randf() < 0.5 else W - 0.6
	var bas := Basis(kit.axis_n, Vector3.UP, -kit.axis_u)  # board plane faces along the street
	kit.wbox("metal", Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n), kit.p(u, 5.0, 0.6)), Vector3(0.04, 0.04, 1.2))
	kit.wbox("metal", Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n).rotated(kit.axis_u, -0.6), kit.p(u, 4.75, 0.45)), Vector3(0.03, 0.03, 0.75))
	var center := kit.p(u, 4.45, 0.75)
	kit.wbox("sign", Transform3D(bas, center), Vector3(0.95, 0.75, 0.05))
	for k in [1.0, -1.0]:
		var lab := Label3D.new()
		lab.text = shop["blade"]
		lab.font = load(shop.get("font", "res://assets/slice/fonts/PlayfairDisplay.ttf"))
		lab.font_size = 64
		lab.pixel_size = 0.0035
		lab.modulate = shop.get("text_col", Color(1.0, 0.86, 0.55))
		lab.shaded = false
		lab.double_sided = false
		lab.width = 0.85 / 0.0035
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var face: Vector3 = -kit.axis_u * k
		lab.transform = Transform3D(Basis(face.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, face), center + face * 0.03)
		labels.append(lab)

# ---------------------------------------------------------------- output

func make_node(materials: Dictionary, name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	# Shell (casts shadows) and fine detail (frames, glass, signs: no shadow
	# pass) are separate instances so lamp shadow maps stay cheap.
	var detail := ["glass", "frame", "door", "shutter", "sign", "bulb_cool", "metal", "awning", "pots"]
	var uvo := Vector2(rng.randf() * 7.0, rng.randf() * 7.0)
	for part in [["Mesh", [], detail], ["Detail", detail, []]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = kit.commit(materials, part[1], part[2])
		mi.set_instance_shader_parameter("tint", spec.get("tint", Vector3.ONE))
		mi.set_instance_shader_parameter("uv_offset", uvo)
		if part[0] == "Detail":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W, H, depth)
	cs.shape = box
	var center := kit.p(W * 0.5, H * 0.5, -depth * 0.5)
	cs.transform = Transform3D(Basis(kit.axis_u, Vector3.UP, kit.axis_n), center)
	body.add_child(cs)
	root.add_child(body)
	for l in labels:
		root.add_child(l)
	for l in lights:
		root.add_child(l)
	return root
