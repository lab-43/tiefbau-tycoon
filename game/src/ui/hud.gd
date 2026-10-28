class_name HUD
extends Control
## In-game interface: top bar (company, date/time, speed, money), left rail with panels
## (jobs, fleet & shop, finance, help), context panel for the selection (vehicle or site),
## notifications and the game menu. Minimal black/white with an orange accent.

signal quit_to_menu

const LEFT_W := 370
const RIGHT_W := 390

var top: PanelContainer
var money_lbl: Label
var money_delta: Label
var date_lbl: Label
var time_lbl: Label
var speed_btns: Array = []
var rail_btns := {}
var left: PanelContainer
var left_title: Label
var left_body: VBoxContainer
var left_scroll: ScrollContainer
var left_mode := ""
var right: PanelContainer
var right_body: VBoxContainer
var right_scroll: ScrollContainer
var right_obj: Object = null
var right_sig := ""
var toasts: VBoxContainer
var hint: Label
var menu: PanelContainer
var report: PanelContainer
var _issue_badge: Label
var _issue_t := 0.0
var _binds: Array = []         # [Label|ProgressBar, Callable]
var _left_dirty := true
var _t := 0.0
var _hint_t := 45.0
var _last_money := 0.0
var markers: WorldMarkers      # screen markers + view bar (#7), below all panels
var designer: ClosureDesigner      # open closure designer (#9) – the rest of the HUD is hidden meanwhile
var _designer_hidden: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.theme()
	_build_markers()
	_build_top()
	_build_rail()
	_build_left()
	_build_right()
	_build_toasts()
	_build_hint()
	Events.notify.connect(_on_notify)
	Events.selection_changed.connect(_on_selection)
	Events.job_offers_changed.connect(func(): _left_dirty = true)
	Events.job_changed.connect(func(_j): _left_dirty = true)
	Events.site_changed.connect(func(_s): _left_dirty = true)
	Events.vehicle_added.connect(func(_v): _left_dirty = true)
	Events.money_changed.connect(_on_money)
	Events.speed_changed.connect(_on_speed)
	_on_speed(Clock.speed_index)
	_last_money = Game.money()
	open_left("jobs")
	_on_selection(null)


# ------------------------------------------------------------------------------------------
# Top bar
# ------------------------------------------------------------------------------------------

func _build_top() -> void:
	top = PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.flat(UI.BG, Color(0, 0, 0, 0), 0, 0, Vector4(18, 8, 14, 8)))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 54)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var h := UI.hbox(18)
	top.add_child(h)
	var mark := ColorRect.new()
	mark.color = UI.ACCENT
	mark.custom_minimum_size = Vector2(6, 26)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var brand := UI.vbox(0)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(UI.caps("Baustellen Manager", UI.MUTED))
	brand.add_child(UI.label(Game.company.name, 16, UI.TEXT, 600))
	h.add_child(brand)
	h.add_child(UI.spacer())
	# clock + speed
	var clock := UI.hbox(10)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock.add_child(UI.tex_icon("clock", 18, UI.MUTED))
	time_lbl = UI.label("07:00", 20, UI.TEXT, 600)
	clock.add_child(time_lbl)
	date_lbl = UI.label("", 13, UI.MUTED)
	clock.add_child(date_lbl)
	h.add_child(clock)
	var sp := UI.hbox(2)
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var specs := [["pause", "Pause (Leertaste)", 0], ["play", "Normal (1)", 1], ["chevrons-right", "Schnell ×3 (2)", 2], ["fast-forward", "Sehr schnell ×10 (3)", 3]]
	for spec in specs:
		var b := UI.icon_button(spec[0], spec[1], true)
		b.custom_minimum_size = Vector2(34, 34)
		var idx: int = spec[2]
		b.pressed.connect(func(): Clock.set_speed(idx))
		sp.add_child(b)
		speed_btns.append(b)
	h.add_child(sp)
	h.add_child(UI.spacer())
	var mon := UI.hbox(8)
	mon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mon.add_child(UI.tex_icon("wallet", 18, UI.MUTED))
	money_lbl = UI.label("", 20, UI.TEXT, 600)
	mon.add_child(money_lbl)
	money_delta = UI.label("", 13, UI.MUTED, 500)
	mon.add_child(money_delta)
	h.add_child(mon)
	var save_b := UI.icon_button("save", "Speichern (F5)")
	save_b.pressed.connect(func(): Game.save_game())
	h.add_child(save_b)
	var menu_b := UI.icon_button("settings", "Menü (Esc)")
	menu_b.pressed.connect(_toggle_menu)
	h.add_child(menu_b)


func _on_speed(idx: int) -> void:
	for i in speed_btns.size():
		(speed_btns[i] as Button).set_pressed_no_signal(i == idx)


func _on_money(_bal: float, delta: float, _reason: String) -> void:
	money_delta.text = ("+" if delta > 0 else "") + Balance.money(delta)
	money_delta.add_theme_color_override("font_color", UI.ACCENT if delta > 0 else UI.MUTED)
	money_delta.modulate.a = 1.0


# ------------------------------------------------------------------------------------------
# Left rail + panel
# ------------------------------------------------------------------------------------------

