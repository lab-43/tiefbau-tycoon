class_name LoadingScreen
extends Control
## Loading screen with live progress: stages, tile map of the download, server status, a live
## log and the running time. It polls MapService.snapshot() a few times per second.

signal cancel_pressed
signal retry_pressed
signal back_pressed

var ms: MapService
var title_label: Label
var sub_label: Label
var elapsed_label: Label
var step_label: Label
var pct_label: Label
var detail_label: Label
var bar: ProgressBar
var stage_box: VBoxContainer
var conn_section: VBoxContainer
var conn_rows: VBoxContainer
var log_view: RichTextLabel
var log_path_label: Label
var tile_view: TileView
var spinner: Spinner
var tip_label: Label
var cancel_btn: Button
var btn_row: HBoxContainer
var error_box: VBoxContainer

var _log_seen := 0
var _poll_t := 0.0
var _stage_sig := ""
var _conn_sig := ""
var _hist: Array = []           # [elapsed, frac] for the time estimate
var _failed := false
var _tips := [
	"Halbseitige Sperrung: Mit Zeichen 208/308 regelst du, wer an der Engstelle Vorrang hat.",
	"Gelbe Markierungen heben die weißen auf – der Verkehr folgt deiner Verschwenkung.",
	"Rechte Maustaste gedrückt halten verschiebt die Karte, Mausrad gedrückt dreht sie.",
	"Der Mobilbagger fährt selbst zur Baustelle, er kann aber auch mit dem Tieflader kommen.",
	"Jede Verfülllage wird mit der Rüttelplatte verdichtet, bevor die nächste kommt.",
	"Nachts blinken die Warnleuchten der Absperrung, die Leitbaken laufen als Lauflicht.",
	"Die Karte wird nur beim ersten Start geladen – danach startet das Spiel in Sekunden.",
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG_SOLID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var root := UI.vbox(18)
	margin.add_child(root)

	# header
	var head := UI.hbox(16)
	root.add_child(head)
	var hl := UI.vbox(2)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	title_label = UI.label("", 28, UI.TEXT, 700)
	hl.add_child(title_label)
	sub_label = UI.label("", 14, UI.MUTED)
	hl.add_child(sub_label)
	var hr := UI.vbox(2)
	head.add_child(hr)
	hr.add_child(UI.caps("Laufzeit"))
	elapsed_label = UI.label("00:00", 22, UI.TEXT, 600)
	elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hr.add_child(elapsed_label)

	# body: map on the left, details on the right
	var body := UI.hbox(32)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := UI.vbox(10)
	left.custom_minimum_size = Vector2(340, 0)
	body.add_child(left)
	left.add_child(UI.caps("Kartenausschnitt"))
	tile_view = TileView.new()
	tile_view.custom_minimum_size = Vector2(340, 340)
	left.add_child(tile_view)
	left.add_child(_legend())

	var right := UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UI.caps("Ablauf"))
	stage_box = UI.vbox(4)
	right.add_child(stage_box)
	right.add_child(UI.sep())
	var step_row := UI.hbox(10)
	right.add_child(step_row)
	spinner = Spinner.new()
	spinner.custom_minimum_size = Vector2(20, 20)
	spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	step_row.add_child(spinner)
	step_label = UI.label("Vorbereiten …", 17, UI.TEXT, 500)
	step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_label.clip_text = true
	step_row.add_child(step_label)
	pct_label = UI.label("0 %", 17, UI.ACCENT, 700)
	step_row.add_child(pct_label)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 1.0
	right.add_child(bar)
	detail_label = UI.label("", 13, UI.MUTED)
	right.add_child(detail_label)
	error_box = UI.vbox(10)
	error_box.visible = false
	right.add_child(error_box)

	conn_section = UI.vbox(6)
	right.add_child(conn_section)
	conn_section.add_child(UI.caps("Server"))
	conn_rows = UI.vbox(4)
	conn_section.add_child(conn_rows)

	var log_head := UI.hbox(8)
	right.add_child(log_head)
	var lc := UI.caps("Protokoll")
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.size_flags_vertical = Control.SIZE_SHRINK_END
	log_head.add_child(lc)
	var copy := UI.button("Kopieren", "clipboard-list")
	copy.tooltip_text = "Das komplette Protokoll in die Zwischenablage kopieren"
	copy.pressed.connect(func():
		if ms:
			DisplayServer.clipboard_set(ms.full_log_text())
			copy.text = "Kopiert"
			get_tree().create_timer(1.5).timeout.connect(func(): copy.text = "Kopieren"))
	log_head.add_child(copy)
	var folder := UI.button("Ordner", "folder-open")
	folder.tooltip_text = "Ordner mit der Protokolldatei öffnen"
	folder.pressed.connect(func():
		if ms and ms.log_path != "":
			OS.shell_open(ms.log_path.get_base_dir()))
	log_head.add_child(folder)
	var log_panel := UI.panel(Vector4(12, 10, 12, 10), UI.BG2)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 140)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	log_view.add_theme_font_override("normal_font", mono)
	log_view.add_theme_font_size_override("normal_font_size", 12)
	log_view.add_theme_color_override("default_color", UI.MUTED)
	log_panel.add_child(log_view)
	log_path_label = UI.label("", 11, UI.DIM)
	log_path_label.clip_text = true
	right.add_child(log_path_label)

	# footer
	var foot := UI.hbox(12)
	root.add_child(foot)
	tip_label = UI.label(_tips[randi() % _tips.size()], 13, UI.DIM)
	tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(tip_label)
	btn_row = UI.hbox(10)
	foot.add_child(btn_row)
	var rep := UI.button("Problem melden (F8)", "flag")
	rep.pressed.connect(func(): Events.report_issue.emit())
	btn_row.add_child(rep)
	cancel_btn = UI.button("Abbrechen", "x")
	cancel_btn.pressed.connect(func(): cancel_pressed.emit())
	btn_row.add_child(cancel_btn)


