class_name DebugPanel
extends Control
## Debug menu (F3 or the wrench in the left rail): time and light, contracts, instant work steps,
## vehicles, money, traffic and a performance overlay. All actions live in DebugTools.

const W := 318
const LIGHT := [["Uhr", -1.0], ["Tag", 12.0], ["Abend", 20.6], ["Nacht", 23.5]]
const TRAFFIC := [["Aus", 0.0], ["50 %", 0.5], ["100 %", 1.0], ["200 %", 2.0]]
const PLACE_HINT := "Die Grube hängt am Mauszeiger: orange = passt, rot = passt nicht. Linksklick setzt den Auftrag, Rechtsklick bricht ab."

var panel: PanelContainer
var _time_lbl: Label
var _site_lbl: Label
var _veh_lbl: Label
var _place_btn: Button
var _place_hint: Label
var _accept_chk: CheckBox
var _auto_btn: Button
var _stats: Label
var _stats_on := false
var _light_btns: Array = []
var _traffic_btns: Array = []
var _season_btns: Array = []
var _speed_btns: Array = []
var _hud: HUD
var _tool: PlaceJobTool
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.theme()
	_build_stats()
	_build_panel()
	_refresh()


func toggle() -> void:
	panel.visible = not panel.visible
	if not panel.visible:
		_cancel_place()
	_refresh()


# ------------------------------------------------------------------------------------------
# Layout
# ------------------------------------------------------------------------------------------

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.flat(UI.BG, UI.ACCENT_DARK, 1, 3, Vector4(16, 14, 14, 14)))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	_place_panel(false)
	panel.offset_top = 64
	panel.offset_bottom = -12
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var outer := UI.vbox(10)
	panel.add_child(outer)
	var head := UI.hbox(8)
	head.add_child(UI.tex_icon("wrench", 18, UI.ACCENT))
	var title := UI.label("Debug", 18, UI.TEXT, 600)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.label("F3", 12, UI.DIM))
	var close := UI.icon_button("x", "Schließen (F3)")
	close.custom_minimum_size = Vector2(30, 30)
	close.pressed.connect(toggle)
	head.add_child(close)
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	# --- time and light ---
	v.add_child(UI.caps("Zeit & Licht"))
	_time_lbl = UI.label("", 13, UI.MUTED)
	v.add_child(_time_lbl)
	_row(v, [["06:00", func(): DebugTools.jump_to_hour(6.0)], ["09:00", func(): DebugTools.jump_to_hour(9.0)],
		["12:00", func(): DebugTools.jump_to_hour(12.0)], ["17:00", func(): DebugTools.jump_to_hour(17.0)],
		["20:00", func(): DebugTools.jump_to_hour(20.0)], ["23:00", func(): DebugTools.jump_to_hour(23.0)]], "Zur nächsten Uhrzeit vorspulen")
	_row(v, [["+1 h", func(): DebugTools.advance(60.0)], ["+6 h", func(): DebugTools.advance(360.0)],
		["+1 Tag", func(): DebugTools.advance(1440.0)]])
	v.add_child(UI.label("Licht festhalten (Uhr läuft weiter)", 12, UI.DIM))
	_light_btns = _row(v, LIGHT.map(func(o): return [o[0], func(): DebugTools.light_override(o[1])]))
	var seasons: Array = []
	for name in DebugTools.SEASONS:
		var doy: int = DebugTools.SEASONS[name]
		seasons.append([name, func(): DebugTools.set_season(doy)])
	_season_btns = _row(v, seasons)
	_speed_btns = _row(v, [["Tempo 10×", func(): DebugTools.turbo(10.0)], ["30×", func(): DebugTools.turbo(30.0)], ["60×", func(): DebugTools.turbo(60.0)]],
		"Zurück zu normalem Tempo mit 1, 2, 3 oder Leertaste")
	v.add_child(UI.sep())

	# --- contracts ---
	v.add_child(UI.caps("Aufträge"))
	_row(v, [["Neue Ausschreibung", func(): DebugTools.new_offer()]])
	var pr := UI.hbox(6)
	_place_btn = UI.button("Auftrag platzieren", "map-pin")
	_place_btn.toggle_mode = true
	_place_btn.toggled.connect(func(on): _start_place() if on else _cancel_place())
	pr.add_child(_place_btn)
	_accept_chk = CheckBox.new()
	_accept_chk.text = "sofort annehmen"
	_accept_chk.button_pressed = true
	_accept_chk.focus_mode = Control.FOCUS_NONE
	pr.add_child(_accept_chk)
	v.add_child(pr)
	_place_hint = UI.label(PLACE_HINT, 12, UI.ACCENT)
	_place_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_hint.visible = false
	v.add_child(_place_hint)
	v.add_child(UI.sep())

	# --- construction site ---
	v.add_child(UI.caps("Baustelle"))
	_site_lbl = UI.label("", 13, UI.MUTED)
	_site_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_site_lbl)
	_row(v, [["Schritt sofort erledigen", func(): DebugTools.finish_step(DebugTools.current_site())]], "Aktueller Arbeitsschritt ist sofort fertig")
	_row(v, [["Bis zur Abnahme", func(): DebugTools.finish_all(DebugTools.current_site())],
		["Fahrzeuge hinschicken", func(): DebugTools.send_fleet(DebugTools.current_site())]])
	var ar := _row(v, [["Arbeitsschritte automatisch: aus", func():
		var s := DebugTools.current_site()
		if s:
			s.auto_continue = not s.auto_continue
			s.changed.emit(s)]])
	_auto_btn = ar[0]
	v.add_child(UI.sep())

	# --- vehicle ---
	v.add_child(UI.caps("Fahrzeug"))
	_veh_lbl = UI.label("", 13, UI.MUTED)
	v.add_child(_veh_lbl)
	_row(v, [["In die Zentrale setzen", func(): DebugTools.teleport_to_hq(Game.selected if Game.selected is Vehicle else null)]],
		"Gewähltes Fahrzeug sofort auf einen freien Stellplatz der Zentrale")
	v.add_child(UI.sep())

	# --- money, traffic, display ---
	v.add_child(UI.caps("Geld"))
	_row(v, [["+10.000 €", func(): DebugTools.add_money(10000.0)], ["+100.000 €", func(): DebugTools.add_money(100000.0)]])
	v.add_child(UI.caps("Verkehr"))
	_traffic_btns = _row(v, TRAFFIC.map(func(o): return [o[0], func(): DebugTools.set_traffic(o[1])]))
	_row(v, [["Verkehr leeren", func(): DebugTools.clear_traffic()]])
	v.add_child(UI.caps("Anzeige"))
	_row(v, [["Leistungsanzeige an/aus", func(): _stats_on = not _stats_on]])


