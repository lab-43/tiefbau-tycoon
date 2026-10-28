class_name ClosurePlan
extends RefCounted
## Player-designed closure of a construction site (#9): barrier items and yellow temporary markings in
## world coordinates (x, z). The crew builds them in list order (Site). Created from the standard
## layout (template) or by the ClosureDesigner. Also owns the chain tools (straight/curved rows of
## items), the rule checks shown in the designer, the bill of materials and save/load.

## Kinds the designer offers. spacing: default chain spacing in m; linear: element with a length
## along its +X axis (origin at its left end); sign: traffic sign on a stand.
const KINDS := {
	"bake": {"label": "Leitbake", "short": "Bake", "spacing": 5.0},
	"cone": {"label": "Leitkegel", "short": "Hütchen", "spacing": 2.0},
	"schranke": {"label": "Absperrschranke", "short": "Schranke", "linear": true},
	"fence": {"label": "Absperrgitter", "short": "Gitter", "linear": true},
	"line": {"label": "Gelbe Markierung", "short": "Markierung", "spacing": 0.0},
	"z123": {"label": "Z 123 Arbeitsstelle", "short": "Z 123", "sign": true, "spacing": 30.0},
	"z208": {"label": "Z 208 Vorrang Gegenverkehr", "short": "Z 208", "sign": true, "spacing": 30.0},
	"z308": {"label": "Z 308 Vorrang vor Gegenverkehr", "short": "Z 308", "sign": true, "spacing": 30.0},
	"z274": {"label": "Z 274 Höchstgeschwindigkeit", "short": "Z 274", "sign": true, "spacing": 30.0},
	"z250": {"label": "Z 250 Verbot für Fahrzeuge aller Art", "short": "Z 250", "sign": true, "spacing": 30.0},
}
const ORDER := ["bake", "cone", "schranke", "fence", "line", "z123", "z208", "z308", "z274", "z250"]
const ELEM_LEN := 2.14      # Absperrschranke / Absperrgitter: length along +X from the origin
const ELEM_STEP := 2.05     # spacing of chained elements (end to end, the feet overlap a little)
const TRAFFIC_CLEAR := 1.3  # m: nothing closer than this to the path of a car's centre
const MAX_ITEMS := 600
const PLAN_RADIUS := 500.0  # m around the trench: where the designer places things (#18)

var items: Array = []       # {kind, pos: Vector2, yaw: float, phase: float, group: String}
var lines: Array = []       # PackedVector2Array per yellow marking
var custom := false         # false = standard template (layout order, traffic geometry unchanged)
var traffic := {}           # player-laid traffic paths (#19): {"k": [Vector2(s, lat)], "k2": [...]}; empty = automatic
var full := false           # full road closure (#20): no through traffic on the site's road, it takes other roads


static func is_linear(kind: String) -> bool:
	return KINDS.get(kind, {}).get("linear", false)


static func is_sign(kind: String) -> bool:
	return KINDS.get(kind, {}).get("sign", false)


static func label(kind: String) -> String:
	return KINDS.get(kind, {}).get("label", kind)


static func default_spacing(kind: String) -> float:
	if is_linear(kind):
		return ELEM_STEP
	return float(KINDS.get(kind, {}).get("spacing", 5.0))


static func make_item(kind: String, p: Vector2, yaw: float, phase := 0.0, group := "") -> Dictionary:
	return {"kind": kind, "pos": p, "yaw": yaw, "phase": phase, "group": group}


