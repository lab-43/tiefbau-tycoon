class_name RoadMesher
extends RefCounted
## Builds road surfaces, sidewalks, curbs and German road markings from a RoadNet, grouped per chunk.

const Y_ROAD := 0.05
const Y_MARK := 0.062
const CURB := 0.12
const Y_SW := Y_ROAD + CURB
const MARK_W := 0.12
const MARKED_CLASSES := {"primary": 1, "secondary": 1, "tertiary": 1, "trunk": 1, "motorway": 1,
	"primary_link": 1, "secondary_link": 1, "tertiary_link": 1, "trunk_link": 1, "motorway_link": 1, "busway": 1}

var net: RoadNet
var chunk_size := 500.0
var origin := Vector2.ZERO
var chunks := {}   # Vector2i -> {"asphalt": MeshLayer, "sidewalk":..., "curb":..., "mark":...}


func _init(n: RoadNet, chunk: float, bounds_origin: Vector2) -> void:
	net = n
	chunk_size = chunk
	origin = bounds_origin


func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / chunk_size)), int(floor((p.y - origin.y) / chunk_size)))


func layer(ck: Vector2i, name: String) -> MeshLayer:
	if not chunks.has(ck):
		chunks[ck] = {}
	var c: Dictionary = chunks[ck]
	if not c.has(name):
		var l := MeshLayer.new()
		c[name] = l
	return c[name]


var progress_cb: Callable   # (fraction 0..1), called from the bake thread

func build_all() -> void:
	var total := maxi(1, net.edges.size() + net.nodes.size())
	for ei in net.edges.size():
		_edge(ei)
		if ei % 200 == 0 and progress_cb.is_valid():
			progress_cb.call(float(ei) / total)
	for ni in net.nodes.size():
		_junction(ni)
		if ni % 200 == 0 and progress_cb.is_valid():
			progress_cb.call(float(net.edges.size() + ni) / total)


# ------------------------------------------------------------------------------------------

func _edge(ei: int) -> void:
	var e: Dictionary = net.edges[ei]
	var s0: float = e.trim_a
	var s1: float = e.len - e.trim_b
	if s1 - s0 < 0.05:
		return
	var center := Geo.sub_polyline(e.pts, e.cum, s0, s1)
	if center.size() < 2:
		return
	center = Geo.densify(center, 12.0)
	var mid: Vector2 = Geo.sample(e.pts, e.cum, (s0 + s1) * 0.5)[0]
	var ck := chunk_of(mid)
	var hw: float = e.width * 0.5
	var left := Geo.offset_polyline(center, -hw)
	var right := Geo.offset_polyline(center, hw)
	var cum := Geo.cumulative(center)
	var asp := layer(ck, "asphalt")
	for i in range(center.size() - 1):
		var v0 := cum[i] + s0
		var v1 := cum[i + 1] + s0
		asp.quad(Geo.v3(left[i], Y_ROAD), Geo.v3(right[i], Y_ROAD), Geo.v3(right[i + 1], Y_ROAD), Geo.v3(left[i + 1], Y_ROAD),
			Vector3.UP, Vector2(0, v0), Vector2(e.width, v0), Vector2(e.width, v1), Vector2(0, v1))
	# sidewalks (not on the asphalt of junction areas built by union, see RoadNet._group_polygon)
	var clips := _area_clips(net.nodes[e.a]) + _area_clips(net.nodes[e.b])
	if e.sw_r > 0.0:
		_sidewalk_strip(ck, right, Geo.offset_polyline(center, hw + e.sw_r), center, true, clips)
	if e.sw_l > 0.0:
		_sidewalk_strip(ck, left, Geo.offset_polyline(center, -hw - e.sw_l), center, false, clips)
	if e.bridge:
		_bridge_sides(ck, center, hw + e.sw_r, hw + e.sw_l)
	_edge_markings(ei, e, ck, s0, s1)


## Junction areas a sidewalk must not cover: [polygon, bounding rect] of node n if its area was built
## by union (merged groups, junctions whose turn paths left the plain polygon).
func _area_clips(n: Dictionary) -> Array:
	if not n.get("area", false):
		return []
	var res: Array = []
	for poly in [n.polygon] + n.get("extra_polys", []):
		var pv: PackedVector2Array = poly
		if pv.size() >= 3:
			var r := Rect2(pv[0], Vector2.ZERO)
			for q in pv:
				r = r.expand(q)
			res.append([pv, r])
	return res


