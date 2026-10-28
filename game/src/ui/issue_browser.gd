class_name IssueBrowser
extends Control
## "Meldungen": all reported issues with their status and thread. The player answers agent
## questions here, checks fixes ("Behoben" / "Nicht behoben") and can jump to the marked spots.

signal closed
signal report_requested

const STATUS_COLOR := {
	"offen": Color(0.86, 0.86, 0.84), "in_arbeit": Color(1.0, 0.416, 0.075), "rueckfrage": Color(1.0, 0.75, 0.2),
	"bitte_pruefen": Color(0.45, 0.8, 1.0), "erledigt": Color(0.45, 0.45, 0.44), "abgelehnt": Color(0.45, 0.45, 0.44),
}

var _list: VBoxContainer
var _detail: VBoxContainer
var _filter := "aktiv"
var _current := ""
var _sig := ""
var _t := 0.0
var _filter_btns := {}
var _reply: TextEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.flat(UI.BG_SOLID, UI.LINE, 1, 3, Vector4(22, 18, 22, 18)))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 60
	panel.offset_bottom = -60
	add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	var head := UI.hbox(12)
	var bar := ColorRect.new()
	bar.color = UI.ACCENT
	bar.custom_minimum_size = Vector2(4, 28)
	head.add_child(bar)
	head.add_child(UI.label("Meldungen", 24, UI.TEXT, 700))
	head.add_child(UI.spacer())
	for f in [["aktiv", "Offen"], ["dich", "Für dich"], ["erledigt", "Erledigt"], ["alle", "Alle"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = f[0] == _filter
		var key: String = f[0]
		b.pressed.connect(func():
			_filter = key
			for k in _filter_btns:
				_filter_btns[k].button_pressed = k == key
			_sig = ""
			_refresh_list())
		_filter_btns[f[0]] = b
		head.add_child(b)
	var new_b := UI.button("Neu melden (F8)", "flag", true)
	new_b.pressed.connect(func(): report_requested.emit())
	head.add_child(new_b)
	var close := UI.icon_button("x", "Schließen (Esc)")
	close.pressed.connect(_close)
	head.add_child(close)
	v.add_child(head)
	var body := UI.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var ls := ScrollContainer.new()
	ls.custom_minimum_size = Vector2(420, 0)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(ls)
	_list = UI.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_list)
	var ds := ScrollContainer.new()
	ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(ds)
	_detail = UI.vbox(12)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.add_child(_detail)
	_refresh_list()
	_show_detail("")


func _process(delta: float) -> void:
	_t += delta
	if _t > 3.0:
		_t = 0.0
		_refresh_list()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE and visible:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


# ------------------------------------------------------------------------------------------
# List
# ------------------------------------------------------------------------------------------

func _matches(it: Dictionary) -> bool:
	match _filter:
		"aktiv":
			return not (it.status in ["erledigt", "abgelehnt"])
		"dich":
			return it.status in IssueStore.NEEDS_USER
		"erledigt":
			return it.status in ["erledigt", "abgelehnt"]
	return true


func _refresh_list() -> void:
	var items := IssueStore.list_all()
	var sig := ""
	for it in items:
		sig += "%d%s%d%s|" % [it.id, it.status, it.entries, it.claimed_by]
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		c.queue_free()
	var shown := 0
	for it in items:
		if not _matches(it):
			continue
		shown += 1
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.toggle_mode = true
		b.button_pressed = it.folder == _current
		b.text = "#%d  %s\n%s · %s · %s · %s%s" % [it.id, it.title, IssueStore.TYPE_TEXT.get(it.type, it.type),
			IssueStore.AREAS.get(it.area, it.area), IssueStore.PRIOS.get(it.priority, it.priority),
			IssueStore.STATUS_TEXT.get(it.status, it.status), (" · Agent: " + it.claimed_by) if it.claimed_by != "" else ""]
		b.clip_text = true
		b.add_theme_color_override("font_color", STATUS_COLOR.get(it.status, UI.TEXT) if it.status in IssueStore.NEEDS_USER else UI.TEXT)
		var folder: String = it.folder
		b.pressed.connect(func(): _show_detail(folder))
		_list.add_child(b)
	if shown == 0:
		_list.add_child(UI.label("Keine Meldungen in dieser Ansicht.\nF8 meldet etwas Neues – im Spiel, im Menü und im Ladebildschirm.", 13, UI.DIM))
	if _current != "":
		_show_detail(_current, true)


# ------------------------------------------------------------------------------------------
# Detail
# ------------------------------------------------------------------------------------------

func _show_detail(folder: String, keep_reply := false) -> void:
	var draft := _reply.text if (keep_reply and _reply and is_instance_valid(_reply)) else ""
	_current = folder
	for c in _detail.get_children():
		c.queue_free()
	if folder == "":
		_detail.add_child(UI.label("Meldung links auswählen.", 14, UI.DIM))
		return
	var it := IssueStore.load_issue(folder)
	var st: String = it.get("status", "offen")
	_detail.add_child(UI.label("#%d  %s" % [it.get("id", 0), it.get("title", "")], 22, UI.TEXT, 700))
	var meta := UI.hbox(10)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UI.flat(STATUS_COLOR.get(st, UI.TEXT), Color(0, 0, 0, 0), 0, 2, Vector4(8, 2, 8, 2)))
	chip.add_child(UI.label(IssueStore.STATUS_TEXT.get(st, st), 12, Color(0.05, 0.05, 0.05), 600))
	meta.add_child(chip)
	meta.add_child(UI.label("%s · %s · %s · gemeldet %s · Build %s" % [IssueStore.TYPE_TEXT.get(it.get("type", ""), ""),
		IssueStore.AREAS.get(it.get("area", ""), ""), IssueStore.PRIOS.get(it.get("priority", ""), ""),
		String(it.get("created", "")).replace("T", " ").left(16), it.get("build", {}).get("version", "?")], 13, UI.MUTED))
	_detail.add_child(meta)
	var claim := IssueStore.active_claim(folder)
	if claim != "":
		_detail.add_child(UI.label("In Arbeit bei: " + claim, 13, UI.ACCENT))
	var txt := UI.label(String(it.get("text", "")), 15, UI.TEXT)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(txt)
	# screenshots
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	for f in it.get("files", []):
		if String(f).ends_with(".png") and not String(f).ends_with("_markiert.png"):
			var marked := String(f).replace(".png", "_markiert.png")
			var path := folder.path_join(marked if (marked in it.get("files", [])) else f)
			row.add_child(_thumb(path))
	for e in it.thread:
		for f in e.get("files", []):
			if String(f).ends_with(".png"):
				row.add_child(_thumb(folder.path_join(f)))
	if row.get_child_count() > 0:
		_detail.add_child(row)
	# pins
	var pins: Array = it.get("pins", [])
	var same_map: bool = Game.world != null and it.get("map", {}).get("id", "") == Game.map_meta.get("id", "-")
	if not pins.is_empty() or not it.get("camera", {}).is_empty():
		var ph := UI.hbox(8)
		for i in pins.size():
			var p: Dictionary = pins[i]
			var b := UI.button("%d %s" % [i + 1, p.get("label", "")], "map-pin")
			b.disabled = not same_map
			b.tooltip_text = "Kamera zur Stelle" if same_map else "Nur mit derselben Karte im Spiel"
			var pos := Vector3(p.x, p.y, p.z)
			b.pressed.connect(func():
				Events.request_focus.emit(pos, 80.0)
				_close())
			ph.add_child(b)
		var cam: Dictionary = it.get("camera", {})
		if not cam.is_empty():
			var cb := UI.button("Ansicht der Meldung", "navigation")
			cb.disabled = not same_map
			cb.pressed.connect(func():
				var t: Array = cam.target
				Game.world.camera_rig.set_view(Vector3(t[0], t[1], t[2]), cam.distance, cam.yaw_deg, cam.pitch_deg)
				_close())
			ph.add_child(cb)
		_detail.add_child(ph)
	_detail.add_child(UI.sep())
	# thread
	_detail.add_child(UI.caps("Verlauf"))
	for e in it.thread:
		_detail.add_child(_entry(e))
	# actions
	_detail.add_child(UI.sep())
	if st == "bitte_pruefen":
		var hint := UI.label("Ein Agent hat das behoben. Bitte im Spiel prüfen und hier bestätigen.", 14, STATUS_COLOR.bitte_pruefen)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(hint)
	elif st == "rueckfrage":
		_detail.add_child(UI.label("Der Agent hat eine Frage – bitte unten antworten.", 14, STATUS_COLOR.rueckfrage))
	_reply = TextEdit.new()
	_reply.placeholder_text = "Antwort oder Ergänzung …"
	_reply.custom_minimum_size = Vector2(0, 96)
	_reply.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_reply.text = draft
	_detail.add_child(_reply)
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 8)
	var send := UI.button("Antworten", "arrow-right", st == "rueckfrage")
	send.pressed.connect(func(): _answer(folder, st, claim))
	btns.add_child(send)
	var shot := UI.button("Aktuelles Bild anhängen", "square-dashed-mouse-pointer")
	shot.pressed.connect(func(): _attach_shot(folder))
	btns.add_child(shot)
	if st == "bitte_pruefen":
		var ok := UI.button("Behoben", "check", true)
		ok.pressed.connect(func():
			IssueStore.append(folder, {"kind": "verify", "status": "erledigt", "text": _reply.text.strip_edges() if _reply.text.strip_edges() != "" else "Behoben bestätigt"})
			_sig = ""
			_refresh_list())
		btns.add_child(ok)
		var no := UI.button("Nicht behoben", "x")
		no.pressed.connect(func():
			if _reply.text.strip_edges() == "":
				_reply.placeholder_text = "Bitte kurz beschreiben, was noch nicht stimmt (gern mit Bild)."
				_reply.grab_focus()
				return
			IssueStore.append(folder, {"kind": "verify", "status": "offen", "text": _reply.text.strip_edges()})
			_sig = ""
			_refresh_list())
		btns.add_child(no)
	elif st in ["erledigt", "abgelehnt"]:
		var re := UI.button("Wieder öffnen", "rotate-ccw")
		re.pressed.connect(func():
			IssueStore.append(folder, {"kind": "status", "status": "offen", "text": _reply.text.strip_edges() if _reply.text.strip_edges() != "" else "Wieder geöffnet"})
			_sig = ""
			_refresh_list())
		btns.add_child(re)
	else:
		var done := UI.button("Als erledigt schließen", "check")
		done.pressed.connect(func():
			IssueStore.append(folder, {"kind": "status", "status": "erledigt", "text": _reply.text.strip_edges() if _reply.text.strip_edges() != "" else "Vom Spieler geschlossen"})
			_sig = ""
			_refresh_list())
		btns.add_child(done)
	_detail.add_child(btns)
	var path_l := UI.label(ProjectSettings.globalize_path(folder), 11, UI.DIM)
	path_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_detail.add_child(path_l)


