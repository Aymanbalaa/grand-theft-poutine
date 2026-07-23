extends SceneTree
# Diagnostic: render car0..car5 in a row on a grey plane, one PNG, going
# through the real CarVisual script (res://scripts/car_visual.gd) so this
# exercises the actual in-game material path, not a bare GLB load. NOT
# headless — needs a GPU. Reusable for future car-material regressions.
# Run: tools/godot/godot_console.exe --path game --script res://tests/car_capture.gd

const CarVisualScript = preload("res://scripts/car_visual.gd")
const MODEL_COUNT := 6
const SPACING := 4.0

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var plane := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(MODEL_COUNT * SPACING + 4.0, 10.0)
	var plane_mat := StandardMaterial3D.new()
	plane_mat.albedo_color = Color(0.45, 0.45, 0.47)
	plane_mesh.material = plane_mat
	plane.mesh = plane_mesh
	root.add_child(plane)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-PI / 3.0, PI / 5.0, 0)
	sun.light_energy = 1.2
	root.add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	root.add_child(env_node)

	var origin_x := -(MODEL_COUNT - 1) * SPACING / 2.0
	for i in MODEL_COUNT:
		var path := "res://assets/models/cars/car%d.glb" % i
		if not ResourceLoader.exists(path):
			push_error("FAIL: %s missing" % path)
			quit(1)
			return
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position = Vector3(origin_x + i * SPACING, 0, 0)
		holder.rotation.y = PI / 5.0
		var visual := Node3D.new()
		visual.set_script(CarVisualScript)
		visual.set("color_index", i)
		holder.add_child(visual)  # triggers CarVisual._ready(): loads carN.glb + polishes materials

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 3.2, 11.0), Vector3(0, 0.5, 0))
	cam.current = true

	for i in 15:  # settle: let deferred imports / shaders / frames stabilize
		await process_frame

	var img := get_root().get_viewport().get_texture().get_image()
	var out_path := "user://car_lineup.png"
	img.save_png(out_path)
	print("saved %s" % out_path)
	quit(0)
