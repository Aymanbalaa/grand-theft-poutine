class_name SliceHud
extends CanvasLayer
# Game HUD for "Nuit de livraison": cash/clock/combo, objective card with an
# order timer, offer cards, bag condition, stamina, toasts, a centred stamp
# (LIVRÉ !), the AU VOLEUR alert, a hit flash, world-anchored floating text,
# edge-of-screen pointers to every target, a minimap with the walking route,
# and the title / end-of-shift screens.

const UI_FONT := "res://assets/slice/fonts/JosefinSans.ttf"
const TITLE_FONT := "res://assets/slice/fonts/PlayfairDisplay.ttf"
const INK := Color(0.96, 0.94, 0.9)
const SHADE := Color(0.03, 0.035, 0.05, 0.62)

var _status: Label
var _clock: Label
var _combo: Label
var _obj_box: PanelContainer
var _obj1: Label
var _obj2: Label
var _obj_bar: ProgressBar
var _obj_time: Label
var _cond_box: HBoxContainer
var _cond_bar: ProgressBar
var _prompt: Label
var _toasts: VBoxContainer
var _alert: Label
var _alert_t := 0.0
var _pointer: Pointer
var _map: MiniMap
var _title: Control
var _summary: Control
var _summary_text: RichTextLabel
var _offers_box: VBoxContainer
var _stam: ProgressBar
var _stam_a := 0.0
var _flash: ColorRect
var _stamp: VBoxContainer
var _stamp1: Label
var _stamp2: Label
var _stamp_tw: Tween
var _pause: Control

func _font(path: String) -> Font:
	if path != UI_FONT:
		return load(path) as Font
	# Josefin's variable default is light; a semi-bold instance reads over rain
	var fv := FontVariation.new()
	fv.base_font = load(path)
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): 600}
	return fv

func _label(text: String, size: int, col := INK, font := UI_FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel_style(alpha := 0.62) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SHADE.r, SHADE.g, SHADE.b, alpha)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb

