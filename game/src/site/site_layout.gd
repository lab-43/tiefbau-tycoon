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
const TWO_WAY_GAP := 2.5       # m between the two traffic paths for both directions at once (#19)
const EXC_REACH_DIG := 7.4     # m from the turret axis to the trench floor at its far end (measured with the rig, #22)
const EXC_REACH := 8.2         # m from the turret axis to a tipper body or the top of the pile
const EXC_REAR := 2.0          # m from the turret axis back to the excavator's rear (keep it off the trench)
# placing anywhere (#33): only the pit itself has to fit; the closure template squeezes to the lane
const PIT_GAP := 1.5           # m between the pit and either end of the lane (the junction area)
const HEAD_MIN := 0.5          # nothing of the closure on K before this s (the lane starts at the junction)
const REV_ROOM := 8.0          # m on K after the detour where tippers and the excavator stop to reverse in
const TAPER_OUT_MIN := 2.0
const DET_OUT_MIN := 1.0
const TRENCH_BEND := 12.0      # degrees the lane may turn along the trench (it is dug as a straight box)
const VAN_APPR_MIN := 6.0      # shortest pull-over of the crew van to its kerb spot
const VAN_EXIT_GAP := 4.5      # m between a van in front of the closure and the start of the detour
const VAN_EXIT_MIN := 3.0      # m a van behind the site needs to pull out into the lane
const VAN_FRONT := 2.6         # crew van: origin to front / rear (kerb spots, #33)
const VAN_REAR := 2.9
const STAGE_SLOT := 12.0       # kerb length of one waiting vehicle away from K (rear to front)
const LOWBED_FRONT := 6.5      # low-loader: tractor origin to its front

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
var k_ctrl: Array = []         # traffic path of K: Vector2(s, lateral) control points on K (#19)
var k2_ctrl: Array = []        # traffic path of K2: Vector2(s2, lateral) control points on K2
var two_way := false           # both paths far enough apart: no bottleneck/zipper needed
# machine and parking spots (#22): defaults from the standard layout, a player plan moves them
var exc_lat := 0.0             # lateral offset of the excavator slot (its s is s_exc, turret at s_tc)
var load_rear := 0.0           # s of the tipper's rear end while the excavator loads it
var load_lat := 0.0
var pile_s := 0.0              # centre of the material pile; the tipper dumps with its rear 1.6 m behind it
var pile_lat := 0.0
var stage0 := -1.0             # first waiting spot behind the site (-1: automatic, 10 m after the detour)
var _def_tc := 0.0
var error := ""
var taper_out := TAPER_OUT     # length of the tail taper (shorter near the end of the lane, #33)
var det_out := 5.0             # m from the tail taper to the end of the detour
var squeezed := false          # the template is shorter than the standard one (close to a junction)
var anchor_s := 0.0            # the s0 the job was made with (trench at anchor_s + TAPER + HEAD_GAP)
var _def := {}                 # traffic geometry of the template (setup), the base of every player plan
# the straight lanes into and out of K (kerb side) where vehicles park when K is too short (#33)
var pre_key := -1
var pre_len := 0.0
var post_key := -1
var post_len := 0.0
var kerb := {}                 # {van: slot (only if not on K), stage: [slot…], lowbed: slot}, see plan_kerb()

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
	# saved jobs keep the key of the map build they were made on; a missing key crashes release builds (#23)
	if not net.lane_geo.has(key) or (key >> 4) >= net.edges.size():
		error = "Straße nicht gefunden"
		return false
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
	# positions: the pit stays where the job put it, the template around it squeezes to the lane (#33)
	anchor_s = start_s
	squeezed = false
	s_t0 = start_s + TAPER + HEAD_GAP
	s_t1 = s_t0 + L
	if s_t0 < PIT_GAP or s_t1 > len_k - PIT_GAP:
		error = "Grube ragt in die Kreuzung"
		return false
	if absf(lane_dir(s_t0).angle_to(lane_dir(s_t1))) > deg_to_rad(TRENCH_BEND):
		error = "Graben in einer engen Kurve"
		return false
	s_c0 = maxf(s_t0 - HEAD_GAP, minf(HEAD_MIN + 0.3, s_t0 - 0.6))
	s0 = clampf(start_s, HEAD_MIN, s_c0)
	if s0 > start_s + 0.01:
		squeezed = true
	s_tc = s_t1 + 2.9
	s_exc = s_tc + exc_turret_z
	_def_tc = s_tc
	load_rear = s_exc + exc_front + 0.75
	pile_s = load_rear + 1.6
	s_c1 = dump_s(tip_rear) + tip_front + 1.0
	# behind the work area: tail taper, end of the detour, then room to stop and reverse in
	var room := len_k - 0.5 - REV_ROOM - s_c1
	var need := TAPER_OUT_MIN + DET_OUT_MIN
	if room < need:
		error = "Hinter der Grube fehlen %d m: Bagger und Kipper stehen dort und fahren von hinten rückwärts hinein" % int(ceil(need - room))
		return false
	var extra := room - need
	taper_out = TAPER_OUT_MIN + clampf(extra, 0.0, TAPER_OUT - TAPER_OUT_MIN)
	det_out = DET_OUT_MIN + clampf(extra - (TAPER_OUT - TAPER_OUT_MIN), 0.0, 5.0 - DET_OUT_MIN)
	if extra < (TAPER_OUT - TAPER_OUT_MIN) + (5.0 - DET_OUT_MIN):
		squeezed = true
	s_taper1 = s_c1 + taper_out
	s_det1 = s_taper1 + det_out
	s_det0 = maxf(HEAD_MIN, s0 - 8.0)
	_find_neighbours()
	s_van = van_default()
	p_full0 = maxf(s_c0 - 1.0, s_det0 + 1.0)
	p_full1 = s_c1
	obst0 = maxf(s0 + 1.0, s_det0 + 0.5)
	obst1 = s_taper1 - 1.0
	# K2 range of the zone
	var k2 := _k2_for(s_det0, s_det1)
	if k2.error != "":
		error = k2.error
		return false
	s2_a = k2.s2_a
	s2_b = k2.s2_b
	shift = k2.shift
	k_ctrl = auto_k_ctrl(current_extent())
	k2_ctrl = [Vector2(s2_a, 0.0), Vector2(s2_b, 0.0)]
	_def = {"det0": s_det0, "det1": s_det1, "full0": p_full0, "full1": p_full1, "obst0": obst0, "obst1": obst1,
		"van": s_van, "s2_a": s2_a, "s2_b": s2_b, "shift": shift}
	kerb = plan_kerb(current_extent())
	if s_van < 0.0 and (kerb.van as Dictionary).is_empty():
		error = "kein Platz für den Kolonnenbus, auch nicht in den Nachbarstraßen"
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
	return load_rear + rear_ext


