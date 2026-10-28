class_name ClosureDesigner
extends Control
## Closure designer ("Absperrung planen", #9): plan view of one site in which the player places
## Leitbaken, Leitkegel, Absperrschranken, Absperrgitter, yellow markings and signs one by one or as
## chains (straight or curved). Shows trench, work area, machine slots and the traffic path; checks
## the plan against basic rules. Opened by the HUD; "Übernehmen" hands the plan to Site.set_plan().
## While open, the game is paused, the light is set to noon and trees are hidden.

signal closed(accepted: bool)

const TOP_H := 54
const LEFT_W := 292
const RIGHT_W := 330
const SNAP_PX := 12.0
const ROT_STEP := PI / 12.0
const RED := Color(0.85, 0.08, 0.08)
const WHITE := Color(0.97, 0.97, 0.95)
const DARK := Color(0.06, 0.06, 0.06)
const YELLOW := Color(1.0, 0.8, 0.05)
const LAMP := Color(1.0, 0.9, 0.3)
const CONE := Color(1.0, 0.42, 0.08)
const BLUE := Color(0.0, 0.36, 0.72)
const TRAFFIC := Color(0.35, 0.78, 1.0)
const MODES := [["single", "Einzeln", "Ein Teil pro Klick"], ["line", "Gerade", "Kette entlang einer Geraden: Klick Anfang, Klick Ende (weiter mit dem nächsten Klick)"],
	["curve", "Kurve", "Kette entlang einer Kurve: Klick Anfang, Klick Ende, dann die Biegung klicken"],
	["select", "Auswählen", "Teile anklicken oder aufziehen, verschieben, drehen (R), löschen (Entf)"], ["erase", "Radierer", "Teile anklicken oder überstreichen, um sie zu entfernen"]]

var site: Site
var lay: SiteLayout
var world: World
var plan: ClosurePlan
var kind := "bake"
var mode := "single"
var spacing := {}
var snap := true
var rot := 0.0                 # extra rotation of single items (R)
var dirty := false

var _chain := PackedVector2Array()   # line: start point; curve: [start] or [start, end]
var _chain_segments := 0
var _chain_line := -1          # yellow marking that the current chain extends
var _mouse := Vector2.ZERO
var _mp := Vector2.ZERO        # map point under the mouse (snapped for placing)
var _mp_raw := Vector2.ZERO
var _over_map := false
var _sel: Array = []           # selected item indices
var _sel_line := -1
var _press := {}               # select / erase gesture in progress
var _undo: Array = []
var _redo: Array = []
var _checks: Array = []
var _ext := {}
var _prev_speed := 1
var _prev_light := -1.0
var _prev_tool: Object = null
var _trees: Array = []
var _cancel_t := 0.0
# screen mapping of the orthographic plan view (map point → screen)
var _o_map := Vector2.ZERO
var _o_scr := Vector2.ZERO
var _ex := Vector2.RIGHT
var _ez := Vector2.DOWN
var _ppm := 10.0

var canvas: Control
var kind_btns := {}
var mode_btns := {}
var spacing_box: HBoxContainer
var spacing_lbl: Label
var checks_box: VBoxContainer
var bom_box: VBoxContainer
var hint_lbl: Label
var accept_btn: Button
var cancel_btn: Button
var undo_btn: Button
var redo_btn: Button
var summary_lbl: Label


# ------------------------------------------------------------------------------------------
# Open / close
# ------------------------------------------------------------------------------------------

func open(s: Site) -> void:
	site = s
	lay = s.lay
	world = s.world
	plan = s.plan.copy()
	for k in ClosurePlan.KINDS:
		spacing[k] = ClosurePlan.default_spacing(k)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.theme()
	_build_ui()
	_prev_speed = Clock.speed_index
	Clock.set_speed(0)
	if world.day_night:
		_prev_light = world.day_night.override_hour
		world.day_night.override_hour = 12.5
		world.day_night.update_now()
	for t in world.city.find_children("trees", "MultiMeshInstance3D", true, false):
		if (t as Node3D).visible:
			(t as Node3D).visible = false
			_trees.append(t)
	if site.marker:
		site.marker.visible = false
	_prev_tool = world.tool
	world.tool = self
	frame_view()
	_changed(false)


## Camera over the whole closure, traffic of the closed lane running from left to right.
func frame_view() -> void:
	var ext: Dictionary = lay.extent_for(plan.items) if plan.custom else lay.default_extent()
	var a: float = minf(float(ext.det0), float(ext.van) - 4.0)
	var b: float = maxf(float(ext.det1), lay.s_taper1)
	# include the planned items (signs far ahead), but not items far away on other streets
	for it in plan.items:
		var sx := lay.lane_coords(ClosurePlan.item_center(it)).x
		if sx > lay.s0 - 90.0 and sx < lay.s_taper1 + 90.0:
			a = minf(a, sx)
			b = maxf(b, sx)
	a -= 8.0
	b += 6.0
	var mid := (a + b) * 0.5
	var vp := get_viewport_rect().size
	var usable := maxf(300.0, vp.x - LEFT_W - RIGHT_W - 60.0)
	var size_m := (b - a) * vp.y / usable
	var ppm := vp.y / size_m
	var d := lay.lane_dir(mid)
	var c := lay.lane_pt(mid, -lay.lw * 0.5)
	# the free map area is shifted by the panel widths: move the target accordingly
	c -= d * ((LEFT_W - RIGHT_W) * 0.5 / ppm)
	c -= Geo.right_of(d) * ((TOP_H * 0.5) / ppm)
	world.camera_rig.enter_topdown(Vector3(c.x, 0.0, c.y), size_m / CameraRig.TOPDOWN_SIZE, rad_to_deg(ClosurePlan.yaw_along(d)))


func close(accepted: bool) -> void:
	if world and is_instance_valid(world):
		world.camera_rig.exit_topdown()
		if world.day_night:
			world.day_night.override_hour = _prev_light
			world.day_night.update_now()
		for t in _trees:
			if is_instance_valid(t):
				(t as Node3D).visible = true
		_trees.clear()
		if world.tool == self:
			world.tool = _prev_tool
	Clock.set_speed(_prev_speed)
	closed.emit(accepted)


func _accept() -> void:
	var p := plan.copy()
	if p.custom:
		p.sort_for_build(lay)
	var why := site.can_edit_plan()
	if why != "":
		Events.warn("Plan nicht übernommen: " + why)
		return
	site.set_plan(p, true)
	close(true)


func _cancel() -> void:
	if dirty and _cancel_t <= 0.0:
		_cancel_t = 3.0
		cancel_btn.text = "Wirklich verwerfen?"
		return
	close(false)


