class_name JunctionMerge
extends RefCounted
## Groups the OSM nodes of one real junction into one RoadNet node (issue #5): dual carriageways,
## turn slips and short links between close nodes. In OSM a big junction is many nodes (the one
## from issue #5 has 23 within 120 m); building a junction area per node gave gaps, overlaps and
## zig-zag lanes. Internal road pieces are removed; which exits can be reached from which entry
## follows the travel directions of the removed pieces. Called from RoadNet.build().
##
## Idea after osm2streets "collapse short roads" (A/B Street, Apache-2.0): two nodes merge when the
## road between them leaves no room for a real road piece once both junction corners are cut out.

const MIN_PIECE := 5.0    # shortest road piece that may stay between two junction areas (m)
const ALWAYS := 6.0       # road pieces shorter than this always merge their nodes (m)
const MAX_SPAN := 70.0    # no two nodes of one group further apart than this (m)
const LOOP_LEN := 105.0   # a piece with both ends in one group but longer than this stays a loop road


## Merge the nodes of `net` (after degree-2 merging and smoothing, before junction geometry).
## Returns the number of groups made.
static func run(net: RoadNet) -> int:
	var nn: int = net.nodes.size()
	# setback every road end needs at its own node (curb corners, not clamped)
	var need := {}
	for ni in nn:
		if net.nodes[ni].ends.size() >= 2:
			var st: Dictionary = net.star(ni)
			for inf in st.infos:
				need[inf.ref] = inf.s
	var parent := PackedInt32Array()
	parent.resize(nn)
	for i in nn:
		parent[i] = i
	var members := {}   # root -> Array[int]
	var order: Array = []
	for ei in net.edges.size():
		order.append(ei)
	order.sort_custom(func(x, y): return net.edges[x].len < net.edges[y].len)
	for ei in order:
		var e: Dictionary = net.edges[ei]
		var a: int = e.a
		var b: int = e.b
		if a == b or int(e.rank) >= 20:
			continue   # self loops; roundabout rings keep their nodes
		var da: int = net.nodes[a].ends.size()
		var db: int = net.nodes[b].ends.size()
		if da < 2 or db < 2 or (da < 3 and db < 3):
			continue
		var gap: float = float(need.get(ei * 2, 0.6)) + float(need.get(ei * 2 + 1, 0.6)) + MIN_PIECE
		if e.len >= ALWAYS and e.len >= gap:
			continue
		var ra := _find(parent, a)
		var rb := _find(parent, b)
		if ra == rb:
			continue
		var ma: Array = members.get(ra, [a])
		var mb: Array = members.get(rb, [b])
		if not _span_ok(net, ma, mb):
			continue
		parent[rb] = ra
		members[ra] = ma + mb
		members.erase(rb)
	var groups := 0
	for root in members:
		var ms: Array = members[root]
		if ms.size() >= 2:
			_make_group(net, ms)
			groups += 1
	return groups


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _span_ok(net: RoadNet, ma: Array, mb: Array) -> bool:
	for x in ma:
		var px: Vector2 = net.nodes[x].pos
		for y in mb:
			if px.distance_to(net.nodes[y].pos) > MAX_SPAN:
				return false
	return true


## Replace the member nodes by one node at their centre. External road ends move to the new node and
## remember their member (mem_a / mem_b) so that RoadNet._build_connectors can check reachability.
static func _make_group(net: RoadNet, ms: Array) -> void:
	var mset := {}
	for m in ms:
		mset[m] = true
	var inner: Array = []
	var seen := {}
	for m in ms:
		for er in net.nodes[m].ends:
			var ei: int = er >> 1
			if seen.has(ei):
				continue
			seen[ei] = true
			var e: Dictionary = net.edges[ei]
			if mset.has(e.a) and mset.has(e.b) and e.len <= LOOP_LEN:
				inner.append(ei)
	# which member can be reached from which, along the internal pieces in their travel direction
	var adj := {}
	for m in ms:
		adj[m] = []
	for ei in inner:
		var e: Dictionary = net.edges[ei]
		if int(e.lf) > 0:
			adj[e.a].append(e.b)
		if int(e.lb) > 0:
			adj[e.b].append(e.a)
	var reach := {}
	for m in ms:
		var r := {m: true}
		var todo: Array = [m]
		while not todo.is_empty():
			var x: int = todo.pop_back()
			for y in adj[x]:
				if not r.has(y):
					r[y] = true
					todo.append(y)
		reach[m] = r
	var c := Vector2.ZERO
	var osm_ids: Array = []
	for m in ms:
		c += net.nodes[m].pos
		osm_ids.append(net.nodes[m].osm_id)
	c /= float(ms.size())
	var inner_polys: Array = []
	var inner_dirs: Array = []
	var inner_lines: Array = []   # for crossings on removed pieces (RoadNet._mark_crossings)
	for ei in inner:
		var e: Dictionary = net.edges[ei]
		for id in e.ids:
			osm_ids.append(id)
		var hw: float = e.width * 0.5
		var left := Geo.offset_polyline(e.pts, -hw)
		var right := Geo.offset_polyline(e.pts, hw)
		right.reverse()
		left.append_array(right)
		inner_polys.append(left)
		inner_dirs.append((e.pts[e.pts.size() - 1] - e.pts[0]).normalized())
		inner_lines.append({"pts": e.pts, "ids": e.ids, "hw": hw})
		e["dead"] = true
	var gi: int = net.nodes.size()
	net.nodes.append({"pos": c, "ends": [], "ctrl": "none", "osm_id": net.nodes[ms[0]].osm_id, "osm_ids": osm_ids,
		"polygon": PackedVector2Array(), "phases": {}, "group": ms.size(), "reach": reach, "inner_polys": inner_polys, "inner_dirs": inner_dirs, "inner_lines": inner_lines})
	for m in ms:
		for er in net.nodes[m].ends:
			var e: Dictionary = net.edges[er >> 1]
			if e.get("dead", false):
				continue
			if (er & 1) == 0:
				e.a = gi
				e["mem_a"] = m
			else:
				e.b = gi
				e["mem_b"] = m


## Union of polygons. Returns [outer polygons, holes]; a hole is kept only if no input covers its middle.
static func union_all(pieces: Array) -> Array:
	var outers: Array = []
	var holes: Array = []
	for p in pieces:
		var cur: PackedVector2Array = p
		if cur.size() < 3:
			continue
		var merged := true
		while merged:
			merged = false
			for j in outers.size():
				var res := Geometry2D.merge_polygons(outers[j], cur)
				var outs: Array = []
				var hs: Array = []
				for r in res:
					if Geometry2D.is_polygon_clockwise(r):
						hs.append(r)
					else:
						outs.append(r)
				if outs.size() == 1:
					cur = outs[0]
					holes.append_array(hs)
					outers.remove_at(j)
					merged = true
					break
		outers.append(cur)
	var keep: Array = []
	for h in holes:
		var m := Geo.polygon_centroid(h)
		var covered := false
		for p in pieces:
			if Geometry2D.is_point_in_polygon(m, p):
				covered = true
				break
		if not covered:
			keep.append(h)
	return [outers, keep]


## True if two non-adjacent edges of the closed polygon cross.
static func self_intersects(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var c := poly[j]
			var d := poly[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
	return false
