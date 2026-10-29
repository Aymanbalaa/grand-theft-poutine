class_name SliceGame
extends Node
# "Nuit de livraison": a rainy-evening courier shift in Old Montréal.
# Pick up orders at shops, deliver them to addresses before the clock runs
# out; tips reward speed and an intact bag, on-time streaks multiply tips.
# Pickpockets strike now and then: chase them down for a reward. Twelve gilt
# fleurs-de-lys are hidden around the quarter (saved across sessions).

const SHIFT_LEN := 360.0
const SAVE_PATH := "user://nuit_de_livraison.json"
const PICKUP_COL := Color(1.0, 0.68, 0.22)
const DROP_COL := Color(0.3, 0.85, 1.0)
const REACH := 2.3
const FLEURS := [
	Vector3(-4.9, 0.85, 41.5), Vector3(4.9, 0.85, -104.0), Vector3(90.0, 0.85, -47.0),
	Vector3(-90.0, 0.85, -57.0), Vector3(55.0, 0.75, -52.0), Vector3(-31.0, 0.85, -46.8),
	Vector3(0.0, 1.55, -121.2), Vector3(-44.0, 0.85, -118.0), Vector3(43.0, 0.85, -113.2),
	Vector3(12.0, 0.75, 44.0), Vector3(-11.0, 0.85, -57.4), Vector3(-2.6, 0.75, -78.0),
]

var world: Node
var player: SlicePlayer
var peds: SlicePedestrians
var hud: SliceHud
var rng := RandomNumberGenerator.new()
var save_path := SAVE_PATH

var state := "title"          # title | shift | free | summary
var shift_t := 0.0
var cash := 0.0
var combo := 0
var order := {}
var stats := {}
var save_data := {"best": 0.0, "fleurs": [], "shifts": 0}
var fleur_nodes := {}
var marker: SliceMarker
var _thief_t := 0.0
var _chase_t := 0.0
var _lost_t := 0.0
var _next_order_t := -1.0
var _bump_cd := 0.0
var _rolled_with_bag := false
var _sfx_players := {}

func _sfx(name: String) -> void:
	if not _sfx_players.has(name):
		var path := "res://assets/slice/audio/sfx_%s.wav" % name
		if not ResourceLoader.exists(path):
			return
		var p := AudioStreamPlayer.new()
		p.stream = load(path)
		p.volume_db = -4.0
		add_child(p)
		_sfx_players[name] = p
	(_sfx_players[name] as AudioStreamPlayer).play()

func setup(w: Node) -> void:
	world = w
	player = w.get("player")
	peds = w.get("peds")
	rng.seed = Time.get_ticks_usec()
	if OS.get_environment("SLICE_SAVE") != "":
		save_path = OS.get_environment("SLICE_SAVE")
	_load()
	hud = SliceHud.new()
	add_child(hud)
	marker = SliceMarker.new()
	marker.visible = false
	world.add_child(marker)
	for i in FLEURS.size():
		if save_data["fleurs"].has(i):
			continue
		var f := SliceFleur.new()
		f.id = i
		f.position = FLEURS[i]
		world.add_child(f)
		fleur_nodes[i] = f
	player.interact_hook = _try_interact
	player.punched.connect(_on_punch)
	peds.thief_caught.connect(_on_thief_caught)
	peds.thief_escaped.connect(_on_thief_escaped)
	show_title()

# ------------------------------------------------------------------ flow

func show_title() -> void:
	state = "title"
	player.active = false
	marker.visible = false
	hud.show_title(save_data["best"], save_data["fleurs"].size(), FLEURS.size())

func start_shift() -> void:
	state = "shift"
	shift_t = SHIFT_LEN
	cash = 0.0
	combo = 0
	stats = {"deliveries": 0, "on_time": 0, "late": 0, "tips": 0.0, "thieves": 0, "fleurs": 0, "fines": 0.0, "best_combo": 0}
	order = {}
	player.active = true
	player.set_carrying(false)
	hud.hide_overlays()
	hud.toast("Début du quart — 19 h 30", Color(1, 0.9, 0.75))
	_thief_t = rng.randf_range(55.0, 80.0)
	_next_order_t = 1.5

