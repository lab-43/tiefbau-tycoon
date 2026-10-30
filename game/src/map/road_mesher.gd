class_name RoadMesher
extends RefCounted
## Builds road surfaces, sidewalks, curbs and German road markings from a RoadNet, grouped per chunk.

const Y_ROAD := 0.05
const Y_MARK := 0.062
const CURB := 0.12
const Y_SW := Y_ROAD + CURB
const MARK_W := 0.12
const Y_UNDER := 0.1      # roads below the surface: a flat band for the underground view (#31)
const MARKED_CLASSES := {"primary": 1, "secondary": 1, "tertiary": 1, "trunk": 1, "motorway": 1,
	"primary_link": 1, "secondary_link": 1, "tertiary_link": 1, "trunk_link": 1, "motorway_link": 1, "busway": 1}

var net: RoadNet
var chunk_size := 500.0
var origin := Vector2.ZERO
var chunks := {}   # Vector2i -> {"asphalt": MeshLayer, "sidewalk":..., "curb":..., "mark":...}
var terrain: Terrain = null   # ground heights (#8): layers lift their vertices onto it, bridges onto their deck
var marks: RoadMarkings   # markings across roads and junctions; marks.stats counts what was painted
var portals: TunnelPortals = null   # tunnel portals are registered here and built after the city (#31)
var under_stats := {"edges": 0, "nodes": 0, "portals": 0, "m": 0.0}


func _init(n: RoadNet, chunk: float, bounds_origin: Vector2) -> void:
	net = n
	chunk_size = chunk
	origin = bounds_origin
	marks = RoadMarkings.new(n)


## Roads with lane and centre lines (residential streets in Germany usually have none).
static func is_marked(e: Dictionary) -> bool:
	return MARKED_CLASSES.has(e.cls) and not e.narrow


## Lateral offset of the line between the two directions (right of the a -> b direction).
static func center_offset(e: Dictionary) -> float:
	var shift: float = ((e.park_l + e.cyc_l) - (e.park_r + e.cyc_r)) * 0.5
	var total: float = (e.lf + e.lb) * e.lw
	return -total * 0.5 + (0 if e.oneway else e.lb) * e.lw + shift


func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / chunk_size)), int(floor((p.y - origin.y) / chunk_size)))


func layer(ck: Vector2i, name: String) -> MeshLayer:
	# bridge decks get their own layers: their shader must not pull them down onto the ground (#8)
	if terrain and (not terrain.mode_deck.is_empty() or terrain.mode_node >= 0) and name in DECK_LAYERS:
		name += "_deck"
	if not chunks.has(ck):
		chunks[ck] = {}
	var c: Dictionary = chunks[ck]
	if not c.has(name):
		var l := MeshLayer.new()
		l.use_uvs = false   # no map shader reads UVs (they use world positions): saves memory and map file size
		l.terrain = terrain
		c[name] = l
	return c[name]


var progress_cb: Callable   # (fraction 0..1), called from the bake thread
const DECK_LAYERS := ["asphalt", "sidewalk", "mark"]

func build_all() -> void:
	var total := maxi(1, net.edges.size() + net.nodes.size())
	for ei in net.edges.size():
		if terrain:
			terrain.mode_deck = terrain.decks.get(ei, {})
		_edge(ei)
		if ei % 200 == 0 and progress_cb.is_valid():
			progress_cb.call(float(ei) / total)
	if terrain:
		terrain.mode_deck = {}
	for ni in net.nodes.size():
		if terrain:
			terrain.mode_node = ni if terrain.node_decks.has(ni) else -1
		_junction(ni)
		if ni % 200 == 0 and progress_cb.is_valid():
			progress_cb.call(float(net.edges.size() + ni) / total)
	if terrain:
		terrain.mode_node = -1


# ------------------------------------------------------------------------------------------

func _edge(ei: int) -> void:
	var e: Dictionary = net.edges[ei]
	var s0: float = e.trim_a
	var s1: float = e.len - e.trim_b
	if e.get("under", false):
		_under_edge(ei, e, s0, s1)
		return
	if s1 - s0 < 0.05:
		return
	var center := Geo.sub_polyline(e.pts, e.cum, s0, s1)
	if center.size() < 2:
		return
	center = Geo.densify(center, 3.0 if _on_deck() else 12.0)   # decks curve into the ground at their ends (#8)
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
	elif _on_deck():
		_embankment(ck, center, hw + e.sw_r, hw + e.sw_l)   # an approach ramp (#32)
	_edge_markings(ei, e, ck, s0, s1)


