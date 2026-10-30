extends RefCounted
## e2e scenario "platzieren" (#33, tools/test.sh platzieren): contracts can go almost anywhere on a street.
##   1. statistics: share of street points where the debug tool can place a contract, and why not
##   2. preview: the pit ghost of PlaceJobTool under the mouse (orange where it fits, red with a reason)
##   3. two real contracts played through without skipping: (A) the pit right behind a junction (short
##      taper, crew van parks on the lane leading in), (B) the pit as close to the next junction as the
##      machines allow (waiting spot and low-loader on the lane leading out; the excavator comes by lowbed)
## Driven by e2e_driver.gd, which owns the clock and shots. --platz-stat-only: only step 1; --platz-kurz:
## steps 1 and 2, then contract A is placed and its closure designer opened, but not played through;
## --platz-routen: only whether the fleet gets from the HQ to both spots.

var drv: Node
var step := 0
var fails := 0
var site: Site
var spot_a := {}
var spot_b := {}
var lb: Vehicle
var ex: Vehicle
var t_mark := 0.0
var seen := {}


func ok(cond: bool, what: String) -> void:
	print("PLATZ %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func tick(delta: float) -> void:
	var w: World = drv.world
	var jm: JobManager = w.jobs
	match step:
		0:
			if drv.t < 1.0:
				return
			_statistics(w, jm)
			if "--platz-stat-only" in OS.get_cmdline_user_args():
				_end()
				return
			_preview_good(w, jm)
			step = 10
		10:
			if not drv.shot_queue.is_empty():
				return
			_preview_bad(w)
			step = 11
		11:
			if not drv.shot_queue.is_empty():
				return
			tool.dispose()
			ok(tool.preview == null, "Vorschau verschwindet mit dem Werkzeug")
			spot_a = _find_spot(w, jm, "a")
			spot_b = _find_spot(w, jm, "b")
			if "--platz-routen" in OS.get_cmdline_user_args():
				for sp in [spot_a, spot_b]:
					var r := jm.check_spot(sp.p, JobManager.PIPES[0])
					var lay: SiteLayout = r.lay
					var dep: Dictionary = w.fleet.vehicles[0]._hq_departure_lane()
					var s_stop := minf(lay.s_det1 + 3.0 + 4.03, lay.len_k - 1.0)
					var pl: Array = w.router.plan(dep.key, 4.0, lay.key, s_stop)
					var pl2: Array = w.router.plan(dep.key, 4.0, lay.key, 1.0)
					print("PLATZ Route Zentrale -> K %d (s %.1f): %d Stücke, -> K-Anfang: %d Stücke, Abschnitt %s" % [lay.key, s_stop, pl.size(), pl2.size(), w.net.edges[lay.key >> 4].name])
				_end()
				return
			ok(not spot_a.is_empty(), "Stelle A gefunden (Grube direkt hinter einer Kreuzung)")
			ok(not spot_b.is_empty(), "Stelle B gefunden (Grube knapp vor der nächsten Kreuzung)")
			if spot_a.is_empty() or spot_b.is_empty():
				_end()
				return
			site = _place(jm, spot_a)
			if site == null:
				_end()
				return
			var lay := site.lay
			print("PLATZ A: %s, Grube s=%.1f..%.1f von %.1f m, Verziehung ab %.1f, Bus %s" % [site.job.location(), lay.s_t0, lay.s_t1, lay.len_k, lay.s0,
				"auf K bei %.1f" % lay.s_van if lay.s_van >= 0.0 else "nebenan (Spur %d)" % int(lay.van_spot().key)])
			ok(lay.squeezed, "A: Vorlage gestaucht")
			_open_designer(w, "A")
			step = 12
		12:
			if not drv.shot_queue.is_empty():
				return
			_close_designer(w)
			if "--platz-kurz" in OS.get_cmdline_user_args():
				# B only for its closure designer (it may lie next to A on the same street)
				var sb := _place(jm, spot_b)
				if sb != null:
					site = sb
					_open_designer(w, "B")
				step = 13
				return
			for v in w.fleet.vehicles:
				if v.def_id in ["van_crew", "excavator_a918", "truck_tipper", "truck_flatbed"]:
					site.send_vehicle(v)
			site.auto_continue = true
			step = 1
		13:
			if not drv.shot_queue.is_empty():
				return
			_close_designer(w)
			_end()
		1:
			if _follow(delta, "A"):
				ok(site.job.state == "done", "A: Auftrag abgenommen")
				seen.clear()
				step = 2
		2:
			# everyone home before the next contract
			for v in w.fleet.vehicles:
				if v.state != "parked" or not v.at_hq():
					return
			for v in w.fleet.vehicles:
				if v.def_id == "tractor_lowbed":
					lb = v
				elif v.def_id == "excavator_a918":
					ex = v
			site = _place(jm, spot_b)
			if site == null:
				_end()
				return
			var lay2 := site.lay
			var st: Dictionary = (lay2.kerb.stage as Array)[0]
			print("PLATZ B: %s, Grube s=%.1f..%.1f von %.1f m, Umleitung bis %.1f, Warteplatz %s, Tieflader %s" % [site.job.location(), lay2.s_t0, lay2.s_t1, lay2.len_k,
				lay2.s_det1, "Spur %d" % int(st.get("key", -1)), "Spur %d" % int(lay2.kerb.lowbed.get("key", -1))])
			ok(lay2.squeezed, "B: Vorlage gestaucht")
			ok(int(st.get("key", lay2.key)) != lay2.key, "B: Warteplatz auf der Nachbarstraße")
			_open_designer(w, "B")
			step = 20
		20:
			if not drv.shot_queue.is_empty():
				return
			_close_designer(w)
			lb.load_machine(ex)
			step = 3
		3:
			if lb.cargo.machine == ex and ex.carried_by == lb and lb.state == "parked":
				site.send_vehicle(lb)
				for v in w.fleet.vehicles:
					if v.def_id in ["van_crew", "truck_tipper", "truck_flatbed"]:
						site.send_vehicle(v)
				site.auto_continue = true
				t_mark = drv.t
				step = 4
		4:
			if _follow(delta, "B"):
				ok(site.job.state == "done", "B: Auftrag abgenommen")
				_end()


func _end() -> void:
	drv._dump()
	if fails > 0:
		print("E2E FAIL platzieren: %d Fehler" % fails)
		drv.get_tree().quit(1)
	else:
		print("E2E OK platzieren")
		drv.get_tree().quit(0)


var _nan_seen := false


## A transform with NaN floods the log and freezes whatever carries it: find the first one.
func _nan_check(tag: String) -> void:
	if _nan_seen:
		return
	var w: World = drv.world
	for ag in w.traffic.agents:
		if ag.visual and not ag.visual.global_position.is_finite():
			_nan_seen = true
			var pc: Dictionary = ag.route[ag.pi] if ag.pi < ag.route.size() else {}
			print("PLATZ NaN %s: Verkehr %d kind=%s pi=%d/%d piece t=%s key=%s s=%.2f tag=%s" % [tag, ag.id, ag.kind, ag.pi, ag.route.size(), pc.get("t", -1), pc.get("key", -1), ag.s, pc.get("tag", "")])
			if pc.has("pts"):
				print("      pts=%s" % str(pc.pts))
			ok(false, "%s: keine NaN-Position im Verkehr" % tag)
			return
	if site and is_instance_valid(site):
		for wk in site.workers:
			if not wk.global_position.is_finite():
				_nan_seen = true
				ok(false, "%s: keine NaN-Position bei der Kolonne" % tag)
				for i in site.item_defs.size():
					var dd: Dictionary = site.item_defs[i]
					if not (dd.pos as Vector2).is_finite() or not is_finite(float(dd.yaw)):
						print("      Teil %d %s pos=%s yaw=%s group=%s" % [i, dd.kind, dd.pos, dd.yaw, dd.get("group", "")])
				for l in site.yellow_lines:
					for q in l:
						if not q.is_finite():
							print("      gelbe Linie mit NaN")
							break
				print("      crew_point=%s van=%s" % [site.lay.crew_point(), site.lay.van_pose()])
				return
		for n in site.item_nodes:
			if n != null and is_instance_valid(n) and not (n as Node3D).global_position.is_finite():
				_nan_seen = true
				ok(false, "%s: keine NaN-Position bei den Absperrteilen" % tag)
				return
	for v in w.fleet.vehicles:
		if not v.global_position.is_finite():
			_nan_seen = true
			ok(false, "%s: keine NaN-Position bei %s" % [tag, v.vname])
			return


## Logs the phases of the current site and checks where the vehicles stand; true when it is finished.
func _follow(delta: float, tag: String) -> bool:
	_nan_check(tag)
	if site == null or not is_instance_valid(site) or site.retired:
		print("PLATZ %s fertig nach t=%.0f (Tag %d %s)" % [tag, drv.t, Clock.day, Clock.time_string()])
		return true
	if site.phase != drv.phase_seen:
		drv.phase_seen = site.phase
		print("[%7.1f] %s PHASE %d %s | %s" % [drv.t, tag, site.phase, site.step_id(), site.status])
		drv.shot("platz_%s_%02d_%s" % [tag, site.phase, site.step_id()], site.center3(), 60.0, -40.0, 50.0)
	for v in site.in_place:
		if not is_instance_valid(v):
			continue
		var sp: String = site.spot_of.get(v, "")
		var k := "%s_%s_%s" % [tag, v.vname, sp]
		if seen.has(k) or v.state != "parked" and v.state != "working":
			continue
		seen[k] = true
		var want := Vector2.INF
		if sp == "van":
			want = site.lay.van_pose().pos
		elif sp == "stage":
			var ss := site.lay.stage_spot(0, v.rear_ext)
			if not ss.is_empty():
				want = site.lay.kerb_pt(ss.key, ss.s, SiteLayout.CURB)
		var d: float = v.pos2().distance_to(want) if want != Vector2.INF else -1.0
		print("[%7.1f] %s %s steht auf %s%s" % [drv.t, tag, v.vname, sp, (" (%.1f m vom Platz)" % d) if d >= 0.0 else ""])
		if sp == "van":
			ok(d < 1.5, "%s: Kolonnenbus auf seinem Platz (%.1f m)" % [tag, d])
	drv.log_t += delta
	if drv.log_t > 60.0:
		drv.log_t = 0.0
		drv._dump()
	return false


func _place(jm: JobManager, spot: Dictionary) -> Site:
	var n := jm.active.size()
	var r := DebugTools.try_place_job_at(spot.p, true, spot.pipe_i)
	ok(r.ok and jm.active.size() == n + 1, "Auftrag platziert: %s" % r.msg)
	if not r.ok:
		return null
	var s: Site = jm.sites.get(jm.active[jm.active.size() - 1].id)
	drv.site = s
	drv.phase_seen = -1
	return s


## 1. Share of street points that take a contract (every 25 m along every street lane, at most ~2500 points).
func _statistics(w: World, jm: JobManager) -> void:
	var net: RoadNet = w.net
	var keys: Array = []
	for key in net.lane_geo:
		var e: Dictionary = net.edges[key >> 4]
		if e.cls in ["motorway", "motorway_link", "trunk", "trunk_link", "service"] or e.get("under", false):
			continue
		keys.append(key)
	keys.sort()
	var total_len := 0.0
	for key in keys:
		var cum: PackedFloat32Array = net.lane_geo[key][1]
		total_len += cum[cum.size() - 1]
	var step_m := maxf(25.0, total_len / 2500.0)
	var reasons := {}
	var n := 0
	var good := 0
	var bridges := 0
	var t0 := Time.get_ticks_msec()
	for key in keys:
		var g: Array = net.lane_geo[key]
		var cum: PackedFloat32Array = g[1]
		var ln: float = cum[cum.size() - 1]
		var s := fmod(float(key) * 7.0, step_m) + 3.0
		while s < ln - 3.0:
			var p: Vector2 = Geo.sample(g[0], cum, s)[0]
			n += 1
			var r := jm.check_spot(p, JobManager.PIPES[0])
			if r.ok:
				good += 1
			else:
				var why: String = RegEx.create_from_string("[0-9]+ m").sub(str(r.error), "N m", true)
				if why.begins_with("auf einer Brücke"):
					bridges += 1
				reasons[why] = int(reasons.get(why, 0)) + 1
			s += step_m
	var share := 100.0 * good / maxf(1.0, n)
	var share_nb := 100.0 * good / maxf(1.0, n - bridges)
	print("PLATZ %d Stellen (alle %.0f m), %d gehen (%.0f %%, ohne Brücken %.0f %%), %.1f ms je Prüfung" % [n, step_m, good, share, share_nb,
		float(Time.get_ticks_msec() - t0) / maxf(1.0, n)])
	var ks := reasons.keys()
	ks.sort_custom(func(a, b): return reasons[a] > reasons[b])
	for k in ks:
		print("PLATZ   %5d  %s" % [reasons[k], k])
	# Hamburg (4 x 4 km, harbour): 82 %; Utrecht: 59 % (many one-way streets with one lane, not possible yet,
	# and lanes the fleet cannot reach from the HQ or not leave towards it);
	# before #33 Hamburg had 34 %
	ok(share_nb >= 55.0, "mindestens 55 %% der Straßenpunkte außerhalb von Brücken nehmen einen Auftrag (%.0f %%)" % share_nb)


## 2. Preview of PlaceJobTool: orange on a good spot (centred on the mouse), red with a reason on a bad one.
var tool: PlaceJobTool
var _texts: Array = []
var _bad := Vector2.INF


func _preview_good(w: World, jm: JobManager) -> void:
	var net: RoadNet = w.net
	var good := Vector2.INF
	for key in net.lane_geo:
		var e: Dictionary = net.edges[key >> 4]
		var cum: PackedFloat32Array = net.lane_geo[key][1]
		var ln: float = cum[cum.size() - 1]
		if good == Vector2.INF and e.cls == "residential" and not e.bridge and ln > 120.0 and (key & 7) == net.lane_count(key >> 4, (key >> 3) & 1) - 1:
			var p: Vector2 = Geo.sample(net.lane_geo[key][0], cum, ln * 0.4)[0]
			var r := jm.check_spot(p, JobManager.PIPES[0])
			if r.ok and absf(float(r.shift)) < 0.01:
				good = p
		if _bad == Vector2.INF and e.bridge and not e.get("under", false) and ln > 30.0 and not (e.cls in JobManager.PLACE_EXCLUDE):
			_bad = Geo.sample(net.lane_geo[key][0], cum, ln * 0.5)[0]
	tool = PlaceJobTool.new()
	tool.pipe_i = 0
	tool.preview_changed.connect(func(tx, okv): _texts.append([tx, okv]))
	ok(good != Vector2.INF, "Vorschau: lange Wohnstraße gefunden")
	if good == Vector2.INF:
		return
	var cam: Camera3D = w.camera_rig.camera
	w.camera_rig.set_view(Site.gw(good, 0.0), 45.0, -30.0, 55.0)
	tool.on_mouse_move(cam.unproject_position(Site.gw(good, 0.0)))
	var pv := tool.preview
	ok(pv != null and pv.visible and pv.info.get("ok", false), "Vorschau: Grube an der Maus, orange (passt)")
	if pv and pv.info.get("ok", false):
		var c: Vector2 = (pv.info.lay as SiteLayout).trench_center()
		ok(c.distance_to(good) < 2.0, "Vorschau: Grube liegt am Mauszeiger (%.1f m daneben)" % c.distance_to(good))
	ok(not _texts.is_empty() and _texts[_texts.size() - 1][1], "Vorschau: Text „passt“ an das Debug-Menü")
	drv.shot("platz_vorschau_passt")


func _preview_bad(w: World) -> void:
	if _bad == Vector2.INF:
		return
	var pv := tool.preview
	var cam: Camera3D = w.camera_rig.camera
	# the deck, not the ground below it
	var deck := Vector3(_bad.x, Terrain.top(_bad), _bad.y)
	w.camera_rig.set_view(deck, 60.0, -30.0, 55.0)
	tool._last_ms = -1000
	tool.on_mouse_move(cam.unproject_position(deck))
	var gp = w.camera_rig.ground_point(cam.unproject_position(deck))
	print("PLATZ Brücke bei (%.1f, %.1f), Deck %.1f m, Boden %.1f m, Mausziel %s" % [_bad.x, _bad.y, deck.y, Terrain.at(_bad), gp])
	ok(pv.visible and not pv.info.get("ok", true), "Vorschau auf einer Brücke: rot")
	ok(str(pv.info.get("error", "")).find("Brücke") >= 0, "Vorschau: Grund genannt (%s)" % pv.info.get("error", ""))
	drv.shot("platz_vorschau_bruecke")


## The closure designer on a squeezed site: opens, draws, checks, shows the crew van where it parks.
func _open_designer(w: World, tag: String) -> void:
	var hud: HUD = drv.get_parent().hud
	if site.step_id() == "scout":
		site._scouted()   # the player plans after scouting (as the game demands)
	hud.open_closure_designer(site)
	var des: ClosureDesigner = hud.designer
	ok(des != null, "%s: Absperrung planen öffnet" % tag)
	if des == null:
		return
	des._refresh_side()
	ok(not des._checks.is_empty(), "%s: Planer prüft den Plan (%d Punkte)" % [tag, des._checks.size()])
	for c in des._checks:
		if c.get("required", false) and not c.ok:
			print("PLATZ %s Pflichtpunkt offen: %s – %s" % [tag, c.text, c.get("hint", "")])
			for bi in c.get("bad", []):
				var it: Dictionary = des.plan.items[bi]
				var lc := site.lay.lane_coords(ClosurePlan.item_center(it))
				print("      %s group=%s s=%.2f lat=%.2f yaw=%.2f" % [it.kind, it.get("group", ""), lc.x, lc.y, float(it.yaw)])
	var ext: Dictionary = des.plan.extent(site.lay)
	print("      Verkehr K: %s" % str(ext.k_ctrl))
	var req: Array = des._checks.filter(func(c): return c.get("required", false) and not c.ok).map(func(c): return c.text)
	ok(req.is_empty(), "%s: Vorlage erfüllt alle Pflichtpunkte %s" % [tag, str(req)])
	# the full closure template on the same squeezed spot (#20)
	des.set_full(true)
	des.load_template()
	des._refresh_side()
	var req2: Array = des._checks.filter(func(c): return c.get("required", false) and not c.ok).map(func(c): return "%s (%s)" % [c.text, c.get("hint", "")])
	ok(req2.is_empty(), "%s: Vorlage Vollsperrung erfüllt alle Pflichtpunkte %s" % [tag, str(req2)])
	des.set_full(false)
	des.load_template()
	var vr := des._spot_ref("van")
	var vp: Vector2 = site.lay.van_pose().pos
	ok(site.lay.lane_pt(vr.x, vr.y).distance_to(vp) < 3.0, "%s: Planer zeigt den Kolonnenbus dort, wo er parkt (%.1f m)" % [tag, site.lay.lane_pt(vr.x, vr.y).distance_to(vp)])
	drv.shot("platz_%s_planer" % tag)


func _close_designer(_w: World) -> void:
	var hud: HUD = drv.get_parent().hud
	if hud.designer:
		hud.designer.close(false)


## 3. A street spot for the long contracts: "a" = the pit right behind a junction, the crew van on the lane
## leading in; "b" = the pit as close to the next junction as possible, waiting spot on the lane leading out.
## Two-way residential-like streets, nearest to the HQ first. {p, pipe_i} or {}.
func _find_spot(w: World, jm: JobManager, kind: String) -> Dictionary:
	var net: RoadNet = w.net
	var hq: Vector2 = w.hq_info.get("lot_center", Vector2.ZERO)
	var best := {}
	var best_d := INF
	for key in net.lane_geo:
		var ei: int = key >> 4
		var e: Dictionary = net.edges[ei]
		if not (e.cls in ["residential", "tertiary", "unclassified", "secondary"]) or e.bridge or e.oneway:
			continue
		var dir: int = (key >> 3) & 1
		if (key & 7) != net.lane_count(ei, dir) - 1 or net.lane_count(ei, dir) != 1:
			continue
		var g: Array = net.lane_geo[key]
		var cum: PackedFloat32Array = g[1]
		var ln: float = cum[cum.size() - 1]
		if ln < 45.0 or ln > 110.0:
			continue
		var p: Vector2 = Geo.sample(g[0], cum, 5.5 if kind == "a" else ln - 26.0)[0]
		var dist := p.distance_to(hq)
		if dist > best_d or dist < 200.0:
			continue
		var r := jm.check_spot(p, JobManager.PIPES[0])
		if not r.ok:
			continue
		var lay: SiteLayout = r.lay
		if kind == "a" and not (lay.squeezed and lay.s_van < 0.0 and absf(float(r.shift)) < 0.5):
			continue
		if kind == "b":
			var st: Dictionary = (lay.kerb.stage as Array)[0]
			if st.is_empty() or int(st.key) == lay.key or (lay.kerb.lowbed as Dictionary).is_empty():
				continue
		best = {"p": p, "pipe_i": 0}
		best_d = dist
	return best
