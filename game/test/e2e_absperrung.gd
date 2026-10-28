extends RefCounted
## e2e scenario "absperrung" (tools/test.sh absperrung, #9): the closure designer with real mouse and
## key events (plan view, chains, curve, select, delete, undo), a player plan that the crew builds
## (incl. moving the crew van ahead of a longer taper), traffic geometry from the plan, save data,
## teardown by the crew, and a plan change after a partly built standard closure (orphan items).
## Driven by e2e_driver.gd (_absperrung_test), which owns the clock and the screenshots.

var drv: Node
var step := 0
var fails := 0
var site: Site
var site2: Site
var hud: HUD
var des: ClosureDesigner
var t_mark := 0.0
var def_ext := {}
var speed_before := 0
var placed_before := 0


func ok(cond: bool, what: String) -> void:
	print("ABSP %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func tick(_delta: float) -> void:
	var w: World = drv.world
	var jm: JobManager = w.jobs
	match step:
		0:
			if drv.t < 1.0:
				return
			hud = drv.get_parent().hud
			site = _place(jm)
			ok(site != null, "Auftrag platziert")
			if site == null:
				_end()
				return
			DebugTools.finish_step(site)   # scout
			ok(site.step_id() == "closure", "Schritt Absperrung")
			var acts := site.actions().map(func(a): return a.id)
			ok(acts.has("plan") and acts.has("closure"), "Aktionen planen + Standard (%s)" % str(acts))
			def_ext = site.lay.default_extent()
			_send(w, site, ["van_crew"])
			DebugTools.turbo(30.0)
			t_mark = drv.t
			step = 1
		1:
			if not site.crew_present():
				if drv.t - t_mark > 2400.0:
					ok(false, "Kolonnenbus kommt nicht an")
					_end()
				return
			DebugTools.turbo(1.0)
			speed_before = Clock.speed_index
			# --- open the designer like the player: button in the site panel ---
			Game.select(site)
			hud._rebuild_right()
			var btn := _find_button(hud.right_body, "Absperrung planen")
			ok(btn != null and not btn.disabled, "Knopf „Absperrung planen“ im Baustellenfenster")
			if btn:
				btn.pressed.emit()
			des = hud.designer
			ok(des != null, "Designer offen")
			if des == null:
				_end()
				return
			ok(w.camera_rig.topdown and w.camera_rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Draufsicht (orthografisch)")
			ok(Clock.is_paused(), "Spiel pausiert")
			ok(not hud.right.visible and not hud.top.visible, "übriges HUD ausgeblendet")
			ok(des._trees.size() > 0, "Bäume ausgeblendet (%d Gruppen)" % des._trees.size())
			ok(des.plan.items.size() == site.item_defs.size() and not des.plan.custom, "startet mit der Standard-Vorlage (%d Teile)" % des.plan.items.size())
			var req_fail := _failed(des._checks, true)
			ok(req_fail.is_empty(), "Standard-Vorlage erfüllt alle Pflichtpunkte %s" % str(req_fail))
			print("ABSP note Empfehlungen offen bei der Vorlage: %s" % str(_failed(des._checks, false)))
			des._update_mapping()
			drv.shot("absp_01_vorlage")
			t_mark = drv.t
			step = 2
		2:
			if not drv.shot_queue.is_empty() or drv.t - t_mark < 0.5:
				return
			_design()
			drv.shot("absp_02_eigener_plan")
			t_mark = drv.t
			step = 3
		3:
			if not drv.shot_queue.is_empty() or drv.t - t_mark < 0.5:
				return
			# hover preview of a curve chain for the screenshot is done; accept with the button
			var lay := site.lay
			var n_items := des.plan.items.size()
			des.accept_btn.pressed.emit()
			ok(hud.designer == null, "Designer nach „Übernehmen“ zu")
			ok(not w.camera_rig.topdown and w.camera_rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Kamera wieder perspektivisch")
			ok(Clock.speed_index == speed_before, "Spieltempo wiederhergestellt")
			ok(hud.top.visible, "HUD wieder sichtbar")
			ok(site.plan.custom and site.plan_confirmed and site.item_defs.size() == n_items, "Plan an der Baustelle (%d Teile)" % site.item_defs.size())
			ok(lay.s_det0 < float(def_ext.det0) - 5.0, "Verschwenkung beginnt früher (%.1f statt %.1f)" % [lay.s_det0, def_ext.det0])
			ok(lay.s_van < float(def_ext.van) - 5.0, "Kolonnenbus-Platz vor die Verschwenkung verlegt (%.1f statt %.1f)" % [lay.s_van, def_ext.van])
			ok(site.crew_van.state == "driving" or site.crew_van.pos2().distance_to(lay.lane_pt(lay.s_van, SiteLayout.CURB)) < 1.0, "Kolonnenbus parkt um (%s)" % site.crew_van.state)
			# order: signs first, then from upstream to downstream
			var first_non_sign := -1
			var order_ok := true
			for i in site.item_defs.size():
				var sg := ClosurePlan.is_sign(site.item_defs[i].kind)
				if not sg and first_non_sign < 0:
					first_non_sign = i
				if sg and first_non_sign >= 0:
					order_ok = false
			ok(order_ok, "Aufbaureihenfolge: Schilder zuerst")
			DebugTools.turbo(30.0)
			t_mark = drv.t
			step = 4
		4:
			if site.phase < 2:
				if drv.t - t_mark > 4000.0:
					ok(false, "Absperrung nicht fertig (%d/%d, %s)" % [site._placed_count(), site.item_defs.size(), site.status])
					_end()
				return
			var lay2 := site.lay
			var pos_ok := true
			for i in site.item_defs.size():
				var n: Node3D = site.item_nodes[i]
				var d: Dictionary = site.item_defs[i]
				if n == null or Vector2(n.global_position.x, n.global_position.z).distance_to(d.pos) > 0.05 \
						or absf(angle_difference(n.global_rotation.y, float(d.yaw))) > 0.02:
					pos_ok = false
					print("ABSP note Teil %d %s steht falsch" % [i, d.kind])
			ok(pos_ok, "alle %d Teile stehen genau wie geplant" % site.item_defs.size())
			ok(site.yellow_lines.size() == 1 and site.yellow_frac >= 1.0, "gelbe Markierung komplett")
			ok(site.traffic_on, "Verkehr verschwenkt")
			ok(site.crew_van.pos2().distance_to(lay2.lane_pt(lay2.s_van, SiteLayout.CURB)) < 1.0, "Kolonnenbus am neuen Platz")
			var sd := site.save_state()
			var pd: Dictionary = sd.get("plan", {})
			ok(not pd.is_empty() and sd.get("plan_ok", false), "Plan im Spielstand")
			var p2 := ClosurePlan.from_dict(pd)
			var same := p2.items.size() == site.plan.items.size() and p2.lines.size() == site.plan.lines.size()
			for i in mini(p2.items.size(), site.plan.items.size()):
				if p2.items[i].kind != site.plan.items[i].kind or (p2.items[i].pos as Vector2).distance_to(site.plan.items[i].pos) > 0.001:
					same = false
			ok(same, "Plan aus dem Spielstand gleich")
			ok(not Game.save_data().is_empty(), "Spielstand speicherbar")
			# pictures in daylight, looking from the curb side and from behind along the lane
			DebugTools.light_override(12.0)
			var d2 := lay2.lane_dir(lay2.s_t0)
			var view := Geo.left_of(d2) - d2 * 0.8   # from the traffic side (buildings stand on the curb side)
			drv.shot("absp_03_aufgebaut", site.center3() - Geo.v3(d2) * 8.0, 42.0, rad_to_deg(atan2(view.x, view.y)), 48.0)
			t_mark = drv.t
			step = 41
		41:
			# one picture per step: shot() takes the picture 8 frames later
			if not drv.shot_queue.is_empty():
				return
			var lay4 := site.lay
			var d4 := lay4.lane_dir(lay4.s_t0)
			var view4 := Geo.left_of(d4)
			drv.shot("absp_04_von_oben", site.center3() - Geo.v3(d4) * 10.0, 70.0, rad_to_deg(atan2(view4.x, view4.y)), 80.0)
			step = 5
		5:
			if not drv.shot_queue.is_empty():
				return
			DebugTools.light_override(-1.0)
			# jump to the teardown and let the crew take the plan down again
			for id in ["dig", "pipe", "refill", "asphalt", "demob"]:
				if site.step_id() == id:
					DebugTools.finish_step(site)
			ok(site.step_id() == "teardown", "Schritt Absperrung abbauen (%s)" % site.step_id())
			ok(site.can_edit_plan() != "", "Plan nach dem Aufbau gesperrt")
			site.do_action("teardown")
			ok(site.running, "Kolonne baut ab")
			t_mark = drv.t
			step = 6
		6:
			if not site.retired and site.step_id() == "teardown":
				if drv.t - t_mark > 4000.0:
					ok(false, "Abbau nicht fertig (%d stehen noch)" % site._placed_count())
					_end()
				return
			ok(not site.traffic_on, "Verkehrsführung nach dem Abbau aufgehoben")
			ok(site.retired, "Auftrag abgeschlossen")
			t_mark = drv.t
			step = 61
		61:
			# the finished job sends the van home (deferred): give it a moment before sending it on
			if drv.t - t_mark < 5.0:
				return
			# --- second site: standard closure partly built, then a changed plan ---
			site2 = _place(jm)
			ok(site2 != null, "zweiter Auftrag platziert")
			if site2 == null:
				_end()
				return
			DebugTools.finish_step(site2)
			_send(w, site2, ["van_crew"])
			t_mark = drv.t
			step = 7
		7:
			if not site2.crew_present():
				if drv.t - t_mark > 2400.0:
					ok(false, "Kolonnenbus kommt an Baustelle 2 nicht an")
					_end()
				return
			if not site2.running and site2._placed_count() == 0:
				site2.do_action("closure")
				ok(site2.running and site2.plan_confirmed and not site2.plan.custom, "Standard-Absperrung gestartet")
			if site2._placed_count() < 6:
				return
			placed_before = site2._placed_count()
			DebugTools._cancel_activity(site2)
			placed_before = site2._placed_count()
			ok(site2.can_edit_plan() == "", "Plan nach Unterbrechung wieder änderbar")
			# changed plan: drop two standing items, move one, add a cone
			var p := site2.plan.copy()
			var removed := 0
			var standing: Array = []
			for i in site2.item_defs.size():
				if site2.item_nodes[i] != null:
					standing.append(i)
			var drop: Array = [standing[1], standing[2]]
			var keep: Array = []
			for i in p.items.size():
				if not drop.has(i):
					keep.append(p.items[i])
				else:
					removed += 1
			p.items = keep
			var lay3 := site2.lay
			p.items.append(ClosurePlan.make_item("cone", lay3.lane_pt(lay3.s_van + 4.0, SiteLayout.CURB + 0.6), 0.0))
			p.custom = true
			p.sort_for_build(lay3)
			site2.set_plan(p, true)
			ok(site2._orphans.size() == removed, "%d aufgestellte Teile nicht mehr im Plan → werden eingesammelt" % site2._orphans.size())
			ok(site2._placed_count() == placed_before - removed, "übrige aufgestellte Teile behalten (%d)" % site2._placed_count())
			t_mark = drv.t
			step = 8
		8:
			if site2.phase < 2:
				if drv.t - t_mark > 4000.0:
					ok(false, "Absperrung 2 nicht fertig (%s)" % site2.status)
					_end()
				return
			ok(site2._orphans.is_empty(), "eingesammelt")
			ok(site2._placed_count() == site2.item_defs.size(), "geänderter Plan komplett aufgebaut")
			var nodes := 0
			for ch in site2.get_children():
				if ch.has_meta("kind") and str(ch.get_meta("kind")) in ClosurePlan.KINDS:
					nodes += 1
			ok(nodes == site2.item_defs.size(), "keine übrig gebliebenen Teile (%d Knoten, %d geplant)" % [nodes, site2.item_defs.size()])
			_end()


## The player's own plan, entered with real mouse and key events in the designer.
func _design() -> void:
	var lay := site.lay
	des.snap = false
	_key(KEY_X)   # nothing bound: must not break anything
	des.clear_all()
	ok(des.plan.is_empty(), "Leeren")
	ok(_failed(des._checks, true).size() >= 3, "leerer Plan: Pflichtpunkte offen %s" % str(_failed(des._checks, true)))
	var lw := lay.lw
	var hw := lay.W * 0.5 + 0.35
	# zoom out (mouse wheel over the map) so that the advance warning sign fits on screen
	var ctr := des._scr(lay.lane_pt(lay.s_c0, 0.0))
	for k in 3:
		var wh := InputEventMouseButton.new()
		wh.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wh.pressed = true
		wh.position = ctr
		_vp().push_input(wh, true)
	var rig: CameraRig = drv.world.camera_rig
	rig.set_view(rig._t_target, rig._t_distance, rad_to_deg(rig._t_yaw), 90.0)
	ok(rig.topdown and rig.camera.size > 0.0, "Zoom in der Draufsicht (Breite %.0f m)" % (rig.camera.size * des.get_viewport_rect().size.x / des.get_viewport_rect().size.y))
	# signs (single, number keys pick the kind)
	_key(KEY_6)
	ok(des.kind == "z123" and des.mode == "single", "Taste 6 = Z 123, einzeln")
	_click(lay.lane_pt(lay.s_c0 - 60.0, lw * 0.5 + 0.8))
	ok(int(des.plan.counts().get("z123", 0)) == 1, "Z 123 per Klick gesetzt")
	if lay.oncoming:
		_key(KEY_7)
		_click(lay.lane_pt(lay.s_c0 - 50.0, lw * 0.5 + 0.8))
		_key(KEY_8)
		_click(lay.lane_pt(lay.s_c1 + 30.0, -lay.shift - lay.lw2 * 0.5 - 0.8))
	# Leitbaken: taper, along the traffic side, tail taper – one chain of three straight segments
	_key(KEY_1)
	des.mode_btns["line"].pressed.emit()
	ok(des.mode == "line", "Werkzeug Gerade")
	_click(lay.lane_pt(lay.s_c0 - 22.0, 0.95))
	_click(lay.lane_pt(lay.s_c0 - 1.0, -lw * 0.5 + 0.3))
	_click(lay.lane_pt((lay.s_c0 + lay.s_c1) * 0.5, -lw * 0.5 + 0.3))
	_click(lay.lane_pt(lay.s_c1 + 0.5, -lw * 0.5 + 0.3))
	_click(lay.lane_pt(lay.s_c1 + 9.0, 0.95))
	_right_click(lay.lane_pt(lay.s_c1 + 9.0, 0.95))
	ok(des._chain.is_empty(), "Rechtsklick beendet die Kette")
	var n_bake := int(des.plan.counts().get("bake", 0))
	ok(n_bake >= 10, "Leitbaken als Kette (%d)" % n_bake)
	# cross barrier: Absperrschranken across the lane
	_key(KEY_3)
	_click(lay.lane_pt(lay.s_c0 + 0.5, -lw * 0.5 + 0.3))
	_click(lay.lane_pt(lay.s_c0 + 0.5, lw * 0.5 - 0.05))
	_key(KEY_ESCAPE)
	ok(int(des.plan.counts().get("schranke", 0)) == 2, "2 Absperrschranken quer (%d)" % int(des.plan.counts().get("schranke", 0)))
	# fall protection on both sides of the trench
	_key(KEY_4)
	for side in [-1.0, 1.0]:
		_click(lay.lane_pt(lay.s_t0 - 0.3, hw * side))
		_click(lay.lane_pt(lay.s_t1 + 0.3, hw * side))
		_key(KEY_ESCAPE)
	ok(int(des.plan.counts().get("fence", 0)) >= 6, "Absperrgitter am Graben (%d)" % int(des.plan.counts().get("fence", 0)))
	# yellow marking: one polyline, three segments
	_key(KEY_5)
	ok(des.kind == "line" and des.mode == "line", "gelbe Markierung zeichnet als Linie")
	_click(lay.lane_pt(lay.s_c0 - 22.0, lw * 0.5 - 0.1))
	_click(lay.lane_pt(lay.s_c0, -lw * 0.5 + 0.1))
	_click(lay.lane_pt(lay.s_c1 + 0.5, -lw * 0.5 + 0.1))
	_click(lay.lane_pt(lay.s_c1 + 9.0, lw * 0.5 - 0.1))
	_key(KEY_ENTER)
	var ylen := Geo.polyline_length(des.plan.lines[0]) if des.plan.lines.size() == 1 else 0.0
	ok(des.plan.lines.size() == 1 and ylen > lay.s_c1 + 9.0 - (lay.s_c0 - 22.0) - 1.0, "eine gelbe Linie aus 3 Abschnitten (%.1f m)" % ylen)
	# cones on a curve along the curb ahead of the van (spacing 1 m)
	_key(KEY_2)
	des.mode_btns["curve"].pressed.emit()
	des._step_spacing(-1)
	ok(is_equal_approx(float(des.spacing.cone), 1.5), "Abstand Hütchen 1,5 m")
	var ca := lay.lane_pt(lay.s_c1 + 14.0, lw * 0.5 + 0.6)
	var cb := lay.lane_pt(lay.s_c1 + 22.0, lw * 0.5 + 0.6)
	_click(ca)
	_click(cb)
	_click(lay.lane_pt(lay.s_c1 + 18.0, lw * 0.5 + 1.8))
	_key(KEY_ESCAPE)
	var n_cone := int(des.plan.counts().get("cone", 0))
	ok(n_cone >= 6, "Hütchen als Kurve (%d)" % n_cone)
	var bent := false
	for it in des.plan.items:
		if it.kind == "cone" and lay.lane_coords(it.pos).y > lw * 0.5 + 1.0:
			bent = true
	ok(bent, "Kurve ist gebogen")
	# checks
	var req := _failed(des._checks, true)
	ok(req.is_empty(), "eigener Plan erfüllt alle Pflichtpunkte %s" % str(req))
	for c in des._checks:
		if not c.ok:
			print("ABSP note %s: %s" % [c.id, c.hint])
	print("ABSP note offene Empfehlungen: %s" % str(_failed(des._checks, false)))
	# undo / redo with keys
	var n0 := des.plan.items.size()
	_key(KEY_Z, true)
	ok(des.plan.items.size() < n0, "Strg+Z nimmt die Hütchen zurück")
	_key(KEY_Y, true)
	ok(des.plan.items.size() == n0, "Strg+Y stellt sie wieder her")
	# select one item by click, delete it, undo
	des.mode_btns["select"].pressed.emit()
	var sign_p := lay.lane_pt(lay.s_c0 - 60.0, lw * 0.5 + 0.8)
	_click(sign_p)
	ok(des._sel.size() == 1 and des.plan.items[des._sel[0]].kind == "z123", "Z 123 per Klick ausgewählt")
	_key(KEY_DELETE)
	ok(des.plan.items.size() == n0 - 1 and int(des.plan.counts().get("z123", 0)) == 0, "Entf löscht")
	_key(KEY_Z, true)
	ok(des.plan.items.size() == n0, "rückgängig")
	# drag an item: move the sign 3 m along the lane, then back with undo
	var before: Vector2 = Vector2.INF
	for it in des.plan.items:
		if it.kind == "z123":
			before = it.pos
	_drag(sign_p, sign_p + lay.lane_dir(lay.s_c0 - 60.0) * 3.0)
	var after: Vector2 = Vector2.INF
	for it in des.plan.items:
		if it.kind == "z123":
			after = it.pos
	ok(after.distance_to(before) > 2.5 and after.distance_to(before) < 3.5, "Z 123 verschoben (%.2f m)" % after.distance_to(before))
	_key(KEY_Z, true)
	# box select the trench fences
	var a := des._scr(lay.lane_pt(lay.s_t0 - 1.0, -hw - 3.0))
	var b := des._scr(lay.lane_pt(lay.s_t1 + 1.0, hw + 2.5))
	_drag_screen(a, b)
	var fences := 0
	for i in des._sel:
		if des.plan.items[i].kind == "fence":
			fences += 1
	ok(fences >= 6, "Rahmen wählt die Gitter (%d von %d)" % [fences, des._sel.size()])
	_key(KEY_ESCAPE)
	ok(des._sel.is_empty(), "Esc hebt die Auswahl auf")
	# snapping: 0.3 m next to the traffic-side lane edge lands on it
	des.snap = true
	des.set_mode("single")
	var near := lay.lane_pt(lay.s_c0 - 30.0, -lw * 0.5 + 0.3)
	var sp := des._snap_point(near)
	ok(absf(lay.lane_coords(sp).y + lw * 0.5) < 0.02, "rastet an der Fahrstreifenkante ein")
	des.snap = false
	# preview for the screenshot: a curve chain of cones under the mouse
	des.set_kind("bake")


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


func _send(w: World, s: Site, defs: Array) -> void:
	for v in w.fleet.vehicles:
		if v.def_id in defs and v.carried_by == null:
			s.send_vehicle(v)


func _place(jm: JobManager) -> Site:
	for c in jm._candidates.slice(0, 60):
		var g: Array = drv.world.net.lane_geo[c.key]
		var mid: Vector2 = Geo.sample(g[0], g[1], c.len * 0.5)[0]
		var n := jm.active.size()
		DebugTools.place_job_at(mid, true)
		if jm.active.size() > n:
			return jm.site_of(jm.active[jm.active.size() - 1])
	return null


# --- input helpers: real events through the viewport (GUI first, then the designer) ---------

func _vp() -> Viewport:
	return drv.get_viewport()


func _click(p: Vector2) -> void:
	des._update_mapping()
	var s := des._scr(p)
	var mv := InputEventMouseMotion.new()
	mv.position = s
	_vp().push_input(mv, true)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = s
		_vp().push_input(mb, true)


func _right_click(p: Vector2) -> void:
	des._update_mapping()
	var s := des._scr(p)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		mb.pressed = pressed
		mb.position = s
		_vp().push_input(mb, true)


func _drag(p0: Vector2, p1: Vector2) -> void:
	des._update_mapping()
	_drag_screen(des._scr(p0), des._scr(p1))


func _drag_screen(a: Vector2, b: Vector2) -> void:
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
	if drv.world.camera_rig.topdown and hud and hud.designer:
		hud.designer.close(false)
	Clock.set_speed(1)
	Engine.time_scale = 1.0
	if fails > 0:
		print("E2E FAIL absperrung: %d Fehler" % fails)
		drv.get_tree().quit(1)
	else:
		print("E2E OK absperrung")
		drv.get_tree().quit(0)
