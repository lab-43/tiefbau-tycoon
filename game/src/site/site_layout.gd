class_name SiteLayout
extends RefCounted
## Geometry of a pipe-repair site in one lane ("closed lane" K). All positions are lane coordinates
## (s along K in travel direction, lateral offset: + = right/curb side).
##
## head → tail:  [Z123/Z208 signs] [crew van at the curb] [taper with Leitbaken] [Absperrschranke]
##               [gap] [trench] [excavator, faces +s] [pile zone] [truck load/dump slot] [tail taper]
## Traffic of K is shifted into lane K2 (oncoming lane → bottleneck with 208/308 priority, or the
## neighbouring lane of the same direction → zipper zone). Trucks reverse in from the tail.

const TAPER := 12.0
const TAPER_OUT := 6.0
const HEAD_GAP := 2.5
const CURB := 2.2

var net: RoadNet
var key := -1
var key2 := -1
var oncoming := false
var lw := 3.0
var lw2 := 3.0
var shift := 3.0
var s0 := 0.0
var L := 4.0
var W := 1.3
var depth := 1.8
var pipe_d := 0.3
var len_k := 0.0
var len_k2 := 0.0
var _g: Array
var _g2: Array
# derived positions on K
var s_c0 := 0.0
var s_t0 := 0.0
var s_t1 := 0.0
var s_tc := 0.0
var s_exc := 0.0
var s_c1 := 0.0
var s_taper1 := 0.0
var s_det0 := 0.0
var s_det1 := 0.0
var s_van := 0.0
var s2_a := 0.0
var s2_b := 0.0
# traffic geometry of the closure (defaults from the standard layout; a player plan moves them, #9)
var p_full0 := 0.0             # s where the detour reaches the full shift into K2
var p_full1 := 0.0             # s where it starts to swing back
var obst0 := 0.0               # blocked range of K
var obst1 := 0.0
var error := ""

# machine geometry (from the extracted assets; fallbacks if missing)
var exc_turret_z := 0.17
var exc_front := 2.17
var tip_rear := 4.40
var tip_front := 4.03


func setup(n: RoadNet, k: int, start_s: float, length: float, width: float, dep: float, pipe: float) -> bool:
	net = n
	key = k
	s0 = start_s
	L = length
	W = width
	depth = dep
	pipe_d = pipe
	_g = net.lane_geo[key]
	len_k = (_g[1] as PackedFloat32Array)[(_g[1] as PackedFloat32Array).size() - 1]
	var e: Dictionary = net.edges[key >> 4]
	lw = e.lw
	var dir := (key >> 3) & 1
	var lane := key & 7
	var nlanes := net.lane_count(key >> 4, dir)
	if lane != nlanes - 1:
		error = "nicht rechter Fahrstreifen"
		return false
	if nlanes >= 2:
		key2 = RoadNet.lane_key(key >> 4, dir, lane - 1)
		oncoming = false
	elif not e.oneway and net.lane_count(key >> 4, 1 - dir) >= 1:
		key2 = RoadNet.lane_key(key >> 4, 1 - dir, 0)
		oncoming = true
	else:
		error = "kein Ausweichstreifen"
		return false
	if not net.lane_geo.has(key2):
		error = "Ausweichstreifen fehlt"
		return false
	_g2 = net.lane_geo[key2]
	len_k2 = (_g2[1] as PackedFloat32Array)[(_g2[1] as PackedFloat32Array).size() - 1]
	lw2 = lw
	var meta := VehicleModels.load_meta("truck_tipper")
	if meta.has("bbox_max"):
		tip_rear = float(meta.bbox_max[2])
		tip_front = -float(meta.bbox_min[2])
	# positions
	s_c0 = s0 + TAPER
	s_t0 = s_c0 + HEAD_GAP
	s_t1 = s_t0 + L
	s_tc = s_t1 + 2.9
	s_exc = s_tc + exc_turret_z
	s_c1 = dump_s(tip_rear) + tip_front + 1.0
	s_taper1 = s_c1 + TAPER_OUT
	s_det0 = s0 - 8.0
	s_det1 = s_taper1 + 5.0
	s_van = s0 - 20.0
	p_full0 = s_c0 - 1.0
	p_full1 = s_c1
	obst0 = s0 + 1.0
	obst1 = s_taper1 - 1.0
	if s0 < 34.0:
		error = "zu nah an der Kreuzung (Anfang)"
		return false
	if s_det1 + 32.0 > len_k:
		error = "zu nah an der Kreuzung (Ende)"
		return false
	# K2 range of the zone
	var k2 := _k2_for(s_det0, s_det1)
	if k2.error != "":
		error = k2.error
		return false
	s2_a = k2.s2_a
	s2_b = k2.s2_b
	shift = k2.shift
	# curvature limits
	var d0 := lane_dir(s_det0)
	var d1 := lane_dir(s_det1)
	if absf(d0.angle_to(d1)) > deg_to_rad(35.0):
		error = "zu kurvig"
		return false
	if absf(lane_dir(s_t0).angle_to(lane_dir(s_t1))) > deg_to_rad(6.0):
		error = "Graben in der Kurve"
		return false
	return true


