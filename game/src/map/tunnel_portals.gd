class_name TunnelPortals
extends RefCounted
## Tunnel portals (#31): where a road or a railway goes below the surface, a concrete mouth with a dark
## opening, covered by a short earth berm. The meshers register portals (add), MapBuilder builds them once
## both are done (build). Portals of parallel tubes (two carriageways, two tracks) become one structure.
## The covered part stops short of roads, junction areas and railways that cross over the tunnel.

const CLEAR := {"road": 4.8, "rail": 5.2}   # clear height of the opening (m)
const LINTEL := 1.0       # concrete above the opening
const WALL := 0.9         # outer walls and the pillars between openings
const DEPTH := 6.0        # covered part (dark inside)
const BERM := 7.0         # earth slope behind it, down to the ground
const MIN_COVER := 1.5    # always at least a headwall this deep, even if a road crosses right behind it
const WING := 4.0         # retaining walls along the approach
const FRONT_STRIP := 0.8  # concrete edge on top of the mouth, the rest of the top is earth
const MERGE_ALONG := 8.0  # portals of parallel tubes this close along their direction become one ...
const MERGE_GAP := 4.0    # ... if the gap between their openings is smaller than this
const GRID := 32.0

var specs: Array = []     # {p: Vector2, d: Vector2 (into the tunnel), wl, wr (opening edges left/right of p), kind, own}
var built := 0            # structures made by build()
var footprints: Array = []   # ground plan of every structure with 2 m around it (trees and lamps keep out)
var _fp_cells := {}          # Vector2i -> Array[footprint index]

var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_hw := PackedFloat32Array()
var _seg_owner := PackedInt32Array()   # road edge index, or rail_owner(i) for surface railway i
var _polys: Array = []    # [polygon, rect, node_owner(node)]
var _cells := {}          # Vector2i -> Array[int]: segment index, or -1 - polygon index


## Register a portal at p, d pointing into the tunnel, the opening reaching wl to the left and wr to the right.
## own: what leads up to the portal (edge indices, node_owner(node), rail_owner(rail)); it only stops the covered
## part where it reaches further into the tunnel than p.
func add(p: Vector2, d: Vector2, wl: float, wr: float, kind: String, own: Array = []) -> void:
	specs.append({"p": p, "d": d.normalized(), "wl": wl, "wr": wr, "kind": kind, "own": own})


static func node_owner(ni: int) -> int:
	return -1000000 - ni


static func rail_owner(ri: int) -> int:
	return -2 - ri


## Builds all portals into layers "portal", "portal_dark", "portal_green" of `mesher` (CityMesher: layer(), chunk_of()).
func build(net: RoadNet, rails: Array, mesher: Object) -> void:
	if specs.is_empty():
		return
	_index(net, rails)
	for g in _cluster():
		_build_one(g, mesher)
		built += 1


# ------------------------------------------------------------------------------------------
# What may not be covered: visible roads, junction areas and surface railways
# ------------------------------------------------------------------------------------------

func _index(net: RoadNet, rails: Array) -> void:
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if e.get("under", false):
			continue
		var s0: float = e.trim_a
		var s1: float = float(e.len) - float(e.trim_b)
		if s1 - s0 < 0.1:
			continue
		var hw: float = float(e.width) * 0.5 + maxf(float(e.sw_l), float(e.sw_r))
		_add_line(Geo.sub_polyline(e.pts, e.cum, s0, s1), hw, ei)
	for ri in rails.size():
		_add_line(rails[ri].pts, 1.8, rail_owner(ri))
	for ni in net.nodes.size():
		var n: Dictionary = net.nodes[ni]
		if n.get("under", false):
			continue
		var polys: Array = [n.get("polygon", PackedVector2Array())] + n.get("extra_polys", [])
		for poly in polys:
			if (poly as PackedVector2Array).size() < 3:
				continue
			var r := Rect2(poly[0], Vector2.ZERO)
			for p in poly:
				r = r.expand(p)
			_polys.append([poly, r, node_owner(ni)])
			_add_cells(r, -_polys.size())


func _add_line(pts: PackedVector2Array, hw: float, owner: int) -> void:
	for i in pts.size() - 1:
		var si := _seg_a.size()
		_seg_a.append(pts[i])
		_seg_b.append(pts[i + 1])
		_seg_hw.append(hw)
		_seg_owner.append(owner)
		_add_cells(Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(hw), si)


func _add_cells(r: Rect2, id: int) -> void:
	for gx in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
		for gz in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
			var k := Vector2i(gx, gz)
			if not _cells.has(k):
				_cells[k] = []
			_cells[k].append(id)


