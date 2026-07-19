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
	if loader == null or loader.loaded_tile_count() == 0:
		push_error("FAIL: no tiles loaded")
		quit(1)
		return
	print("SMOKE OK: %d tiles" % loader.loaded_tile_count())
	quit(0)