func start_free() -> void:
	state = "free"
	player.active = true
	order = {}
	marker.visible = false
	hud.hide_overlays()
	hud.toast("Balade libre — Entrée pour commencer un quart", Color(0.9, 0.9, 0.95))
	_thief_t = rng.randf_range(40.0, 70.0)

func end_shift() -> void:
	state = "summary"
	player.active = false
	player.set_carrying(false)
	marker.visible = false
	order = {}
	peds.give_up_thief()
	var total := cash
	var record := total > float(save_data["best"])
	if record:
		save_data["best"] = total
	save_data["shifts"] = int(save_data.get("shifts", 0)) + 1
	_save()
	_sfx("end")
	hud.show_summary(stats, total, save_data["best"], record, save_data["fleurs"].size(), FLEURS.size())

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		if state in ["title", "summary", "free"]:
			start_shift()
			get_viewport().set_input_as_handled()
	elif e.keycode == KEY_SPACE and state in ["title", "summary"]:
		start_free()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ orders

func _doors(kind: String) -> Array:
	var out := []
	for d in world.get("doors"):
		if d["kind"] == kind:
			out.append(d)
	return out

func _new_order() -> void:
	var shops := _doors("shop")
	var homes := _doors("home")
	var ppos := player.global_position
	for attempt in 40:
		var s: Dictionary = shops[rng.randi() % shops.size()]
		var h: Dictionary = homes[rng.randi() % homes.size()]
		var d1: float = (s["pos"] as Vector3).distance_to(ppos)
		var d2: float = (s["pos"] as Vector3).distance_to(h["pos"])
		if d1 < 12.0 or d1 > 110.0 or d2 < 35.0 or d2 > 170.0:
			continue
		var route := _route_len(s["pos"], h["pos"])
		var express: bool = stats.get("deliveries", 0) >= 2 and rng.randf() < 0.22
		order = {"shop": s, "home": h, "item": s.get("item", "un colis"), "fragile": s.get("fragile", false),
			"stage": "pickup", "route": route, "limit": 0.0, "t": 0.0, "condition": 1.0, "express": express}
		marker.visible = true
		marker.set_color(PICKUP_COL)
		marker.global_position = s["pos"]
		hud.toast(("EXPRESS — pourboire double : %s" if express else "Nouvelle commande : %s") % s["name"], PICKUP_COL)
		_sfx("order")
		return
	_next_order_t = 1.0   # try again shortly

# Streets form a + with a market street: approximate walking distance via
# the nearest junction when the two points aren't on the same street.
func _route_len(a: Vector3, b: Vector3) -> float:
	var direct := Vector2(a.x - b.x, a.z - b.z).length()
	var same: bool = abs(a.x - b.x) < 12.0 or abs(a.z - b.z) < 12.0
	if same:
		return direct
	return abs(a.x - b.x) + abs(a.z - b.z)

func _try_interact() -> bool:
	if state != "shift" or order.is_empty():
		return false
	var target: Dictionary = order["shop"] if order["stage"] == "pickup" else order["home"]
	if player.global_position.distance_to(target["pos"]) > REACH:
		return false
	if order["stage"] == "pickup":
		order["stage"] = "drop"
		# later in the shift the clock gets tighter; express orders are tighter still
		var ramp := maxf(0.72, 1.0 - 0.035 * stats["deliveries"])
		order["limit"] = (22.0 + order["route"] / 4.1 * (1.15 if order["fragile"] else 1.0)) * ramp * (0.75 if order["express"] else 1.0)
		order["t"] = order["limit"]
		player.set_carrying(true)
		marker.set_color(DROP_COL)
		marker.global_position = order["home"]["pos"]
		_sfx("pickup")
		hud.toast("Récupéré : %s%s" % [order["item"], "  (fragile !)" if order["fragile"] else ""], DROP_COL)
	else:
		_deliver()
	return true