## A row of small buttons; items: [[text, callable], …]. Returns the buttons.
func _row(parent: Control, items: Array, tip := "") -> Array:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	parent.add_child(h)
	var out: Array = []
	for it in items:
		var b := UI.button(it[0])
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = tip
		var f: Callable = it[1]
		b.pressed.connect(func():
			f.call()
			_refresh())
		h.add_child(b)
		out.append(b)
	return out


func _build_stats() -> void:
	_stats = UI.label("", 12, UI.TEXT)
	_stats.add_theme_stylebox_override("normal", UI.flat(Color(0, 0, 0, 0.72), Color(0, 0, 0, 0), 0, 3, Vector4(8, 4, 8, 4)))
	_stats.anchor_left = 0.5
	_stats.anchor_right = 0.5
	_stats.offset_left = -330
	_stats.offset_right = 330
	_stats.offset_top = 60
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.visible = false
	add_child(_stats)


# ------------------------------------------------------------------------------------------
# Placing a contract by click
# ------------------------------------------------------------------------------------------

func _start_place() -> void:
	if Game.world == null:
		_place_btn.set_pressed_no_signal(false)
		return
	_tool = PlaceJobTool.new()
	_tool.done.connect(_on_place_done)
	_tool.preview_changed.connect(_on_preview_changed)
	Game.world.tool = _tool
	_place_hint.text = PLACE_HINT
	_place_hint.visible = true


func _cancel_place() -> void:
	if Game.world and Game.world.tool == _tool and _tool != null:
		Game.world.tool = null
	if _tool != null:
		_tool.dispose()
	_tool = null
	if _place_btn:
		_place_btn.set_pressed_no_signal(false)
	if _place_hint:
		_place_hint.visible = false