func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 6)
	b.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _ready() -> void:
	layer = 11   # above the lens post-process so vignette/grain never dim it
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = """shader_type canvas_item;
uniform vec4 col : source_color = vec4(1.0, 0.3, 0.2, 0.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float e = smoothstep(0.35, 1.25, length(p * vec2(1.0, 0.8)));
	COLOR = vec4(col.rgb, col.a * e);
}"""
	fm.shader = fsh
	_flash.material = fm
	root.add_child(_flash)

	_pointer = Pointer.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.font = _font(UI_FONT)
	root.add_child(_pointer)

	# status, top-right
	var st := VBoxContainer.new()
	st.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	st.offset_left = -300
	st.offset_right = -32
	st.offset_top = 24
	st.alignment = BoxContainer.ALIGNMENT_BEGIN
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = _label("", 46, Color(0.75, 1.0, 0.75))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock = _label("", 22, Color(0.85, 0.87, 0.95))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo = _label("", 20, Color(1.0, 0.85, 0.4))
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	st.add_child(_status)
	st.add_child(_clock)
	st.add_child(_combo)
	root.add_child(st)

	# objective card, top-centre
	_obj_box = PanelContainer.new()
	_obj_box.add_theme_stylebox_override("panel", _panel_style())
	_obj_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_obj_box.offset_left = -330
	_obj_box.offset_right = 330
	_obj_box.offset_top = 22
	_obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ov := VBoxContainer.new()
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj1 = _label("", 24)
	_obj1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj2 = _label("", 19, Color(0.82, 0.84, 0.9))
	_obj2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj_bar = _bar(Color(0.3, 0.85, 1.0))
	_obj_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_obj_time = _label("", 18)
	_obj_time.custom_minimum_size = Vector2(110, 0)
	_obj_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_obj_bar)
	row.add_child(_obj_time)
	ov.add_child(_obj1)
	ov.add_child(_obj2)
	ov.add_child(row)
	_obj_box.add_child(ov)
	root.add_child(_obj_box)

	# offer cards, under the objective card
	_offers_box = VBoxContainer.new()
	_offers_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_offers_box.offset_left = -330
	_offers_box.offset_right = 330
	_offers_box.offset_top = 112
	_offers_box.add_theme_constant_override("separation", 6)
	_offers_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_offers_box)

	# bag condition, under the objective
	_cond_box = HBoxContainer.new()
	_cond_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_cond_box.offset_left = -150
	_cond_box.offset_right = 150
	_cond_box.offset_top = 150
	_cond_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := _label("Colis", 16, Color(0.85, 0.85, 0.9))
	_cond_bar = _bar(Color(0.95, 0.75, 0.35))
	_cond_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cond_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cond_box.add_child(cl)
	_cond_box.add_child(_cond_bar)
	root.add_child(_cond_box)

	# stamina, bottom-centre, only while it isn't full
	_stam = _bar(Color(0.95, 0.95, 0.98))
	_stam.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_stam.offset_left = -110
	_stam.offset_right = 110
	_stam.offset_top = -64
	_stam.offset_bottom = -58
	_stam.modulate.a = 0.0
	root.add_child(_stam)

	# prompt, bottom-centre
	_prompt = _label("", 26, Color(1, 1, 1))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -170
	_prompt.offset_bottom = -130
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_prompt)

	# toasts, centre-left stack
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_toasts.offset_left = 32
	_toasts.offset_right = 760
	_toasts.offset_top = -40
	_toasts.offset_bottom = 200
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	_alert = _label("", 72, Color(1.0, 0.3, 0.25), TITLE_FONT)
	_alert.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_alert.offset_left = -500
	_alert.offset_right = 500
	_alert.offset_top = -210
	_alert.offset_bottom = -110
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_alert)

	# big centred stamp (LIVRÉ !, shift start, thief caught)
	_stamp = VBoxContainer.new()
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stamp.offset_left = -600
	_stamp.offset_right = 600
	_stamp.offset_top = -260
	_stamp.offset_bottom = -100
	_stamp.alignment = BoxContainer.ALIGNMENT_CENTER
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp1 = _label("", 76, INK, TITLE_FONT)
	_stamp1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp2 = _label("", 28, INK)
	_stamp2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp.add_child(_stamp1)
	_stamp.add_child(_stamp2)
	_stamp.modulate.a = 0.0
	root.add_child(_stamp)

	_map = MiniMap.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_map.offset_left = -260
	_map.offset_top = -260
	_map.offset_right = -24
	_map.offset_bottom = -24
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.font = _font(UI_FONT)
	root.add_child(_map)

	_build_title(root)
	_build_summary(root)
	_build_pause(root)
	set_status(-1.0, "", 0, -1.0)
	set_objective("", "", INK, -1.0, "")
	set_condition(-1.0)