## A road below the surface (#31): no asphalt, sidewalks or markings on top, only a flat band for the underground
## view, and a portal where it meets a road on the surface.
func _under_edge(ei: int, e: Dictionary, s0: float, s1: float) -> void:
	under_stats.edges += 1
	if s1 - s0 >= 0.05:
		var center := Geo.densify(Geo.sub_polyline(e.pts, e.cum, s0, s1), 12.0)
		if center.size() >= 2:
			under_stats.m += s1 - s0
			var ck := chunk_of(Geo.sample(e.pts, e.cum, (s0 + s1) * 0.5)[0])
			var hw: float = e.width * 0.5
			var left := Geo.offset_polyline(center, -hw)
			var right := Geo.offset_polyline(center, hw)
			var ul := layer(ck, "under_road")
			for i in range(center.size() - 1):
				ul.quad(Geo.v3(left[i], Y_UNDER), Geo.v3(right[i], Y_UNDER), Geo.v3(right[i + 1], Y_UNDER),
					Geo.v3(left[i + 1], Y_UNDER), Vector3.UP)
	if portals == null:
		return
	for at_b in [false, true]:
		var ni: int = e.b if at_b else e.a
		var n: Dictionary = net.nodes[ni]
		if n.get("under", false):
			continue
		var s := clampf(s1 if at_b else s0, 0.0, e.len)
		var smp := Geo.sample(e.pts, e.cum, s)
		var d: Vector2 = -(smp[1] as Vector2) if at_b else smp[1]
		# the opening takes the road with its sidewalks; at a plain transition at least the road leading to it
		var wr: float = e.width * 0.5 + (e.sw_l if at_b else e.sw_r) + 0.4
		var wl: float = e.width * 0.5 + (e.sw_r if at_b else e.sw_l) + 0.4
		var own := [TunnelPortals.node_owner(ni)]
		for end in n.ends:
			own.append(end >> 1)
			var o: Dictionary = net.edges[end >> 1]
			if n.ends.size() == 2 and not o.get("under", false):
				var ow: float = o.width * 0.5 + maxf(o.sw_l, o.sw_r) + 0.4
				wl = maxf(wl, ow)
				wr = maxf(wr, ow)
		portals.add(smp[0], d, wl, wr, "road", own)
		under_stats.portals += 1


func _on_bridge_node(n: Dictionary) -> bool:
	for end in n.ends:
		if not net.edges[end >> 1].bridge:
			return false
	return true


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
		# reaches below the road surface: on slopes the exact road surface lies a few cm off the straight mesh
		cb.quad(Geo.v3(a, Y_ROAD - 0.15), Geo.v3(b, Y_ROAD - 0.15), Geo.v3(b, Y_SW), Geo.v3(a, Y_SW), n,
			Vector2(0, 0), Vector2(seg.length(), 0), Vector2(seg.length(), CURB), Vector2(0, CURB))
		# outer face down into the ground (on slopes the ground between two vertices can be lower)
		var n2 := -n
		cb.quad(Geo.v3(d, -0.4), Geo.v3(c, -0.4), Geo.v3(c, Y_SW), Geo.v3(d, Y_SW), n2)


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


func _on_deck() -> bool:
	return terrain != null and not terrain.mode_deck.is_empty()


func _inside_any(p: Vector2, clips: Array) -> bool:
	for cl in clips:
		if (cl[1] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, cl[0]):
			return true
	return false


## Embankment of a raised road that is no bridge (approach ramp, #32): grass slopes 1 : 1.5 from the outer edge
## (sidewalk included) down to the ground on both sides, from the height of the deck at its edge.
const SLOPE := 1.5