## Standard plan for a full road closure (#20): barriers across the whole carriageway in front of the
## work area (and behind it when the other lane carries oncoming traffic), Z 250 and Z 123 for every
## closed direction, fall protection at the trench as in the standard closure.
static func full_from_layout(lay: SiteLayout) -> ClosurePlan:
	var p := ClosurePlan.new()
	p.custom = true
	p.full = true
	var side := lay.lw * 0.5 + 0.7
	var sf := lay.s_c0 + 0.6
	for sk in [["z123", 45.0], ["z250", 4.0]]:
		var ss := maxf(3.0, sf - float(sk[1]))
		p.items.append(make_item(str(sk[0]), lay.lane_pt(ss, side), SiteLayout.yaw_of(lay.lane_dir(ss)), 0.0, "signs"))
	if lay.oncoming:
		# the oncoming direction meets the closure behind the work area (K2 runs the other way)
		var sr := lay.s_c1 + 1.5
		var s2r: float = lay.lane2_coords(lay.lane_pt(sr)).x
		for sk2 in [["z123", 45.0], ["z250", 4.0]]:
			var s2 := maxf(3.0, s2r - float(sk2[1]))
			p.items.append(make_item(str(sk2[0]), lay.lane2_pt(s2, lay.lw2 * 0.5 + 0.7), SiteLayout.yaw_of(lay.lane2_dir(s2)), 0.0, "signs"))
	p.items.append_array(_across(lay, sf, false))
	if lay.oncoming:
		p.items.append_array(_across(lay, lay.s_c1 + 1.5, true))
	for it in lay.items():
		if it.group == "pit":
			p.items.append((it as Dictionary).duplicate())
	return p


## Absperrschranken across the whole carriageway (both lanes) at s on K. from_k2: the chain starts on
## the far side, so that the warning side faces the traffic of the other lane.
static func _across(lay: SiteLayout, s: float, from_k2: bool) -> Array:
	var away := 1.0 if lay.oncoming else -1.0
	var a := lay.lane_pt(s, lay.lw * 0.5 - 0.05)
	var s2: float = lay.lane2_coords(lay.lane_pt(s)).x
	var b := lay.lane2_pt(s2, away * (lay.lw2 * 0.5 - 0.05))
	var out := chain("schranke", PackedVector2Array([b, a]) if from_k2 else PackedVector2Array([a, b]), ELEM_STEP, lay)
	for it in out:
		it.group = "head"
	return out


## Lateral extent of the whole carriageway (K and K2) in K coordinates near s: Vector2(lo, hi).
static func road_span(lay: SiteLayout, s: float) -> Vector2:
	var away := 1.0 if lay.oncoming else -1.0
	var s2: float = lay.lane2_coords(lay.lane_pt(s)).x
	var far: float = lay.lane_coords(lay.lane2_pt(s2, away * lay.lw2 * 0.5)).y
	return Vector2(minf(far, -lay.lw * 0.5), maxf(far, lay.lw * 0.5))


## The standard closure of the layout (what the game built before #9), in its build order.
static func from_layout(lay: SiteLayout) -> ClosurePlan:
	var p := ClosurePlan.new()
	for it in lay.items():
		p.items.append((it as Dictionary).duplicate())
	p.lines.append(lay.yellow_line())
	p.custom = false
	return p


func copy() -> ClosurePlan:
	var p := ClosurePlan.new()
	for it in items:
		p.items.append((it as Dictionary).duplicate())
	for l in lines:
		p.lines.append(PackedVector2Array(l))
	p.custom = custom
	p.full = full
	for k in traffic:
		p.traffic[k] = (traffic[k] as Array).duplicate()
	return p


## Traffic geometry this plan leads to (detour, blocked range, crew van spot, traffic paths).
func extent(lay: SiteLayout) -> Dictionary:
	return lay.extent_for(items, traffic) if custom else lay.default_extent()


func is_empty() -> bool:
	return items.is_empty() and lines.is_empty()


# ------------------------------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------------------------------

## Local +X of an item in map coordinates (x, z).
static func axis_x(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


## Local +Z (the side facing approaching traffic) in map coordinates.
static func axis_z(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## Centre of the item's footprint (linear elements extend along +X from their origin).
static func item_center(it: Dictionary) -> Vector2:
	var p: Vector2 = it.pos
	if is_linear(it.kind):
		return p + axis_x(float(it.yaw)) * ELEM_LEN * 0.5
	return p


## Yaw for a linear element whose +X runs along tangent t.
static func yaw_along(t: Vector2) -> float:
	return atan2(-t.y, t.x)


## Facing for a single item at p: signs and beacons face the traffic of the nearest lane of the site
## (K or K2); linear elements stand across that lane.
static func auto_yaw(kind: String, p: Vector2, lay: SiteLayout) -> float:
	var d := _traffic_dir(p, lay)
	if is_linear(kind):
		# across the lane, warning side (+Z) towards approaching traffic
		return yaw_along(Geo.right_of(d))
	return SiteLayout.yaw_of(d)


## Travel direction of the nearest lane at p: the site lanes (K, K2) or, further away (signs on other
## streets within the planning radius), any lane of the road network.
static func _traffic_dir(p: Vector2, lay: SiteLayout) -> Vector2:
	var r1: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], p)
	var r2: Array = Geo.closest_on_polyline(lay._g2[0], lay._g2[1], p)
	var best_d := minf(float(r1[0]), float(r2[0]))
	if best_d > 6.0 and Game.world and Game.world.router:
		var nl: Dictionary = Game.world.router.nearest_lane(p, minf(best_d, 40.0))
		if not nl.is_empty():
			var g: Array = lay.net.lane_geo[nl.key]
			return Geo.sample(g[0], g[1], float(nl.s))[1]
	if float(r2[0]) < float(r1[0]):
		return lay.lane2_dir(float(r2[1]))
	return lay.lane_dir(float(r1[1]))


