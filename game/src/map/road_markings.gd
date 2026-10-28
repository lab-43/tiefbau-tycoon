class_name RoadMarkings
extends RefCounted
## German road markings (RMS; built-up area unless the road is faster than 60 km/h) that need more
## than one road or the turn paths: lines through transitions and merged junctions, guide lines for
## neighbouring turning lanes, direction arrows and restricted areas (Sperrflächen, Z 298).
## RoadMesher draws the lines along each road and calls in here (#5, Etappe 4).

const Y := 0.062               # = RoadMesher.Y_MARK
const NARROW := 0.12           # Schmalstrich
const BROAD := 0.25            # Breitstrich
const STOP_W := 0.50           # Haltlinie (Z 294)
const GIVE_W := 0.50           # Wartelinie (Z 341): broad dashes 0.50 m, gaps 0.25 m
const GIVE_DASH := 0.50
const GIVE_GAP := 0.25
const FURT_DASH := 0.50        # Fußgängerfurt: dashed broad lines, 0.50 m dash, 0.20 m gap
const FURT_GAP := 0.20
const KNOT_DASH := 1.5         # Leitlinie im Knotenpunkt, dash : gap = 1 : 1
const WARN_DASH := 3.0         # Warnlinie innerorts, dash : gap = 2 : 1
const WARN_GAP := 1.5
const WARN_LEN := 30.0         # Warnlinie in front of the solid centre line at signals
const ARROW_LEN := 5.0         # Richtungspfeil innerorts (außerorts 7.5 m)
const ARROW_LEN_FAST := 7.5
const ARROW_BACK := 3.0        # tip of the first arrow in front of the stop line
const ARROW_REPEAT := 25.0     # second arrow further back on long lanes
const HATCH_W := 0.25          # Sperrfläche: oblique broad stripes ...
const HATCH_STEP := 1.25       # ... centre to centre (the small grid of built-up areas)
const HATCH_MIN_AREA := 4.0
const GORE_MAX_R := 2.0        # a gore is narrower than 4 m everywhere (wider rest areas are left alone)

var net: RoadNet
var stats := {"haltlinie": 0, "wartelinie": 0, "pfeil": 0, "furt": 0, "zebra": 0, "durchgang_m": 0.0,
	"knoten_leitlinie_m": 0.0, "warnlinie_m": 0.0, "sperrflaechen": 0, "sperrflaeche_m2": 0.0}


func _init(n: RoadNet) -> void:
	net = n


# ------------------------------------------------------------------------------------------
# Drawing helpers
# ------------------------------------------------------------------------------------------

## Solid band of width w centred on polyline pts.
func band(l: MeshLayer, pts: PackedVector2Array, w: float) -> void:
	if pts.size() < 2:
		return
	var a := Geo.offset_polyline(pts, -w * 0.5)
	var b := Geo.offset_polyline(pts, w * 0.5)
	for i in pts.size() - 1:
		l.quad(Geo.v3(a[i], Y), Geo.v3(b[i], Y), Geo.v3(b[i + 1], Y), Geo.v3(a[i + 1], Y), Vector3.UP)


## Dashes along pts (dash <= 0: solid). Starts with half a gap, so lines meeting end to end do not
## run into one another. Returns the painted length.
func dashes(l: MeshLayer, pts: PackedVector2Array, w: float, dash: float, gap: float) -> float:
	if pts.size() < 2:
		return 0.0
	var cum := Geo.cumulative(pts)
	var total: float = cum[cum.size() - 1]
	if dash <= 0.0:
		band(l, pts, w)
		return total
	var painted := 0.0
	var s := gap * 0.5
	while s < total - 0.2:
		var e := minf(s + dash, total)
		band(l, Geo.sub_polyline(pts, cum, s, e), w)
		painted += e - s
		s += dash + gap
	return painted


