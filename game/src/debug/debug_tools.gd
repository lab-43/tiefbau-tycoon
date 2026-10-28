class_name DebugTools
extends RefCounted
## Debug actions for testing the game quickly: time and light, contracts, instant work steps,
## vehicles, money and traffic. Used by the debug panel (F3) and by the e2e scenario "debug".
## Every action returns a short German message (also shown as a notification).

const SEASONS := {"Winter": 15, "Frühling": 105, "Sommer": 172, "Herbst": 288}


static func _world() -> World:
	return Game.world


static func _say(msg: String, ok := true) -> String:
	if ok:
		Events.info("Debug: " + msg)
	else:
		Events.warn("Debug: " + msg)
	return msg


# ------------------------------------------------------------------------------------------
# Time and light
# ------------------------------------------------------------------------------------------

## Advances the game clock (forward only, so deadlines and offers stay consistent).
static func advance(minutes: float) -> String:
	Clock.minutes += maxf(0.0, minutes)
	while Clock.minutes >= 1440.0:
		Clock.minutes -= 1440.0
		Clock.day += 1
		Clock.day_of_year = (Clock.day_of_year % 365) + 1
	Events.time_tick.emit(Clock.day, Clock.minutes)
	_refresh_light()
	return _say("Zeit: Tag %d, %s" % [Clock.day, Clock.time_string()])


## Jumps forward to the next time the clock shows hour h (0..24).
static func jump_to_hour(h: float) -> String:
	var target := fposmod(h, 24.0) * 60.0
	var delta := target - Clock.minutes
	if delta <= 0.5:
		delta += 1440.0
	return advance(delta)


