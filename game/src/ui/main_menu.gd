class_name MainMenu
extends Control

signal new_game
signal continue_game
signal quit
signal open_issues


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG_SOLID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var deco := MenuDeco.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deco)
	var col := UI.vbox(0)
	col.position = Vector2(120, 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 120
	col.offset_right = 620
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	var mark := UI.hbox(12)
	var bar := ColorRect.new()
	bar.color = UI.ACCENT
	bar.custom_minimum_size = Vector2(6, 64)
	mark.add_child(bar)
	var tbox := UI.vbox(0)
	tbox.add_child(UI.label("BAUSTELLEN", 46, UI.TEXT, 700))
	tbox.add_child(UI.label("MANAGER", 46, UI.ACCENT, 700))
	mark.add_child(tbox)
	col.add_child(mark)
	var sub := UI.label("Tiefbau auf echten Stadtkarten", 17, UI.MUTED)
	col.add_child(_pad(sub, 14))
	col.add_child(_pad(Control.new(), 30))
	var b1 := UI.button("Neue Firma gründen", "hard-hat", true)
	b1.custom_minimum_size = Vector2(320, 48)
	b1.pressed.connect(func(): new_game.emit())
	col.add_child(b1)
	col.add_child(_pad(Control.new(), 10))
	var b2 := UI.button("Spiel fortsetzen", "folder-open")
	b2.custom_minimum_size = Vector2(320, 46)
	b2.disabled = not Game.has_save()
	b2.pressed.connect(func(): continue_game.emit())
	col.add_child(b2)
	col.add_child(_pad(Control.new(), 10))
	var bi := UI.button("Meldungen", "flag")
	bi.custom_minimum_size = Vector2(320, 46)
	bi.tooltip_text = "Gemeldete Fehler und Wünsche ansehen, Rückfragen beantworten (F8 meldet etwas Neues)"
	bi.pressed.connect(func(): open_issues.emit())
	col.add_child(bi)
	col.add_child(_pad(Control.new(), 10))
	var b3 := UI.button("Beenden", "log-out")
	b3.custom_minimum_size = Vector2(320, 46)
	b3.pressed.connect(func(): quit.emit())
	col.add_child(b3)
	var foot := UI.label("%s · Kartendaten © OpenStreetMap-Mitwirkende" % Game.version_text(), 12, UI.DIM)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(120, -40)
	foot.offset_top = -40
	foot.offset_left = 120
	add_child(foot)


func _pad(c: Control, h: float) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", int(h))
	m.add_child(c)
	return m


class MenuDeco extends Control:
	## Abstract road-marking graphic on the right side.
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var x0 := w * 0.55
		draw_rect(Rect2(x0, 0, w - x0, h), Color(0.07, 0.07, 0.07))
		for i in 14:
			var y := 60.0 + i * 70.0
			draw_rect(Rect2(x0 + 140 + (i % 2) * 40, y, 160, 6), Color(1, 1, 1, 0.08))
		# yellow/orange construction lane shift
		var pts := PackedVector2Array([Vector2(x0 + 420, h), Vector2(x0 + 420, h * 0.62), Vector2(x0 + 300, h * 0.42), Vector2(x0 + 300, 0)])
		draw_polyline(pts, UI.ACCENT, 8.0, true)
		for i in 9:
			var by := h * 0.40 + i * 26.0
			draw_rect(Rect2(x0 + 360 + i * 6, by, 18, 18), Color(1, 1, 1, 0.12 + 0.05 * (i % 2)))