func _build_title(root: Control) -> void:
	_title = Control.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var small := _label("MTL  ·  VIEUX-MONTRÉAL", 22, Color(0.85, 0.85, 0.92))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var big := _label("Nuit de livraison", 110, Color(1.0, 0.93, 0.8), TITLE_FONT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tag := _label("Un soir de pluie. Deux commandes à la fois : à vous de choisir. Des pickpockets à attraper.", 24, Color(0.88, 0.88, 0.94))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	var menu := _label("ENTRÉE  —  commencer un quart (6 min)          ESPACE  —  balade libre", 24, Color(1, 1, 1))
	menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rec := _label("", 20, Color(1.0, 0.85, 0.45))
	rec.name = "Record"
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var keys := _label("WASD courir · Maj sprint · Espace sauter · C / clic droit plonger · Clic bousculer · Alt marcher · Tab visite · F1-F3 ambiance\nManette : stick gauche · RT sprint · A sauter · B plonger · X bousculer · Start quart · Select balade", 17, Color(0.8, 0.8, 0.86, 0.85))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for c in [small, big, tag, gap, menu, rec, keys]:
		v.add_child(c)
	_title.add_child(v)
	root.add_child(_title)

func _build_summary(root: Control) -> void:
	_summary = CenterContainer.new()
	_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(0.82))
	p.custom_minimum_size = Vector2(820, 0)
	var v := VBoxContainer.new()
	var h := _label("Fin du quart", 64, Color(1.0, 0.93, 0.8), TITLE_FONT)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_text = RichTextLabel.new()
	_summary_text.bbcode_enabled = true
	_summary_text.fit_content = true
	_summary_text.scroll_active = false
	_summary_text.add_theme_font_override("normal_font", _font(UI_FONT))
	_summary_text.add_theme_font_size_override("normal_font_size", 24)
	var bold := FontVariation.new()
	bold.base_font = load(UI_FONT)
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	_summary_text.add_theme_font_override("bold_font", bold)
	_summary_text.add_theme_font_size_override("bold_font_size", 26)
	_summary_text.add_theme_color_override("default_color", INK)
	var foot := _label("ENTRÉE — nouveau quart        ESPACE — balade libre", 20, Color(0.9, 0.9, 0.95))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	v.add_child(_summary_text)
	v.add_child(foot)
	p.add_child(v)
	_summary.add_child(p)
	_summary.visible = false
	root.add_child(_summary)

func _build_pause(root: Control) -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := _label("Pause", 96, Color(1.0, 0.93, 0.8), TITLE_FONT)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var a := _label("ÉCHAP / START  —  reprendre", 26)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := _label("T / SELECT  —  retour au titre", 26, Color(0.85, 0.85, 0.92))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var k := _label("Maj sprint · Espace sauter · C plonger (attrape les voleurs) · Courir près des passants avec un colis : « Frôlé ! »\nVoitures : elles freinent, mais pas toujours à temps.", 18, Color(0.8, 0.8, 0.86, 0.85))
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for c in [h, a, b, k]:
		v.add_child(c)
	_pause.add_child(v)
	_pause.visible = false
	root.add_child(_pause)

func show_pause(on: bool) -> void:
	_pause.visible = on

# ------------------------------------------------------------------ API

var _play := true

func set_gameplay_visible(on: bool) -> void:
	_play = on
	for n in [_status, _clock, _combo, _prompt, _map, _pointer, _stam]:
		(n as Control).visible = on
	if not on:
		_obj_box.visible = false
		_cond_box.visible = false
		_offers_box.visible = false

func show_title(best: float, found: int, total: int, medal: Array = []) -> void:
	set_gameplay_visible(false)
	_title.visible = true
	_summary.visible = false
	var rec := _title.find_child("Record", true, false) as Label
	rec.text = ("Record : %.2f $" % best if best > 0.0 else "") + ("   (médaille %s)" % medal[1] if not medal.is_empty() else "") \
		+ ("     Fleurs de lys : %d / %d" % [found, total]) + "\nObjectifs : bronze 150 $ · argent 250 $ · or 350 $"
	_map.visible = false

func hide_overlays() -> void:
	_title.visible = false
	_summary.visible = false
	set_gameplay_visible(true)

func show_summary(s: Dictionary, total: float, best: float, record: bool, found: int, ftotal: int) -> void:
	_summary.visible = true
	alert("")
	for c in _toasts.get_children():
		c.queue_free()
	set_prompt("")
	set_gameplay_visible(false)
	var t := ""
	t += "[center]Livraisons : [b]%d[/b]   (à temps %d · en retard %d)\n" % [s["deliveries"], s["on_time"], s["late"]]
	t += "Pourboires : [b]%.2f $[/b]     Meilleure série : x%d\n" % [s["tips"], s["best_combo"]]
	t += "Voleurs arrêtés : [b]%d[/b]     Fleurs trouvées : %d  (total %d / %d)\n" % [s["thieves"], s["fleurs"], found, ftotal]
	if s["deliveries"] > 0:
		t += "Note moyenne : [b]%.1f ★[/b]     Frôlés : %d     Colis abîmés : %d\n" % [float(s["stars"]) / s["deliveries"], s["grazes"], s["damage"]]
	if s["fines"] > 0.0:
		t += "Amendes : −%.2f $\n" % s["fines"]
	t += "\n[font_size=44][color=#bff5bf]%.2f $[/color][/font_size]\n" % total
	var med: Array = s.get("medal", [])
	if not med.is_empty():
		t += "[font_size=30][color=#%s]Médaille %s[/color][/font_size]\n" % [(med[2] as Color).to_html(false), med[1]]
	else:
		t += "[color=#b0b0b8]Bronze à 150 $ — encore %.0f $[/color]\n" % maxf(0.0, 150.0 - total)
	t += ("[color=#ffd873]Nouveau record ![/color]" if record else "Record : %.2f $" % best) + "[/center]"
	_summary_text.text = t