## Items along a polyline: point items every `spacing` m (first at the start), linear elements end to
## end. skip_first: the start point already carries an item (continued chain).
static func chain(kind: String, path: PackedVector2Array, spacing: float, lay: SiteLayout, skip_first := false) -> Array:
	var out: Array = []
	if path.size() < 2 or kind == "line":
		return out
	var cum := Geo.cumulative(path)
	var total: float = cum[cum.size() - 1]
	if total < 0.05:
		return out
	if is_linear(kind):
		# end to end with the feet touching (#17: stretching them over the path made them overlap);
		# the last one may stick out or stop short by up to half an element
		var n := maxi(1, int(round((total - ELEM_LEN) / ELEM_STEP)) + 1)
		var d0 := _traffic_dir(path[0], lay)
		var pref := (-d0 + Geo.left_of(d0)).normalized()
		var end_dir: Vector2 = Geo.sample(path, cum, total)[1]
		for i in n:
			var s0 := i * ELEM_STEP
			var a: Vector2
			var t: Vector2
			if s0 + 0.5 < total:
				a = Geo.sample(path, cum, s0)[0]
				var b: Vector2 = Geo.sample(path, cum, minf(s0 + ELEM_LEN, total))[0]
				t = (b - a).normalized()
			else:
				t = end_dir
				a = path[path.size() - 1] + end_dir * (s0 - total)
			var yaw := yaw_along(t)
			var origin := a
			if axis_z(yaw).dot(pref) < 0.0:
				# turn it around so that its warning side faces the traffic; origin moves to the other end
				yaw += PI
				origin = a + t * ELEM_LEN
			out.append(make_item(kind, origin, wrapf(yaw, -PI, PI)))
		return out
	# never wider than the chosen spacing (Leitbaken have a maximum distance)
	var sp := maxf(0.3, spacing)
	var cnt := maxi(1, int(ceil(total / sp - 0.02)))
	var step2 := total / float(cnt)
	for i in range(0, cnt + 1):
		if i == 0 and skip_first:
			continue
		var s := minf(i * step2, total)
		var p: Vector2 = Geo.sample(path, cum, s)[0]
		out.append(make_item(kind, p, auto_yaw(kind, p, lay)))
	return out


## Path of a straight chain from a to b. Along the closed lane (both ends near it, running roughly
## parallel) the chain follows the lane's curvature at a linearly changing offset, like a real
## Leitbaken line; otherwise it is the straight segment.
static func lane_path(a: Vector2, b: Vector2, lay: SiteLayout) -> PackedVector2Array:
	var la := lay.lane_coords(a)
	var lb := lay.lane_coords(b)
	var ds := lb.x - la.x
	var straight := PackedVector2Array([a, b])
	if absf(ds) < 2.0 or absf(la.y) > 7.0 or absf(lb.y) > 7.0:
		return straight
	if absf(lb.y - la.y) > absf(ds) * 0.6:
		return straight
	if la.x < 0.0 or lb.x < 0.0 or la.x > lay.len_k or lb.x > lay.len_k:
		return straight
	var n := clampi(int(ceil(absf(ds) / 1.0)), 2, 400)
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(lay.lane_pt(lerpf(la.x, lb.x, t), lerpf(la.y, lb.y, t)))
	# exact end points (lane_coords rounding)
	out[0] = a
	out[out.size() - 1] = b
	return out


