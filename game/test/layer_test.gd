extends SceneTree
## Height order of the flat map layers, baked from the Utrecht fixture (#4: the water lay under the opaque
## base ground plane and was never visible). Checks: water and landuse areas lie above MapBuilder.GROUND_Y,
## water lies above every landuse area and below paths, ballast and road surfaces.
## usage: godot --headless --path game -s res://test/layer_test.gd   (tools/test.sh ebenen)
## Prints "EBENEN OK" and exits 0, or "EBENEN FAIL [...]" and exits 1.

const ABOVE_WATER := ["path", "cycleway", "ballast", "asphalt", "sidewalk"]


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var meta := {"center_lat": 52.0907, "center_lon": 5.1214, "size_m": 6000.0}
	var res: Dictionary = MapBuilder.new().bake(meta, "res://test_fixtures/utrecht/osm")
	# layer name -> Vector2(min y, max y) over all chunks
	var span := {}
	for group in ["roads", "city"]:
		var chunks: Dictionary = res[group]
		for ck in chunks:
			for ln in chunks[ck]:
				var name: String = ln
				if not (name == "water" or name.begins_with("area_") or name in ABOVE_WATER):
					continue
				var l: MeshLayer = chunks[ck][ln]
				var s: Vector2 = span.get(name, Vector2(INF, -INF))
				for v in l.verts:
					s = Vector2(minf(s.x, v.y), maxf(s.y, v.y))
				span[name] = s
	var bad: Array = []
	if not span.has("water"):
		bad.append("keine Wasserfläche in Utrecht gebaut")
	else:
		var w: Vector2 = span["water"]
		for name in span:
			var s: Vector2 = span[name]
			if (name == "water" or String(name).begins_with("area_")) and s.x <= MapBuilder.GROUND_Y:
				bad.append("%s liegt mit %.3f nicht über dem Boden (%.3f)" % [name, s.x, MapBuilder.GROUND_Y])
			if String(name).begins_with("area_") and s.y >= w.x:
				bad.append("%s (bis %.3f) deckt das Wasser (%.3f) ab" % [name, s.y, w.x])
			if name in ABOVE_WATER and s.x <= w.y:
				bad.append("%s (ab %.3f) liegt nicht über dem Wasser (%.3f)" % [name, s.x, w.y])
	var txt := []
	for name in span:
		txt.append("%s %.3f..%.3f" % [name, span[name].x, span[name].y])
	print("Ebenen: ", ", ".join(txt))
	if bad.is_empty():
		print("EBENEN OK %d Ebenen in %d ms" % [span.size(), Time.get_ticks_msec() - t0])
		quit(0)
	else:
		print("EBENEN FAIL ", bad)
		quit(1)
