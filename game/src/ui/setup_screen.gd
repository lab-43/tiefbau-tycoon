class_name SetupScreen
extends Control
## Company founding: name, city search (Nominatim), HQ location on the map, map size.

signal back
signal create(company_name: String, meta: Dictionary)

var picker: MapPicker
var name_edit: LineEdit
var search_edit: LineEdit
var results: ItemList
var size_opt: OptionButton
var create_btn: Button
var hq_label: Label
var _results_data: Array = []
var _city_name := ""
var _hq := Vector2(INF, INF)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG_SOLID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := UI.hbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# left form
	var left := MarginContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	for side in ["left", "right", "top", "bottom"]:
		left.add_theme_constant_override("margin_" + side, 36)
	root.add_child(left)
	var form := UI.vbox(10)
	left.add_child(form)
	var title := UI.hbox(10)
	var bar := ColorRect.new()
	bar.color = UI.ACCENT
	bar.custom_minimum_size = Vector2(4, 30)
	title.add_child(bar)
	title.add_child(UI.label("Firma gründen", 26, UI.TEXT, 700))
	form.add_child(title)
	form.add_child(UI.label("Wähle eine Stadt und setze deine Zentrale. Um sie herum entsteht die Spielkarte mit echten Straßen.", 14, UI.MUTED))
	form.get_child(form.get_child_count() - 1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_gap(8))
	form.add_child(UI.caps("Firmenname"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "z. B. Hansa Tiefbau GmbH"
	name_edit.text = "Hansa Tiefbau GmbH"
	name_edit.text_changed.connect(func(_t): _update())
	form.add_child(name_edit)
	form.add_child(_gap(6))
	form.add_child(UI.caps("Stadt suchen"))
	var sh := UI.hbox(6)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Hamburg"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_submitted.connect(func(_t): _search())
	sh.add_child(search_edit)
	var sb := UI.button("", "search")
	sb.custom_minimum_size = Vector2(44, 0)
	sb.pressed.connect(_search)
	sh.add_child(sb)
	form.add_child(sh)
	results = ItemList.new()
	results.custom_minimum_size = Vector2(0, 150)
	results.item_selected.connect(_on_result)
	form.add_child(results)
	form.add_child(_gap(6))
	form.add_child(UI.caps("Kartengröße"))
	size_opt = OptionButton.new()
	size_opt.add_item("4 × 4 km – schnell geladen", 4000)
	size_opt.add_item("6 × 6 km – empfohlen", 6000)
	size_opt.add_item("10 × 10 km – groß (lange Ladezeit)", 10000)
	size_opt.select(1)
	size_opt.item_selected.connect(func(_i):
		picker.map_size_m = float(size_opt.get_selected_id())
		picker.queue_redraw())
	form.add_child(size_opt)
	form.add_child(_gap(6))
	form.add_child(UI.caps("Zentrale"))
	hq_label = UI.label("Noch kein Standort gewählt", 14, UI.MUTED)
	hq_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(hq_label)
	form.add_child(UI.spacer(false))
	var info := UI.label("Beim ersten Start werden die Kartendaten von OpenStreetMap geladen und aufbereitet. Das dauert je nach Größe einige Minuten und wird danach gespeichert.", 12, UI.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(info)
	var demo := UI.button("Ohne Internet: Offline-Demokarte (Utrecht)", "map-pin")
	demo.add_theme_font_size_override("font_size", 12)
	demo.pressed.connect(_create_demo)
	form.add_child(demo)
	var bh := UI.hbox(8)
	var back_btn := UI.button("Zurück", "x")
	back_btn.custom_minimum_size = Vector2(120, 44)
	back_btn.pressed.connect(func(): back.emit())
	bh.add_child(back_btn)
	create_btn = UI.button("Firma gründen", "flag", true)
	create_btn.custom_minimum_size = Vector2(0, 44)
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_create)
	bh.add_child(create_btn)
	form.add_child(bh)
	# right map
	var mapbox := MarginContainer.new()
	mapbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["right", "top", "bottom"]:
		mapbox.add_theme_constant_override("margin_" + side, 24)
	root.add_child(mapbox)
	picker = MapPicker.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker.hq_changed.connect(_on_hq)
	mapbox.add_child(picker)
	if Game.dev_fixture != "":
		picker.set_center(52.0907, 5.1214, 13.0)
		_city_name = "Utrecht (Testdaten)"
		search_edit.text = "Utrecht"
	else:
		picker.set_center(53.5511, 9.9937, 12.0)
		search_edit.text = "Hamburg"
		_city_name = "Hamburg"
	_update()


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _search() -> void:
	var q := search_edit.text.strip_edges()
	if q == "":
		return
	results.clear()
	results.add_item("Suche …")
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body):
		req.queue_free()
		results.clear()
		_results_data.clear()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			results.add_item("Suche fehlgeschlagen – Internetverbindung prüfen")
			return
		var arr = JSON.parse_string(body.get_string_from_utf8())
		if not (arr is Array) or arr.is_empty():
			results.add_item("Keine Treffer")
			return
		for r in arr:
			_results_data.append(r)
			results.add_item(str(r.get("display_name", "?"))))
	var url := "https://nominatim.openstreetmap.org/search?format=json&limit=6&accept-language=de&q=" + q.uri_encode()
	req.request(url, ["User-Agent: " + MapPicker.UA])