func dump_s(rear_ext: float) -> float:
	return pile_s + 1.6 + rear_ext


func pile_center() -> Vector2:
	return lane_pt(pile_s, pile_lat)


func turret_pt() -> Vector2:
	return lane_pt(s_tc, exc_lat)


func van_pose() -> Dictionary:
	if s_van < 0.0 and not (kerb.get("van", {}) as Dictionary).is_empty():
		var sp := van_spot()
		return {"pos": kerb_pt(sp.key, sp.s, CURB), "yaw": yaw_of(kerb_dir(sp.key, sp.s)), "s": s_van, "lat": CURB}
	return pose(s_van, CURB)


## Where the crew van parks: {key, s (its origin), appr (pull-over length)} – on K, or on a lane next to it (#33).
func van_spot() -> Dictionary:
	if s_van >= 0.0 or (kerb.get("van", {}) as Dictionary).is_empty():
		return {"key": key, "s": s_van, "appr": van_approach()}
	return slot_drive(kerb.van, VAN_REAR)


func van_dir() -> Vector2:
	var sp := van_spot()
	return kerb_dir(sp.key, sp.s)


## Kerb spot of the crew van on K (#33): 20 m in front of the taper where there is room, closer to
## the closure on short lanes, otherwise behind the site after the reversing room. -1: no room on K.
func van_default() -> float:
	var up := minf(s0 - 20.0, s_det0 - VAN_EXIT_GAP)
	if up >= HEAD_MIN + VAN_APPR_MIN:
		return up
	var down := s_det1 + REV_ROOM + 3.0
	if down + 3.0 + VAN_EXIT_MIN <= len_k - 0.5:
		return down
	return -1.0


## Metres the crew van pulls over before its spot (at most 12, never from inside the detour).
func van_approach() -> float:
	if s_van > s_det1:
		return clampf(s_van - s_det1 - 0.5, VAN_APPR_MIN, 12.0)
	return clampf(s_van - HEAD_MIN, VAN_APPR_MIN, 12.0)


