class_name SlicePedestrians
extends Node3D
# Foot traffic for the quarter. Walkers pace sidewalk segments (many under
# umbrellas), idlers window-shop. They step around the player, stagger when
# body-checked, flee when punched, and one of them can turn pickpocket: the
# thief sprints along the street graph away from the player until caught.

signal thief_caught(pos: Vector3)
signal thief_escaped

const IDS := ["woman_red", "woman_green", "woman_white", "man_tshirt", "adventurer"]
const UMBRELLA_COLS := [Color(0.03, 0.03, 0.035), Color(0.05, 0.08, 0.18), Color(0.4, 0.05, 0.05), Color(0.08, 0.15, 0.1), Color(0.55, 0.45, 0.2)]
const CURB_H := 0.15
const THIEF_SPEED := 4.7

var rng := RandomNumberGenerator.new()
var walkers: Array[Dictionary] = []
var player: Node3D
var segments: Array = []        # [a: Vector3, b: Vector3] sidewalk centre lines
var graph := {}                 # node name -> Vector3 (road centre)
var edges := {}                 # node name -> Array of node names
var on_road: Callable           # Vector3 -> bool
var thief: Dictionary = {}

func spawn(count: int, idlers: Array) -> void:
	rng.seed = 1535
	var total_len := 0.0
	for s in segments:
		total_len += (s[0] as Vector3).distance_to(s[1])
	for i in count:
		# pick a segment weighted by length
		var pick := rng.randf() * total_len
		var si := 0
		for k in segments.size():
			var l: float = (segments[k][0] as Vector3).distance_to(segments[k][1])
			if pick < l:
				si = k
				break
			pick -= l
		var p := SlicePerson.new()
		add_child(p)
		p.setup(IDS[rng.randi() % IDS.size()], rng.randf_range(1.62, 1.85))
		var w := {"p": p, "seg": si, "s": rng.randf(), "dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"lane": rng.randf_range(-0.45, 0.45), "speed": rng.randf_range(1.05, 1.45),
			"state": "walk", "timer": 0.0, "dodge": 0.0, "umbrella": null}
		if rng.randf() < 0.6:
			w["umbrella"] = _umbrella(p)
		walkers.append(w)
		_place_on_segment(w, 0.0)
		p.play("walk", 0.0, w["speed"] / 1.3)
		if p.anim != null:
			p.anim.seek(rng.randf(), true)
	for spot in idlers:
		var p2 := SlicePerson.new()
		add_child(p2)
		p2.setup(IDS[rng.randi() % IDS.size()], rng.randf_range(1.62, 1.82))
		p2.position = spot[0]
		p2.rotation.y = spot[1]
		p2.play("idle", 0.0, rng.randf_range(0.8, 1.1))
		if p2.anim != null:
			p2.anim.seek(rng.randf() * 2.0, true)
		walkers.append({"p": p2, "state": "idle", "timer": 0.0, "umbrella": null, "home": spot[0], "yaw": spot[1]})

func _umbrella(p: SlicePerson) -> MeshInstance3D:
	var kit := MeshKit.new()
	var prof := []
	for i in 9:
		var t := float(i) / 8.0
		prof.append(Vector2(0.55 * t + 0.0001, 0.32 * (1.0 - t * t)))
	kit.lathe("canopy", Transform3D(Basis(), Vector3.ZERO), prof, 16, 8, 0.05)
	var inner := prof.duplicate()
	inner.reverse()
	kit.lathe("canopy", Transform3D(Basis(), Vector3(0, -0.005, 0)), inner, 16, 8, 0.05)
	kit.lathe("stick", Transform3D(Basis(), Vector3.ZERO), [Vector2(0.008, -0.85), Vector2(0.008, 0.38), Vector2(0.0, 0.42)], 6)
	var m := StandardMaterial3D.new()
	m.albedo_color = UMBRELLA_COLS[rng.randi() % UMBRELLA_COLS.size()]
	m.roughness = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.04, 0.03)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit({"canopy": m, "stick": sm})
	mi.position = Vector3(0.12, 2.02, 0.08)
	mi.rotation = Vector3(0.08, 0, -0.1)
	p.add_child(mi)
	return mi

func _seg_frame(w: Dictionary) -> Array:
	var a: Vector3 = segments[w["seg"]][0]
	var b: Vector3 = segments[w["seg"]][1]
	var d := b - a
	d.y = 0
	var len := d.length()
	d = d / len
	return [a, d, Vector3(-d.z, 0, d.x), len]

