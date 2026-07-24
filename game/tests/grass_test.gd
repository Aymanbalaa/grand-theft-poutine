extends SceneTree
# headless: godot_console --headless --path game --script res://tests/grass_test.gd

func _init() -> void:
	var GF = load("res://scripts/grass_field.gd")
	# clearly green park vertex -> grass
	assert(GF.is_grass(Color(0.30, 0.55, 0.25)) == true)
	# grey road / concrete (r==g==b) -> not grass
	assert(GF.is_grass(Color(0.45, 0.45, 0.45)) == false)
	# brown dirt (r>g) -> not grass
	assert(GF.is_grass(Color(0.42, 0.34, 0.20)) == false)
	# water bottom (b dominant, wet) -> not grass even if slightly green
	assert(GF.is_grass(Color(0.20, 0.30, 0.40)) == false)
	# borderline just under threshold -> not grass
	assert(GF.is_grass(Color(0.40, 0.45, 0.30)) == false)  # g-r = 0.05 < 0.06
	print("GRASS CLASSIFIER OK")
	quit()