# ------------------------------------------------------------------------------------------
# Lane sampling
# ------------------------------------------------------------------------------------------

func lane_pt(s: float, lat := 0.0) -> Vector2:
	var smp := Geo.sample(_g[0], _g[1], clampf(s, 0.0, len_k))
	var p: Vector2 = smp[0]
	var d: Vector2 = smp[1]
	if s > len_k:
		p += d * (s - len_k)
	elif s < 0.0:
		p += d * s
	return p + Geo.right_of(d) * lat


func lane_dir(s: float) -> Vector2:
	return Geo.sample(_g[0], _g[1], clampf(s, 0.0, len_k))[1]


func lane2_pt(s: float, lat := 0.0) -> Vector2:
	var smp := Geo.sample(_g2[0], _g2[1], clampf(s, 0.0, len_k2))
	return (smp[0] as Vector2) + Geo.right_of(smp[1]) * lat


func lane2_dir(s: float) -> Vector2:
	return Geo.sample(_g2[0], _g2[1], clampf(s, 0.0, len_k2))[1]


static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func pose(s: float, lat := 0.0) -> Dictionary:
	return {"pos": lane_pt(s, lat), "yaw": yaw_of(lane_dir(s)), "s": s, "lat": lat}


## Polyline along K from sa to sb with a lateral offset profile function f(s) -> lat.
func lane_poly(sa: float, sb: float, lat_fn: Callable, step := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(2, int(ceil(absf(sb - sa) / step)))
	for i in n + 1:
		var s := lerpf(sa, sb, float(i) / n)
		out.append(lane_pt(s, lat_fn.call(s)))
	return out


# ------------------------------------------------------------------------------------------
# Slots
# ------------------------------------------------------------------------------------------

func load_s(rear_ext: float) -> float:
	return s_exc + exc_front + 0.75 + rear_ext


func dump_s(rear_ext: float) -> float:
	return load_s(rear_ext) + 3.2


func pile_center() -> Vector2:
	return lane_pt(s_exc + exc_front + 0.75 + 1.6, 0.0)


func van_pose() -> Dictionary:
	return pose(s_van, CURB)


func crew_point() -> Vector2:
	return lane_pt(s_van, CURB + 1.6)


func stage_s(i: int) -> float:
	return s_det1 + 10.0 + i * 14.0


## Lowbed parks after the tail so that its ramp lands behind the closure; returns the tractor origin s.
func lowbed_s(back_to_ramp_end: float) -> float:
	return tail_s() + 3.0 + back_to_ramp_end


## End of the closure on K (standard: end of the tail taper; a player plan may reach further).
func tail_s() -> float:
	return maxf(s_taper1, obst1 + 1.0)


func trench_center() -> Vector2:
	return lane_pt((s_t0 + s_t1) * 0.5, 0.0)


func trench_dir() -> Vector2:
	return lane_dir((s_t0 + s_t1) * 0.5)


func closure_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	for i in n + 1:
		pts.append(lane_pt(lerpf(s0 - 2.0, s_taper1 + 2.0, float(i) / n), -lw * 0.5 - 0.3))
	for i in range(n, -1, -1):
		pts.append(lane_pt(lerpf(s0 - 2.0, s_taper1 + 2.0, float(i) / n), lw * 0.5 + 1.5))
	return pts


# ------------------------------------------------------------------------------------------
# Traffic geometry
# ------------------------------------------------------------------------------------------

func _shift_profile(s: float) -> float:
	return _profile(s, s_det0, p_full0, p_full1, s_det1)


static func _profile(s: float, d0: float, f0: float, f1: float, d1: float) -> float:
	var a := clampf((s - d0) / maxf(0.5, f0 - d0), 0.0, 1.0)
	var b := clampf((d1 - s) / maxf(0.5, d1 - f1), 0.0, 1.0)
	var t := minf(a, b)
	return t * t * (3.0 - 2.0 * t)


## Path of K traffic around the closure (into K2).
func detour_pts() -> PackedVector2Array:
	return lane_poly(s_det0, s_det1, func(s): return -shift * _shift_profile(s), 1.0)


## Own path of K2 traffic through the bottleneck/zipper zone.
func zone2_pts() -> PackedVector2Array:
	return Geo.sub_polyline(_g2[0], _g2[1], s2_a, s2_b)


## K2 range and lateral shift for a detour from d0 to d1 on K. {error, s2_a, s2_b, shift}
func _k2_for(d0: float, d1: float) -> Dictionary:
	var pa := lane_pt(d1)
	var pb := lane_pt(d0)
	var ca := Geo.closest_on_polyline(_g2[0], _g2[1], pa)
	var cb := Geo.closest_on_polyline(_g2[0], _g2[1], pb)
	var out := {"error": "", "s2_a": 0.0, "s2_b": 0.0, "shift": 0.0}
	if oncoming:
		out.s2_a = ca[1]
		out.s2_b = cb[1]
	else:
		out.s2_a = cb[1]
		out.s2_b = ca[1]
	if ca[0] > lw * 2.2 or cb[0] > lw * 2.2:
		out.error = "Gegenfahrstreifen zu weit entfernt"
	elif out.s2_a < 3.0 or out.s2_b > len_k2 - 3.0 or out.s2_b - out.s2_a < 20.0:
		out.error = "Gegenfahrstreifen zu kurz"
	out.shift = (pa.distance_to(Vector2(ca[2])) + pb.distance_to(Vector2(cb[2]))) * 0.5
	return out


# ------------------------------------------------------------------------------------------
# Traffic geometry of a player-designed closure (#9)
# ------------------------------------------------------------------------------------------

## Lane coordinates of a map point: Vector2(s along K, lateral offset, + = right/curb side).
func lane_coords(p: Vector2) -> Vector2:
	var r: Array = Geo.closest_on_polyline(_g[0], _g[1], p)
	var s: float = r[1]
	var q: Vector2 = r[2]
	var d := lane_dir(s)
	var lat := (p - q).dot(Geo.right_of(d))
	# beyond the ends of K: continue along the end direction
	if s <= 0.001:
		s = (p - q).dot(d)
	elif s >= len_k - 0.001:
		s = len_k + (p - q).dot(d)
	return Vector2(s, lat)


## Inside the closed lane K (blocks it). Items snapped exactly onto a lane edge count as inside.
func in_lane(lc: Vector2) -> bool:
	return lc.x >= 0.0 and lc.x <= len_k and absf(lc.y) <= lw * 0.5 + 0.05


func current_extent() -> Dictionary:
	return {"det0": s_det0, "det1": s_det1, "full0": p_full0, "full1": p_full1, "obst0": obst0, "obst1": obst1,
		"van": s_van, "s2_a": s2_a, "s2_b": s2_b, "shift": shift}


func default_extent() -> Dictionary:
	var k2 := _k2_for(s0 - 8.0, s_taper1 + 5.0)
	return {"det0": s0 - 8.0, "det1": s_taper1 + 5.0, "full0": s_c0 - 1.0, "full1": s_c1, "obst0": s0 + 1.0,
		"obst1": s_taper1 - 1.0, "van": s0 - 20.0, "s2_a": k2.s2_a, "s2_b": k2.s2_b, "shift": k2.shift}


## Traffic geometry for the items of a player plan: the detour starts 8 m before the first item that
## stands in K and reaches the full shift where the plan blocks K up to its traffic-side edge. Kept
## within limits so the crew van, the machine slots and the waiting spots still fit.
func extent_for(items: Array) -> Dictionary:
	var ext := default_extent()
	var a := INF
	var b := -INF
	var e0 := INF
	var e1 := -INF
	for it in items:
		var lc := lane_coords(ClosurePlan.item_center(it))
		if not in_lane(lc):
			continue
		a = minf(a, lc.x)
		b = maxf(b, lc.x)
		if lc.y < -lw * 0.5 + 0.7:
			e0 = minf(e0, lc.x)
			e1 = maxf(e1, lc.x)
	if a == INF:
		return ext
	var a_eff := clampf(a, maxf(s0 - 15.0, 35.0), s_c0 - 4.0)
	var d0 := a_eff - 8.0
	var d1 := minf(clampf(b, s_c1 + 2.0, s_taper1 + 15.0) + 5.0, maxf(s_taper1 + 5.0, len_k - 32.0))
	var b_eff := minf(clampf(b, s_c1 + 2.0, s_taper1 + 15.0), d1 - 5.0)
	var f0 := clampf(e0 if e0 < INF else s_c0 - 1.0, a_eff + 3.0, s_c0 - 1.0)
	var f1 := clampf(e1 if e1 > -INF else s_c1, s_c1, maxf(s_c1, minf(b_eff - 2.0, d1 - 6.0)))
	var k2 := _k2_for(d0, d1)
	if k2.error != "":
		return ext
	return {"det0": d0, "det1": d1, "full0": f0, "full1": f1, "obst0": a_eff + 1.0, "obst1": b_eff - 1.0,
		"van": minf(s0 - 20.0, d0 - 12.0), "s2_a": k2.s2_a, "s2_b": k2.s2_b, "shift": k2.shift}


## How far a player plan may extend the closure on K: Vector2(earliest start, latest end).
func extent_limits() -> Vector2:
	var b_max := minf(s_taper1 + 15.0, maxf(s_taper1 + 5.0, len_k - 32.0) - 5.0)
	return Vector2(maxf(s0 - 15.0, 35.0), b_max)


func apply_extent(ext: Dictionary) -> void:
	s_det0 = ext.det0
	s_det1 = ext.det1
	p_full0 = ext.full0
	p_full1 = ext.full1
	obst0 = ext.obst0
	obst1 = ext.obst1
	s_van = ext.van
	s2_a = ext.s2_a
	s2_b = ext.s2_b
	shift = ext.shift


func detour_pts_for(ext: Dictionary) -> PackedVector2Array:
	var d0: float = ext.det0
	var d1: float = ext.det1
	var f0: float = ext.full0
	var f1: float = ext.full1
	var sh: float = ext.shift
	return lane_poly(d0, d1, func(s): return -sh * _profile(s, d0, f0, f1, d1), 1.0)


func zone2_pts_for(ext: Dictionary) -> PackedVector2Array:
	return Geo.sub_polyline(_g2[0], _g2[1], ext.s2_a, ext.s2_b)


# ------------------------------------------------------------------------------------------
# Closure kit
# ------------------------------------------------------------------------------------------

## Items in setup order: {kind, pos: Vector2, yaw, phase, group}. group: signs | taper | head | line | tail | pit
func items() -> Array:
	var out: Array = []
	var d0 := lane_dir(s0)
	var side := lw * 0.5 + 0.7
	out.append(_item("z123", lane_pt(maxf(3.0, s0 - 48.0), side), yaw_of(lane_dir(maxf(3.0, s0 - 48.0))), "signs"))
	out.append(_item("z208", lane_pt(maxf(3.0, s0 - 30.0), side), yaw_of(lane_dir(maxf(3.0, s0 - 30.0))), "signs"))
	var k2_sign_kind := "z308" if oncoming else ""
	# standard positions: from the default K2 range (a player plan may have moved s2_a)
	var s2a_def: float = _k2_for(s0 - 8.0, s_taper1 + 5.0).s2_a
	var s2_123 := maxf(3.0, s2a_def - 45.0)
	out.append({"kind": "z123", "pos": lane2_pt(s2_123, lw2 * 0.5 + 0.7), "yaw": yaw_of(lane2_dir(s2_123)), "phase": 0.0, "group": "signs"})
	if k2_sign_kind != "":
		var s2_308 := maxf(3.0, s2a_def - 24.0)
		out.append({"kind": "z308", "pos": lane2_pt(s2_308, lw2 * 0.5 + 0.7), "yaw": yaw_of(lane2_dir(s2_308)), "phase": 0.0, "group": "signs"})
	# taper (Verschwenkung) with running warning lights
	var n_taper := 5
	for i in n_taper:
		var t := float(i) / (n_taper - 1)
		var s := lerpf(s0, s_c0, t)
		var lat := lerpf(lw * 0.5 - 0.25, -lw * 0.5 + 0.3, t)
		var it := _item("bake", lane_pt(s, lat), yaw_of(lane_dir(s)), "taper")
		it.phase = 0.12 * i
		out.append(it)
	# head barrier across the closed lane
	var left := -lw * 0.5 + 0.3
	var right := lw * 0.5 - 0.05
	var width := right - left
	var panels := maxi(1, int(ceil(width / 2.05)))
	var step := (width - 2.05) / maxf(1.0, panels - 1) if panels > 1 else 0.0
	for i in panels:
		var lat2 := left + i * step
		out.append(_item("schranke", lane_pt(s_c0 + 0.6, lat2), yaw_of(lane_dir(s_c0 + 0.6)), "head"))
	# longitudinal Leitbaken along the traffic side
	var s := s_c0 + 4.5
	while s < s_c1 - 0.5:
		out.append(_item("bake", lane_pt(s, -lw * 0.5 + 0.3), yaw_of(lane_dir(s)), "line"))
		s += 5.0
	for i in 3:
		var t2 := float(i + 1) / 3.0
		var s2 := lerpf(s_c1, s_taper1, t2)
		var lat3 := lerpf(-lw * 0.5 + 0.3, lw * 0.5 - 0.25, t2)
		out.append(_item("bake", lane_pt(s2, lat3), yaw_of(lane_dir(s2)), "tail"))
	# fall protection around the pit (Absperrschranken without lights)
	var dl := lane_dir((s_t0 + s_t1) * 0.5)
	var fence_yaw := yaw_of(Geo.left_of(dl))
	for lat4 in [-W * 0.5 - 0.35, W * 0.5 + 0.35]:
		var sa := s_t0 - 0.35
		while sa < s_t1 + 0.1:
			out.append(_item("fence", lane_pt(sa, lat4), fence_yaw, "pit"))
			sa += 2.05
	out.append(_item("fence", lane_pt(s_t0 - 0.55, -W * 0.5 - 0.3), yaw_of(lane_dir(s_t0)), "pit"))
	return out


func _item(kind: String, p: Vector2, yaw: float, group: String) -> Dictionary:
	return {"kind": kind, "pos": p, "yaw": yaw, "phase": 0.0, "group": group}


## Yellow temporary marking along the closure boundary.
func yellow_line() -> PackedVector2Array:
	var edge := -lw * 0.5 + 0.08
	var curb := lw * 0.5 - 0.1
	return lane_poly(s0, s_taper1, func(s):
		if s < s_c0:
			return lerpf(curb, edge, (s - s0) / (s_c0 - s0))
		if s > s_c1:
			return lerpf(edge, curb, (s - s_c1) / (s_taper1 - s_c1))
		return edge, 1.0)