func _embankment(ck: Vector2i, center: PackedVector2Array, off_r: float, off_l: float) -> void:
	var dk: Dictionary = terrain.mode_deck
	terrain.mode_deck = {}   # the foot lies on the ground, the top is given as height above it
	var l := layer(ck, "embankment")
	for side in [1.0, -1.0]:
		var off: float = (off_r if side > 0 else off_l) + 0.2
		var tops := Geo.offset_polyline(center, off * side)
		var feet := PackedVector2Array()
		var ht := PackedFloat32Array()   # top height above its own ground (the edge of the deck, cross-slopes)
		for i in center.size():
			var r := terrain.deck_at(dk, tops[i]) - terrain.sample(tops[i].x, tops[i].y)
			var d := (center[mini(i + 1, center.size() - 1)] - center[maxi(i - 1, 0)]).normalized()
			feet.append(tops[i] + Geo.right_of(d) * side * (maxf(r, 0.0) * SLOPE + 0.05))
			ht.append(r - 0.05)
		for i in center.size() - 1:
			if ht[i] < 0.05 and ht[i + 1] < 0.05:
				continue
			var a := Geo.v3(tops[i], maxf(ht[i], 0.0))
			var b := Geo.v3(tops[i + 1], maxf(ht[i + 1], 0.0))
			var c := Geo.v3(feet[i + 1], 0.0)
			var f := Geo.v3(feet[i], 0.0)
			var out: Vector2 = Geo.right_of((center[i + 1] - center[i]).normalized()) * side
			var n := (Vector3.UP * SLOPE + Vector3(out.x, 0.0, out.y)).normalized()
			l.quad(a, b, c, f, n)
	terrain.mode_deck = dk


## Embankment around a raised junction area that does not lie on a bridge: slopes from the outline down to the
## ground, except where its roads leave it.
func _junction_embankment(ck: Vector2i, ni: int, poly: PackedVector2Array) -> void:
	var n: Dictionary = net.nodes[ni]
	var z: float = terrain.node_decks[ni]
	var mode := terrain.mode_node
	terrain.mode_node = -1
	var l := layer(ck, "embankment")
	var m := poly.size()
	for i in m:
		var a := poly[i]
		var b := poly[(i + 1) % m]
		if a.distance_to(b) < 0.2:
			continue
		var d := (b - a).normalized()
		var out := Geo.right_of(d)
		var mid := (a + b) * 0.5
		if Geometry2D.is_point_in_polygon(mid + out * 0.3, poly):
			out = -out
		# where a road leaves the junction area the ground in front is that road, not a slope
		var mouth := false
		for end in n.ends:
			var e: Dictionary = net.edges[end >> 1]
			var at_b: bool = (end & 1) == 1
			var smp := Geo.sample(e.pts, e.cum, float(e.len) - float(e.trim_b) if at_b else float(e.trim_a))
			if (smp[0] as Vector2).distance_to(mid) < float(e.width) * 0.5 + maxf(float(e.sw_l), float(e.sw_r)) + 0.5:
				mouth = true
				break
		if mouth:
			continue
		var ra := maxf(0.0, z - terrain.sample(a.x, a.y))
		var rb := maxf(0.0, z - terrain.sample(b.x, b.y))
		if ra < 0.1 and rb < 0.1:
			continue
		var fa := a + out * (ra * SLOPE + 0.05)
		var fb := b + out * (rb * SLOPE + 0.05)
		var nrm := (Vector3.UP * SLOPE + Vector3(out.x, 0.0, out.y)).normalized()
		l.quad(Geo.v3(a, ra - 0.05), Geo.v3(b, rb - 0.05), Geo.v3(fb, 0.0), Geo.v3(fa, 0.0), nrm)
	terrain.mode_node = mode


