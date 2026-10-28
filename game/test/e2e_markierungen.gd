extends RefCounted
## e2e scenario "markierungen" (#7): screen markers for HQ, offers, sites and vehicles, edge markers
## with arrow when off screen, click (fly there / select), right click (send the selected vehicle),
## buildings and marker toggles. Called by e2e_driver.gd. Run: tools/test.sh markierungen
## (screenshots: E2E_SHOTS=<dir> tools/gd.sh run -- --autostart --fixture=utrecht --e2e=markierungen --shots=<dir>).

var d                       # e2e driver (Node)
var step := 0
var wait_until := 0.0
var fails := 0
var saved_view := {}
var lc := Vector3.ZERO
var site: Site
var van: Vehicle
var _t0 := -1.0


func _init(driver) -> void:
	d = driver


func check(ok: bool, what: String) -> void:
	print("MARK %-4s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	wait_until = d.real_t + s


func find(wm: WorldMarkers, kind: String, obj: Object = null):
	for i in wm.used:
		var m = wm.markers[i]
		if m.visible and m.kind == kind and (obj == null or m.obj == obj):
			return m
	return null


## Real input through the viewport (GUI routing, camera, World), not a direct _gui_input call.
func send_button(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	if button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		ev.factor = 1.0
	d.get_viewport().push_input(ev, true)


func send_motion(pos: Vector2, rel: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = mask
	d.get_viewport().push_input(ev, true)


func click(m, button: MouseButton) -> void:
	var p: Vector2 = m.get_global_rect().get_center()
	send_button(p, button, true)
	send_button(p, button, false)


func tick(_delta: float) -> void:
	# watchdog first: a script error further down only aborts this call and would repeat every frame
	# (Lektion testskript-skriptfehler), the scenario needs well under a minute
	if _t0 < 0.0:
		_t0 = d.real_t
	if d.real_t - _t0 > 300.0:
		print("E2E FAIL markierungen: hängt in Schritt %d" % step)
		d.get_tree().quit(1)
		return
	if d.real_t < wait_until or not d.shot_queue.is_empty():
		return
	var w: World = d.world
	var wm: WorldMarkers = d.get_parent().hud.markers
	var jm := w.jobs
	match step:
		0:
			if d.t < 1.5:
				return
			WorldMarkers.persist = false
			saved_view = WorldMarkers.view.duplicate()
			for k in WorldMarkers.view:
				wm.set_view(k, true)
			Clock.set_speed(0)
			var c2: Vector2 = w.hq_info.lot_center
			lc = Vector3(c2.x, 0, c2.y)
			w.camera_rig.set_view(lc, 900.0, -35.0, 55.0)
			_wait(0.6)
			step = 1
		1:
			var hq = find(wm, "hq")
			check(hq != null and not hq.edge, "Zentrale im Bild markiert")
			if hq:
				check(hq.members.size() == w.fleet.vehicles.size(), "alle %d Fahrzeuge an der Zentrale gezählt (%d)" % [w.fleet.vehicles.size(), hq.members.size()])
			check(find(wm, "vehicle") == null, "keine einzelnen Fahrzeugsymbole über der Zentrale")
			var n_off := 0
			for i in wm.used:
				var m = wm.markers[i]
				if m.kind == "offer":
					n_off += 1 + m.extra
				check(wm.get_viewport_rect().encloses(m.get_rect()), "%s-Markierung ganz im Bild" % m.kind)
			check(n_off == jm.offers.size(), "jede Ausschreibung markiert (%d von %d)" % [n_off, jm.offers.size()])
			d.shot("markierungen_1_weit")
			step = 2
		2:
			# far away: the HQ leaves the screen
			w.camera_rig.set_view(lc + Vector3(2600.0, 0, 1400.0), 300.0, -35.0, 50.0)
			_wait(0.6)
			step = 3
		3:
			var hq = find(wm, "hq")
			check(hq != null and hq.edge, "Zentrale außerhalb: Randmarkierung")
			if hq:
				check(wm.free_rect.grow(2.0).encloses(hq.get_rect()), "Randmarkierung im freien Bereich")
				var cam := w.camera_rig.camera
				if not cam.is_position_behind(lc):
					var want: Vector2 = (cam.unproject_position(lc) - wm.free_rect.get_center()).normalized()
					check(want.dot(hq.dir) > 0.95, "Pfeil zeigt zur Zentrale (%.2f)" % want.dot(hq.dir))
				check(hq.text.ends_with("km"), "Entfernung angezeigt: %s" % hq.text)
			d.shot("markierungen_2_rand")
			step = 4
		4:
			var hq = find(wm, "hq")
			check(hq != null, "Randmarkierung noch da")
			if hq:
				# wheel over a marker still zooms (markers only take the left click)
				var dist0: float = w.camera_rig._t_distance
				send_button(hq.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, true)
				check(w.camera_rig._t_distance < dist0 - 1.0, "Mausrad über einer Markierung zoomt (%.0f -> %.0f m)" % [dist0, w.camera_rig._t_distance])
				click(hq, MOUSE_BUTTON_LEFT)
				check(Vector2(w.camera_rig._t_target.x, w.camera_rig._t_target.z).distance_to(Vector2(lc.x, lc.z)) < 1.0, "Klick fliegt zur Zentrale")
			# a site and a selected vehicle get their own markers
			var j: Job = jm.offers[0]
			jm.accept(j)
			site = jm.site_of(j)
			for v in w.fleet.vehicles:
				if v.def_id == "van_crew":
					van = v
			Game.select(van)
			w.camera_rig.set_view(lc.lerp(site.center3(), 0.5), 1400.0, -35.0, 60.0)
			_wait(0.6)
			step = 5
		5:
			var sm = find(wm, "site", site)
			check(sm != null, "Baustelle markiert")
			var vm = find(wm, "vehicle", van)
			check(vm != null and vm.selected, "gewähltes Fahrzeug einzeln markiert")
			d.shot("markierungen_3_baustelle")
			step = 6
		6:
			var sm2 = find(wm, "site", site)
			check(sm2 != null, "Baustelle noch markiert")
			if sm2:
				var p: Vector2 = sm2.get_global_rect().get_center()
				# right drag that starts on a marker pans the map and sends nobody
				var t0: Vector3 = w.camera_rig._t_target
				send_button(p, MOUSE_BUTTON_RIGHT, true)
				for k in 5:
					send_motion(p + Vector2(30.0 * (k + 1), 0), Vector2(30, 0), MOUSE_BUTTON_MASK_RIGHT)
				send_button(p + Vector2(150, 0), MOUSE_BUTTON_RIGHT, false)
				check(w.camera_rig._t_target.distance_to(t0) > 5.0, "Rechts ziehen auf einer Markierung verschiebt die Karte")
				check(van.site == null, "… und schickt kein Fahrzeug los")
				# a short right click on the site marker sends the selected van
				w.camera_rig.set_view(t0, w.camera_rig._t_distance, rad_to_deg(w.camera_rig._t_yaw), rad_to_deg(w.camera_rig._t_pitch))
				step = 61
				return
			step = 62
		61:
			var sm3 = find(wm, "site", site)
			if sm3:
				click(sm3, MOUSE_BUTTON_RIGHT)
				check(van.site == site, "Rechtsklick auf die Markierung schickt %s zur Baustelle" % van.vname)
			# a world tool (debug: place contract) gets the left click, the marker does not
			var sm4 = find(wm, "site", site)
			if sm4:
				Game.select(null)
				w.tool = RefCounted.new()
				var tgt0: Vector3 = w.camera_rig._t_target
				click(sm4, MOUSE_BUTTON_LEFT)
				check(Game.selected != site and w.camera_rig._t_target.distance_to(tgt0) < 0.01, "Mit aktivem Werkzeug nimmt die Markierung keinen Klick")
				w.tool = null
			step = 62
		62:
			Game.select(null)
			_wait(0.3)
			step = 7
		7:
			wm.set_view("buildings", false)
			var n := 0
			var shown := 0
			for c in w.city.get_children():
				var b := c.get_node_or_null("building") as Node3D
				if b:
					n += 1
					if b.visible:
						shown += 1
			check(n > 0 and shown == 0, "Gebäude aus: %d von %d Ebenen sichtbar" % [shown, n])
			d.shot("markierungen_4_ohne_gebaeude", lc, 420.0, -35.0, 45.0)
			step = 8
		8:
			wm.set_view("buildings", true)
			var hidden := 0
			for c in w.city.get_children():
				var b := c.get_node_or_null("building") as Node3D
				if b and not b.visible:
					hidden += 1
			check(hidden == 0, "Gebäude wieder an")
			wm.set_view("markers", false)
			_wait(0.3)
			step = 9
		9:
			check(wm.used == 0, "Markierungen aus: keine sichtbar")
			wm.set_view("markers", true)
			_wait(0.3)
			step = 10
		10:
			check(wm.used > 0, "Markierungen wieder an")
			for k in saved_view:
				WorldMarkers.view[k] = saved_view[k]
			if fails > 0:
				print("E2E FAIL markierungen: %d Fehler" % fails)
				d.get_tree().quit(1)
				return
			print("E2E OK markierungen")
			d.get_tree().quit(0)
