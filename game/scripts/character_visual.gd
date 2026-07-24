extends Node3D
# Player visual: loads the CC0 rigged character model (animated by speed,
# tuque bone-attached to the head) with a procedural blocky minifig as a
# fallback when the model is absent. Parent must be a CharacterBody3D.

const MODEL_PATH := "res://assets/models/character/character.glb"
const COLORMAP_PATH := "res://assets/models/character/Textures/colormap.png"

# Tuned by screenshot (tests/screenshot.gd -> shot_onfoot_day.png / shot_onfoot_night.png):
# the model's rest/idle pose is short (chibi proportions, ~0.67 m tall at scale 1),
# so it is scaled up to a ~1.7 m standing character; MODEL_YAW picks the facing
# that matches the movement code's -Z-forward convention (see _process below).
const MODEL_SCALE := 2.5
const MODEL_YAW := PI

const IDLE_CLIP := "idle"
const WALK_CLIP := "walk"
const WALK_SPEED_THRESHOLD := 0.6

const HEAD_BONE := "head"
const TUQUE_WORLD_SIZE := Vector3(1.0, 0.5, 1.0)  # sized to this model's oversized chibi head
const HAT_BONE_OFFSET := Vector3(0.0, 0.39, 0.0)   # local to the head bone (unscaled model space)
const HEAD_Y := 1.6                                   # fallback world-space head height

const JACKET := Color(58.0 / 255.0, 74.0 / 255.0, 96.0 / 255.0)
const PANTS := Color(40.0 / 255.0, 42.0 / 255.0, 48.0 / 255.0)
const SKIN := Color(224.0 / 255.0, 172.0 / 255.0, 138.0 / 255.0)
const TUQUE := Color(176.0 / 255.0, 52.0 / 255.0, 48.0 / 255.0)

var _l_arm: Node3D
var _r_arm: Node3D
var _l_leg: Node3D
var _r_leg: Node3D
var _phase := 0.0
var _model_mode := false
var _anim: AnimationPlayer
@onready var _body := get_parent() as CharacterBody3D

func _ready() -> void:
	if ResourceLoader.exists(MODEL_PATH):
		var packed: PackedScene = load(MODEL_PATH)
		if packed != null:
			var inst := packed.instantiate()
			if inst != null:
				add_child(inst)
				var n3d := inst as Node3D
				if n3d != null:
					n3d.scale = Vector3.ONE * MODEL_SCALE
					n3d.rotation.y = MODEL_YAW
				# colormap net MUST run before _attach_tuque: it only fills
				# materials missing an albedo_texture, and the tuque box is exactly
				# such a material — running it after would tint the tuque with the colormap.
				_apply_colormap_safety_net(inst)
				_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if _anim != null:
					# glTF import leaves clips non-looping; force real looping instead of
					# relying on replay-on-finish (which only looks seamless because the
					# Kenney clips happen to author first==last frame).
					for clip in [IDLE_CLIP, WALK_CLIP]:
						var a := _anim.get_animation(clip)
						if a != null:
							a.loop_mode = Animation.LOOP_LINEAR
				_attach_tuque(inst)
				_model_mode = true
				return
	_build_procedural()

# ---- model mode helpers ----

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

# Mirrors car_visual.gd::_polish_materials (colormap safety net): a fresh
# import can drop the external-URI colormap.png (gltf/embedded_image_handling
# default), rendering the model solid white. Recursively re-assign the
# colormap on any surface material missing an albedo_texture. Matte (no
# clearcoat/metallic) since this is a character, not a car.
static func _apply_colormap_safety_net(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.albedo_texture == null:
				var tex := load(COLORMAP_PATH) as Texture2D
				if tex != null:
					mat.albedo_texture = tex
	for child in node.get_children():
		_apply_colormap_safety_net(child)

func _tuque_mesh(world_size: Vector3, local_scale: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = world_size / local_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TUQUE
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

func _attach_tuque(root: Node) -> void:
	var sk := _find_skeleton(root)
	if sk != null and HEAD_BONE != "" and sk.find_bone(HEAD_BONE) != -1:
		var hat := _tuque_mesh(TUQUE_WORLD_SIZE, MODEL_SCALE)
		var ba := BoneAttachment3D.new()
		ba.bone_name = HEAD_BONE
		sk.add_child(ba)
		ba.add_child(hat)
		hat.position = HAT_BONE_OFFSET
	else:
		var hat := _tuque_mesh(TUQUE_WORLD_SIZE, 1.0)
		hat.position = Vector3(0.0, HEAD_Y, 0.0)
		add_child(hat)

# ---- procedural fallback ----

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi

func _limb(size: Vector3, pivot_pos: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	add_child(pivot)
	_box(size, Vector3(0, -size.y / 2.0, 0), color, pivot)
	return pivot

func _build_procedural() -> void:
	_box(Vector3(0.5, 0.6, 0.3), Vector3(0, 1.15, 0), JACKET, self)   # torso
	_box(Vector3(0.3, 0.3, 0.3), Vector3(0, 1.6, 0), SKIN, self)      # head
	_box(Vector3(0.32, 0.12, 0.32), Vector3(0, 1.78, 0), TUQUE, self) # tuque
	_l_arm = _limb(Vector3(0.14, 0.55, 0.14), Vector3(-0.33, 1.42, 0), JACKET)
	_r_arm = _limb(Vector3(0.14, 0.55, 0.14), Vector3(0.33, 1.42, 0), JACKET)
	_l_leg = _limb(Vector3(0.18, 0.85, 0.18), Vector3(-0.13, 0.85, 0), PANTS)
	_r_leg = _limb(Vector3(0.18, 0.85, 0.18), Vector3(0.13, 0.85, 0), PANTS)

func _process(delta: float) -> void:
	if _body == null:
		return
	var hvel := Vector2(_body.velocity.x, _body.velocity.z)
	var speed := hvel.length()
	if speed > 0.5:
		var target_yaw := atan2(-hvel.x, -hvel.y)
		rotation.y = lerp_angle(rotation.y, target_yaw, 10.0 * delta)

	if _model_mode:
		if _anim != null:
			var want := WALK_CLIP if speed > WALK_SPEED_THRESHOLD else IDLE_CLIP
			if want != "" and _anim.current_animation != want:
				_anim.play(want)
		return

	_phase += speed * 2.2 * delta
	var amp := clampf(speed / 4.5, 0.0, 1.4) * 0.7
	var swing := sin(_phase) * amp
	if speed < 0.5:
		swing = lerpf(_l_leg.rotation.x, 0.0, 12.0 * delta)
	_l_leg.rotation.x = swing
	_r_leg.rotation.x = -swing
	_l_arm.rotation.x = -swing * 0.8
	_r_arm.rotation.x = swing * 0.8
