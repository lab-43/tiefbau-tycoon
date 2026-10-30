extends Node
## Bridge heights (#32) on the Waltershof / Köhlbrand fixture (testdata/bruecken), once with the real ground heights
## of the fixture and once on a flat map:
##   lichte Höhe – every road, railway, path and water crossed by a bridge has its clear height below the deck
##                 (cable-stayed bridges over wide water: 50 m, or as high as their own ramps allow),
##   Steigung    – raised decks rise no steeper than their class allows, unless the ground itself is steeper
##                 (then a ramp loses its height above the ground with that grade),
##   Stufen      – a raised road meets its junction without a step,
##   Köhlbrand   – the Köhlbrandbrücke stands more than 40 m above the water,
##   Rampen      – some roads next to bridges are raised as ramps and get embankments (RoadMesher),
##   Ruhe        – the solution settles (fewer than 6 rounds).
## usage: godot --headless --path game res://test/bridge_test.tscn -- --fixture=<testdata/bruecken>
## (a scene: TerrainBake reads tiles through TerrainSource, which needs the Game autoload)  ·  tools/test.sh bruecken
## Prints "BRUECKEN OK …" or "BRUECKEN FAIL …" (exit code 1).

var fails: Array = []


func _ready() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fixture="):
			dir = a.substr(10)
	var spec = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("bruecken.json")))
	if typeof(spec) != TYPE_DICTIONARY:
		print("BRUECKEN FAIL bruecken.json fehlt in ", dir)
		get_tree().quit(1)
		return
	var res: Array = []
	for with_ground in [true, false]:
		res.append(_run(dir, spec, with_ground))
	if fails.is_empty():
		print("BRUECKEN OK %s | %s" % res)
		get_tree().quit(0)
	else:
		print("BRUECKEN FAIL ", "; ".join(fails))
		get_tree().quit(1)