## Quadratic Bézier from a to b with control point c (the curve leaves a towards c, like the curve
## tool of Cities: Skylines: start, direction, end).
static func bezier(a: Vector2, c: Vector2, b: Vector2, step := 0.5) -> PackedVector2Array:
	var approx := a.distance_to(c) + c.distance_to(b)
	var n := clampi(int(ceil(approx / step)), 2, 400)
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		out.append(a * u * u + c * 2.0 * u * t + b * t * t)
	return out


## Quadratic Bézier from a to b that passes through m at its middle.
static func curve_through(a: Vector2, m: Vector2, b: Vector2, step := 0.5) -> PackedVector2Array:
	var c := 2.0 * m - (a + b) * 0.5
	var approx := a.distance_to(m) + m.distance_to(b)
	var n := clampi(int(ceil(approx / step)), 2, 400)
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		out.append(a * u * u + c * 2.0 * u * t + b * t * t)
	return out


# ------------------------------------------------------------------------------------------
# Build order
# ------------------------------------------------------------------------------------------

## Order for a player plan: signs first (upstream first), then everything else from upstream to
## downstream along the closed lane. Beacons in the taper get running-light phases.
func sort_for_build(lay: SiteLayout) -> void:
	var keyed: Array = []
	for i in items.size():
		var it: Dictionary = items[i]
		var lc := lay.lane_coords(item_center(it))
		keyed.append([0 if is_sign(it.kind) else 1, lc.x, i, it])
	keyed.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		if absf(float(a[1]) - float(b[1])) > 0.01:
			return float(a[1]) < float(b[1])
		return int(a[2]) < int(b[2]))
	items.clear()
	for k in keyed:
		items.append(k[3])
	# running light along the taper: in-lane beacons before the first cross barrier
	var head_s := lay.s_c0
	for it in items:
		var lc2 := lay.lane_coords(item_center(it))
		if it.kind == "schranke" and lay.in_lane(lc2):
			head_s = lc2.x
			break
	var k2 := 0
	for it in items:
		it["group"] = ""
		it["phase"] = 0.0
		if it.kind == "bake":
			var lc3 := lay.lane_coords(it.pos)
			if lay.in_lane(lc3) and lc3.x < head_s:
				it["phase"] = fmod(0.12 * k2, 1.0)
				k2 += 1


## Item definitions as the Site uses them: the plan items plus in_lane (blocks the closed lane K;
## the first one placed shifts the traffic, the last one removed ends the detour).
func defs(lay: SiteLayout) -> Array:
	var out: Array = []
	for it in items:
		var d: Dictionary = (it as Dictionary).duplicate()
		d["in_lane"] = lay.in_lane(lay.lane_coords(item_center(d)))
		if not d.has("group"):
			d["group"] = ""
		out.append(d)
	return out


# ------------------------------------------------------------------------------------------
# Bill of materials
# ------------------------------------------------------------------------------------------

func counts() -> Dictionary:
	var c := {}
	for it in items:
		c[it.kind] = int(c.get(it.kind, 0)) + 1
	var m := 0.0
	for l in lines:
		m += Geo.polyline_length(l)
	if m > 0.0:
		c["line"] = m
	return c


# ------------------------------------------------------------------------------------------
# Rule checks (shown in the designer; nothing is blocked)
# ------------------------------------------------------------------------------------------

