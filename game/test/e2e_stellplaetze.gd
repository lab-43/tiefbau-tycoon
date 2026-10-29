extends RefCounted
## e2e scenario "stellplaetze" (tools/test.sh stellplaetze, #22): machine and parking spots laid in the
## closure designer with real mouse drags (excavator off the lane centre, tipper further back, pile
## towards the curb), reach check, the vehicles park exactly there, the excavator digs into the tipper
## at its new spot, the tipper is moved during the works (re-parks inside the closure), and the
## material pile lands where it was planned. Driven by e2e_driver.gd (_stellplaetze_test).

var drv: Node
var step := 0
var fails := 0
var site: Site
var hud: HUD
var des: ClosureDesigner
var t_mark := 0.0
var dug0 := 0.0
var bulk0 := 0.0
var load_target := Vector2.ZERO


func ok(cond: bool, what: String) -> void:
	print("STELL %s %s" % ["ok  " if cond else "FAIL", what])
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
			Game.select(site)
			hud._rebuild_right()
			var btn := _find_button(hud.right_body, "Absperrung planen")
			if btn:
				btn.pressed.emit()
			des = hud.designer
			ok(des != null, "Designer offen")
			if des == null:
				_end()
				return
			t_mark = drv.t
			step = 1
		1:
			# real mouse events only once the designer's controls are laid out (a frame later)
			if drv.t - t_mark < 0.5:
				return
			_design()
			drv.shot("stell_01_plan")
			t_mark = drv.t
			step = 11
		11:
			if not drv.shot_queue.is_empty() or drv.t - t_mark < 0.5:
				return
			des.accept_btn.pressed.emit()
			var lay := site.lay
			ok(absf(lay.exc_lat - 0.6) < 0.05 and site.plan.slots.has("exc"), "Plan übernommen: Bagger 0,6 m zur Seite (%.2f)" % lay.exc_lat)
			DebugTools.finish_step(site)   # closure
			DebugTools.send_fleet(site)
			DebugTools.turbo(30.0)
			t_mark = drv.t
			step = 2
		2:
			var ex := site._excavator()
			var tip := site._tipper_at_load()
			if ex == null or tip == null or not site.crew_present():
				if drv.t - t_mark > 3000.0:
					ok(false, "Fahrzeuge nicht an ihren Plätzen (%s)" % site._can_dig())
					_end()
				return
			var lay2 := site.lay
			var le := lay2.lane_coords(ex.pos2())
			ok(Vector2(le.x, le.y).distance_to(Vector2(lay2.s_exc, lay2.exc_lat)) < 0.15, "Bagger steht auf seinem Stellplatz (s %.2f/%.2f, seitlich %.2f/%.2f)" % [le.x, lay2.s_exc, le.y, lay2.exc_lat])
			var lt := lay2.lane_coords(tip.pos2())
			ok(Vector2(lt.x, lt.y).distance_to(Vector2(lay2.load_s(tip.rear_ext), lay2.load_lat)) < 0.15 and absf(lt.y - 0.3) < 0.05, "Kipper steht auf seinem Stellplatz (seitlich %.2f)" % lt.y)
			dug0 = site.terrain.remaining_dig()
			bulk0 = tip.bulk_m3()
			_shot_from_above("stell_02_plaetze")
			site.do_action("dig")
			ok(site.running, "Bagger gräbt")
			t_mark = drv.t
			step = 3
		3:
			var tip2 := site._tipper_at_load()
			if site.terrain.remaining_dig() > dug0 - 0.6 or tip2 == null or tip2.bulk_m3() < bulk0 + 0.5:
				if drv.t - t_mark > 900.0:
					ok(false, "Bagger lädt den Kipper am neuen Platz nicht (Rest %.2f, Kipper %s)" % [site.terrain.remaining_dig(), str(tip2.bulk_m3() if tip2 else -1.0)])
					_end()
				return
			ok(true, "Bagger gräbt und lädt den Kipper am neuen Platz (%.1f m³ im Kipper)" % tip2.bulk_m3())
			step = 31
		31:
			# during the works: the tipper spot 1 m further back (the plan waits for a bucket cycle under way)
			var p := site.plan.copy()
			var ld: Vector2 = p.slots.get("load", Vector2(site.lay.load_rear, site.lay.load_lat))
			p.slots["load"] = ld + Vector2(1.0, 0.0)
			site.set_plan(p, true)
			ok(site._pending_plan != null or site.rebuild, "Plan während der Arbeit geändert")
			t_mark = drv.t
			step = 4
		4:
			var tip3 := site._tipper_at_load()
			if site._pending_plan != null or site.rebuild or site._rebuilding or tip3 == null or not site._moving.is_empty():
				if drv.t - t_mark > 900.0:
					ok(false, "Kipper parkt nicht um (%s)" % site.status)
					_end()
				return
			var lay3 := site.lay
			var lt3 := lay3.lane_coords(tip3.pos2())
			load_target = Vector2(lay3.load_s(tip3.rear_ext), lay3.load_lat)
			ok(Vector2(lt3.x, lt3.y).distance_to(load_target) < 0.15, "Kipper parkt in der Absperrung um (s %.2f/%.2f)" % [lt3.x, load_target.x])
			ok(site.running and site.step_id() == "dig", "Graben geht weiter")
			dug0 = site.terrain.remaining_dig()
			t_mark = drv.t
			step = 5
		5:
			if site.terrain.remaining_dig() > dug0 - 0.3:
				if drv.t - t_mark > 600.0:
					ok(false, "Bagger gräbt nach dem Umparken nicht weiter (%s)" % site.status)
					_end()
				return
			ok(true, "Bagger gräbt nach dem Umparken weiter")
			# the rest of the trench at once; then the tipper takes the spoil away and brings sand
			DebugTools.finish_step(site)
			ok(site.step_id() == "pipe", "Schritt Rohr")
			DebugTools.finish_step(site)
			ok(site.step_id() == "refill", "Schritt Verfüllen")
			t_mark = drv.t
			step = 6
		6:
			if site.pile_m3 < 0.5:
				if drv.t - t_mark > 3000.0:
					ok(false, "kein Material auf dem Haufen (%s)" % site.status)
					_end()
				return
			var lay4 := site.lay
			var pc := Vector2(site.pile_node.global_position.x, site.pile_node.global_position.z)
			ok(absf(lay4.lane_coords(pc).y - 0.8) < 0.1, "Haufen liegt 0,8 m zum Bordstein wie geplant (%.2f)" % lay4.lane_coords(pc).y)
			# the tipper stands where it dumps onto that pile
			var tp: Vehicle = site.occupant("load")
			ok(tp != null and site.in_place.has(tp), "Kipper kippt am Haufen ab")
			if tp:
				var lt4 := lay4.lane_coords(tp.pos2())
				ok(Vector2(lt4.x, lt4.y).distance_to(Vector2(lay4.dump_s(tp.rear_ext), lay4.pile_lat)) < 0.15, "Kipper steht zum Abkippen hinter dem Haufen (seitlich %.2f)" % lt4.y)
			DebugTools.turbo(1.0)
			_shot_from_above("stell_03_haufen")
			t_mark = drv.t
			step = 7
		7:
			if not drv.shot_queue.is_empty():
				return
			DebugTools.light_override(-1.0)
			_end()


