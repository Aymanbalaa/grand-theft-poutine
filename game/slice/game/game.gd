class_name SliceGame
extends Node
# "Nuit de livraison": a rainy-evening courier shift in Old Montréal.
#
# Loop: two order offers light up as beams at their shops (amber = regular,
# rose = express). Run into either beam to take that job: the other one
# lapses. Pickup and drop-off happen automatically on arrival (E also works).
# Pay = base by route length + tip by time left and bag condition, times the
# on-time streak; express doubles tips on a tighter clock. Sprinting close
# past people ("Frôlé !") pays small style bonuses while carrying, but
# bumping them, diving, hard landings and cars damage the bag.
# Pickpockets strike now and then: sprint them down, dive or shove to tackle.
# Twelve gilt fleurs-de-lys are hidden around the quarter (saved).

const SHIFT_LEN := 360.0
const SAVE_PATH := "user://nuit_de_livraison.json"
const PICKUP_COL := Color(1.0, 0.68, 0.22)
const EXPRESS_COL := Color(1.0, 0.36, 0.62)
const DROP_COL := Color(0.3, 0.85, 1.0)
const THIEF_COL := Color(1.0, 0.25, 0.2)
const REACH := 2.4
const OFFER_LIFE := 40.0
const MEDALS := [[350.0, "Or", Color(1.0, 0.82, 0.3)], [250.0, "Argent", Color(0.85, 0.88, 0.95)], [150.0, "Bronze", Color(0.85, 0.55, 0.3)]]
const FLEURS := [
	Vector3(-4.9, 0.85, 41.5), Vector3(4.9, 0.85, -104.0), Vector3(90.0, 0.85, -47.0),
	Vector3(-90.0, 0.85, -57.0), Vector3(55.0, 0.75, -52.0), Vector3(-31.0, 0.85, -46.8),
	Vector3(0.0, 1.55, -121.2), Vector3(-44.0, 0.85, -118.0), Vector3(43.0, 0.85, -113.2),
	Vector3(12.0, 0.75, 44.0), Vector3(-11.0, 0.85, -57.4), Vector3(-2.6, 0.75, -78.0),
]
# Street graph (road centre lines) used for route lengths and the minimap line.
const NODES := {"N": Vector3(0, 0, 42), "X": Vector3(0, 0, -52), "S": Vector3(0, 0, -118),
	"W": Vector3(-93, 0, -52), "E": Vector3(93, 0, -52), "CW": Vector3(-44, 0, -118), "CE": Vector3(44, 0, -118)}
const EDGES := [["N", "X"], ["X", "S"], ["X", "W"], ["X", "E"], ["S", "CW"], ["S", "CE"]]

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
var order := {}               # the job in hand (stage "drop")
var offers: Array = []        # up to two jobs waiting at their shops
var stats := {}
var save_data := {"best": 0.0, "fleurs": [], "shifts": 0}
var fleur_nodes := {}
var marker: SliceMarker       # drop-off beam
var offer_markers: Array[SliceMarker] = []
var _thief_t := 0.0
var _chase_t := 0.0
var _lost_t := 0.0
var _next_offer_t := -1.0
var _bump_cd := 0.0
var _rolled_with_bag := false
var _graze_chain := 0
var _graze_t := 0.0
var _sfx_players := {}

func _sfx(name: String, vol := -4.0, pitch := 1.0) -> void:
	if not _sfx_players.has(name):
		var path := "res://assets/slice/audio/sfx_%s.wav" % name
		if not ResourceLoader.exists(path):
			return
		var p := AudioStreamPlayer.new()
		p.stream = load(path)
		add_child(p)
		_sfx_players[name] = p
	var ap := _sfx_players[name] as AudioStreamPlayer
	ap.volume_db = vol
	ap.pitch_scale = pitch
	ap.play()

static func medal_for(total: float) -> Array:
	for m in MEDALS:
		if total >= m[0]:
			return m
	return []

