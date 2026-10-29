class_name SlicePedestrians
extends Node3D
# Evening foot traffic: walkers loop up and down both sidewalks (many under
# umbrellas), a few idlers linger by shop windows. Lanes keep walkers apart;
# anyone who comes within reach of the player steps around them.

const IDS := ["woman_red", "woman_green", "woman_white", "man_tshirt", "adventurer"]
const UMBRELLA_COLS := [Color(0.03, 0.03, 0.035), Color(0.05, 0.08, 0.18), Color(0.4, 0.05, 0.05), Color(0.08, 0.15, 0.1), Color(0.55, 0.45, 0.2)]

var rng := RandomNumberGenerator.new()
var walkers: Array[Dictionary] = []
var player: Node3D
var z_max := 40.0
var z_min := -110.0
var cross := Vector2(-46.0, -58.0)
var face_x := 5.6
var road_half := 3.7
var curb_h := 0.15

func spawn(count: int, idlers: Array) -> void:
	rng.seed = 1535
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var lane := rng.randf_range(0.0, 1.0)
		var x := side * lerpf(road_half + 0.55, face_x - 0.5, lane)
		var z := rng.randf_range(z_min + 2.0, z_max - 2.0)
		var dirz := -1.0 if rng.randf() < 0.5 else 1.0
		var p := SlicePerson.new()
		add_child(p)
		p.setup(IDS[rng.randi() % IDS.size()], rng.randf_range(1.62, 1.85))
		p.position = Vector3(x, curb_h, z)
		p.rotation.y = 0.0 if dirz > 0 else PI
		var spd := rng.randf_range(1.05, 1.45)
		p.play("walk", 0.0, spd / 1.3)
		if p.anim != null:
			p.anim.seek(rng.randf() * 1.0, true)
		if rng.randf() < 0.6:
			_umbrella(p)
		walkers.append({"p": p, "x": x, "dir": dirz, "speed": spd, "dodge": 0.0})
	for spot in idlers:
		var p2 := SlicePerson.new()
		add_child(p2)
		p2.setup(IDS[rng.randi() % IDS.size()], rng.randf_range(1.62, 1.82))
		p2.position = spot[0]
		p2.rotation.y = spot[1]
		p2.play("idle", 0.0, rng.randf_range(0.8, 1.1))
		if p2.anim != null:
			p2.anim.seek(rng.randf() * 2.0, true)

func _umbrella(p: SlicePerson) -> void:
	var kit := MeshKit.new()
	var prof := []
	for i in 9:
		var t := float(i) / 8.0
		prof.append(Vector2(0.55 * t + 0.0001, 0.32 * (1.0 - t * t)))
	# canopy (8 ribs), both faces
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

func _physics_process(delta: float) -> void:
	for w in walkers:
		var p: SlicePerson = w["p"]
		var pos := p.position
		var dz: float = w["dir"] * w["speed"] * delta
		pos.z += dz
		# step around the player
		var tx: float = w["x"]
		if player != null:
			var rel := player.global_position - p.global_position
			rel.y = 0
			if rel.length() < 1.6 and rel.z * w["dir"] > -0.2:
				tx = w["x"] + (0.9 if rel.x < 0 else -0.9)
		pos.x = lerpf(pos.x, tx, clampf(delta * 2.5, 0, 1))
		# turn around at the ends of the street
		if pos.z > z_max or pos.z < z_min:
			w["dir"] = -w["dir"]
			pos.z += -dz * 2.0
		# step down onto the cobbles while crossing the side street
		var in_cross := pos.z < cross.x - 0.1 and pos.z > cross.y + 0.1
		pos.y = lerpf(pos.y, 0.03 if in_cross else curb_h, clampf(delta * 8.0, 0, 1))
		p.position = pos
		var target := 0.0 if w["dir"] > 0 else PI
		target += (tx - pos.x) * 0.3 * w["dir"]
		p.rotation.y = lerp_angle(p.rotation.y, target, clampf(delta * 5.0, 0, 1))