func set_status(cash: float, clock: String, combo: int, shift_left: float) -> void:
	_status.visible = cash > -999.0 and _play and clock != ""
	_status.text = "%.2f $" % cash
	_clock.text = clock + ("    reste %d:%02d" % [int(shift_left) / 60, int(shift_left) % 60] if shift_left >= 0.0 else "")
	_combo.text = "série x%d" % combo if combo > 1 else ""

func set_objective(l1: String, l2: String, col: Color, frac: float, tl: String) -> void:
	_obj_box.visible = l1 != "" and _play
	_obj1.text = l1
	_obj1.add_theme_color_override("font_color", col)
	_obj2.text = l2
	_obj2.visible = l2 != ""
	_obj_bar.visible = frac >= 0.0
	_obj_bar.value = maxf(frac, 0.0)
	var fill := _obj_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(1.0, 0.35, 0.3) if frac < 0.25 else Color(0.3, 0.85, 1.0)
	_obj_time.visible = tl != ""
	_obj_time.text = tl
	_obj_time.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if tl == "EN RETARD" else INK)

# Offer cards: [{col, title, sub, pay, dist, life}]
func set_offers(rows: Array) -> void:
	_offers_box.visible = not rows.is_empty() and _play
	var key := ""
	for r in rows:
		key += String(r["title"]) + String(r["sub"]) + "|"
	if String(_offers_box.get_meta("key", "")) != key:
		_offers_box.set_meta("key", key)
		for c in _offers_box.get_children():
			c.free()
		for r in rows:
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", _panel_style(0.55))
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 14)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sw := ColorRect.new()
			sw.color = r["col"]
			sw.custom_minimum_size = Vector2(5, 0)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(_label(r["title"], 21, r["col"]))
			v.add_child(_label(r["sub"], 16, Color(0.82, 0.84, 0.9)))
			var right := VBoxContainer.new()
			right.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pay := _label(r["pay"], 24, Color(0.75, 1.0, 0.75))
			pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var dist := _label(r["dist"], 16, Color(0.82, 0.84, 0.9))
			dist.name = "Dist"
			dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(pay)
			right.add_child(dist)
			h.add_child(sw)
			h.add_child(v)
			h.add_child(right)
			card.add_child(h)
			_offers_box.add_child(card)
	for i in mini(rows.size(), _offers_box.get_child_count()):
		var dl := _offers_box.get_child(i).find_child("Dist", true, false) as Label
		var life: float = rows[i]["life"]
		dl.text = String(rows[i]["dist"]) + ("  ·  expire bientôt" if life >= 0.0 and life < 0.25 else "")

func set_condition(frac: float) -> void:
	_cond_box.visible = frac >= 0.0 and _play
	_cond_bar.value = maxf(frac, 0.0)
	var fill := _cond_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(1.0, 0.4, 0.3) if frac < 0.5 else Color(0.95, 0.75, 0.35)

func set_stamina(v: float, winded: bool) -> void:
	_stam.value = v
	var fill := _stam.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(1.0, 0.55, 0.3) if winded else Color(0.95, 0.95, 0.98)
	_stam_a = 0.85 if v < 0.995 else 0.0