func _legend() -> Control:
	var h := UI.hbox(14)
	for e in [[TileView.C_WAIT, "offen"], [UI.ACCENT, "lädt"], [TileView.C_DONE, "fertig"], [UI.ERROR, "Fehler"]]:
		var item := UI.hbox(6)
		var sw := ColorRect.new()
		sw.color = e[0]
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sw)
		item.add_child(UI.label(e[1], 12, UI.MUTED))
		h.add_child(item)
	return h


# ------------------------------------------------------------------------------------------
# Public API (used by main.gd)
# ------------------------------------------------------------------------------------------

func set_title(company: String, city: String) -> void:
	if title_label == null:
		await ready
	title_label.text = company
	sub_label.text = "Karte: " + city


func attach(service: MapService) -> void:
	if title_label == null:
		await ready
	ms = service
	_log_seen = 0
	log_view.clear()
	_hist.clear()
	_failed = false
	error_box.visible = false
	cancel_btn.visible = true
	spinner.state = "run"
	step_label.remove_theme_color_override("font_color")
	var m: Dictionary = service.meta if not service.meta.is_empty() else Game.map_meta
	tile_view.half = float(m.get("size_m", 6000.0)) * 0.5
	if m.has("hq"):
		tile_view.hq = Vector2(float(m.hq.get("x", 0.0)), float(m.hq.get("z", 0.0)))
	sub_label.text = "Karte: %s · %.0f × %.0f km" % [m.get("name", ""), tile_view.half * 2.0 / 1000.0, tile_view.half * 2.0 / 1000.0]


## Kept for compatibility (the MapService progress signal).
func set_progress(_step: String, _frac: float) -> void:
	pass


