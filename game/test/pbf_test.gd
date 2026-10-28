extends SceneTree
## Compares reading the Utrecht .pbf directly with reading the Overpass-format fixture made from it.
## usage: godot --headless -s res://test/pbf_test.gd -- <file.osm.pbf>   (tools/test.sh pbf)
## Prints "PBF OK" if both readers agree within the tolerances below, exit code 1 otherwise.
func _initialize() -> void:
	var pbf: String = OS.get_cmdline_user_args()[0]
	Geo.setup(52.0907, 5.1214)
	var t0 := Time.get_ticks_msec()
	var a := OsmParser.new()
	var da := a.parse_pbf(pbf, 3000.0, func(f, t): pass, func(t): print("  note: ", t))
	var ms_pbf := Time.get_ticks_msec() - t0
	print("PBF  %d ms: %s" % [ms_pbf, da.stats])
	t0 = Time.get_ticks_msec()
	var b := OsmParser.new()
	var db := b.parse_dir("res://test_fixtures/utrecht/osm", 3000.0)
	print("JSON %d ms: %s" % [Time.get_ticks_msec() - t0, db.stats])
	print("crossings %d/%d give_way %d/%d bus_stops %d/%d lamps %d/%d" % [da.crossings.size(), db.crossings.size(), da.give_way.size(), db.give_way.size(), da.bus_stops.size(), db.bus_stops.size(), da.lamps.size(), db.lamps.size()])
	# The fixture was cut from the same extract, so counts must match closely. PBF keeps a margin
	# around the map and complete multipolygon rings, hence slightly more roads/areas.
	var bad: Array = []
	for k in ["buildings", "roads", "areas", "paths", "rails", "trees", "signals", "bus_ways"]:
		var x: float = float(da.stats.get(k, 0))
		var y: float = float(db.stats.get(k, 0))
		var tol: float = 0.10 if k == "areas" else 0.02
		if y <= 0.0 or absf(x - y) / y > tol:
			bad.append("%s %d vs %d" % [k, int(x), int(y)])
	if da.bus_stops.size() != db.bus_stops.size() or da.crossings.size() != db.crossings.size():
		bad.append("bus_stops/crossings")
	if ms_pbf > 60000:
		bad.append("PBF zu langsam: %d ms" % ms_pbf)
	if bad.is_empty():
		print("PBF OK roads=%d buildings=%d in %d ms" % [da.stats.roads, da.stats.buildings, ms_pbf])
		quit(0)
	else:
		print("PBF FAIL ", bad)
		quit(1)
