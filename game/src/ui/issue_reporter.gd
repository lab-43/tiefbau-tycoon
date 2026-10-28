class_name IssueReporter
extends Control
## F8: report a bug, wish or improvement. Takes a screenshot right away (before the dialog shows),
## lets the player mark spots in the world, add more screenshots and describe the problem, then
## writes everything an agent needs into an issue folder (see IssueStore).

signal closed

var shots: Array = []          # [{image: Image, cam: {xform, fov, size} or {}}]
var pins: Array = []           # [{pos: Vector3, label: String}]
var origin := "welt"           # welt | ladebildschirm | menue
var extra_context := {}        # e.g. loading screen state

var _panel: PanelContainer
var _dim: ColorRect
var _hint: PanelContainer
var _hint_label: Label
var _hint_btn: Button
var _mode := ""                # "" | "pin" | "shot"
var _title: LineEdit
var _text: TextEdit
var _type := "fehler"
var _prio := "normal"
var _area: OptionButton
var _save_cb: CheckBox
var _logs_cb: CheckBox
var _shot_row: HBoxContainer
var _pin_box: VBoxContainer
var _type_btns := {}
var _prio_btns := {}
var _prev_speed := -1
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_build_panel()
	_build_hint()


## Call right after adding to the tree: takes the first screenshot, then shows the dialog.
func start() -> void:
	if Game.world and Clock.running:
		_prev_speed = Clock.speed_index
		Clock.set_speed(0)
	await _add_shot()
	_refresh_shots()
	visible = true
	_title.grab_focus()


# ------------------------------------------------------------------------------------------
# Layout
# ------------------------------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.flat(UI.BG_SOLID, UI.LINE, 1, 3, Vector4(26, 22, 26, 22)))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(820, 0)
	_panel.offset_left = -410
	_panel.offset_right = 410
	_panel.offset_top = -430
	_panel.offset_bottom = 430
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := UI.hbox(10)
	var bar := ColorRect.new()
	bar.color = UI.ACCENT
	bar.custom_minimum_size = Vector2(4, 28)
	head.add_child(bar)
	var ht := UI.label("Problem oder Wunsch melden", 22, UI.TEXT, 700)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ht)
	head.add_child(UI.label("F8", 12, UI.DIM))
	v.add_child(head)
	v.add_child(UI.label("Die Meldung landet im Ordner „issues“. Ein Agent bekommt alles mit: Bilder, markierte Stellen, Spielstand, Protokolle und deine Beschreibung.", 13, UI.MUTED))
	# type and priority
	var row := UI.hbox(24)
	row.add_child(_seg("Art", IssueStore.TYPES, _type_btns, func(k): _type = k, _type))
	row.add_child(_seg("Priorität", IssueStore.PRIOS, _prio_btns, func(k): _prio = k, _prio))
	v.add_child(row)
	var arow := UI.hbox(10)
	arow.add_child(UI.caps("Bereich"))
	_area = OptionButton.new()
	for k in IssueStore.AREAS:
		_area.add_item(IssueStore.AREAS[k])
		_area.set_item_metadata(_area.item_count - 1, k)
	_area.custom_minimum_size = Vector2(220, 0)
	arow.add_child(_area)
	v.add_child(arow)
	v.add_child(UI.caps("Titel"))
	_title = LineEdit.new()
	_title.placeholder_text = "Kurz: Was ist das Problem / der Wunsch?"
	_title.max_length = 120
	v.add_child(_title)
	v.add_child(UI.caps("Beschreibung"))
	_text = TextEdit.new()
	_text.placeholder_text = "Was ist passiert? Was hast du erwartet? Wie kommt man dahin?\nBei Wünschen: Wie soll es sich anfühlen, was soll man damit tun können?"
	_text.custom_minimum_size = Vector2(0, 170)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_text)
	# screenshots
	var sh := UI.hbox(10)
	var sl := UI.caps("Bilder")
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sl)
	var add_shot := UI.button("Weiteres Bild", "square-dashed-mouse-pointer")
	add_shot.pressed.connect(func(): _enter_mode("shot"))
	sh.add_child(add_shot)
	v.add_child(sh)
	_shot_row = UI.hbox(8)
	v.add_child(_shot_row)
	# pins
	var ph := UI.hbox(10)
	var pl := UI.caps("Markierte Stellen")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pl)
	var add_pin := UI.button("Stelle markieren", "map-pin")
	add_pin.disabled = Game.world == null
	add_pin.tooltip_text = "In die Welt klicken, um die Stelle festzuhalten" if Game.world else "Nur im Spiel möglich"
	add_pin.pressed.connect(func(): _enter_mode("pin"))
	ph.add_child(add_pin)
	v.add_child(ph)
	_pin_box = UI.vbox(6)
	v.add_child(_pin_box)
	_refresh_pins()
	# attachments
	_save_cb = _check()
	_save_cb.text = "Spielstand anhängen (damit der Agent genau diese Situation laden kann)"
	_save_cb.button_pressed = Game.world != null
	_save_cb.disabled = Game.world == null
	v.add_child(_save_cb)
	_logs_cb = _check()
	_logs_cb.text = "Protokolle anhängen (Engine-Log, Meldungen im Spiel, Ladeprotokoll)"
	_logs_cb.button_pressed = true
	v.add_child(_logs_cb)
	v.add_child(UI.sep())
	var btns := UI.hbox(10)
	btns.add_child(UI.spacer())
	var cancel := UI.button("Abbrechen", "x")
	cancel.pressed.connect(_close)
	btns.add_child(cancel)
	var send := UI.button("Melden", "flag", true)
	send.pressed.connect(_submit)
	btns.add_child(send)
	v.add_child(btns)


