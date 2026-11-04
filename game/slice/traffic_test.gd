extends SceneTree
# Traffic gate: cars drive, brake for a courier standing in the lane, and clip
# one who steps out too late.
#   tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/traffic_test.gd

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _init() -> void:
	var scene: Node = (load("res://slice/slice.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	await frames(5)
	scene.get("game").call("start_free")
	var player: CharacterBody3D = scene.get("player")
	var traffic: Node = scene.get("traffic")
	var cars: Array = traffic.get("cars")
	player.global_position = Vector3(5.0, 0.3, 30.0)   # on the sidewalk, out of the way
	var p0 := []
	for c in cars:
		p0.append((c["node"] as Node3D).global_position)
	await frames(180)
	var moving := 0
	for i in cars.size():
		if cars[i]["active"] and (cars[i]["node"] as Node3D).global_position.distance_to(p0[i]) > 5.0:
			moving += 1
	check(moving >= 2, "%d of %d cars on the move" % [moving, cars.size()])

	# take car 0 onto Saint-Paul southbound, 30 m up from a courier standing in the lane
	var c: Dictionary = cars[0]
	c["active"] = true
	c["route"] = 0
	c["seg"] = 0
	c["s"] = 4.0
	c["speed"] = 7.0
	(c["node"] as Node3D).visible = true
	for o in cars:
		if o != c:
			o["active"] = false
			(o["node"] as Node3D).global_position = Vector3(0, -50, 0)
			o["wait"] = 999.0
	traffic.call("_pose", c, 0.0)
	player.global_position = Vector3(0.0, 0.2, 10.0)
	player.velocity = Vector3.ZERO
	var hits := [0]
	traffic.connect("hit_player", func(_d, _s): hits[0] += 1)
	await frames(60 * 6)
	var cz: float = (c["node"] as Node3D).global_position.z
	var gap := cz - 2.1 - player.global_position.z
	check(c["speed"] < 0.3 and gap > 0.3 and gap < 3.5, "car stops %.1f m short of the courier" % gap)
	check(hits[0] == 0, "no contact when there's room to brake")
	check(c["blocked_t"] > 1.0, "car waits on the courier (%.1f s)" % c["blocked_t"])

	# courier steps aside: the car moves on
	player.global_position = Vector3(5.0, 0.3, 10.0)
	await frames(90)
	check(c["speed"] > 2.0, "car pulls away once the lane clears (%.1f m/s)" % c["speed"])

	# step out right in front of it at speed
	await frames(30)
	var cp: Vector3 = (c["node"] as Node3D).global_position
	var fwd: Vector3 = -(c["node"] as Node3D).global_transform.basis.z
	player.global_position = cp + fwd * 2.4 + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	await frames(20)
	check(hits[0] >= 1, "late step-out gets clipped")
	check(bool(player.call("knocked")), "courier knocked down")
	print("TRAFFIC OK" if fails == 0 else "TRAFFIC FAIL: %d" % fails)
	quit(1 if fails else 0)
