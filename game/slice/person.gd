class_name SlicePerson
extends Node3D
# A CC0 Quaternius character normalised to a target height, with its clips
# resolved by role (idle / walk / run / punch / roll / wave) since each pack
# names them differently ("CharacterArmature|Walk", "Armature|Walking",
# "HumanArmature|Man_Walk").

const DIR := "res://assets/slice/models/people/"

var anim: AnimationPlayer
var clips := {}
var model: Node3D
var _current := ""

func setup(id: String, height := 1.75) -> SlicePerson:
	model = (load(DIR + id + ".glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		_resolve_clips()
	var skel: Skeleton3D = null
	for n in model.find_children("*", "Skeleton3D", true, false):
		skel = n
	if skel != null:
		var head := skel.find_bone("Head")
		if head >= 0:
			var rest_y := (skel.global_transform * skel.get_bone_global_rest(head)).origin.y - global_position.y
			if rest_y > 0.01:
				model.scale = Vector3.ONE * (height - 0.12) / rest_y
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_smooth((mi as MeshInstance3D).mesh)
	return self

# The CC0 characters ship flat-shaded (one normal per facet), which reads as
# faceted plastic under the street's PBR lighting. Average normals across
# vertices that share a position, once per shared mesh resource.
static var _smoothed := {}

static func _smooth(mesh: Mesh) -> void:
	var am := mesh as ArrayMesh
	if am == null or _smoothed.has(am.get_rid()):
		return
	_smoothed[am.get_rid()] = true
	var groups := {}    # quantised position -> summed normal
	var mdts: Array[MeshDataTool] = []
	for s in am.get_surface_count():
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(am, s) != OK:
			mdts.append(null)
			continue
		mdts.append(mdt)
		for v in mdt.get_vertex_count():
			var key := (mdt.get_vertex(v) * 2000.0).round()
			groups[key] = groups.get(key, Vector3.ZERO) + mdt.get_vertex_normal(v)
	var mats := []
	for s in am.get_surface_count():
		var m := am.surface_get_material(s)
		# matte cloth and skin rather than glossy plastic
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).roughness = maxf((m as StandardMaterial3D).roughness, 0.78)
			(m as StandardMaterial3D).metallic = 0.0
			(m as StandardMaterial3D).metallic_specular = 0.35
		mats.append(m)
	var names := []
	for s in am.get_surface_count():
		names.append(am.surface_get_name(s))
	am.clear_surfaces()
	for s in mdts.size():
		var mdt := mdts[s]
		if mdt == null:
			continue
		for v in mdt.get_vertex_count():
			var key := (mdt.get_vertex(v) * 2000.0).round()
			var n: Vector3 = groups[key]
			if n.length() > 0.001:
				mdt.set_vertex_normal(v, n.normalized())
		mdt.commit_to_surface(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[s])
		am.surface_set_name(am.get_surface_count() - 1, names[s])

func _resolve_clips() -> void:
	var names := anim.get_animation_list()
	var want := {
		"idle": ["idle", "man_idle", "standing"],
		"walk": ["walk", "walking", "man_walk"],
		"run": ["run", "running", "man_run"],
		"punch": ["punch_right", "punch", "man_punch"],
		"kick": ["kick_right"],
		"roll": ["roll"],
		"wave": ["wave", "man_clapping"],
		"interact": ["interact", "pickup"],
		"hit": ["hitrecieve", "hitrecieve_2"],
		"death": ["death", "man_death"],
	}
	for role in want.keys():
		for cand in want[role]:
			for n in names:
				var short := String(n).get_slice("|", String(n).get_slice_count("|") - 1).to_lower()
				if short == cand:
					clips[role] = n
					break
			if clips.has(role):
				break
	for role in ["idle", "walk", "run"]:
		if clips.has(role):
			var a := anim.get_animation(clips[role])
			a.loop_mode = Animation.LOOP_LINEAR

func play(role: String, blend := 0.2, speed := 1.0) -> void:
	if not clips.has(role) or anim == null:
		return
	if _current == role and anim.is_playing():
		anim.speed_scale = speed
		return
	_current = role
	anim.play(clips[role], blend)
	anim.speed_scale = speed

func current() -> String:
	return _current

# Hold a single frame of a clip (e.g. mid-stride of the run as an airborne
# leap pose, since the courier model ships without a jump clip).
func pose(role: String, frac: float, blend := 0.12) -> void:
	if not clips.has(role) or anim == null:
		return
	var key := role + "@pose"
	if _current == key:
		return
	_current = key
	anim.play(clips[role], blend)
	anim.seek(anim.get_animation(clips[role]).length * frac, true)
	anim.speed_scale = 0.0

# Recolour named surface materials (e.g. the shirt), duplicating so other
# instances of the same model keep theirs.
func tint(material_name: String, col: Color) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat is StandardMaterial3D and mat.resource_name == material_name:
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = col
				m.set_surface_override_material(s, dup)

func busy() -> bool:
	# one-shot clips (punch, roll, wave...) still running
	return anim != null and anim.is_playing() and not (_current in ["idle", "walk", "run"]) and not _current.ends_with("@pose")