func _bridge_sides(ck: Vector2i, center: PackedVector2Array, off_r: float, off_l: float) -> void:
	var cb := layer(ck, "bridge")
	# the structure below the surface (#32 stage 2): as deep as BridgeHeights planned it, closed underneath
	var depth: float = terrain.mode_deck.get("depth", 1.2) if _on_deck() else 1.2
	var outer := {}
	for side in [1, -1]:
		var off: float = (off_r if side == 1 else off_l) + 0.35
		var line := Geo.offset_polyline(center, off * side)
		outer[side] = line
		var line_in := Geo.offset_polyline(center, (off - 0.35) * side)
		for i in range(line.size() - 1):
			var a := line[i]
			var b := line[i + 1]
			var dir := (b - a).normalized()
			var nout: Vector2 = Geo.right_of(dir) * side
			var n := Vector3(nout.x, 0, nout.y)
			# deck edge from the underside up to the parapet
			cb.quad(Geo.v3(a, -depth), Geo.v3(b, -depth), Geo.v3(b, Y_SW + 0.9), Geo.v3(a, Y_SW + 0.9), n)
			var ai := line_in[i]
			var bi := line_in[i + 1]
			cb.quad(Geo.v3(ai, Y_SW), Geo.v3(bi, Y_SW), Geo.v3(bi, Y_SW + 0.9), Geo.v3(ai, Y_SW + 0.9), -n)
			cb.quad(Geo.v3(ai, Y_SW + 0.9), Geo.v3(bi, Y_SW + 0.9), Geo.v3(b, Y_SW + 0.9), Geo.v3(a, Y_SW + 0.9), Vector3.UP)
	if not _on_deck():
		return
	var lr: PackedVector2Array = outer[1]
	var ll: PackedVector2Array = outer[-1]
	for i in range(mini(lr.size(), ll.size()) - 1):
		cb.quad(Geo.v3(ll[i], -depth), Geo.v3(lr[i], -depth), Geo.v3(lr[i + 1], -depth), Geo.v3(ll[i + 1], -depth), Vector3.DOWN)


## A junction area on a bridge (#32 stage 2): underside and edge with parapet around it, like the bridge sides,
## except where its roads leave it. Built while terrain.mode_node is set.
func _bridge_junction(ck: Vector2i, ni: int, poly: PackedVector2Array) -> void:
	var n: Dictionary = net.nodes[ni]
	var depth := 1.3
	var sw := 0.0
	for end in n.ends:
		var dk: Dictionary = terrain.decks.get(end >> 1, {})
		depth = maxf(depth, float(dk.get("depth", 1.3)))
		var e: Dictionary = net.edges[end >> 1]
		sw = maxf(sw, maxf(float(e.sw_l), float(e.sw_r)))
	# the sidewalks around the corners lie outside the asphalt polygon: the structure reaches around them
	var grown := poly
	var best := 0.0
	for o: PackedVector2Array in Geometry2D.offset_polygon(poly, sw + 0.35):
		if not Geometry2D.is_polygon_clockwise(o) and absf(Geo.polygon_area(o)) > best:
			best = absf(Geo.polygon_area(o))
			grown = o
	var cb := layer(ck, "bridge")
	var tri := cb.triangulate(grown)
	for t in range(0, tri.size(), 3):
		cb.tri(Geo.v3(grown[tri[t]], -depth), Geo.v3(grown[tri[t + 1]], -depth), Geo.v3(grown[tri[t + 2]], -depth), Vector3.DOWN)
	var m := grown.size()
	for i in m:
		var a := grown[i]
		var b := grown[(i + 1) % m]
		if a.distance_to(b) < 0.2:
			continue
		var mid := (a + b) * 0.5
		var mouth := false
		for end in n.ends:
			var e: Dictionary = net.edges[end >> 1]
			var at_b: bool = (end & 1) == 1
			var smp := Geo.sample(e.pts, e.cum, float(e.len) - float(e.trim_b) if at_b else float(e.trim_a))
			if (smp[0] as Vector2).distance_to(mid) < float(e.width) * 0.5 + maxf(float(e.sw_l), float(e.sw_r)) + 1.0:
				mouth = true
				break
		if mouth:
			continue
		var out := Geo.right_of((b - a).normalized())
		if Geometry2D.is_point_in_polygon(mid + out * 0.3, grown):
			out = -out
		var nv := Vector3(out.x, 0.0, out.y)
		var ai := a - out * 0.35
		var bi := b - out * 0.35
		cb.quad(Geo.v3(a, -depth), Geo.v3(b, -depth), Geo.v3(b, Y_SW + 0.9), Geo.v3(a, Y_SW + 0.9), nv)
		cb.quad(Geo.v3(ai, Y_SW), Geo.v3(bi, Y_SW), Geo.v3(bi, Y_SW + 0.9), Geo.v3(ai, Y_SW + 0.9), -nv)
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
	if _on_deck():
		sub = Geo.densify(sub, 3.0)
	var l0 := Geo.offset_polyline(sub, off - w * 0.5)
	var l1 := Geo.offset_polyline(sub, off + w * 0.5)
	for i in range(sub.size() - 1):
		l.quad(Geo.v3(l0[i], Y_MARK), Geo.v3(l1[i], Y_MARK), Geo.v3(l1[i + 1], Y_MARK), Geo.v3(l0[i + 1], Y_MARK), Vector3.UP)