# ------------------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------------------

func _build_ui() -> void:
	canvas = Control.new()
	canvas.name = "Plan"
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_plan)
	add_child(canvas)
	_build_top()
	_build_left()
	_build_right()
	hint_lbl = UI.label("", 13, UI.TEXT)
	hint_lbl.anchor_top = 1.0
	hint_lbl.anchor_bottom = 1.0
	hint_lbl.offset_left = LEFT_W + 20
	hint_lbl.offset_top = -34
	hint_lbl.offset_bottom = -12
	hint_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_lbl.add_theme_constant_override("outline_size", 5)
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_lbl)


func _build_top() -> void:
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.flat(UI.BG, Color(0, 0, 0, 0), 0, 0, Vector4(18, 8, 14, 8)))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, TOP_H)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var h := UI.hbox(16)
	top.add_child(h)
	var mark := ColorRect.new()
	mark.color = UI.ACCENT
	mark.custom_minimum_size = Vector2(6, 26)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var brand := UI.vbox(0)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(UI.caps("Absperrung planen", UI.ACCENT))
	brand.add_child(UI.label("%s · %s" % [site.job.short_title(), site.job.location()], 16, UI.TEXT, 600))
	h.add_child(brand)
	h.add_child(UI.spacer())
	var info := UI.label("Spiel pausiert · Draufsicht · %s" % ("Engstelle mit Gegenverkehr" if lay.oncoming else "Fahrstreifensperrung"), 13, UI.MUTED)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(info)
	h.add_child(UI.spacer())
	cancel_btn = UI.button("Abbrechen", "x")
	cancel_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(_cancel)
	h.add_child(cancel_btn)
	accept_btn = UI.button("Übernehmen und aufbauen" if site.crew_present() else "Plan übernehmen", "check", true)
	accept_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	accept_btn.tooltip_text = "Die Kolonne baut die Absperrung genau so auf." if site.crew_present() else "Die Kolonne baut den Plan auf, sobald der Kolonnenbus vor Ort ist."
	accept_btn.pressed.connect(_accept)
	h.add_child(accept_btn)