func _build_rail() -> void:
	var rail := PanelContainer.new()
	rail.add_theme_stylebox_override("panel", UI.flat(UI.BG, Color(0, 0, 0, 0), 0, 0, Vector4(8, 10, 8, 10)))
	rail.anchor_top = 0.0
	rail.anchor_bottom = 1.0
	rail.offset_top = 54
	rail.offset_bottom = 0
	rail.offset_left = 0
	rail.offset_right = 56
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rail)
	var v := UI.vbox(6)
	rail.add_child(v)
	for spec in [["jobs", "clipboard-list", "Aufträge"], ["fleet", "truck", "Fuhrpark & Kauf"], ["finance", "wallet", "Finanzen"], ["help", "info", "Hilfe & Steuerung"]]:
		var b := UI.icon_button(spec[1], spec[2], true)
		var mode: String = spec[0]
		b.pressed.connect(func(): open_left("" if left_mode == mode else mode))
		v.add_child(b)
		rail_btns[mode] = b
	var iss := UI.icon_button("flag", "Meldungen (F8 = neu melden)")
	iss.pressed.connect(func(): Events.open_issues.emit())
	v.add_child(iss)
	_issue_badge = UI.label("", 10, Color(0.05, 0.05, 0.05), 700)
	_issue_badge.add_theme_stylebox_override("normal", UI.flat(UI.ACCENT, Color(0, 0, 0, 0), 0, 7, Vector4(4, 0, 4, 0)))
	_issue_badge.position = Vector2(24, -2)
	_issue_badge.visible = false
	iss.add_child(_issue_badge)
	var dbg := UI.icon_button("wrench", "Debug-Menü (F3)")
	dbg.pressed.connect(func(): Events.toggle_debug.emit())
	v.add_child(dbg)
	v.add_child(UI.spacer(false))
	var hq_b := UI.icon_button("house", "Zur Zentrale springen")
	hq_b.pressed.connect(func():
		if Game.world:
			var lc: Vector2 = Game.world.hq_info.get("lot_center", Vector2.ZERO)
			Events.request_focus.emit(Vector3(lc.x, 0, lc.y), 150.0))
	v.add_child(hq_b)


func _build_left() -> void:
	left = PanelContainer.new()
	left.add_theme_stylebox_override("panel", UI.flat(UI.BG, UI.LINE, 1, 0, Vector4(18, 16, 14, 16)))
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_top = 54
	left.offset_bottom = 0
	left.offset_left = 56
	left.offset_right = 56 + LEFT_W
	left.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(left)
	var v := UI.vbox(12)
	left.add_child(v)
	var head := UI.hbox(8)
	left_title = UI.label("", 18, UI.TEXT, 600)
	left_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left_title)
	var close := UI.icon_button("x", "Schließen")
	close.custom_minimum_size = Vector2(30, 30)
	close.pressed.connect(func(): open_left(""))
	head.add_child(close)
	v.add_child(head)
	left_scroll = ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(left_scroll)
	left_body = UI.vbox(10)
	left_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_body)


func open_left(mode: String) -> void:
	left_mode = mode
	left.visible = mode != ""
	for k in rail_btns:
		(rail_btns[k] as Button).set_pressed_no_signal(k == mode)
	_left_dirty = true


func _rebuild_left() -> void:
	_left_dirty = false
	if left_mode == "":
		return
	var scroll_v := left_scroll.scroll_vertical
	for c in left_body.get_children():
		c.queue_free()
	match left_mode:
		"jobs":
			left_title.text = "Aufträge"
			_left_jobs()
		"fleet":
			left_title.text = "Fuhrpark"
			_left_fleet()
		"finance":
			left_title.text = "Finanzen"
			_left_finance()
		"help":
			left_title.text = "Hilfe & Steuerung"
			_left_help()
	await get_tree().process_frame
	left_scroll.scroll_vertical = scroll_v


func _card(accent := false) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.flat(UI.BG2, UI.ACCENT if accent else UI.LINE, 1, 3, Vector4(14, 12, 14, 12)))
	left_body.add_child(p)
	var v := UI.vbox(6)
	p.add_child(v)
	return v