func _dashed(l: MeshLayer, center: PackedVector2Array, cum: PackedFloat32Array, sa: float, sb: float, off: float, w: float, dash: float, gap: float) -> void:
	var s := sa + gap * 0.5
	while s < sb:
		_strip(l, center, cum, s, minf(s + dash, sb), off, w)
		s += dash + gap


## A longitudinal line from sa to sb at lateral offset off (dash <= 0: solid) that pauses over the
## intervals in excl (pedestrian crossings). Returns the painted length.
func _line(l: MeshLayer, center: PackedVector2Array, cum: PackedFloat32Array, sa: float, sb: float, off: float, w: float,
		dash: float, gap: float, excl: Array) -> float:
	var parts: Array = [Vector2(sa, sb)]
	for x in excl:
		var nxt: Array = []
		for p in parts:
			if x.y <= p.x or x.x >= p.y:
				nxt.append(p)
				continue
			if x.x > p.x:
				nxt.append(Vector2(p.x, x.x))
			if x.y < p.y:
				nxt.append(Vector2(x.y, p.y))
		parts = nxt
	var painted := 0.0
	for p in parts:
		if p.y - p.x < 0.3:
			continue
		if dash <= 0.0:
			_strip(l, center, cum, p.x, p.y, off, w)
			painted += p.y - p.x
		else:
			var s: float = p.x + gap * 0.5
			while s < p.y - 0.2:
				var e := minf(s + dash, p.y)
				_strip(l, center, cum, s, e, off, w)
				painted += e - s
				s += dash + gap
	return painted


## What crosses the lanes arriving at one end of edge ei: {"kind": "" | "halt" | "warte", "s": arc
## length of the line}. Haltlinie (Z 294) at signals and stop signs, Wartelinie (Z 341) where the
## road has to give way (sign, or a marked road meeting a main road). It sits 0.6 m before the end
## of the lanes and at least 1 m before a pedestrian crossing (RMS).
func _end_line(ei: int, e: Dictionary, at_b: bool, s0: float, s1: float) -> Dictionary:
	var none := {"kind": "", "s": s1 if at_b else s0}
	var n: Dictionary = net.nodes[e.b if at_b else e.a]
	var lanes: int = e.lf if at_b else e.lb
	if lanes == 0 or n.ends.size() < 3 or n.get("cont", false):
		return none
	var kind := ""
	var ref := ei * 2 + (1 if at_b else 0)
	if n.ctrl == "signals" or (e.get("stop_b", false) if at_b else e.get("stop_a", false)):
		kind = "halt"
	elif (e.giveway_b if at_b else e.giveway_a):
		kind = "warte"
	elif n.ctrl == "priority" and is_marked(e) and not (ref in n.get("major_ends", [])):
		kind = "warte"
	if kind == "":
		return none
	var hb := RoadMarkings.STOP_W * 0.5
	var s_end := s1 if at_b else s0
	var s := s_end - 0.6 if at_b else s_end + 0.6
	var room := 1.0 + hb + 2.0   # crossings are 4 m wide (s ± 2)
	for c in e.crossings:
		if not (c.kind in ["zebra", "signals"]):
			continue
		var cs: float = c.s
		if at_b and cs > s_end - 12.0 and cs < s_end + 3.0:
			s = minf(s, cs - room)
		elif not at_b and cs < s_end + 12.0 and cs > s_end - 3.0:
			s = maxf(s, cs + room)
	# crossings drawn on a merged junction area, just beyond the end of the lanes
	var smp := Geo.sample(e.pts, e.cum, s_end)
	var p_end: Vector2 = smp[0]
	var fwd: Vector2 = (smp[1] as Vector2) if at_b else -(smp[1] as Vector2)
	for c in n.get("crossings", []):
		if not (c.kind in ["zebra", "signals"]):
			continue
		var rel: Vector2 = (c.p as Vector2) - p_end
		var along := rel.dot(fwd)
		if absf(rel.dot(Geo.right_of(fwd))) < e.width * 0.5 + 3.0 and along > -3.0 and along < 6.0:
			if at_b:
				s = minf(s, s_end + along - room)
			else:
				s = maxf(s, s_end - along + room)
	if (at_b and s < s0 + 1.0) or (not at_b and s > s1 - 1.0):
		s = s_end - 0.6 if at_b else s_end + 0.6
	return {"kind": kind, "s": s}


