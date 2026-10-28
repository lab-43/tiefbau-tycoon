extends SceneTree
## Height order of the flat map layers (#4: the water lay under the opaque base ground plane and was never
## visible). Checks the height constants directly (covers area kinds a test map lacks) and the baked meshes
## of the Utrecht .pbf: water and landuse areas above MapBuilder.GROUND_Y, water above every landuse area and
## below paths, ballast, rails, markings and road surfaces.
## usage: godot --headless --path game -s res://test/layer_test.gd -- <utrecht.osm.pbf>   (tools/test.sh ebenen)
## Prints "EBENEN OK" and exits 0, or "EBENEN FAIL [...]" and exits 1 (also after a script error, via watchdog).

const ABOVE_WATER := ["path", "cycleway", "track", "ballast", "rail", "asphalt", "sidewalk", "mark"]
const WATCHDOG_S := 120.0

var _done := false


func _initialize() -> void:
	# a script error below would leave Godot running until the outer timeout; fail early instead
	create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	var bad: Array = []
	# a script error inside a function only aborts that function (it returns false), the caller goes on
	if not _check_constants(bad):
		bad.append("Prüfung der Konstanten abgebrochen (Skriptfehler?)")
	var args := OS.get_cmdline_user_args()
	var pbf: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://").path_join("../testdata/utrecht.osm.pbf")
	var t0 := Time.get_ticks_msec()
	var meta := {"center_lat": 52.0907, "center_lon": 5.1214, "size_m": 6000.0}
	var res: Dictionary = MapBuilder.new().bake(meta, "", pbf)
	if not _check_meshes(res, bad):
		bad.append("Prüfung der Meshes abgebrochen (Skriptfehler?)")
	_done = true
	if bad.is_empty():
		print("EBENEN OK in %d ms" % (Time.get_ticks_msec() - t0))
		quit(0)
	else:
		print("EBENEN FAIL ", bad)
		quit(1)


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("EBENEN FAIL nach %d s nicht fertig (Skriptfehler?)" % int(WATCHDOG_S))
	quit(1)


## The constants, independent of which area kinds the test map contains.
func _check_constants(bad: Array) -> bool:
	var w: float = CityMesher.WATER_Y
	if w <= MapBuilder.GROUND_Y:
		bad.append("WATER_Y %.3f liegt nicht über dem Boden %.3f" % [w, MapBuilder.GROUND_Y])
	for kind in CityMesher.Y:
		var y: float = CityMesher.Y[kind]
		if y <= MapBuilder.GROUND_Y or y >= w:
			bad.append("Fläche %s auf %.3f liegt nicht zwischen Boden und Wasser (%.3f)" % [kind, y, w])
	var order := [["Wasser", w], ["Gleisbett", CityMesher.BALLAST_Y], ["Wege", CityMesher.PATH_Y], ["Straße", RoadMesher.Y_ROAD]]
	for i in range(1, order.size()):
		if float(order[i][1]) <= float(order[i - 1][1]):
			bad.append("%s (%.3f) liegt nicht über %s (%.3f)" % [order[i][0], order[i][1], order[i - 1][0], order[i - 1][1]])
	return true


## The baked meshes: min/max height per layer over all chunks.
func _check_meshes(res: Dictionary, bad: Array) -> bool:
	var span := {}   # layer name -> Vector2(min y, max y), only layers with vertices
	for group in ["roads", "city"]:
		var chunks: Dictionary = res[group]
		for ck in chunks:
			for ln in chunks[ck]:
				var name: String = ln
				if not (name == "water" or name.begins_with("area_") or name in ABOVE_WATER):
					continue
				var l: MeshLayer = chunks[ck][ln]
				if l.verts.is_empty():
					continue
				var s: Vector2 = span.get(name, Vector2(INF, -INF))
				for v in l.verts:
					s = Vector2(minf(s.x, v.y), maxf(s.y, v.y))
				span[name] = s
	var txt := []
	for name in span:
		txt.append("%s %.3f..%.3f" % [name, span[name].x, span[name].y])
	print("Ebenen: ", ", ".join(txt))
	for need in ["water", "area_paved", "ballast", "path", "asphalt"]:
		if not span.has(need):
			bad.append("Ebene %s fehlt in Utrecht (Test prüft sonst ins Leere)" % need)
	if not span.has("water"):
		return true
	var w: Vector2 = span["water"]
	for name in span:
		var s: Vector2 = span[name]
		var n := String(name)
		if (n == "water" or n.begins_with("area_")) and s.x <= MapBuilder.GROUND_Y:
			bad.append("%s liegt mit %.3f nicht über dem Boden (%.3f)" % [n, s.x, MapBuilder.GROUND_Y])
		if n.begins_with("area_") and s.y >= w.x:
			bad.append("%s (bis %.3f) deckt das Wasser (%.3f) ab" % [n, s.y, w.x])
		if n in ABOVE_WATER and s.x <= w.y:
			bad.append("%s (ab %.3f) liegt nicht über dem Wasser (%.3f)" % [n, s.x, w.y])
	return true