## Raised sidewalk between inner (curb line) and outer polylines, with curb face toward the road.
## Parts lying on a junction area in `clips` (see _area_clips) are cut away.
func _sidewalk_strip(ck: Vector2i, inner: PackedVector2Array, outer: PackedVector2Array, center: PackedVector2Array, right_side: bool, clips: Array = []) -> void:
	var sw := layer(ck, "sidewalk")
	var cb := layer(ck, "curb")
	for i in range(inner.size() - 1):
		var a := inner[i]
		var b := inner[i + 1]
		var c := outer[i + 1]
		var d := outer[i]
		var q := PackedVector2Array([a, b, c, d])
		var pieces := _clip_away(q, clips)
		if pieces.size() == 1 and pieces[0] == q:
			sw.quad(Geo.v3(a, Y_SW), Geo.v3(b, Y_SW), Geo.v3(c, Y_SW), Geo.v3(d, Y_SW), Vector3.UP, a, b, c, d)
		else:
			for pc in pieces:
				sw.polygon_up(pc, Y_SW, 1.0)
			if _inside_any((a + b) * 0.5, clips):
				continue   # curb line lies on the junction area: no curb faces here
		var seg := (b - a)
		if seg.length() < 0.001:
			continue
		var road_dir := (center[i] - a).normalized()
		var n := Vector3(road_dir.x, 0, road_dir.y)
		cb.quad(Geo.v3(a, Y_ROAD - 0.02), Geo.v3(b, Y_ROAD - 0.02), Geo.v3(b, Y_SW), Geo.v3(a, Y_SW), n,
			Vector2(0, 0), Vector2(seg.length(), 0), Vector2(seg.length(), CURB), Vector2(0, CURB))
		# outer face down to the ground
		var n2 := -n
		cb.quad(Geo.v3(d, 0.0), Geo.v3(c, 0.0), Geo.v3(c, Y_SW), Geo.v3(d, Y_SW), n2)


## Parts of polygon q outside all clip areas (q itself if it touches none).
func _clip_away(q: PackedVector2Array, clips: Array) -> Array:
	var pieces: Array = [q]
	if clips.is_empty():
		return pieces
	var r := Rect2(q[0], Vector2.ZERO)
	for v in q:
		r = r.expand(v)
	for cl in clips:
		if not r.intersects(cl[1]):
			continue
		var nxt: Array = []
		for pc in pieces:
			for res in Geometry2D.clip_polygons(pc, cl[0]):
				if not Geometry2D.is_polygon_clockwise(res) and absf(Geo.polygon_area(res)) > 0.005:
					nxt.append(res)
		pieces = nxt
		if pieces.is_empty():
			break
	return pieces


func _inside_any(p: Vector2, clips: Array) -> bool:
	for cl in clips:
		if (cl[1] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, cl[0]):
			return true
	return false


func _bridge_sides(ck: Vector2i, center: PackedVector2Array, off_r: float, off_l: float) -> void:
	var cb := layer(ck, "bridge")
	for side in [1, -1]:
		var off: float = (off_r if side == 1 else off_l) + 0.35
		var line := Geo.offset_polyline(center, off * side)
		var line_in := Geo.offset_polyline(center, (off - 0.35) * side)
		for i in range(line.size() - 1):
			var a := line[i]
			var b := line[i + 1]
			var dir := (b - a).normalized()
			var nout: Vector2 = Geo.right_of(dir) * side
			var n := Vector3(nout.x, 0, nout.y)
			# deck side down into the water and parapet up
			cb.quad(Geo.v3(a, -1.2), Geo.v3(b, -1.2), Geo.v3(b, Y_SW + 0.9), Geo.v3(a, Y_SW + 0.9), n)
			var ai := line_in[i]
			var bi := line_in[i + 1]
			cb.quad(Geo.v3(ai, Y_SW), Geo.v3(bi, Y_SW), Geo.v3(bi, Y_SW + 0.9), Geo.v3(ai, Y_SW + 0.9), -n)
			cb.quad(Geo.v3(ai, Y_SW + 0.9), Geo.v3(bi, Y_SW + 0.9), Geo.v3(b, Y_SW + 0.9), Geo.v3(a, Y_SW + 0.9), Vector3.UP)


# ------------------------------------------------------------------------------------------
# Markings
# ------------------------------------------------------------------------------------------

func _strip(l: MeshLayer, center: PackedVector2Array, cum: PackedFloat32Array, sa: float, sb: float, off: float, w: float) -> void:
	if sb - sa < 0.05:
		return
	var sub := Geo.sub_polyline(center, cum, sa, sb)
	if sub.size() < 2:
		return
	var l0 := Geo.offset_polyline(sub, off - w * 0.5)
	var l1 := Geo.offset_polyline(sub, off + w * 0.5)
	for i in range(sub.size() - 1):
		l.quad(Geo.v3(l0[i], Y_MARK), Geo.v3(l1[i], Y_MARK), Geo.v3(l1[i + 1], Y_MARK), Geo.v3(l0[i + 1], Y_MARK), Vector3.UP)