func _left_jobs() -> void:
	var jm: JobManager = Game.world.jobs
	left_body.add_child(UI.caps("Ausschreibungen (%d)" % jm.offers.size()))
	if jm.offers.is_empty():
		left_body.add_child(UI.label("Gerade keine neuen Ausschreibungen. Alle paar Stunden kommen neue hinzu.", 13, UI.MUTED))
	for j in jm.offers:
		var job: Job = j
		var v := _card()
		var t := UI.label(job.title(), 15, UI.TEXT, 600)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		v.add_child(UI.label("%s · %s" % [job.location(), job.client], 13, UI.MUTED))
		var row := UI.hbox(10)
		var pay := UI.label(Balance.money(job.pay), 20, UI.ACCENT, 700)
		pay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pay)
		var hours_left := maxf(0.0, (job.expires_at - Clock.total_minutes()) / 60.0)
		row.add_child(UI.label("läuft ab in %d h" % int(hours_left), 12, UI.MUTED))
		v.add_child(row)
		var facts := UI.label("Graben %.1f × %.1f m, %.2f m tief · Frist %d Tage · %.1f km entfernt" % [job.length, job.width, job.depth, job.duration_days, job.distance_m / 1000.0], 12, UI.MUTED)
		facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(facts)
		var btns := UI.hbox(6)
		var acc := UI.button("Annehmen", "check", true)
		acc.pressed.connect(func():
			if jm.accept(job):
				var s := jm.site_of(job)
				if s:
					Game.select(s)
					Events.request_focus.emit(s.center3(), 120.0))
		btns.add_child(acc)
		var show := UI.button("Zeigen", "map-pin")
		show.pressed.connect(func(): Events.request_focus.emit(Vector3(job.center.x, 0, job.center.y), 160.0))
		btns.add_child(show)
		var dec := UI.icon_button("x", "Ablehnen")
		dec.pressed.connect(func(): jm.decline(job))
		btns.add_child(dec)
		v.add_child(btns)
	left_body.add_child(UI.sep())
	left_body.add_child(UI.caps("Laufende Baustellen (%d)" % jm.active.size()))
	if jm.active.is_empty():
		left_body.add_child(UI.label("Nimm einen Auftrag an, um eine Baustelle zu eröffnen.", 13, UI.MUTED))
	for j in jm.active:
		var job2: Job = j
		var s: Site = jm.site_of(job2)
		var v2 := _card(Game.selected == s)
		var head := UI.hbox(8)
		var tl := UI.label("%s · %s" % [job2.short_title(), job2.location()], 14, UI.TEXT, 600)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.clip_text = true
		head.add_child(tl)
		var open := UI.button("Öffnen")
		open.pressed.connect(func():
			Game.select(s)
			Events.request_focus.emit(s.center3(), 110.0))
		head.add_child(open)
		v2.add_child(head)
		if s:
			v2.add_child(UI.label("%d/%d · %s" % [s.phase + 1, Site.STEPS.size(), Site.STEPS[mini(s.phase, Site.STEPS.size() - 1)].title], 13, UI.ACCENT, 500))
			var st := UI.label(s.status, 12, UI.MUTED)
			st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v2.add_child(st)
		var days_left := job2.deadline_day - Clock.day
		v2.add_child(UI.label("Frist: Tag %d (%s)" % [job2.deadline_day, ("noch %d Tage" % days_left) if days_left >= 0 else "überfällig"], 12, UI.MUTED if days_left >= 0 else UI.ERROR))
	if not jm.history.is_empty():
		left_body.add_child(UI.sep())
		left_body.add_child(UI.caps("Abgeschlossen"))
		for j in jm.history.slice(0, 8):
			var job3: Job = j
			var row2 := UI.hbox(8)
			var l := UI.label("%s · %s" % [job3.short_title(), job3.location()], 13, UI.MUTED)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			row2.add_child(l)
			row2.add_child(UI.label(Balance.money(job3.result.get("total", 0.0)), 13, UI.TEXT, 500))
			left_body.add_child(row2)


func _left_fleet() -> void:
	var fleet: Fleet = Game.world.fleet
	left_body.add_child(UI.caps("Fahrzeuge (%d)" % fleet.vehicles.size()))
	for veh in fleet.vehicles:
		var v: Vehicle = veh
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   ·   %s" % [v.vname, v.status_text]
		b.icon = UI.icon(_vehicle_icon(v))
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 40)
		if Game.selected == v:
			b.add_theme_stylebox_override("normal", UI.flat(UI.BG3, UI.ACCENT, 1))
		b.pressed.connect(func():
			Game.select(v)
			Events.request_focus.emit(v.global_position, maxf(45.0, Game.world.camera_rig.distance * 0.7)))
		left_body.add_child(b)
	left_body.add_child(UI.sep())
	left_body.add_child(UI.caps("Fahrzeug kaufen"))
	for id in ["truck_tipper", "truck_flatbed", "van_crew", "excavator_a918", "tractor_lowbed"]:
		var d := Balance.vehicle(id)
		var v2 := _card()
		var row := UI.hbox(8)
		var n := UI.label(d.name, 14, UI.TEXT, 600)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(UI.label(Balance.money(d.price), 14, UI.ACCENT, 600))
		v2.add_child(row)
		var info := ""
		match id:
			"truck_tipper":
				info = "%d m³ Mulde · %d km/h · mehr Kipper = weniger Wartezeit beim Baggern" % [int(d.bulk_capacity_m3), int(d.max_kmh)]
			"truck_flatbed":
				info = "Rohre und Material · %d km/h" % int(d.max_kmh)
			"van_crew":
				info = "Kolonne (3 Arbeiter) + Absperrsatz · %d km/h" % int(d.max_kmh)
			"excavator_a918":
				info = "Mobilbagger 18 t · fährt selbst %d km/h" % int(d.max_kmh)
			"tractor_lowbed":
				info = "Transportiert Maschinen schnell zur Baustelle"
		var il := UI.label(info, 12, UI.MUTED)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v2.add_child(il)
		var buy := UI.button("Kaufen", "shopping-cart")
		buy.disabled = Game.money() < d.price
		buy.pressed.connect(func():
			var nv := fleet.buy(id)
			if nv:
				Game.select(nv)
				_left_dirty = true)
		v2.add_child(buy)