## [{id, ok, required, text, hint}]. Geometry from the layout: trench, machine slots, traffic paths.
func checks(lay: SiteLayout) -> Array:
	var out: Array = []
	var ext := extent(lay)
	var sep_kinds := ["bake", "cone", "schranke", "fence"]
	var lc_of: Array = []
	for it in items:
		lc_of.append(lay.lane_coords(item_center(it)))
	if full:
		return _checks_full(lay, lc_of)
	# 1. cross barrier ahead of the trench
	var quer := false
	for i in items.size():
		var it: Dictionary = items[i]
		var lc: Vector2 = lc_of[i]
		if (it.kind == "schranke" or it.kind == "fence") and lc.x > lay.s_t0 - 25.0 and lc.x < lay.s_t0 - 0.3 and absf(lc.y) < lay.lw * 0.5 + 0.2:
			if absf(axis_x(float(it.yaw)).dot(lay.lane_dir(lc.x))) < 0.6:
				quer = true
				break
	out.append({"id": "quer", "ok": quer, "required": true, "text": "Querabsperrung vor dem Graben",
		"hint": "Eine Absperrschranke quer über den gesperrten Fahrstreifen vor den Arbeitsbereich stellen."})
	# 2. longitudinal separation between traffic and the work area
	var s_a := lay.s_t0 - 0.5
	var s_b := lay.s_c1
	var band_lo := -lay.lw * 0.5 - 0.9
	var band_hi := -lay.lw * 0.5 + 0.7
	var covered: Array = []
	for i in items.size():
		var it2: Dictionary = items[i]
		if not (it2.kind in sep_kinds):
			continue
		var lc4: Vector2 = lc_of[i]
		if lc4.y < band_lo or lc4.y > band_hi:
			continue
		var half := 4.6 if it2.kind == "bake" else (2.1 if it2.kind == "cone" else 1.4)
		covered.append(Vector2(lc4.x - half, lc4.x + half))
	for l in lines:
		var pl: PackedVector2Array = l
		var run_a := INF
		for k in pl.size():
			var lcl := lay.lane_coords(pl[k])
			var inside := lcl.y >= band_lo and lcl.y <= band_hi
			if inside and run_a == INF:
				run_a = lcl.x
			if (not inside or k == pl.size() - 1) and run_a != INF:
				covered.append(Vector2(minf(run_a, lcl.x) - 0.3, maxf(run_a, lcl.x) + 0.3))
				run_a = INF
	var gap_at := _first_gap(covered, s_a, s_b)
	out.append({"id": "laengs", "ok": gap_at < 0.0, "required": true, "text": "Längsabsicherung zum Verkehr",
		"hint": ("Lücke etwa %d m nach Grabenbeginn. " % int(round(gap_at - lay.s_t0)) if gap_at >= 0.0 else "") + "Leitbaken (höchstens 9 m Abstand), Hütchen, Gitter oder gelbe Linie an der Kante zum Verkehr entlang des ganzen Arbeitsbereichs."})
	# 3. fall protection along both long sides of the trench
	out.append(_check_grube(lay, lc_of))
	# 4. nothing on the path of the traffic
	var in_path: Array = []
	var paths: Array = [lay.detour_pts_for(ext), lay.zone2_pts_for(ext),
		lay.lane_poly(maxf(0.0, ext.det0 - 80.0), ext.det0, func(_s): return 0.0, 2.0),
		lay.lane_poly(ext.det1, minf(lay.len_k, ext.det1 + 60.0), func(_s): return 0.0, 2.0)]
	var cums: Array = []
	for pth in paths:
		cums.append(Geo.cumulative(pth) if (pth as PackedVector2Array).size() >= 2 else PackedFloat32Array())
	for i in items.size():
		for pk in paths.size():
			var pp: PackedVector2Array = paths[pk]
			if pp.size() >= 2 and _elem_dist(items[i], pp, cums[pk]) < TRAFFIC_CLEAR:
				in_path.append(i)
				break
	var why := "Der Verkehr wird ab der ersten Bake im Fahrstreifen verschwenkt."
	if not traffic.is_empty():
		why = "Die Fahrspuren hast du selbst gelegt: mit dem Werkzeug „Fahrspur“ um die Teile herumführen oder die Teile versetzen."
	elif not in_path.is_empty():
		# the detour has limits (crew van, waiting spots, next junction): explain when the plan exceeds them
		var bx := lay.lane_coords(item_center(items[in_path[0]])).x
		if bx > float(ext.obst1) + 0.5:
			why = "Weiter hinten geht es hier nicht (Kreuzung oder Warteplätze): Der Verkehr schwenkt dort schon zurück. Hinteres Ende kürzer machen."
		elif bx < float(ext.obst0) - 0.5:
			why = "Früher als %s m vor dem Graben kann die Verschwenkung hier nicht beginnen. Vorderes Ende kürzer machen." % _fmt(lay.s_t0 - float(ext.obst0))
	out.append({"id": "fahrweg", "ok": in_path.is_empty(), "required": true, "text": "Fahrweg des Verkehrs frei", "bad": in_path,
		"hint": _bad_text(in_path, "dort, wo Autos fahren (gestrichelte Linie)", lay) + why})
	# 4b. the traffic paths (automatic or laid by the player, #19) stay out of the work area
	var through := ""
	for pk2 in 2:
		var pp2: PackedVector2Array = paths[pk2]
		for q in pp2:
			var lq := lay.lane_coords(q)
			if lq.x > lay.s_t0 - 0.5 and lq.x < lay.s_c1 and lq.y > -lay.lw * 0.5 + 0.9 and lq.y < lay.lw * 0.5 + 0.5:
				through = where(lay, q)
				break
		if through != "":
			break
	out.append({"id": "spur", "ok": through == "", "required": true, "text": "Fahrspuren am Arbeitsbereich vorbei",
		"hint": ("Eine Fahrspur führt %s durch den Arbeitsbereich. " % through if through != "" else "") + "Mit dem Werkzeug „Fahrspur“ die blauen Linien verschieben."})
	# 5. machine slots free
	out.append(_check_plaetze(lay, lc_of))
	# 6. taper ahead of the cross barrier
	var n_taper := 0
	for i in items.size():
		var lc7: Vector2 = lc_of[i]
		if items[i].kind in ["bake", "cone"] and lay.in_lane(lc7) and lc7.x < lay.s_t0 - 1.0 and lc7.x > lay.s_t0 - 80.0:
			n_taper += 1
	out.append({"id": "verschwenkung", "ok": n_taper >= 3, "required": false, "text": "Verschwenkung mit Leitbaken",
		"hint": "Mindestens 3 Leitbaken schräg über den Fahrstreifen vor der Querabsperrung."})
	# 7. advance warning
	var warn := false
	for i in items.size():
		var lc8: Vector2 = lc_of[i]
		if items[i].kind == "z123" and lc8.x < ext.det0 + 2.0 and lc8.x > ext.det0 - 150.0 and lc8.y > -lay.lw * 0.5:
			warn = true
	out.append({"id": "vorwarnung", "ok": warn, "required": false, "text": "Vorwarnung Z 123",
		"hint": "Zeichen 123 am rechten Rand vor dem Beginn der Verschwenkung aufstellen."})
	# 8. priority signs at a bottleneck with oncoming traffic (not needed when both paths are apart, #19)
	if lay.oncoming and not bool(ext.get("two_way", false)):
		var has208 := false
		var has308 := false
		for i in items.size():
			var lc9: Vector2 = lc_of[i]
			if items[i].kind == "z208" and lc9.x < ext.det0 + 2.0 and lc9.x > ext.det0 - 120.0 and lc9.y > -lay.lw * 0.5:
				has208 = true
			if items[i].kind == "z308" and lc9.x > ext.det1 - 5.0 and lc9.x < ext.det1 + 120.0 and lc9.y < -lay.lw * 0.5:
				has308 = true
		out.append({"id": "vorrang", "ok": has208 and has308, "required": false, "text": "Engstelle mit Z 208 und Z 308 geregelt",
			"hint": "Z 208 vor der Engstelle auf deiner Seite, Z 308 für den Gegenverkehr auf dessen Seite."})
	return out


