extends RefCounted
## e2e scenario "umbau" (tools/test.sh umbau, #21): the closure is changed while the excavator digs.
## The plan waits for the bucket cycle under way, then the work pauses (no new cycle, nothing dug),
## the crew builds the change, and the digging goes on by itself. Also: the action in the site panel,
## blocked actions while paused, save data. Driven by e2e_driver.gd (_umbau_test).

var drv: Node
var step := 0
var fails := 0
var site: Site
var hud: HUD
var des: ClosureDesigner
var t_mark := 0.0
var n_items := 0
var dug_at_pause := -1.0
var cycles_in_pause := 0
var was_busy := false
var saw_pending := false


func ok(cond: bool, what: String) -> void:
	print("UMBAU %s %s" % ["ok  " if cond else "FAIL", what])
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
			ok(site.can_edit_plan() == "", "Plan im Schritt Absperrung änderbar")
			DebugTools.finish_step(site)   # closure (standard, at once)
			ok(site.step_id() == "dig", "Schritt Graben ausheben")
			DebugTools.send_fleet(site)
			DebugTools.turbo(30.0)
			t_mark = drv.t
			step = 1
		1:
			# wait for crew, excavator and tipper, then dig
			if site._can_dig() != "" or not site.crew_present():
				if drv.t - t_mark > 3000.0:
					ok(false, "Fahrzeuge nicht an der Baustelle (%s)" % site._can_dig())
					_end()
				return
			site.do_action("dig")
			ok(site.running, "Bagger gräbt")
			t_mark = drv.t
			step = 2
		2:
			var ex := site._excavator()
			if ex == null or ex.rig == null or not ex.rig.busy:
				if drv.t - t_mark > 600.0:
					ok(false, "Bagger beginnt keinen Arbeitsgang")
					_end()
				return
			DebugTools.turbo(1.0)
			# change the closure from the site panel while a bucket cycle runs
			var acts: Array = site.actions()
			var pa: Array = acts.filter(func(a): return a.id == "plan")
			ok(pa.size() == 1 and pa[0].enabled, "„Absperrung ändern“ während der Arbeit")
			Game.select(site)
			hud._rebuild_right()
			var btn := _find_button(hud.right_body, "Absperrung ändern")
			ok(btn != null and not btn.disabled, "Knopf im Baustellenfenster")
			if btn:
				btn.pressed.emit()
			des = hud.designer
			ok(des != null and des.accept_btn.text == "Übernehmen und umbauen", "Designer offen, Knopf „Übernehmen und umbauen“")
			if des == null:
				_end()
				return
			# three cones at the curb ahead of the closure
			var lay := site.lay
			for k in 3:
				var s := lay.s0 - 6.0 - 2.0 * k
				des.plan.items.append(ClosurePlan.make_item("cone", lay.lane_pt(s, lay.lw * 0.5 + 0.6), 0.0))
			des._changed()
			n_items = des.plan.items.size()
			des.accept_btn.pressed.emit()
			ok(hud.designer == null, "Designer zu")
			saw_pending = site._pending_plan != null
			ok(saw_pending, "der laufende Arbeitsgang wird erst fertig (Plan wartet)")
			ok(site.work_paused() and site.can_edit_plan() != "", "Arbeit pausiert, Plan gesperrt bis zum Umbau")
			var blocked: Array = site.actions().filter(func(a): return a.id == "dig")
			ok(blocked.size() == 1 and not blocked[0].enabled, "Arbeitsschritt gesperrt")
			var sd := site.save_state()
			ok(not (sd.get("plan_pending", {}) as Dictionary).is_empty(), "wartender Plan im Spielstand")
			t_mark = drv.t
			step = 3
		3:
			var ex2 := site._excavator()
			if site._pending_plan != null:
				if drv.t - t_mark > 120.0:
					ok(false, "Plan wird nach dem Arbeitsgang nicht übernommen")
					_end()
				return
			if dug_at_pause < 0.0:
				dug_at_pause = site.terrain.remaining_dig()
				was_busy = ex2.rig.busy
				ok(site.item_defs.size() == n_items and site.rebuild, "Plan übernommen, Umbau steht an (%d Teile)" % site.item_defs.size())
				ok(not was_busy, "kein Arbeitsgang mehr, als der Plan übernommen wurde")
			if ex2.rig.busy and not was_busy:
				cycles_in_pause += 1
			was_busy = ex2.rig.busy
			if site.rebuild or site._rebuilding:
				if drv.t - t_mark > 900.0:
					ok(false, "Umbau wird nicht fertig (%s)" % site.status)
					_end()
				return
			ok(cycles_in_pause == 0, "während des Umbaus kein Baggerspiel (%d)" % cycles_in_pause)
			ok(absf(site.terrain.remaining_dig() - dug_at_pause) < 0.001, "während des Umbaus nichts ausgehoben")
			var placed := 0
			for n in site.item_nodes:
				if n != null:
					placed += 1
			ok(placed == site.item_defs.size(), "neue Teile aufgestellt (%d/%d)" % [placed, site.item_defs.size()])
			ok(site.running and site.step_id() == "dig", "Schritt läuft weiter")
			t_mark = drv.t
			step = 4
		4:
			if site.terrain.remaining_dig() > dug_at_pause - 0.05:
				if drv.t - t_mark > 300.0:
					ok(false, "Bagger gräbt nach dem Umbau nicht weiter (%s)" % site.status)
					_end()
				return
			ok(true, "Bagger gräbt nach dem Umbau von selbst weiter")
			ok(not site.work_paused() and site.can_edit_plan() == "", "Plan wieder änderbar")
			var sd2 := site.save_state()
			ok(not bool(sd2.get("rebuild", true)), "kein Umbau mehr im Spielstand")
			_end()


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


func _end() -> void:
	if hud and hud.designer:
		hud.designer.close(false)
	Clock.set_speed(1)
	Engine.time_scale = 1.0
	if fails > 0:
		print("E2E FAIL umbau: %d Fehler" % fails)
		drv.get_tree().quit(1)
	else:
		print("E2E OK umbau")
		drv.get_tree().quit(0)