func _entry(e: Dictionary) -> Control:
	var p := PanelContainer.new()
	var kind: String = e.get("kind", "comment")
	var by: String = e.get("by", "")
	var agent := by.begins_with("agent")
	var border := UI.LINE
	if kind == "question":
		border = STATUS_COLOR.rueckfrage
	elif kind == "fix":
		border = STATUS_COLOR.bitte_pruefen
	p.add_theme_stylebox_override("panel", UI.flat(UI.BG2 if agent else UI.BG3, border, 1, 3, Vector4(12, 8, 12, 8)))
	var v := UI.vbox(4)
	p.add_child(v)
	var kinds := {"comment": "Kommentar", "question": "Rückfrage", "answer": "Antwort", "status": "Status", "fix": "Behoben in Build",
		"verify": "Prüfung", "plan": "Plan"}
	var head := "%s · %s · %s" % [by.replace("agent:", "Agent "), kinds.get(kind, kind), String(e.get("t", "")).replace("T", " ").left(16)]
	if e.has("status"):
		head += " → " + IssueStore.STATUS_TEXT.get(e.status, e.status)
	v.add_child(UI.label(head, 12, UI.ACCENT if agent else UI.MUTED, 600))
	if String(e.get("text", "")) != "":
		var t := UI.label(String(e.text), 14, UI.TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
	if e.has("build"):
		var bl := UI.label("Test-Build: " + String(e.build), 12, UI.MUTED)
		bl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		v.add_child(bl)
	return p


func _thumb(path: String) -> Control:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(240, 135)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if img:
		tr.texture = ImageTexture.create_from_image(img)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.tooltip_text = "Klicken zum Vergrößern"
	tr.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and tr.texture:
			_zoom(tr.texture))
	return tr


func _zoom(tex: Texture2D) -> void:
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(bg)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 40
	tr.offset_top = 40
	tr.offset_right = -40
	tr.offset_bottom = -40
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	o.add_child(tr)
	o.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			o.queue_free())
	add_child(o)


func _answer(folder: String, st: String, claim: String) -> void:
	var t := _reply.text.strip_edges()
	if t == "":
		return
	var e := {"kind": "answer" if st == "rueckfrage" else "comment", "text": t}
	if st == "rueckfrage":
		e["status"] = "in_arbeit" if claim != "" else "offen"
	IssueStore.append(folder, e)
	_reply.text = ""
	_sig = ""
	_refresh_list()


func _attach_shot(folder: String) -> void:
	visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	visible = true
	var n := 1
	while FileAccess.file_exists(folder.path_join("nachtrag_%d.png" % n)):
		n += 1
	var name := "nachtrag_%d.png" % n
	img.save_png(folder.path_join(name))
	IssueStore.append(folder, {"kind": "comment", "text": _reply.text.strip_edges() if _reply.text.strip_edges() != "" else "Bild angehängt", "files": [name]})
	_reply.text = ""
	_sig = ""
	_refresh_list()