func _on_place_done(p: Variant) -> void:
	# a click on an unsuitable spot keeps the mode on, so the next click can try elsewhere
	if p is Vector2 and not DebugTools.try_place_job_at(p, _accept_chk.button_pressed, _tool.pipe_i if _tool else -1).ok:
		return
	_cancel_place()
	_refresh()


# ------------------------------------------------------------------------------------------
# Live state
# ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Game.world == null:
		panel.visible = false
		_stats.visible = false
		_cancel_place()
		return
	_t += delta / maxf(Engine.time_scale, 0.001)   # real time, independent of game speed
	if _tool != null:
		_tool.update_preview()
	if _t >= 0.25:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	_stats.visible = _stats_on and Game.world != null
	if _stats.visible:
		var tr: TrafficSim = Game.world.traffic
		_stats.text = "FPS %d · %.1f ms · Draw-Calls %d · Objekte %d · Verkehr %d · Tempo %d×" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), tr.traffic_count(), int(Engine.time_scale)]
	if not panel.visible or Game.world == null:
		return
	if _hud == null or not is_instance_valid(_hud):
		for c in get_parent().get_children():
			if c is HUD:
				_hud = c
	_place_panel(_hud != null and _hud.right.visible)
	var dn: DayNight = Game.world.day_night
	_time_lbl.text = "%s · %s · Tempo %d×%s" % [Clock.date_string(), Clock.time_string(), int(Engine.time_scale) if not Clock.is_paused() else 0,
		(" · Licht fest auf %02d:%02d" % [int(dn.override_hour), int(fmod(dn.override_hour, 1.0) * 60.0)]) if dn and dn.override_hour >= 0.0 else ""]
	for i in _light_btns.size():
		_mark(_light_btns[i], dn != null and is_equal_approx(dn.override_hour, LIGHT[i][1]))
	for i in _season_btns.size():
		_mark(_season_btns[i], Clock.day_of_year == DebugTools.SEASONS.values()[i])
	for i in _speed_btns.size():
		_mark(_speed_btns[i], not Clock.is_paused() and is_equal_approx(Engine.time_scale, [10.0, 30.0, 60.0][i]))
	for i in _traffic_btns.size():
		_mark(_traffic_btns[i], is_equal_approx(Game.world.traffic.density_scale, TRAFFIC[i][1]))
	var s := DebugTools.current_site()
	if s:
		_site_lbl.text = "%s · %s – Schritt %d/%d: %s" % [s.job.short_title(), s.job.location(), s.phase + 1, Site.STEPS.size(),
			Site.STEPS[mini(s.phase, Site.STEPS.size() - 1)].title]
		_auto_btn.text = "Arbeitsschritte automatisch: %s" % ("an" if s.auto_continue else "aus")
	else:
		_site_lbl.text = "Keine aktive Baustelle – erst einen Auftrag annehmen oder platzieren."
		_auto_btn.text = "Arbeitsschritte automatisch: –"
	var veh: Vehicle = Game.selected if Game.selected is Vehicle and is_instance_valid(Game.selected) else null
	_veh_lbl.text = ("%s · %s" % [veh.vname, veh.status_text]) if veh else "Kein Fahrzeug gewählt (Linksklick auf ein Fahrzeug)."


## Right screen edge; left of the HUD's context panel while that is open.
func _place_panel(beside_context: bool) -> void:
	panel.offset_right = -(HUD.RIGHT_W + 10) if beside_context else -10
	panel.offset_left = panel.offset_right - W


func _mark(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", UI.flat(UI.ACCENT_DARK, UI.ACCENT, 1))
	else:
		b.remove_theme_stylebox_override("normal")


func _unhandled_key_input(ev: InputEvent) -> void:
	# Esc leaves the placing mode first
	if _tool and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_cancel_place()
		get_viewport().set_input_as_handled()


func _on_preview_changed(text: String, ok: bool) -> void:
	if _place_hint == null:
		return
	_place_hint.text = PLACE_HINT if text == "" else text
	_place_hint.add_theme_color_override("font_color", UI.ACCENT if ok or text == "" else UI.ERROR)