func _place_on_segment(w: Dictionary, delta: float) -> void:
	var f := _seg_frame(w)
	var a: Vector3 = f[0]
	var d: Vector3 = f[1]
	var perp: Vector3 = f[2]
	var len: float = f[3]
	var p: SlicePerson = w["p"]
	var pos: Vector3 = a + d * (w["s"] * len) + perp * (w["lane"] + w["dodge"])
	var road: bool = on_road.call(pos) if on_road.is_valid() else false
	var ty := 0.02 if road else CURB_H
	pos.y = lerpf(p.position.y, ty, clampf(delta * 8.0, 0.0, 1.0)) if delta > 0.0 else ty
	p.position = pos
	var face: Vector3 = d * w["dir"]
	var target: float = atan2(face.x, face.z) + w["dodge"] * 0.4 * w["dir"]
	p.rotation.y = lerp_angle(p.rotation.y, target, clampf(delta * 6.0, 0, 1)) if delta > 0.0 else target

func _physics_process(delta: float) -> void:
	for w in walkers:
		var p: SlicePerson = w["p"]
		match w["state"]:
			"walk":
				var f := _seg_frame(w)
				w["s"] += w["dir"] * w["speed"] * delta / f[3]
				if w["s"] > 1.0 or w["s"] < 0.0:
					w["dir"] = -w["dir"]
					w["s"] = clampf(w["s"], 0.0, 1.0)
				# step aside for the player
				var want := 0.0
				if player != null:
					var rel := player.global_position - p.global_position
					rel.y = 0
					if rel.length() < 2.0:
						var side: float = rel.dot(f[2])
						want = -0.9 * signf(side) if abs(side) > 0.01 else 0.9
				w["dodge"] = lerpf(w["dodge"], want, clampf(delta * 3.0, 0, 1))
				_place_on_segment(w, delta)
			"stagger":
				w["timer"] -= delta
				if w["timer"] <= 0.0:
					_resume(w)
			"flee":
				w["timer"] -= delta
				var away: Vector3 = p.global_position - player.global_position
				away.y = 0
				if away.length() > 0.01:
					away = away.normalized()
					p.position += away * 4.0 * delta
					p.rotation.y = lerp_angle(p.rotation.y, atan2(away.x, away.z), clampf(delta * 8.0, 0, 1))
				if w["timer"] <= 0.0:
					_resume(w)
			"down":
				w["timer"] -= delta
			"thief":
				_thief_step(w, delta)

func _resume(w: Dictionary) -> void:
	var p: SlicePerson = w["p"]
	if w.has("seg"):
		w["state"] = "walk"
		# re-anchor on the segment wherever they ended up
		var f := _seg_frame(w)
		w["s"] = clampf((p.position - (f[0] as Vector3)).dot(f[1]) / f[3], 0.0, 1.0)
		w["dodge"] = 0.0
		p.play("walk", 0.3, w["speed"] / 1.3)
	else:
		w["state"] = "idle"
		p.position = w["home"]
		p.rotation.y = w["yaw"]
		p.play("idle", 0.3)
	if w["umbrella"] != null:
		(w["umbrella"] as Node3D).visible = true

# A running player body-checks walkers. Returns true when someone was knocked.
func check_bump(pos: Vector3, speed: float) -> bool:
	if speed < 3.4:
		return false
	for w in walkers:
		if w["state"] in ["walk", "idle"]:
			var p: SlicePerson = w["p"]
			var d := p.global_position - pos
			d.y = 0
			if d.length() < 0.75:
				w["state"] = "stagger"
				w["timer"] = 1.3
				p.play("hit" if p.clips.has("hit") else "idle", 0.08)
				p.position += d.normalized() * 0.5
				return true
	return false

# Player punch: hits the closest person in front within reach.
# Returns "thief", "person" or "".
func punch(pos: Vector3, facing: Vector3) -> String:
	var best: Dictionary = {}
	var best_d := 1.6
	for w in walkers:
		if w["state"] == "down":
			continue
		var d := (w["p"] as Node3D).global_position - pos
		d.y = 0
		if d.length() < best_d and (d.length() < 0.6 or d.normalized().dot(facing) > 0.3):
			best = w
			best_d = d.length()
	if best.is_empty():
		return ""
	if best.get("is_thief", false):
		_catch_thief(best)
		return "thief"
	var bp: SlicePerson = best["p"]
	bp.play("hit" if bp.clips.has("hit") else "idle", 0.05)
	best["state"] = "flee"
	best["timer"] = 3.5
	_start_running_later(best)
	return "person"

func _start_running_later(w: Dictionary) -> void:
	await get_tree().create_timer(0.35).timeout
	if w["state"] == "flee":
		(w["p"] as SlicePerson).play("run", 0.15, 1.0)