func _side_panel(left_side: bool, w: int) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.flat(UI.BG, UI.LINE, 1, 0, Vector4(16, 14, 14, 14)))
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.offset_top = TOP_H
	p.offset_bottom = 0
	if left_side:
		p.offset_left = 0
		p.offset_right = w
	else:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -w
		p.offset_right = 0
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _build_left() -> void:
	var v := _side_panel(true, LEFT_W)
	v.add_child(UI.caps("Bauteile"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var n := 1
	for k in ClosurePlan.ORDER:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(124, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s (Taste %d)" % [ClosurePlan.label(k), n]
		var col := UI.vbox(2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := SymbolIcon.new()
		ic.kind = k
		ic.custom_minimum_size = Vector2(0, 26)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ic)
		var l := UI.label(str(ClosurePlan.KINDS[k].short), 12, UI.TEXT, 500)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
		b.add_child(col)
		var kk: String = k
		b.pressed.connect(func(): set_kind(kk))
		grid.add_child(b)
		kind_btns[k] = b
		n += 1
	v.add_child(UI.sep())
	v.add_child(UI.caps("Werkzeug"))
	var mg := GridContainer.new()
	mg.columns = 3
	mg.add_theme_constant_override("h_separation", 4)
	mg.add_theme_constant_override("v_separation", 4)
	v.add_child(mg)
	for m in MODES:
		var b2 := UI.button(m[1])
		b2.toggle_mode = true
		b2.tooltip_text = m[2]
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.add_theme_font_size_override("font_size", 13)
		var mm: String = m[0]
		b2.pressed.connect(func(): set_mode(mm))
		mg.add_child(b2)
		mode_btns[mm] = b2
	spacing_box = UI.hbox(6)
	var sl := UI.label("Abstand", 13, UI.MUTED)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacing_box.add_child(sl)
	var minus := UI.button("–")
	minus.custom_minimum_size = Vector2(34, 30)
	minus.pressed.connect(func(): _step_spacing(-1))
	spacing_box.add_child(minus)
	spacing_lbl = UI.label("", 14, UI.TEXT, 600)
	spacing_lbl.custom_minimum_size = Vector2(62, 0)
	spacing_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spacing_box.add_child(spacing_lbl)
	var plus := UI.button("+")
	plus.custom_minimum_size = Vector2(34, 30)
	plus.pressed.connect(func(): _step_spacing(1))
	spacing_box.add_child(plus)
	v.add_child(spacing_box)
	var snap_row := CheckButton.new()
	snap_row.text = "An Fahrstreifen einrasten"
	snap_row.button_pressed = snap
	snap_row.focus_mode = Control.FOCUS_NONE
	snap_row.add_theme_font_size_override("font_size", 13)
	snap_row.tooltip_text = "Rastet an Fahrstreifenkanten und -mitten ein. Alt gedrückt halten: frei setzen."
	snap_row.toggled.connect(func(on): snap = on)
	v.add_child(snap_row)
	v.add_child(UI.sep())
	v.add_child(UI.caps("Bearbeiten"))
	var r1 := UI.hbox(6)
	undo_btn = UI.button("Rückgängig", "rotate-ccw")
	undo_btn.tooltip_text = "Strg+Z"
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.pressed.connect(undo)
	r1.add_child(undo_btn)
	redo_btn = UI.button("Wiederholen")
	redo_btn.tooltip_text = "Strg+Y"
	redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_btn.pressed.connect(redo)
	r1.add_child(redo_btn)
	v.add_child(r1)
	var r2 := UI.hbox(6)
	var tpl := UI.button("Standard-Vorlage", "layers")
	tpl.tooltip_text = "Die bisherige Standard-Absperrung laden (ersetzt den Plan)"
	tpl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tpl.pressed.connect(load_template)
	r2.add_child(tpl)
	var clr := UI.button("Leeren", "trash-2")
	clr.tooltip_text = "Alle Teile und Markierungen entfernen"
	clr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clr.pressed.connect(clear_all)
	r2.add_child(clr)
	v.add_child(r2)
	var view := UI.button("Ansicht zurücksetzen", "search")
	view.pressed.connect(frame_view)
	v.add_child(view)
	_refresh_tools()


func _build_right() -> void:
	var v := _side_panel(false, RIGHT_W)
	v.add_child(UI.caps("Prüfung"))
	summary_lbl = UI.label("", 13, UI.TEXT, 600)
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(summary_lbl)
	checks_box = UI.vbox(7)
	v.add_child(checks_box)
	v.add_child(UI.sep())
	v.add_child(UI.caps("Stückliste"))
	bom_box = UI.vbox(2)
	v.add_child(bom_box)
	v.add_child(UI.sep())
	v.add_child(UI.caps("Legende"))
	for spec in [[Color(UI.ACCENT, 0.35), "Arbeitsbereich (muss abgesperrt sein)"], [Color(0.35, 0.22, 0.12, 0.9), "Graben"],
			[UI.ACCENT, "Platz für Bagger und Kipper"], [TRAFFIC, "Fahrweg des Verkehrs (nach deinem Plan)"], [WHITE, "Stellplatz Kolonnenbus"],
			[RED, "Grenzen der Sperrung auf dieser Straße"]]:
		var row := UI.hbox(8)
		var sw := ColorRect.new()
		sw.color = spec[0]
		sw.custom_minimum_size = Vector2(16, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		row.add_child(UI.label(spec[1], 12, UI.MUTED))
		v.add_child(row)
	v.add_child(UI.sep())
	v.add_child(UI.caps("Steuerung"))
	for t in ["Linksklick: setzen · Rechtsklick / Esc: Kette beenden", "R / Umschalt+R: drehen · Entf: löschen",
			"Umschalt: Winkel einrasten · Alt: frei setzen", "Strg+Z / Strg+Y: rückgängig / wiederholen", "1–9: Bauteil wählen",
			"Rechte Maus ziehen: verschieben · Mausrad: zoomen · Q/E: drehen · B: Gebäude aus/ein"]:
		var l := UI.label(t, 12, UI.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)


func set_kind(k: String) -> void:
	if k != kind:
		_end_chain()
	kind = k
	rot = 0.0
	if mode in ["select", "erase"]:
		mode = "single" if k != "line" else "line"
	if k == "line" and mode == "single":
		mode = "line"
	_refresh_tools()
	canvas.queue_redraw()


func set_mode(m: String) -> void:
	_end_chain()
	if m == "single" and kind == "line":
		m = "line"
	mode = m
	if m != "select":
		_sel.clear()
		_sel_line = -1
	_refresh_tools()
	canvas.queue_redraw()


func _refresh_tools() -> void:
	for k in kind_btns:
		(kind_btns[k] as Button).button_pressed = k == kind and not (mode in ["select", "erase"])
	for m in mode_btns:
		(mode_btns[m] as Button).button_pressed = m == mode
		(mode_btns[m] as Button).disabled = m == "single" and kind == "line"
	var chain_mode := mode in ["line", "curve"]
	spacing_box.visible = chain_mode and kind != "line" and not ClosurePlan.is_linear(kind)
	spacing_lbl.text = "%s m" % _fmt(float(spacing.get(kind, 5.0)))
	if undo_btn:
		undo_btn.disabled = _undo.is_empty()
		redo_btn.disabled = _redo.is_empty()


func _step_spacing(dir: int) -> void:
	var steps := [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0]
	var cur: float = spacing.get(kind, 5.0)
	var idx := 0
	for i in steps.size():
		if absf(float(steps[i]) - cur) < 0.01:
			idx = i
	idx = clampi(idx + dir, 0, steps.size() - 1)
	spacing[kind] = steps[idx]
	_refresh_tools()
	canvas.queue_redraw()


func _refresh_side() -> void:
	for c in checks_box.get_children():
		c.queue_free()
	var open_req := 0
	var open_opt := 0
	for ch in _checks:
		var ok: bool = ch.ok
		var req: bool = ch.required
		if not ok:
			if req:
				open_req += 1
			else:
				open_opt += 1
		var row := UI.hbox(8)
		var col := UI.MUTED if ok else (UI.ERROR if req else UI.ACCENT)
		var ic := UI.tex_icon("check" if ok else "triangle-alert", 16, col)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var tv := UI.vbox(1)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := UI.label(str(ch.text) + ("" if req else " (Empfehlung)"), 13, UI.TEXT if not ok else UI.MUTED, 600 if not ok else 400)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(title)
		if not ok:
			var hl := UI.label(str(ch.hint), 12, UI.MUTED)
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tv.add_child(hl)
		row.add_child(tv)
		checks_box.add_child(row)
	if open_req == 0 and open_opt == 0:
		summary_lbl.text = "Alles erfüllt."
		summary_lbl.add_theme_color_override("font_color", UI.TEXT)
	elif open_req == 0:
		summary_lbl.text = "Pflichtpunkte erfüllt, %d Empfehlung%s offen." % [open_opt, "" if open_opt == 1 else "en"]
		summary_lbl.add_theme_color_override("font_color", UI.TEXT)
	else:
		summary_lbl.text = "%d Pflichtpunkt%s offen – Übernehmen geht trotzdem." % [open_req, "" if open_req == 1 else "e"]
		summary_lbl.add_theme_color_override("font_color", UI.ERROR)
	for c in bom_box.get_children():
		c.queue_free()
	var cnt := plan.counts()
	if cnt.is_empty():
		bom_box.add_child(UI.label("Noch nichts geplant.", 12, UI.DIM))
	for k in ClosurePlan.ORDER:
		if not cnt.has(k):
			continue
		var val := ("%s m" % _fmt(float(cnt[k]))) if k == "line" else str(int(cnt[k]))
		bom_box.add_child(UI.kv(ClosurePlan.label(k), val))


# ------------------------------------------------------------------------------------------
# Plan changes, undo
# ------------------------------------------------------------------------------------------

func _snapshot() -> ClosurePlan:
	return plan.copy()


func _push_undo(snap_plan: ClosurePlan) -> void:
	_undo.append(snap_plan)
	if _undo.size() > 120:
		_undo.pop_front()
	_redo.clear()


func _changed(user_edit := true) -> void:
	if user_edit:
		plan.custom = true
		dirty = true
	_ext = lay.extent_for(plan.items) if plan.custom else lay.default_extent()
	_checks = plan.checks(lay)
	_sel = _sel.filter(func(i): return i < plan.items.size())
	if _sel_line >= plan.lines.size():
		_sel_line = -1
	_refresh_side()
	_refresh_tools()
	canvas.queue_redraw()


func undo() -> void:
	if _undo.is_empty():
		return
	_press = {}   # a drag in progress is dropped with the undone state
	_end_chain()
	_redo.append(plan.copy())
	plan = _undo.pop_back()
	_sel.clear()
	_sel_line = -1
	dirty = true
	_changed(false)


func redo() -> void:
	if _redo.is_empty():
		return
	_press = {}
	_end_chain()
	_undo.append(plan.copy())
	plan = _redo.pop_back()
	_sel.clear()
	_sel_line = -1
	dirty = true
	_changed(false)


func load_template() -> void:
	_end_chain()
	_push_undo(_snapshot())
	plan = ClosurePlan.from_layout(lay)
	_sel.clear()
	dirty = true
	_changed(false)


func clear_all() -> void:
	_end_chain()
	if plan.is_empty():
		return
	_push_undo(_snapshot())
	plan.items.clear()
	plan.lines.clear()
	_sel.clear()
	_changed()


func _fits(n: int) -> bool:
	if plan.items.size() + n > ClosurePlan.MAX_ITEMS:
		Events.warn("Zu viele Teile (höchstens %d)" % ClosurePlan.MAX_ITEMS)
		return false
	return true


func _delete_selection() -> void:
	if _sel.is_empty() and _sel_line < 0:
		return
	_push_undo(_snapshot())
	var keep: Array = []
	for i in plan.items.size():
		if not _sel.has(i):
			keep.append(plan.items[i])
	plan.items = keep
	if _sel_line >= 0:
		plan.lines.remove_at(_sel_line)
	_sel.clear()
	_sel_line = -1
	_changed()


func _rotate_selection(sgn: float) -> void:
	if _sel.is_empty():
		return
	_push_undo(_snapshot())
	for i in _sel:
		var it: Dictionary = plan.items[i]
		var c := ClosurePlan.item_center(it)
		it.yaw = wrapf(float(it.yaw) + ROT_STEP * sgn, -PI, PI)
		if ClosurePlan.is_linear(it.kind):
			it.pos = c - ClosurePlan.axis_x(it.yaw) * ClosurePlan.ELEM_LEN * 0.5
	_changed()


# ------------------------------------------------------------------------------------------
# Placing
# ------------------------------------------------------------------------------------------

func _place_single(p: Vector2) -> void:
	var yaw := ClosurePlan.auto_yaw(kind, p, lay) + rot
	var origin := p
	if ClosurePlan.is_linear(kind):
		origin = p - ClosurePlan.axis_x(yaw) * ClosurePlan.ELEM_LEN * 0.5
	if not _fits(1):
		return
	_push_undo(_snapshot())
	plan.items.append(ClosurePlan.make_item(kind, origin, wrapf(yaw, -PI, PI)))
	_changed()


## Path of the chain segment that the next click would commit (empty if none).
func _pending_path() -> PackedVector2Array:
	if _chain.is_empty():
		return PackedVector2Array()
	if mode == "line":
		return ClosurePlan.lane_path(_chain[0], _mp, lay)
	if mode == "curve":
		if _chain.size() == 1:
			return PackedVector2Array([_chain[0], _mp])
		return ClosurePlan.curve_through(_chain[0], _mp, _chain[1])
	return PackedVector2Array()


func _chain_click(p: Vector2) -> void:
	if _chain.is_empty():
		_chain = PackedVector2Array([p])
		_chain_segments = 0
		_chain_line = -1
		return
	if mode == "curve" and _chain.size() == 1:
		if p.distance_to(_chain[0]) < 0.3:
			return
		_chain.append(p)
		return
	var path := _pending_path()
	if Geo.polyline_length(path) < 0.3:
		return
	var list: Array = []
	if kind != "line":
		list = ClosurePlan.chain(kind, path, float(spacing.get(kind, 5.0)), lay, _chain_segments > 0)
		if not _fits(list.size()):
			return
	_push_undo(_snapshot())
	if kind == "line":
		if _chain_line < 0 or _chain_line >= plan.lines.size():
			plan.lines.append(path)
			_chain_line = plan.lines.size() - 1
		else:
			var pl: PackedVector2Array = plan.lines[_chain_line]
			for k in range(1, path.size()):
				pl.append(path[k])
			plan.lines[_chain_line] = pl
	else:
		plan.items.append_array(list)
	_chain_segments += 1
	var end := path[path.size() - 1]
	_chain = PackedVector2Array([end])
	_changed()


func _end_chain() -> void:
	_chain = PackedVector2Array()
	_chain_segments = 0
	_chain_line = -1
	if canvas:
		canvas.queue_redraw()


## World tool hook: a short right click ends the chain or the selection.
func on_right_click(_screen: Vector2) -> void:
	if not _chain.is_empty():
		_end_chain()
	elif not _sel.is_empty() or _sel_line >= 0:
		_sel.clear()
		_sel_line = -1
		canvas.queue_redraw()


# ------------------------------------------------------------------------------------------
# Hit tests
# ------------------------------------------------------------------------------------------

func _item_at(p: Vector2) -> int:
	var tol := 10.0 / maxf(0.01, _ppm)
	var best := INF
	var idx := -1
	for i in plan.items.size():
		var it: Dictionary = plan.items[i]
		var d := 0.0
		if ClosurePlan.is_linear(it.kind):
			var a: Vector2 = it.pos
			var b: Vector2 = a + ClosurePlan.axis_x(float(it.yaw)) * ClosurePlan.ELEM_LEN
			d = p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		else:
			d = maxf(0.0, p.distance_to(it.pos) - (0.45 if ClosurePlan.is_sign(it.kind) else 0.2))
		if d < tol and d < best:
			best = d
			idx = i
	return idx


func _line_at(p: Vector2) -> int:
	var tol := 9.0 / maxf(0.01, _ppm)
	for l in range(plan.lines.size() - 1, -1, -1):
		var pl: PackedVector2Array = plan.lines[l]
		if pl.size() >= 2 and float(Geo.closest_on_polyline(pl, Geo.cumulative(pl), p)[0]) < tol:
			return l
	return -1


func _snap_point(p: Vector2) -> Vector2:
	var out := p
	if snap and not Input.is_key_pressed(KEY_ALT):
		var tol := SNAP_PX / maxf(0.01, _ppm)
		var best := tol
		var lc := lay.lane_coords(p)
		for lat in [-lay.lw * 0.5, 0.0, lay.lw * 0.5]:
			var d := absf(lc.y - float(lat))
			if d < best:
				best = d
				out = lay.lane_pt(lc.x, float(lat))
		var r2: Array = Geo.closest_on_polyline(lay._g2[0], lay._g2[1], p)
		var s2: float = r2[1]
		var lat2 := (p - Vector2(r2[2])).dot(Geo.right_of(lay.lane2_dir(s2)))
		for lt in [-lay.lw2 * 0.5, 0.0, lay.lw2 * 0.5]:
			var d2 := absf(lat2 - float(lt))
			if d2 < best:
				best = d2
				out = lay.lane2_pt(s2, float(lt))
	# Shift: chain direction in 15° steps relative to the lane
	if Input.is_key_pressed(KEY_SHIFT) and not _chain.is_empty() and mode in ["line", "curve"]:
		var a: Vector2 = _chain[_chain.size() - 1] if mode == "line" or _chain.size() == 1 else _chain[0]
		var v := out - a
		if v.length() > 0.05:
			var base := lay.lane_dir(lay.lane_coords(a).x).angle()
			var ang := snappedf(v.angle() - base, PI / 12.0)
			out = a + Vector2.from_angle(base + ang) * v.length()
	return out


# ------------------------------------------------------------------------------------------
# Input
# ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _cancel_t > 0.0:
		_cancel_t -= delta / maxf(0.01, Engine.time_scale) if not get_tree().paused else delta
		if _cancel_t <= 0.0:
			cancel_btn.text = "Abbrechen"
	if not _press.is_empty() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_left_up()
	# the camera moves smoothly (and the mouse may rest over a panel): keep the plan glued to the map
	_mouse = get_viewport().get_mouse_position()
	_update_hover()
	canvas.queue_redraw()


func _update_mapping() -> void:
	var cam := world.camera_rig.camera
	var t := world.camera_rig.target
	_o_map = Vector2(t.x, t.z)
	_o_scr = cam.unproject_position(Vector3(t.x, 0.06, t.z))
	_ex = cam.unproject_position(Vector3(t.x + 1.0, 0.06, t.z)) - _o_scr
	_ez = cam.unproject_position(Vector3(t.x, 0.06, t.z + 1.0)) - _o_scr
	_ppm = maxf(0.01, _ex.length())


func _scr(p: Vector2) -> Vector2:
	return _o_scr + _ex * (p.x - _o_map.x) + _ez * (p.y - _o_map.y)


func _sdir(v: Vector2) -> Vector2:
	return (_ex * v.x + _ez * v.y).normalized()


func _update_hover() -> void:
	_update_mapping()
	var gp = world.camera_rig.ground_point(_mouse)
	_over_map = gp != null and _mouse.x > LEFT_W and _mouse.x < get_viewport_rect().size.x - RIGHT_W and _mouse.y > TOP_H
	if gp != null:
		_mp_raw = Vector2(gp.x, gp.z)
		_mp = _snap_point(_mp_raw) if mode in ["single", "line", "curve"] else _mp_raw


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_mouse = (ev as InputEventMouseMotion).position
		_update_hover()
		if not _press.is_empty():
			_press_move()
		canvas.queue_redraw()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		_mouse = mb.position
		_update_hover()
		get_viewport().set_input_as_handled()
		if mb.pressed:
			if mb.double_click and not _chain.is_empty():
				_end_chain()
				return
			_left_down(mb.shift_pressed)
		else:
			_left_up()


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed:
		return
	var handled := true
	match k.keycode:
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
			if not _chain.is_empty():
				_end_chain()
			elif not _sel.is_empty() or _sel_line >= 0:
				_sel.clear()
				_sel_line = -1
		KEY_R:
			var sgn := -1.0 if k.shift_pressed else 1.0
			if mode == "select":
				_rotate_selection(sgn)
			else:
				rot = wrapf(rot + ROT_STEP * sgn, -PI, PI)
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selection()
		KEY_Z:
			if k.ctrl_pressed and k.shift_pressed:
				redo()
			elif k.ctrl_pressed:
				undo()
		KEY_Y:
			if k.ctrl_pressed:
				redo()
		KEY_SPACE, KEY_F5, KEY_F:
			pass   # stay paused while planning; saving would store a half-made plan; no camera follow
		_:
			var n := k.keycode - KEY_1
			if n >= 0 and n < ClosurePlan.ORDER.size() and not k.ctrl_pressed:
				set_kind(ClosurePlan.ORDER[n])
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()
		canvas.queue_redraw()


func _left_down(shift: bool) -> void:
	if not _over_map:
		return
	match mode:
		"single":
			if kind == "line":
				return
			_place_single(_mp)
		"line", "curve":
			_chain_click(_mp)
		"select":
			var i := _item_at(_mp_raw)
			if i >= 0:
				_sel_line = -1
				if shift:
					if _sel.has(i):
						_sel.erase(i)
					else:
						_sel.append(i)
				elif not _sel.has(i):
					_sel = [i]
				var orig: Array = []
				for j in _sel:
					orig.append(plan.items[j].pos)
				_press = {"type": "move", "start": _mp_raw, "orig": orig, "snap": _snapshot(), "moved": false}
				return
			var l := _line_at(_mp_raw)
			if l >= 0:
				_sel.clear()
				_sel_line = l
				_press = {"type": "move_line", "start": _mp_raw, "orig": PackedVector2Array(plan.lines[l]), "snap": _snapshot(), "moved": false}
				return
			if not shift:
				_sel.clear()
				_sel_line = -1
			_press = {"type": "box", "a": _mouse, "b": _mouse}
		"erase":
			_press = {"type": "erase", "snap": _snapshot(), "removed": false}
			_erase_at(_mp_raw)


func _press_move() -> void:
	match str(_press.get("type", "")):
		"move":
			var dlt: Vector2 = _mp_raw - Vector2(_press.start)
			if dlt.length() * _ppm > 3.0:
				_press.moved = true
			if _press.moved:
				var orig: Array = _press.orig
				for k in _sel.size():
					plan.items[_sel[k]].pos = Vector2(orig[k]) + dlt
		"move_line":
			var dl: Vector2 = _mp_raw - Vector2(_press.start)
			if dl.length() * _ppm > 3.0:
				_press.moved = true
			if _press.moved and _sel_line >= 0:
				var o: PackedVector2Array = _press.orig
				var pl := PackedVector2Array()
				for q in o:
					pl.append(q + dl)
				plan.lines[_sel_line] = pl
		"box":
			_press.b = _mouse
		"erase":
			_erase_at(_mp_raw)


func _left_up() -> void:
	if _press.is_empty():
		return
	var pr := _press
	_press = {}
	match str(pr.get("type", "")):
		"move", "move_line":
			if pr.moved:
				_push_undo(pr.snap)
				_changed()
		"box":
			var r := Rect2(Vector2(pr.a), Vector2.ZERO).expand(Vector2(pr.b))
			if r.size.length() > 4.0:
				for i in plan.items.size():
					if r.has_point(_scr(ClosurePlan.item_center(plan.items[i]))) and not _sel.has(i):
						_sel.append(i)
		"erase":
			if pr.removed:
				_push_undo(pr.snap)
				_changed()
	canvas.queue_redraw()


func _erase_at(p: Vector2) -> void:
	var i := _item_at(p)
	if i >= 0:
		plan.items.remove_at(i)
		_press["removed"] = true
		_sel.clear()
		canvas.queue_redraw()
		return
	var l := _line_at(p)
	if l >= 0:
		plan.lines.remove_at(l)
		_press["removed"] = true
		_sel_line = -1
		canvas.queue_redraw()


# ------------------------------------------------------------------------------------------
# Drawing
# ------------------------------------------------------------------------------------------

func _draw_plan() -> void:
	if world == null:
		return
	_update_mapping()
	var cv := canvas
	var font := UI.font(600)
	var ext: Dictionary = _ext if not _ext.is_empty() else lay.current_extent()
	# work area, trench, machine slots, van spot
	var wa := _lane_rect(lay.s_t0 - 0.5, lay.s_c1, -lay.lw * 0.5 + 0.15, lay.lw * 0.5)
	cv.draw_colored_polygon(wa, Color(UI.ACCENT, 0.13))
	_dashed_poly(cv, wa, Color(UI.ACCENT, 0.75), 1.5, true)
	var tr := _lane_rect(lay.s_t0, lay.s_t1, -lay.W * 0.5, lay.W * 0.5)
	cv.draw_colored_polygon(tr, Color(0.33, 0.21, 0.11, 0.85))
	cv.draw_polyline(_closed(tr), Color(0.75, 0.55, 0.35), 1.5, true)
	var slot := _lane_rect(lay.s_t1 + 2.3, lay.s_c1 - 0.5, -1.1, 1.1)
	cv.draw_polyline(_closed(slot), Color(UI.ACCENT, 0.95), 2.0, true)
	var van_s: float = ext.van
	var van := _lane_rect(van_s - 3.0, van_s + 3.0, SiteLayout.CURB - 1.1, SiteLayout.CURB + 1.1)
	cv.draw_polyline(_closed(van), Color(WHITE, 0.75), 1.5, true)
	_tag(cv, font, _scr(lay.lane_pt((lay.s_t0 + lay.s_t1) * 0.5, lay.W * 0.5 + 0.2)), "Graben %s m" % _fmt(lay.L), Color(0.95, 0.8, 0.6))
	_tag(cv, font, _scr(lay.lane_pt((lay.s_t1 + 2.3 + lay.s_c1) * 0.5, 1.2)), "Bagger · Kipper", UI.ACCENT)
	_tag(cv, font, _scr(lay.lane_pt(van_s, SiteLayout.CURB + 1.2)), "Kolonnenbus", WHITE)
	# traffic paths (dashed, arrows in travel direction)
	var k_path := PackedVector2Array()
	k_path.append_array(lay.lane_poly(maxf(0.0, float(ext.det0) - 60.0), float(ext.det0), func(_s): return 0.0, 2.0))
	k_path.append_array(lay.detour_pts_for(ext))
	k_path.append_array(lay.lane_poly(float(ext.det1), minf(lay.len_k, float(ext.det1) + 45.0), func(_s): return 0.0, 2.0))
	_traffic_line(cv, k_path)
	var k2a := maxf(0.0, float(ext.s2_a) - 45.0)
	var k2b := minf(lay.len_k2, float(ext.s2_b) + 45.0)
	_traffic_line(cv, Geo.sub_polyline(lay._g2[0], lay._g2[1], k2a, k2b))
	_tag(cv, font, _scr(lay.lane_pt(float(ext.det0), -0.3)), "Verschwenkung", TRAFFIC)
	# how far the closure may reach on this street (crew van, waiting spots, junctions)
	var lim := lay.extent_limits()
	for k in 2:
		var ls: float = lim.x if k == 0 else lim.y
		cv.draw_dashed_line(_scr(lay.lane_pt(ls, -lay.lw * 0.5)), _scr(lay.lane_pt(ls, lay.lw * 0.5)), Color(RED, 0.85), 2.0, 5.0)
		_tag(cv, font, _scr(lay.lane_pt(ls, lay.lw * 0.5 + 0.6)), "Sperrung frühestens ab hier" if k == 0 else "Sperrung höchstens bis hier", Color(1.0, 0.55, 0.5))
	# yellow markings
	for l in plan.lines.size():
		var pl: PackedVector2Array = plan.lines[l]
		if l == _sel_line:
			cv.draw_polyline(_scr_poly(pl), Color(UI.ACCENT, 0.9), maxf(0.15 * _ppm, 2.5) + 6.0, true)
		cv.draw_polyline(_scr_poly(pl), YELLOW, maxf(0.15 * _ppm, 2.5), true)
	# items
	var hover := -1
	if mode in ["select", "erase"] and _over_map and _press.is_empty():
		hover = _item_at(_mp_raw)
	var bad := {}
	for ch in _checks:
		for bi in ch.get("bad", []):
			bad[bi] = true
	for i in plan.items.size():
		var it: Dictionary = plan.items[i]
		if bad.has(i):
			_halo(cv, it, RED)
		if _sel.has(i) or i == hover:
			_halo(cv, it, UI.ACCENT if _sel.has(i) else (UI.ERROR if mode == "erase" else WHITE))
		_draw_item(cv, it, 1.0)
	# previews
	if _over_map and _press.is_empty():
		var path := _pending_path()
		if mode == "single" and kind != "line":
			var yaw := ClosurePlan.auto_yaw(kind, _mp, lay) + rot
			var origin := _mp - (ClosurePlan.axis_x(yaw) * ClosurePlan.ELEM_LEN * 0.5 if ClosurePlan.is_linear(kind) else Vector2.ZERO)
			_draw_item(cv, ClosurePlan.make_item(kind, origin, yaw), 0.55)
			_tag(cv, font, _mouse + Vector2(16, 18), _where(_mp), WHITE)
		elif mode in ["line", "curve"]:
			if path.size() >= 2:
				if mode == "curve" and _chain.size() == 2:
					cv.draw_dashed_line(_scr(_chain[0]), _scr(_chain[1]), Color(WHITE, 0.35), 1.0, 6.0)
				if kind == "line":
					cv.draw_polyline(_scr_poly(path), Color(YELLOW, 0.6), maxf(0.15 * _ppm, 2.5), true)
				else:
					cv.draw_polyline(_scr_poly(path), Color(WHITE, 0.45), 1.0, true)
					var prev := ClosurePlan.chain(kind, path, float(spacing.get(kind, 5.0)), lay, _chain_segments > 0)
					for it2 in prev:
						_draw_item(cv, it2, 0.55)
				var len_m := Geo.polyline_length(path)
				var txt := "%s m" % _fmt(len_m)
				if kind != "line":
					var n := ClosurePlan.chain(kind, path, float(spacing.get(kind, 5.0)), lay, _chain_segments > 0).size()
					txt += " · %d × %s" % [n, str(ClosurePlan.KINDS[kind].short)]
				if mode == "curve" and _chain.size() == 1:
					txt += " · Ende klicken"
				elif mode == "curve":
					txt += " · Biegung klicken"
				_tag(cv, font, _mouse + Vector2(16, 18), txt, WHITE)
			else:
				_draw_cursor_dot(cv)
				_tag(cv, font, _mouse + Vector2(16, 18), "Anfang klicken · " + _where(_mp), WHITE)
	if str(_press.get("type", "")) == "box":
		var r := Rect2(Vector2(_press.a), Vector2.ZERO).expand(Vector2(_press.b))
		cv.draw_rect(r, Color(UI.ACCENT, 0.12), true)
		cv.draw_rect(r, Color(UI.ACCENT, 0.8), false, 1.0)
	_scale_bar(cv, font)
	hint_lbl.text = _hint_text()


func _draw_cursor_dot(cv: Control) -> void:
	var c := _scr(_mp)
	cv.draw_circle(c, 4.0, Color(WHITE, 0.9))
	cv.draw_arc(c, 8.0, 0.0, TAU, 20, Color(DARK, 0.7), 1.5, true)


func _hint_text() -> String:
	match mode:
		"single":
			return "%s setzen: Linksklick · R drehen (%d°) · Umschalt+R zurück" % [ClosurePlan.label(kind), int(round(rad_to_deg(rot)))]
		"line":
			return "%s als Gerade: Anfang und Ende klicken, weiterklicken für den nächsten Abschnitt · Rechtsklick/Esc beendet · Umschalt: Winkel" % ClosurePlan.label(kind)
		"curve":
			return "%s als Kurve: Anfang, Ende, dann Biegung klicken · Rechtsklick/Esc beendet" % ClosurePlan.label(kind)
		"select":
			return "Teile anklicken (Umschalt: mehrere) oder Rahmen aufziehen · ziehen = verschieben · R drehen · Entf löschen"
		"erase":
			return "Teile oder Markierungen anklicken oder überstreichen, um sie zu entfernen"
	return ""


## Position relative to the trench, e.g. "12 m vor dem Graben".
func _where(p: Vector2) -> String:
	return ClosurePlan.where(lay, p)


func _lane_rect(sa: float, sb: float, la: float, lb: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(2, int(ceil((sb - sa) / 1.5)))
	for i in n + 1:
		out.append(_scr(lay.lane_pt(lerpf(sa, sb, float(i) / n), la)))
	for i in range(n, -1, -1):
		out.append(_scr(lay.lane_pt(lerpf(sa, sb, float(i) / n), lb)))
	return out


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if pts.size() > 0:
		out.append(pts[0])
	return out


func _scr_poly(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_scr(p))
	return out


func _dashed_poly(cv: Control, pts: PackedVector2Array, col: Color, w: float, closed: bool) -> void:
	var p2 := _closed(pts) if closed else pts
	for i in p2.size() - 1:
		cv.draw_dashed_line(p2[i], p2[i + 1], col, w, 7.0)


func _traffic_line(cv: Control, pts_map: PackedVector2Array) -> void:
	if pts_map.size() < 2:
		return
	var pts := _scr_poly(pts_map)
	for i in pts.size() - 1:
		cv.draw_dashed_line(pts[i], pts[i + 1], Color(TRAFFIC, 0.85), 2.0, 9.0, false)
	# arrows every ~90 px
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		acc += seg
		if acc > 90.0:
			acc = 0.0
			var d := (b - a) / seg
			var n := Vector2(-d.y, d.x)
			cv.draw_colored_polygon(PackedVector2Array([b + d * 6.0, b - d * 4.0 + n * 5.0, b - d * 4.0 - n * 5.0]), Color(TRAFFIC, 0.95))


func _tag(cv: Control, font: Font, pos: Vector2, text: String, col: Color) -> void:
	var fs := 12
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(pos + Vector2(-4, -sz.y + 2), sz + Vector2(8, 4))
	cv.draw_rect(r, Color(0, 0, 0, 0.62), true)
	cv.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _scale_bar(cv: Control, font: Font) -> void:
	var nice := [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0]
	var m := 1.0
	for x in nice:
		if float(x) * _ppm >= 70.0:
			m = x
			break
	var vp := get_viewport_rect().size
	var a := Vector2(LEFT_W + 24, vp.y - 52)
	var b := a + Vector2(m * _ppm, 0)
	cv.draw_line(a, b, WHITE, 2.0)
	cv.draw_line(a + Vector2(0, -5), a + Vector2(0, 5), WHITE, 2.0)
	cv.draw_line(b + Vector2(0, -5), b + Vector2(0, 5), WHITE, 2.0)
	_tag(cv, font, a + Vector2(0, -10), "%d m" % int(m), WHITE)


func _halo(cv: Control, it: Dictionary, col: Color) -> void:
	if ClosurePlan.is_linear(it.kind):
		var a: Vector2 = it.pos
		var b: Vector2 = a + ClosurePlan.axis_x(float(it.yaw)) * ClosurePlan.ELEM_LEN
		cv.draw_line(_scr(a), _scr(b), Color(col, 0.55), maxf(0.18 * _ppm, 5.0) + 8.0)
	else:
		var r := maxf(0.45 * _ppm, 9.0) + 5.0
		cv.draw_arc(_scr(it.pos), r, 0.0, TAU, 28, col, 2.0, true)


func _draw_item(cv: Control, it: Dictionary, a: float) -> void:
	var yaw: float = it.yaw
	var c := _scr(ClosurePlan.item_center(it))
	draw_symbol(cv, str(it.kind), c, _sdir(ClosurePlan.axis_x(yaw)), _sdir(ClosurePlan.axis_z(yaw)), _ppm, a)


## Plan symbol of an item. c: screen centre, ux/uz: screen directions of the item's +X / +Z
## (+Z faces the traffic), ppm: pixels per metre (symbols keep a minimum size), a: alpha.
static func draw_symbol(cv: CanvasItem, kind: String, c: Vector2, ux: Vector2, uz: Vector2, ppm: float, a := 1.0) -> void:
	match kind:
		"bake":
			var half := maxf(0.3 * ppm, 7.0)
			var th := maxf(0.14 * ppm, 4.0)
			cv.draw_line(c - ux * (half + 1.0), c + ux * (half + 1.0), Color(DARK, a), th + 2.0)
			cv.draw_line(c - ux * half, c + ux * half, Color(WHITE, a), th)
			cv.draw_line(c - ux * half, c - ux * half * 0.33, Color(RED, a), th)
			cv.draw_line(c + ux * half * 0.33, c + ux * half, Color(RED, a), th)
			_facing(cv, c + uz * (th * 0.5 + 1.0), ux, uz, Color(RED, a))
			cv.draw_circle(c - uz * (th * 0.5 + 2.0), maxf(1.8, th * 0.35), Color(LAMP, a))
		"cone":
			var r := maxf(0.22 * ppm, 5.0)
			cv.draw_circle(c, r + 1.0, Color(DARK, a))
			cv.draw_circle(c, r, Color(CONE, a))
			cv.draw_arc(c, r * 0.55, 0.0, TAU, 16, Color(WHITE, a), maxf(1.2, r * 0.22), true)
		"schranke", "fence":
			var half2 := ClosurePlan.ELEM_LEN * 0.5 * ppm
			half2 = maxf(half2, 9.0)
			var th2 := maxf((0.16 if kind == "schranke" else 0.1) * ppm, 4.0 if kind == "schranke" else 3.0)
			var p0 := c - ux * half2
			var p1 := c + ux * half2
			cv.draw_line(p0 - ux, p1 + ux, Color(DARK, a), th2 + 2.0)
			if kind == "schranke":
				var n := 5
				for i in n:
					var q0 := p0.lerp(p1, float(i) / n)
					var q1 := p0.lerp(p1, float(i + 1) / n)
					cv.draw_line(q0, q1, Color(RED if i % 2 == 0 else WHITE, a), th2)
				_facing(cv, c + uz * (th2 * 0.5 + 1.0), ux, uz, Color(RED, a))
				for q in [p0, c, p1]:
					cv.draw_circle(q - uz * (th2 * 0.5 + 2.0), maxf(1.8, th2 * 0.3), Color(LAMP, a))
			else:
				cv.draw_line(p0, p1, Color(0.82, 0.83, 0.82, a), th2)
				var m := 6
				for i in m + 1:
					cv.draw_line(p0.lerp(p1, float(i) / m) - uz * th2 * 0.5, p0.lerp(p1, float(i) / m) + uz * th2 * 0.5, Color(0.45, 0.46, 0.45, a), 1.0)
				cv.draw_circle(p0, th2 * 0.6, Color(RED, a))
				cv.draw_circle(p1, th2 * 0.6, Color(RED, a))
		"z123", "z208", "z308", "z274":
			var r2 := maxf(0.45 * ppm, 10.0)
			# sign board seen from above, with the face side towards the traffic
			cv.draw_line(c - ux * r2 * 0.8, c + ux * r2 * 0.8, Color(DARK, a), 3.0)
			_facing(cv, c + uz * 2.0, ux, uz, Color(DARK, a))
			draw_sign_face(cv, kind, c - uz * (r2 + 4.0), r2, a)
		"line":
			cv.draw_line(c - ux * 12.0 + uz * 4.0, c + ux * 12.0 - uz * 4.0, Color(YELLOW, a), 3.0)


## Upright sign face (screen aligned) of radius r at ic.
static func draw_sign_face(cv: CanvasItem, kind: String, ic: Vector2, r2: float, a := 1.0) -> void:
	match kind:
		"z123":
			var tri := PackedVector2Array([ic + Vector2(0, -r2), ic + Vector2(r2 * 0.95, r2 * 0.7), ic + Vector2(-r2 * 0.95, r2 * 0.7)])
			cv.draw_colored_polygon(tri, Color(RED, a))
			var inner := PackedVector2Array([ic + Vector2(0, -r2 * 0.52), ic + Vector2(r2 * 0.56, r2 * 0.45), ic + Vector2(-r2 * 0.56, r2 * 0.45)])
			cv.draw_colored_polygon(inner, Color(WHITE, a))
			cv.draw_circle(ic + Vector2(0, r2 * 0.1), r2 * 0.14, Color(DARK, a))
		"z208", "z274":
			cv.draw_circle(ic, r2, Color(RED, a))
			cv.draw_circle(ic, r2 * 0.74, Color(WHITE, a))
			if kind == "z208":
				cv.draw_line(ic + Vector2(-r2 * 0.25, r2 * 0.45), ic + Vector2(-r2 * 0.25, -r2 * 0.45), Color(RED, a), 2.0)
				cv.draw_line(ic + Vector2(r2 * 0.25, -r2 * 0.45), ic + Vector2(r2 * 0.25, r2 * 0.45), Color(DARK, a), 2.0)
			else:
				cv.draw_line(ic + Vector2(-r2 * 0.35, 0), ic + Vector2(r2 * 0.35, 0), Color(DARK, a), 2.0)
		"z308":
			var rr := Rect2(ic - Vector2(r2, r2) * 0.85, Vector2(r2, r2) * 1.7)
			cv.draw_rect(rr, Color(BLUE, a), true)
			cv.draw_rect(rr, Color(WHITE, a), false, 1.5)
			cv.draw_line(ic + Vector2(-r2 * 0.25, r2 * 0.45), ic + Vector2(-r2 * 0.25, -r2 * 0.45), Color(WHITE, a), 2.0)
			cv.draw_line(ic + Vector2(r2 * 0.25, -r2 * 0.3), ic + Vector2(r2 * 0.25, r2 * 0.45), Color(RED, a), 2.0)


static func _facing(cv: CanvasItem, base: Vector2, ux: Vector2, uz: Vector2, col: Color) -> void:
	cv.draw_colored_polygon(PackedVector2Array([base + ux * 3.0, base - ux * 3.0, base + uz * 4.5]), col)


static func _fmt(x: float) -> String:
	if absf(x - round(x)) < 0.05:
		return str(int(round(x)))
	return ("%.1f" % x).replace(".", ",")


## Small control that draws one kind's plan symbol (tool buttons).
class SymbolIcon:
	extends Control
	var kind := ""

	func _draw() -> void:
		var c := size * 0.5
		if ClosurePlan.is_sign(kind):
			ClosureDesigner.draw_sign_face(self, kind, c, 11.0)
		elif kind == "line":
			draw_line(c + Vector2(-16, 5), c + Vector2(16, -5), ClosureDesigner.YELLOW, 4.0, true)
		else:
			ClosureDesigner.draw_symbol(self, kind, c, Vector2.RIGHT, Vector2.DOWN, 12.0 if ClosurePlan.is_linear(kind) else 40.0)