func _on_result(i: int) -> void:
	if i >= _results_data.size():
		return
	var r: Dictionary = _results_data[i]
	picker.set_center(float(r.lat), float(r.lon), 13.0)
	_city_name = str(r.get("display_name", "")).split(",")[0]


func _on_hq(lat: float, lon: float) -> void:
	_hq = Vector2(lat, lon)
	hq_label.text = "%.5f° N, %.5f° O – Karte %s um diesen Punkt" % [lat, lon, size_opt.get_item_text(size_opt.selected).split(" – ")[0]]
	hq_label.add_theme_color_override("font_color", UI.TEXT)
	_update()


func _update() -> void:
	create_btn.disabled = name_edit.text.strip_edges() == "" or _hq.x == INF


func _create() -> void:
	var size_m := float(size_opt.get_selected_id())
	var meta := {}
	var slug := _city_name.to_lower().replace(" ", "-").replace("(", "").replace(")", "")
	meta["id"] = "%s_%d" % [slug.left(24), int(Time.get_unix_time_from_system())]
	meta["name"] = _city_name
	if Game.dev_fixture != "":
		meta["center_lat"] = 52.0907
		meta["center_lon"] = 5.1214
		meta["size_m"] = 6000.0
		Geo.setup(52.0907, 5.1214)
		var p := Geo.to_local(_hq.x, _hq.y)
		meta["hq"] = {"x": clampf(p.x, -2500, 2500), "z": clampf(p.y, -2500, 2500), "lat": _hq.x, "lon": _hq.y}
		meta["id"] = "dev_" + Game.dev_fixture
	else:
		meta["center_lat"] = _hq.x
		meta["center_lon"] = _hq.y
		meta["size_m"] = size_m
		meta["hq"] = {"x": 0.0, "z": 0.0, "lat": _hq.x, "lon": _hq.y}
	create.emit(name_edit.text.strip_edges(), meta)


## Offline fallback: the bundled Utrecht test map (works without Overpass/OSM servers).
func _create_demo() -> void:
	Game.dev_fixture = "utrecht"
	var meta := {"id": "dev_utrecht", "name": "Utrecht (Demo)", "center_lat": 52.0907, "center_lon": 5.1214, "size_m": 6000.0,
		"hq": {"x": -650.0, "z": 420.0}}
	var n := name_edit.text.strip_edges()
	create.emit(n if n != "" else "Hansa Tiefbau GmbH", meta)
