extends RefCounted
## e2e scenario "debug" (tools/test.sh debug): exercises every DebugTools action and checks the
## state it leaves behind. Driven by e2e_driver.gd (_debug_test), which owns the clock and shots.

var drv: Node            # the e2e driver (world, t, shot(), _dump())
var step := 0
var fails := 0
var site: Site
var site2: Site
var money0 := 0.0
var t_mark := 0.0
var children_after_skip := 0


func ok(cond: bool, what: String) -> void:
	print("DEBUG %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func tick(_delta: float) -> void:
	var w: World = drv.world
	var jm: JobManager = w.jobs
	match step:
		0:
			if drv.t < 1.0:
				return
			# --- time and light ---
			var day0 := Clock.day
			DebugTools.jump_to_hour(22.0)
			ok(absf(Clock.hour() - 22.0) < 0.05, "Uhrzeit 22:00 (ist %s)" % Clock.time_string())
			ok(Clock.day >= day0, "Tag läuft nicht rückwärts")
			ok(w.day_night.night > 0.5, "nachts dunkel (night=%.2f)" % w.day_night.night)
			DebugTools.light_override(12.0)
			ok(w.day_night.night < 0.05, "Licht fest auf Mittag (night=%.2f)" % w.day_night.night)
			DebugTools.light_override(-1.0)
			ok(w.day_night.night > 0.5, "Licht wieder nach Uhr")
			var d1 := Clock.day
			DebugTools.advance(1440.0)
			ok(Clock.day == d1 + 1 and absf(Clock.hour() - 22.0) < 0.05, "+1 Tag")
			DebugTools.jump_to_hour(9.0)
			DebugTools.set_season(172)
			ok(Clock.day_of_year == 172, "Jahreszeit Sommer")
			DebugTools.turbo(30.0)
			ok(is_equal_approx(Engine.time_scale, 30.0), "Tempo 30×")
			# --- money and traffic ---
			var m := Game.money()
			DebugTools.add_money(10000.0)
			ok(absf(Game.money() - m - 10000.0) < 0.01, "+10.000 €")
			DebugTools.set_traffic(0.0)
			ok(w.traffic.density_scale == 0.0, "Verkehr aus")
			DebugTools.clear_traffic()
			DebugTools.set_traffic(1.0)
			# --- contracts ---
			var n_off := jm.offers.size()
			DebugTools.new_offer()
			ok(jm.offers.size() == n_off + 1, "neue Ausschreibung")
			var n_act := jm.active.size()
			site = _place(jm)
			ok(site != null and jm.active.size() == n_act + 1, "Auftrag per Klickpunkt platziert und angenommen")
			if site == null:
				_end()
				return
			money0 = Game.money()
			# --- every step instantly, with its end state ---
			_skip_and_check(site, "scout", func(): return site.job.scouted)
			_skip_and_check(site, "closure", func(): return site.traffic_on and site._placed_count() == site.item_defs.size() and site.yellow_frac >= 1.0)
			_skip_and_check(site, "dig", func(): return site.terrain.remaining_dig() < 0.05 and site.needs.size() == 3)
			_skip_and_check(site, "pipe", func(): return site.pipe_old == null and site.pipe_new != null)
			_skip_and_check(site, "refill", func(): return site.terrain.fill_needed(-SiteTerrain.ASPHALT) < 0.01)
			_skip_and_check(site, "asphalt", func(): return site.terrain.fill_needed(0.0) < 0.01)
			if site.step_id() == "demob":   # without machines on site the game completes it by itself
				_skip_and_check(site, "demob", func(): return true)
			var pay := site.job.pay
			_skip_and_check(site, "teardown", func(): return site.retired)
			ok(site.retired and site.job.state == "done", "Abnahme nach dem Abbau")
			ok(Game.money() > money0 + pay * 0.5, "Vergütung gebucht (%s)" % Balance.money(Game.money() - money0))
			ok(not site.traffic_on, "Verkehrsführung aufgehoben")
			# --- second site: skip while the crew is working, then everything ---
			site2 = _place(jm)
			ok(site2 != null, "zweiter Auftrag platziert")
			if site2 == null:
				_end()
				return
			DebugTools.finish_step(site2)   # scout
			DebugTools.send_fleet(site2)
			site2.auto_continue = true
			drv.shot("debug_site2", site2.center3(), 70.0)
			t_mark = drv.t
			step = 1
		1:
			# drive in at 30x until the crew has placed a few closure items, then skip the rest
			if site2.step_id() == "closure" and site2.running and site2._placed_count() >= 2:
				var placed := site2._placed_count()
				DebugTools.finish_step(site2)
				ok(site2.step_id() == "dig" and site2._placed_count() == site2.item_defs.size(),
					"Absperrung mitten im Aufbau übersprungen (%d Teile standen schon)" % placed)
				children_after_skip = site2.get_child_count()
				t_mark = drv.t
				step = 2
			elif site2.phase > 1:
				print("DEBUG note Absperrung war schon fertig – Überspringen mitten im Aufbau nicht geprüft")
				children_after_skip = site2.get_child_count()
				t_mark = drv.t
				step = 2
			elif drv.t - t_mark > 1800.0:
				ok(false, "Absperrung wurde nicht begonnen (Schritt %s)" % site2.step_id())
				_end()
		2:
			# let the simulation run a bit: interrupted workers must not place extra items
			if drv.t - t_mark < 20.0:
				return
			# interrupted workers must not place extra items afterwards
			ok(site2._placed_count() == site2.item_defs.size() and site2.get_child_count() <= children_after_skip,
				"keine zusätzlichen Absperrteile (%d → %d Knoten)" % [children_after_skip, site2.get_child_count()])
			ok(not site2.workers.any(func(wk): return wk.carry != null), "Kolonne trägt nichts mehr")
			# a vehicle on its way or working: put it back to the HQ at once
			for v in w.fleet.vehicles:
				if v.def_id == "truck_tipper" and v.carried_by == null:
					DebugTools.teleport_to_hq(v)
					ok(v.at_hq() and v.site == null and v.state == "parked", "Kipper in die Zentrale gesetzt")
					break
			var save: Dictionary = Game.save_data()
			ok(save.get("world", {}).has("jobs"), "Spielstand nach dem Überspringen speicherbar")
			drv.get_parent().toggle_debug()
			Game.select(site2)
			drv.shot("debug_panel", site2.center3(), 60.0, -40.0, 45.0)
			t_mark = drv.t
			step = 3
		3:
			if not drv.shot_queue.is_empty() or drv.t - t_mark < 1.0:
				return
			DebugTools.finish_all(site2)
			ok(site2.retired, "Bis zur Abnahme")
			_click_place(w, jm)
			_end()


## The panel's "Auftrag platzieren" with a real click: button, world tool, screen point of a street.
func _click_place(w: World, jm: JobManager) -> void:
	var panel: DebugPanel = drv.get_parent()._debug
	panel._place_btn.button_pressed = true
	ok(w.tool is PlaceJobTool, "Platzier-Modus an")
	var n := jm.active.size()
	for c in jm._candidates.slice(40, 80):
		var g: Array = w.net.lane_geo[c.key]
		var mid: Vector2 = Geo.sample(g[0], g[1], c.len * 0.5)[0]
		w.camera_rig.set_view(Vector3(mid.x, 0, mid.y), 120.0)
		var screen := w.camera_rig.camera.unproject_position(Vector3(mid.x, 0, mid.y))
		w.tool.on_left_click(screen)
		if jm.active.size() > n or w.tool == null:
			break
	ok(jm.active.size() == n + 1, "Auftrag per Mausklick platziert")
	ok(w.tool == null and not panel._place_btn.button_pressed, "Platzier-Modus danach aus")


func _place(jm: JobManager) -> Site:
	# click points: the middle of a few candidate streets (like a player clicking on the road)
	for c in jm._candidates.slice(0, 40):
		var g: Array = drv.world.net.lane_geo[c.key]
		var mid: Vector2 = Geo.sample(g[0], g[1], c.len * 0.5)[0]
		var n := jm.active.size()
		DebugTools.place_job_at(mid, true)
		if jm.active.size() > n:
			return jm.site_of(jm.active[jm.active.size() - 1])
	return null


func _skip_and_check(s: Site, id: String, check: Callable) -> void:
	if s.retired or s.step_id() != id:
		ok(false, "Schritt %s erwartet, ist %s" % [id, "fertig" if s.retired else s.step_id()])
		return
	var ph := s.phase
	DebugTools.finish_step(s)
	ok((s.retired or s.phase > ph) and check.call(), "Schritt %s übersprungen" % id)


func _end() -> void:
	Clock.set_speed(1)
	if fails > 0:
		print("E2E FAIL debug: %d Fehler" % fails)
		drv.get_tree().quit(1)
	else:
		print("E2E OK debug")
		drv.get_tree().quit(0)
