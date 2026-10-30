extends RefCounted
## e2e scenario "gelaende" (tools/test.sh gelaende, #8): map with ground heights (--terrain=synthetic).
## Checks that map layers, HQ, company vehicles, traffic and the camera sit on the terrain and takes
## pictures of slopes when rendered (--shots). Driven by e2e_driver.gd (_gelaende_test).

var drv: Node            # the e2e driver (world, t, shot(), _dump())
var step := 0
var fails := 0
var t_mark := 0.0
var _shots: Array = []


func ok(cond: bool, what: String) -> void:
	print("GELAENDE %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func tick(_delta: float) -> void:
	var w: World = drv.world
	match step:
		0:
			if drv.t < 2.0:
				return
			var tr := Terrain.cur
			ok(tr != null, "Gelände geladen")
			if tr == null:
				_end()
				return
			var lo := float(tr.info.get("min", 0.0))
			var hi := float(tr.info.get("max", 0.0))
			ok(hi - lo > 5.0, "Höhenunterschied %.1f m" % (hi - lo))
			if TerrainSource._url_override() != "":
				_check_download(tr)
			_check_layers(w)
			_check_bridges(w)
			_check_hq(w)
			_check_vehicles(w)
			_check_camera(w)
			# pictures: the HQ, a slope with traffic, the overview with and without buildings (one at a time)
			var lc: Vector2 = w.hq_info.lot_center
			var steep := _steepest_road(w)
			if steep == Vector2.INF:
				steep = lc
			_shots = [["gelaende_hq", lc, 110.0, -30.0, 35.0, true], ["gelaende_hang", steep, 70.0, 60.0, 20.0, true],
				["gelaende_hang_weit", steep, 300.0, 150.0, 16.0, true], ["gelaende_uebersicht", lc, 1500.0, -20.0, 20.0, true],
				["gelaende_ohne_gebaeude", lc, 1500.0, -20.0, 20.0, false]]
			t_mark = drv.t
			step = 1
		1:
			# let traffic drive for a while, then check it sits on the roads
			if not drv.shot_queue.is_empty():
				return
			if not _shots.is_empty():
				var sh: Array = _shots.pop_front()
				_buildings(w, sh[5])
				drv.shot(sh[0], Vector3(sh[1].x, 0, sh[1].y), sh[2], sh[3], sh[4])
				return
			_buildings(w, true)
			if drv.t - t_mark < 20.0:
				return
			_check_traffic(w)
			_end()


func _buildings(w: World, on: bool) -> void:
	for holder in w.city.get_children():
		var b := holder.get_node_or_null("building")
		if b:
			b.visible = on


func _end() -> void:
	drv._dump()
	if fails == 0:
		print("E2E OK gelaende")
		drv.get_tree().quit(0)
	else:
		print("E2E FAIL gelaende: %d Fehler" % fails)
		drv.get_tree().quit(1)


## Baked map layers: every vertex lies at its layer height above the ground. Bridge decks are skipped, and the
## tolerance covers the vertex compression of the meshes (16 bit over the chunk's extent).
func _check_layers(w: World) -> void:
	var expect := {"asphalt": RoadMesher.Y_ROAD, "sidewalk": RoadMesher.Y_SW, "mark": RoadMesher.Y_MARK,
		"area_grass": CityMesher.Y.grass, "area_residential": CityMesher.Y.residential, "ground": 0.0}
	var tr := Terrain.cur
	var checked := {}
	var bad := {}
	for holder in w.city.get_children():
		for mi in holder.get_children():
			if not (mi is MeshInstance3D) or not expect.has(String(mi.name)):
				continue
			var mesh: ArrayMesh = mi.mesh
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var bb := mesh.get_aabb()
			var q := maxf(bb.size.x, bb.size.z) / 65535.0
			var nm := String(mi.name)
			for k in range(0, verts.size(), maxi(1, verts.size() / 40)):
				var v := verts[k] + (mi as MeshInstance3D).position   # meshes sit at their chunk (#5)
				var p := Vector2(v.x, v.z)
				var g := tr.sample(v.x, v.z)
				if _on_bridge(tr, p):
					continue
				var tol := 0.003 + tr.gradient(v.x, v.z).length() * q * 1.5 + q * 0.0
				checked[nm] = int(checked.get(nm, 0)) + 1
				if absf(v.y - g - float(expect[nm])) > tol:
					bad[nm] = int(bad.get(nm, 0)) + 1
					if int(bad[nm]) <= 3:
						print("GELAENDE  Abweichung %s bei (%.2f, %.3f, %.2f): %.4f über Grund (Toleranz %.4f)" % [nm, v.x, v.y, v.z, v.y - g, tol])
	for nm in expect:
		ok(int(checked.get(nm, 0)) > 0, "Ebene %s geprüft (%d Punkte)" % [nm, int(checked.get(nm, 0))])
		ok(int(bad.get(nm, 0)) == 0, "Ebene %s liegt auf dem Gelände (%d Abweichungen)" % [nm, int(bad.get(nm, 0))])


## Junctions on a bridge: the road starts at the junction's height (no step where the junction area ends), and a
## click on a bridge picks the deck, not the ground below.
func _check_bridges(w: World) -> void:
	var tr := Terrain.cur
	var n := 0
	var worst := 0.0
	for ei in tr.decks:
		var dk: Dictionary = tr.decks[ei]
		var e: Dictionary = w.net.edges[ei]
		var pts: PackedVector2Array = dk.pts
		var total: float = (dk.cum as PackedFloat32Array)[pts.size() - 1]
		for end in [[e.a, float(e.trim_a)], [e.b, total - float(e.trim_b)]]:
			if not tr.node_decks.has(end[0]) or total < 1.0:
				continue
			var at_trim: Vector2 = Geo.sample(pts, dk.cum, clampf(float(end[1]), 0.0, total))[0]
			worst = maxf(worst, absf(tr.deck_at(dk, at_trim) - tr.node_height(end[0], at_trim)))
			n += 1
	print("GELAENDE Kreuzungen auf Brücken: %d Anschlüsse geprüft" % n)
	ok(worst < 0.05, "Brückenfahrbahn trifft Kreuzung ohne Stufe (max. %.3f m)" % worst)
	var picked := 0
	var high := 0
	for ei in tr.decks:
		var dk: Dictionary = tr.decks[ei]
		var pts: PackedVector2Array = dk.pts
		var mid: Vector2 = Geo.sample(pts, dk.cum, (dk.cum as PackedFloat32Array)[pts.size() - 1] * 0.5)[0]
		var deck := tr.deck_at(dk, mid)
		if deck - tr.sample(mid.x, mid.y) < 2.0:
			continue
		high += 1
		var from := Vector3(mid.x + 30.0, deck + 60.0, mid.y + 30.0)
		var hit = CameraRig.terrain_hit(from, (Vector3(mid.x, deck, mid.y) - from).normalized())
		if hit != null and absf((hit as Vector3).y - deck) < 0.5:
			picked += 1
		elif high - picked <= 5:
			var e: Dictionary = w.net.edges[ei]
			print("GELAENDE   Klick verfehlt: %s%s bei %s, Deck %.2f, Treffer %s, top dort %.2f" % [e.cls,
				" (Brücke)" if e.bridge else "", str(mid.round()), deck, str(hit), Terrain.top(mid)])
			for oi in tr.decks:   # what lies higher at the same spot
				var od: Dictionary = tr.decks[oi]
				var ods := tr.deck_ds(od, mid)
				if oi != ei and ods.x <= float(od.hw) and tr.deck_at(od, mid) > deck + 0.3:
					var oe: Dictionary = w.net.edges[oi]
					print("GELAENDE     darüber: Kante %d %s%s, %.1f m von ihrer Mitte (Breite/2 %.1f), Höhe %.2f" % [oi, oe.cls,
						" (Brücke)" if oe.bridge else "", ods.x, float(od.hw), tr.deck_at(od, mid)])
			for ni in tr.node_pos:
				var dn: float = (tr.node_pos[ni] as Vector2).distance_to(mid)
				if tr._on_node(ni, mid) and tr.node_height(ni, mid) > deck + 0.3:
					print("GELAENDE     darüber: Kreuzung %d, %.1f m entfernt (Radius %.1f), Höhe %.2f" % [ni, dn,
						float(tr.node_r.get(ni, Terrain.NODE_R)), tr.node_height(ni, mid)])
	ok(picked == high, "Mausklick trifft die Brücke (%d von %d)" % [picked, high])


## Within a deck footprint (bridges, ramps and raised junctions).
func _on_bridge(tr: Terrain, p: Vector2) -> bool:
	for ei in tr.decks:
		var dk: Dictionary = tr.decks[ei]
		if tr.deck_ds(dk, p).x <= float(dk.hw) + 3.0:
			return true
	for ni in tr.node_pos:
		if (tr.node_pos[ni] as Vector2).distance_to(p) <= Terrain.NODE_R + 3.0:
			return true
	return false


## Heights from the local tile server (test/mock_terrain.py): a tilted plane, so the values are known.
func _check_download(tr: Terrain) -> void:
	ok(String(tr.info.get("source", "")) == "test", "Höhen vom Test-Server (Quelle %s)" % tr.info.get("source", "?"))
	var good := 0
	var n := 0
	var worst := 0.0
	for gx in range(-2500, 2600, 500):
		for gz in range(-2500, 2600, 500):
			var p := Vector2(gx, gz)
			var ll := Geo.to_latlon(p)
			var expect := 12.0 + 900.0 * (ll.y - 5.1214) - 700.0 * (ll.x - 52.0907)
			var d := absf(tr.sample(p.x, p.y) - expect)
			n += 1
			if d < 0.1:
				good += 1
			else:
				worst = maxf(worst, d)
	# water beds and the levelled HQ yard differ on purpose
	ok(good >= n * 0.8, "Höhen stimmen mit dem Test-Server überein (%d von %d Punkten, sonst bis %.2f m)" % [good, n, worst])


func _check_hq(w: World) -> void:
	var lot: PackedVector2Array = w.hq_info.lot
	var c := Geo.polygon_centroid(lot)
	var dev := 0.0
	for p in lot:
		var q := c.lerp(p, 0.8)
		dev = maxf(dev, absf(Terrain.at(q) - w.hq.level))
	ok(dev < 0.05, "Hof der Zentrale eben (Abweichung %.3f m)" % dev)


func _check_vehicles(w: World) -> void:
	var worst := 0.0
	for v in w.fleet.vehicles:
		if v.carried_by != null:
			continue
		var g := Terrain.near(v.pos2(), v.global_position.y)
		worst = maxf(worst, absf(v.global_position.y - g))
	ok(worst < 0.05, "Firmenfahrzeuge stehen auf dem Boden (max. %.3f m)" % worst)


func _check_camera(w: World) -> void:
	var cam := w.camera_rig
	var vp := cam.camera.get_viewport().get_visible_rect().size
	var gp = cam.ground_point(vp * 0.5)
	ok(gp != null, "Mausklick trifft das Gelände")
	if gp != null:
		var d := Vector2((gp as Vector3).x - cam.target.x, (gp as Vector3).z - cam.target.z).length()
		ok(d < 3.0, "Bildmitte = Kameraziel auf dem Gelände (%.2f m)" % d)


func _check_traffic(w: World) -> void:
	var n := 0
	var worst := 0.0
	var max_pitch := 0.0
	for ag in w.traffic.agents:
		if ag.player != null:
			continue
		var pc: Dictionary = ag.route[ag.pi]
		var pose := Router.piece_pose(pc, ag.s)
		var y := 0.05 + Terrain.piece_y(pc, pose[0])
		worst = maxf(worst, absf(ag.p_cur.y - y))
		max_pitch = maxf(max_pitch, absf(ag.pitch_cur))
		n += 1
	ok(n > 5, "Verkehr unterwegs (%d Fahrzeuge)" % n)
	ok(worst < 0.01, "Verkehr fährt auf der Fahrbahn (max. %.3f m)" % worst)
	ok(max_pitch > 0.001 and max_pitch < 0.35, "Fahrzeuge neigen sich am Hang (max. %.1f°)" % rad_to_deg(max_pitch))


## Middle of the road edge with the largest height difference (for the slope pictures).
func _steepest_road(w: World) -> Vector2:
	var best := Vector2.INF
	var best_g := 0.0
	for e in w.net.edges:
		if e.bridge or float(e.len) < 40.0:
			continue
		var pts: PackedVector2Array = e.pts
		var g := absf(Terrain.at(pts[0]) - Terrain.at(pts[pts.size() - 1])) / float(e.len)
		if g > best_g and w.bounds.grow(-400.0).has_point(pts[0]):
			best_g = g
			best = Geo.sample(pts, e.cum, float(e.len) * 0.5)[0]
	print("GELAENDE steilste Straße: %.1f %% Steigung" % (best_g * 100.0))
	return best