## Lights the scene as at hour h while the clock keeps running (-1 = off).
static func light_override(h: float) -> String:
	var w := _world()
	if w == null or w.day_night == null:
		return "Keine Welt"
	w.day_night.override_hour = h
	_refresh_light()
	return _say("Licht folgt wieder der Uhr" if h < 0.0 else "Licht fest auf %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)])


static func set_season(doy: int) -> String:
	Clock.day_of_year = clampi(doy, 1, 365)
	_refresh_light()
	return _say("Jahreszeit: %s" % Clock.date_string())


## Game speed beyond 10x (Engine.time_scale). Pressing 1/2/3/Space returns to normal speeds.
static func turbo(scale: float) -> String:
	Clock.set_speed(3)
	Engine.time_scale = scale
	return _say("Tempo %d×" % int(scale))


static func _refresh_light() -> void:
	var w := _world()
	if w and w.day_night:
		w.day_night.update_now()


# ------------------------------------------------------------------------------------------
# Contracts
# ------------------------------------------------------------------------------------------

static func new_offer() -> String:
	var w := _world()
	if w == null:
		return "Keine Welt"
	var j: Job = w.jobs.debug_new_offer()
	if j == null:
		return _say("Keine passende Straße für eine neue Ausschreibung gefunden", false)
	return _say("Neue Ausschreibung: %s, %s" % [j.title(), j.location()])


## Places a contract with its trench at world point p (x, z). accept: take it on immediately.
static func place_job_at(p: Vector2, accept := true) -> String:
	return try_place_job_at(p, accept).msg


## Like place_job_at, returns {ok: bool, msg: String}.
static func try_place_job_at(p: Vector2, accept := true) -> Dictionary:
	var w := _world()
	if w == null:
		return {"ok": false, "msg": "Keine Welt"}
	var r: Dictionary = w.jobs.offer_at(p)
	if r.has("error"):
		return {"ok": false, "msg": _say(r.error, false)}
	var j: Job = r.job
	if accept:
		if not w.jobs.accept(j):
			return {"ok": false, "msg": _say("Ausschreibung angelegt, Annehmen ging nicht (zu viele Baustellen?)", false)}
		var s: Site = w.jobs.site_of(j)
		if s:
			Game.select(s)
		return {"ok": true, "msg": _say("Auftrag %d platziert und angenommen: %s" % [j.id, j.location()])}
	return {"ok": true, "msg": _say("Ausschreibung %d platziert: %s" % [j.id, j.location()])}


# ------------------------------------------------------------------------------------------
# Construction sites
# ------------------------------------------------------------------------------------------

## The selected site, otherwise the first active one.
static func current_site() -> Site:
	if Game.selected is Site and is_instance_valid(Game.selected) and not (Game.selected as Site).retired:
		return Game.selected
	var w := _world()
	if w == null:
		return null
	for s in w.jobs.all_sites():
		if is_instance_valid(s) and not s.retired:
			return s
	return null


## Completes the current work step of site s instantly, with the end state the real work would leave.
static func finish_step(s: Site) -> String:
	if s == null or not is_instance_valid(s) or s.retired:
		return _say("Keine aktive Baustelle", false)
	var step := s.step_id()
	var title: String = Site.STEPS[s.phase].title if s.phase < Site.STEPS.size() else step
	var was_running := s.running
	_cancel_activity(s)
	match step:
		"scout":
			s._scouted()
		"closure":
			_instant_closure(s, was_running)
			s._complete("closure")
		"dig":
			var bank: float = s.terrain.dig_all()
			s.stats.spoil_m3 += bank * Site.BULKING
			s.terrain.set_hole(s.jm.pit_slot_of(s), true)
			s._finish_dig()
		"pipe":
			_instant_pipe(s)
			s._finish_pipe()
		"refill":
			s.terrain.fill_all(s.terrain.sand_top)
			s.terrain.fill_all(-SiteTerrain.ASPHALT)
			_deliver_needs(s, ["sand", "gravel"])
			s.layer = 1
			s._finish_refill()
		"asphalt":
			s.terrain.set_fresh_all()
			s.terrain.compact(1.0)
			_deliver_needs(s, ["asphalt"])
			s._finish_asphalt()
		"demob":
			for v in s._machines_on_site():
				teleport_to_hq(v, true)
			s._complete("demob")
		"teardown":
			_instant_teardown(s)
			s._complete("teardown")
		"acceptance":
			s._do_acceptance()
		_:
			return _say("Schritt %s kann nicht übersprungen werden" % step, false)
	return _say("%s: „%s“ sofort erledigt" % [s.job.short_title(), title])


## Skips all remaining steps up to and including the acceptance (payment).
static func finish_all(s: Site) -> String:
	if s == null or not is_instance_valid(s) or s.retired:
		return _say("Keine aktive Baustelle", false)
	var title := s.job.short_title()
	for guard in Site.STEPS.size() + 2:
		if s.retired:
			break
		finish_step(s)
	if not s.retired:
		return _say("%s: nicht ganz fertig geworden (Schritt %s)" % [title, s.step_id()], false)
	return _say("%s: alle Schritte erledigt, abgenommen" % title)


## Sends crew van, excavator, tipper and flatbed (if free) to site s.
static func send_fleet(s: Site) -> String:
	if s == null or not is_instance_valid(s) or s.retired:
		return _say("Keine aktive Baustelle", false)
	var n := 0
	for v in _world().fleet.vehicles:
		if not is_instance_valid(v) or v.site != null or v.carried_by != null:
			continue
		if v.def_id in ["van_crew", "excavator_a918", "truck_tipper", "truck_flatbed"]:
			s.send_vehicle(v)
			n += 1
	return _say("%d Fahrzeuge zu %s geschickt" % [n, s.job.short_title()])


static func _cancel_activity(s: Site) -> void:
	s.running = false
	s.sub = ""
	s.compacting = false
	s._wtasks.clear()
	for w in s.workers:
		var wk: Worker = w
		wk.path = []
		wk.walking = false
		wk.action = ""
		wk._cb = Callable()
		wk.remove_meta("tape")
		wk.remove_meta("untape")
		var c := wk.release_carry()
		if c:
			c.queue_free()
		wk.busy = false
	for i in s.workers.size():
		s._worker_home(s.workers[i], i)
	var ex: Vehicle = s._excav
	if ex and is_instance_valid(ex) and ex.rig:
		ex.rig.stop()
		ex.rig.set_meta("cycle", {})
		ex.rig.hook_item = null
		ex.rig.set_load(0.0, "")
		ex.working = false


static func _instant_closure(s: Site, _was_running: bool) -> void:
	if not s.kit_used and s.crew_van and is_instance_valid(s.crew_van) and s.crew_van.cargo.barriers > 0:
		s.crew_van.cargo.barriers -= 1
		s.kit_used = true
	s.plan_confirmed = true
	s.build_when_ready = false
	s.clear_orphans()
	for i in s.item_defs.size():
		if s.item_nodes[i] == null:
			var df: Dictionary = s.item_defs[i]
			var node := SiteProps.item(df.kind, df.phase)
			s.add_child(node)
			node.global_transform = Transform3D(Basis(Vector3.UP, df.yaw), Vector3(df.pos.x, 0.05, df.pos.y))
			s.item_nodes[i] = node
	s.yellow_frac = 1.0
	s._update_yellow()
	s._traffic_activate()


static func _instant_pipe(s: Site) -> void:
	if s.pipe_old:
		s.pipe_old.queue_free()
		s.pipe_old = null
	var fb: Vehicle = s._flatbed_at_load()
	if s.pipe_new == null:
		if fb and fb.cargo.pipes_new > 0:
			fb.cargo.pipes_new -= 1
			fb.cargo.pipes_old += 1
		s.pipe_new = SiteProps.pipe("new", s.job.length - 0.3, s.job.pipe_d)
		s.add_child(s.pipe_new)
		var c := s.lay.trench_center()
		s.pipe_new.global_transform = Transform3D(Basis(Vector3.UP, SiteLayout.yaw_of(s.lay.trench_dir())),
			Vector3(c.x, SiteTerrain.Y_ROAD - s.job.depth + 0.05, c.y))


static func _instant_teardown(s: Site) -> void:
	s.clear_orphans()
	for i in s.item_nodes.size():
		var n: Node3D = s.item_nodes[i]
		if n:
			n.queue_free()
			s.item_nodes[i] = null
	s.yellow_frac = 0.0
	s._update_yellow()
	s._traffic_deactivate()
	if s.kit_used and s.crew_van and is_instance_valid(s.crew_van):
		s.crew_van.cargo.barriers += 1
		s.kit_used = false


static func _deliver_needs(s: Site, mats: Array) -> void:
	for n in s.needs:
		if n.mat in mats:
			n["delivered"] = maxf(float(n.get("delivered", 0.0)), float(n.m3))


# ------------------------------------------------------------------------------------------
# Vehicles, money, traffic
# ------------------------------------------------------------------------------------------

## Puts vehicle v onto a free parking slot at the HQ at once (stuck vehicles, quick resets).
static func teleport_to_hq(v: Vehicle, quiet := false) -> String:
	if v == null or not is_instance_valid(v):
		return _say("Kein Fahrzeug gewählt", false)
	if v.carried_by != null:
		return _say("%s wird gerade transportiert" % v.vname, false)
	var w := _world()
	if v.site and is_instance_valid(v.site):
		v.site.release_vehicle(v)
	v.stop_now()
	var slot_i: int = v.slot if v.slot >= 0 else w.hq.free_slot(v.kind_slot())
	if slot_i < 0:
		return _say("Kein freier Stellplatz in der Zentrale", false)
	v._free_slot()
	v._park_in_slot(slot_i)
	v.status_text = "In der Zentrale"
	Events.vehicle_changed.emit(v)
	var msg := "%s steht in der Zentrale" % v.vname
	return msg if quiet else _say(msg)


static func add_money(amount: float) -> String:
	Game.add_money(amount, "Debug")
	return _say("%s gutgeschrieben" % Balance.money(amount))


## Traffic density factor (0 = no new traffic, 1 = normal, 2 = double).
static func set_traffic(scale: float) -> String:
	var w := _world()
	if w == null:
		return "Keine Welt"
	w.traffic.density_scale = maxf(0.0, scale)
	return _say("Verkehrsdichte %d %%" % int(scale * 100.0))


## Removes all traffic cars (company vehicles stay).
static func clear_traffic() -> String:
	var w := _world()
	if w == null:
		return "Keine Welt"
	var n := 0
	for ag in w.traffic.agents:
		if ag.player == null:
			ag.despawn = true
			n += 1
	return _say("%d Verkehrsfahrzeuge entfernt" % n)