func crew_point() -> Vector2:
	var sp := van_spot()
	return kerb_pt(sp.key, sp.s, CURB + 1.6)


func stage_s(i: int) -> float:
	return (stage0 if stage0 >= 0.0 else s_det1 + 10.0) + i * 14.0


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


# ------------------------------------------------------------------------------------------
# Kerb spots for parked vehicles (#33): on K where there is room, else on the lanes next to it
# ------------------------------------------------------------------------------------------

## The straight continuation lanes into and out of K (the kerb lane of that road), if there are any.
func _find_neighbours() -> void:
	var pre := _neighbour(net.lane_in.get(key, []), true)
	var post := _neighbour(net.lane_out.get(key, []), false)
	pre_key = pre.get("key", -1)
	pre_len = pre.get("len", 0.0)
	post_key = post.get("key", -1)
	post_len = post.get("len", 0.0)


func _neighbour(conns: Array, incoming: bool) -> Dictionary:
	var best := {}
	var best_score := INF
	for ci in conns:
		var c: Dictionary = net.connectors[ci]
		var other: int = c.from if incoming else c.to
		var oe := other >> 4
		var od := (other >> 3) & 1
		if oe == (key >> 4) or oe == (key2 >> 4) or oe == net.hq_edge:
			continue
		var e: Dictionary = net.edges[oe]
		if e.bridge or e.get("tunnel", false) or e.get("under", false) or e.cls in ["motorway", "motorway_link"]:
			continue
		var k := RoadNet.lane_key(oe, od, net.lane_count(oe, od) - 1)
		if not net.lane_geo.has(k):
			continue
		var cum: PackedFloat32Array = net.lane_geo[k][1]
		var ln: float = cum[cum.size() - 1]
		var score: float = {"S": 0.0, "R": 30.0, "L": 60.0}.get(c.turn, 1000.0) - minf(ln, 60.0) * 0.2
		if score < best_score:
			best_score = score
			best = {"key": k, "len": ln}
	return best


func kerb_pt(k: int, s: float, lat := 0.0) -> Vector2:
	if k == key:
		return lane_pt(s, lat)
	var g: Array = net.lane_geo[k]
	var smp := Geo.sample(g[0], g[1], s)
	return (smp[0] as Vector2) + Geo.right_of(smp[1]) * lat


func kerb_dir(k: int, s: float) -> Vector2:
	if k == key:
		return lane_dir(s)
	var g: Array = net.lane_geo[k]
	return Geo.sample(g[0], g[1], s)[1]


func kerb_len(k: int) -> float:
	if k == key:
		return len_k
	var cum: PackedFloat32Array = net.lane_geo[k][1]
	return cum[cum.size() - 1]


## Kerb runs for an extent: on K in front of the closure (in and out before the detour) and behind it
## (after the reversing room), on the lane into K (not right at the junction) and the lane out of it.
func _kerb_runs(ext: Dictionary) -> Dictionary:
	var runs := {}
	runs["up"] = {"key": key, "a": HEAD_MIN, "b": float(ext.det0) - VAN_EXIT_GAP}
	runs["down"] = {"key": key, "a": float(ext.det1) + REV_ROOM, "b": len_k - 0.5}
	if pre_key >= 0:
		runs["pre"] = {"key": pre_key, "a": 0.5, "b": pre_len - 8.0}
	if post_key >= 0:
		runs["post"] = {"key": post_key, "a": 6.0, "b": post_len - 0.5}
	return runs


## First free kerb slot of length ln in run id (the pull-over needs VAN_APPR_MIN m before the rear, the
## pull-out VAN_EXIT_MIN m after the front). from_end: as close to the run's end as possible.
## {key, rear, len, a} or {} if it does not fit.
static func _slot(runs: Dictionary, id: String, ln: float, from_end: bool, used: Array) -> Dictionary:
	if not runs.has(id):
		return {}
	var run: Dictionary = runs[id]
	var lo: float = run.a + VAN_APPR_MIN
	var hi: float = run.b - VAN_EXIT_MIN - ln
	if hi < lo:
		return {}
	var n := int(floor(hi - lo)) + 1
	for i in n:
		var r: float = (hi - i) if from_end else (lo + i)
		var free := true
		for u in used:
			if int(u[0]) == int(run.key) and r < float(u[2]) + 1.0 and r + ln > float(u[1]) - 1.0:
				free = false
				break
		if free:
			return {"key": run.key, "rear": r, "len": ln, "a": run.a, "run": id}
	return {}