func _run(dir: String, spec: Dictionary, with_ground: bool) -> String:
	var tag := "Gelände" if with_ground else "flach"
	Geo.setup(float(spec.lat), float(spec.lon))
	var half: float = spec.halbe_kante_m
	var data := OsmParser.new().parse_pbf(dir.path_join(spec.pbf), half)
	var meta := {"center_lat": float(spec.lat), "center_lon": float(spec.lon), "size_m": half * 2.0,
		"terrain_dir": dir.path_join(spec.gelaende) if with_ground else ""}
	var t := TerrainBake.build(meta, data, {}, func(_s): pass)
	if with_ground and t == null:
		fails.append("Gelände der Testdaten nicht lesbar")
	if t == null:
		t = Terrain.flat_for(data.bounds)
	var net := RoadNet.new()
	net.build(data, {})
	var bh := BridgeHeights.new(t, net, data)
	bh.run()
	print("  [%s] %s, %d Runden" % [tag, bh.summary(), int(bh.stats.iterations)])
	if int(bh.stats.iterations) >= 6:
		fails.append("[%s] Höhen kommen nicht zur Ruhe" % tag)
	# clear heights
	var low := 0
	var by := {}
	for c in bh.crossings:
		var li: int = c.link
		var l: Dictionary = bh.links[li]
		var top := bh.height_at(li, float(c.s))
		var base: float = c.base
		var kind := "Wasser"
		if int(c.lower) >= 0:
			var ho := bh.height_and_origin(int(c.lower), float(c.ls))
			base = ho.x if int(ho.y) != bh.chain[li] else bh.ground_at(int(c.lower), float(c.ls))
			kind = ["Straße", "Gleis", "Weg"][int(bh.links[int(c.lower)].net)]
		var depth: float = BridgeHeights.BIG_DEPTH if c.big else float(BridgeHeights.DEPTH[int(l.net)])
		var free := top - base - depth
		var need: float = c.clear
		if c.big:
			var cp: Vector2 = Geo.sample(l.pts, l.cum, float(c.s))[0]
			need = minf(need, t.sample(cp.x, cp.y) + float(l.g) * bh.room_at(li, float(c.s)) - base - depth - 0.5)
		if not by.has(kind):
			by[kind] = [0, INF]
		by[kind][0] += 1
		by[kind][1] = minf(by[kind][1], free - need)
		if free < need - 0.1:
			low += 1
			if low <= 5:
				print("    zu niedrig: %s über %s: %.1f statt %.1f m bei %s" % [l.cls, kind, free, need,
					str(Geo.sample(l.pts, l.cum, float(c.s))[0].round())])
	var parts: Array = []
	for k in by:
		parts.append("%s %d (knappste Reserve %.1f m)" % [k, by[k][0], by[k][1]])
	print("    Kreuzungen: ", ", ".join(parts))
	if bh.crossings.size() < 100:
		fails.append("[%s] nur %d Kreuzungen unter Brücken gefunden" % [tag, bh.crossings.size()])
	if low > 0:
		fails.append("[%s] %d Kreuzungen zu niedrig" % [tag, low])
	# grades
	var steep := 0
	for li in bh.profiles:
		var l: Dictionary = bh.links[li]
		var z: PackedFloat32Array = bh.profiles[li]
		var step: float = float(l.len) / maxf(1.0, z.size() - 1)
		if step < 0.5:
			continue
		for k in z.size() - 1:
			var gr := absf(z[k + 1] - z[k]) / step
			if gr <= float(l.g) + 0.005:
				continue
			var pa: Vector2 = Geo.sample(l.pts, l.cum, step * k)[0]
			var pb: Vector2 = Geo.sample(l.pts, l.cum, step * (k + 1))[0]
			var ga := t.sample(pa.x, pa.y)
			var gb := t.sample(pb.x, pb.y)
			var on_ground := absf(z[k] - ga) < 0.02 or absf(z[k + 1] - gb) < 0.02
			# a ramp on falling ground goes down with the ground and loses its height above it with its grade
			var along_ground: bool = not l.bridge and absf((z[k + 1] - gb) - (z[k] - ga)) / step <= float(l.g) + 0.005
			if not on_ground and not along_ground:
				steep += 1
	print("    zu steil (nicht vom Gelände): ", steep)
	if steep > 0:
		fails.append("[%s] %d zu steile Stücke" % [tag, steep])
	# steps at junctions
	var worst := 0.0
	var worst_at := ""
	for ei in t.decks:
		var dk: Dictionary = t.decks[ei]
		var e: Dictionary = net.edges[ei]
		var total: float = float(e.len)
		for end in [[e.a, float(e.trim_a)], [e.b, total - float(e.trim_b)]]:
			var at: Vector2 = Geo.sample(e.pts, e.cum, clampf(float(end[1]), 0.0, total))[0]
			var node_h := t.node_height(int(end[0]), at)
			var d := absf(t.deck_at(dk, at) - node_h)
			if d > worst:
				worst = d
				worst_at = "%s %s an Knoten %d bei %s (Fahrbahn %.2f, Kreuzung %.2f, Grund %.2f)" % [e.cls, e.name,
					int(end[0]), str(at.round()), t.deck_at(dk, at), node_h, t.sample(at.x, at.y)]
	print("    größte Stufe zur Kreuzung: %.3f m %s" % [worst, worst_at])
	if worst > 0.1:
		fails.append("[%s] Stufe von %.2f m zwischen Fahrbahn und Kreuzung" % [tag, worst])
	# Köhlbrandbrücke
	var kb := 0.0
	for ei in t.decks:
		if String(net.edges[ei].name).contains("Köhlbrand"):
			var dk: Dictionary = t.decks[ei]
			var h: PackedFloat32Array = dk.h
			var g: PackedFloat32Array = dk.g
			for k in h.size():
				kb = maxf(kb, h[k] - g[k])
	print("    Köhlbrandbrücke: %.0f m über Grund" % kb)
	if kb < 40.0:
		fails.append("[%s] Köhlbrandbrücke nur %.0f m hoch" % [tag, kb])
	# ramps with embankments
	var rm := RoadMesher.new(net, 500.0, data.bounds.position)
	rm.terrain = t
	rm.build_all()
	var emb := 0
	for ck in rm.chunks:
		var l = rm.chunks[ck].get("embankment")
		if l != null:
			emb += (l as MeshLayer).indices.size() / 3
	print("    Rampen %.1f km, Böschungsdreiecke %d" % [float(bh.stats.ramp_m) / 1000.0, emb])
	if float(bh.stats.ramp_m) < 200.0 or emb == 0:
		fails.append("[%s] keine Rampen mit Böschung" % tag)
	return "%s: %d Kreuzungen, Köhlbrand %.0f m" % [tag, bh.crossings.size(), kb]
