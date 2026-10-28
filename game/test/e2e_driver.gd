extends Node
## End-to-end test driver. Started by main.gd with --e2e=<scenario> [--shots=dir] [--speed=n] [--timeout=s].
## Scenarios: smoke (load + screenshot), job (complete one contract with the start fleet).

var scenario := "smoke"
var shots_dir := ""
var speed := 3
var timeout := 1800.0
var t := 0.0
var real_t := 0.0
var world: World
var site: Site
var phase_seen := -1
var log_t := 0.0
var started := false
var step := 0
var shot_queue: Array = []
var near := 0.0
var traffic := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--e2e="):
			scenario = a.substr(6)
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--speed="):
			speed = int(a.substr(8))
		elif a.begins_with("--timeout="):
			timeout = float(a.substr(10))
		elif a.begins_with("--near="):
			near = float(a.substr(7))
		elif a.begins_with("--traffic="):
			traffic = float(a.substr(10))
	Events.world_ready.connect(_on_ready)
	if scenario == "load":
		get_parent().continue_game.call_deferred()
	if scenario == "repro":
		_repro_start.call_deferred()
	Events.notify.connect(func(txt, kind): print("[%7.1f] NOTE %s: %s" % [t, kind, txt]))


func _on_ready() -> void:
	world = Game.world
	started = true
	print("E2E world ready: %d vehicles, %d offers, %d job candidates" % [world.fleet.vehicles.size(), world.jobs.offers.size(), world.jobs._candidates.size()])
	Clock.set_speed(speed)
	world.traffic.density_scale = traffic
	if near > 0.0:
		var jm := world.jobs
		jm._candidates = jm._candidates.filter(func(c): return c.dist < near)
		jm.offers.clear()
		var j := jm._make_offer()
		if j:
			jm.offers.append(j)
		print("E2E near offer: ", j.location() if j else "none", " candidates ", jm._candidates.size())


func shot(name: String, focus: Vector3 = Vector3.INF, dist := 0.0, yaw := -35.0, pitch := 48.0) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	if focus != Vector3.INF:
		world.camera_rig.set_view(focus, dist, yaw, pitch)
	shot_queue.append([name, 8, _shot_state()])


## Camera goal + selection when a shot is queued; the picture is taken 8 frames later (e2e-shot-verzoegert).
func _shot_state() -> Array:
	if world == null or world.camera_rig == null:
		return []
	var rig := world.camera_rig
	# while following a vehicle the goal moves every frame: compare the followed node instead
	return [rig.follow if rig.follow else rig._t_target, rig._t_distance, Game.selected]


func _process(delta: float) -> void:
	real_t += delta / maxf(0.01, Engine.time_scale)
	t += delta
	if not shot_queue.is_empty():
		shot_queue[0][1] -= 1
		if shot_queue[0][1] <= 0:
			var s: Array = shot_queue.pop_front()
			if s.size() > 2 and s[2] != _shot_state():
				print("SHOT WARNUNG %s: Kamera oder Auswahl nach shot() geändert – das Bild zeigt den neuen Stand (Lektion e2e-shot-verzoegert)" % s[0])
			var img := get_viewport().get_texture().get_image()
			var path := shots_dir.path_join(s[0] + ".png")
			img.save_png(path)
			print("SHOT ", path)
	if scenario == "menu":
		_menu()
		return
	if scenario == "loadshot":
		_loadshot()
		return
	if scenario == "retry":
		_retry_test()
		return
	if not started:
		return
	if real_t > timeout:
		print("E2E TIMEOUT at sim t=%.0f" % t)
		_dump()
		get_tree().quit(2)
		return
	match scenario:
		"repro":
			_repro(delta)
		"smoke":
			_smoke()
		"job":
			_job(delta)
		"lowbed":
			_lowbed(delta)
		"showcase":
			_showcase(delta)
		"issue":
			_issue_test()
		"save":
			_save_test(delta)
		"load":
			_load_test(delta)
		"leuchten":
			_leuchten()
		"verkehrslichter":
			_verkehrslichter_test(delta)
		"debug":
			_debug_test(delta)
		"markierungen":
			_markierungen(delta)
		"absperrung":
			_absperrung_test(delta)