## German markings along one road (RMS): centre line, lane dividers (solid towards signals, a
## Warnlinie in front), edge and cycle lines, stop and give-way lines, crossings and direction arrows.
## Lines through transitions and junctions: RoadMarkings.
func _edge_markings(ei: int, e: Dictionary, ck: Vector2i, s0: float, s1: float) -> void:
	var mk := layer(ck, "mark")
	var pts: PackedVector2Array = e.pts
	var cum: PackedFloat32Array = e.cum
	var urban: bool = e.speed <= 60.0 / 3.6 + 0.1
	var dash := 3.0 if urban else 6.0
	var gap := 6.0 if urban else 12.0
	var marked: bool = is_marked(e)
	var n_a: Dictionary = net.nodes[e.a]
	var n_b: Dictionary = net.nodes[e.b]
	# edge and cycle lines run on to the node at a transition; lane and centre lines are drawn through
	# it along the turn paths (RoadMarkings.through_lines)
	var e0 := 0.0 if n_a.get("cont", false) else s0
	var e1: float = e.len if n_b.get("cont", false) else s1
	var sig_a: bool = n_a.ctrl == "signals"
	var sig_b: bool = n_b.ctrl == "signals"
	var lf: int = e.lf
	var lb: int = e.lb
	var lw: float = e.lw
	var x_div := center_offset(e)
	var length := s1 - s0
	# lines across the lanes at both ends; the longitudinal lines stop there
	var end_b := _end_line(ei, e, true, s0, s1)
	var end_a := _end_line(ei, e, false, s0, s1)
	var sb_l: float = end_b.s - RoadMarkings.STOP_W * 0.5 if end_b.kind != "" else s1
	var sa_l: float = end_a.s + RoadMarkings.STOP_W * 0.5 if end_a.kind != "" else s0
	# longitudinal lines pause over pedestrian crossings
	var excl: Array = []
	for c in e.crossings:
		if c.kind == "zebra" or c.kind == "signals":
			excl.append(Vector2(c.s - 2.4, c.s + 2.4))
	if marked and length > 2.0 and sb_l - sa_l > 1.0:
		var solid_a := 20.0 if sig_a and lb > 0 else 0.0
		var solid_b := 20.0 if sig_b and lf > 0 else 0.0
		# centre line between the directions: solid towards a signal (Fahrstreifenbegrenzung) with a
		# Warnlinie in front, solid on roads with four lanes or more, else a Leitlinie
		if not e.oneway and lb > 0 and lf > 0:
			var multi := (lf + lb) >= 4
			# at a transition the centre line may stop early: the shift to the next road is spread
			var sa := sa_l + marks.center_back(ei * 2)
			var sb := sb_l - marks.center_back(ei * 2 + 1)
			if solid_a > 0.0:
				_line(mk, pts, cum, sa, minf(sa + solid_a, sb), x_div, MARK_W, 0.0, 0.0, excl)
				sa = minf(sa + solid_a, sb)
				if not multi:
					var w_end := minf(sa + RoadMarkings.WARN_LEN, sb)
					marks.stats.warnlinie_m += _line(mk, pts, cum, sa, w_end, x_div, MARK_W, RoadMarkings.WARN_DASH, RoadMarkings.WARN_GAP, excl)
					sa = w_end
			if solid_b > 0.0:
				_line(mk, pts, cum, maxf(sb - solid_b, sa), sb, x_div, MARK_W, 0.0, 0.0, excl)
				sb = maxf(sb - solid_b, sa)
				if not multi:
					var w_start := maxf(sb - RoadMarkings.WARN_LEN, sa)
					marks.stats.warnlinie_m += _line(mk, pts, cum, w_start, sb, x_div, MARK_W, RoadMarkings.WARN_DASH, RoadMarkings.WARN_GAP, excl)
					sb = w_start
			_line(mk, pts, cum, sa, sb, x_div, MARK_W, 0.0 if multi else dash, gap, excl)
		# lane dividers within each direction, solid for the last 15 m towards a signal
		for li in range(1, lf):
			var off := x_div + li * lw
			var cut_b := maxf(s0, sb_l - solid_b * 0.75)
			_line(mk, pts, cum, s0, cut_b, off, MARK_W, dash, gap, excl)
			if solid_b > 0.0:
				_line(mk, pts, cum, cut_b, sb_l, off, MARK_W, 0.0, 0.0, excl)
		for li in range(1, lb):
			var off2 := x_div - li * lw
			var cut_a := minf(s1, sa_l + solid_a * 0.75)
			_line(mk, pts, cum, cut_a, s1, off2, MARK_W, dash, gap, excl)
			if solid_a > 0.0:
				_line(mk, pts, cum, sa_l, cut_a, off2, MARK_W, 0.0, 0.0, excl)
		# edge lines on fast roads
		if not urban:
			var hw: float = e.width * 0.5
			_line(mk, pts, cum, e0, e1, hw - 0.25, 0.15, 0.0, 0.0, excl)
			_line(mk, pts, cum, e0, e1, -hw + 0.25, 0.15, 0.0, 0.0, excl)
	# cycle lane separation lines (any class)
	if e.cyc_r > 0.0:
		_line(mk, pts, cum, e0, e1, e.width * 0.5 - e.park_r - e.cyc_r, RoadMarkings.BROAD, 0.0, 0.0, excl)
	if e.cyc_l > 0.0:
		_line(mk, pts, cum, e0, e1, -e.width * 0.5 + e.park_l + e.cyc_l, RoadMarkings.BROAD, 0.0, 0.0, excl)
	# stop and give-way lines across the arriving lanes
	# (a Haltlinie spans the cycle lane next to the lanes as well)
	if end_b.kind != "" and length > 4.0:
		var x1b: float = x_div + lf * lw
		if end_b.kind == "halt" and e.cyc_r > 0.0:
			x1b = maxf(x1b, e.width * 0.5 - e.park_r)
		_end_bar(mk, pts, cum, end_b, x_div, x1b)
	if end_a.kind != "" and length > 4.0:
		var x0a: float = x_div - lb * lw
		if end_a.kind == "halt" and e.cyc_l > 0.0:
			x0a = minf(x0a, -e.width * 0.5 + e.park_l)
		_end_bar(mk, pts, cum, end_a, x0a, x_div)
	# direction arrows on multi-lane approaches, the first one 3 m in front of the stop line
	if marked:
		if lf >= 2 and n_b.ends.size() >= 3 and not n_b.get("cont", false):
			marks.lane_arrows(mk, ei, 0, (s1 - sb_l) + RoadMarkings.ARROW_BACK)
		if lb >= 2 and n_a.ends.size() >= 3 and not n_a.get("cont", false):
			marks.lane_arrows(mk, ei, 1, (sa_l - s0) + RoadMarkings.ARROW_BACK)
	# pedestrian crossings
	for c in e.crossings:
		var s: float = c.s
		# also inside the cut at a junction (big merged junctions cut deep, the crossing is still there)
		if s < 1.5 or s > e.len - 1.5:
			continue
		var hw2: float = e.width * 0.5
		if c.kind == "zebra":
			# Fußgängerüberweg (Z 293): 0.50 m stripes, 0.50 m apart, 4 m long
			marks.stats.zebra += 1
			var x := -hw2 + 0.25
			while x < hw2 - 0.25:
				_strip(mk, pts, cum, s - 2.0, s + 2.0, x + 0.25, 0.5)
				x += 1.0
		elif c.kind == "signals":
			# Fußgängerfurt: two dashed broad lines across the road, 4 m apart
			marks.stats.furt += 1
			for side in [-1.0, 1.0]:
				var ss: float = s + side * 2.0
				var x2 := -hw2
				while x2 < hw2:
					_cross_bar(mk, pts, cum, ss, x2, minf(x2 + RoadMarkings.FURT_DASH, hw2), RoadMarkings.BROAD)
					x2 += RoadMarkings.FURT_DASH + RoadMarkings.FURT_GAP