## The line half way between two polylines running the same way (resampled by relative arc length).
static func midline(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var ca := Geo.cumulative(a)
	var cb := Geo.cumulative(b)
	var la: float = ca[ca.size() - 1]
	var lb: float = cb[cb.size() - 1]
	var n := maxi(2, ceili(maxf(la, lb) / 0.5) + 1)
	var out := PackedVector2Array()
	for i in n:
		var t := float(i) / float(n - 1)
		out.append(((Geo.sample(a, ca, t * la)[0] as Vector2) + (Geo.sample(b, cb, t * lb)[0] as Vector2)) * 0.5)
	return out


# ------------------------------------------------------------------------------------------
# Lines through transitions and merged junctions
# ------------------------------------------------------------------------------------------

## Pairs of road ends at node n where one road simply continues as the other: a transition node
## (`cont`) or a pass-through member of a merged group (RoadNet._pass_through_cuts).
func pass_pairs(n: Dictionary) -> Array:
	var pairs: Array = []
	if n.get("cont", false) and n.ends.size() == 2:
		pairs.append([n.ends[0], n.ends[1]])
	else:
		for inf in n.get("infos", []):
			if inf.has("pass") and int(inf.ref) < int(inf.pass):
				pairs.append([int(inf.ref), int(inf.pass)])
	return pairs


## Straight paths from the lanes arriving at road end r_in to road end r_out of the same node:
## Array indexed by the entry lane, each {pts, lo} or null.
func _paths_between(r_in: int, r_out: int) -> Array:
	var ein := r_in >> 1
	var dir_in := 0 if (r_in & 1) == 1 else 1
	var eout := r_out >> 1
	var dir_out := r_out & 1
	var res: Array = []
	for li in net.lane_count(ein, dir_in):
		var found = null
		for ci in net.lane_out.get(RoadNet.lane_key(ein, dir_in, li), []):
			var c: Dictionary = net.connectors[ci]
			var to: int = c.to
			if (to >> 4) == eout and ((to >> 3) & 1) == dir_out:
				found = {"pts": c.pts, "lo": to & 7}
				break
		res.append(found)
	return res


## Where a road continues as another one (transition, pass-through member of a merged group), its
## lane dividers and centre line run on between the turn paths of neighbouring lanes, in the style of
## the road (RMS: the lines are not interrupted where nothing crosses).
func through_lines(l: MeshLayer, ni: int) -> void:
	var n: Dictionary = net.nodes[ni]
	for pr in pass_pairs(n):
		var ea: Dictionary = net.edges[pr[0] >> 1]
		var eb: Dictionary = net.edges[pr[1] >> 1]
		if not (RoadMesher.is_marked(ea) and RoadMesher.is_marked(eb)):
			continue
		var urban: bool = minf(ea.speed, eb.speed) <= 60.0 / 3.6 + 0.1
		var dash := 3.0 if urban else 6.0
		var gap := 6.0 if urban else 12.0
		for k in 2:
			var paths := _paths_between(pr[k], pr[1 - k])
			for li in range(paths.size() - 1):
				var A = paths[li]
				var B = paths[li + 1]
				if A == null or B == null or int(B.lo) != int(A.lo) + 1:
					continue
				stats.durchgang_m += dashes(l, midline(A.pts, B.pts), NARROW, dash, gap)
		# centre line of a two-way road: from the centre line of the one road at its cut to that of the
		# other (the lanes may begin or end on either side, so not between lane paths)
		if _two_way(ea) and _two_way(eb):
			var pa := _cut_point(pr[0], RoadMesher.center_offset(ea), center_back(pr[0]))
			var pb := _cut_point(pr[1], RoadMesher.center_offset(eb), center_back(pr[1]))
			var path := RoadNet.turn_path(pa[0], -(pa[1] as Vector2), pb[0], pb[1])
			var solid: bool = int(ea.lf) + int(ea.lb) >= 4 or int(eb.lf) + int(eb.lb) >= 4
			stats.durchgang_m += dashes(l, path, NARROW, 0.0 if solid else dash, gap)


static func _two_way(e: Dictionary) -> bool:
	return not e.oneway and int(e.lf) > 0 and int(e.lb) > 0


var _center_back := {}   # road end -> metres its centre line stops short of the cut (see center_back)


## Where the centre line moves sideways in a transition (a turning lane begins, the road gets
## wider), the shift is spread at 1:8 instead of over the few metres between the cuts: the edges'
## own centre lines stop this much earlier and through_lines draws the S curve from there.
func center_back(r: int) -> float:
	if _center_back.has(r):
		return _center_back[r]
	_center_back[r] = 0.0
	var e: Dictionary = net.edges[r >> 1]
	var n: Dictionary = net.nodes[e.b if (r & 1) == 1 else e.a]
	for pr in pass_pairs(n):
		if pr[0] != r and pr[1] != r:
			continue
		var o: int = pr[1] if pr[0] == r else pr[0]
		var eo: Dictionary = net.edges[o >> 1]
		if not (_two_way(e) and _two_way(eo) and RoadMesher.is_marked(e) and RoadMesher.is_marked(eo)):
			break
		var pa := _cut_point(r, RoadMesher.center_offset(e), 0.0)
		var pb := _cut_point(o, RoadMesher.center_offset(eo), 0.0)
		var t: Vector2 = -(pa[1] as Vector2)
		var rel: Vector2 = (pb[0] as Vector2) - (pa[0] as Vector2)
		var need := maxf(0.0, (8.0 * absf(t.cross(rel)) - rel.length()) * 0.5)
		_center_back[r] = minf(need, _back_cap(e))
		_center_back[o] = minf(need, _back_cap(eo))
		break
	return _center_back[r]


static func _back_cap(e: Dictionary) -> float:
	return clampf((e.len - e.trim_a - e.trim_b) * 0.4, 0.0, 25.0)


## Point at lateral offset off (right of the edge's a -> b direction) where road end r is cut (or
## `back` metres further from the node), and the direction away from the node: [point, direction].
func _cut_point(r: int, off: float, back: float) -> Array:
	var e: Dictionary = net.edges[r >> 1]
	var at_b: bool = (r & 1) == 1
	var s: float = e.len - e.trim_b - back if at_b else e.trim_a + back
	var smp := Geo.sample(e.pts, e.cum, s)
	var fwd: Vector2 = smp[1]
	var p: Vector2 = (smp[0] as Vector2) + Geo.right_of(fwd) * off
	return [p, -fwd if at_b else fwd]


## Leitlinien im Knotenpunkt (1.5 m / 1.5 m) between neighbouring lanes that turn together from the
## same approach into neighbouring lanes of the same exit (double left turns …). Straight on only in
## large merged junctions, where the paths are long and lead past islands.
func knot_lines(l: MeshLayer, ni: int) -> void:
	var n: Dictionary = net.nodes[ni]
	if n.get("cont", false) or n.ends.size() < 3:
		return
	var group: bool = n.has("group")
	if not group and n.ctrl != "signals":
		return
	var skip := {}
	for pr in pass_pairs(n):
		skip[Vector2i(pr[0], pr[1])] = true
		skip[Vector2i(pr[1], pr[0])] = true
	var bundles := {}
	for ci in n.get("conns", []):
		var c: Dictionary = net.connectors[ci]
		if c.turn == "U":
			continue
		var out_end: int = (int(c.to) >> 4) * 2 + ((int(c.to) >> 3) & 1)
		if skip.has(Vector2i(int(c.approach_end), out_end)):
			continue
		var key := Vector2i(int(c.from) >> 3, int(c.to) >> 3)
		if not bundles.has(key):
			bundles[key] = []
		bundles[key].append(c)
	for key in bundles:
		var cs: Array = bundles[key]
		if cs.size() < 2 or not RoadMesher.is_marked(net.edges[int(cs[0].from) >> 4]):
			continue
		if cs[0].turn == "S" and not (group and float(cs[0].len) >= 20.0):
			continue
		cs.sort_custom(func(a, b): return (int(a.from) & 7) < (int(b.from) & 7))
		for i in cs.size() - 1:
			var A: Dictionary = cs[i]
			var B: Dictionary = cs[i + 1]
			if (int(B.from) & 7) != (int(A.from) & 7) + 1 or (int(B.to) & 7) != (int(A.to) & 7) + 1:
				continue
			stats.knoten_leitlinie_m += dashes(l, midline(A.pts, B.pts), NARROW, KNOT_DASH, KNOT_DASH)


# ------------------------------------------------------------------------------------------
# Direction arrows (Z 297)
# ------------------------------------------------------------------------------------------

## Turns a lane allows at its end (from its turn paths): a set of "S", "L", "R".
func lane_turns(key: int) -> Dictionary:
	var t := {}
	for ci in net.lane_out.get(key, []):
		var turn: String = net.connectors[ci].turn
		if turn != "U":
			t[turn] = true
	return t


## Arrows on the lanes of edge ei in direction dir towards a junction, when the lanes there lead to
## different directions. tip_from_end: distance of the first arrow tip from the lane end.
func lane_arrows(l: MeshLayer, ei: int, dir: int, tip_from_end: float) -> void:
	var e: Dictionary = net.edges[ei]
	var nl := net.lane_count(ei, dir)
	if nl < 2 or not RoadMesher.is_marked(e):
		return
	var sets: Array = []
	var differ := false
	for li in nl:
		var t := lane_turns(RoadNet.lane_key(ei, dir, li))
		sets.append(t)
		if li > 0 and not _same(t, sets[0]):
			differ = true
	if not differ:
		return
	var alen := ARROW_LEN if e.speed <= 60.0 / 3.6 + 0.1 else ARROW_LEN_FAST
	for li in nl:
		var t: Dictionary = sets[li]
		if t.is_empty():
			continue
		var g: Array = net.lane_geo.get(RoadNet.lane_key(ei, dir, li), [])
		if g.is_empty():
			continue
		var pts: PackedVector2Array = g[0]
		var cum: PackedFloat32Array = g[1]
		var total: float = cum[cum.size() - 1]
		var tip := total - tip_from_end
		var k := 0
		while tip - alen > 2.0 and k < 2:
			_arrow(l, pts, cum, tip - alen, alen, t)
			stats.pfeil += 1
			tip -= alen + ARROW_REPEAT
			k += 1


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true


## One arrow on a lane: base at arc length s0, length alen, heads for the turns in t. Drawn in the
## lane's own coordinates (u along, v to the right), so it follows a curved lane.
func _arrow(l: MeshLayer, pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, alen: float, t: Dictionary) -> void:
	var k := alen / 5.0
	var hw := 0.09 * k
	var straight: bool = t.has("S")
	var shaft_end := 3.5 if straight else 2.4
	var polys: Array = []
	polys.append([Vector2(0, -hw), Vector2(shaft_end * k, -hw), Vector2(shaft_end * k, hw), Vector2(0, hw)])
	if straight:
		polys.append([Vector2(3.4 * k, -0.32 * k), Vector2(5.0 * k, 0.0), Vector2(3.4 * k, 0.32 * k)])
	for side in ["L", "R"]:
		if not t.has(side):
			continue
		var sg := -1.0 if side == "L" else 1.0
		var p0 := Vector2((2.0 if straight else 2.2) * k, 0.0)
		var p1 := Vector2((3.0 if straight else 3.3) * k, 0.55 * k * sg)
		var d := (p1 - p0).normalized()
		var nrm := Vector2(-d.y, d.x)
		polys.append([p0 - nrm * hw, p1 - nrm * hw, p1 + nrm * hw, p0 + nrm * hw])
		polys.append([p1 - nrm * 0.3 * k, p1 + d * 1.0 * k, p1 + nrm * 0.3 * k])
	for poly in polys:
		var w := PackedVector2Array()
		for q in poly:
			var smp := Geo.sample(pts, cum, s0 + q.x)
			w.append((smp[0] as Vector2) + Geo.right_of(smp[1]) * q.y)
		if w.size() == 3:
			l.tri(Geo.v3(w[0], Y), Geo.v3(w[1], Y), Geo.v3(w[2], Y), Vector3.UP)
		else:
			l.quad(Geo.v3(w[0], Y), Geo.v3(w[1], Y), Geo.v3(w[2], Y), Geo.v3(w[3], Y), Vector3.UP)


# ------------------------------------------------------------------------------------------
# Restricted areas (Sperrflächen, Z 298)
# ------------------------------------------------------------------------------------------

## In a merged junction: asphalt no turn path uses is hatched where it lies in front of an island or
## forms a narrow gore between paths that part or meet. Wide rest areas and the strips along the
## curbs stay plain.
func sperrflaechen(l: MeshLayer, ni: int) -> void:
	var n: Dictionary = net.nodes[ni]
	if not n.has("group") or n.polygon.size() < 3:
		return
	var outer: PackedVector2Array = n.polygon
	var islands: Array = n.get("holes", [])
	var drive: Array = []
	for ci in n.get("conns", []):
		var c: Dictionary = net.connectors[ci]   # U-turns too: in a group they are crossovers
		var hw: float = float(net.edges[int(c.from) >> 4].lw) * 0.5
		for b in Geometry2D.offset_polyline(_coarse(c.pts, 1.5), hw, Geometry2D.JOIN_MITER, Geometry2D.END_SQUARE):
			if not Geometry2D.is_polygon_clockwise(b):
				drive.append(b)
	if drive.is_empty():
		return
	var u := JunctionMerge.union_all(drive)
	var rest: Array = [outer]
	for dp in u[0]:
		var nxt: Array = []
		for part in rest:
			for r in Geometry2D.clip_polygons(part, dp):
				if not Geometry2D.is_polygon_clockwise(r):
					nxt.append(r)
		rest = nxt
	# islands are ground, and the surfaces of the OSM roads inside the group are roads (a ramp no
	# turn path follows closely is no restricted area)
	for h in islands + n.get("inner_roads", []):
		var nxt2: Array = []
		for part in rest:
			for r in Geometry2D.clip_polygons(part, h):
				if not Geometry2D.is_polygon_clockwise(r):
					nxt2.append(r)
		rest = nxt2
	var grid := _seg_grid(outer, islands)
	for part in rest:
		# opening: the slivers along the paths go
		for sp in Geometry2D.offset_polygon(part, -0.4, Geometry2D.JOIN_MITER):
			if Geometry2D.is_polygon_clockwise(sp):
				continue
			for g in Geometry2D.offset_polygon(sp, 0.4, Geometry2D.JOIN_MITER):
				if Geometry2D.is_polygon_clockwise(g) or absf(Geo.polygon_area(g)) < HATCH_MIN_AREA:
					continue
				# islands and road surfaces overlapping the area (one lying wholly inside a part comes
				# back from the clipping as a hole, which is dropped): cut out of the stripes here
				var inside: Array = []
				var island_inside := false
				var roads: Array = n.get("inner_roads", [])
				for h in islands + roads:
					for ov in Geometry2D.intersect_polygons(g, h):
						if not Geometry2D.is_polygon_clockwise(ov) and absf(Geo.polygon_area(ov)) > 0.5:
							inside.append(ov)
							island_inside = island_inside or h in islands
				var touch := _touching(g, grid)
				var gore := Geometry2D.offset_polygon(g, -GORE_MAX_R, Geometry2D.JOIN_MITER).is_empty()
				if touch.island >= 1.0 or island_inside or (gore and touch.curb < 0.3 * touch.total):
					_hatch(l, g, grid, inside)


## Polyline thinned to points at least `step` apart (end points kept): turn paths have a point every
## 0.75 m, which makes the union of their strips slow.
static func _coarse(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		if pts[i].distance_to(out[out.size() - 1]) >= step:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


const GRID := 4.0


## Spatial index of the outline of a group: cell -> [[a, b, kind]], kind 0 = curb, 1 = island.
static func _seg_grid(outer: PackedVector2Array, islands: Array) -> Dictionary:
	var g := {}
	_add_ring(g, outer, 0)
	for h in islands:
		_add_ring(g, h, 1)
	return g


static func _add_ring(g: Dictionary, ring: PackedVector2Array, kind: int) -> void:
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		for x in range(floori(minf(a.x, b.x) / GRID), floori(maxf(a.x, b.x) / GRID) + 1):
			for y in range(floori(minf(a.y, b.y) / GRID), floori(maxf(a.y, b.y) / GRID) + 1):
				var c := Vector2i(x, y)
				if not g.has(c):
					g[c] = []
				g[c].append([a, b, kind])


## What lies within d (< GRID) of p: 0 a curb, 1 an island, -1 nothing (a curb wins).
static func _near(grid: Dictionary, p: Vector2, d: float) -> int:
	var cx := floori(p.x / GRID)
	var cy := floori(p.y / GRID)
	var res := -1
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for sg in grid.get(Vector2i(cx + dx, cy + dy), []):
				if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])) < d * d:
					if sg[2] == 0:
						return 0
					res = 1
	return res


