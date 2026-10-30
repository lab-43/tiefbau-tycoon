extends Node
## Bridge heights (#32) on the Waltershof / Köhlbrand fixture (testdata/bruecken), once with the real ground heights
## of the fixture and once on a flat map, and on the flat Utrecht test map (many small canal bridges, rail lines):
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
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fixture="):
			dir = a.substr(10)
		elif a.begins_with("--nur="):
			only = a.substr(6)   # one run only (Gelände, flach, Utrecht), for debugging
	var spec = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("bruecken.json")))
	if typeof(spec) != TYPE_DICTIONARY:
		print("BRUECKEN FAIL bruecken.json fehlt in ", dir)
		get_tree().quit(1)
		return
	spec["koehlbrand"] = true
	var utrecht := {"lat": 52.0907, "lon": 5.1214, "halbe_kante_m": 3000.0, "pbf": "../utrecht.osm.pbf"}
	var res: Array = []
	for run in [[spec, true, "Gelände"], [spec, false, "flach"], [utrecht, false, "Utrecht"]]:
		if only == "" or only == run[2]:
			res.append(_run(dir, run[0], run[1], run[2]))
	if fails.is_empty():
		print("BRUECKEN OK ", " | ".join(res))
		get_tree().quit(0)
	else:
		print("BRUECKEN FAIL ", "; ".join(fails))
		get_tree().quit(1)


func _run(dir: String, spec: Dictionary, with_ground: bool, tag: String) -> String:
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
				# at the edges of a curved road the deck is level across its own direction, not along the trim
				# line: up to grade x the offset of the trim line (0.15 m allowed there, 0.1 m on the centre line)
				var d := absf(t.deck_at(dk, at) - node_h) * (1.0 if side == 0.0 else 0.1 / 0.15)
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
	if spec.get("koehlbrand", false) and kb < 40.0:
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
	if miss > 0 or (tried == 0 and spec.get("koehlbrand", false)):
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