func _smoke() -> void:
	if step == 0 and t > 3.0:
		step = 1
		var hud = get_parent().hud
		print("HUD size ", hud.size, " top ", hud.top.size, " left ", hud.left.size, " ui_root ", get_parent().ui_root.size, " vp ", get_viewport().get_visible_rect())
		var lc: Vector2 = world.hq_info.lot_center
		shot("smoke_hq", Vector3(lc.x, 0, lc.y), 95.0, -30.0, 50.0)
	elif step == 1 and t > 4.0 and shot_queue.is_empty():
		_dump()
		print("E2E OK smoke")
		get_tree().quit(0)


func _job(delta: float) -> void:
	var jm := world.jobs
	match step:
		0:
			if t < 1.0:
				return
			if jm.offers.is_empty():
				print("E2E FAIL: no offers")
				get_tree().quit(1)
				return
			var j: Job = jm.offers[0]
			for o in jm.offers:
				if o.distance_m < j.distance_m:
					j = o
			print("E2E accept job %d at %s (%.0f m away), %s" % [j.id, j.location(), j.distance_m, j.title()])
			jm.accept(j)
			site = jm.site_of(j)
			site.auto_continue = true
			for v in world.fleet.vehicles:
				if v.def_id in ["van_crew", "excavator_a918", "truck_tipper", "truck_flatbed"]:
					site.send_vehicle(v)
			shot("job_00_start", site.center3(), 140.0)
			step = 1
		1:
			if site == null or not is_instance_valid(site) or site.retired:
				print("E2E site finished at t=%.0f (day %d %s)" % [t, Clock.day, Clock.time_string()])
				_dump()
				step = 2
				return
			if site.phase != phase_seen:
				phase_seen = site.phase
				print("[%7.1f] PHASE %d %s | %s" % [t, site.phase, site.step_id(), site.status])
				shot("job_%02d_%s" % [site.phase, site.step_id()], site.center3(), 55.0, -40.0, 42.0)
			log_t += delta
			if log_t > 30.0:
				log_t = 0.0
				_dump()
		2:
			if shot_queue.is_empty():
				print("E2E OK money=%s" % Balance.money(Game.money()))
				get_tree().quit(0)


func _dump() -> void:
	var s := "[%7.1f] day %d %s money %s traffic %d" % [t, Clock.day, Clock.time_string(), Balance.money(Game.money()), world.traffic.traffic_count()]
	print(s)
	if site and is_instance_valid(site):
		print("    site phase=%s running=%s sub=%s prog=%.2f status=%s pile=%.1f %s" % [site.step_id(), site.running, site.sub, site.progress, site.status, site.pile_m3, site.pile_mat])
	for v in world.fleet.vehicles:
		var ag := ""
		if v.agent:
			var pc: Dictionary = v.agent.route[v.agent.pi]
			ag = "pi=%d/%d t=%d s=%.1f/%.1f v=%.1f rem=%.1f why=%s" % [v.agent.pi, v.agent.route.size(), pc.t, v.agent.s, pc.s1, v.agent.v, v.agent.remaining_route(), v.agent.reason]
		print("    %-14s %-8s %-30s pos=(%.0f,%.0f) spot=%s load=%s %s" % [v.vname, v.state, v.status_text, v.position.x, v.position.z, site.spot_of.get(v, "-") if site and is_instance_valid(site) else "-", v.cargo_text(), ag])


## Lowbed: load the excavator at HQ, deliver it to a site (unload + reverse into the slot), pick it up again.
var lb: Vehicle
var ex: Vehicle
func _lowbed(_delta: float) -> void:
	var jm := world.jobs
	match step:
		0:
			if t < 1.0:
				return
			for v in world.fleet.vehicles:
				if v.def_id == "tractor_lowbed":
					lb = v
				elif v.def_id == "excavator_a918":
					ex = v
			var j: Job = jm.offers[0]
			for o in jm.offers:
				if o.distance_m < j.distance_m:
					j = o
			jm.accept(j)
			site = jm.site_of(j)
			print("E2E lowbed test at ", j.location())
			lb.load_machine(ex)
			step = 1
		1:
			if lb.cargo.machine == ex and ex.carried_by == lb and lb.state == "parked":
				print("[%7.1f] loaded at HQ" % t)
				site.send_vehicle(lb)
				for v in world.fleet.vehicles:
					if v.def_id == "van_crew":
						site.send_vehicle(v)
				site.auto_continue = true
				step = 2
		2:
			if site.in_place.has(ex) and site.spot_of.get(ex, "") == "exc":
				print("[%7.1f] excavator in slot, lowbed state=%s status=%s" % [t, lb.state, lb.status_text])
				shot("lowbed_exc_in_slot", site.center3(), 60.0)
				site.auto_continue = false
				step = 3
			elif site.phase != phase_seen:
				phase_seen = site.phase
				print("[%7.1f] PHASE %d %s" % [t, site.phase, site.step_id()])
		3:
			# fast-forward: jump the site to demob and fetch the excavator with the lowbed
			if lb.state == "parked" and lb.at_hq():
				site.phase = 6
				site.running = false
				site.send_vehicle(lb)
				step = 4
		4:
			if ex.carried_by == lb:
				print("[%7.1f] picked up from site" % t)
				step = 5
		5:
			if lb.at_hq() and lb.state == "parked":
				print("E2E OK lowbed round trip")
				_dump()
				get_tree().quit(0)
	log_t += _delta
	if log_t > 30.0:
		log_t = 0.0
		_dump()