## Picture of the machine spots from above, across the road, at noon.
func _shot_from_above(name: String) -> void:
	DebugTools.light_override(12.0)
	var lay := site.lay
	var dl := lay.lane_dir(lay.s_tc)
	var vw := Geo.left_of(dl)
	drv.shot(name, Site.gw(lay.lane_pt(lay.s_tc + 3.0, 0.0), 0.0), 30.0, rad_to_deg(atan2(vw.x, vw.y)), 72.0)


## Spots laid with real mouse drags in the tool "Stellplätze".
func _design() -> void:
	var lay := site.lay
	des.snap = false
	# about 12 px per metre over the work area
	var rig: CameraRig = drv.world.camera_rig
	var c := lay.lane_pt(lay.s_t1 + 4.0, 0.0)
	rig.set_view(Vector3(c.x, 0.0, c.y), des.get_viewport_rect().size.y / (12.0 * CameraRig.TOPDOWN_SIZE), rad_to_deg(rig._t_yaw), 90.0)
	des._update_mapping()
	des.mode_btns["slots"].pressed.emit()
	ok(des.mode == "slots", "Werkzeug Stellplätze")
	var e0 := des._spot_ref("exc")
	var l0 := des._spot_ref("load")
	var p0 := des._spot_ref("pile")
	ok(des._checks.filter(func(ch): return ch.id == "reichweite" and ch.ok).size() == 1, "Standard: Bagger erreicht alles")
	# excavator 0.6 m towards the curb
	_drag(lay.lane_pt(e0.x, e0.y), lay.lane_pt(e0.x, e0.y + 0.6))
	var e1 := des._spot_ref("exc")
	ok(des.plan.slots.has("exc") and absf(e1.y - 0.6) < 0.05 and absf(e1.x - e0.x) < 0.05, "Bagger zur Seite gezogen (%.2f)" % e1.y)
	# too far back: out of reach of the trench, then undone
	_drag(lay.lane_pt(e1.x, e1.y), lay.lane_pt(e1.x + 3.0, e1.y))
	ok(_failed(des._checks).has("reichweite"), "zu weit weg: Reichweite wird gemeldet")
	_key(KEY_Z, true)
	ok(absf(des._spot_ref("exc").x - e0.x) < 0.05 and not _failed(des._checks).has("reichweite"), "Strg+Z: Bagger wieder in Reichweite")
	# the tipper 0.3 m towards the traffic: it would stand on the Leitbaken line – reported
	_drag(lay.lane_pt(l0.x, l0.y), lay.lane_pt(l0.x, l0.y - 0.3))
	ok(_failed(des._checks).has("plaetze"), "Kipper auf der Leitbakenreihe wird gemeldet")
	_key(KEY_Z, true)
	# tipper 1 m further back and 0.3 m to the curb, pile 1 m back and 0.8 m to the curb
	_drag(lay.lane_pt(l0.x, l0.y), lay.lane_pt(l0.x + 1.0, l0.y + 0.3))
	var l1 := des._spot_ref("load")
	ok(absf(l1.x - (l0.x + 1.0)) < 0.1 and absf(l1.y - 0.3) < 0.05, "Kipper verschoben (%.2f, %.2f)" % [l1.x - l0.x, l1.y])
	p0 = des._spot_ref("pile")   # follows the tipper as long as it is not placed itself
	_drag(lay.lane_pt(p0.x, p0.y), lay.lane_pt(p0.x + 1.0, 0.8))
	var p1 := des._spot_ref("pile")
	ok(absf(p1.y - 0.8) < 0.05, "Haufen zum Bordstein (%.2f)" % p1.y)
	var req := _failed(des._checks)
	ok(req.is_empty(), "Plan mit eigenen Stellplätzen erfüllt alle Pflichtpunkte %s" % str(req))
	# the crew van further away from the closure
	var v0 := des._spot_ref("van")
	_drag(lay.lane_pt(v0.x, v0.y), lay.lane_pt(v0.x - 5.0, v0.y))
	ok(absf(des._spot_ref("van").x - (v0.x - 5.0)) < 0.2, "Kolonnenbus 5 m weiter vorne")


func _failed(checks: Array) -> Array:
	var out: Array = []
	for c in checks:
		if not c.ok and bool(c.required):
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


func _vp() -> Viewport:
	return drv.get_viewport()


func _drag(p0: Vector2, p1: Vector2) -> void:
	des._update_mapping()
	var a := des._scr(p0)
	var b := des._scr(p1)
	var mv := InputEventMouseMotion.new()
	mv.position = a
	_vp().push_input(mv, true)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = a
	_vp().push_input(mb, true)
	for k in 6:
		var m2 := InputEventMouseMotion.new()
		m2.position = a.lerp(b, (k + 1) / 6.0)
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		_vp().push_input(m2, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	_vp().push_input(up, true)


func _key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		k.ctrl_pressed = ctrl
		_vp().push_input(k, true)


func _end() -> void:
	if hud and hud.designer:
		hud.designer.close(false)
	Clock.set_speed(1)
	Engine.time_scale = 1.0
	if fails > 0:
		print("E2E FAIL stellplaetze: %d Fehler" % fails)
		drv.get_tree().quit(1)
	else:
		print("E2E OK stellplaetze")
		drv.get_tree().quit(0)