func _check() -> CheckBox:
	var c := CheckBox.new()
	var clear := UI.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, Vector4(4, 4, 4, 4))
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		c.add_theme_stylebox_override(st, clear)
	c.focus_mode = Control.FOCUS_NONE
	return c


func _seg(caption: String, opts: Dictionary, store: Dictionary, on_pick: Callable, current: String) -> Control:
	var box := UI.vbox(6)
	box.add_child(UI.caps(caption))
	var h := UI.hbox(0)
	for k in opts:
		var b := Button.new()
		b.text = opts[k]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = k == current
		var key: String = k
		b.pressed.connect(func():
			on_pick.call(key)
			for k2 in store:
				store[k2].button_pressed = k2 == key)
		store[k] = b
		h.add_child(b)
	box.add_child(h)
	return box


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", UI.flat(UI.BG_SOLID, UI.ACCENT, 1, 3, Vector4(16, 10, 16, 10)))
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 70
	_hint.offset_left = -330
	_hint.offset_right = 330
	_hint.visible = false
	add_child(_hint)
	var h := UI.hbox(12)
	_hint.add_child(h)
	_hint_label = UI.label("", 14, UI.TEXT)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(_hint_label)
	_hint_btn = UI.button("Aufnehmen", "square-dashed-mouse-pointer", true)
	_hint_btn.pressed.connect(func():
		if _mode == "shot":
			_take_extra_shot())
	h.add_child(_hint_btn)
	var back := UI.button("Zurück", "x")
	back.pressed.connect(func(): _leave_mode())
	h.add_child(back)


# ------------------------------------------------------------------------------------------
# Modes: marking spots and taking more screenshots happen with the dialog hidden
# ------------------------------------------------------------------------------------------

func _enter_mode(m: String) -> void:
	_mode = m
	_panel.visible = false
	_dim.visible = false
	_hint.visible = true
	mouse_filter = Control.MOUSE_FILTER_PASS   # camera keeps working; left clicks set pins
	_hint_btn.visible = m == "shot"
	if m == "pin":
		_hint_label.text = "Auf die Stelle in der Welt klicken (Kamera wie gewohnt bewegen). Esc = zurück"
	else:
		_hint_label.text = "Ansicht einstellen, dann „Aufnehmen“ oder F8. Esc = zurück"


func _leave_mode() -> void:
	_mode = ""
	_panel.visible = true
	_dim.visible = true
	_hint.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_pins()
	_refresh_shots()


func _gui_input(ev: InputEvent) -> void:
	if _mode == "pin" and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if Game.world:
			var gp = Game.world.camera_rig.ground_point(ev.position)
			if gp != null:
				pins.append({"pos": gp, "label": "Stelle %d" % (pins.size() + 1)})
				_leave_mode()


func _input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _mode != "":
			_leave_mode()
		else:
			_close()
	elif ev.keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		if _mode == "shot":
			_take_extra_shot()


func _take_extra_shot() -> void:
	if _busy:
		return
	_busy = true
	await _add_shot()
	_busy = false
	_leave_mode()


## Screenshot without the dialog (also remembers the camera so pins can be drawn into it).
func _add_shot() -> void:
	var was := visible
	visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var cam := {}
	if Game.world and Game.world.camera_rig:
		var c: Camera3D = Game.world.camera_rig.camera
		cam = {"xform": c.global_transform, "fov": c.fov}
	shots.append({"image": img, "cam": cam})
	visible = was


func _refresh_shots() -> void:
	for c in _shot_row.get_children():
		c.queue_free()
	for i in shots.size():
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(shots[i].image)
		tr.custom_minimum_size = Vector2(176, 99)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var wrap := VBoxContainer.new()
		wrap.add_child(tr)
		var rm := Button.new()
		rm.text = "entfernen"
		rm.flat = true
		rm.add_theme_font_size_override("font_size", 11)
		var idx := i
		rm.pressed.connect(func():
			shots.remove_at(idx)
			_refresh_shots())
		rm.disabled = shots.size() == 1
		wrap.add_child(rm)
		_shot_row.add_child(wrap)