func setup(w: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps the pause menu alive
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
	for i in 2:
		var m := SliceMarker.new()
		m.visible = false
		world.add_child(m)
		offer_markers.append(m)
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
	player.landed.connect(_on_landed)
	peds.thief_caught.connect(_on_thief_caught)
	peds.thief_escaped.connect(_on_thief_escaped)
	var tr = w.get("traffic")
	if tr != null:
		tr.hit_player.connect(on_hit_by_car)
	show_title()

# ------------------------------------------------------------------ flow

func _attract(on: bool) -> void:
	if world.has_method("set_attract"):
		world.call("set_attract", on)

func show_title() -> void:
	state = "title"
	_attract(true)
	player.active = false
	_clear_jobs()
	var mi := int(save_data.get("medal", 99))
	hud.show_title(save_data["best"], save_data["fleurs"].size(), FLEURS.size(), MEDALS[mi] if mi < MEDALS.size() else [])

func start_shift() -> void:
	_attract(false)
	state = "shift"
	shift_t = SHIFT_LEN
	cash = 0.0
	combo = 0
	stats = {"deliveries": 0, "on_time": 0, "late": 0, "tips": 0.0, "thieves": 0, "fleurs": 0, "fines": 0.0,
		"best_combo": 0, "grazes": 0, "stars": 0, "damage": 0}
	_clear_jobs()
	player.active = true
	player.stamina = 1.0
	hud.hide_overlays()
	hud.stamp("Début du quart", "19 h 30  ·  Vieux-Montréal", Color(1, 0.9, 0.75))
	_thief_t = rng.randf_range(50.0, 75.0)
	_next_offer_t = 1.2
	if world.has_method("set_shift_progress"):
		world.call("set_shift_progress", 0.0)

func start_free() -> void:
	_attract(false)
	state = "free"
	player.active = true
	_clear_jobs()
	hud.hide_overlays()
	hud.toast("Balade libre — Entrée pour commencer un quart", Color(0.9, 0.9, 0.95))
	_thief_t = rng.randf_range(35.0, 60.0)

func end_shift() -> void:
	state = "summary"
	player.active = false
	_clear_jobs()
	peds.give_up_thief()
	var total := cash
	var record := total > float(save_data["best"])
	var med := medal_for(total)
	stats["medal"] = med
	if not med.is_empty():
		var rank := MEDALS.find(med)
		var prev := int(save_data.get("medal", 99))
		save_data["medal"] = mini(rank, prev)
	if record:
		save_data["best"] = total
	save_data["shifts"] = int(save_data.get("shifts", 0)) + 1
	_save()
	_attract(true)
	_sfx("end")
	hud.show_summary(stats, total, save_data["best"], record, save_data["fleurs"].size(), FLEURS.size())

func _clear_jobs() -> void:
	order = {}
	offers = []
	marker.visible = false
	for m in offer_markers:
		m.visible = false
	player.set_carrying(false)

func set_paused(on: bool) -> void:
	if on == get_tree().paused or state not in ["shift", "free"]:
		return
	get_tree().paused = on
	hud.show_pause(on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	var start := false
	var free := false
	var pause := false
	var quit_title := false
	if e is InputEventKey and e.pressed and not e.echo:
		start = e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER
		free = e.keycode == KEY_SPACE
		pause = e.keycode == KEY_ESCAPE or e.keycode == KEY_P
		quit_title = e.keycode == KEY_T
	elif e is InputEventJoypadButton and e.pressed:
		start = e.button_index == JOY_BUTTON_START
		free = e.button_index == JOY_BUTTON_BACK
		pause = start and state in ["shift", "free"]
		quit_title = free and get_tree().paused
	if get_tree().paused:
		if pause:
			set_paused(false)
		elif quit_title:
			get_tree().paused = false
			hud.show_pause(false)
			peds.give_up_thief()
			show_title()
		get_viewport().set_input_as_handled()
		return
	if pause and state in ["shift", "free"]:
		set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if start and state in ["title", "summary", "free"]:
		start_shift()
		get_viewport().set_input_as_handled()
	elif free and state in ["title", "summary"]:
		start_free()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ routes

static func _project(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return a + ab * t

static func _nearest_edge(p: Vector3) -> int:
	var flat := Vector3(p.x, 0, p.z)
	var best := 0
	var bd := INF
	for i in EDGES.size():
		var q := _project(flat, NODES[EDGES[i][0]], NODES[EDGES[i][1]])
		var d := q.distance_to(flat)
		if d < bd:
			bd = d
			best = i
	return best

# Walking route between two points along the street graph:
# [a, junctions..., b] (sidewalk-to-centre jogs are left out).
static func route_points(a: Vector3, b: Vector3) -> PackedVector3Array:
	var fa := Vector3(a.x, 0, a.z)
	var fb := Vector3(b.x, 0, b.z)
	var ea: int = _nearest_edge(fa)
	var eb: int = _nearest_edge(fb)
	if ea == eb:
		return PackedVector3Array([fa, fb])
	# Dijkstra over the junction nodes, seeded from both ends of edge ea
	var dist := {}
	var prev := {}
	for n in NODES.keys():
		dist[n] = INF
	for n in EDGES[ea]:
		dist[n] = fa.distance_to(NODES[n])
		prev[n] = ""
	var todo: Array = NODES.keys()
	while not todo.is_empty():
		var u: String = todo[0]
		for n in todo:
			if dist[n] < dist[u]:
				u = n
		todo.erase(u)
		for e in EDGES:
			var v := ""
			if e[0] == u: v = e[1]
			elif e[1] == u: v = e[0]
			else: continue
			var nd: float = dist[u] + (NODES[u] as Vector3).distance_to(NODES[v])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	var end_n: String = EDGES[eb][0]
	if dist[EDGES[eb][1]] + fb.distance_to(NODES[EDGES[eb][1]]) < dist[end_n] + fb.distance_to(NODES[end_n]):
		end_n = EDGES[eb][1]
	var chain: Array = []
	var cur := end_n
	while cur != "":
		chain.push_front(NODES[cur])
		cur = prev.get(cur, "")
	var out := PackedVector3Array([fa])
	for c in chain:
		out.append(c)
	out.append(fb)
	return out

static func route_len(a: Vector3, b: Vector3) -> float:
	var pts := route_points(a, b)
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l

# ------------------------------------------------------------------ offers

func _doors(kind: String) -> Array:
	var out := []
	for d in world.get("doors"):
		if d["kind"] == kind:
			out.append(d)
	return out

func _make_offer(want_express: bool, avoid_shop: String) -> Dictionary:
	var shops := _doors("shop")
	var homes := _doors("home")
	var ppos := player.global_position
	for attempt in 60:
		var s: Dictionary = shops[rng.randi() % shops.size()]
		if s["name"] == avoid_shop:
			continue
		var h: Dictionary = homes[rng.randi() % homes.size()]
		var d1 := route_len(ppos, s["pos"])
		var d2 := route_len(s["pos"], h["pos"])
		if d1 < 10.0 or d1 > 120.0 or d2 < 40.0 or d2 > 190.0:
			continue
		var express := want_express
		var fragile: bool = s.get("fragile", false)
		var o := {"shop": s, "home": h, "item": s.get("item", "un colis"), "fragile": fragile,
			"stage": "offer", "route": d2, "limit": 0.0, "t": 0.0, "condition": 1.0, "express": express, "age": 0.0}
		o["limit"] = _limit_for(o)
		o["pay_est"] = _base_pay(o) + 9.0 * (2.0 if express else 1.0)
		return o
	return {}

func _limit_for(o: Dictionary) -> float:
	# later in the shift the clock gets tighter; express orders are tighter still
	var ramp := maxf(0.74, 1.0 - 0.03 * stats.get("deliveries", 0))
	return (10.0 + o["route"] / 3.7 * (1.1 if o["fragile"] else 1.0)) * ramp * (0.72 if o["express"] else 1.0)

func _base_pay(o: Dictionary) -> float:
	return 6.0 + o["route"] * 0.07

func _refresh_offers() -> void:
	# keep two offers: one regular, and from the 2nd delivery on often an express
	while offers.size() < 2:
		var express: bool = offers.size() == 1 and stats.get("deliveries", 0) >= 1 and rng.randf() < 0.6
		var avoid := "" if offers.is_empty() else String(offers[0]["shop"]["name"])
		var o := _make_offer(express, avoid)
		if o.is_empty():
			break
		offers.append(o)
	for i in offer_markers.size():
		var m := offer_markers[i]
		m.visible = i < offers.size()
		if m.visible:
			m.set_color(EXPRESS_COL if offers[i]["express"] else PICKUP_COL)
			m.global_position = offers[i]["shop"]["pos"]
	if not offers.is_empty():
		_sfx("order")
		hud.toast("Nouvelles commandes — choisissez-en une", PICKUP_COL)

func _take_offer(i: int) -> void:
	order = offers[i]
	offers = []
	for m in offer_markers:
		m.visible = false
	order["stage"] = "drop"
	order["limit"] = _limit_for(order)
	order["t"] = order["limit"]
	player.set_carrying(true)
	player.handoff()
	marker.visible = true
	marker.set_color(DROP_COL)
	marker.global_position = order["home"]["pos"]
	_sfx("pickup")
	hud.toast("Récupéré : %s%s" % [order["item"], "  (fragile !)" if order["fragile"] else ""], DROP_COL)
	hud.float_text(order["shop"]["pos"] + Vector3.UP * 2.0, "%d s" % int(order["limit"]), DROP_COL)

func _near(p: Vector3) -> bool:
	var d := player.global_position - p
	return Vector2(d.x, d.z).length() < REACH and abs(d.y) < 1.5

func _try_interact() -> bool:
	if state != "shift":
		return false
	if order.is_empty():
		for i in offers.size():
			if _near(offers[i]["shop"]["pos"]):
				_take_offer(i)
				return true
		return false
	if _near(order["home"]["pos"]):
		_deliver()
		return true
	return false

func _deliver() -> void:
	var on_time: bool = order["t"] > 0.0
	var base := _base_pay(order)
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
	var frac: float = order["t"] / order["limit"]
	var stars := 1
	if on_time:
		stars = clampi(1 + int(round(cond * 2.0)) + (2 if frac > 0.4 else (1 if frac > 0.15 else 0)), 1, 5)
	stats["stars"] += stars
	player.handoff()
	hud.stamp("LIVRÉ !" if on_time else "En retard…", "+%.2f $   %s" % [pay, "★".repeat(stars) + "☆".repeat(5 - stars)],
		Color(0.6, 1.0, 0.6) if on_time else Color(1.0, 0.6, 0.4))
	if on_time and combo > 1:
		hud.toast("Série x%d  —  pourboires x%.2f" % [combo, 1.0 + 0.25 * (combo - 1)], Color(1.0, 0.85, 0.4))
	_sfx("cash" if on_time else "fail")
	player.set_carrying(false)
	order = {}
	marker.visible = false
	_next_offer_t = 1.5

func _damage(amount: float, why: String) -> void:
	if order.is_empty():
		return
	if order["fragile"]:
		amount *= 1.6
	order["condition"] = maxf(0.0, order["condition"] - amount)
	stats["damage"] += 1
	_sfx("bump")
	hud.flash(Color(1.0, 0.3, 0.2), 0.22)
	hud.toast("%s  colis %d %%" % [why, int(order["condition"] * 100.0)], Color(1.0, 0.5, 0.35))

# ------------------------------------------------------------------ events

func _on_punch(pos: Vector3, facing: Vector3) -> void:
	if state not in ["shift", "free"]:
		return
	var r := peds.punch(pos, facing)
	if r == "person":
		player.add_trauma(0.15)
		if state == "shift":
			cash -= 5.0
			stats["fines"] += 5.0
			hud.toast("Hé ! Pas de bagarre.  −5 $", Color(1.0, 0.45, 0.35))
		else:
			hud.toast("Hé ! Pas de bagarre.", Color(1.0, 0.45, 0.35))

func _on_landed(_pos: Vector3, impact: float) -> void:
	if impact > 0.75 and state == "shift":
		_damage(0.08, "Atterrissage brutal…")

# A car clipped the player.
func on_hit_by_car(dir: Vector3, speed: float) -> void:
	player.knock(dir, clampf(speed / 7.0, 0.5, 1.2))
	if state == "shift":
		_damage(0.3, "Attention aux voitures !")
	_sfx("bump", 0.0, 0.7)

func _on_thief_caught(pos: Vector3) -> void:
	_chase_t = 0.0
	_sfx("cash")
	player.add_trauma(0.35)
	hud.float_text(pos + Vector3.UP * 1.8, "Arrêté !", Color(0.6, 1.0, 0.6))
	if state == "shift":
		cash += 25.0
		stats["thieves"] += 1
		hud.stamp("Voleur arrêté !", "+25 $ de récompense", Color(0.6, 1.0, 0.6))
	else:
		hud.stamp("Voleur arrêté !", "Merci !", Color(0.6, 1.0, 0.6))
	hud.alert("")
	_thief_t = rng.randf_range(65.0, 100.0)

func _on_thief_escaped() -> void:
	if state not in ["shift", "free"]:
		return
	_sfx("fail")
	hud.toast("Le voleur s'est enfui…", Color(1.0, 0.6, 0.4))
	hud.alert("")
	_thief_t = rng.randf_range(55.0, 90.0)

func _collect_fleur(i: int) -> void:
	var f: Node3D = fleur_nodes[i]
	fleur_nodes.erase(i)
	hud.float_text(f.global_position + Vector3.UP * 0.5, "Fleur de lys", Color(1.0, 0.85, 0.4))
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
		hud.stamp("Toutes les fleurs de lys !", "Le Vieux-Montréal n'a plus de secrets.", Color(1.0, 0.85, 0.4))

# ------------------------------------------------------------------ tick

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var cam: Camera3D = world.call("active_camera")
	if state in ["shift", "free"]:
		var ppos := player.global_position
		for i in fleur_nodes.keys():
			if (fleur_nodes[i] as Node3D).global_position.distance_to(ppos + Vector3.UP * 0.8) < 1.3:
				_collect_fleur(i)
		_tick_thief(delta, ppos)
		_tick_contact(delta, ppos)
	if state == "shift":
		shift_t -= delta
		if world.has_method("set_shift_progress"):
			world.call("set_shift_progress", 1.0 - shift_t / SHIFT_LEN)
		if _next_offer_t > 0.0:
			_next_offer_t -= delta
			if _next_offer_t <= 0.0:
				_refresh_offers()
				if offers.is_empty():
					_next_offer_t = 1.0
		# untaken offers lapse and are replaced
		for o in offers:
			o["age"] += delta
		if offers.size() == 2 and offers[0]["age"] > OFFER_LIFE:
			offers.pop_front()
			_refresh_offers()
		if not order.is_empty():
			order["t"] -= delta
		# arrive = act (rolling or knocked over doesn't count)
		if not player.rolling() and not player.knocked():
			_try_interact()
		if shift_t <= 0.0:
			end_shift()
	_update_hud(cam)

func _tick_contact(delta: float, ppos: Vector3) -> void:
	_bump_cd -= delta
	var carrying := state == "shift" and not order.is_empty()
	var sp := player.horizontal_speed()
	if _bump_cd <= 0.0 and peds.check_bump(ppos, sp, player.rolling()):
		_bump_cd = 0.8
		player.add_trauma(0.3)
		if carrying:
			_damage(0.18, "Bousculade !")
		else:
			_sfx("bump", -8.0)
	# near misses at speed: small style tips while carrying
	var g := peds.near_misses(ppos, sp)
	if g > 0 and carrying:
		_graze_chain += g
		_graze_t = 1.6
		var bonus := 0.5 * g * (1.0 + 0.25 * mini(_graze_chain - 1, 6))
		cash += bonus
		stats["grazes"] += g
		_sfx("graze", -10.0, 1.0 + 0.06 * mini(_graze_chain, 8))
		hud.float_text(ppos + Vector3.UP * 2.1, "Frôlé ! +%.2f $" % bonus + ("  x%d" % _graze_chain if _graze_chain > 1 else ""), Color(0.85, 0.95, 1.0))
	_graze_t -= delta
	if _graze_t <= 0.0:
		_graze_chain = 0
	if player.rolling():
		if not peds.thief.is_empty():
			peds.tackle(ppos)
		if not _rolled_with_bag and carrying:
			_rolled_with_bag = true
			_damage(0.06, "Plongeon avec le colis…")
	else:
		_rolled_with_bag = false

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
				hud.toast("Un pickpocket s'enfuit avec un sac — rattrapez-le ! (Maj sprint, C plonger)", THIEF_COL)
		return
	_chase_t += delta
	var d := peds.thief_pos().distance_to(ppos)
	_lost_t = _lost_t + delta if d > 50.0 else 0.0
	if _lost_t > 5.0 or _chase_t > 45.0:
		peds.give_up_thief()

func _update_hud(cam: Camera3D) -> void:
	var targets: Array = []     # [pos, col, label]
	var route_to := Vector3.INF
	if state == "shift":
		var mins := int((SHIFT_LEN - shift_t) / SHIFT_LEN * 210.0)   # 19:30 -> 23:00
		hud.set_status(cash, "%02d:%02d" % [19 + (30 + mins) / 60, (30 + mins) % 60], combo, shift_t)
		hud.set_prompt("")
		if not order.is_empty():
			var tgt: Dictionary = order["home"]
			var dist := route_len(player.global_position, tgt["pos"])
			marker.set_proximity(player.global_position.distance_to(tgt["pos"]))
			var l1: String = ("EXPRESS  ·  " if order["express"] else "") + "LIVRER  ·  " + String(order["item"])
			var l2: String = "%d, %s   ·   %d m" % [tgt["number"], tgt["street"], int(dist)]
			var tl := ("%d s" % int(ceil(maxf(order["t"], 0.0)))) if order["t"] > 0.0 else "EN RETARD"
			hud.set_objective(l1, l2, DROP_COL, clampf(order["t"] / order["limit"], 0.0, 1.0), tl)
			hud.set_offers([])
			hud.set_condition(order["condition"])
			targets.append([tgt["pos"], DROP_COL, ""])
			route_to = tgt["pos"]
		elif offers.is_empty():
			hud.set_objective("En attente d'une commande…", "", Color(0.85, 0.85, 0.9), -1.0, "")
			hud.set_offers([])
			hud.set_condition(-1.0)
		else:
			hud.set_objective("CHOISISSEZ UNE COMMANDE", "allez chercher l'une des deux", PICKUP_COL, -1.0, "")
			var rows := []
			var best_d := INF
			for i in offers.size():
				var o: Dictionary = offers[i]
				var col := EXPRESS_COL if o["express"] else PICKUP_COL
				var d := route_len(player.global_position, o["shop"]["pos"])
				offer_markers[i].set_proximity(player.global_position.distance_to(o["shop"]["pos"]))
				rows.append({"col": col, "title": ("EXPRESS · " if o["express"] else "") + String(o["shop"]["name"]),
					"sub": "%s%s → %s · %d m" % [o["item"], " (fragile)" if o["fragile"] else "", o["home"]["street"], int(o["route"])],
					"pay": "~%d $" % int(o["pay_est"]), "dist": "%d m" % int(d), "life": 1.0 - o["age"] / OFFER_LIFE if offers.size() == 2 and i == 0 else -1.0})
				targets.append([o["shop"]["pos"], col, ""])
				if d < best_d:
					best_d = d
					route_to = o["shop"]["pos"]
			hud.set_offers(rows)
			hud.set_condition(-1.0)
	elif state == "free":
		hud.set_status(-1.0, "", 0, -1.0)
		hud.set_objective("", "", Color.WHITE, -1.0, "")
		hud.set_offers([])
		hud.set_condition(-1.0)
		hud.set_prompt("")
	if not peds.thief.is_empty() and state in ["shift", "free"]:
		targets.append([peds.thief_pos(), THIEF_COL, "VOLEUR"])
	hud.set_stamina(player.stamina, player.get("_winded"))
	if state in ["shift", "free"]:
		var route := route_points(player.global_position, route_to) if route_to != Vector3.INF else PackedVector3Array()
		hud.update_pointer(cam, targets)
		hud.update_map(player.global_position, cam.global_rotation.y, targets, route, world.get("traffic_positions"))
	else:
		hud.update_pointer(cam, [])

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
