class_name AsphaltIndex
extends RefCounted
## Spatial index of the ground road surface as RoadMesher draws it: carriageways between their junction cuts
## and junction areas (with their islands as holes), without bridge decks and tunnels (#31). Answers whether a map point lies
## on asphalt and finds the nearest spot beside the road. CityMesher uses it to keep trees off the roads (#30).

const CELL := 25.0

var net: RoadNet
var _segs := {}    # Vector2i -> Array of [edge index, segment index]
var _areas := {}   # Vector2i -> Array of [polygon, bounding rect, holes]


func _init(n: RoadNet, terrain: Terrain = null) -> void:
	net = n
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if terrain != null and terrain.decks.has(ei):
			continue   # bridge deck: the ground below it is free
		if e.get("under", false):
			continue   # tunnel (#31): the ground above it is free
		if float(e.len) - float(e.trim_a) - float(e.trim_b) < 0.05:
			continue
		var pts: PackedVector2Array = e.pts
		var grow: float = float(e.width) * 0.5 + 0.5
		for i in range(pts.size() - 1):
			var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(grow)
			_put(_segs, r, [ei, i])
	for ni in net.nodes.size():
		if terrain != null and terrain.node_decks.has(ni):
			continue
		var nd: Dictionary = net.nodes[ni]
		if nd.get("under", false):
			continue
		var polys: Array = [nd.get("polygon", PackedVector2Array())] + nd.get("extra_polys", [])
		for i in polys.size():
			var poly: PackedVector2Array = polys[i]
			if poly.size() < 3:
				continue
			var r := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				r = r.expand(q)
			var holes: Array = nd.get("holes", []) if i == 0 else []
			if not holes.is_empty() and not _holes_cut(poly, holes):
				holes = []   # the mesh could not cut the islands out: they are drawn as asphalt
			_put(_areas, r, [poly, r, holes])


func _put(grid: Dictionary, r: Rect2, item: Array) -> void:
	for gx in range(int(floor(r.position.x / CELL)), int(floor(r.end.x / CELL)) + 1):
		for gz in range(int(floor(r.position.y / CELL)), int(floor(r.end.y / CELL)) + 1):
			var k := Vector2i(gx, gz)
			if not grid.has(k):
				grid[k] = []
			grid[k].append(item)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


## True if p lies on the ground road surface.
func on_asphalt(p: Vector2) -> bool:
	return not _hit(p, 0.0).is_empty()


## A spot for something standing at p (a tree trunk) that is not on asphalt: p itself if it is free,
## otherwise p moved straight out of the road to `margin` metres beside the curb (or the edge of the junction
## area). Returns null if that needs more than `max_shift` metres or ends on another road.
func clear_spot(p: Vector2, margin: float, max_shift: float):
	var c := p
	for i in 3:
		var h := _hit(c, margin)
		if h.is_empty():
			return c if c.distance_to(p) <= max_shift else null
		c = h.out
	return null


## {} if p is free; otherwise {"out": the nearest point `margin` beside the asphalt piece p lies deepest in}.
func _hit(p: Vector2, margin: float) -> Dictionary:
	var k := _cell(p)
	var best := {}
	var best_depth := -INF
	# carriageways: closest segment per edge, inside half the width and between the junction cuts
	var seen := {}
	for it in _segs.get(k, []):
		var ei: int = it[0]
		var e: Dictionary = net.edges[ei]
		var pts: PackedVector2Array = e.pts
		var cum: PackedFloat32Array = e.cum
		var si: int = it[1]
		var a := pts[si]
		var b := pts[si + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if seen.has(ei) and float(seen[ei]) <= d:
			continue
		seen[ei] = d
		var hw: float = float(e.width) * 0.5
		var s: float = cum[si] + a.distance_to(q)
		if d >= hw or s < float(e.trim_a) or s > float(e.len) - float(e.trim_b):
			continue
		var depth := hw - d
		if depth > best_depth:
			var out_dir := (p - q) / d if d > 0.01 else Geo.right_of((b - a).normalized())
			best_depth = depth
			best = {"out": q + out_dir * (hw + margin)}
	if not best.is_empty():
		return best
	# junction areas (islands are holes and free)
	for it in _areas.get(k, []):
		if not (it[1] as Rect2).has_point(p):
			continue
		var poly: PackedVector2Array = it[0]
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var in_hole := false
		for hole in it[2]:
			if Geometry2D.is_point_in_polygon(p, hole):
				in_hole = true
				break
		if in_hole:
			continue
		# nearest border (outline or island) and on through it
		var q := _closest_on_ring(poly, p)
		for hole in it[2]:
			var qh := _closest_on_ring(hole, p)
			if qh.distance_to(p) < q.distance_to(p):
				q = qh
		var d := q.distance_to(p)
		var out_dir := (q - p) / d if d > 0.01 else Vector2.RIGHT
		return {"out": q + out_dir * margin}
	return {}


## True if MeshLayer triangulates the junction area with its islands left out. When joining the islands to the
## outline fails, it falls back to the plain outline (_last_points is then the outline itself).
static func _holes_cut(poly: PackedVector2Array, holes: Array) -> bool:
	var ml := MeshLayer.new()
	var idx := ml.triangulate(poly, holes)
	return not idx.is_empty() and ml._last_points.size() > poly.size()


static func _closest_on_ring(ring: PackedVector2Array, p: Vector2) -> Vector2:
	var best := ring[0]
	var best_d := INF
	for i in ring.size():
		var q := Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best