func _dashed(l: MeshLayer, center: PackedVector2Array, cum: PackedFloat32Array, sa: float, sb: float, off: float, w: float, dash: float, gap: float) -> void:
	var s := sa + gap * 0.5
	while s < sb:
		_strip(l, center, cum, s, minf(s + dash, sb), off, w)
		s += dash + gap


func _edge_markings(ei: int, e: Dictionary, ck: Vector2i, s0: float, s1: float) -> void:
	var mk := layer(ck, "mark")
	var pts: PackedVector2Array = e.pts
	var cum: PackedFloat32Array = e.cum
	var urban: bool = e.speed <= 60.0 / 3.6 + 0.1
	var dash := 3.0 if urban else 6.0
	var gap := 6.0 if urban else 12.0
	var marked: bool = MARKED_CLASSES.has(e.cls) and not e.narrow
	var n_a: Dictionary = net.nodes[e.a]
	var n_b: Dictionary = net.nodes[e.b]
	var sig_a: bool = n_a.ctrl == "signals"
	var sig_b: bool = n_b.ctrl == "signals"
	var solid_a := 20.0 if sig_a else 0.0
	var solid_b := 20.0 if sig_b else 0.0
	var lf: int = e.lf
	var lb: int = e.lb
	var lw: float = e.lw
	var shift: float = ((e.park_l + e.cyc_l) - (e.park_r + e.cyc_r)) * 0.5
	var total := (lf + lb) * lw
	var x_div := -total * 0.5 + (0 if e.oneway else lb) * lw + shift
	var length := s1 - s0
	if marked and length > 2.0:
		# center line between directions
		if not e.oneway and lb > 0 and lf > 0:
			var sa := s0
			var sb := s1
			if solid_a > 0.0:
				_strip(mk, pts, cum, s0, minf(s0 + solid_a, s1), x_div, MARK_W)
				sa = s0 + solid_a
			if solid_b > 0.0:
				_strip(mk, pts, cum, maxf(s1 - solid_b, s0), s1, x_div, MARK_W)
				sb = s1 - solid_b
			if (lf + lb) >= 4:
				# multi-lane two-way: solid center line
				_strip(mk, pts, cum, sa, sb, x_div, MARK_W)
			else:
				_dashed(mk, pts, cum, sa, sb, x_div, MARK_W, dash, gap)
		# lane dividers within each direction
		for li in range(1, lf):
			var off := x_div + li * lw
			_dashed(mk, pts, cum, s0 + (0.0), s1 - solid_b * 0.75, off, MARK_W, dash, gap)
			if solid_b > 0.0:
				_strip(mk, pts, cum, maxf(s0, s1 - solid_b * 0.75), s1, off, MARK_W)
		for li in range(1, lb):
			var off2 := x_div - li * lw
			_dashed(mk, pts, cum, s0 + solid_a * 0.75, s1, off2, MARK_W, dash, gap)
			if solid_a > 0.0:
				_strip(mk, pts, cum, s0, minf(s1, s0 + solid_a * 0.75), off2, MARK_W)
		# edge lines on fast roads
		if not urban:
			var hw: float = e.width * 0.5
			_strip(mk, pts, cum, s0, s1, hw - 0.25, 0.15)
			_strip(mk, pts, cum, s0, s1, -hw + 0.25, 0.15)
	# cycle lane separation lines (any class)
	if e.cyc_r > 0.0:
		_strip(mk, pts, cum, s0, s1, e.width * 0.5 - e.park_r - e.cyc_r, 0.25)
	if e.cyc_l > 0.0:
		_strip(mk, pts, cum, s0, s1, -e.width * 0.5 + e.park_l + e.cyc_l, 0.25)
	# stop lines at signalized junctions
	if sig_b and lf > 0 and length > 4.0:
		var a_off := x_div
		var b_off := x_div + lf * lw
		_cross_bar(mk, pts, cum, s1 - 0.6, a_off, b_off, 0.4)
	if sig_a and lb > 0 and length > 4.0:
		var a2 := x_div - lb * lw
		var b2 := x_div if not e.oneway else x_div
		if not e.oneway:
			_cross_bar(mk, pts, cum, s0 + 0.6, a2, b2, 0.4)
	# pedestrian crossings
	for c in e.crossings:
		var s: float = c.s
		# also inside the cut at a junction (big merged junctions cut deep, the crossing is still there)
		if s < 1.5 or s > e.len - 1.5:
			continue
		var hw2: float = e.width * 0.5
		if c.kind == "zebra":
			var x := -hw2 + 0.25
			while x < hw2 - 0.25:
				_strip(mk, pts, cum, s - 2.0, s + 2.0, x + 0.25, 0.5)
				x += 1.0
		elif c.kind == "signals":
			for side in [-1.0, 1.0]:
				var ss: float = s + side * 2.0
				var x2 := -hw2
				while x2 < hw2:
					_cross_bar(mk, pts, cum, ss, x2, minf(x2 + 0.5, hw2), 0.25)
					x2 += 1.0