func _refresh_pins() -> void:
	for c in _pin_box.get_children():
		c.queue_free()
	if pins.is_empty():
		_pin_box.add_child(UI.label("Keine – optional, hilft aber sehr bei Problemen an einer bestimmten Stelle.", 12, UI.DIM))
		return
	for i in pins.size():
		var h := UI.hbox(8)
		var p: Vector3 = pins[i].pos
		h.add_child(UI.label("%d" % (i + 1), 14, UI.ACCENT, 700))
		var le := LineEdit.new()
		le.text = pins[i].label
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		le.text_changed.connect(func(t): pins[idx].label = t)
		h.add_child(le)
		h.add_child(UI.label("x %.0f  z %.0f" % [p.x, p.z], 12, UI.DIM))
		var rm := UI.icon_button("x", "Stelle entfernen")
		rm.pressed.connect(func():
			pins.remove_at(idx)
			_refresh_pins())
		h.add_child(rm)
		_pin_box.add_child(h)


# ------------------------------------------------------------------------------------------
# Submit
# ------------------------------------------------------------------------------------------

func _submit() -> void:
	if _title.text.strip_edges() == "":
		_title.placeholder_text = "Bitte einen kurzen Titel eingeben"
		_title.grab_focus()
		return
	var area: String = _area.get_item_metadata(_area.selected)
	if area == "auto":
		area = _auto_area()
	var pin_data: Array = []
	for p in pins:
		pin_data.append({"x": snappedf(p.pos.x, 0.01), "y": snappedf(p.pos.y, 0.01), "z": snappedf(p.pos.z, 0.01), "label": p.label})
	var report := {
		"title": _title.text.strip_edges(), "text": _text.text, "type": _type, "area": area, "priority": _prio,
		"origin": origin, "pins": pin_data, "camera": _camera_state(), "selection": _selection_state(),
		"game": {"company": Game.company.get("name", ""), "day": Clock.day, "time": Clock.time_string(),
			"money": Game.company.get("money", 0.0), "speed": _prev_speed},
		"context": extra_context,
	}
	var shot_data: Array = []
	for s in shots:
		shot_data.append({"image": s.image, "pins_screen": _pins_on(s)})
	var folder := IssueStore.create(report, shot_data, _save_cb.button_pressed, _logs_cb.button_pressed)
	var id: int = int(IssueStore.summary(folder).get("id", 0))
	Events.ok("Meldung #%d gespeichert – ein Agent kann sie jetzt bearbeiten" % id)
	print("Meldung #%d gespeichert: %s" % [id, ProjectSettings.globalize_path(folder)])
	_close()


func _auto_area() -> String:
	if origin == "ladebildschirm":
		return "karte"
	if Game.selected is Vehicle:
		return "fahrzeuge"
	if Game.selected is Site:
		return "baustelle"
	return "sonstiges"


func _camera_state() -> Dictionary:
	if Game.world == null or Game.world.camera_rig == null:
		return {}
	var cr = Game.world.camera_rig
	return {"target": [cr.target.x, cr.target.y, cr.target.z], "yaw_deg": rad_to_deg(cr.yaw),
		"pitch_deg": rad_to_deg(cr.pitch), "distance": cr.distance}


func _selection_state() -> Dictionary:
	var o = Game.selected
	if o == null or not is_instance_valid(o):
		return {}
	if o is Vehicle:
		return {"kind": "vehicle", "name": o.vname, "type": o.def_id, "state": o.state, "status": o.status_text,
			"pos": [o.position.x, o.position.z], "site": o.site.job.short_title() if o.site else "",
			"save": o.save_state() if o.has_method("save_state") else {}}
	if o is Site:
		return {"kind": "site", "id": o.sid, "title": o.job.short_title(), "step": o.step_id(), "sub": o.sub,
			"status": o.status, "running": o.running}
	return {"kind": str(o)}


## Screen positions of the pins in one screenshot (camera of that moment).
func _pins_on(shot: Dictionary) -> Array:
	var out: Array = []
	if shot.cam.is_empty() or pins.is_empty() or Game.world == null:
		return out
	var c: Camera3D = Game.world.camera_rig.camera
	var keep := c.global_transform
	var keep_fov := c.fov
	c.global_transform = shot.cam.xform
	c.fov = shot.cam.fov
	var img: Image = shot.image
	var vp := get_viewport().get_visible_rect().size
	var k := Vector2(img.get_width() / vp.x, img.get_height() / vp.y)
	for p in pins:
		if c.is_position_behind(p.pos):
			continue
		var sp := c.unproject_position(p.pos) * k
		if sp.x >= 0 and sp.y >= 0 and sp.x < img.get_width() and sp.y < img.get_height():
			out.append([sp.x, sp.y, p.label])
	c.global_transform = keep
	c.fov = keep_fov
	return out


func _close() -> void:
	if _prev_speed >= 0:
		Clock.set_speed(_prev_speed)
	closed.emit()
	queue_free()