# Rolling into the thief also brings him down.
func tackle(pos: Vector3) -> bool:
	if thief.is_empty():
		return false
	var d: Vector3 = (thief["p"] as Node3D).global_position - pos
	d.y = 0
	if d.length() < 1.2:
		_catch_thief(thief)
		return true
	return false

# ------------------------------------------------------------------ thief

func start_thief(near: Vector3) -> Dictionary:
	if not thief.is_empty():
		return {}
	var cands := []
	for w in walkers:
		if w["state"] == "walk":
			var dist: float = (w["p"] as Node3D).global_position.distance_to(near)
			if dist > 9.0 and dist < 30.0:
				cands.append(w)
	if cands.is_empty():
		return {}
	var w: Dictionary = cands[rng.randi() % cands.size()]
	w["state"] = "thief"
	w["is_thief"] = true
	w["timer"] = 0.0
	w["target"] = _nearest_node((w["p"] as Node3D).global_position)
	w["prev"] = ""
	if w["umbrella"] != null:
		(w["umbrella"] as Node3D).visible = false
	var p: SlicePerson = w["p"]
	p.play("run", 0.1, THIEF_SPEED / 4.5)
	# stolen handbag + bobbing red marker
	var bag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.22, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.05, 0.08)
	mat.roughness = 0.3
	bm.material = mat
	bag.mesh = bm
	bag.position = Vector3(0.28, 0.95, 0.05)
	bag.name = "StolenBag"
	p.add_child(bag)
	var arrow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.0
	cm.height = 0.42
	cm.radial_segments = 4
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(1, 0.15, 0.1)
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.material = am
	arrow.mesh = cm
	arrow.position = Vector3(0, 2.45, 0)
	arrow.name = "ThiefArrow"
	p.add_child(arrow)
	thief = w
	return w

func thief_pos() -> Vector3:
	return (thief["p"] as Node3D).global_position if not thief.is_empty() else Vector3.INF

func _nearest_node(pos: Vector3) -> String:
	var best := ""
	var bd := INF
	for k in graph.keys():
		var d: float = (graph[k] as Vector3).distance_to(Vector3(pos.x, 0, pos.z))
		if d < bd:
			bd = d
			best = k
	return best

func _thief_step(w: Dictionary, delta: float) -> void:
	var p: SlicePerson = w["p"]
	w["timer"] += delta
	var tgt: Vector3 = graph[w["target"]]
	var to := tgt - Vector3(p.position.x, 0, p.position.z)
	if to.length() < 1.0:
		# take the onward street that keeps the most distance from the player
		var best := ""
		var bd := -INF
		for n in edges[w["target"]]:
			if n == w["prev"] and (edges[w["target"]] as Array).size() > 1:
				continue
			var d: float = (graph[n] as Vector3).distance_to(player.global_position)
			if d > bd:
				bd = d
				best = n
		w["prev"] = w["target"]
		w["target"] = best
		tgt = graph[best]
		to = tgt - Vector3(p.position.x, 0, p.position.z)
	var dir := to.normalized()
	# jink sideways a little so the chase isn't a straight line
	var side := Vector3(-dir.z, 0, dir.x) * sin(w["timer"] * 1.7) * 1.2
	p.position += (dir * THIEF_SPEED + side) * delta
	p.position.y = 0.02 if on_road.call(p.position) else CURB_H
	p.rotation.y = lerp_angle(p.rotation.y, atan2(dir.x, dir.z), clampf(delta * 10.0, 0, 1))
	var arrow := p.get_node_or_null("ThiefArrow") as Node3D
	if arrow != null:
		arrow.position.y = 2.45 + sin(w["timer"] * 6.0) * 0.08
		arrow.rotation.y += delta * 3.0

func _catch_thief(w: Dictionary) -> void:
	var p: SlicePerson = w["p"]
	w["state"] = "down"
	w["timer"] = 6.0
	p.play("death" if p.clips.has("death") else "idle", 0.05)
	_strip_thief(p)
	thief = {}
	thief_caught.emit(p.global_position)
	_get_up_later(w)

func _get_up_later(w: Dictionary) -> void:
	await get_tree().create_timer(5.5).timeout
	w["is_thief"] = false
	w.erase("target")
	_resume(w)

func _strip_thief(p: Node3D) -> void:
	for n in ["StolenBag", "ThiefArrow"]:
		var c := p.get_node_or_null(n)
		if c != null:
			c.queue_free()

func give_up_thief() -> void:
	if thief.is_empty():
		return
	var w := thief
	_strip_thief(w["p"])
	w["is_thief"] = false
	thief = {}
	# vanishes down an alley and turns up walking somewhere else
	w["seg"] = rng.randi() % segments.size()
	w["s"] = rng.randf()
	_resume(w)
	_place_on_segment(w, 0.0)
	thief_escaped.emit()