func _left_finance() -> void:
	left_body.add_child(UI.caps("Kontostand"))
	left_body.add_child(UI.label(Balance.money(Game.money()), 28, UI.TEXT, 700))
	var inc := 0.0
	var exp := 0.0
	for e in Game.ledger:
		if e.amount > 0:
			inc += e.amount
		else:
			exp += e.amount
	left_body.add_child(UI.kv("Einnahmen (letzte Buchungen)", Balance.money(inc)))
	left_body.add_child(UI.kv("Ausgaben (letzte Buchungen)", Balance.money(exp)))
	left_body.add_child(UI.kv("Abgeschlossene Aufträge", str(Game.company.jobs_done)))
	left_body.add_child(UI.kv("Ruf", "%d / 100" % int(Game.company.reputation)))
	left_body.add_child(UI.sep())
	left_body.add_child(UI.caps("Buchungen"))
	for e in Game.ledger.slice(0, 60):
		var row := UI.hbox(8)
		var when := UI.label("T%d %s" % [e.day, e.time], 11, UI.DIM)
		when.custom_minimum_size = Vector2(66, 0)
		row.add_child(when)
		var r := UI.label(e.reason, 12, UI.MUTED)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.clip_text = true
		row.add_child(r)
		row.add_child(UI.label(Balance.money(e.amount), 12, UI.ACCENT if e.amount > 0 else UI.TEXT, 500))
		left_body.add_child(row)


func _left_help() -> void:
	var steps := [
		["1  Auftrag annehmen", "Links unter Aufträge eine Ausschreibung annehmen. Auf der Karte erscheint die Baustelle."],
		["2  Erkunden", "Ein Fahrzeug auswählen und mit Rechtsklick auf die Baustelle schicken."],
		["3  Absperren", "Kolonnenbus (Arbeiter + Absperrmaterial) hinschicken, dann in der Baustelle „Absperrung aufbauen“. Der Verkehr wird über die gelbe Markierung an der Engstelle vorbeigeführt."],
		["4  Baggern", "Bagger zur Baustelle (fährt selbst oder per Tieflader) und Kipper schicken. Der Kipper pendelt automatisch und fährt den Aushub zur Zentrale."],
		["5  Rohr tauschen", "Pritschen-LKW schicken – er lädt in der Zentrale das neue Rohr. Bagger hebt Alt- und Neurohr."],
		["6  Verfüllen", "Der Kipper holt Sand, Schotter und Asphalt aus der Zentrale. Die Kolonne verdichtet lagenweise."],
		["7  Abziehen & Abbauen", "Maschinen zur Zentrale schicken, Absperrung abbauen – danach folgt die Abnahme mit Bezahlung."],
	]
	for s in steps:
		var v := _card()
		v.add_child(UI.label(s[0], 14, UI.ACCENT, 600))
		var l := UI.label(s[1], 13, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	left_body.add_child(UI.sep())
	left_body.add_child(UI.caps("Steuerung"))
	for kvp in [["WASD / Pfeile", "Kamera bewegen (Shift schneller)"], ["Rechte Maus ziehen", "Karte verschieben"], ["Mittlere Maus ziehen", "Drehen und neigen"],
			["Mausrad", "Zoomen"], ["Q / E", "Drehen"], ["Linksklick", "Fahrzeug oder Baustelle wählen"], ["Rechtsklick", "Befehl: hinfahren / zuweisen"],
			["F", "Auswahl folgen"], ["Leertaste, 1, 2, 3", "Pause und Geschwindigkeit"], ["F5", "Speichern"],
			["F8", "Problem melden"], ["F3", "Debug-Menü"]]:
		left_body.add_child(UI.kv(kvp[0], kvp[1]))

	left_body.add_child(UI.kv("H", "Markierungen ein/aus"))
	left_body.add_child(UI.kv("B", "Gebäude ein/aus"))
	left_body.add_child(UI.kv("Klick auf Markierung", "Hinfliegen / auswählen"))
	left_body.add_child(UI.kv("Rechtsklick auf Markierung", "Gewähltes Fahrzeug hinschicken"))


func _vehicle_icon(v: Vehicle) -> String:
	if v.has_ability("crew"):
		return "users"
	if v.has_ability("dig"):
		return "construction"
	if v.has_ability("lowbed"):
		return "navigation"
	return "truck"


# ------------------------------------------------------------------------------------------
# Right: selection panel
# ------------------------------------------------------------------------------------------

func _build_right() -> void:
	right = PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.flat(UI.BG, UI.LINE, 1, 0, Vector4(18, 16, 16, 16)))
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -RIGHT_W
	right.offset_right = 0
	right.offset_top = 54
	right.offset_bottom = 0
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(right)
	right_scroll = ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(right_scroll)
	right_body = UI.vbox(10)
	right_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_body)


func _on_selection(obj: Object) -> void:
	right_obj = obj
	right_sig = ""
	right.visible = obj != null
	_rebuild_right()
	_left_dirty = true


func _bind(c: Control, f: Callable) -> void:
	_binds.append([c, f])


