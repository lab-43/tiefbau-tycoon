class_name JobManager
extends Node
## Generates contract offers on suitable streets around the HQ, turns accepted jobs into sites,
## books wages and fixed costs, pays out on acceptance and keeps finished road patches.

const CLIENTS := ["Stadtwerke", "Wasserwerke", "Netzgesellschaft", "Stadtentwässerung"]
const PIPES := [
	{"name": "Trinkwasserleitung DN 150", "d": 0.17, "client": 1, "width": 1.2},
	{"name": "Trinkwasserleitung DN 200", "d": 0.22, "client": 1, "width": 1.2},
	{"name": "Trinkwasserleitung DN 300", "d": 0.32, "client": 1, "width": 1.3},
	{"name": "Gasleitung DN 200", "d": 0.22, "client": 2, "width": 1.2},
	{"name": "Abwasserkanal DN 300", "d": 0.36, "client": 3, "width": 1.4},
	{"name": "Abwasserkanal DN 400", "d": 0.46, "client": 3, "width": 1.5},
]
const STREET_CLASSES := ["residential", "tertiary", "secondary", "unclassified", "tertiary_link", "secondary_link"]
const MAX_ACTIVE := 3

var world: World
var offers: Array = []
var active: Array = []
var history: Array = []
var sites := {}                 # job id -> Site
var pit_slots: Array = [null, null, null, null]
var patches: Array = []         # {c: Vector2, d: Vector2, hl, hw}
var rng := RandomNumberGenerator.new()
var _next_id := 1
var _candidates: Array = []
var _next_offer_at := 0.0
var _wage_acc := 0.0
var _last_day := 1


func setup(w: World) -> void:
	world = w
	rng.randomize()
	_build_candidates()
	Events.time_tick.connect(_on_tick)
	_last_day = Clock.day


func _build_candidates() -> void:
	var net := world.net
	var hq := world.hq_info.get("lot_center", Vector2.ZERO) as Vector2
	for key in net.lane_geo:
		var ei: int = key >> 4
		var e: Dictionary = net.edges[ei]
		if not (e.cls in STREET_CLASSES) or e.bridge or e.get("tunnel", false) or e.get("under", false) or ei == world.traffic._hq_edge:
			continue
		var dir: int = (key >> 3) & 1
		if (key & 7) != net.lane_count(ei, dir) - 1:
			continue
		var g: Array = net.lane_geo[key]
		var cum: PackedFloat32Array = g[1]
		var ln: float = cum[cum.size() - 1]
		if ln < 135.0:
			continue
		var mid: Vector2 = Geo.sample(g[0], cum, ln * 0.5)[0]
		var dist := mid.distance_to(hq)
		if dist < 250.0 or dist > Balance.JOB_RADIUS_M:
			continue
		_candidates.append({"key": key, "len": ln, "dist": dist})


func generate_initial_offers() -> void:
	for i in 2:
		var j := _make_offer()
		if j:
			offers.append(j)
	_next_offer_at = Clock.total_minutes() + Balance.JOB_OFFER_INTERVAL_H * 60.0
	Events.job_offers_changed.emit()


func _make_offer() -> Job:
	if _candidates.is_empty():
		return null
	for attempt in 60:
		var c: Dictionary = _candidates[rng.randi() % _candidates.size()]
		var pipe: Dictionary = PIPES[rng.randi() % PIPES.size()]
		var L := snappedf(rng.randf_range(3.5, 4.4), 0.1)
		var W: float = pipe.width
		var D := snappedf(rng.randf_range(1.5, 2.1), 0.05)
		var lay := SiteLayout.new()
		var max_s0: float = c.len - 95.0
		if max_s0 < 36.0:
			continue
		var s0 := rng.randf_range(36.0, max_s0)
		if not lay.setup(world.net, c.key, s0, L, W, D, pipe.d):
			continue
		if not _location_free(lay):
			continue
		return _build_job(c, pipe, L, W, D, s0)
	return null