## Where a vehicle drives for a kerb slot: {key, s (its origin), appr}; rear_ext: origin to its rear.
static func slot_drive(sl: Dictionary, rear_ext: float) -> Dictionary:
	var s: float = float(sl.rear) + rear_ext
	return {"key": sl.key, "s": s, "appr": clampf(s - float(sl.a), VAN_APPR_MIN, 12.0)}


## Kerb slots for an extent: the crew van (only if it has no spot on K), three waiting spots and the
## low-loader. Behind the site on K first (as the standard layout), then the lane out of K, in front
## of the closure and the lane into K.
func plan_kerb(ext: Dictionary) -> Dictionary:
	var runs := _kerb_runs(ext)
	var used: Array = []
	var out := {"van": {}, "stage": [], "lowbed": {}}
	var van_s: float = ext.get("van", -1.0)
	if van_s >= 0.0:
		used.append([key, van_s - VAN_REAR, van_s + VAN_FRONT])
	else:
		for id in ["pre", "post"]:
			var sv := _slot(runs, id, VAN_REAR + VAN_FRONT, id == "pre", used)
			if not sv.is_empty():
				out.van = sv
				used.append([sv.key, sv.rear, sv.rear + sv.len])
				break
	var st0: float = float(ext.get("slots", {}).get("stage", -1.0))
	for i in 3:
		var sl := {}
		# the standard waiting spot behind the site, 14 m apart
		var r: float = (st0 if st0 >= 0.0 else float(ext.det1) + 10.0) + i * 14.0
		if r - 8.0 >= float(ext.det1) + 0.5 and r + 10.0 <= len_k - 0.5:
			sl = {"key": key, "rear": r, "len": STAGE_SLOT, "a": float(ext.det1) + 0.5, "run": "down"}
		else:
			for id in ["post", "up", "pre"]:
				sl = _slot(runs, id, STAGE_SLOT, id != "post", used)
				if not sl.is_empty():
					break
		if not sl.is_empty():
			used.append([sl.key, sl.rear, sl.rear + sl.len])
		out.stage.append(sl)
	# low-loader: its ramp lands behind the closure (the machine backs off it and reverses in), else on
	# the lane out of K, else in front of the site
	var back := 21.5
	var lr: float = maxf(float(ext.get("obst1", s_taper1)) + 1.0, s_taper1) + 3.0
	if lr + back - 12.0 >= float(ext.det1) + 0.5 and lr + back + LOWBED_FRONT <= len_k - 0.5:
		out.lowbed = {"key": key, "rear": lr, "len": back + LOWBED_FRONT, "a": float(ext.det1) + 0.5, "run": "down"}
	else:
		for id in ["post", "up", "pre", "down"]:
			var sb := _slot(runs, id, back + LOWBED_FRONT, id in ["up", "pre"], [])
			if not sb.is_empty():
				out.lowbed = sb
				break
	return out


## Waiting spot i for a vehicle (rear_ext: origin to its rear): {key, s, appr}, {} if there is none.
## More than three waiting vehicles queue on behind the last spot.
func stage_spot(i: int, rear_ext: float) -> Dictionary:
	var st: Array = kerb.get("stage", [])
	var n := mini(i, st.size() - 1)
	while n >= 0 and (st[n] as Dictionary).is_empty():
		n -= 1
	if n < 0:
		return {}
	var sl: Dictionary = st[n]
	var d := slot_drive(sl, rear_ext)
	if i > n:
		var away := -1.0 if str(sl.run) in ["up", "pre"] else 1.0
		d.s = float(d.s) + away * 14.0 * (i - n)
	return d


## Low-loader spot: {key, s (tractor origin), appr} for a trailer whose ramp end lies back m behind it.
func lowbed_spot(back: float) -> Dictionary:
	var sl: Dictionary = kerb.get("lowbed", {})
	if sl.is_empty():
		return {}
	var d := slot_drive(sl, back)
	# the slot was planned for a 21.5 m trailer: keep the tractor where it was planned if this one is longer
	d.s = minf(float(d.s), float(sl.rear) + float(sl.len) - LOWBED_FRONT)
	return d