## Pedestrian crossing at point p across a road running in direction d with half width hw (used for
## crossings on pieces removed inside merged junctions; same look as on edges).
func _crossing_at(l: MeshLayer, p: Vector2, d: Vector2, hw: float, kind: String) -> void:
	var r := Geo.right_of(d)
	if kind == "zebra":
		var x := -hw + 0.25
		while x < hw - 0.25:
			var c := p + r * (x + 0.25)
			_rect(l, c, d, 2.0, 0.25)
			x += 1.0
	elif kind == "signals":
		for side in [-1.0, 1.0]:
			var x2 := -hw
			while x2 < hw:
				var c2: Vector2 = p + d * (side * 2.0) + r * (x2 + minf(0.5, hw - x2) * 0.5)
				_rect(l, c2, r, minf(0.5, hw - x2) * 0.5, 0.125)
				x2 += 1.0


## Flat rectangle centred at c, half length hl along d and half width hw across.
func _rect(l: MeshLayer, c: Vector2, d: Vector2, hl: float, hw: float) -> void:
	var r := Geo.right_of(d)
	l.quad(Geo.v3(c - d * hl - r * hw, Y_MARK), Geo.v3(c + d * hl - r * hw, Y_MARK), Geo.v3(c + d * hl + r * hw, Y_MARK),
		Geo.v3(c - d * hl + r * hw, Y_MARK), Vector3.UP)


## A bar perpendicular to the road at arc length s spanning lateral offsets [x0, x1].
func _cross_bar(l: MeshLayer, pts: PackedVector2Array, cum: PackedFloat32Array, s: float, x0: float, x1: float, thickness: float) -> void:
	var smp := Geo.sample(pts, cum, s)
	var p: Vector2 = smp[0]
	var d: Vector2 = smp[1]
	var r := Geo.right_of(d)
	var a := p + r * x0 - d * thickness * 0.5
	var b := p + r * x1 - d * thickness * 0.5
	var c := p + r * x1 + d * thickness * 0.5
	var dd := p + r * x0 + d * thickness * 0.5
	l.quad(Geo.v3(a, Y_MARK), Geo.v3(b, Y_MARK), Geo.v3(c, Y_MARK), Geo.v3(dd, Y_MARK), Vector3.UP)


# ------------------------------------------------------------------------------------------
# Junctions
# ------------------------------------------------------------------------------------------

func _junction(ni: int) -> void:
	var n: Dictionary = net.nodes[ni]
	var poly: PackedVector2Array = n.get("polygon", PackedVector2Array())
	if poly.size() < 3:
		return
	var ck := chunk_of(n.pos)
	var asp := layer(ck, "asphalt")
	asp.polygon_up(poly, Y_ROAD, 1.0, Color.WHITE, n.get("holes", []))
	for extra in n.get("extra_polys", []):
		asp.polygon_up(extra, Y_ROAD, 1.0)
	for c in n.get("crossings", []):
		_crossing_at(layer(ck, "mark"), c.p, c.d, c.hw, c.kind)
	# corner sidewalks
	for corner in n.get("corners", []):
		var sw: float = corner.sw
		if sw <= 0.0:
			continue
		var curve: PackedVector2Array = corner.pts
		if curve.size() < 2 or curve[0].distance_to(curve[curve.size() - 1]) < 0.05:
			continue
		var o1 := Geo.offset_polyline(curve, sw)
		var o2 := Geo.offset_polyline(curve, -sw)
		var mid := curve[curve.size() >> 1]
		var outer := o1 if Geo.polygon_centroid(o1).distance_to(n.pos) > Geo.polygon_centroid(o2).distance_to(n.pos) else o2
		# center reference for curb normal: junction center
		var center := PackedVector2Array()
		for p in curve:
			center.append(n.pos)
		_sidewalk_strip(ck, curve, outer, center, true, _area_clips(n))