## Job for lane candidate c ({key, dist}) with the trench starting at s0 (layout already validated).
func _build_job(c: Dictionary, pipe: Dictionary, L: float, W: float, D: float, s0: float) -> Job:
	var lay := SiteLayout.new()
	lay.setup(world.net, c.key, s0, L, W, D, pipe.d)
	var j := Job.new()
	j.id = _next_id
	_next_id += 1
	j.key = c.key
	j.s0 = s0
	j.length = L
	j.width = W
	j.depth = D
	j.pipe_d = pipe.d
	j.pipe_name = pipe.name
	var city: String = Game.map_meta.get("name", "")
	j.client = "%s %s" % [CLIENTS[pipe.client], city] if city != "" else CLIENTS[pipe.client]
	var e: Dictionary = world.net.edges[c.key >> 4]
	j.street = e.name
	j.center = lay.trench_center()
	j.distance_m = c.dist
	j.duration_days = 3 if rng.randf() < 0.6 else 4
	var base: float = 9000.0 + 1250.0 * L + 3400.0 * maxf(0.0, D - 1.2) + 5000.0 * pipe.d + c.dist * 0.6
	if e.cls in ["secondary", "secondary_link"]:
		base *= 1.12
	j.pay = snappedf(base * rng.randf_range(0.92, 1.12), 50.0)
	j.offered_at = Clock.total_minutes()
	j.expires_at = j.offered_at + 22.0 * 60.0
	return j


## Debug: an offer whose trench lies at point p, on the right lane of the nearest street (any class
## except motorways and service roads). Searches up to 40 m along the street for a valid spot.
## Returns {"job": Job} or {"error": String}. The job is added to the offers.
func offer_at(p: Vector2) -> Dictionary:
	var net: RoadNet = world.net
	var near := net.nearest_lane(p, 40.0, ["motorway", "motorway_link", "trunk", "trunk_link", "service"])
	if near.is_empty():
		return {"error": "Keine passende Straße in der Nähe"}
	var ei: int = int(near.key) >> 4
	var e: Dictionary = net.edges[ei]
	if e.bridge or e.get("tunnel", false) or e.get("under", false):
		return {"error": "Auf Brücken und in Tunneln geht keine Baustelle"}
	var dir: int = (int(near.key) >> 3) & 1
	var key := RoadNet.lane_key(ei, dir, net.lane_count(ei, dir) - 1)
	var g: Array = net.lane_geo[key]
	var s_click: float = Geo.closest_on_polyline(g[0], g[1], p)[1]
	var pipe: Dictionary = PIPES[rng.randi() % PIPES.size()]
	var L := 4.0
	var D := 1.8
	var err := ""
	for k in 41:
		# 0, +2, -2, +4, -4 … metres around the clicked point
		var shift_m := float((k + 1) / 2) * 2.0 * (1.0 if k % 2 == 1 else -1.0)
		var s0 := s_click + shift_m - SiteLayout.TAPER - SiteLayout.HEAD_GAP - L * 0.5
		var lay := SiteLayout.new()
		if not lay.setup(net, key, s0, L, pipe.width, D, pipe.d):
			if err == "":
				err = lay.error
			continue
		if not _location_free(lay):
			if err == "":
				err = "zu nah an einem anderen Auftrag, Zebrastreifen, Haltestelle oder der Zentrale"
			continue
		var hq := world.hq_info.get("lot_center", Vector2.ZERO) as Vector2
		var j := _build_job({"key": key, "dist": lay.trench_center().distance_to(hq)}, pipe, L, pipe.width, D, s0)
		offers.append(j)
		Events.job_offers_changed.emit()
		return {"job": j}
	return {"error": "Hier geht keine Baustelle: " + err}


## Debug: one more random offer right now (ignores the offer interval and the maximum).
func debug_new_offer() -> Job:
	var j := _make_offer()
	if j:
		offers.append(j)
		Events.job_offers_changed.emit()
	return j