## Showcase: build a site state directly (no waiting) and take screenshots by day and night.
func _place_at(v: Vehicle, spot: String, s: float, lat := 0.0) -> void:
	var p := site.lay.pose(s, lat)
	v.place(Vector3(p.pos.x, 0, p.pos.y), p.yaw)
	if not site.vehicles.has(v):
		site.vehicles.append(v)
	v.site = site
	v._free_slot()
	site._arrived(v, spot)


func _showcase(_delta: float) -> void:
	var jm := world.jobs
	match step:
		0:
			if t < 1.0:
				return
			var j: Job = jm.offers[0]
			for o in jm.offers:
				if o.distance_m < j.distance_m:
					j = o
			jm.accept(j)
			site = jm.site_of(j)
			Clock.set_speed(1)
			Clock.minutes = 10.5 * 60.0
			var lay := site.lay
			for v in world.fleet.vehicles:
				match v.def_id:
					"van_crew":
						var vp := lay.van_pose()
						v.place(Vector3(vp.pos.x, 0, vp.pos.y), vp.yaw)
						site.vehicles.append(v)
						v.site = site
						v._free_slot()
						site.crew_van = v
						site._arrived(v, "van")
					"excavator_a918":
						_place_at(v, "exc", lay.s_exc)
					"truck_tipper":
						_place_at(v, "load", lay.load_s(v.rear_ext))
					"truck_flatbed":
						_place_at(v, "stage", lay.stage_s(0) + v.rear_ext, SiteLayout.CURB)
			site.phase = 2
			site._build_spray()
			for i in site.item_defs.size():
				var d: Dictionary = site.item_defs[i]
				var node := SiteProps.item(d.kind, d.phase)
				site.add_child(node)
				node.global_transform = Transform3D(Basis(Vector3.UP, d.yaw), Vector3(d.pos.x, 0.05, d.pos.y))
				site.item_nodes[i] = node
			site.yellow_frac = 1.0
			site._update_yellow()
			site._traffic_activate()
			site.terrain.set_hole(jm.pit_slot_of(site), true)
			# pre-dig 60 %
			for k in 14:
				var b := site.terrain.next_bite(site._turret_u())
				if b.is_empty():
					break
				site.terrain.dig_strip(b, 0.5)
			site.do_action("dig")
			step = 1
		1:
			if t > 25.0:
				shot("show_01_dig_day", site.center3(), 34.0, -55.0, 38.0)
				step = 2
		2:
			if shot_queue.is_empty() and t > 27.0:
				Game.select(site)
				get_parent().hud.open_left("")
				shot("show_02_site_panel", site.center3(), 70.0, -20.0, 55.0)
				step = 3
		3:
			if shot_queue.is_empty() and t > 29.0:
				shot("show_03_trench", site.center3(), 13.0, -80.0, 62.0)
				step = 31
		31:
			if shot_queue.is_empty() and t > 31.0:
				for v in world.fleet.vehicles:
					if v.def_id == "excavator_a918":
						Game.select(v)
				shot("show_05_vehicle_panel", site.center3() + Geo.v3(site.lay.lane_dir(site.lay.s0)) * -14.0, 22.0, -110.0, 30.0)
				step = 4
		4:
			if shot_queue.is_empty() and t > 33.0:
				Game.select(null)
				Clock.minutes = 22.3 * 60.0
				step = 5
		5:
			if t > 42.0:
				shot("show_04_night", site.center3(), 60.0, -40.0, 45.0)
				step = 6
		6:
			if shot_queue.is_empty() and t > 44.0:
				_dump()
				get_tree().quit(0)