## Is q on a visible road, a junction area or a surface railway? own: owner -> portal point of the tube it
## leads to; such a thing only counts where it reaches further into the tunnel than that portal.
func _hit(q: Vector2, own: Dictionary) -> bool:
	for id in _cells.get(Vector2i(floori(q.x / GRID), floori(q.y / GRID)), []):
		var owner: int
		if id >= 0:
			if Geometry2D.get_closest_point_to_segment(q, _seg_a[id], _seg_b[id]).distance_to(q) >= _seg_hw[id]:
				continue
			owner = _seg_owner[id]
		else:
			var pr: Array = _polys[-1 - id]
			if not (pr[1] as Rect2).has_point(q) or not Geometry2D.is_point_in_polygon(q, pr[0]):
				continue
			owner = pr[2]
		if own.has(owner) and (q - (own[owner] as Vector2)).dot(_d) < 0.5:
			continue
		return true
	return false


# ------------------------------------------------------------------------------------------
# Grouping parallel tubes
# ------------------------------------------------------------------------------------------

func _cluster() -> Array:
	var n := specs.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	for i in n:
		var a: Dictionary = specs[i]
		var r := Geo.right_of(a.d)
		for j in range(i + 1, n):
			var b: Dictionary = specs[j]
			if b.kind != a.kind or (a.d as Vector2).dot(b.d) < 0.85:
				continue
			var rel: Vector2 = b.p - a.p
			if absf(rel.dot(a.d)) > MERGE_ALONG:
				continue
			var lat := rel.dot(r)
			var gap := maxf(lat - float(b.wl) - float(a.wr), -float(a.wl) - lat - float(b.wr))
			if gap < MERGE_GAP:
				var ri := _find(parent, i)
				var rj := _find(parent, j)
				if ri != rj:
					parent[rj] = ri
	var groups := {}
	for i in n:
		var root := _find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(specs[i])
	return groups.values()


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


# ------------------------------------------------------------------------------------------
# Geometry
# ------------------------------------------------------------------------------------------

var _o := Vector2.ZERO
var _d := Vector2.ZERO
var _r := Vector2.ZERO


## Point of the portal frame: `lat` metres to the right of the axis, `dep` metres into the tunnel, h above ground.
func _pt(lat: float, dep: float, h: float) -> Vector3:
	var q := _o + _r * lat + _d * dep
	return Vector3(q.x, h, q.y)