func _location_free(lay: SiteLayout) -> bool:
	var c := lay.trench_center()
	for j in offers + active:
		if (j as Job).center.distance_to(c) < 160.0:
			return false
	# no pedestrian crossing or bus stop inside the closure
	var e: Dictionary = world.net.edges[lay.key >> 4]
	for cr in e.get("crossings", []):
		var p: Vector2 = Geo.sample(e.pts, e.cum, cr.s)[0]
		var r: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], p)
		if r[1] > lay.s_det0 - 15.0 and r[1] < lay.s_det1 + 15.0:
			return false
	for k in [lay.key, lay.key2]:
		for s in world.traffic.stops_by_lane.get(k, PackedFloat32Array()):
			var sp := lay.lane_pt(0.0)
			if k == lay.key and s > lay.s_det0 - 20.0 and s < lay.s_det1 + 20.0:
				return false
			if k == lay.key2 and s > lay.s2_a - 20.0 and s < lay.s2_b + 20.0:
				return false
	# keep away from the HQ driveway
	if c.distance_to(world.hq_info.get("lot_center", Vector2(1e9, 1e9))) < 120.0:
		return false
	return true


func accept(j: Job) -> bool:
	if not offers.has(j):
		return false
	if active.size() >= MAX_ACTIVE:
		Events.warn("Maximal %d Aufträge gleichzeitig" % MAX_ACTIVE)
		return false
	var slot := pit_slots.find(null)
	if slot < 0:
		Events.warn("Zu viele offene Baustellen")
		return false
	var lay := SiteLayout.new()
	if not lay.setup(world.net, j.key, j.s0, j.length, j.width, j.depth, j.pipe_d):
		Events.error("Baustelle nicht mehr möglich: %s" % lay.error)
		offers.erase(j)
		Events.job_offers_changed.emit()
		return false
	offers.erase(j)
	j.state = "active"
	j.accepted_day = Clock.day
	j.deadline_day = Clock.day + j.duration_days
	active.append(j)
	var site := Site.new()
	add_child(site)
	pit_slots[slot] = site
	site.setup(world, self, j, lay, j.id)
	sites[j.id] = site
	Events.ok("Auftrag angenommen: %s, %s" % [j.title(), j.location()])
	Events.job_offers_changed.emit()
	Events.job_changed.emit(j)
	return true


func decline(j: Job) -> void:
	if offers.has(j):
		offers.erase(j)
		j.state = "declined"
		Events.job_offers_changed.emit()


func site_of(j: Job) -> Site:
	return sites.get(j.id)


func site_at(p: Vector2) -> Site:
	for id in sites:
		var s: Site = sites[id]
		if s.contains(p):
			return s
	return null


func pit_slot_of(s: Site) -> int:
	return pit_slots.find(s)


func all_sites() -> Array:
	return sites.values()


func finish_job(site: Site) -> void:
	var j := site.job
	var late := maxi(0, Clock.day - j.deadline_day)
	var penalty := j.pay * Balance.JOB_PENALTY_PER_DAY * late
	var bonus := 0.0
	if Clock.day <= j.accepted_day + int(j.duration_days / 2.0):
		bonus = j.pay * 0.05
	var total := j.pay - penalty + bonus
	Game.add_money(total, "Abnahme %s (%s)" % [j.short_title(), j.location()])
	Game.company.jobs_done += 1
	Game.company.reputation = clampf(Game.company.reputation + (4.0 if late == 0 else -3.0 * late), 0.0, 100.0)
	j.result = {"pay": j.pay, "penalty": penalty, "bonus": bonus, "total": total, "costs": j.costs, "late_days": late,
		"day": Clock.day, "jam_min": site.stats.jam_s / 60.0}
	j.state = "done"
	active.erase(j)
	history.push_front(j)
	if history.size() > 30:
		history.resize(30)
	Events.ok("Abnahme bestanden – %s gutgeschrieben" % Balance.money(total))
	Events.notify.emit("ABNAHME|%d" % j.id, "report")
	# keep the repaired surface as a permanent patch
	var t := site.terrain
	patches.append({"c": t.center, "d": t.dir, "hl": t.hl, "hw": t.hw})
	_add_patch(patches[patches.size() - 1])
	var van := site.crew_van
	var leftovers: Array = site.vehicles.filter(func(v): return is_instance_valid(v) and v != van and v.carried_by == null)
	site.remove_site()
	var slot := pit_slots.find(site)
	if slot >= 0:
		pit_slots[slot] = null
	sites.erase(j.id)
	site.retire()
	if van and is_instance_valid(van):
		van.drive_to_hq.call_deferred()
	for v in leftovers:
		if v.site == null and v.state in ["parked", "working"] and not v.at_hq():
			v.drive_to_hq.call_deferred()
	Events.job_changed.emit(j)
	Events.job_offers_changed.emit()