## Boundary length of g lying on the curb line and on islands (sampled every metre).
func _touching(g: PackedVector2Array, grid: Dictionary) -> Dictionary:
	var res := {"curb": 0.0, "island": 0.0, "total": 0.0}
	for i in g.size():
		var a := g[i]
		var b := g[(i + 1) % g.size()]
		var len_ab := a.distance_to(b)
		var steps := maxi(1, ceili(len_ab))
		for k in steps:
			var part := len_ab / steps
			res.total += part
			match _near(grid, a.lerp(b, (k + 0.5) / steps), 0.35):
				0:
					res.curb += part
				1:
					res.island += part
	return res


## Oblique stripes over area g at 45° to its long axis, and a narrow border line where the area
## meets the lanes (not along curbs and islands).
func _hatch(l: MeshLayer, g: PackedVector2Array, grid: Dictionary, inside: Array) -> void:
	var cut_out: Array = []
	var area := absf(Geo.polygon_area(g))
	for h in inside:
		area -= absf(Geo.polygon_area(h))
		for gh in Geometry2D.offset_polygon(h, 0.2, Geometry2D.JOIN_MITER):
			if not Geometry2D.is_polygon_clockwise(gh):
				cut_out.append(gh)
	if area < HATCH_MIN_AREA:
		return
	stats.sperrflaechen += 1
	stats.sperrflaeche_m2 += area
	# long axis from the covariance of the outline
	var c := Geo.polygon_centroid(g)
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in g:
		var d := p - c
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	var axis := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var dir := Vector2.from_angle(axis + PI * 0.25)
	var across := Vector2(-dir.y, dir.x)
	var reach := 0.0
	for p in g:
		reach = maxf(reach, p.distance_to(c))
	for inner in Geometry2D.offset_polygon(g, -0.2, Geometry2D.JOIN_MITER):
		if Geometry2D.is_polygon_clockwise(inner):
			continue
		var t := -reach
		while t <= reach:
			var o := c + across * t
			var line := PackedVector2Array([o - dir * (reach + 1.0), o + dir * (reach + 1.0)])
			var segs: Array = Geometry2D.intersect_polyline_with_polygon(line, inner)
			for h in cut_out:
				var nxt: Array = []
				for sg in segs:
					nxt.append_array(Geometry2D.clip_polyline_with_polygon(sg, h))
				segs = nxt
			for seg in segs:
				if (seg as PackedVector2Array).size() >= 2 and seg[0].distance_to(seg[seg.size() - 1]) > 0.2:
					band(l, seg, HATCH_W)
			t += HATCH_STEP
	# border: narrow solid line just inside the outline, where the area meets a lane
	for ring in Geometry2D.offset_polygon(g, -NARROW * 0.5, Geometry2D.JOIN_MITER):
		if Geometry2D.is_polygon_clockwise(ring):
			continue
		for i in ring.size():
			var a: Vector2 = ring[i]
			var b: Vector2 = ring[(i + 1) % ring.size()]
			if _near(grid, (a + b) * 0.5, 0.45) < 0:
				band(l, PackedVector2Array([a, b]), NARROW)