## "Leitbake (12 m vor dem Graben) und 2 weitere stehen <where>. " – the offending items are marked red.
func _check_grube(lay: SiteLayout, lc_of: Array) -> Dictionary:
	var sides_ok := true
	for side in [-1.0, 1.0]:
		var cov: Array = []
		for i in items.size():
			var it3: Dictionary = items[i]
			if not (it3.kind in ["fence", "schranke"]):
				continue
			var lc5: Vector2 = lc_of[i]
			var off: float = lc5.y * side - lay.W * 0.5
			if off < 0.05 or off > 1.6:
				continue
			cov.append(Vector2(lc5.x - 1.2, lc5.x + 1.2))
		if _first_gap(cov, lay.s_t0 + 0.2, lay.s_t1 - 0.2) >= 0.0:
			sides_ok = false
	return {"id": "grube", "ok": sides_ok, "required": true, "text": "Graben gegen Absturz gesichert",
		"hint": "Absperrgitter an beiden Längsseiten des Grabens."}


func _check_plaetze(lay: SiteLayout, lc_of: Array) -> Dictionary:
	var slot_block: Array = []
	for i in items.size():
		var lc6: Vector2 = lc_of[i]
		if lc6.x > lay.s_t1 + 2.3 and lc6.x < lay.s_c1 - 0.5 and absf(lc6.y) < 1.1:
			slot_block.append(i)
	return {"id": "plaetze", "ok": slot_block.is_empty(), "required": true, "text": "Platz für Bagger und Kipper frei", "bad": slot_block,
		"hint": _bad_text(slot_block, "im Maschinenplatz", lay) + "Im orange umrandeten Platz darf nichts stehen."}