## Area of the site on K (the closure and the machine spots, #22 may move them off the lane centre).
func closure_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	var a := minf(s0, obst0) - 2.0
	var b := maxf(maxf(s_taper1, tail_s()), pile_s + 1.6 + tip_rear + tip_front) + 2.0
	var lo := minf(-lw * 0.5 - 0.3, minf(minf(exc_lat, load_lat), pile_lat) - 1.6)
	var hi := maxf(lw * 0.5 + 1.5, maxf(maxf(exc_lat, load_lat), pile_lat) + 1.6)
	for i in n + 1:
		pts.append(lane_pt(lerpf(a, b, float(i) / n), lo))
	for i in range(n, -1, -1):
		pts.append(lane_pt(lerpf(a, b, float(i) / n), hi))
	return pts


# ------------------------------------------------------------------------------------------
# Traffic geometry
# ------------------------------------------------------------------------------------------

## Path of K traffic around the closure (into K2, or where the player laid it).
func detour_pts() -> PackedVector2Array:
	return ctrl_path(k_ctrl)


## Own path of K2 traffic through the bottleneck/zipper zone.
func zone2_pts() -> PackedVector2Array:
	return ctrl2_path(k2_ctrl)


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
	# near a junction the zone simply ends with K2 (#33)
	out.s2_a = maxf(out.s2_a, HEAD_MIN)
	out.s2_b = minf(out.s2_b, len_k2 - HEAD_MIN)
	if out.error == "" and out.s2_b - out.s2_a < 2.0:
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
		"van": s_van, "s2_a": s2_a, "s2_b": s2_b, "shift": shift, "k_ctrl": k_ctrl.duplicate(), "k2_ctrl": k2_ctrl.duplicate(),
		"two_way": two_way, "slots": {"tc": s_tc, "exc_lat": exc_lat, "load_rear": load_rear, "load_lat": load_lat,
		"pile_s": pile_s, "pile_lat": pile_lat, "stage": stage0}}


func default_extent() -> Dictionary:
	var ext := _def.duplicate()
	_finish_extent(ext, {})
	_finish_slots(ext, {})
	return ext


# ------------------------------------------------------------------------------------------
# Traffic paths as control points (#19): the automatic detour or the one the player laid
# ------------------------------------------------------------------------------------------

## Control points of the automatic detour (the same curve as the old smoothstep profile).
static func auto_k_ctrl(ext: Dictionary) -> Array:
	var sh := -float(ext.shift)
	return [Vector2(ext.det0, 0.0), Vector2(ext.full0, sh), Vector2(ext.full1, sh), Vector2(ext.det1, 0.0)]


## Lateral offset along control points: smoothstep between neighbours.
static func ctrl_lat(ctrl: Array, s: float) -> float:
	if ctrl.is_empty():
		return 0.0
	if s <= (ctrl[0] as Vector2).x:
		return (ctrl[0] as Vector2).y
	for i in ctrl.size() - 1:
		var a: Vector2 = ctrl[i]
		var b: Vector2 = ctrl[i + 1]
		if s <= b.x:
			var t := clampf((s - a.x) / maxf(0.01, b.x - a.x), 0.0, 1.0)
			return lerpf(a.y, b.y, t * t * (3.0 - 2.0 * t))
	return (ctrl[ctrl.size() - 1] as Vector2).y


func ctrl_path(ctrl: Array) -> PackedVector2Array:
	if ctrl.size() < 2:
		return PackedVector2Array()
	return lane_poly((ctrl[0] as Vector2).x, (ctrl[ctrl.size() - 1] as Vector2).x, func(s): return ctrl_lat(ctrl, s), 1.0)


func ctrl2_path(ctrl: Array) -> PackedVector2Array:
	if ctrl.size() < 2:
		return PackedVector2Array()
	var a: float = (ctrl[0] as Vector2).x
	var b: float = (ctrl[ctrl.size() - 1] as Vector2).x
	var straight := true
	for c in ctrl:
		if absf((c as Vector2).y) > 0.01:
			straight = false
	if straight:
		return Geo.sub_polyline(_g2[0], _g2[1], a, b)
	var out := PackedVector2Array()
	var n := maxi(2, int(ceil(absf(b - a))))
	for i in n + 1:
		var s2 := lerpf(a, b, float(i) / n)
		out.append(lane2_pt(s2, ctrl_lat(ctrl, s2)))
	return out


