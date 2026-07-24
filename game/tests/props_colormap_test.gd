extends SceneTree
# godot_console --headless --path game --script res://tests/props_colormap_test.gd
# Guards the lamp against the white-car-bug class: a fresh import can drop the
# external-URI colormap; the safety net in props_multimesh must re-assign it so
# the kept material is never an untextured white default.
func _init() -> void:
	var PM = load("res://scripts/props_multimesh.gd")
	var entry: Dictionary = PM._first_mesh("res://assets/models/props/lamp_post.glb")
	assert(not entry.is_empty(), "lamp_post.glb produced no mesh")
	var mesh: Mesh = entry["mesh"]
	var textured_or_colored := false
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s) as BaseMaterial3D
		if mat == null:
			continue
		# after the net, every kept surface material is either a MAT_COLORS solid
		# color OR carries the colormap texture — never an untextured white default
		if mat.albedo_texture != null or mat.albedo_color != Color(1, 1, 1, 1):
			textured_or_colored = true
	assert(textured_or_colored, "lamp material is untextured white (colormap safety net failed)")
	print("PROPS COLORMAP OK")
	quit()