func set_prompt(t: String) -> void:
	_prompt.text = t

func toast(text: String, col := INK) -> void:
	var l := _label(text, 24, col)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

func stamp(big: String, small: String, col: Color) -> void:
	_stamp1.text = big
	_stamp1.add_theme_color_override("font_color", col)
	_stamp2.text = small
	_stamp.pivot_offset = _stamp.size * 0.5
	if _stamp_tw != null:
		_stamp_tw.kill()
	_stamp_tw = create_tween()
	_stamp.modulate.a = 1.0
	_stamp.scale = Vector2(1.3, 1.3)
	_stamp_tw.tween_property(_stamp, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stamp_tw.tween_interval(1.3)
	_stamp_tw.tween_property(_stamp, "modulate:a", 0.0, 0.5)

func flash(col: Color, strength := 0.25) -> void:
	var m := _flash.material as ShaderMaterial
	var tw := create_tween()
	tw.tween_method(func(a: float): m.set_shader_parameter("col", Color(col.r, col.g, col.b, a)), strength, 0.0, 0.45)

# World-anchored text that rises and fades (+12.40 $, Frôlé !, ...).
func float_text(pos: Vector3, text: String, col: Color) -> void:
	_pointer.floaters.append({"pos": pos, "text": text, "col": col, "t": 0.0})

func alert(text: String) -> void:
	_alert.text = text
	_alert_t = 3.0 if text != "" else 0.0
	if text != "" and _stamp_tw != null:
		_stamp_tw.kill()
		_stamp.modulate.a = 0.0

func update_pointer(cam: Camera3D, targets: Array) -> void:
	_pointer.cam = cam
	_pointer.targets = targets
	_pointer.queue_redraw()

func update_map(ppos: Vector3, yaw: float, targets: Array, route: PackedVector3Array, cars: Array = []) -> void:
	_map.player = ppos
	_map.yaw = yaw
	_map.targets = targets
	_map.route = route
	_map.cars = cars
	_map.queue_redraw()

func _process(delta: float) -> void:
	_stam.modulate.a = lerpf(_stam.modulate.a, _stam_a, clampf(delta * 6.0, 0, 1))
	if not _pointer.floaters.is_empty():
		for f in _pointer.floaters:
			f["t"] += delta
		_pointer.floaters = _pointer.floaters.filter(func(f): return f["t"] < 1.6)
		_pointer.queue_redraw()
	if _alert_t > 0.0:
		_alert_t -= delta
		_alert.modulate.a = clampf(_alert_t, 0.0, 1.0) * (0.75 + 0.25 * sin(_alert_t * 14.0))
	else:
		_alert.modulate.a = 0.0

# ------------------------------------------------------------------ widgets

class Pointer extends Control:
	# Per target: on-screen, a chevron + distance over it; off-screen, an arrow
	# pinned to the screen edge pointing the way. Also draws floating texts.
	var cam: Camera3D
	var targets: Array = []     # [pos, col, label]
	var floaters: Array = []
	var font: Font

	func _draw() -> void:
		if cam == null:
			return
		for t in targets:
			_draw_target(t[0], t[1], t[2])
		for f in floaters:
			var p: Vector3 = f["pos"] + Vector3.UP * f["t"] * 0.9
			if cam.is_position_behind(p):
				continue
			var sp := cam.unproject_position(p)
			var a: float = clampf(1.6 - f["t"], 0.0, 1.0) * clampf(f["t"] * 8.0, 0.0, 1.0)
			var c: Color = f["col"]
			draw_string(font, sp + Vector2(-198, 2), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 400, 26, Color(0, 0, 0, 0.6 * a))
			draw_string(font, sp + Vector2(-200, 0), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 400, 26, Color(c.r, c.g, c.b, a))

	func _draw_target(target: Vector3, col: Color, label: String) -> void:
		var vs := get_viewport_rect().size
		var tp := target + Vector3.UP * 2.4
		var dist := cam.global_position.distance_to(target)
		var behind := cam.is_position_behind(tp)
		var sp := cam.unproject_position(tp)
		var margin := 60.0
		var inside := not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin
		var txt := ("%s  " % label if label != "" else "") + "%d m" % int(dist)
		if inside:
			var pts := PackedVector2Array([sp + Vector2(-12, -18), sp + Vector2(12, -18), sp + Vector2(0, 0)])
			draw_colored_polygon(pts, col)
			draw_string(font, sp + Vector2(-80, -26), txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, col)
			return
		var c := vs * 0.5
		var dir := (sp - c)
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var hx := vs.x * 0.5 - margin
		var hy := vs.y * 0.5 - margin
		var k := minf(hx / maxf(abs(dir.x), 1e-4), hy / maxf(abs(dir.y), 1e-4))
		var p := c + dir * k
		var perp := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * 20.0, p - dir * 8.0 + perp * 14.0, p - dir * 8.0 - perp * 14.0])
		draw_colored_polygon(tri, col)
		draw_string(font, p - dir * 44.0 + Vector2(-80, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, col)

class MiniMap extends Control:
	# North-up map of the quarter's three streets: walking route, targets,
	# cars, player arrow.
	var player := Vector3.ZERO
	var yaw := 0.0
	var targets: Array = []
	var route := PackedVector3Array()
	var cars: Array = []
	var font: Font
	const VIEW := 70.0   # metres from centre to edge

	func _w2m(p: Vector3) -> Vector2:
		var s := size * 0.5
		return s + Vector2(p.x - player.x, p.z - player.z) / VIEW * s.x

	func _rect(x0: float, z0: float, x1: float, z1: float, c: Color) -> void:
		var a := _w2m(Vector3(x0, 0, z0))
		var b := _w2m(Vector3(x1, 0, z1))
		var r := Rect2(a, b - a).abs().intersection(Rect2(Vector2.ZERO, size))
		if r.size.x > 0 and r.size.y > 0:
			draw_rect(r, c)

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.035, 0.05, 0.6))
		var street := Color(0.55, 0.57, 0.62, 0.9)
		_rect(-5.9, 45.0, 5.9, -112.0, street)        # rue Saint-Paul
		_rect(-95.0, -45.7, 95.0, -58.3, street)      # rue Saint-Vincent
		_rect(-46.0, -112.0, 46.0, -124.0, street)    # rue de la Commune
		_rect(-46.0, -124.0, 46.0, -146.0, Color(0.35, 0.33, 0.3, 0.8))  # market hall
		var dome := _w2m(Vector3(0, 0, -135))
		if Rect2(Vector2.ZERO, s).has_point(dome):
			draw_circle(dome, 6.0, Color(0.75, 0.77, 0.8))
		if route.size() > 1:
			var pts := PackedVector2Array()
			for rp in route:
				pts.append(_w2m(rp))
			var rc: Color = targets[0][1] if not targets.is_empty() else Color.WHITE
			draw_polyline(pts, Color(rc.r, rc.g, rc.b, 0.85), 3.0, true)
		for cp in cars:
			var m := _w2m(cp)
			if Rect2(Vector2.ZERO, s).has_point(m):
				draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.9, 0.7, 0.8))
		for tg in targets:
			var tcol: Color = tg[1]
			var t := _w2m(tg[0])
			var tc := Vector2(clampf(t.x, 6, s.x - 6), clampf(t.y, 6, s.y - 6))
			draw_circle(tc, 7.0, tcol)
			draw_arc(tc, 10.0, 0, TAU, 20, Color(tcol.r, tcol.g, tcol.b, 0.5), 2.0)
		# player arrow (camera yaw; -Z is up on the map)
		var c := s * 0.5
		var f := Vector2(-sin(yaw), -cos(yaw))
		var r := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([c + f * 11.0, c - f * 7.0 + r * 7.0, c - f * 3.0, c - f * 7.0 - r * 7.0]), Color(1, 1, 1))
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.25), false, 1.5)