func _deliver() -> void:
	var on_time: bool = order["t"] > 0.0
	var base: float = 6.0 + order["route"] * 0.06
	var tip := 0.0
	var cond: float = order["condition"]
	if on_time:
		combo += 1
		var mult := 1.0 + 0.25 * (combo - 1)
		tip = (4.0 + 10.0 * order["t"] / order["limit"]) * cond * mult * (2.0 if order["express"] else 1.0)
		stats["on_time"] += 1
	else:
		base *= 0.5
		combo = 0
		stats["late"] += 1
	if cond < 0.5:
		base *= 0.7
	var pay := snappedf(base + tip, 0.01)
	cash += pay
	stats["deliveries"] += 1
	stats["tips"] += tip
	stats["best_combo"] = maxi(stats["best_combo"], combo)
	var stars := clampi(int(round((tip / 14.0) * 5.0)), 1, 5) if on_time else 1
	var line := "+%.2f $  %s" % [pay, "★".repeat(stars) + "☆".repeat(5 - stars)]
	if on_time and combo > 1:
		line += "   série x%d" % combo
	hud.toast(line, Color(0.6, 1.0, 0.6) if on_time else Color(1.0, 0.6, 0.4))
	_sfx("cash" if on_time else "fail")
	if not on_time:
		hud.toast("En retard… pas de pourboire", Color(1.0, 0.6, 0.4))
	player.set_carrying(false)
	order = {}
	marker.visible = false
	_next_order_t = 2.5

func _damage(amount: float, why: String) -> void:
	if order.is_empty() or order["stage"] != "drop":
		return
	if order["fragile"]:
		amount *= 1.6
	order["condition"] = maxf(0.0, order["condition"] - amount)
	_sfx("bump")
	hud.toast("%s  colis %d %%" % [why, int(order["condition"] * 100.0)], Color(1.0, 0.5, 0.35))

# ------------------------------------------------------------------ events

func _on_punch(pos: Vector3, facing: Vector3) -> void:
	if state not in ["shift", "free"]:
		return
	var r := peds.punch(pos, facing)
	if r == "person":
		if state == "shift":
			cash -= 5.0
			stats["fines"] += 5.0
			hud.toast("Hé ! Pas de bagarre.  −5 $", Color(1.0, 0.45, 0.35))
		else:
			hud.toast("Hé ! Pas de bagarre.", Color(1.0, 0.45, 0.35))

func _on_thief_caught(_pos: Vector3) -> void:
	_chase_t = 0.0
	_sfx("cash")
	if state == "shift":
		cash += 25.0
		stats["thieves"] += 1
		hud.toast("Voleur arrêté ! +25 $ de récompense", Color(0.6, 1.0, 0.6))
	else:
		hud.toast("Voleur arrêté ! Merci !", Color(0.6, 1.0, 0.6))
	hud.alert("")
	_thief_t = rng.randf_range(70.0, 110.0)

func _on_thief_escaped() -> void:
	if state not in ["shift", "free"]:
		return
	_sfx("fail")
	hud.toast("Le voleur s'est enfui…", Color(1.0, 0.6, 0.4))
	hud.alert("")
	_thief_t = rng.randf_range(60.0, 100.0)

func _collect_fleur(i: int) -> void:
	var f: Node3D = fleur_nodes[i]
	fleur_nodes.erase(i)
	f.queue_free()
	_sfx("fleur")
	save_data["fleurs"].append(i)
	_save()
	var n: int = save_data["fleurs"].size()
	if state == "shift":
		cash += 5.0
		stats["fleurs"] += 1
	hud.toast("Fleur de lys trouvée !  %d / %d%s" % [n, FLEURS.size(), "  +5 $" if state == "shift" else ""], Color(1.0, 0.85, 0.4))
	if n == FLEURS.size():
		hud.toast("Toutes les fleurs de lys ! Le Vieux-Montréal n'a plus de secrets.", Color(1.0, 0.85, 0.4))

# ------------------------------------------------------------------ tick

