extends SceneTree
# Headless gameplay gate for "Nuit de livraison":
#   SLICE_SAVE=user://test_save.json tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/game_test.gd
# Plays one full loop through the real systems and prints GAME OK.

var scene: Node
var game: Node
var player: Node3D
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func tp(pos: Vector3) -> void:
	player.global_position = pos + Vector3.UP * 0.05
	player.set("velocity", Vector3.ZERO)
	await frames(3)

func _init() -> void:
	if FileAccess.file_exists("user://test_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	scene = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	await frames(5)
	game = scene.get("game")
	if game == null:
		print("GAME FAIL: scene did not build (script error?)")
		quit(1)
		return
	player = scene.get("player")
	var doors: Array = scene.get("doors")
	var shops := doors.filter(func(d): return d["kind"] == "shop").size()
	var homes := doors.filter(func(d): return d["kind"] == "home").size()
	check(shops >= 15 and homes >= 15, "doors registered: %d shops, %d homes" % [shops, homes])
	check(game.get("state") == "title", "starts on title")

	# street-graph routes: same street is straight, cross-quarter goes via junctions
	var rl: float = game.call("route_len", Vector3(4, 0, 30), Vector3(4, 0, 0))
	check(abs(rl - 30.0) < 1.0, "route along one street = %.1f m" % rl)
	var rl2: float = game.call("route_len", Vector3(4.6, 0, 30), Vector3(60, 0, -46))
	check(rl2 > 135.0 and rl2 < 155.0, "route around the corner = %.1f m" % rl2)
	var pts: PackedVector3Array = game.call("route_points", Vector3(4.6, 0, 30), Vector3(30, 0, -116))
	check(pts.size() >= 4, "route Saint-Paul -> la Commune has %d points" % pts.size())

	game.call("start_shift")
	for i in 400:
		await process_frame
		if (game.get("offers") as Array).size() == 2:
			break
	var offers: Array = game.get("offers")
	check(offers.size() == 2, "two offers at once")
	check(offers.size() == 2 and offers[0]["shop"]["name"] != offers[1]["shop"]["name"], "offers come from different shops")
	if offers.size() < 2:
		print("GAME FAIL: no offers")
		quit(1)
		return
	var pick: Dictionary = offers[1]
	# arriving at the beam takes the job (no key press)
	await tp(pick["shop"]["pos"])
	await frames(3)
	var order: Dictionary = game.get("order")
	check(not order.is_empty() and order["shop"]["name"] == pick["shop"]["name"], "walking into an offer takes it")
	check((game.get("offers") as Array).is_empty(), "the other offer lapses")
	check(not order.is_empty() and order["stage"] == "drop" and order["limit"] > 15.0, "stage -> drop (limit %.0f s)" % (order.get("limit", 0.0)))
	await frames(40)   # handoff animation
	var cash0: float = game.get("cash")
	await tp(order["home"]["pos"])
	await frames(3)
	var stats: Dictionary = game.get("stats")
	check(stats["deliveries"] == 1 and stats["on_time"] == 1, "auto-delivered on time")
	check(float(game.get("cash")) > cash0 + 6.0, "paid %.2f $" % (float(game.get("cash")) - cash0))
	check(stats["stars"] >= 3, "rated %d stars" % stats["stars"])

	# next offers arrive, and E still works as a fallback
	for i in 300:
		await process_frame
		if (game.get("offers") as Array).size() == 2:
			break
	offers = game.get("offers")
	check(offers.size() == 2, "new offers after delivery")
	player.global_position = Vector3(0, 0.2, 200)   # far away: no auto-take
	await frames(2)
	player.global_position = offers[0]["shop"]["pos"] + Vector3.UP * 0.05
	check(game.call("_try_interact"), "E interaction takes an offer")
	# damage to the bag: a car clip
	game.call("on_hit_by_car", Vector3(1, 0, 0), 7.0)
	check(float((game.get("order") as Dictionary)["condition"]) < 0.8, "car hit damages the bag")
	check(bool(player.call("knocked")), "car hit knocks the courier down")
	await frames(70)
	check(not bool(player.call("knocked")), "courier gets back up")

	# pickpocket: spawn near the crossroads, run him down and shove
	var peds: Node = scene.get("peds")
	await tp(Vector3(0.0, 0.2, -20.0))
	game.set("_thief_t", 0.0)
	for i in 600:
		await process_frame
		if not (peds.get("thief") as Dictionary).is_empty():
			break
	check(not (peds.get("thief") as Dictionary).is_empty(), "thief event started")
	await frames(90)
	var tpos: Vector3 = peds.call("thief_pos")
	var moved: bool = tpos.distance_to(Vector3(0, 0, -20)) > 3.0
	check(moved, "thief is running (%.1f m from start area)" % tpos.distance_to(Vector3(0, 0, -20)))
	await tp(tpos - Vector3(0, tpos.y, 0) + Vector3(0, 0.2, 0) + Vector3(0.0, 0.0, 0.5))
	tpos = peds.call("thief_pos")
	var facing: Vector3 = (tpos - player.global_position)
	facing.y = 0
	var r: String = peds.call("punch", player.global_position, facing.normalized())
	await frames(2)
	check(r == "thief" and int(game.get("stats")["thieves"]) == 1, "thief caught by shove")

	# collectible
	var fleurs: Dictionary = game.get("fleur_nodes")
	var before := fleurs.size()
	var fpos: Vector3 = (fleurs.values()[0] as Node3D).global_position
	await tp(Vector3(fpos.x, 0.2, fpos.z))
	await frames(5)
	check((game.get("fleur_nodes") as Dictionary).size() == before - 1, "fleur collected")
	check(int(game.get("stats")["fleurs"]) == 1, "fleur counted in shift")

	game.set("shift_t", 0.02)
	await frames(5)
	check(game.get("state") == "summary", "shift ends -> summary (%.2f $)" % float(game.get("cash")))
	check(FileAccess.file_exists("user://test_save.json"), "progress saved")
	print("GAME OK" if fails == 0 else "GAME FAIL: %d" % fails)
	quit(1 if fails > 0 else 0)