func _signature() -> String:
	if right_obj != null and is_instance_valid(right_obj) and right_obj is Site and right_obj.retired:
		right_obj = null
	if right_obj == null or not is_instance_valid(right_obj):
		return ""
	if right_obj is Vehicle:
		var v: Vehicle = right_obj
		var sites := ""
		for s in Game.world.jobs.all_sites():
			sites += str(s.sid)
		return "V%s|%s|%s|%s|%s|%s|%s|%s" % [v.get_instance_id(), v.cargo.machine != null, v.site != null, sites, JSON.stringify(v.light_mode), v.auto_shuttle, v.state == "loading", v.carried_by != null]
	if right_obj is Site:
		var s: Site = right_obj
		var acts := ""
		for a in s.actions():
			acts += "%s%s%s" % [a.id, a.enabled, a.reason]
		var vs := ""
		for v2 in s.vehicles:
			if is_instance_valid(v2):
				vs += v2.vname + str(s.spot_of.get(v2, "")) + str(s.in_place.has(v2))
		var nd := ""
		for n in s.needs:
			nd += "%s%.1f" % [n.mat, n.delivered]
		return "S%d|%d|%s|%s|%s|%s|%s" % [s.sid, s.phase, s.running, acts, vs, nd, s.auto_continue]
	return "?"


func _rebuild_right() -> void:
	_binds.clear()
	for c in right_body.get_children():
		c.queue_free()
	if right_obj == null or not is_instance_valid(right_obj):
		right.visible = false
		return
	right.visible = true
	right_sig = _signature()
	if right_obj is Vehicle:
		_right_vehicle(right_obj)
	elif right_obj is Site:
		_right_site(right_obj)


func _header(icon_name: String, title: String, sub: String) -> void:
	var h := UI.hbox(12)
	var ic := PanelContainer.new()
	ic.add_theme_stylebox_override("panel", UI.flat(UI.ACCENT, UI.ACCENT, 0, 3, Vector4(8, 8, 8, 8)))
	var tr := UI.tex_icon(icon_name, 22, Color(0.04, 0.04, 0.04))
	ic.add_child(tr)
	h.add_child(ic)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(title, 18, UI.TEXT, 700)
	t.clip_text = true
	v.add_child(t)
	var s := UI.label(sub, 12, UI.MUTED)
	s.clip_text = true
	v.add_child(s)
	h.add_child(v)
	var close := UI.icon_button("x", "Auswahl aufheben (Esc)")
	close.custom_minimum_size = Vector2(30, 30)
	close.pressed.connect(func(): Game.select(null))
	h.add_child(close)
	right_body.add_child(h)


func _kv_bound(key: String, f: Callable) -> void:
	var row := UI.kv(key, "")
	var val: Label = row.get_node("Value")
	val.text = str(f.call())
	_bind(val, f)
	right_body.add_child(row)


