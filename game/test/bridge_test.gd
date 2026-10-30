extends Node
## Bridge heights (#32) on the Waltershof / Köhlbrand fixture (testdata/bruecken), once with the real ground heights
## of the fixture and once on a flat map:
##   lichte Höhe – every road, railway, path and water crossed by a bridge has its clear height below the deck
##                 (cable-stayed bridges over wide water: 50 m, or as high as their own ramps allow),
##   Steigung    – raised decks rise no steeper than their class allows, unless the ground itself is steeper
##                 (then a ramp loses its height above the ground with that grade),
##   Stufen      – a raised road meets its junction without a step (centre line and both edges),
##   Durchdringen – no bridge cuts through a road it raised itself (same chain),
##   Köhlbrand   – the Köhlbrandbrücke stands more than 40 m above the water,
##   Mausklick   – a click from above hits the decks of high bridges (CameraRig.terrain_hit),
##   Rampen      – some roads next to bridges are raised as ramps and get embankments (RoadMesher), also below
##                 an edge that is raised only by a cross-slope,
##   Ruhe        – the solution settles (fewer than 6 rounds),
##   Bauwerk     – piers keep off roads (as drawn), railways and narrow water and reach the deck, long high
##                 bridges stand on piers, there are abutments and deck undersides (stage 2).
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
	var through := 0   # raised by the same chain (measured from the ground above): must still not cut through it
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
			var dep: float = BridgeHeights.BIG_DEPTH if c.big else float(BridgeHeights.DEPTH[int(l.net)])
			if top - dep < ho.x + 0.5:
				through += 1
				print("    Brücke durchdringt, was unter ihr liegt: %s über %s bei %s (Unterkante %.1f, darunter %.1f)" % [
					l.cls, kind, str(Geo.sample(l.pts, l.cum, float(c.s))[0].round()), top - dep, ho.x])
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
	if through > 0:
		fails.append("[%s] %d Brücken durchdringen, was unter ihnen liegt" % [tag, through])
	# grades: the grade of the link, or a quarter faster than the ground where that falls steeper (ramps)
	var steep := 0
	for li in bh.profiles:
		var l: Dictionary = bh.links[li]
		var z: PackedFloat32Array = bh.profiles[li]
		var step: float = float(l.len) / maxf(1.0, z.size() - 1)
		if step < 0.5:
			continue
		var allowed: float = float(l.g) + 0.005
		var lf: float = float(l.u1) - float(l.u0)
		if not l.bridge and lf >= 1.0:   # (worked out here, not with BridgeHeights.descent, which is under test)
			var pa0: Vector2 = Geo.sample(l.pts, l.cum, float(l.u0))[0]
			var pb0: Vector2 = Geo.sample(l.pts, l.cum, float(l.u1))[0]
			var fall := absf(t.sample(pa0.x, pa0.y) - t.sample(pb0.x, pb0.y)) / lf
			if fall > float(l.g):
				allowed = fall * 1.25 + 0.005
		for k in z.size() - 1:
			if absf(z[k + 1] - z[k]) / step <= allowed:
				continue
			var pa: Vector2 = Geo.sample(l.pts, l.cum, step * k)[0]
			var pb: Vector2 = Geo.sample(l.pts, l.cum, step * (k + 1))[0]
			if absf(z[k] - t.sample(pa.x, pa.y)) < 0.02 or absf(z[k + 1] - t.sample(pb.x, pb.y)) < 0.02:
				continue   # on the ground: the ground is that steep
			steep += 1
			if steep <= 3:
				print("    zu steil: %s %.1f %% (erlaubt %.1f %%) bei %s" % [l.cls, absf(z[k + 1] - z[k]) / step * 100.0,
					allowed * 100.0, str(pa.round())])
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
			var smp := Geo.sample(e.pts, e.cum, clampf(float(end[1]), 0.0, total))
			var across: Vector2 = Geo.right_of(smp[1]) * (float(dk.hw) - 0.5) * 0.9
			for side in [0.0, 1.0, -1.0]:   # the centre line and both edges (cross-slopes)
				var at: Vector2 = smp[0] + across * side
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
	# a mouse click from above hits the deck, not the water below (the ray starts above the highest bridge)
	var was := Terrain.cur
	Terrain.cur = t
	var miss := 0
	var tried := 0
	for ei in t.decks:
		var dk: Dictionary = t.decks[ei]
		var h: PackedFloat32Array = dk.h
		var g: PackedFloat32Array = dk.g
		var k := 0
		for i in h.size():
			if h[i] - g[i] > h[k] - g[k]:
				k = i
		if h[k] - g[k] < 10.0:
			continue
		var at: Vector2 = Geo.sample(dk.pts, dk.cum, float(dk.step) * k)[0]
		var deck := t.deck_at(dk, at)
		var from := Vector3(at.x + 30.0, deck + 60.0, at.y + 30.0)
		var hit = CameraRig.terrain_hit(from, (Vector3(at.x, deck, at.y) - from).normalized())
		tried += 1
		if hit == null or absf((hit as Vector3).y - deck) > 0.5:
			miss += 1
	Terrain.cur = was
	print("    Mausklick auf hohe Brücken: %d von %d verfehlt" % [miss, tried])
	if tried == 0 or miss > 0:
		fails.append("[%s] Mausklick verfehlt %d von %d hohen Brücken" % [tag, miss, tried])
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
	# a ramp edge above the ground stands on an embankment (also on cross-slopes where its centre lies on the
	# ground): just outside the edge there is embankment
	var tris := {}
	for ck in rm.chunks:
		var ml = rm.chunks[ck].get("embankment")
		if ml == null:
			continue
		for i in range(0, (ml as MeshLayer).indices.size(), 3):
			var tri: Array = []
			for j in 3:
				var v: Vector3 = ml.verts[ml.indices[i + j]]
				tri.append(Vector2(v.x, v.z))
			var r := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
			for gx in range(floori(r.position.x / 10.0), floori(r.end.x / 10.0) + 1):
				for gz in range(floori(r.position.y / 10.0), floori(r.end.y / 10.0) + 1):
					var key := Vector2i(gx, gz)
					if not tris.has(key):
						tris[key] = []
					tris[key].append(tri)
	var bare := 0
	var edges := 0
	for ei in t.decks:
		var e: Dictionary = net.edges[ei]
		if e.bridge:
			continue
		var dk: Dictionary = t.decks[ei]
		var s := float(e.trim_a) + 2.0
		while s < float(e.len) - float(e.trim_b) - 2.0:
			var smp := Geo.sample(e.pts, e.cum, s)
			s += 4.0
			for side in [1.0, -1.0]:
				var off: float = float(e.width) * 0.5 + float(e.sw_r if side > 0 else e.sw_l)
				var q: Vector2 = smp[0] + Geo.right_of(smp[1]) * off * side
				if t.deck_at(dk, q) - t.sample(q.x, q.y) < 0.3:
					continue
				edges += 1
				var out: Vector2 = smp[0] + Geo.right_of(smp[1]) * (off + 0.4) * side
				var hit := false
				for tri in tris.get(Vector2i(floori(out.x / 10.0), floori(out.y / 10.0)), []):
					if Geometry2D.point_is_inside_triangle(out, tri[0], tri[1], tri[2]):
						hit = true
						break
				if not hit:
					bare += 1
					if bare <= 3:
						print("    Rampenrand ohne Böschung: %s %s bei %s (%.2f m über Grund)" % [e.cls, e.name, str(q.round()),
							t.deck_at(dk, q) - t.sample(q.x, q.y)])
	print("    Rampenränder über Grund: %d, davon ohne Böschung %d" % [edges, bare])
	if bare > edges / 50:
		fails.append("[%s] %d von %d Rampenrändern ohne Böschung" % [tag, bare, edges])
	var st := _structures(tag, t, net, data, bh, rm)
	return "%s: %d Kreuzungen, Köhlbrand %.0f m, %s" % [tag, bh.crossings.size(), kb, st]