## Haltlinie (solid) or Wartelinie (broad dashes) at arc length end.s between lateral offsets x0, x1.
func _end_bar(mk: MeshLayer, pts: PackedVector2Array, cum: PackedFloat32Array, end: Dictionary, x0: float, x1: float) -> void:
	if end.kind == "halt":
		_cross_bar(mk, pts, cum, end.s, x0, x1, RoadMarkings.STOP_W)
		marks.stats.haltlinie += 1
	else:
		var x := x0 + RoadMarkings.GIVE_GAP * 0.5
		while x < x1 - 0.1:
			_cross_bar(mk, pts, cum, end.s, x, minf(x + RoadMarkings.GIVE_DASH, x1), RoadMarkings.GIVE_W)
			x += RoadMarkings.GIVE_DASH + RoadMarkings.GIVE_GAP
		marks.stats.wartelinie += 1


## Pedestrian crossing at point p across a road running in direction d with half width hw (used for
## crossings on pieces removed inside merged junctions; same look as on edges).
func _crossing_at(l: MeshLayer, p: Vector2, d: Vector2, hw: float, kind: String) -> void:
	var r := Geo.right_of(d)
	if kind == "zebra":
		marks.stats.zebra += 1
		var x := -hw + 0.25
		while x < hw - 0.25:
			var c := p + r * (x + 0.25)
			_rect(l, c, d, 2.0, 0.25)
			x += 1.0
	elif kind == "signals":
		marks.stats.furt += 1
		for side in [-1.0, 1.0]:
			var x2 := -hw
			while x2 < hw:
				var hl := minf(RoadMarkings.FURT_DASH, hw - x2) * 0.5
				var c2: Vector2 = p + d * (side * 2.0) + r * (x2 + hl)
				_rect(l, c2, r, hl, RoadMarkings.BROAD * 0.5)
				x2 += RoadMarkings.FURT_DASH + RoadMarkings.FURT_GAP


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
	var ck := chunk_of(n.pos)
	if n.get("under", false):
		# underground junction (#31): only the band of the underground view
		under_stats.nodes += 1
		var up: PackedVector2Array = n.get("polygon", PackedVector2Array())
		if up.size() >= 3:
			layer(ck, "under_road").polygon_up(up, Y_UNDER, 1.0, Color.WHITE, n.get("holes", []))
		for extra in n.get("extra_polys", []):
			layer(ck, "under_road").polygon_up(extra, Y_UNDER, 1.0)
		return
	if n.ends.size() >= 2:
		var mk0 := layer(ck, "mark")
		marks.through_lines(mk0, ni)
		marks.knot_lines(mk0, ni)
	var poly: PackedVector2Array = n.get("polygon", PackedVector2Array())
	if poly.size() < 3:
		return
	var asp := layer(ck, "asphalt")
	asp.polygon_up(poly, Y_ROAD, 1.0, Color.WHITE, n.get("holes", []))
	for extra in n.get("extra_polys", []):
		asp.polygon_up(extra, Y_ROAD, 1.0)
	if terrain and terrain.node_decks.has(ni) and not _on_bridge_node(n):
		_junction_embankment(ck, ni, poly)
	elif terrain and terrain.node_decks.has(ni):
		_bridge_junction(ck, ni, poly)
	var mk := layer(ck, "mark")
	for c in n.get("crossings", []):
		_crossing_at(mk, c.p, c.d, c.hw, c.kind)
	marks.sperrflaechen(mk, ni)
	# transitions between two roads (RoadNet._continuation_geometry): sidewalks along the joint line
	for sw_strip in n.get("cont_sw", []):
		_sidewalk_strip(ck, sw_strip[0], sw_strip[1], sw_strip[2], sw_strip[3], _area_clips(n))
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