func _build_one(group: Array, mesher: Object) -> void:
	var dsum := Vector2.ZERO
	var osum := Vector2.ZERO
	for s in group:
		dsum += s.d
		osum += s.p
	_d = dsum.normalized()
	_r = Geo.right_of(_d)
	_o = osum / group.size()
	var front := INF
	for s in group:
		front = minf(front, ((s.p as Vector2) - _o).dot(_d))
	_o += _d * front
	# openings: the lateral spans of the tubes, overlapping ones (or with a pillar thinner than 0.6 m) joined
	var spans: Array = []
	for s in group:
		var lat := ((s.p as Vector2) - _o).dot(_r)
		spans.append(Vector2(lat - float(s.wl), lat + float(s.wr)))
	spans.sort_custom(func(x, y): return x.x < y.x)
	var open: Array = [spans[0]]
	for i in range(1, spans.size()):
		var last: Vector2 = open[open.size() - 1]
		if spans[i].x < last.y + 0.6:
			open[open.size() - 1] = Vector2(last.x, maxf(last.y, spans[i].y))
		else:
			open.append(spans[i])
	var x0: float = (open[0] as Vector2).x - WALL
	var x1: float = (open[open.size() - 1] as Vector2).y + WALL
	var kind: String = group[0].kind
	var own := {}
	for s in group:
		for o in s.own:
			own[o] = s.p
	var hc: float = CLEAR[kind]
	var ht := hc + LINTEL
	# how deep may it be covered before something on the surface crosses?
	var free := DEPTH + BERM
	var dep := 0.5
	while dep < DEPTH + BERM and free >= DEPTH + BERM:
		var lat := x0
		while lat <= x1 + 0.01:
			var q := _o + _r * lat + _d * dep
			if _hit(q, own):
				free = dep
				break
			lat += 1.0
		dep += 0.75
	var cover := clampf(free - 0.5, MIN_COVER, DEPTH)
	var berm := clampf(free - cover - 0.5, 0.0, BERM)
	var fp := PackedVector2Array()
	for c in [[x0 - 2.0, -WING - 1.0], [x1 + 2.0, -WING - 1.0], [x1 + 2.0, cover + berm + 1.0], [x0 - 2.0, cover + berm + 1.0]]:
		fp.append(_o + _r * float(c[0]) + _d * float(c[1]))
	footprints.append(fp)
	var fr := Rect2(fp[0], Vector2.ZERO)
	for q in fp:
		fr = fr.expand(q)
	for gx in range(floori(fr.position.x / GRID), floori(fr.end.x / GRID) + 1):
		for gz in range(floori(fr.position.y / GRID), floori(fr.end.y / GRID) + 1):
			var k := Vector2i(gx, gz)
			if not _fp_cells.has(k):
				_fp_cells[k] = []
			_fp_cells[k].append(footprints.size() - 1)
	var ck: Vector2i = mesher.chunk_of(_o)
	var con: MeshLayer = mesher.layer(ck, "portal")
	var dark: MeshLayer = mesher.layer(ck, "portal_dark")
	var green: MeshLayer = mesher.layer(ck, "portal_green")
	var back := -_v3(_d)
	# front face: pillars between and beside the openings, the lintel across
	var edges: Array = [x0]
	for o in open:
		edges.append(o.x)
		edges.append(o.y)
	edges.append(x1)
	for i in range(0, edges.size(), 2):
		var a: float = edges[i]
		var b: float = edges[i + 1]
		if b - a > 0.01:
			con.quad(_pt(a, 0, 0), _pt(b, 0, 0), _pt(b, 0, hc), _pt(a, 0, hc), back)
	con.quad(_pt(x0, 0, hc), _pt(x1, 0, hc), _pt(x1, 0, ht), _pt(x0, 0, ht), back)
	# dark inside every opening: floor, walls, ceiling and the far end
	for o in open:
		var a: float = o.x
		var b: float = o.y
		dark.quad(_pt(a, 0, 0.15), _pt(b, 0, 0.15), _pt(b, cover, 0.15), _pt(a, cover, 0.15), Vector3.UP)
		dark.quad(_pt(a, 0, hc), _pt(b, 0, hc), _pt(b, cover, hc), _pt(a, cover, hc), Vector3.DOWN)
		dark.quad(_pt(a, 0, 0), _pt(a, cover, 0), _pt(a, cover, hc), _pt(a, 0, hc), _v3(_r))
		dark.quad(_pt(b, 0, 0), _pt(b, cover, 0), _pt(b, cover, hc), _pt(b, 0, hc), -_v3(_r))
		dark.quad(_pt(a, cover, 0), _pt(b, cover, 0), _pt(b, cover, hc), _pt(a, cover, hc), back)
	# outside: side walls, the top (concrete edge, then earth), berm or back wall
	con.quad(_pt(x0, 0, 0), _pt(x0, cover, 0), _pt(x0, cover, ht), _pt(x0, 0, ht), -_v3(_r))
	con.quad(_pt(x1, 0, 0), _pt(x1, cover, 0), _pt(x1, cover, ht), _pt(x1, 0, ht), _v3(_r))
	var strip := minf(FRONT_STRIP, cover)
	con.quad(_pt(x0, 0, ht), _pt(x1, 0, ht), _pt(x1, strip, ht), _pt(x0, strip, ht), Vector3.UP)
	if cover > strip + 0.01:
		green.quad(_pt(x0, strip, ht), _pt(x1, strip, ht), _pt(x1, cover, ht), _pt(x0, cover, ht), Vector3.UP)
	if berm >= 2.0:
		var n := (Vector3.UP * berm + _v3(_d) * ht).normalized()
		green.quad(_pt(x0, cover, ht), _pt(x1, cover, ht), _pt(x1, cover + berm, 0), _pt(x0, cover + berm, 0), n)
		green.tri(_pt(x0, cover, ht), _pt(x0, cover, 0), _pt(x0, cover + berm, 0), -_v3(_r))
		green.tri(_pt(x1, cover, ht), _pt(x1, cover, 0), _pt(x1, cover + berm, 0), _v3(_r))
	else:
		con.quad(_pt(x0, cover, 0), _pt(x1, cover, 0), _pt(x1, cover, ht), _pt(x0, cover, ht), _v3(_d))
	# retaining walls along the approach, sloping down from the top of the mouth
	for side in [[x0, x0 + 0.5], [x1 - 0.5, x1]]:
		var a: float = side[0]
		var b: float = side[1]
		var hl := 0.6
		con.quad(_pt(a, 0, 0), _pt(a, -WING, 0), _pt(a, -WING, hl), _pt(a, 0, ht), -_v3(_r))
		con.quad(_pt(b, 0, 0), _pt(b, -WING, 0), _pt(b, -WING, hl), _pt(b, 0, ht), _v3(_r))
		var tn := (Vector3.UP * WING - _v3(_d) * (ht - hl)).normalized()
		con.quad(_pt(a, 0, ht), _pt(b, 0, ht), _pt(b, -WING, hl), _pt(a, -WING, hl), tn)
		con.quad(_pt(a, -WING, 0), _pt(b, -WING, 0), _pt(b, -WING, hl), _pt(a, -WING, hl), back)


## Does a portal stand at p (with 2 m around it)?
func covers(p: Vector2) -> bool:
	for fi in _fp_cells.get(Vector2i(floori(p.x / GRID), floori(p.y / GRID)), []):
		if Geometry2D.is_point_in_polygon(p, footprints[fi]):
			return true
	return false


## Removes the transforms (trees, lamps: chunk -> Array[Transform3D]) that stand on a portal. Returns how many.
func clear_xforms(by_chunk: Dictionary) -> int:
	if footprints.is_empty():
		return 0
	var n := 0
	for ck in by_chunk:
		var keep: Array = []
		for x: Transform3D in by_chunk[ck]:
			if covers(Vector2(x.origin.x, x.origin.z)):
				n += 1
			else:
				keep.append(x)
		by_chunk[ck] = keep
	return n


static func _v3(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)