## Lane coordinates on K2: Vector2(s2, lateral, + = right of K2's travel direction).
func lane2_coords(p: Vector2) -> Vector2:
	var r: Array = Geo.closest_on_polyline(_g2[0], _g2[1], p)
	var s2: float = r[1]
	return Vector2(s2, (p - Vector2(r[2])).dot(Geo.right_of(lane2_dir(s2))))


## Adds the traffic paths to an extent: the automatic ones or the player's (traffic = {k, k2} control
## points, kept inside the limits: the path of K must start before and end after the blocked range).
func _finish_extent(ext: Dictionary, traffic: Dictionary) -> void:
	ext["k_ctrl"] = auto_k_ctrl(ext)
	ext["k2_ctrl"] = [Vector2(ext.s2_a, 0.0), Vector2(ext.s2_b, 0.0)]
	var kc: Array = traffic.get("k", [])
	if kc.size() >= 2:
		var lim := extent_limits()
		var lo := lim.x
		var hi := lim.y
		var c := _clean_ctrl(kc, lo, hi, -(lw + 4.0), lw * 0.5 + 3.0)
		# the path must leave K before the blocked range and come back after it
		var first: Vector2 = c[0]
		var last: Vector2 = c[c.size() - 1]
		first.x = maxf(lo, minf(first.x, float(ext.obst0) - 2.0))
		last.x = minf(hi, maxf(last.x, float(ext.obst1) + 2.0))
		var mid: Array = c.slice(1, c.size() - 1).filter(func(v): return v.x > first.x + 0.5 and v.x < last.x - 0.5)
		c = [first] + mid + [last]
		ext["k_ctrl"] = c
		ext.det0 = first.x
		ext.det1 = last.x
		ext.van = _van_for(ext.det0, ext.det1, float(ext.van))
		var k2 := _k2_for(ext.det0, ext.det1)
		if k2.error == "":
			ext.s2_a = k2.s2_a
			ext.s2_b = k2.s2_b
		ext["k2_ctrl"] = [Vector2(ext.s2_a, 0.0), Vector2(ext.s2_b, 0.0)]
	var k2c: Array = traffic.get("k2", [])
	if k2c.size() >= 2:
		var c2 := _clean_ctrl(k2c, HEAD_MIN, len_k2 - HEAD_MIN, -(lw2 * 0.5 + 3.0), lw2 * 0.5 + 4.0)
		ext["k2_ctrl"] = c2
		ext.s2_a = c2[0].x
		ext.s2_b = c2[c2.size() - 1].x
	ext["two_way"] = paths_apart(ctrl_path(ext.k_ctrl), ctrl2_path(ext.k2_ctrl))


## Sorted, clamped control points; both ends on the lane (lateral 0), at least 1 m apart.
static func _clean_ctrl(src: Array, lo: float, hi: float, lat_lo: float, lat_hi: float) -> Array:
	var pts: Array = []
	for q in src:
		var v: Vector2 = q
		pts.append(Vector2(clampf(v.x, lo, hi), clampf(v.y, lat_lo, lat_hi)))
	pts.sort_custom(func(u, w): return u.x < w.x)
	var out: Array = [pts[0]]
	for i in range(1, pts.size()):
		if (pts[i] as Vector2).x - (out[out.size() - 1] as Vector2).x >= 1.0:
			out.append(pts[i])
	if out.size() < 2:
		out.append(Vector2(minf(hi, (out[0] as Vector2).x + 10.0), 0.0))
	out[0] = Vector2((out[0] as Vector2).x, 0.0)
	out[out.size() - 1] = Vector2((out[out.size() - 1] as Vector2).x, 0.0)
	return out


## True if two traffic paths keep a car width plus margin apart (no shared bottleneck needed).
static func paths_apart(a: PackedVector2Array, b: PackedVector2Array, min_gap := TWO_WAY_GAP) -> bool:
	if a.size() < 2 or b.size() < 2:
		return true
	var cum_b := Geo.cumulative(b)
	for p in a:
		if float(Geo.closest_on_polyline(b, cum_b, p)[0]) < min_gap:
			return false
	return true


## Traffic geometry for the items of a player plan: the detour starts 8 m before the first item that
## stands in K and reaches the full shift where the plan blocks K up to its traffic-side edge. Kept
## within limits so the crew van, the machine slots and the waiting spots still fit.
func extent_for(items: Array, traffic: Dictionary = {}, slots: Dictionary = {}) -> Dictionary:
	var ext := _extent_items(items)
	_finish_extent(ext, traffic)
	_finish_slots(ext, slots)
	return ext