## Stage 2: piers and abutments (BridgeStructures), deck undersides and edges. Checked against what the meshers
## drew and the OSM data, not against the helpers BridgeStructures uses itself.
func _structures(tag: String, t: Terrain, net: RoadNet, data: OsmData, bh: BridgeHeights, rm: RoadMesher) -> String:
	var bs := BridgeStructures.new(bh, net, t, AsphaltIndex.new(net, t))
	bs.build(rm)
	# railway and path decks: CityMesher
	var cm := CityMesher.new(data, net, 500.0)
	cm.terrain = t
	cm.rail_decks = bh.rail_decks
	cm.path_decks = bh.path_decks
	cm._rails()
	cm._paths()
	print("    ", bs.summary())
	if bs.piers.size() < 30 or bs.abutments.size() < 5:
		fails.append("[%s] zu wenige Pfeiler (%d) oder Widerlager (%d)" % [tag, bs.piers.size(), bs.abutments.size()])
	# drawn road surfaces (with their heights), deck undersides and the vertical walls of the bridge layer
	var surf := {}    # 10 m cell -> [[a, b, c] (Vector3)]
	var under := {}   # 10 m cell -> [[a, b, c] (Vector3)]
	var walls := {}   # 10 m cell -> [[p, q] (Vector2)]
	for ck in cm.chunks:
		var cbl = cm.chunks[ck].get("bridge")
		if cbl != null:
			_index_tris(cbl, under, func(n: Vector3): return n.y < -0.9)
	for ck in rm.chunks:
		for lname in ["asphalt", "asphalt_deck", "sidewalk", "sidewalk_deck"]:
			var ml = rm.chunks[ck].get(lname)
			if ml != null:
				_index_tris(ml, surf, func(_n: Vector3): return true)
		var bl = rm.chunks[ck].get("bridge")
		if bl != null:
			_index_tris(bl, under, func(n: Vector3): return n.y < -0.9)
			for i in range(0, (bl as MeshLayer).indices.size(), 3):
				if absf((bl as MeshLayer).normals[bl.indices[i]].y) > 0.2:
					continue
				var pa: Vector3 = bl.verts[bl.indices[i]]
				var pb: Vector3 = bl.verts[bl.indices[i + 1]]
				var pc: Vector3 = bl.verts[bl.indices[i + 2]]
				var ps := [Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), Vector2(pc.x, pc.z)]
				var seg := [ps[0], ps[1]]
				for u in 3:
					for v in range(u + 1, 3):
						if (ps[u] as Vector2).distance_to(ps[v]) > (seg[0] as Vector2).distance_to(seg[1]):
							seg = [ps[u], ps[v]]
				_add_cell(walls, Rect2(seg[0], Vector2.ZERO).expand(seg[1]), seg)
	# what may lie below a pier
	var water: Array = []
	for ar in data.areas:
		if ar.kind == "water" and (ar.outer as PackedVector2Array).size() >= 3:
			water.append(ar)
	var lines := {}   # railways and paths: [a, b, half width, railway?, way index]
	for ri in data.rails.size():
		var rp: PackedVector2Array = data.rails[ri].pts
		for k in rp.size() - 1:
			_add_cell(lines, Rect2(rp[k], Vector2.ZERO).expand(rp[k + 1]).grow(4.0), [rp[k], rp[k + 1], 1.7, true, ri])
	for pi in data.paths.size():
		var pp: PackedVector2Array = data.paths[pi].pts
		var hw := CityMesher.path_width(data.paths[pi].tags) * 0.5
		for k in pp.size() - 1:
			_add_cell(lines, Rect2(pp[k], Vector2.ZERO).expand(pp[k + 1]).grow(hw + 2.0), [pp[k], pp[k + 1], hw, false, pi])
	var houses := {}
	for bd in data.buildings:
		var o: PackedVector2Array = bd.outer
		if o.size() >= 3:
			var r := Rect2(o[0], Vector2.ZERO)
			for q in o:
				r = r.expand(q)
			_add_cell(houses, r, [o, r])
	var bad := {"Fahrbahn": 0, "Gleis": 0, "Weg": 0, "Gebäude": 0, "Wasser": 0, "nicht am Deck": 0}
	for pr in bs.piers:
		var c: Vector2 = pr.p
		var d: Vector2 = pr.d
		var rt := Geo.right_of(d)
		var top: float = pr.top
		var samples: Array = []
		for i in 7:
			for j in 5:
				samples.append(c + rt * (float(pr.w) * lerpf(-0.5, 0.5, i / 6.0)) + d * (float(pr.t) * lerpf(-0.5, 0.5, j / 4.0)))
		var hit := {}
		for q: Vector2 in samples:
			# a road surface below the deck: on the ground or a lower deck
			for tri in surf.get(_cell(q), []):
				var a3: Vector3 = tri[0]
				var b3: Vector3 = tri[1]
				var c3: Vector3 = tri[2]
				if Geometry2D.point_is_inside_triangle(q, Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), Vector2(c3.x, c3.z)) \
						and minf(a3.y, minf(b3.y, c3.y)) < top - 0.3:
					if not hit.has("Fahrbahn"):
						print("    (Fahrbahn %.2f m hoch unter dem Pfeiler, Pfeiler bis %.2f, Grund %.2f)" % [_tri_height(q, a3, b3, c3), top, t.sample(q.x, q.y)])
					hit["Fahrbahn"] = true
			for ln in lines.get(_cell(q), []):
				var cp := Geometry2D.get_closest_point_to_segment(q, ln[0], ln[1])
				if cp.distance_to(q) < float(ln[2]):
					var ldk: Dictionary = (bh.rail_decks if ln[3] else bh.path_decks).get(int(ln[4]), {})
					var lh := t.sample(cp.x, cp.y) if ldk.is_empty() else t.deck_at(ldk, cp)
					if lh < top - 0.5:
						hit["Gleis" if ln[3] else "Weg"] = true
			for hs in houses.get(_cell(q), []):
				if (hs[1] as Rect2).has_point(q) and Geometry2D.is_point_in_polygon(q, hs[0]):
					hit["Gebäude"] = true
			for wa in water:
				if _in_area(q, wa) and _water_run(q, d, water) < 70.0:
					if not hit.has("Wasser"):
						print("    (Wasser %.0f m entlang der Brücke)" % _water_run(q, d, water))
					hit["Wasser"] = true
		# the top of the pier meets the drawn underside above it
		var uh := NAN
		for tri in under.get(_cell(c), []):
			var a3: Vector3 = tri[0]
			var b3: Vector3 = tri[1]
			var c3: Vector3 = tri[2]
			if Geometry2D.point_is_inside_triangle(c, Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), Vector2(c3.x, c3.z)):
				var hgt := _tri_height(c, a3, b3, c3)
				if is_nan(uh) or absf(hgt - top) < absf(uh - top):
					uh = hgt
		if is_nan(uh) or absf(uh - top) > 0.25:
			hit["nicht am Deck"] = true
		for k in hit:
			bad[k] += 1
			if bad[k] <= 2:
				print("    Pfeiler: %s bei %s (%s, %.1f × %.1f m)" % [k, str(c.round()), ["Straße", "Gleis", "Weg"][int(bh.links[int(pr.link)].net)], pr.w, pr.t])
	print("    Pfeiler auf/an: ", bad)
	var nbad := 0
	for k in bad:
		nbad += int(bad[k])
	if nbad > 0:
		fails.append("[%s] Pfeiler am falschen Ort %s" % [tag, str(bad)])
	# road bridge decks closed underneath, and walls along every open edge of a junction on a bridge
	var pts_n := 0
	var open_under := 0
	var edge_n := 0
	var open_edge := 0
	for ei in t.decks:
		var e: Dictionary = net.edges[ei]
		if not e.bridge:
			continue
		var dk: Dictionary = t.decks[ei]
		var sp := float(e.trim_a) + 1.0
		while sp < float(e.len) - float(e.trim_b) - 1.0:
			var q: Vector2 = Geo.sample(e.pts, e.cum, sp)[0]
			sp += 10.0
			if t.deck_at(dk, q) - t.sample(q.x, q.y) < 2.0:
				continue
			pts_n += 1
			var covered := false
			for tri in under.get(_cell(q), []):
				if Geometry2D.point_is_inside_triangle(q, Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z)):
					covered = true
					break
			if not covered:
				open_under += 1
	for ni in t.node_decks:
		var n: Dictionary = net.nodes[ni]
		var all_bridge := true
		for end in n.ends:
			if not net.edges[end >> 1].bridge:
				all_bridge = false
		var poly: PackedVector2Array = n.get("polygon", PackedVector2Array())
		if not all_bridge or poly.size() < 3:
			continue
		for i in poly.size():
			var a2 := poly[i]
			var b2 := poly[(i + 1) % poly.size()]
			var m := (a2 + b2) * 0.5
			var out := Geo.right_of((b2 - a2).normalized())
			if Geometry2D.is_point_in_polygon(m + out * 0.3, poly):
				out = -out
			var q := m + out * 3.5   # beyond the sidewalk: open air unless a road goes on there
			if t.node_height(ni, m) - t.sample(m.x, m.y) < 2.0 or not t.raised_at(q).is_empty():
				continue
			edge_n += 1
			var near := false
			for wseg in walls.get(_cell(m), []) + walls.get(_cell(q), []):
				if Geometry2D.get_closest_point_to_segment(m + out * 1.5, wseg[0], wseg[1]).distance_to(m + out * 1.5) < 2.5:
					near = true
					break
			if not near:
				open_edge += 1
				if open_edge <= 2:
					print("    offener Rand einer Kreuzung auf einer Brücke bei %s" % str(m.round()))
	print("    Unterseite: %d von %d Punkten offen; Ränder von Kreuzungen auf Brücken: %d von %d ohne Wand" % [open_under,
		pts_n, open_edge, edge_n])
	if pts_n == 0 or open_under * 50 > pts_n:
		fails.append("[%s] Brückendecks unten offen (%d von %d)" % [tag, open_under, pts_n])
	if open_edge * 20 > edge_n:
		fails.append("[%s] Kreuzungen auf Brücken ohne Wand (%d von %d)" % [tag, open_edge, edge_n])
	# long high bridges stand on piers (some may find no room over rail yards or wide roads)
	var long_links := 0
	var bare := 0
	for li in bh.profiles:
		var l: Dictionary = bh.links[li]
		if not l.bridge or bh.big_chains.has(bh.chain[li]):
			continue
		var length: float = float(l.u1) - float(l.u0)
		var dk := bs.deck_of(li)
		if length < 2.0 * float(BridgeStructures.SPAN[int(l.net)]) or dk.is_empty():
			continue
		var mid: Vector2 = Geo.sample(l.pts, l.cum, (float(l.u0) + float(l.u1)) * 0.5)[0]
		if t.deck_at(dk, mid) - t.sample(mid.x, mid.y) < 4.0:
			continue
		long_links += 1
		var half := bs.half_of(li)
		var has := false
		for pr in bs.piers:   # a pier under this deck (it may belong to a parallel deck of the same width)
			if t.deck_ds(dk, pr.p).x <= half and t.deck_ds(dk, pr.p).y > float(l.u0) and t.deck_ds(dk, pr.p).y < float(l.u1):
				has = true
				break
		if not has:
			bare += 1
			if bare <= 4:
				print("    ohne Pfeiler: %s %.0f m lang, %.1f m hoch, Mitte %s" % [l.cls, length, t.deck_at(dk, mid) - t.sample(mid.x, mid.y), str(mid.round())])
	print("    lange hohe Brückenabschnitte %d, davon ohne Pfeiler %d" % [long_links, bare])
	# where roads, tracks or water fill the space below, a span stays without a pier (Waltershof: about a fifth)
	if long_links > 0 and bare * 4 > long_links:
		fails.append("[%s] %d von %d langen Brückenabschnitten ohne Pfeiler" % [tag, bare, long_links])
	return "%d Pfeiler, %d Widerlager" % [bs.piers.size(), bs.abutments.size()]


