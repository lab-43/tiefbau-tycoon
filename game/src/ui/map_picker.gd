class_name MapPicker
extends Control
## Slippy map (OpenStreetMap raster tiles) for choosing the HQ location. Drag = pan, wheel = zoom,
## click = place the headquarters. Shows the square that will become the playable map.

signal hq_changed(lat: float, lon: float)

const UA := "BaustellenManager/0.1 (private single-player game)"
const TILE_URL := "https://tile.openstreetmap.org/%d/%d/%d.png"

var center := Vector2(53.5511, 9.9937)   # lat, lon (Hamburg)
var zoom := 12.0
var hq := Vector2(INF, INF)
var map_size_m := 6000.0
var _tiles := {}       # key -> Texture2D or null (pending/failed)
var _queue: Array = []
var _active := 0
var _drag := false
var _drag_moved := 0.0
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	DirAccess.make_dir_recursive_absolute(Game.data_path("tiles"))
	var attr := UI.label("© OpenStreetMap-Mitwirkende", 11, Color(0.15, 0.15, 0.15))
	attr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	attr.position = Vector2(-190, -22)
	attr.offset_left = -190
	attr.offset_top = -22
	var bgp := Panel.new()
	bgp.add_theme_stylebox_override("panel", UI.flat(Color(1, 1, 1, 0.75), Color(0, 0, 0, 0), 0, 0))
	bgp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bgp.offset_left = -196
	bgp.offset_top = -24
	add_child(bgp)
	add_child(attr)


static func lonlat_to_px(lat: float, lon: float, z: float) -> Vector2:
	var n := 256.0 * pow(2.0, z)
	var la := deg_to_rad(clampf(lat, -85.0, 85.0))
	return Vector2((lon + 180.0) / 360.0 * n, (1.0 - log(tan(la) + 1.0 / cos(la)) / PI) / 2.0 * n)


static func px_to_lonlat(p: Vector2, z: float) -> Vector2:
	var n := 256.0 * pow(2.0, z)
	var lon := p.x / n * 360.0 - 180.0
	var lat := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * p.y / n))))
	return Vector2(lat, lon)


func set_center(lat: float, lon: float, z := -1.0) -> void:
	center = Vector2(lat, lon)
	if z > 0.0:
		zoom = z
	queue_redraw()


func _screen_to_latlon(sp: Vector2) -> Vector2:
	var c := lonlat_to_px(center.x, center.y, zoom)
	return px_to_lonlat(c + (sp - size * 0.5), zoom)


func _latlon_to_screen(lat: float, lon: float) -> Vector2:
	var c := lonlat_to_px(center.x, center.y, zoom)
	return lonlat_to_px(lat, lon, zoom) - c + size * 0.5


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_moved = 0.0
				_last_mouse = mb.position
			else:
				if _drag and _drag_moved < 5.0:
					var ll := _screen_to_latlon(mb.position)
					hq = ll
					hq_changed.emit(ll.x, ll.y)
					queue_redraw()
				_drag = false
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := _screen_to_latlon(mb.position)
			zoom = clampf(zoom + (0.5 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.5), 4.0, 18.0)
			# keep point under cursor
			var after_px := lonlat_to_px(before.x, before.y, zoom)
			var c_px := after_px - (mb.position - size * 0.5)
			var c := px_to_lonlat(c_px, zoom)
			center = c
			queue_redraw()
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		var mm := ev as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		var c := lonlat_to_px(center.x, center.y, zoom) - mm.relative
		center = px_to_lonlat(c, zoom)
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.86, 0.84))
	var zi := int(floor(zoom))
	var scale := pow(2.0, zoom - zi)
	var c := lonlat_to_px(center.x, center.y, zi)
	var tl := c - size * 0.5 / scale
	var tx0 := int(floor(tl.x / 256.0))
	var ty0 := int(floor(tl.y / 256.0))
	var tx1 := int(floor((tl.x + size.x / scale) / 256.0))
	var ty1 := int(floor((tl.y + size.y / scale) / 256.0))
	var maxt := int(pow(2, zi))
	for ty in range(ty0, ty1 + 1):
		for tx in range(tx0, tx1 + 1):
			if ty < 0 or ty >= maxt:
				continue
			var txw := posmod(tx, maxt)
			var key := "%d/%d/%d" % [zi, txw, ty]
			var r := Rect2((Vector2(tx * 256.0, ty * 256.0) - tl) * scale, Vector2(256, 256) * scale)
			var tex = _tiles.get(key, null)
			if tex is Texture2D:
				draw_texture_rect(tex, r, false)
			else:
				draw_rect(r, Color(0.82, 0.82, 0.80))
				draw_rect(r, Color(0.75, 0.75, 0.73), false, 1.0)
				if not _tiles.has(key):
					_request(zi, txw, ty)
	# map square + HQ
	if hq.x != INF:
		var p := _latlon_to_screen(hq.x, hq.y)
		var mpp := 156543.03392 * cos(deg_to_rad(hq.x)) / pow(2.0, zoom)
		var half := map_size_m * 0.5 / mpp
		draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), Color(1.0, 0.42, 0.07, 0.10))
		draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), UI.ACCENT, false, 2.0)
		draw_circle(p, 9.0, Color(0.04, 0.04, 0.04))
		draw_circle(p, 6.0, UI.ACCENT)
	else:
		var hint := "Klicke auf die Karte, um den Standort der Zentrale zu wählen"
		var f := UI.font(600)
		var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(Rect2(Vector2((size.x - w) * 0.5 - 12, 14), Vector2(w + 24, 32)), Color(0.04, 0.04, 0.04, 0.88))
		draw_string(f, Vector2((size.x - w) * 0.5, 35), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT)


func _request(z: int, x: int, y: int) -> void:
	var key := "%d/%d/%d" % [z, x, y]
	_tiles[key] = null
	var path := Game.data_path("tiles").path_join("%d_%d_%d.png" % [z, x, y])
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			_tiles[key] = ImageTexture.create_from_image(img)
			queue_redraw()
			return
	_queue.append([z, x, y, path, key])
	_pump()


func _pump() -> void:
	while _active < 4 and not _queue.is_empty():
		var job: Array = _queue.pop_back()
		_active += 1
		var req := HTTPRequest.new()
		req.timeout = 15.0
		add_child(req)
		req.request_completed.connect(func(result, code, _h, body):
			_active -= 1
			req.queue_free()
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				var img := Image.new()
				if img.load_png_from_buffer(body) == OK:
					img.save_png(job[3])
					_tiles[job[4]] = ImageTexture.create_from_image(img)
					queue_redraw()
			_pump())
		var err := req.request(TILE_URL % [job[0], job[1], job[2]], ["User-Agent: " + UA])
		if err != OK:
			_active -= 1
			req.queue_free()