## Machine and parking spots of a plan (#22). slots (lane coordinates, all optional): exc = turret
## (s, lat), load = tipper rear while loading (s, lat), pile = pile centre (s, lat), van / stage = (s, _)
## along the curb. Kept where the vehicles can get to: behind the trench, in order excavator → tipper,
## between the far edge of the road and 1.5 m onto the curb; reach and traffic are checked by the plan.
func _finish_slots(ext: Dictionary, slots: Dictionary) -> void:
	var tc := _def_tc
	var el := 0.0
	if slots.has("exc"):
		var v: Vector2 = slots.exc
		tc = clampf(v.x, s_t1 + EXC_REAR, s_t1 + 12.0)
		el = _clamp_lat(tc, v.y)
	var front := tc + exc_turret_z + exc_front
	var lr := front + 0.75
	var ll := 0.0
	if slots.has("load"):
		var v2: Vector2 = slots.load
		lr = clampf(v2.x, front + 0.3, front + 10.0)
		ll = _clamp_lat(lr, v2.y)
	var ps := lr + 1.6
	var pl := ll
	if slots.has("pile"):
		var v3: Vector2 = slots.pile
		ps = clampf(v3.x, front + 0.8, front + 12.0)
		pl = _clamp_lat(ps, v3.y)
	elif slots.has("load"):
		ps = lr + 1.6
	var st := -1.0
	if slots.has("stage"):
		st = clampf((slots.stage as Vector2).x, float(ext.det1) + 6.0, maxf(float(ext.det1) + 6.0, len_k - 14.0))
	if slots.has("van"):
		ext.van = _van_for(float(ext.det0), float(ext.det1), (slots.van as Vector2).x)
	ext["slots"] = {"tc": tc, "exc_lat": el, "load_rear": lr, "load_lat": ll, "pile_s": ps, "pile_lat": pl, "stage": st}


func _clamp_lat(s: float, lat: float) -> float:
	var sp := road_span(s)
	return clampf(lat, sp.x + 1.3, lw * 0.5 + 1.5)


## Lateral extent of the whole carriageway (K and K2) in K coordinates near s: Vector2(lo, hi).
func road_span(s: float) -> Vector2:
	var away := 1.0 if oncoming else -1.0
	var s2: float = lane2_coords(lane_pt(s)).x
	var far: float = lane_coords(lane2_pt(s2, away * lw2 * 0.5)).y
	return Vector2(minf(far, -lw * 0.5), maxf(far, lw * 0.5))


func _extent_items(items: Array) -> Dictionary:
	var ext := _def.duplicate()
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
	# the detour starts 8 m before the first item in K and ends 5 m after the last, anywhere on the lane
	# between the junctions (#33); it always covers the pit and the machine spots
	var lim := extent_limits()
	var a_eff := clampf(a, lim.x, maxf(lim.x, minf(s_c0 - 4.0, float(_def.obst0) - 1.0)))
	var d0 := maxf(lim.x, a_eff - 8.0)
	var b_eff := clampf(b, minf(s_c1 + 2.0, lim.y - DET_OUT_MIN), lim.y - DET_OUT_MIN)
	var d1 := minf(b_eff + 5.0, lim.y)
	var f0 := _clamp_ordered(e0 if e0 < INF else s_c0 - 1.0, minf(a_eff + 3.0, s_c0 - 1.0), s_c0 - 1.0)
	f0 = maxf(f0, d0 + 1.0)
	var f1 := clampf(e1 if e1 > -INF else s_c1, s_c1, maxf(s_c1, minf(b_eff - 2.0, d1 - 6.0)))
	var k2 := _k2_for(d0, d1)
	if k2.error != "":
		return ext
	return {"det0": d0, "det1": d1, "full0": f0, "full1": f1, "obst0": maxf(a_eff + 1.0, d0 + 0.5), "obst1": b_eff - 1.0,
		"van": _van_for(d0, d1, float(_def.van)), "s2_a": k2.s2_a, "s2_b": k2.s2_b, "shift": k2.shift}


static func _clamp_ordered(x: float, lo: float, hi: float) -> float:
	return clampf(x, minf(lo, hi), maxf(lo, hi))


## How far a player plan may extend the closure on K: Vector2(earliest start, latest end) of the
## detour – the whole lane between the junctions, minus the room behind it to stop and reverse in (#33).
func extent_limits() -> Vector2:
	return Vector2(HEAD_MIN, maxf(HEAD_MIN + 1.0, len_k - 0.5 - REV_ROOM))