func _process(delta: float) -> void:
	var cam: Camera3D = world.call("active_camera")
	if state in ["shift", "free"]:
		var ppos := player.global_position
		for i in fleur_nodes.keys():
			if (fleur_nodes[i] as Node3D).global_position.distance_to(ppos + Vector3.UP * 0.8) < 1.2:
				_collect_fleur(i)
		_tick_thief(delta, ppos)
		_bump_cd -= delta
		if _bump_cd <= 0.0 and peds.check_bump(ppos, player.horizontal_speed()):
			_bump_cd = 1.0
			if not order.is_empty() and order["stage"] == "drop":
				_damage(0.2, "Bousculade !")
		if player.rolling():
			if not peds.thief.is_empty():
				peds.tackle(ppos)
			if not _rolled_with_bag and not order.is_empty() and order["stage"] == "drop":
				_rolled_with_bag = true
				_damage(0.1, "Roulade avec le colis…")
		else:
			_rolled_with_bag = false
	if state == "shift":
		shift_t -= delta
		if _next_order_t > 0.0:
			_next_order_t -= delta
			if _next_order_t <= 0.0:
				_new_order()
		if not order.is_empty() and order["stage"] == "drop":
			order["t"] -= delta
		if shift_t <= 0.0:
			end_shift()
	_update_hud(cam)

func _tick_thief(delta: float, ppos: Vector3) -> void:
	if peds.thief.is_empty():
		_thief_t -= delta
		if _thief_t <= 0.0:
			var w := peds.start_thief(ppos)
			if w.is_empty():
				_thief_t = 5.0
			else:
				_chase_t = 0.0
				_lost_t = 0.0
				hud.alert("AU VOLEUR !")
				_sfx("whistle")
				hud.toast("Un pickpocket s'enfuit avec un sac — rattrapez-le !", Color(1.0, 0.4, 0.3))
		return
	_chase_t += delta
	var d := peds.thief_pos().distance_to(ppos)
	_lost_t = _lost_t + delta if d > 55.0 else 0.0
	if _lost_t > 5.0 or _chase_t > 45.0:
		peds.give_up_thief()

func _update_hud(cam: Camera3D) -> void:
	var target := Vector3.INF
	var tcol := Color.WHITE
	if state == "shift":
		var mins := int((SHIFT_LEN - shift_t) / SHIFT_LEN * 210.0)   # 19:30 -> 23:00
		hud.set_status(cash, "%02d:%02d" % [19 + (30 + mins) / 60, (30 + mins) % 60], combo, shift_t)
		if order.is_empty():
			hud.set_objective("En attente d'une commande…", "", Color(0.85, 0.85, 0.9), -1.0, "")
			hud.set_condition(-1.0)
			hud.set_prompt("")
		else:
			var pick: bool = order["stage"] == "pickup"
			var tgt: Dictionary = order["shop"] if pick else order["home"]
			target = tgt["pos"]
			tcol = PICKUP_COL if pick else DROP_COL
			var dist := player.global_position.distance_to(target)
			marker.set_proximity(dist)
			var l1: String = ("EXPRESS  ·  " if order["express"] else "") + ("RÉCUPÉRER  ·  " if pick else "LIVRER  ·  ") + String(order["item"])
			var l2: String = ("%s" % tgt["name"]) if pick else ("%d, %s" % [tgt["number"], tgt["street"]])
			var tl := "" if pick else ("%d s" % int(ceil(maxf(order["t"], 0.0))) if order["t"] > 0.0 else "EN RETARD")
			var frac := -1.0 if pick else clampf(order["t"] / order["limit"], 0.0, 1.0)
			hud.set_objective(l1, l2 + "   ·   %d m" % int(dist), tcol, frac, tl)
			hud.set_condition(-1.0 if pick else order["condition"])
			hud.set_prompt(("[E]  Récupérer la commande" if pick else "[E]  Livrer") if dist < REACH else "")
	elif state == "free":
		hud.set_status(-1.0, "", 0, -1.0)
		hud.set_objective("", "", Color.WHITE, -1.0, "")
		hud.set_condition(-1.0)
		hud.set_prompt("")
	if not peds.thief.is_empty() and state in ["shift", "free"]:
		target = peds.thief_pos()
		tcol = Color(1.0, 0.25, 0.2)
	if state in ["shift", "free"]:
		hud.update_pointer(cam, target, tcol)
		hud.update_map(player.global_position, cam.global_rotation.y, target, tcol)
	else:
		hud.update_pointer(cam, Vector3.INF, tcol)

# ------------------------------------------------------------------ save

func _load() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		save_data.merge(data, true)
		var fl := []
		for v in save_data["fleurs"]:
			fl.append(int(v))
		save_data["fleurs"] = fl

func _save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_data))
