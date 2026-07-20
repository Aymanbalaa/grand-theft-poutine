extends SceneTree
# Validates committed car models load and reports their bounding boxes.

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
	quit(0)
