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
		if ln < 95.0:
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
		# generated offers keep the full standard closure (crew van in front, waiting spots behind on the same
		# street); squeezed spots right at junctions come from the player placing them (#33)
		var max_s0: float = c.len - 60.0
		if max_s0 < 34.0:
			continue
		var s0 := rng.randf_range(34.0, max_s0)
		if not lay.setup(world.net, c.key, s0, L, W, D, pipe.d) or not _standard_kerb(lay) or _route_problem(lay) != "":
			continue
		if not _location_free(lay):
			continue
		return _build_job(c, pipe, L, W, D, s0)
	return null


## Generated offers keep the full standard closure: not squeezed, the crew van in front of it, all waiting
## spots and the low-loader behind it on the same street (#33).
static func _standard_kerb(lay: SiteLayout) -> bool:
	if lay.squeezed or lay.s_van < 0.0 or str(lay.kerb.get("lowbed", {}).get("run", "")) != "down":
		return false
	for i in 3:
		var sl: Dictionary = (lay.kerb.stage as Array)[i]
		if sl.is_empty() or int(sl.key) != lay.key:
			return false
	return true


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


## Debug: an offer whose trench lies at point p, on the right lane of the nearest street (#33: only the
## pit has to fit, the player plans the rest). Returns {"job": Job} or {"error": String}. The job is
## added to the offers. pipe_i: index into PIPES (-1: random); y_click: height of the click (bridge decks).
func offer_at(p: Vector2, pipe_i := -1, y_click := NAN) -> Dictionary:
	var pipe: Dictionary = PIPES[pipe_i if pipe_i >= 0 and pipe_i < PIPES.size() else rng.randi() % PIPES.size()]
	var r := check_spot(p, pipe, 4.0, 1.8, y_click)
	if not r.ok:
		return {"error": "Hier geht keine Baustelle: " + str(r.error) if r.get("near_road", false) else str(r.error)}
	var lay: SiteLayout = r.lay
	var hq := world.hq_info.get("lot_center", Vector2.ZERO) as Vector2
	var j := _build_job({"key": r.key, "dist": lay.trench_center().distance_to(hq)}, pipe, r.L, pipe.width, r.D, r.s0)
	offers.append(j)
	Events.job_offers_changed.emit()
	return {"job": j, "hints": r.hints}


const PLACE_EXCLUDE := ["motorway", "motorway_link", "service"]
const PLACE_SEARCH := 25.0     # m the pit may move along the street from the click to fit (#33)
const PIT_GAP_OTHER := 4.0     # m between two pits on different streets


## Where a contract for a click at p would go, without side effects (placing and its preview, #33).
## Rules for the pit only: on the right lane of the clicked direction of a street, not on a bridge, in a
## tunnel or in a junction area, room behind it for excavator and tipper, not inside another site.
## Returns {ok, error, near_road, lay, key, s0, L, D, shift, hints: Array[String]}.
func check_spot(p: Vector2, pipe: Dictionary, L := 4.0, D := 1.8, y_click := NAN) -> Dictionary:
	var out := {"ok": false, "error": "", "near_road": false, "lay": null, "key": -1, "s0": 0.0, "L": L, "D": D, "shift": 0.0, "hints": []}
	var net: RoadNet = world.net
	var near: Dictionary = world.router.nearest_lane(p, 25.0)   # grid lookup (the preview calls this per mouse move)
	if near.is_empty():
		out.error = "Keine Straße in der Nähe"
		return out
	var ei: int = int(near.key) >> 4
	var e: Dictionary = net.edges[ei]
	out.near_road = true
	out["probe"] = {"key": int(near.key), "s": float(near.s)}
	# a click on a bridge deck means the bridge, not the road below it
	if not is_nan(y_click) and y_click > Terrain.at(p) + 2.5 and not e.bridge:
		out.error = "auf einer Brücke wird nicht gegraben"
		return out
	if e.cls in PLACE_EXCLUDE:
		out.error = "Autobahnen und Zufahrten (service) gehen noch nicht" if e.cls != "service" else "Zufahrten und Parkplatzwege gehen noch nicht"
		return out
	if e.bridge:
		out.error = "auf einer Brücke wird nicht gegraben"
		return out
	if e.get("tunnel", false) or e.get("under", false):
		out.error = "im Tunnel wird nicht gegraben"
		return out
	if ei == world.traffic._hq_edge:
		out.error = "das ist die Zufahrt der Zentrale"
		return out
	var dir: int = (int(near.key) >> 3) & 1
	var key := RoadNet.lane_key(ei, dir, net.lane_count(ei, dir) - 1)
	if not net.lane_geo.has(key):
		out.error = "Fahrstreifen fehlt"
		return out
	var g: Array = net.lane_geo[key]
	var s_click: float = Geo.closest_on_polyline(g[0], g[1], p)[1]
	out["probe"] = {"key": key, "s": s_click}
	var others := _other_layouts()
	var err := ""
	var steps := int(PLACE_SEARCH)
	for k in 2 * steps + 1:
		# 0, -1, +1, -2, +2 … metres around the clicked point (upstream first: the room behind it is the limit)
		var shift_m := float((k + 1) / 2) * (-1.0 if k % 2 == 1 else 1.0)
		var s0 := s_click + shift_m - SiteLayout.TAPER - SiteLayout.HEAD_GAP - L * 0.5
		var lay := SiteLayout.new()
		if not lay.setup(net, key, s0, L, pipe.width, D, pipe.d):
			if err == "":
				err = lay.error
			continue
		var clash := _clash(lay, others)
		if clash == "":
			clash = _route_problem(lay)
		if clash != "":
			if err == "":
				err = clash
			continue
		out.ok = true
		out.lay = lay
		out.key = key
		out.s0 = s0
		out.shift = shift_m
		out.hints = _spot_hints(lay, shift_m)
		return out
	out.error = err
	return out


