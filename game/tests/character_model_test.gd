extends SceneTree
# Headless load/inspection test for the CC0 rigged player character model.
# Reports the AnimationPlayer's clip names and the Skeleton3D's bone names
# so Task 2 (M9c2) can wire animation state and find the head bone for the
# tuque attachment. Also reports the native bounding box for SOURCE.md.
#
# godot_console --headless --path game --script res://tests/character_model_test.gd

const CHAR_PATH := "res://assets/models/character/character.glb"


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D()
	var n := node
	while n != null and n != ancestor:
		t = n.transform * t
		n = n.get_parent()
	return t


func _init() -> void:
	if not ResourceLoader.exists(CHAR_PATH):
		push_error("FAIL: character.glb missing at %s" % CHAR_PATH)
		quit(1)
		return
	var packed: PackedScene = load(CHAR_PATH)
	if packed == null:
		push_error("FAIL: character.glb failed to load as PackedScene")
		quit(1)
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_error("FAIL: character.glb failed to instantiate")
		quit(1)
		return
	get_root().add_child(inst)

	var anim := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips: Array = []
	if anim != null:
		clips = anim.get_animation_list()

	var sk := _find_skeleton(inst)
	var bones: Array = []
	if sk != null:
		for i in sk.get_bone_count():
			bones.append(sk.get_bone_name(i))

	print("CHARACTER OK: anim=%s clips=%s bones=%d" % [anim != null, clips, bones.size()])
	print("BONES: %s" % [bones])

	var mesh_instances := inst.find_children("*", "MeshInstance3D", true, false)
	var aabb := AABB()
	for mi in mesh_instances:
		var m := mi as MeshInstance3D
		var rel := _relative_transform(m, inst)
		aabb = aabb.merge(rel * m.get_aabb())
	print("CHARACTER SIZE: %s" % aabb.size)

	inst.queue_free()
	quit(0)
