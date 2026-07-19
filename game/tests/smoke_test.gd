extends SceneTree
# Headless smoke test: main scene loads, tiles instantiate.
# Run: tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("FAIL: main.tscn did not load")
		quit(1)
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame
	var loader := root.get_node("TileLoader") as TileLoader
	if loader == null or loader.loaded_tile_count() <= 100:
		var n := -1 if loader == null else loader.loaded_tile_count()
		push_error("FAIL: expected >100 tiles, got %d" % n)
		quit(1)
		return
	var cam := root.get_node_or_null("Camera") as Camera3D
	if cam == null:
		push_error("FAIL: Camera3D node named 'Camera' missing from main scene")
		quit(1)
		return
	print("SMOKE OK: %d tiles" % loader.loaded_tile_count())
	quit(0)