## Layouts of all offers and running sites, for the overlap check.
func _other_layouts() -> Array:
	var out: Array = []
	for j in offers + active:
		var s := site_of(j)
		if s and s.lay:
			out.append({"job": j, "lay": s.lay})
			continue
		var l := SiteLayout.new()
		if l.setup(world.net, j.key, j.s0, j.length, j.width, j.depth, j.pipe_d):
			out.append({"job": j, "lay": l})
	return out


## Why lay cannot go next to the other sites ("" = it can): nothing one site occupies on a lane (detour
## with the reversing room behind it, the oncoming zone, kerb spots of van, waiting vehicles and
## low-loader) may overlap what the other occupies; pits on other streets keep a few metres apart.
func _clash(lay: SiteLayout, others: Array) -> String:
	var c := lay.trench_center()
	var mine := occupied(lay)
	for o in others:
		var ol: SiteLayout = o.lay
		var j: Job = o.job
		for a in mine:
			for b in occupied(ol):
				if int(a.key) == int(b.key) and float(a.a) < float(b.b) + 5.0 and float(a.b) > float(b.a) - 5.0:
					return "überschneidet sich mit %s" % j.short_title()
		if ol.trench_center().distance_to(c) < PIT_GAP_OTHER + (lay.L + ol.L) * 0.5:
			return "zu nah an %s" % j.short_title()
	return ""


## Why the fleet could not drive to this site and back ("" = it can): the site's lane and the lanes of
## its kerb spots must be reachable from the HQ, and the HQ from them. Some lanes of a map are not
## (one-way chains, dead ends, gaps in the data; #10, #33). Cached per lane and direction.
func _route_problem(lay: SiteLayout) -> String:
	var keys: Array = [lay.key]
	for sl in [lay.van_spot()] + (lay.kerb.get("stage", []) as Array) + [lay.kerb.get("lowbed", {})]:
		if not (sl as Dictionary).is_empty() and not keys.has(int(sl.key)):
			keys.append(int(sl.key))
	for k in keys:
		var why := _reach(k)
		if why != "":
			return why if k == lay.key else "Parkplatz in der Nachbarstraße: " + why
	return ""


var _reach_from := {}          # edge direction -> true: reachable from the HQ (built once, _build_reach)
var _reach_to := {}            # edge direction -> true: the HQ is reachable from it
var _reach_built := false


func _reach(key: int) -> String:
	if not _reach_built:
		_build_reach()
	var ed := key >> 3
	if _reach_from.is_empty():
		return ""   # no HQ node on this map (tests): nothing to check
	if not _reach_from.has(ed):
		return "von der Zentrale aus nicht erreichbar (Fahrtrichtung oder Lücke im Straßennetz)"
	if not _reach_to.has(ed):
		return "von dort kommt kein Fahrzeug zur Zentrale zurück"
	return ""


## Breadth-first over the edge-direction graph of the router, forwards from the lane leaving the HQ and
## backwards from the lane arriving there (one pass each instead of an A* per lane under the mouse).
func _build_reach() -> void:
	_reach_built = true
	var net: RoadNet = world.net
	var hn: int = net.hq_node
	if hn < 0:
		return
	var starts: Array = []
	var goals: Array = []
	for er in net.nodes[hn].ends:
		var e: int = er >> 1
		var d_out := 0 if (er & 1) == 0 else 1
		if net.lane_count(e, d_out) > 0:
			starts.append(e * 2 + d_out)
		if net.lane_count(e, 1 - d_out) > 0:
			goals.append(e * 2 + 1 - d_out)
	var out: Dictionary = world.router.edir_out
	var back := {}
	for u in out:
		for pair in out[u]:
			var v: int = pair[1]
			if not back.has(v):
				back[v] = []
			back[v].append(u)
	_reach_from = _bfs(starts, func(u): return (out.get(u, []) as Array).map(func(pr): return pr[1]))
	_reach_to = _bfs(goals, func(u): return back.get(u, []))