## Crew van spot for a detour from d0 to d1: the wanted s if it is outside the detour with room to pull
## in and out, otherwise the nearest such spot in front of or behind the closure (#33).
func _van_for(d0: float, d1: float, want: float) -> float:
	var up_hi := d0 - VAN_EXIT_GAP
	var up_lo := HEAD_MIN + VAN_APPR_MIN
	var dn_lo := d1 + REV_ROOM + 3.0
	var dn_hi := len_k - 0.5 - 3.0 - VAN_EXIT_MIN
	var best := -1.0
	var best_d := INF
	if up_hi >= up_lo:
		var u := clampf(want, up_lo, up_hi)
		best = u
		best_d = absf(u - want)
	if dn_hi >= dn_lo:
		var dn := clampf(want, dn_lo, dn_hi)
		if absf(dn - want) < best_d:
			best = dn
	return best   # -1: no room on K, the van parks on a lane next to it (plan_kerb)


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
	k_ctrl = (ext.k_ctrl as Array).duplicate() if ext.has("k_ctrl") else auto_k_ctrl(ext)
	k2_ctrl = (ext.k2_ctrl as Array).duplicate() if ext.has("k2_ctrl") else [Vector2(s2_a, 0.0), Vector2(s2_b, 0.0)]
	two_way = bool(ext.get("two_way", false))
	var sl: Dictionary = ext.get("slots", {})
	if not sl.is_empty():
		s_tc = sl.tc
		s_exc = s_tc + exc_turret_z
		exc_lat = sl.exc_lat
		load_rear = sl.load_rear
		load_lat = sl.load_lat
		pile_s = sl.pile_s
		pile_lat = sl.pile_lat
		stage0 = sl.stage
	kerb = plan_kerb(current_extent())


func detour_pts_for(ext: Dictionary) -> PackedVector2Array:
	return ctrl_path(ext.k_ctrl)


func zone2_pts_for(ext: Dictionary) -> PackedVector2Array:
	return ctrl2_path(ext.k2_ctrl)


# ------------------------------------------------------------------------------------------
# Closure kit
# ------------------------------------------------------------------------------------------

## Items in setup order: {kind, pos: Vector2, yaw, phase, group}. group: signs | taper | head | line | tail | pit
func items() -> Array:
	var out: Array = []
	var d0 := lane_dir(s0)
	var side := lw * 0.5 + 0.7
	# close to a junction the signs stand at the start of the lane, one behind the other (#33)
	var s123 := maxf(1.0, s0 - 48.0)
	var s208 := maxf(s123 + 3.0, s0 - 30.0)
	out.append(_item("z123", lane_pt(s123, side), yaw_of(lane_dir(s123)), "signs"))
	out.append(_item("z208", lane_pt(s208, side), yaw_of(lane_dir(s208)), "signs"))
	var k2_sign_kind := "z308" if oncoming else ""
	# standard positions: from the default K2 range (a player plan may have moved s2_a)
	var s2a_def: float = _def.get("s2_a", s2_a)
	var s2_123 := maxf(1.0, s2a_def - 45.0)
	out.append({"kind": "z123", "pos": lane2_pt(s2_123, lw2 * 0.5 + 0.7), "yaw": yaw_of(lane2_dir(s2_123)), "phase": 0.0, "group": "signs"})
	if k2_sign_kind != "":
		var s2_308 := maxf(s2_123 + 3.0, s2a_def - 24.0)
		out.append({"kind": "z308", "pos": lane2_pt(s2_308, lw2 * 0.5 + 0.7), "yaw": yaw_of(lane2_dir(s2_308)), "phase": 0.0, "group": "signs"})
	# taper (Verschwenkung) with running warning lights
	# a short taper near a junction gets fewer Leitbaken; none if the head barrier stands at the lane start (#33)
	var taper_len := s_c0 - s0
	var n_taper := 0 if taper_len < 0.4 else clampi(int(taper_len / 3.0) + 1, 2, 5)
	for i in n_taper:
		var t := float(i) / maxf(1.0, n_taper - 1)
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
			return lerpf(curb, edge, clampf((s - s0) / maxf(0.1, s_c0 - s0), 0.0, 1.0))
		if s > s_c1:
			return lerpf(edge, curb, (s - s_c1) / (s_taper1 - s_c1))
		return edge, 1.0)