func _menu() -> void:
	match step:
		0:
			if real_t > 2.0:
				shot("menu_01_main")
				step = 1
		1:
			if shot_queue.is_empty():
				get_parent().show_setup()
				step = 2
				real_t = 0.0
		2:
			if real_t > 3.0:
				shot("menu_02_setup")
				step = 3
		3:
			if shot_queue.is_empty():
				get_tree().quit(0)


## Save test: play until the excavator digs, then save and quit. Load test: continue and check the state.
func _save_test(delta: float) -> void:
	if step < 2:
		_job(delta)
		if site and is_instance_valid(site) and site.step_id() == "dig" and site.running and site.progress > 0.2:
			step = 10
		return
	if step == 10:
		print("SAVE at phase ", site.step_id(), " progress ", site.progress)
		_dump()
		Game.save_game()
		step = 11
	elif step == 11:
		print("E2E OK save")
		get_tree().quit(0)


var printed_after := false
func _load_test(_delta: float) -> void:
	match step:
		0:
			var jm := world.jobs
			if jm.active.is_empty():
				print("E2E FAIL: no active job after load")
				get_tree().quit(1)
				return
			site = jm.site_of(jm.active[0])
			print("LOADED site phase=%s placed=%d vehicles=%d remaining_dig=%.2f" % [site.step_id(), site._placed_count(), site.vehicles.size(), site.terrain.remaining_dig()])
			_dump()
			step = 1
		_:
			if t > 240.0 and not printed_after:
				printed_after = true
				print("AFTER 240s: phase=%s running=%s prog=%.2f status=%s" % [site.step_id(), site.running, site.progress, site.status])
				_dump()
			# then play the loaded job to the end like the job scenario
			_job(_delta)


## Screenshots of the loading screen while the map loads (use with the mock Overpass server).
var _ls_next := 2.0
var _ls_n := 0
func _loadshot() -> void:
	if started:
		if real_t > _ls_next:
			print("E2E OK loadshot")
			get_tree().quit(0)
		return
	if real_t > _ls_next and shots_dir != "":
		_ls_next = real_t + 2.0
		var img := get_viewport().get_texture().get_image()
		var path := shots_dir.path_join("load_%02d.png" % _ls_n)
		img.save_png(path)
		print("SHOT ", path)
		_ls_n += 1


## Loading fails (no server), then "Erneut versuchen" is pressed; the shell starts a server meanwhile.
var _retried := false
func _retry_test() -> void:
	if started:
		print("E2E OK retry: world ready after retry=%s" % _retried)
		get_tree().quit(0 if _retried else 1)
		return
	var ls = get_parent()._screen
	if not _retried and ls is LoadingScreen and ls._failed:
		for b in ls.error_box.find_children("*", "Button", true, false):
			if b.text == "Erneut versuchen":
				print("E2E pressing retry at %.0f s" % real_t)
				_retried = true
				b.pressed.emit()
				return


## Issue reporting round trip: report with pin, agent question, player answer, browser view.
var _iss_folder := ""
func _issue_test() -> void:
	var main = get_parent()
	match step:
		0:
			if t > 3.0:
				var lc: Vector2 = world.hq_info.lot_center
				world.camera_rig.set_view(Vector3(lc.x, 0, lc.y), 120.0, -35.0, 48.0)
				for v in world.fleet.vehicles:
					if v.def_id == "truck_tipper":
						Game.select(v)
				Events.report_issue.emit()
				step = 1
		1:
			if t > 5.0:
				var r = main._reporter
				r._title.text = "Kipper bleibt in der Zentrale stehen"
				r._text.text = "Test: der Kipper fährt nicht los.\nErwartet: Er fährt zur Baustelle."
				var lc: Vector2 = world.hq_info.lot_center
				r.pins.append({"pos": Vector3(lc.x, 0, lc.y), "label": "Zentrale"})
				r._refresh_pins()
				shot("issue_01_reporter")
				step = 2
		2:
			if t > 7.0 and shot_queue.is_empty():
				main._reporter._submit()
				step = 3
		3:
			if t > 8.0:
				var items := IssueStore.list_all()
				_iss_folder = items[0].folder
				var it := IssueStore.load_issue(_iss_folder)
				print("ISSUE #%d %s files=%s status=%s area=%s pins=%d" % [it.id, it.title, it.files, it.status, it.area, it.pins.size()])
				IssueStore.append(_iss_folder, {"by": "agent:test-session", "kind": "question", "status": "rueckfrage", "text": "Welcher Kipper genau – Kipper 1?"})
				Events.open_issues.emit()
				step = 4
		4:
			if t > 10.0:
				main._issues._show_detail(_iss_folder)
				shot("issue_02_browser")
				step = 5
		5:
			if t > 12.0 and shot_queue.is_empty():
				main._issues._reply.text = "Ja, Kipper 1."
				main._issues._answer(_iss_folder, "rueckfrage", "")
				var it := IssueStore.load_issue(_iss_folder)
				for e in it.thread:
					print("  THREAD %s %s %s %s" % [e.by, e.kind, e.get("status", ""), e.get("text", "")])
				print("E2E OK issue status=%s" % it.status)
				get_tree().quit(0)