## Checks of a full road closure (#20): no traffic passes, so no separation, detour or priority rules;
## instead barriers across the whole carriageway where traffic arrives.
func _checks_full(lay: SiteLayout, lc_of: Array) -> Array:
	var out: Array = []
	var front := _across_cover(lay, lc_of, lay.s_t0 - 60.0, lay.s_t0 - 0.3)
	out.append({"id": "voll_vorne", "ok": front >= 0.0, "required": true, "text": "Fahrbahn vor dem Arbeitsbereich ganz gesperrt",
		"hint": "Absperrschranken quer über die ganze Fahrbahn (alle Fahrstreifen) vor den Graben stellen."})
	var s_front := front if front >= 0.0 else lay.s_t0
	if lay.oncoming:
		var back := _across_cover(lay, lc_of, lay.s_c1 - 0.5, lay.s_c1 + 60.0)
		out.append({"id": "voll_hinten", "ok": back >= 0.0, "required": true, "text": "Fahrbahn hinter dem Arbeitsbereich ganz gesperrt",
			"hint": "Der Gegenverkehr kommt von der anderen Seite: auch hinter dem Platz für Bagger und Kipper quer über die ganze Fahrbahn absperren."})
	out.append(_check_grube(lay, lc_of))
	out.append(_check_plaetze(lay, lc_of))
	var z250 := false
	var warn := false
	for i in items.size():
		var lc: Vector2 = lc_of[i]
		if items[i].kind == "z250" and lc.x < s_front + 1.0 and lc.x > s_front - 30.0:
			z250 = true
		if items[i].kind == "z123" and lc.x < s_front and lc.x > s_front - 150.0 and lc.y > -lay.lw * 0.5:
			warn = true
	out.append({"id": "z250", "ok": z250, "required": false, "text": "Z 250 an der Sperrung",
		"hint": "Zeichen 250 (Verbot für Fahrzeuge aller Art) an der vorderen Absperrung aufstellen."})
	out.append({"id": "vorwarnung", "ok": warn, "required": false, "text": "Vorwarnung Z 123",
		"hint": "Zeichen 123 am rechten Rand vor der Sperrung aufstellen."})
	return out


## Barriers standing across the carriageway between s_a and s_b on K: s of the first row that covers the
## whole width (gaps under 0.6 m), -1 if none.
func _across_cover(lay: SiteLayout, lc_of: Array, s_a: float, s_b: float) -> float:
	var rows: Array = []   # [s, [Vector2(lat_lo, lat_hi)]]
	for i in items.size():
		var it: Dictionary = items[i]
		if not (it.kind in ["schranke", "fence"]):
			continue
		var lc: Vector2 = lc_of[i]
		if lc.x < s_a or lc.x > s_b or absf(axis_x(float(it.yaw)).dot(lay.lane_dir(lc.x))) > 0.6:
			continue
		var a := lay.lane_coords(it.pos)
		var b := lay.lane_coords((it.pos as Vector2) + axis_x(float(it.yaw)) * ELEM_LEN)
		var span := Vector2(minf(a.y, b.y) - 0.3, maxf(a.y, b.y) + 0.3)
		var hit := false
		for r in rows:
			if absf(float(r[0]) - lc.x) < 2.5:
				(r[1] as Array).append(span)
				hit = true
				break
		if not hit:
			rows.append([lc.x, [span]])
	for r in rows:
		# measured from the far road edge: _first_gap returns a position >= 0 or -1 for "covered"
		var road := road_span(lay, float(r[0]))
		var rel: Array = []
		for sp in r[1]:
			rel.append((sp as Vector2) - Vector2(road.x, road.x))
		if _first_gap(rel, 0.3, road.y - road.x - 0.3) < 0.0:
			return float(r[0])
	return -1.0