## Stage 2: piers and abutments (BridgeStructures), deck undersides. Checked against what the meshers drew and the
## OSM data, not against the helpers BridgeStructures uses itself.
func _structures(tag: String, t: Terrain, net: RoadNet, data: OsmData, bh: BridgeHeights, rm: RoadMesher) -> String:
	var bs := BridgeStructures.new(bh, net, t, AsphaltIndex.new(net, t))
	bs.build(rm)
	print("    ", bs.summary())
	if bs.piers.size() < 30 or bs.abutments.size() < 5:
		fails.append("[%s] zu wenige Pfeiler (%d) oder Widerlager (%d)" % [tag, bs.piers.size(), bs.abutments.size()])
	# ground asphalt as drawn (bridge decks and ramps are separate *_deck layers)
	var asph := {}
	var down := 0
	for ck in rm.chunks:
		var al = rm.chunks[ck].get("asphalt")
		if al != null:
			for i in range(0, (al as MeshLayer).indices.size(), 3):
				var tri: Array = []
				for j in 3:
					var v: Vector3 = al.verts[al.indices[i + j]]
					tri.append(Vector2(v.x, v.z))
				var r := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
				for gx in range(floori(r.position.x / 10.0), floori(r.end.x / 10.0) + 1):
					for gz in range(floori(r.position.y / 10.0), floori(r.end.y / 10.0) + 1):
						var k := Vector2i(gx, gz)
						if not asph.has(k):
							asph[k] = []
						asph[k].append(tri)
		var bl = rm.chunks[ck].get("bridge")
		if bl != null:
			for i in range(0, (bl as MeshLayer).indices.size(), 3):
				if (bl as MeshLayer).normals[bl.indices[i]].y < -0.9:
					down += 1
	if down == 0:
		fails.append("[%s] Brückendecks ohne Unterseite" % tag)
	# water areas
	var water: Array = []
	for a in data.areas:
		if a.kind == "water" and (a.outer as PackedVector2Array).size() >= 3:
			water.append(a.outer)
	var on_road := 0
	var on_rail := 0
	var in_water := 0
	var gap := 0
	for pr in bs.piers:
		var c: Vector2 = pr.p
		var d: Vector2 = pr.d
		var rt := Geo.right_of(d)
		var corners := [c, c + rt * (pr.w * 0.5) + d * (pr.t * 0.5), c - rt * (pr.w * 0.5) + d * (pr.t * 0.5),
			c + rt * (pr.w * 0.5) - d * (pr.t * 0.5), c - rt * (pr.w * 0.5) - d * (pr.t * 0.5)]
		var hit_road := false
		for q: Vector2 in corners:
			for tri in asph.get(Vector2i(floori(q.x / 10.0), floori(q.y / 10.0)), []):
				if Geometry2D.point_is_inside_triangle(q, tri[0], tri[1], tri[2]):
					hit_road = true
		if hit_road:
			on_road += 1
			if on_road <= 3:
				print("    Pfeiler auf der Fahrbahn bei %s" % str(c.round()))
		# railways on the ground
		for ri in data.rails.size():
			var rpts: PackedVector2Array = data.rails[ri].pts
			var rdk: Dictionary = bh.rail_decks.get(ri, {})
			var rect := PackedVector2Array([corners[1], corners[2], corners[4], corners[3]])
			for k in rpts.size() - 1:
				var cp := Geometry2D.get_closest_point_to_segment(c, rpts[k], rpts[k + 1])
				if _seg_rect_dist(rpts[k], rpts[k + 1], rect) < 2.0:
					if rdk.is_empty() or t.deck_at(rdk, cp) - t.sample(cp.x, cp.y) < 1.0:
						on_rail += 1
						if on_rail <= 3:
							print("    Pfeiler (%s, %.1f × %.1f m) %.1f m neben Gleis %d (%s, %.1f m über Grund) bei %s" % [
								["Straße", "Gleis", "Weg"][int(bh.links[int(pr.link)].net)], pr.w, pr.t, cp.distance_to(c), ri,
								data.rails[ri].tags.get("railway", ""), 0.0 if rdk.is_empty() else t.deck_at(rdk, cp) - t.sample(cp.x, cp.y),
								str(c.round())])
						break
		# in water only under bridges over wide water: how far the water reaches along the bridge from here
		for wpoly in water:
			if Geometry2D.is_point_in_polygon(c, wpoly):
				var run := 0.0
				for dirn in [1.0, -1.0]:
					var q: Vector2 = c
					for k in 60:
						q += d * dirn * 2.0
						if not Geometry2D.is_point_in_polygon(q, wpoly):
							break
						run += 2.0
				if run < 70.0:
					in_water += 1
					print("    Pfeiler im Wasser unter einer Brücke über %.0f m Wasser bei %s" % [run, str(c.round())])
				break
		# the pier reaches the deck
		var dk := bs.deck_of(int(pr.link))
		var depth: float = dk.get("depth", 0.0)
		if absf(float(pr.top) - (t.deck_at(dk, c) - depth)) > 0.15:
			gap += 1
	print("    Pfeiler auf Fahrbahnen %d, an Gleisen %d, in schmalem Wasser %d, nicht am Deck %d" % [on_road, on_rail, in_water, gap])
	if on_road + on_rail + in_water + gap > 0:
		fails.append("[%s] Pfeiler am falschen Ort (Fahrbahn %d, Gleis %d, Wasser %d, nicht am Deck %d)" % [tag, on_road,
			on_rail, in_water, gap])
	# long high bridges stand on piers (some may find no room over rail yards or wide roads)
	var long_links := 0
	var bare := 0
	for li in bh.profiles:
		var l: Dictionary = bh.links[li]
		if not l.bridge or bh.big_chains.has(bh.chain[li]):
			continue
		var length: float = float(l.u1) - float(l.u0)
		var dk := bs.deck_of(li)
		if length < 2.5 * float(BridgeStructures.SPAN[int(l.net)]) or dk.is_empty():
			continue
		var mid: Vector2 = Geo.sample(l.pts, l.cum, (float(l.u0) + float(l.u1)) * 0.5)[0]
		if t.deck_at(dk, mid) - t.sample(mid.x, mid.y) < 4.0:
			continue
		long_links += 1
		var has := false
		for pr in bs.piers:
			if int(pr.link) == li:
				has = true
				break
		if not has:
			bare += 1
	print("    lange hohe Brückenabschnitte %d, davon ohne Pfeiler %d" % [long_links, bare])
	if long_links > 0 and bare * 5 > long_links:
		fails.append("[%s] %d von %d langen Brückenabschnitten ohne Pfeiler" % [tag, bare, long_links])
	return "%d Pfeiler, %d Widerlager" % [bs.piers.size(), bs.abutments.size()]


## Distance between segment a-b and the convex polygon rect (0 if they touch).
static func _seg_rect_dist(a: Vector2, b: Vector2, rect: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(a, rect) or Geometry2D.is_point_in_polygon(b, rect):
		return 0.0
	var best := INF
	for i in rect.size():
		var p := rect[i]
		var q := rect[(i + 1) % rect.size()]
		if Geometry2D.segment_intersects_segment(a, b, p, q) != null:
			return 0.0
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
		best = minf(best, Geometry2D.get_closest_point_to_segment(a, p, q).distance_to(a))
		best = minf(best, Geometry2D.get_closest_point_to_segment(b, p, q).distance_to(b))
	return best