## Reproduce an issue: --e2e=repro --issue=<issue folder> [--watch=<s>] [--out=<dir>] [--shots=<dir>]
## Loads the attached save, restores the reported camera, takes pictures of the camera view and of
## every pin, then lets the game run and dumps the state every 10 s into <out>/repro.log.
var _iss := {}
var _iss_dir := ""
var _out := ""
var _watch := 60.0
var _rlog: FileAccess
func _repro_start() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--issue="):
			_iss_dir = a.substr(8)
		elif a.begins_with("--watch="):
			_watch = float(a.substr(8))
		elif a.begins_with("--out="):
			_out = a.substr(6)
	_iss = IssueStore.load_issue(_iss_dir)
	if _iss.is_empty() or not FileAccess.file_exists(_iss_dir.path_join("spielstand.sav")):
		print("E2E FAIL repro: issue or spielstand.sav missing in ", _iss_dir)
		get_tree().quit(4)
		return
	if _out == "":
		_out = _iss_dir.path_join("repro")
	DirAccess.make_dir_recursive_absolute(_out)
	if shots_dir == "":
		shots_dir = _out
	var mid: String = _iss.get("map", {}).get("id", "")
	var mdir := Game.MAPS_DIR.path_join(mid)
	if not FileAccess.file_exists(mdir.path_join("baked_v%d.bin" % MapBuilder.BAKE_VERSION)) and not mid.begins_with("dev_"):
		print("E2E HINWEIS: gebackene Karte fehlt in %s – sie wird neu aufbereitet (Geofabrik/Overpass nötig)." % ProjectSettings.globalize_path(mdir))
	_rlog = FileAccess.open(_out.path_join("repro.log"), FileAccess.WRITE)
	print("E2E repro #%d: %s" % [int(_iss.get("id", 0)), _iss.get("title")])
	var ok: bool = await get_parent().load_save_file(_iss_dir.path_join("spielstand.sav"))
	if not ok:
		print("E2E FAIL repro: save could not be read")
		get_tree().quit(4)


func _rdump(tag: String) -> void:
	var d := IssueStore.state_dump()
	var txt := "=== %s · t=%.0f ===\n%s\n" % [tag, t, d.text]
	print(txt)
	if _rlog:
		_rlog.store_string(txt)
		_rlog.flush()


func _repro(_delta: float) -> void:
	match step:
		0:
			if t > 2.0:
				var cam: Dictionary = _iss.get("camera", {})
				if not cam.is_empty():
					var tg: Array = cam.target
					world.camera_rig.set_view(Vector3(tg[0], tg[1], tg[2]), cam.distance, cam.yaw_deg, cam.pitch_deg)
					shot("repro_kamera")
				_rdump("Start")
				step = 1
		1:
			if shot_queue.is_empty():
				# pins one after another (camera move + picture)
				var pins: Array = _iss.get("pins", [])
				if _pin_i < pins.size():
					var p: Dictionary = pins[_pin_i]
					world.camera_rig.set_view(Vector3(p.x, 0.0, p.z), 70.0, -35.0, 45.0)
					shot("repro_stelle_%d" % (_pin_i + 1))
					_pin_i += 1
				else:
					Clock.set_speed(speed)
					step = 2
					log_t = 0.0
		2:
			log_t += _delta
			if log_t > 10.0:
				log_t = 0.0
				_rdump("nach %.0f s" % t)
			if t > _watch + 4.0:
				_rdump("Ende")
				print("E2E OK repro – Ergebnisse in ", ProjectSettings.globalize_path(_out))
				get_tree().quit(0)
var _pin_i := 0