func _bad_text(bad: Array, where_txt: String, lay: SiteLayout) -> String:
	if bad.is_empty():
		return ""
	var it: Dictionary = items[bad[0]]
	var more := (" und %d weitere" % (bad.size() - 1)) if bad.size() > 1 else ""
	return "%s (%s)%s %s %s (rot markiert). " % [label(it.kind), where(lay, item_center(it)), more, "stehen" if bad.size() > 1 else "steht", where_txt]


## Position along the closed lane relative to the trench, e.g. "12 m vor dem Graben".
static func where(lay: SiteLayout, p: Vector2) -> String:
	var lc := lay.lane_coords(p)
	if lc.x < lay.s_t0:
		return "%s m vor dem Graben" % _fmt(lay.s_t0 - lc.x)
	if lc.x > lay.s_t1:
		return "%s m hinter dem Graben" % _fmt(lc.x - lay.s_t1)
	return "neben dem Graben"


static func _fmt(x: float) -> String:
	if absf(x - round(x)) < 0.05:
		return str(int(round(x)))
	return ("%.1f" % x).replace(".", ",")


## Distance of an item's footprint (segment for linear elements) to a polyline.
static func _elem_dist(it: Dictionary, pp: PackedVector2Array, cum: PackedFloat32Array) -> float:
	if not is_linear(it.kind):
		return float(Geo.closest_on_polyline(pp, cum, it.pos)[0])
	var a: Vector2 = it.pos
	var b: Vector2 = a + axis_x(float(it.yaw)) * ELEM_LEN
	var best := INF
	for k in 5:
		var q := a.lerp(b, k / 4.0)
		best = minf(best, float(Geo.closest_on_polyline(pp, cum, q)[0]))
	return best


## First s in [a, b] not covered by any interval (x..y); -1 if all covered.
static func _first_gap(cov: Array, a: float, b: float) -> float:
	cov.sort_custom(func(u, v): return u.x < v.x)
	var reach := a
	for c in cov:
		var iv: Vector2 = c
		if iv.y < reach:
			continue
		if iv.x > reach + 0.01:
			return reach
		reach = iv.y
		if reach >= b:
			return -1.0
	return reach if reach < b else -1.0


# ------------------------------------------------------------------------------------------
# Save / load
# ------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var its: Array = []
	for it in items:
		var p: Vector2 = it.pos
		its.append([it.kind, p.x, p.y, float(it.yaw), float(it.get("phase", 0.0)), str(it.get("group", ""))])
	var ls: Array = []
	for l in lines:
		var flat: Array = []
		for p2 in (l as PackedVector2Array):
			flat.append(p2.x)
			flat.append(p2.y)
		ls.append(flat)
	var tr := {}
	for k in traffic:
		var arr: Array = []
		for v in (traffic[k] as Array):
			arr.append([(v as Vector2).x, (v as Vector2).y])
		tr[k] = arr
	return {"v": 1, "custom": custom, "items": its, "lines": ls, "traffic": tr, "full": full}


static func from_dict(d: Dictionary) -> ClosurePlan:
	var p := ClosurePlan.new()
	p.custom = bool(d.get("custom", true))
	p.full = bool(d.get("full", false))
	for a in d.get("items", []):
		var arr: Array = a
		if arr.size() < 4 or not KINDS.has(str(arr[0])):
			continue
		p.items.append(make_item(str(arr[0]), Vector2(float(arr[1]), float(arr[2])), float(arr[3]),
			float(arr[4]) if arr.size() > 4 else 0.0, str(arr[5]) if arr.size() > 5 else ""))
	for f in d.get("lines", []):
		var flat: Array = f
		var pl := PackedVector2Array()
		for k in range(0, flat.size() - 1, 2):
			pl.append(Vector2(float(flat[k]), float(flat[k + 1])))
		if pl.size() >= 2:
			p.lines.append(pl)
	var tr: Dictionary = d.get("traffic", {})
	for k in tr:
		var arr: Array = []
		for q in tr[k]:
			arr.append(Vector2(float(q[0]), float(q[1])))
		if arr.size() >= 2:
			p.traffic[str(k)] = arr
	return p
