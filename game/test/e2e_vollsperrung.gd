extends RefCounted
## e2e scenario "vollsperrung" (tools/test.sh vollsperrung, #20): a full road closure planned in the
## closure designer (toggle, template, checks, key 0 = Z 250), built; background traffic no longer
## turns into the closed road, cars caught in front of the barrier vanish, company vehicles route
## around it, the site's own excavator still reaches its slot; saved; opened again after the teardown.
## Driven by e2e_driver.gd (_vollsperrung_test), which owns the clock and the screenshots.

var drv: Node
var step := 0
var fails := 0
var site: Site
var hud: HUD
var des: ClosureDesigner
var t_mark := 0.0
var inside0 := {}        # agent id -> true: on the closed road (or turning into it) when it closed
var intruders := {}
var seen_traffic := 0


func ok(cond: bool, what: String) -> void:
	print("VOLL %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func tick(_delta: float) -> void:
	var w: World = drv.world
	match step:
		0:
			if drv.t < 1.0:
				return
			hud = drv.get_parent().hud
			site = _place(w.jobs)
			ok(site != null, "Auftrag platziert")
			if site == null:
				_end()
				return
			DebugTools.finish_step(site)   # scout
			# traffic around the site
			w.camera_rig.set_view(site.center3(), 260.0, -30.0, 52.0)
			DebugTools.set_traffic(2.5)
			Game.select(site)
			hud._rebuild_right()
			var btn := _find_button(hud.right_body, "Absperrung planen")
			ok(btn != null, "Knopf „Absperrung planen“")
			if btn:
				btn.pressed.emit()
			des = hud.designer
			ok(des != null, "Designer offen")
			if des == null:
				_end()
				return
			_design()
			drv.shot("voll_01_plan")
			t_mark = drv.t
			step = 1
		1:
			if not drv.shot_queue.is_empty() or drv.t - t_mark < 0.5:
				return
			des.accept_btn.pressed.emit()
			ok(hud.designer == null and site.plan.full, "Vollsperrung übernommen")
			# let traffic build up for a while before the road closes
			t_mark = drv.t
			step = 2
		2:
			if drv.t - t_mark < 60.0:
				return
			DebugTools.finish_step(site)   # closure: built at once, traffic switched
			var tr := w.traffic
			var edges := site.closed_edges()
			ok(site.traffic_on and edges.all(func(e): return tr.closed_edges.has(e)), "Straße gesperrt (Abschnitte %s)" % str(edges))
			ok(not tr.zones.has(100 + site.sid), "keine Engstelle bei Vollsperrung")
			var in_future := 0
			for ag in tr.agents:
				if ag.player != null or ag.finished:
					continue
				var cur: Dictionary = ag.route[ag.pi]
				if _on_closed_road(tr, ag) or _turning_in(tr, ag) or (cur.has("key") and tr.is_closed(int(cur.key))):
					inside0[ag.id] = true   # already on the closed road, about to turn in, or with no other way
					continue
				for k in range(ag.pi + 1, ag.route.size()):
					var pc: Dictionary = ag.route[k]
					if pc.t == Agent.CONN and tr.is_closed(int(w.net.connectors[pc.conn].to)):
						in_future += 1
			ok(in_future == 0, "keine Route biegt mehr in die gesperrte Straße ein (%d)" % in_future)
			print("VOLL note %d Autos waren beim Sperren auf der Straße" % inside0.size())
			# from above, across the road, in daylight (buildings stand on the curb side)
			DebugTools.light_override(12.0)
			var dl := site.lay.lane_dir(site.lay.s_t0)
			var vw := Geo.left_of(dl)
			drv.shot("voll_02_gesperrt", site.center3() - Geo.v3(dl) * 6.0, 60.0, rad_to_deg(atan2(vw.x, vw.y)), 78.0)
			t_mark = drv.t
			step = 3
		3:
			# watch the traffic: nobody new drives onto the closed road
			var tr2 := w.traffic
			for ag in tr2.agents:
				if ag.player != null or ag.finished:
					continue
				seen_traffic += 1
				if _on_closed_road(tr2, ag) and not inside0.has(ag.id) and not intruders.has(ag.id):
					intruders[ag.id] = true
					var hist: Array = []
					for k in range(maxi(0, ag.pi - 3), ag.pi + 1):
						var pc: Dictionary = ag.route[k]
						if pc.t == Agent.CONN:
							var c: Dictionary = w.net.connectors[pc.conn]
							hist.append("conn %d→%d (%s, Auswahl %d)" % [c.from, c.to, c.turn, w.net.lane_out.get(c.from, []).size()])
						else:
							hist.append("%s %s" % [str(pc.t), str(pc.get("key", "-"))])
					print("VOLL note Eindringling %d: %s" % [ag.id, " | ".join(hist)])
			if drv.t - t_mark < 150.0:
				return
			DebugTools.light_override(-1.0)
			ok(seen_traffic > 0, "Verkehr unterwegs")
			ok(intruders.is_empty(), "kein Durchgangsverkehr fährt in die gesperrte Straße (%d)" % intruders.size())
			var stuck := 0
			for ag in tr2.agents:
				if ag.player == null and not ag.finished and tr2._on_closed(ag) and ag.wait_t > 45.0:
					stuck += 1
			ok(stuck == 0, "vor der Sperrung hängt niemand fest (%d)" % stuck)
			# company vehicles route around it, unless the trip starts or ends on the closed road
			var lay := site.lay
			var v: Vehicle = null
			for fv in w.fleet.vehicles:
				if fv.site == null and fv.carried_by == null:
					v = fv
			ok(v != null and v._avoid_edges().has(lay.key >> 4) and not v._avoid_edges(lay.key, -1).has(lay.key >> 4), "Firmenfahrzeuge meiden die gesperrte Straße")
			var from_ci := -1
			for ci in w.net.lane_in.get(lay.key, []):
				from_ci = ci
			var to_ci := -1
			for ci2 in w.net.lane_out.get(lay.key, []):
				if str(w.net.connectors[ci2].turn) != "U":
					to_ci = ci2
			if from_ci >= 0 and to_ci >= 0 and v:
				var a_key: int = w.net.connectors[from_ci].from
				var b_key: int = w.net.connectors[to_ci].to
				var plan: Array = w.router.plan(a_key, maxf(0.0, w.router.lane_len(a_key) - 5.0), b_key, minf(5.0, w.router.lane_len(b_key)), v._avoid_edges(a_key, b_key))
				var through := false
				for pc in plan:
					if pc.has("key") and site.closed_edges().has(int(pc.key) >> 4):
						through = true
				ok(not through, "Route von vor nach hinter der Sperrung führt außen herum (%d Stücke)" % plan.size())
			# the site's own excavator still gets in
			for fv2 in w.fleet.vehicles:
				if fv2.def_id == "excavator_a918" and fv2.site == null:
					site.send_vehicle(fv2)
			DebugTools.turbo(30.0)
			t_mark = drv.t
			step = 4
		4:
			if site._excavator() == null:
				if drv.t - t_mark > 3000.0:
					ok(false, "Bagger erreicht seinen Platz nicht")
					_end()
				return
			DebugTools.turbo(1.0)
			ok(true, "Bagger erreicht seinen Platz trotz Vollsperrung (%.0f s)" % (drv.t - t_mark))
			var pd: Dictionary = site.save_state().get("plan", {})
			ok(ClosurePlan.from_dict(pd).full, "Vollsperrung im Spielstand")
			drv.shot("voll_03_bagger", site.center3(), 45.0, -30.0, 48.0)
			t_mark = drv.t
			step = 5
		5:
			if not drv.shot_queue.is_empty():
				return
			for id in ["dig", "pipe", "refill", "asphalt", "demob", "teardown"]:
				if site.step_id() == id:
					DebugTools.finish_step(site)
			ok(not site.traffic_on and w.traffic.closed_edges.is_empty(), "nach dem Abbau ist die Straße wieder offen")
			_end()


## Full closure in the designer with real events where it matters.
func _design() -> void:
	var lay := site.lay
	ok(not des.plan.full and not des.full_btn.button_pressed, "anfangs keine Vollsperrung")
	des.full_btn.button_pressed = true
	ok(des.plan.full and des.info_lbl.text.contains("Vollsperrung"), "Schalter Vollsperrung")
	ok(des.mode_btns["lane"].disabled and des.lane_btn.disabled, "Werkzeug Fahrspur gesperrt")
	var ids: Array = des._checks.map(func(c): return c.id)
	ok(ids.has("voll_vorne") and not ids.has("laengs") and not ids.has("fahrweg") and not ids.has("verschwenkung"), "Prüfung für Vollsperrung %s" % str(ids))
	var tpl := _find_button(des, "Standard-Vorlage")
	ok(tpl != null, "Knopf Standard-Vorlage")
	if tpl:
		tpl.pressed.emit()
	ok(des.plan.full and int(des.plan.counts().get("z250", 0)) >= 1, "Vorlage Vollsperrung mit Z 250 (%s)" % str(des.plan.counts()))
	var req := _failed(des._checks, true)
	ok(req.is_empty(), "Vorlage erfüllt alle Pflichtpunkte %s" % str(req))
	ok(_failed(des._checks, false).is_empty(), "und alle Empfehlungen %s" % str(_failed(des._checks, false)))
	if lay.oncoming:
		ok(des._checks.any(func(c): return c.id == "voll_hinten"), "mit Gegenverkehr auch hinten gesperrt")
	# one barrier of the front row missing: the check notices the gap
	var drop := -1
	for i in des.plan.items.size():
		var it: Dictionary = des.plan.items[i]
		# one in the other lane (the pit's head fence covers the middle of the closed lane)
		var lcd := lay.lane_coords(ClosurePlan.item_center(it))
		if it.kind == "schranke" and lcd.x < lay.s_t0 and lcd.y < -lay.lw * 0.5 - 0.5 and lcd.y > ClosurePlan.road_span(lay, lcd.x).x + 0.5:
			drop = i
	ok(drop >= 0, "Schranke vorne gefunden")
	if drop >= 0:
		des.set_mode("select")
		des._sel = [drop]
		var n_before := des.plan.items.size()
		_key(KEY_DELETE)
		print("VOLL note Teile %d → %d, Prüfung vorne: %s" % [n_before, des.plan.items.size(), str(des._checks.filter(func(c): return c.id == "voll_vorne"))])
		ok(_failed(des._checks, true).has("voll_vorne"), "Lücke in der Sperrung wird gemeldet")
		_key(KEY_Z, true)
		ok(_failed(des._checks, true).is_empty(), "Strg+Z schließt sie wieder")
	_key(KEY_0)
	ok(des.kind == "z250", "Taste 0 = Z 250")
	des.set_mode("select")


func _on_closed_road(tr: TrafficSim, ag: Agent) -> bool:
	var pc: Dictionary = ag.route[ag.pi]
	return (pc.t == Agent.LANE or pc.t == Router.BLEND) and tr.closed_edges.has(int(pc.key) >> 4)


func _turning_in(tr: TrafficSim, ag: Agent) -> bool:
	var pc: Dictionary = ag.route[ag.pi]
	return pc.t == Agent.CONN and tr.closed_edges.has(int(drv.world.net.connectors[pc.conn].to) >> 4)


func _failed(checks: Array, required: bool) -> Array:
	var out: Array = []
	for c in checks:
		if not c.ok and bool(c.required) == required:
			out.append(c.id)
	return out


func _find_button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _place(jm: JobManager) -> Site:
	for c in jm._candidates.slice(0, 60):
		var g: Array = drv.world.net.lane_geo[c.key]
		var mid: Vector2 = Geo.sample(g[0], g[1], c.len * 0.5)[0]
		var n := jm.active.size()
		DebugTools.place_job_at(mid, true)
		if jm.active.size() > n:
			return jm.site_of(jm.active[jm.active.size() - 1])
	return null


func _key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		k.ctrl_pressed = ctrl
		drv.get_viewport().push_input(k, true)


func _end() -> void:
	if hud and hud.designer:
		hud.designer.close(false)
	Clock.set_speed(1)
	Engine.time_scale = 1.0
	if fails > 0:
		print("E2E FAIL vollsperrung: %d Fehler" % fails)
		drv.get_tree().quit(1)
	else:
		print("E2E OK vollsperrung")
		drv.get_tree().quit(0)