## Beacons (#1): every start-fleet vehicle has beacons that sit on its body (not floating), the flash
## patterns have 2 / 3 flashes per cycle, and with --shots close-ups of each vehicle with beacons on.
var _li := 0
var _lfail := 0
var _lt := 0.0
func _leuchten() -> void:
	var vs: Array = world.fleet.vehicles
	match step:
		0:
			if t < 1.5:
				return
			for n in [2, 3]:
				var edges := 0
				var was := false
				for ms in int(Vehicle.FLASH_CYCLE * 1000.0):
					var on := Vehicle.flash_lit(ms * 0.001, n)
					if on and not was:
						edges += 1
					was = on
				print("FLASH n=%d flashes per cycle=%d" % [n, edges])
				if edges != n:
					_lfail += 1
			for v in vs:
				var veh: Vehicle = v
				veh.light_mode.beacon = "on"
				var nodes := veh.beacon_nodes()
				var want := 2 if veh.def_id == "van_crew" else 1
				if nodes.size() < want:
					print("BEACON FAIL %s: %d beacons, expected >= %d" % [veh.def_id, nodes.size(), want])
					_lfail += 1
				var inv := veh.model.global_transform.affine_inverse()
				for nd in nodes:
					var p: Vector3 = inv * (nd as Node3D).global_position
					var sy := VehicleModels.surface_y(veh.model, p.x, p.z, p.y + 0.02, [nd])
					var gap := p.y - sy
					var ok := sy > -INF and absf(gap) <= 0.06
					print("BEACON %s %-4s %s at (%.2f, %.2f, %.2f) surface %.2f gap %.3f" % [veh.def_id, "ok" if ok else "FAIL", nd.name, p.x, p.y, p.z, sy, gap])
					if not ok:
						_lfail += 1
			Clock.set_speed(1)
			step = 1
		1:
			if not shot_queue.is_empty():
				return
			# same view twice: beacons frozen lit, then frozen dark
			if _li < vs.size() * 2:
				var veh: Vehicle = vs[_li / 2]
				veh.beacon_freeze = 1 if _li % 2 == 0 else 0
				var yaw := rad_to_deg(veh.rotation.y + PI) + 40.0
				shot("leuchten_%02d_%s_%s" % [_li, veh.def_id, "an" if _li % 2 == 0 else "aus"], veh.global_position + Vector3(0, 1.6, 0), 9.0 if veh.def_id == "van_crew" else 13.0, yaw, 30.0)
				_li += 1
				return
			for v in vs:
				if v.def_id == "van_crew":
					Game.select(v)
					shot("leuchten_panel", v.global_position + Vector3(0, 1.6, 0), 12.0, rad_to_deg(v.rotation.y + PI) + 40.0, 30.0)
			step = 3
		3:
			if not shot_queue.is_empty():
				return
			Game.select(null)
			Clock.minutes = 22.0 * 60.0
			_lt = t
			_li = 0
			step = 4
		4:
			if not shot_queue.is_empty() or t < _lt + 5.0:
				return
			if _li < 2:
				for v in vs:
					if v.def_id == "van_crew":
						v.beacon_freeze = 1 if _li == 0 else 0
						shot("leuchten_nacht_%s" % ("an" if _li == 0 else "aus"), v.global_position + Vector3(0, 1.6, 0), 9.0, rad_to_deg(v.rotation.y + PI) + 40.0, 30.0)
				_li += 1
				return
			step = 2
		2:
			if not shot_queue.is_empty():
				return
			for v in vs:
				v.beacon_freeze = -1
			if _lfail > 0:
				print("E2E FAIL leuchten: %d Fehler" % _lfail)
				get_tree().quit(1)
				return
			print("E2E OK leuchten")
			get_tree().quit(0)


## Debug menu actions (test/e2e_debug.gd).
var _dbg: RefCounted
func _debug_test(delta: float) -> void:
	if _dbg == null:
		_dbg = load("res://test/e2e_debug.gd").new()
		_dbg.drv = self
	_dbg.tick(delta)


## Screen markers and view bar (#7): the checks live in test/e2e_markierungen.gd.
var _mk: RefCounted
func _markierungen(delta: float) -> void:
	if _mk == null:
		_mk = load("res://test/e2e_markierungen.gd").new(self)
	_mk.tick(delta)


## Traffic car lights (#2), logic in test/e2e_verkehrslichter.gd.
var _vl: RefCounted
func _verkehrslichter_test(delta: float) -> void:
	if _vl == null:
		_vl = load("res://test/e2e_verkehrslichter.gd").new()
		_vl.drv = self
	_vl.tick(delta)


## Closure designer and player plans (test/e2e_absperrung.gd, #9).
var _absp: RefCounted
func _absperrung_test(delta: float) -> void:
	if _absp == null:
		_absp = load("res://test/e2e_absperrung.gd").new()
		_absp.drv = self
	_absp.tick(delta)