func _segmented(title: String, options: Array, current: String, on_pick: Callable) -> void:
	var row := UI.hbox(6)
	var l := UI.label(title, 13, UI.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var grp := UI.hbox(0)
	for o in options:
		var b := Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(48, 28)
		b.add_theme_font_size_override("font_size", 12)
		b.set_pressed_no_signal(o[0] == current)
		var val: String = o[0]
		b.pressed.connect(func(): on_pick.call(val))
		grp.add_child(b)
	row.add_child(grp)
	right_body.add_child(row)


func _toggle_row(title: String, on: bool, on_toggle: Callable) -> void:
	var row := UI.hbox(6)
	var l := UI.label(title, 13, UI.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 28)
	b.add_theme_font_size_override("font_size", 12)
	b.set_pressed_no_signal(on)
	b.text = "AN" if on else "AUS"
	b.toggled.connect(func(v):
		b.text = "AN" if v else "AUS"
		on_toggle.call(v))
	row.add_child(b)
	right_body.add_child(row)


func _right_vehicle(v: Vehicle) -> void:
	_header(_vehicle_icon(v), v.vname, "%s · %s" % [v.def.get("name", ""), v.plate])
	var st := UI.label(v.status_text, 14, UI.ACCENT, 500)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bind(st, func():
		var t: String = v.status_text
		if v.state == "driving":
			t += " · ca. %d min" % int(ceil(v.eta_minutes()))
		return t)
	right_body.add_child(st)
	right_body.add_child(UI.sep())
	right_body.add_child(UI.caps("Werte"))
	_kv_bound("Geschwindigkeit", func(): return "%d km/h" % int(round(v.speed * 3.6)) if v.state == "driving" else "steht")
	_kv_bound("Kilometerstand", func(): return "%.1f km" % v.odometer_km)
	_kv_bound("Betriebsstunden", func(): return "%.1f h" % v.op_hours)
	_kv_bound("Tank", func(): return "%d %%" % int(v.fuel * 100.0))
	_kv_bound("Zustand", func(): return "%d %%" % int(v.condition * 100.0))
	_kv_bound("Im Betrieb seit", func(): return "Tag %d" % v.purchase_day)
	_kv_bound("Höchstgeschwindigkeit", func(): return "%d km/h" % int(v.def.get("max_kmh", 0)))
	if v.bulk_capacity() > 0.0:
		_kv_bound("Mulde", func(): return "%.1f / %.0f m³" % [v.bulk_m3(), v.bulk_capacity()])
	_kv_bound("Ladung", func(): return v.cargo_text())
	_kv_bound("Baustelle", func(): return v.site.job.short_title() if v.site else "–")
	right_body.add_child(UI.sep())
	right_body.add_child(UI.caps("Licht"))
	_segmented("Abblendlicht", [["auto", "Auto"], ["on", "An"], ["off", "Aus"]], v.light_mode.low, func(val):
		v.light_mode.low = val
		right_sig = "")
	_segmented("Rundumleuchte", [["auto", "Auto"], ["on", "An"], ["off", "Aus"]], v.light_mode.beacon, func(val):
		v.light_mode.beacon = val
		right_sig = "")
	_segmented("Blitzmuster", [["2", "Doppelblitz"], ["3", "Dreifachblitz"]], str(v.light_mode.get("flash", "2")), func(val):
		v.light_mode.flash = val
		right_sig = "")
	_toggle_row("Warnblinker", v.light_mode.hazard, func(on): v.light_mode.hazard = on)
	_toggle_row("Arbeitsscheinwerfer", v.light_mode.work, func(on): v.light_mode.work = on)
	right_body.add_child(UI.sep())
	right_body.add_child(UI.caps("Befehle"))
	var row := UI.hbox(6)
	var home := UI.button("Zur Zentrale", "house")
	home.pressed.connect(func(): v.drive_to_hq())
	row.add_child(home)
	var stop := UI.button("Anhalten", "pause")
	stop.pressed.connect(func(): v.stop_now())
	row.add_child(stop)
	var fol := UI.icon_button("navigation", "Folgen (F)")
	fol.pressed.connect(func(): Game.world.camera_rig.follow = v)
	row.add_child(fol)
	right_body.add_child(row)
	for s in Game.world.jobs.all_sites():
		var site: Site = s
		var b := UI.button("%s · %s" % [site.job.short_title(), site.job.location()], "arrow-right", v.site == null)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.pressed.connect(func(): site.send_vehicle(v))
		right_body.add_child(b)
	if v.def_id == "tractor_lowbed":
		if v.cargo.machine != null:
			var ub := UI.button("Maschine hier abladen", "package")
			ub.pressed.connect(func(): v.unload_machine())
			right_body.add_child(ub)
		else:
			for m in Game.world.fleet.vehicles:
				if m.is_machine() and m.carried_by == null and m.pos2().distance_to(v.pos2()) < 60.0:
					var lb := UI.button("%s aufladen" % m.vname, "package")
					var mm: Vehicle = m
					lb.pressed.connect(func(): v.load_machine(mm))
					right_body.add_child(lb)
	if v.bulk_capacity() > 0.0:
		_toggle_row("Pendelbetrieb automatisch (Aushub / Material)", v.auto_shuttle, func(on): v.auto_shuttle = on)
	if v.is_machine():
		var hint2 := UI.label("Tipp: Maschine wählen und mit Rechtsklick auf einen stehenden Tieflader aufladen lassen.", 12, UI.DIM)
		hint2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right_body.add_child(hint2)
	var hint := UI.label("Rechtsklick auf Straße: hinfahren · auf Baustelle: zuweisen · auf Zentrale: heimfahren", 12, UI.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_body.add_child(hint)


func _right_site(s: Site) -> void:
	var j := s.job
	_header("construction", "%s · %s" % [j.short_title(), j.location()], j.client)
	var pay_row := UI.hbox(8)
	var p := UI.label(Balance.money(j.pay), 20, UI.ACCENT, 700)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pay_row.add_child(p)
	var dl := UI.label("", 12, UI.MUTED)
	_bind(dl, func():
		var left_days := j.deadline_day - Clock.day
		return "Frist Tag %d · %s" % [j.deadline_day, ("noch %d Tage" % left_days) if left_days >= 0 else "überfällig!"])
	dl.text = str(_binds[_binds.size() - 1][1].call())
	pay_row.add_child(dl)
	right_body.add_child(pay_row)
	var desc := UI.label("%s · Graben %.1f × %.1f m, %.2f m tief · Absperrung: %s" % [j.title(), j.length, j.width, j.depth, s.closure_kind()], 12, UI.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_body.add_child(desc)
	right_body.add_child(UI.sep())
	right_body.add_child(UI.caps("Ablauf"))
	for st in s.steps_view():
		var row := UI.hbox(10)
		var icon := "check" if st.state == "done" else ("circle-dot" if st.state == "active" else "circle-dot")
		var col := UI.MUTED if st.state == "done" else (UI.ACCENT if st.state == "active" else UI.DIM)
		row.add_child(UI.tex_icon(icon, 16, col))
		var l := UI.label(st.title, 14, UI.TEXT if st.state == "active" else (UI.MUTED if st.state == "done" else UI.DIM), 600 if st.state == "active" else 400)
		row.add_child(l)
		right_body.add_child(row)
	right_body.add_child(UI.sep())
	var status := UI.label(s.status, 13, UI.TEXT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bind(status, func(): return s.status)
	right_body.add_child(status)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 6)
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.value = s.progress
	_bind(pb, func(): return s.progress)
	right_body.add_child(pb)
	for a in s.actions():
		var b := UI.button(a.label, "pencil" if a.id == "plan" else "hammer", a.enabled and not (a.id == "plan" and s.step_id() in Site.WORK_STEPS))
		b.disabled = not a.enabled
		var id: String = a.id
		b.pressed.connect(func():
			if id == "plan":
				open_closure_designer(s)
			else:
				s.do_action(id))
		right_body.add_child(b)
		if not a.enabled and a.reason != "":
			var r := UI.label("→ " + a.reason, 12, UI.MUTED)
			r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			right_body.add_child(r)
	_toggle_row("Arbeitsschritte automatisch fortsetzen", s.auto_continue, func(on): s.auto_continue = on)
	if not s.needs.is_empty():
		right_body.add_child(UI.sep())
		right_body.add_child(UI.caps("Material"))
		for n in s.needs:
			var nn: Dictionary = n
			_kv_bound(Balance.MATERIALS[nn.mat].name, func(): return "%.1f / %.1f m³" % [minf(nn.delivered, nn.m3), nn.m3])
		_kv_bound("Haufen vor Ort", func(): return ("%.1f m³ %s" % [s.pile_m3, Balance.MATERIALS[s.pile_mat].name]) if s.pile_m3 > 0.05 and s.pile_mat != "" else "–")
	right_body.add_child(UI.sep())
	right_body.add_child(UI.caps("Fahrzeuge an der Baustelle"))
	if s.vehicles.is_empty():
		var hint := UI.label("Fahrzeug wählen und Rechtsklick auf die Baustelle (oder Button im Fahrzeugfenster).", 12, UI.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right_body.add_child(hint)
	for veh in s.vehicles:
		if not is_instance_valid(veh):
			continue
		var vv: Vehicle = veh
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.icon = UI.icon(_vehicle_icon(vv))
		b2.clip_text = true
		b2.text = "%s · %s" % [vv.vname, vv.status_text]
		_bind(b2, func(): return "%s · %s" % [vv.vname, vv.status_text])
		b2.pressed.connect(func(): Game.select(vv))
		right_body.add_child(b2)
	var show := UI.button("Baustelle zeigen", "map-pin")
	show.pressed.connect(func(): Events.request_focus.emit(s.center3(), 90.0))
	right_body.add_child(show)


# ------------------------------------------------------------------------------------------
# Notifications, hints, menu, report
# ------------------------------------------------------------------------------------------

func _build_toasts() -> void:
	toasts = UI.vbox(6)
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.anchor_top = 1.0
	toasts.anchor_bottom = 1.0
	toasts.offset_left = -260
	toasts.offset_right = 260
	toasts.offset_bottom = -22
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)


func _on_notify(text: String, kind: String) -> void:
	if kind == "report":
		_show_report(int(text.split("|")[1]))
		return
	var p := PanelContainer.new()
	var col := UI.ACCENT if kind == "ok" else (UI.ERROR if kind in ["error", "warn"] else UI.MUTED)
	var sb := UI.flat(UI.BG_SOLID, Color(0, 0, 0, 0), 0, 2, Vector4(14, 9, 14, 9))
	sb.border_width_left = 3
	sb.border_color = col
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(text, 14, UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	p.add_child(l)
	p.set_meta("t", 6.5 if kind != "warn" else 8.0)
	toasts.add_child(p)
	while toasts.get_child_count() > 5:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))


func _build_hint() -> void:
	hint = UI.label("WASD bewegen · Rechte Maus ziehen: verschieben · Mittlere Maus: drehen · Mausrad: zoomen · Linksklick: wählen · Rechtsklick: Befehl", 12, UI.DIM)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 72
	hint.offset_top = -30
	hint.offset_bottom = -10
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _toggle_menu() -> void:
	if menu and is_instance_valid(menu):
		menu.queue_free()
		menu = null
		return
	menu = UI.panel(Vector4(22, 20, 22, 20), UI.BG_SOLID)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu)
	var v := UI.vbox(10)
	v.custom_minimum_size = Vector2(300, 0)
	menu.add_child(v)
	v.add_child(UI.label("Menü", 20, UI.TEXT, 700))
	var save := UI.button("Spiel speichern", "save", true)
	save.pressed.connect(func():
		Game.save_game()
		_toggle_menu())
	v.add_child(save)
	var cont := UI.button("Weiterspielen", "play")
	cont.pressed.connect(_toggle_menu)
	v.add_child(cont)
	var mm := UI.button("Hauptmenü (ohne Speichern)", "log-out")
	mm.pressed.connect(func():
		_toggle_menu()
		quit_to_menu.emit())
	v.add_child(mm)
	var q := UI.button("Beenden", "x")
	q.pressed.connect(func(): get_tree().quit())
	v.add_child(q)
	await get_tree().process_frame
	if menu:
		menu.position = (size - menu.size) * 0.5


func _show_report(job_id: int) -> void:
	var job: Job = null
	for j in Game.world.jobs.history:
		if j.id == job_id:
			job = j
	if job == null:
		return
	if report and is_instance_valid(report):
		report.queue_free()
	report = UI.panel(Vector4(26, 22, 26, 22), UI.BG_SOLID)
	report.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(report)
	var v := UI.vbox(10)
	v.custom_minimum_size = Vector2(420, 0)
	report.add_child(v)
	v.add_child(UI.caps("Abnahme bestanden", UI.ACCENT))
	v.add_child(UI.label("%s · %s" % [job.short_title(), job.location()], 20, UI.TEXT, 700))
	v.add_child(UI.label(job.title(), 13, UI.MUTED))
	v.add_child(UI.sep())
	var r: Dictionary = job.result
	v.add_child(UI.kv("Vergütung", Balance.money(r.get("pay", 0.0))))
	if r.get("bonus", 0.0) > 0.0:
		v.add_child(UI.kv("Bonus (schnell erledigt)", "+" + Balance.money(r.bonus)))
	if r.get("penalty", 0.0) > 0.0:
		v.add_child(UI.kv("Vertragsstrafe (%d Tage)" % r.late_days, Balance.money(-r.penalty)))
	v.add_child(UI.kv("Gutschrift", Balance.money(r.get("total", 0.0))))
	v.add_child(UI.kv("Kosten der Baustelle (Material, Löhne, Entsorgung)", Balance.money(-r.get("costs", 0.0))))
	var profit: float = r.get("total", 0.0) - r.get("costs", 0.0)
	var pr := UI.kv("Ergebnis", Balance.money(profit))
	(pr.get_node("Value") as Label).add_theme_color_override("font_color", UI.ACCENT if profit >= 0.0 else UI.ERROR)
	v.add_child(pr)
	if r.get("jam_min", 0.0) > 0.5:
		v.add_child(UI.kv("Stauzeit an der Engstelle", "%d min" % int(r.jam_min)))
	var ok := UI.button("Weiter", "check", true)
	ok.pressed.connect(func():
		report.queue_free()
		report = null)
	v.add_child(ok)
	await get_tree().process_frame
	if report:
		report.position = (size - report.size) * 0.5


# ------------------------------------------------------------------------------------------
# Frame
# ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var real := delta / maxf(0.01, Engine.time_scale) if not get_tree().paused else delta
	_t += real
	_issue_t -= real
	if _issue_t <= 0.0 and _issue_badge:
		# issues that wait for the player (agent question or fix to check)
		_issue_t = 5.0
		var n := 0
		for it in IssueStore.list_all():
			if it.status in IssueStore.NEEDS_USER:
				n += 1
		_issue_badge.text = str(n)
		_issue_badge.visible = n > 0
	# toasts fade
	for t in toasts.get_children():
		var left_t: float = t.get_meta("t", 6.0) - real
		t.set_meta("t", left_t)
		if left_t < 0.6:
			t.modulate.a = clampf(left_t / 0.6, 0.0, 1.0)
		if left_t <= 0.0:
			t.queue_free()
	if money_delta.modulate.a > 0.0:
		money_delta.modulate.a = maxf(0.0, money_delta.modulate.a - real * 0.25)
	_hint_t -= real
	if _hint_t < 3.0:
		hint.modulate.a = maxf(0.25, _hint_t / 3.0)
	if _t < 0.2 or designer != null:
		return
	_t = 0.0
	time_lbl.text = Clock.time_string()
	date_lbl.text = Clock.date_string()
	var m := Game.money()
	money_lbl.text = Balance.money(m)
	money_lbl.add_theme_color_override("font_color", UI.TEXT if m >= 0.0 else UI.ERROR)
	if _left_dirty:
		_rebuild_left()
	if right_obj != null:
		if not is_instance_valid(right_obj):
			Game.select(null)
			return
		if _signature() != right_sig:
			_rebuild_right()
		else:
			for b in _binds:
				var c: Control = b[0]
				if not is_instance_valid(c):
					continue
				var val = b[1].call()
				if c is ProgressBar:
					(c as ProgressBar).value = float(val)
				elif c is Label:
					(c as Label).text = str(val)
				elif c is Button:
					(c as Button).text = str(val)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE:
				if report:
					report.queue_free()
					report = null
				elif Game.selected != null:
					Game.select(null)
				else:
					_toggle_menu()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				Clock.toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_1:
				Clock.set_speed(1)
			KEY_2:
				Clock.set_speed(2)
			KEY_3:
				Clock.set_speed(3)
			KEY_F5:
				Game.save_game()
				get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------------------
# Screen markers (#7)
# ------------------------------------------------------------------------------------------

func _build_markers() -> void:
	# first child: every HUD panel is drawn above the markers and gets the mouse first
	markers = WorldMarkers.new()
	markers.name = "WorldMarkers"
	markers.hud = self
	add_child(markers)


# ------------------------------------------------------------------------------------------
# Closure designer (#9)
# ------------------------------------------------------------------------------------------

func open_closure_designer(s: Site) -> void:
	if designer != null or s == null or not is_instance_valid(s):
		return
	var why := s.can_edit_plan()
	if why != "":
		Events.warn(why)
		return
	_designer_hidden.clear()
	for c in get_children():
		if c != toasts and c is CanvasItem and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
			_designer_hidden.append(c)
	designer = ClosureDesigner.new()
	designer.name = "ClosureDesigner"
	add_child(designer)
	move_child(toasts, -1)
	designer.closed.connect(_on_designer_closed)
	designer.open(s)


func _on_designer_closed(_accepted: bool) -> void:
	for c in _designer_hidden:
		if is_instance_valid(c):
			(c as CanvasItem).visible = true
	_designer_hidden.clear()
	if designer:
		remove_child(designer)
		designer.queue_free()
		designer = null
	_on_selection(Game.selected)