static func _cell(q: Vector2) -> Vector2i:
	return Vector2i(floori(q.x / 10.0), floori(q.y / 10.0))


static func _add_cell(grid: Dictionary, r: Rect2, item: Variant) -> void:
	for gx in range(floori(r.position.x / 10.0), floori(r.end.x / 10.0) + 1):
		for gz in range(floori(r.position.y / 10.0), floori(r.end.y / 10.0) + 1):
			var k := Vector2i(gx, gz)
			if not grid.has(k):
				grid[k] = []
			grid[k].append(item)


static func _index_tris(ml: MeshLayer, grid: Dictionary, keep: Callable) -> void:
	for i in range(0, ml.indices.size(), 3):
		if not keep.call(ml.normals[ml.indices[i]]):
			continue
		var a3: Vector3 = ml.verts[ml.indices[i]]
		var b3: Vector3 = ml.verts[ml.indices[i + 1]]
		var c3: Vector3 = ml.verts[ml.indices[i + 2]]
		var r := Rect2(Vector2(a3.x, a3.z), Vector2.ZERO).expand(Vector2(b3.x, b3.z)).expand(Vector2(c3.x, c3.z))
		_add_cell(grid, r, [a3, b3, c3])


## Height of the plane through triangle a-b-c above point q.
static func _tri_height(q: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := (b - a).cross(c - a)
	if absf(n.y) < 1e-6:
		return maxf(a.y, maxf(b.y, c.y))
	return a.y - (n.x * (q.x - a.x) + n.z * (q.y - a.z)) / n.y


## q lies on water area wa (not in one of its holes).
static func _in_area(q: Vector2, wa: Dictionary) -> bool:
	if not Geometry2D.is_point_in_polygon(q, wa.outer):
		return false
	for hole in wa.get("holes", []):
		if Geometry2D.is_point_in_polygon(q, hole):
			return false
	return true


## How far water reaches along d through c (any water area, both ways, 2 m steps, at most 240 m).
static func _water_run(c: Vector2, d: Vector2, water: Array) -> float:
	var run := 0.0
	for dirn in [1.0, -1.0]:
		var q: Vector2 = c
		for k in 60:
			q += d * dirn * 2.0
			var wet := false
			for wa in water:
				if _in_area(q, wa):
					wet = true
					break
			if not wet:
				break
			run += 2.0
	return run


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