func _add_patch(p: Dictionary) -> void:
	var c: Vector2 = p.c
	var d: Vector2 = p.d
	var r := Geo.right_of(d)
	var hl: float = p.hl
	var hw: float = p.hw
	var a := c - d * hl - r * hw
	var b := c + d * hl - r * hw
	var cc := c + d * hl + r * hw
	var dd := c - d * hl + r * hw
	var l := MeshLayer.new()
	l.terrain = Terrain.cur   # on the ground (#8); null on flat maps
	l.quad(Geo.v3(a, 0.056), Geo.v3(b, 0.056), Geo.v3(cc, 0.056), Geo.v3(dd, 0.056), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = l.commit()
	mi.material_override = Mats.get_mat("asphalt_new")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var seam := StandardMaterial3D.new()
	seam.albedo_color = Color(0.04, 0.04, 0.045)
	seam.roughness = 0.4
	var ring := PackedVector2Array([a, b, cc, dd, a])
	add_child(SiteProps.ribbon(ring, 0.06, 0.058, seam))


# ------------------------------------------------------------------------------------------
# Time: offers, wages, fixed costs
# ------------------------------------------------------------------------------------------

func _on_tick(day: int, minutes: float) -> void:
	var now := Clock.total_minutes()
	# expire offers
	var changed := false
	for j in offers.duplicate():
		if now > j.expires_at:
			offers.erase(j)
			j.state = "expired"
			changed = true
	if now >= _next_offer_at:
		_next_offer_at = now + Balance.JOB_OFFER_INTERVAL_H * 60.0 * rng.randf_range(0.7, 1.3)
		if offers.size() < Balance.JOB_MAX_OFFERS:
			var j2 := _make_offer()
			if j2:
				offers.append(j2)
				changed = true
				Events.info("Neue Ausschreibung: %s, %s" % [j2.title(), j2.location()])
	if changed:
		Events.job_offers_changed.emit()
	# crew wages (per game minute while a crew is out of the yard)
	var h := fmod(minutes / 60.0, 24.0)
	var night := h >= 22.0 or h < 6.0
	for v in world.fleet.vehicles:
		if v.has_ability("crew") and not v.at_hq():
			var crew: int = v.crew_aboard
			if v.site and v.site.crew_van == v:
				crew += v.site.workers.size()
			if crew > 0:
				var wage := Balance.WORKER_WAGE_H * crew / 60.0 * (1.0 + (Balance.NIGHT_SURCHARGE if night else 0.0))
				_wage_acc += wage
				if v.site:
					v.site.job.costs += wage
	if _wage_acc >= 150.0 or (int(minutes) % 60 == 0 and _wage_acc > 0.0):
		Game.spend(_wage_acc, "Löhne Kolonne", true)
		_wage_acc = 0.0
	# daily fixed costs
	if day != _last_day:
		_last_day = day
		var fixed := 180.0
		for v in world.fleet.vehicles:
			fixed += float(v.def.get("price", 0.0)) * 0.00035
		Game.spend(fixed, "Fixkosten Tag %d (Versicherung, Wartung, Hof)" % (day - 1), true)
		for j in active:
			if day > j.deadline_day:
				Events.warn("%s ist überfällig (Vertragsstrafe pro Tag)" % j.short_title())
		# autosave once per game day
		Game.save_game.call_deferred()


# ------------------------------------------------------------------------------------------
# Save / load
# ------------------------------------------------------------------------------------------

func save_state() -> Dictionary:
	var off := []
	for j in offers:
		off.append(j.to_dict())
	var act := []
	for j in active:
		var d: Dictionary = j.to_dict()
		var s := site_of(j)
		if s:
			d["site"] = s.save_state()
		act.append(d)
	var hist := []
	for j in history:
		hist.append(j.to_dict())
	return {"offers": off, "active": act, "history": hist, "patches": patches, "next_id": _next_id, "next_offer": _next_offer_at}


func load_state(d: Dictionary) -> void:
	_next_id = d.get("next_id", 1)
	_next_offer_at = d.get("next_offer", Clock.total_minutes() + 120.0)
	for jd in d.get("offers", []):
		var oj := Job.from_dict(jd)
		if _relocate(oj):
			offers.append(oj)
	for jd in d.get("history", []):
		history.append(Job.from_dict(jd))
	for p in d.get("patches", []):
		patches.append(p)
		_add_patch(p)
	for jd in d.get("active", []):
		var j := Job.from_dict(jd)
		var key0 := j.key
		var site_d: Dictionary = jd.get("site", {})
		if not _relocate(j):
			var msg := "%s (%s) passt nicht auf die neu aufbereitete Karte und wurde abgebrochen." % [j.short_title(), j.location()]
			push_warning(msg)
			Events.warn.call_deferred(msg)
			continue
		if j.key != key0 and not site_d.is_empty():
			# the player's traffic paths are lane coordinates of the old lane: back to automatic (#23)
			site_d = site_d.duplicate(true)
			var pl: Dictionary = site_d.get("plan", {})
			if pl.has("traffic"):
				pl["traffic"] = {}
		var lay := SiteLayout.new()
		if not lay.setup(world.net, j.key, j.s0, j.length, j.width, j.depth, j.pipe_d):
			continue
		active.append(j)
		var slot := pit_slots.find(null)
		var site := Site.new()
		add_child(site)
		pit_slots[slot] = site
		site.setup(world, self, j, lay, j.id)
		sites[j.id] = site
		if not site_d.is_empty():
			site.load_state(site_d)
	Events.job_offers_changed.emit()


const RELOCATE_TOL := 2.5      # m between the saved and the rebuilt trench centre


## Saved jobs keep the lane key of the map build they were made on. A newer build (other BAKE_VERSION) numbers
## the roads anew: the key can be missing or belong to another street (#23). Keeps the key if the trench still
## lies where it was saved, otherwise finds the right lane at the saved trench centre again (both directions of the
## nearest road, the closer one wins). Returns false if the job does not fit on this map.
func _relocate(j: Job) -> bool:
	var net: RoadNet = world.net
	var lay := SiteLayout.new()
	var fits := lay.setup(net, j.key, j.s0, j.length, j.width, j.depth, j.pipe_d)
	if j.center == Vector2.ZERO:
		return fits                # saves from before the centre was stored
	if fits and lay.trench_center().distance_to(j.center) < RELOCATE_TOL:
		return true
	var near := net.nearest_lane(j.center, 30.0)
	if near.is_empty():
		return false
	var ei: int = int(near.key) >> 4
	var best_key := -1
	var best_s0 := 0.0
	var best_d := RELOCATE_TOL
	for dir in [0, 1]:
		var n := net.lane_count(ei, dir)
		if n < 1:
			continue
		var key := RoadNet.lane_key(ei, dir, n - 1)
		if not net.lane_geo.has(key):
			continue
		var g: Array = net.lane_geo[key]
		var s_c: float = Geo.closest_on_polyline(g[0], g[1], j.center)[1]
		var s0 := s_c - SiteLayout.TAPER - SiteLayout.HEAD_GAP - j.length * 0.5
		var l2 := SiteLayout.new()
		if not l2.setup(net, key, s0, j.length, j.width, j.depth, j.pipe_d):
			continue
		var dc := l2.trench_center().distance_to(j.center)
		if dc < best_d:
			best_d = dc
			best_key = key
			best_s0 = s0
	if best_key < 0:
		return false
	print("Auftrag %d: Straße neu zugeordnet (Abschnitt %d -> %d, %.1f m)" % [j.id, j.key, best_key, best_d])
	j.key = best_key
	j.s0 = best_s0
	return true
