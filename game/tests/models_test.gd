extends SceneTree
# Validates committed car models load and reports their bounding boxes.

# Prop models (game/assets/models/props/SOURCE.md has full provenance).
# Keys recorded there as unavailable/skipped are listed here so the test
# prints a SKIP instead of failing on a path that was never sourced.
const PROP_FILES := ["tree0", "tree1", "tree2", "lamp_post", "bench", "hydrant"]
const PROP_SKIP := []  # e.g. ["hydrant"] if a future prop can't be sourced CC0

# MeshInstance3D.global_transform requires the node to be inside the live
# SceneTree (asserts and silently returns identity otherwise), which is not
# guaranteed for a node instantiated and measured within a single _init()
# call. Several props (e.g. the hydrant) apply a non-trivial scale on an
# intermediate node, so falling back to identity there would misreport their
# true world-space size. Walk local transforms up to `ancestor` instead —
# this needs no tree membership and gives the correct composite transform.
static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D()
	var n := node
	while n != null and n != ancestor:
		t = n.transform * t
		n = n.get_parent()
	return t

func _init() -> void:
	var i := 0
	while true:
		var path := "res://assets/models/cars/car%d.glb" % i
		if not ResourceLoader.exists(path):
			break
		var scene: PackedScene = load(path)
		if scene == null:
			push_error("FAIL: %s did not load" % path)
			quit(1)
			return
		var node := scene.instantiate() as Node3D
		get_root().add_child(node)
		var aabb := AABB()
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			aabb = aabb.merge(m.global_transform * m.get_aabb())
		print("MODEL %d OK size=%s" % [i, aabb.size])
		node.queue_free()
		i += 1
	if i == 0:
		push_error("FAIL: no car models found")
		quit(1)
		return
	print("MODELS OK: %d" % i)

	var prop_count := 0
	for prop_name in PROP_FILES:
		if prop_name in PROP_SKIP:
			print("PROP %s SKIP (not available CC0, see props/SOURCE.md)" % prop_name)
			continue
		var prop_path := "res://assets/models/props/%s.glb" % prop_name
		if not ResourceLoader.exists(prop_path):
			push_error("FAIL: %s did not load" % prop_path)
			quit(1)
			return
		var prop_scene: PackedScene = load(prop_path)
		if prop_scene == null:
			push_error("FAIL: %s did not load" % prop_path)
			quit(1)
			return
		var prop_node := prop_scene.instantiate() as Node3D
		get_root().add_child(prop_node)
		var mesh_instances := prop_node.find_children("*", "MeshInstance3D", true, false)
		if mesh_instances.is_empty():
			push_error("FAIL: %s has no MeshInstance3D" % prop_path)
			quit(1)
			return
		var first_mesh := (mesh_instances[0] as MeshInstance3D).mesh
		if first_mesh == null:
			push_error("FAIL: %s first MeshInstance3D has a null mesh" % prop_path)
			quit(1)
			return
		var prop_aabb := AABB()
		for mi in mesh_instances:
			var m := mi as MeshInstance3D
			var rel := _relative_transform(m, prop_node)
			prop_aabb = prop_aabb.merge(rel * m.get_aabb())
		print("PROP %s OK size=%s" % [prop_name, prop_aabb.size])
		prop_node.queue_free()
		prop_count += 1
	print("PROPS OK: %d" % prop_count)
	quit(0)