static func _bfs(starts: Array, next: Callable) -> Dictionary:
	var seen := {}
	var queue: Array = starts.duplicate()
	for st in starts:
		seen[st] = true
	var i := 0
	while i < queue.size():
		var u: int = queue[i]
		i += 1
		for v in next.call(u):
			if not seen.has(v):
				seen[v] = true
				queue.append(v)
	return seen


## Lane ranges a site uses, each in its lane's own coordinates: [{key, a, b}].
static func occupied(lay: SiteLayout) -> Array:
	var out: Array = [{"key": lay.key, "a": lay.s_det0, "b": lay.s_det1 + SiteLayout.REV_ROOM},
		{"key": lay.key2, "a": lay.s2_a, "b": lay.s2_b}]
	var vs := lay.van_spot()
	out.append({"key": vs.key, "a": float(vs.s) - SiteLayout.VAN_REAR - float(vs.appr), "b": float(vs.s) + SiteLayout.VAN_FRONT + 3.0})
	for sl in (lay.kerb.get("stage", []) as Array) + [lay.kerb.get("lowbed", {})]:
		if not (sl as Dictionary).is_empty():
			out.append({"key": sl.key, "a": float(sl.rear) - 6.0, "b": float(sl.rear) + float(sl.len) + 3.0})
	return out


## Things the player should know about a spot (none of them blocks it).
func _spot_hints(lay: SiteLayout, shift_m: float) -> Array:
	var h: Array = []
	if absf(shift_m) > 0.5:
		h.append("Grube um %d m verschoben, damit Bagger und Kipper dahinter Platz haben" % int(round(absf(shift_m))))
	if lay.squeezed:
		h.append("Kurze Straße: Absperrung reicht bis an die Kreuzung – im Planer anpassen")
	var e: Dictionary = world.net.edges[lay.key >> 4]
	for cr in e.get("crossings", []):
		var cp: Vector2 = Geo.sample(e.pts, e.cum, cr.s)[0]
		var cs: float = lay.lane_coords(cp).x
		if cs > lay.s_det0 - 15.0 and cs < lay.s_det1 + 15.0:
			h.append("Fußgängerüberweg im Baustellenbereich")
			break
	var bus := false
	for k in [lay.key, lay.key2]:
		var lg: Array = world.net.lane_geo.get(k, [])
		if lg.is_empty():
			continue
		for st in world.traffic.stops_by_lane.get(k, PackedFloat32Array()):
			var ss: float = lay.lane_coords(Geo.sample(lg[0], lg[1], st)[0]).x
			if ss > lay.s_det0 - 20.0 and ss < lay.s_det1 + 20.0:
				bus = true
	if bus:
		h.append("Bushaltestelle im Baustellenbereich")
	h.append("Engstelle mit Gegenverkehr" if lay.oncoming else "Fahrstreifensperrung (Nachbarstreifen frei)")
	return h


## Debug: one more random offer right now (ignores the offer interval and the maximum).
func debug_new_offer() -> Job:
	var j := _make_offer()
	if j:
		offers.append(j)
		Events.job_offers_changed.emit()
	return j


func _location_free(lay: SiteLayout) -> bool:
	# random offers keep a wider spacing and stay away from the HQ (the player can place anywhere, #33)
	var c := lay.trench_center()
	for j in offers + active:
		if (j as Job).center.distance_to(c) < 160.0:
			return false
	if c.distance_to(world.hq_info.get("lot_center", Vector2(1e9, 1e9))) < 120.0:
		return false
	return _clash(lay, _other_layouts()) == ""


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
		# a few metres of slack: a squeezed site (#33) may just miss the new lane ends
		for sh in [0.0, -1.0, 1.0, -2.0, 2.0]:
			var s0: float = s_c - SiteLayout.TAPER - SiteLayout.HEAD_GAP - j.length * 0.5 + sh
			var l2 := SiteLayout.new()
			if not l2.setup(net, key, s0, j.length, j.width, j.depth, j.pipe_d):
				continue
			var dc := l2.trench_center().distance_to(j.center)
			if dc < best_d:
				best_d = dc
				best_key = key
				best_s0 = s0
			break
	if best_key < 0:
		return false
	print("Auftrag %d: Straße neu zugeordnet (Abschnitt %d -> %d, %.1f m)" % [j.id, j.key, best_key, best_d])
	j.key = best_key
	j.s0 = best_s0
	return true