func show_error(msg: String, on_back: Callable, on_retry: Callable = Callable()) -> void:
	_failed = true
	_poll(true)
	spinner.state = "fail"
	step_label.text = "Laden fehlgeschlagen"
	step_label.add_theme_color_override("font_color", UI.ERROR)
	cancel_btn.visible = false
	for c in error_box.get_children():
		c.queue_free()
	var l := UI.label(msg, 14, UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_box.add_child(l)
	var row := UI.hbox(10)
	if on_retry.is_valid():
		var r := UI.button("Erneut versuchen", "rotate-ccw", true)
		r.pressed.connect(on_retry)
		row.add_child(r)
	var b := UI.button("Zurück zum Menü", "log-out")
	b.pressed.connect(on_back)
	row.add_child(b)
	error_box.add_child(row)
	error_box.visible = true


# ------------------------------------------------------------------------------------------
# Live update
# ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_t += delta
	if _poll_t >= 0.15:
		_poll_t = 0.0
		_poll(false)


func _poll(force: bool) -> void:
	if ms == null or not is_instance_valid(ms):
		return
	var snap := ms.snapshot()
	var el: float = snap.elapsed
	elapsed_label.text = _clock(el)
	if not _failed:
		step_label.text = snap.step
	bar.value = snap.frac
	pct_label.text = "%d %%" % int(snap.frac * 100.0)
	_update_stages(snap.stages, el)
	var dl: Dictionary = snap.dl
	conn_section.visible = not dl.is_empty()
	if not dl.is_empty() and dl.get("mode", "") == "geofabrik":
		# one file for the whole area: the grid fills up with the download
		tile_view.tiles = []
		tile_view.fill = float(dl.fill)
		tile_view.all_done = false
		_update_conns(dl.eps)
		var parts := []
		if String(dl.region) != "":
			parts.append("Geofabrik-Auszug „%s“" % dl.region)
		if int(dl.total) > 0:
			parts.append("%s von %s" % [MapDownloader._fmt_bytes(int(dl.got)), MapDownloader._fmt_bytes(int(dl.total))])
		if float(dl.bps) > 1000.0:
			parts.append("%s/s" % MapDownloader._fmt_bytes(int(dl.bps)))
		detail_label.text = " · ".join(parts) + _eta(el, snap.frac)
	elif not dl.is_empty():
		tile_view.tiles = dl.tiles
		tile_view.fill = -1.0
		tile_view.all_done = false
		_update_conns(dl.eps)
		detail_label.text = "%d von %d Teilen fertig (Kacheln, Flächen, Buslinien) · %d gleichzeitig%s%s" % [
			dl.jobs_done, dl.jobs_total, dl.jobs_active,
			("  · %d Fehlversuche" % _sum_fail(dl.eps)) if _sum_fail(dl.eps) > 0 else "", _eta(el, snap.frac)]
	elif not _failed:
		tile_view.fill = -1.0
		tile_view.all_done = tile_view.tiles.is_empty() or _stage_done(snap.stages, "download")
		detail_label.text = _eta(el, snap.frac).trim_prefix("  · ")
	tile_view.queue_redraw()
	if force or ms.log_serial != _log_seen:
		_append_log()
	if log_path_label.text == "" and ms.log_path != "":
		log_path_label.text = "Protokolldatei: " + ms.log_path


func _append_log() -> void:
	var new_lines := ms.log_serial - _log_seen
	var lines: Array = ms.log_lines
	var from := maxi(0, lines.size() - new_lines)
	for i in range(from, lines.size()):
		var l: Array = lines[i]
		var col := UI.MUTED
		match int(l[1]):
			1:
				col = Color(0.80, 0.86, 0.78)
			2:
				col = UI.ACCENT
			3:
				col = UI.ERROR
		var t: float = l[0]
		log_view.append_text("[color=#%s]%s[/color]  [color=#%s]%s[/color]\n" % [UI.DIM.to_html(false), _clock(t),
			col.to_html(false), String(l[2]).replace("[", "[lb]")])
	_log_seen = ms.log_serial


func _update_stages(stages: Array, el: float) -> void:
	var sig := ""
	for s in stages:
		sig += "%s%s|" % [s.id, s.state]
	if sig != _stage_sig:
		_stage_sig = sig
		for c in stage_box.get_children():
			stage_box.remove_child(c)
			c.queue_free()
		for s in stages:
			var row := UI.hbox(10)
			row.name = s.id
			var ic: Control
			match s.state:
				"run":
					var sp := Spinner.new()
					sp.custom_minimum_size = Vector2(16, 16)
					ic = sp
				"done":
					ic = UI.tex_icon("check", 16, UI.TEXT)
				"fail":
					ic = UI.tex_icon("x", 16, UI.ERROR)
				"skip":
					ic = UI.tex_icon("chevrons-right", 16, UI.DIM)
				_:
					ic = UI.tex_icon("circle-dot", 16, UI.DIM)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(ic)
			var col := UI.TEXT if s.state in ["run", "done"] else (UI.ERROR if s.state == "fail" else UI.DIM)
			var t := UI.label(s.title + (" – übersprungen, schon vorhanden" if s.state == "skip" else ""), 14, col, 600 if s.state == "run" else 400)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(t)
			var d := UI.label("", 13, UI.MUTED)
			d.name = "Dur"
			row.add_child(d)
			stage_box.add_child(row)
	for s in stages:
		var row := stage_box.get_node_or_null(NodePath(s.id))
		if row == null:
			continue
		var d: Label = row.get_node_or_null("Dur")
		if d == null:
			continue
		match s.state:
			"run":
				d.text = _clock(el - float(s.t0))
			"done", "fail":
				d.text = ("%.1f s" % (float(s.t1) - float(s.t0))).replace(".", ",")
			_:
				d.text = ""


func _update_conns(rows: Array) -> void:
	var sig := ""
	for r in rows:
		sig += r.host
	if sig != _conn_sig:
		_conn_sig = sig
		for c in conn_rows.get_children():
			conn_rows.remove_child(c)
			c.queue_free()
		for ri in rows.size():
			var r: Dictionary = rows[ri]
			var h := UI.hbox(10)
			h.name = "Ep%d" % ri
			var dot := ColorRect.new()
			dot.name = "Dot"
			dot.custom_minimum_size = Vector2(8, 8)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(dot)
			var host := UI.label(r.host, 13, UI.TEXT, 600)
			host.custom_minimum_size = Vector2(190, 0)
			h.add_child(host)
			var st := UI.label("", 13, UI.MUTED)
			st.name = "State"
			st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			st.clip_text = true
			h.add_child(st)
			var cnt := UI.label("", 12, UI.DIM)
			cnt.name = "Count"
			h.add_child(cnt)
			conn_rows.add_child(h)
	for ri in rows.size():
		var r: Dictionary = rows[ri]
		var h := conn_rows.get_node_or_null(NodePath("Ep%d" % ri))
		if h == null:
			continue
		var dot: ColorRect = h.get_node("Dot")
		match r.state:
			"busy":
				dot.color = UI.ACCENT
			"pause":
				dot.color = UI.ERROR
			_:
				dot.color = UI.DIM if r.ok == 0 else TileView.C_DONE
		(h.get_node("State") as Label).text = r.text
		(h.get_node("Count") as Label).text = "%d ok · %d Fehler · %s" % [r.ok, r.fail, MapDownloader._fmt_bytes(r.bytes)]


func _sum_fail(rows: Array) -> int:
	var n := 0
	for r in rows:
		n += int(r.fail)
	return n


func _stage_done(stages: Array, id: String) -> bool:
	for s in stages:
		if s.id == id:
			return s.state in ["done", "skip"]
	return true


func _eta(el: float, f: float) -> String:
	_hist.append([el, f])
	while _hist.size() > 2 and float(_hist[0][0]) < el - 30.0:
		_hist.pop_front()
	if f < 0.03 or f >= 0.999 or _hist.size() < 4:
		return ""
	var a: Array = _hist[0]
	var df := f - float(a[1])
	var dt := el - float(a[0])
	if df <= 0.0005 or dt < 3.0:
		return ""
	var rest := (1.0 - f) * dt / df
	if rest > 3600.0:
		return ""
	return "  · noch etwa " + _clock(rest)


static func _clock(t: float) -> String:
	var s := int(maxf(t, 0.0))
	return "%02d:%02d" % [s / 60, s % 60]


# ------------------------------------------------------------------------------------------
# Widgets
# ------------------------------------------------------------------------------------------

## Square map of the download: every piece is a tile in its state colour.
class TileView extends Control:
	const C_WAIT := Color(0.17, 0.17, 0.17)
	const C_DONE := Color(0.86, 0.86, 0.84)
	var tiles: Array = []
	var half := 3000.0
	var hq := Vector2.ZERO
	var all_done := false
	var fill := -1.0      # 0..1: one download for the whole map (Geofabrik); -1 = not used

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := Vector2((size.x - s) * 0.5, 0.0)
		draw_rect(Rect2(o, Vector2(s, s)), UI.BG2)
		var k := s / (half * 2.0)
		var t := Time.get_ticks_msec() / 1000.0
		if tiles.is_empty():
			# no piecewise download: a 1 km grid (filled from the centre while one file downloads)
			var n := maxi(1, int(round(half * 2.0 / 1000.0)))
			var cells := []
			for i in n:
				for j in n:
					cells.append(Vector2(i, j))
			var mid := Vector2(n - 1, n - 1) * 0.5
			cells.sort_custom(func(a, b): return a.distance_squared_to(mid) < b.distance_squared_to(mid))
			var filled := int(floor(fill * cells.size())) if fill >= 0.0 else 0
			for ci in cells.size():
				var cell: Vector2 = cells[ci]
				var r := Rect2(o + cell * 1000.0 * k, Vector2(1000.0, 1000.0) * k).grow(-1.0)
				var col := C_DONE if all_done else C_WAIT
				if fill >= 0.0 and not all_done:
					if ci < filled:
						col = C_DONE
					elif ci == filled:
						col = UI.ACCENT.lerp(UI.ACCENT_DARK, 0.5 + 0.5 * sin(t * 6.0))
				draw_rect(r, col)
		for tl in tiles:
			var rr: Rect2 = tl.rect
			var r2 := Rect2(o + (rr.position + Vector2(half, half)) * k, rr.size * k).grow(-1.0)
			var c := C_WAIT
			match tl.state:
				"done":
					c = C_DONE
				"active":
					c = UI.ACCENT.lerp(UI.ACCENT_DARK, 0.5 + 0.5 * sin(t * 6.0))
				"failed":
					c = UI.ERROR
			if all_done:
				c = C_DONE
			draw_rect(r2, c)
			if tl.get("retry", false) and tl.state == "pending":
				draw_rect(r2, UI.ERROR, false, 1.5)
		# yard marker
		var hp := o + (hq + Vector2(half, half)) * k
		draw_arc(hp, 7.0, 0.0, TAU, 24, Color(0.04, 0.04, 0.04), 4.0)
		draw_arc(hp, 7.0, 0.0, TAU, 24, UI.ACCENT, 2.0)
		draw_rect(Rect2(o, Vector2(s, s)), UI.LINE, false, 1.0)


## Small rotating arc: shows that the game is alive even when a step takes long.
class Spinner extends Control:
	var state := "run"

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		match state:
			"fail":
				draw_line(c - Vector2(r, r) * 0.7, c + Vector2(r, r) * 0.7, UI.ERROR, 2.5)
				draw_line(c + Vector2(-r, r) * 0.7, c + Vector2(r, -r) * 0.7, UI.ERROR, 2.5)
			_:
				var a := Time.get_ticks_msec() / 1000.0 * 5.0
				draw_arc(c, r, 0.0, TAU, 32, UI.LINE, 2.5, true)
				draw_arc(c, r, a, a + 4.0, 32, UI.ACCENT, 2.5, true)
