class_name BridgeHeights
extends RefCounted
## Heights of bridges and their approach ramps (#32), computed in the bake after the road network and the ground.
## OSM tells only that a bridge is higher (layer=1), not how high. So every bridge has to clear what it crosses:
## roads 4.70 m (or their OSM maxheight), railways 5.90 m (S-Bahn, U-Bahn, tram 4.80 m), paths 2.50 m, water by
## the span over it, plus its own structure. Cable-stayed and suspension bridges (man_made=bridge outlines) over
## water clear 50 m where their ramps allow it (Köhlbrandbrücke). Between these points a deck rises and falls at
## most as steep as its class allows (motorway 4 %, ramps 6 %, railway 2 %, paths 10 %), rounded off. Where a
## bridge is too short for that, the roads next to it rise as well: ramps on embankments. Where two bridges cross,
## the upper one clears the deck of the lower one (higher layer, else a slip road over a main carriageway, else
## the one with more room to its ends).
## The heights are the lowest profile that meets all of this: for every point the maximum over all requirements
## of "requirement minus grade times the distance along the network" (a max-plus Dijkstra), then rounded.
## Results: Terrain.decks / node_decks (road edges, junctions), rail_decks and path_decks for CityMesher.

const CLEAR_ROAD := 4.7
const CLEAR_RAIL := 5.9
const CLEAR_METRO := 4.8      # S-Bahn and U-Bahn (third rail), trams
const CLEAR_PATH := 2.5
const DEPTH := [1.3, 1.6, 0.8]   # structure under the surface: road, railway, path bridges
const BIG_STRUCTURES := ["cable-stayed", "suspension"]
const BIG_CLEAR := 50.0       # Köhlbrandbrücke: 53 m above the water
const BIG_DEPTH := 3.0
const MARGIN := 0.2           # a little extra above every requirement
const CREST := [15.0, 40.0, 6.0]   # the crest over a requirement is rounded over this length on each side
const RAISED := 0.05          # higher than this above the ground counts as raised
const STEP := 2.0             # profile stations (Terrain.DECK_STEP)
const PARALLEL_GAP := 3.5     # a path this close beside a raised road and parallel to it rides along at its height
const GRID := 32.0

enum {ROAD, RAIL, PATH}

var terrain: Terrain
var net: RoadNet
var data: OsmData
var links: Array = []         # carriers of all three networks (see _add_link)
var nodes: Array = [[], [], []]   # per network: {pos, ground, links: Array[int]}
var profiles := {}            # link index -> PackedFloat32Array (heights at evenly spaced stations)
var origins := {}             # link index -> PackedInt32Array: the bridge (chain) whose requirement set each station
var chain := PackedInt32Array()   # link index -> bridge chain (connected bridge links), -1 for other links
var rail_decks := {}          # rail way index -> Terrain deck
var path_decks := {}          # path way index -> Terrain deck
var crossings: Array = []     # {link, lo, hi, s, lower (link or -1 = water), ls, clear, base, big}
var stats := {}

var _seg := {}                # Vector2i -> Array of [link, segment]
var _room := []               # per network: PackedFloat32Array, distance of a node along bridges to their end
var _v := []                  # per network: node heights of the current solution
var _water: Array = []        # [polygon, rect, level]
var _water_grid := {}
var _big: Array = []          # outlines of cable-stayed and suspension bridges


func _init(t: Terrain, n: RoadNet, d: OsmData) -> void:
	terrain = t
	net = n
	data = d


## Computes all heights and stores them in the terrain (roads) and in rail_decks / path_decks.
func run() -> void:
	var t0 := Time.get_ticks_msec()
	_build_networks()
	_index_water()
	_compute_room()
	_compute_chains()
	_find_crossings()
	var change := 0.0
	var it := 0
	while it < 6:
		var src := _sources()
		var before := profiles.duplicate()
		profiles.clear()
		origins.clear()
		for nid in 3:
			_solve(nid, src)
		change = _max_change(before)
		stats["change_%d" % it] = change
		it += 1
		if change < 0.05:
			break
	_store()
	stats["iterations"] = it
	stats["ms"] = Time.get_ticks_msec() - t0


func summary() -> String:
	var bn: Array = stats.get("by_net", [0.0, 0.0, 0.0])
	return "Brücken: %d Kreuzungen darunter, %d Abschnitte angehoben (%.1f km: Straßen %.1f, Gleise %.1f, Wege %.1f; davon Rampen ohne Brückentag %.1f km), höchster Punkt %.0f m über Grund (%d ms)" % [
		crossings.size(), int(stats.get("raised", 0)), float(stats.get("raised_m", 0.0)) / 1000.0,
		float(bn[0]) / 1000.0, float(bn[1]) / 1000.0, float(bn[2]) / 1000.0,
		float(stats.get("ramp_m", 0.0)) / 1000.0, float(stats.get("max_height", 0.0)), int(stats.get("ms", 0))]


# ------------------------------------------------------------------------------------------
# Networks: road edges, railway ways, path ways
# ------------------------------------------------------------------------------------------

func _build_networks() -> void:
	for ni in net.nodes.size():
		var p: Vector2 = net.nodes[ni].pos
		nodes[ROAD].append({"pos": p, "ground": terrain.sample(p.x, p.y), "links": []})
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if e.get("under", false):
			continue   # tunnels stay where they are (#31)
		var hw: float = float(e.width) * 0.5 + maxf(float(e.sw_l), float(e.sw_r))
		_add_link(ROAD, ei, e.a, e.b, e.pts, e.cum, float(e.trim_a), float(e.len) - float(e.trim_b), bool(e.bridge),
			hw, int(e.layer), String(e.cls), float(e.get("maxheight", 0.0)))
	# A junction area follows the ground unless it is raised; "raised" means above its lowest point, where its roads
	# leave it (otherwise a ramp could end between the ground at the edge and the ground at the node: a step).
	for l in links:
		for end in [[int(l.a), float(l.u0)], [int(l.b), float(l.u1)]]:
			var p: Vector2 = Geo.sample(l.pts, l.cum, end[1])[0]
			nodes[ROAD][end[0]].ground = minf(float(nodes[ROAD][end[0]].ground), terrain.sample(p.x, p.y))
	_line_network(RAIL, data.rails)
	_line_network(PATH, data.paths)


func _line_network(nid: int, ways: Array) -> void:
	var keys := {}
	for wi in ways.size():
		var w: Dictionary = ways[wi]
		var pts: PackedVector2Array = w.pts
		if pts.size() < 2:
			continue
		var ends: Array = []
		for p in [pts[0], pts[pts.size() - 1]]:
			var k := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
			if not keys.has(k):
				keys[k] = nodes[nid].size()
				nodes[nid].append({"pos": p, "ground": terrain.sample(p.x, p.y), "links": []})
			ends.append(keys[k])
		var tags: Dictionary = w.tags
		var br := str(tags.get("bridge", ""))
		var ls := str(tags.get("layer", "0"))
		var cls := str(tags.get("railway", "")) if nid == RAIL else str(tags.get("highway", ""))
		var hw := 1.8 if nid == RAIL else clampf(RoadNet.parse_width(str(tags.get("width", ""))) * 0.5, 0.8, 4.0)
		var cum := Geo.cumulative(pts)
		_add_link(nid, wi, ends[0], ends[1], pts, cum, 0.0, cum[cum.size() - 1], br != "" and br != "no", hw,
			ls.to_int() if ls.is_valid_int() else 0, cls, 0.0)


func _add_link(nid: int, id: int, a: int, b: int, pts: PackedVector2Array, cum: PackedFloat32Array, u0: float, u1: float,
		bridge: bool, hw: float, layer: int, cls: String, maxheight: float) -> void:
	var total: float = cum[cum.size() - 1]
	u0 = clampf(u0, 0.0, total)
	u1 = clampf(u1, u0, total)
	var li := links.size()
	var pa: Vector2 = Geo.sample(pts, cum, u0)[0]
	var pb: Vector2 = Geo.sample(pts, cum, u1)[0]
	links.append({"net": nid, "id": id, "a": a, "b": b, "pts": pts, "cum": cum, "len": total, "u0": u0, "u1": u1,
		"g": grade(nid, cls), "bridge": bridge, "hw": hw, "layer": layer, "cls": cls, "maxheight": maxheight,
		"big": false, "ga": terrain.sample(pa.x, pa.y), "gb": terrain.sample(pb.x, pb.y)})
	nodes[nid][a].links.append(li)
	if b != a:
		nodes[nid][b].links.append(li)


## Steepest grade of a deck (rise per metre).
static func grade(nid: int, cls: String) -> float:
	if nid == RAIL:
		return 0.02 if cls == "rail" else 0.04
	if nid == PATH:
		return 0.10
	match cls:
		"motorway", "trunk":
			return 0.04
		"motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link":
			return 0.06
		"primary", "secondary":
			return 0.05
	return 0.07


## Clear height a link needs above it when a bridge crosses it.
func clearance(li: int) -> float:
	var l: Dictionary = links[li]
	match int(l.net):
		ROAD:
			var mh: float = l.maxheight
			if mh > 2.0 and mh < CLEAR_ROAD:
				return mh + 0.1
			return CLEAR_ROAD
		RAIL:
			return CLEAR_RAIL if l.cls == "rail" else CLEAR_METRO
	return CLEAR_PATH


## Clear height above water for a bridge that spans `span` metres of it.
static func water_clearance(span: float) -> float:
	if span < 15.0:
		return 1.0
	if span < 40.0:
		return 2.5
	if span < 100.0:
		return 4.0
	return 6.0


# ------------------------------------------------------------------------------------------
# What lies below a bridge
# ------------------------------------------------------------------------------------------

func _index_water() -> void:
	var levels: Dictionary = terrain.info.get("water_levels", {})
	for ai in data.areas.size():
		var a: Dictionary = data.areas[ai]
		if a.kind != "water" or (a.outer as PackedVector2Array).size() < 3:
			continue
		var r := Rect2(a.outer[0], Vector2.ZERO)
		for p in a.outer:
			r = r.expand(p)
		_water.append([a.outer, r, float(levels.get(ai, 0.0)), a.holes])
		for gx in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
			for gz in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
				var k := Vector2i(gx, gz)
				if not _water_grid.has(k):
					_water_grid[k] = []
				_water_grid[k].append(_water.size() - 1)
	for ba in data.bridge_areas:
		if str(ba.tags.get("bridge:structure", "")) in BIG_STRUCTURES:
			_big.append(ba.outer)


## Water level at p, or NAN if p is not on water.
func _water_at(p: Vector2) -> float:
	for wi in _water_grid.get(Vector2i(floori(p.x / GRID), floori(p.y / GRID)), []):
		var w: Array = _water[wi]
		if not (w[1] as Rect2).has_point(p) or not Geometry2D.is_point_in_polygon(p, w[0]):
			continue
		var in_hole := false
		for hole in w[3]:
			if Geometry2D.is_point_in_polygon(p, hole):
				in_hole = true
				break
		if not in_hole:
			return float(w[2])
	return NAN


## On a cable-stayed or suspension bridge? Inside its outline or within 25 m of it (an outline that reaches beyond
## the read area comes only in part, see OsmParser).
func _in_big(p: Vector2) -> bool:
	for outline in _big:
		var o: PackedVector2Array = outline
		if Geometry2D.is_point_in_polygon(p, o):
			return true
		for i in o.size():
			if Geometry2D.get_closest_point_to_segment(p, o[i], o[(i + 1) % o.size()]).distance_to(p) < 25.0:
				return true
	return false


## Distance of every node along bridges to the nearest end of its bridge (where it meets a normal road or ends).
func _compute_room() -> void:
	for nid in 3:
		var ns: Array = nodes[nid]
		var d := PackedFloat32Array()
		d.resize(ns.size())
		var heap := _Heap.new()
		for ni in ns.size():
			d[ni] = INF
			var land: bool = (ns[ni].links as Array).size() <= 1
			for li in ns[ni].links:
				if not links[li].bridge:
					land = true
			if land:
				d[ni] = 0.0
				heap.push(0.0, ni)
		while not heap.empty():
			var top := heap.pop()
			var ni: int = top[1]
			if top[0] > d[ni] + 0.001:
				continue
			for li in ns[ni].links:
				var l: Dictionary = links[li]
				if not l.bridge:
					continue
				var m: int = l.b if int(l.a) == ni else l.a
				var nd: float = d[ni] + float(l.len)
				if nd < d[m]:
					d[m] = nd
					heap.push(nd, m)
		_room.append(d)


## Bridge links that share a node form one chain (one structure, its requirements belong together).
func _compute_chains() -> void:
	chain.resize(links.size())
	for li in links.size():
		chain[li] = li if links[li].bridge else -1
	for nid in 3:
		for nd in nodes[nid]:
			var first := -1
			for li in nd.links:
				if not links[li].bridge:
					continue
				if first < 0:
					first = li
				else:
					var ra := _find(first)
					var rb := _find(li)
					if ra != rb:
						chain[rb] = ra
	for li in links.size():
		if chain[li] >= 0:
			chain[li] = _find(li)


func _find(i: int) -> int:
	while chain[i] != i:
		chain[i] = chain[chain[i]]
		i = chain[i]
	return i


## Room of a bridge link at arc length s: how far along the bridge to its nearest end.
func room_at(li: int, s: float) -> float:
	var l: Dictionary = links[li]
	var d: PackedFloat32Array = _room[int(l.net)]
	return minf(d[int(l.a)] + s, d[int(l.b)] + float(l.len) - s)


## Height at distance d from a requirement of height hh: a rounded crest (parabola over the first `crest` metres),
## then falling with the full grade g. Never below the plain cone hh - g * d.
static func cone(hh: float, d: float, g: float, crest: float) -> float:
	if d < crest:
		return hh - d * d * g / (2.0 * crest)
	return hh + g * crest * 0.5 - g * d


## Of two bridges crossing each other, is link i (at s) above link j (at t)?
func above(i: int, s: float, j: int, t: float) -> bool:
	var a: Dictionary = links[i]
	var b: Dictionary = links[j]
	if int(a.layer) != int(b.layer):
		return int(a.layer) > int(b.layer)
	var sa: bool = String(a.cls).ends_with("_link")
	var sb: bool = String(b.cls).ends_with("_link")
	if sa != sb:
		return sa
	var ra := room_at(i, s)
	var rb := room_at(j, t)
	if absf(ra - rb) > 1.0:
		return ra > rb
	return i > j


func _find_crossings() -> void:
	for li in links.size():
		var pts: PackedVector2Array = links[li].pts
		for i in pts.size() - 1:
			var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1])
			for gx in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
				for gz in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
					var k := Vector2i(gx, gz)
					if not _seg.has(k):
						_seg[k] = []
					_seg[k].append(Vector2i(li, i))
	for li in links.size():
		var l: Dictionary = links[li]
		if not l.bridge:
			continue
		_cross_lines(li)
		_cross_water(li)


func _cross_lines(li: int) -> void:
	var l: Dictionary = links[li]
	var pts: PackedVector2Array = l.pts
	var cum: PackedFloat32Array = l.cum
	var seen := {}
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var r := Rect2(a, Vector2.ZERO).expand(b)
		for gx in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
			for gz in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
				for item in _seg.get(Vector2i(gx, gz), []):
					var lj: int = item.x
					var j: int = item.y
					if lj == li or seen.has(Vector3i(i, lj, j)):
						continue
					seen[Vector3i(i, lj, j)] = true
					var m: Dictionary = links[lj]
					if int(m.net) == int(l.net) and (int(m.a) in [l.a, l.b] or int(m.b) in [l.a, l.b]):
						continue   # meets this bridge at one of its nodes
					var mp: PackedVector2Array = m.pts
					var x = Geometry2D.segment_intersects_segment(a, b, mp[j], mp[j + 1])
					if x == null:
						continue
					var s: float = cum[i] + a.distance_to(x)
					var t: float = float(m.cum[j]) + mp[j].distance_to(x)
					if s < 1.5 or s > float(l.len) - 1.5:
						continue
					if int(m.net) != ROAD and (t < 1.0 or t > float(m.len) - 1.0):
						continue   # a path or track that ends at the bridge comes up to it
					if m.bridge and not above(li, s, lj, t):
						continue   # this one passes below the other
					var da := (b - a).normalized()
					var db := (mp[j + 1] - mp[j]).normalized()
					var sn := maxf(absf(da.cross(db)), 0.25)
					var cs := sqrt(maxf(0.0, 1.0 - sn * sn))
					var half := minf(80.0, float(m.hw) / sn + float(l.hw) * cs / sn) + 0.5
					crossings.append({"link": li, "lo": s - half, "hi": s + half, "s": s, "lower": lj, "ls": t,
						"clear": clearance(lj), "base": 0.0, "big": false})


## Water under a bridge: every run of stations on water becomes one requirement over its whole length.
func _cross_water(li: int) -> void:
	var l: Dictionary = links[li]
	var total: float = l.len
	var n := maxi(2, int(ceil(total / 4.0)))
	var run_lo := -1.0
	var lvl := 0.0
	for k in n + 2:
		var s := total * k / n
		var wl := NAN
		if k <= n:
			wl = _water_at(Geo.sample(l.pts, l.cum, s)[0])
		if not is_nan(wl):
			if run_lo < 0.0:
				run_lo = s
				lvl = wl
			lvl = maxf(lvl, wl)
		elif run_lo >= 0.0:
			var hi := minf(s, total)
			var span := hi - run_lo
			var big := span > 100.0 and _in_big(Geo.sample(l.pts, l.cum, (run_lo + hi) * 0.5)[0])
			crossings.append({"link": li, "lo": run_lo, "hi": hi, "s": (run_lo + hi) * 0.5, "lower": -1, "ls": 0.0,
				"clear": BIG_CLEAR if big else water_clearance(span), "base": lvl, "big": big})
			run_lo = -1.0


# ------------------------------------------------------------------------------------------
# Solving
# ------------------------------------------------------------------------------------------

## Requirements per link: link index -> Array of [lo, hi, height].
func _sources() -> Dictionary:
	var src := {}
	for c in crossings:
		var li: int = c.link
		var l: Dictionary = links[li]
		var base: float = c.base
		if int(c.lower) >= 0:
			var ho := height_and_origin(int(c.lower), float(c.ls))
			base = ho.x
			if int(ho.y) >= 0 and int(ho.y) == chain[li]:
				# raised by this bridge itself (through its own ramps): measure from the ground, or it would
				# push itself up without end
				base = ground_at(int(c.lower), float(c.ls))
		var depth: float = BIG_DEPTH if c.big else DEPTH[int(l.net)]
		var hh: float = base + float(c.clear) + depth + MARGIN
		if c.big:
			# only as high as the bridge itself can climb: its ramps are part of the structure
			var cp: Vector2 = Geo.sample(l.pts, l.cum, float(c.s))[0]
			hh = minf(hh, terrain.sample(cp.x, cp.y) + float(l.g) * room_at(li, float(c.s)))
		if not src.has(li):
			src[li] = []
		src[li].append([float(c.lo), float(c.hi), hh, chain[li]])
	_paths_along_raised_roads(src)
	return src


## Height of link li at arc length s in the current solution (the ground where it is not raised).
func height_at(li: int, s: float) -> float:
	return height_and_origin(li, s).x


## (height, chain of the bridge that raised it or -1) of link li at arc length s.
func height_and_origin(li: int, s: float) -> Vector2:
	var l: Dictionary = links[li]
	var pr = profiles.get(li)
	if pr != null:
		var z: PackedFloat32Array = pr
		var step := float(l.len) / maxf(1.0, z.size() - 1.0)
		var zo: PackedInt32Array = origins[li]
		var k := clampi(roundi(s / maxf(step, 0.001)), 0, zo.size() - 1)
		return Vector2(Terrain._deck_lerp(z, step, s), zo[k])
	return Vector2(ground_at(li, s), -1)


func ground_at(li: int, s: float) -> float:
	var l: Dictionary = links[li]
	var p: Vector2 = Geo.sample(l.pts, l.cum, s)[0]
	return terrain.sample(p.x, p.y)


## A footway or cycleway mapped beside a raised road (a separate sidewalk) rides along at the road's height.
func _paths_along_raised_roads(src: Dictionary) -> void:
	var raised := {}
	for li in profiles:
		if int(links[li].net) == ROAD:
			raised[li] = true
	if raised.is_empty():
		return
	var cells := {}
	for li in raised:
		var l: Dictionary = links[li]
		var pts: PackedVector2Array = l.pts
		for i in pts.size() - 1:
			var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(float(l.hw) + PARALLEL_GAP + 4.0)
			for gx in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
				for gz in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
					var k := Vector2i(gx, gz)
					if not cells.has(k):
						cells[k] = []
					cells[k].append(Vector2i(li, i))
	for pi in links.size():
		var p: Dictionary = links[pi]
		if int(p.net) != PATH:
			continue
		var pts: PackedVector2Array = p.pts
		var cum: PackedFloat32Array = p.cum
		for i in pts.size() - 1:
			var ca := Vector2i(floori(pts[i].x / GRID), floori(pts[i].y / GRID))
			var cb := Vector2i(floori(pts[i + 1].x / GRID), floori(pts[i + 1].y / GRID))
			if not cells.has(ca) and not cells.has(cb):
				continue
			var seg_len := cum[i + 1] - cum[i]
			var dq := (pts[i + 1] - pts[i]).normalized()
			var m := maxi(1, int(ceil(seg_len / 4.0)))
			for k in m + 1:
				var q := pts[i].lerp(pts[i + 1], float(k) / m)
				var s := cum[i] + seg_len * k / m
				var best := INF
				var hh := 0.0
				var ho := -1
				for item in cells.get(Vector2i(floori(q.x / GRID), floori(q.y / GRID)), []):
					var rl: Dictionary = links[item.x]
					if rl.bridge and not p.bridge:
						continue   # a path on the ground beside (or under) a viaduct stays on the ground
					var a: Vector2 = rl.pts[item.y]
					var b: Vector2 = rl.pts[item.y + 1]
					var c := Geometry2D.get_closest_point_to_segment(q, a, b)
					var d := c.distance_to(q)
					if d > float(rl.hw) + PARALLEL_GAP + float(p.hw) or d >= best:
						continue
					if absf(dq.dot((b - a).normalized())) < 0.85:
						continue
					best = d
					var r := height_and_origin(item.x, float(rl.cum[item.y]) + a.distance_to(c))
					hh = r.x
					ho = int(r.y)
				if best < INF and hh > terrain.sample(q.x, q.y) + RAISED:
					if not src.has(pi):
						src[pi] = []
					src[pi].append([s - 2.0, s + 2.0, hh, ho])


## Lowest heights of network nid that meet all requirements with its grades, then the profiles of its raised links.
func _solve(nid: int, src: Dictionary) -> void:
	var ns: Array = nodes[nid]
	var v := PackedFloat32Array()
	var vo := PackedInt32Array()
	v.resize(ns.size())
	vo.resize(ns.size())
	for ni in ns.size():
		v[ni] = ns[ni].ground
		vo[ni] = -1
	var heap := _Heap.new()
	for li in src:
		var l: Dictionary = links[li]
		if int(l.net) != nid:
			continue
		var g: float = l.g
		var crest: float = CREST[nid]
		var lf: float = float(l.u1) - float(l.u0)
		for q in src[li]:
			var flo := clampf(float(q[0]), float(l.u0), float(l.u1)) - float(l.u0)
			var fhi := clampf(float(q[1]), float(l.u0), float(l.u1)) - float(l.u0)
			for end in [[int(l.a), cone(float(q[2]), flo, g, crest)], [int(l.b), cone(float(q[2]), lf - fhi, g, crest)]]:
				if end[1] > v[end[0]] + 0.001:
					v[end[0]] = end[1]
					vo[end[0]] = int(q[3])
					heap.push(-float(end[1]), end[0])
	while not heap.empty():
		var top := heap.pop()
		var ni: int = top[1]
		if -float(top[0]) < v[ni] - 0.001:
			continue
		for li in ns[ni].links:
			var l: Dictionary = links[li]
			if int(l.a) == int(l.b):
				continue
			var m: int = l.b if int(l.a) == ni else l.a
			var cand := _carry(l, v[ni], int(l.a) == ni)
			if cand > v[m] + 0.001:
				v[m] = cand
				vo[m] = vo[ni]
				heap.push(-cand, m)
	if _v.size() <= nid:
		_v.resize(nid + 1)
	_v[nid] = v
	for li in links.size():
		var l: Dictionary = links[li]
		if int(l.net) != nid:
			continue
		var has_src := src.has(li)
		if not has_src and v[int(l.a)] <= ns[int(l.a)].ground + RAISED and v[int(l.b)] <= ns[int(l.b)].ground + RAISED:
			continue
		var res := _profile(li, v[int(l.a)], v[int(l.b)], vo[int(l.a)], vo[int(l.b)], src.get(li, []))
		if not res.is_empty():
			profiles[li] = res[0]
			origins[li] = res[1]


## Height that a raised end (height h, at end a if from_a) leaves at the other end of link l's free length. It falls
## with the grade of the link; a ramp (not a bridge) also loses its height above the ground at least that fast, so on
## ground falling steeper than the grade it follows the ground down instead of running on as a long embankment.
static func _carry(l: Dictionary, h: float, from_a: bool) -> float:
	var drop: float = float(l.g) * (float(l.u1) - float(l.u0))
	var c := h - drop
	if not l.bridge:
		var g0: float = l.ga if from_a else l.gb
		var g1: float = l.gb if from_a else l.ga
		c = minf(c, g1 + (h - g0) - drop)
	return c


## [heights, origins] at evenly spaced stations along link li, rounded off; empty if it nowhere rises above the ground.
func _profile(li: int, va: float, vb: float, oa: int, ob: int, srcs: Array) -> Array:
	var l: Dictionary = links[li]
	var total: float = l.len
	var n := maxi(1, int(ceil(total / STEP)))
	var step := total / n
	var g: float = l.g
	var u0: float = l.u0
	var u1: float = l.u1
	var lf := u1 - u0
	var z := PackedFloat32Array()
	var gr := PackedFloat32Array()
	var zo := PackedInt32Array()
	z.resize(n + 1)
	gr.resize(n + 1)
	zo.resize(n + 1)
	var crest: float = CREST[int(l.net)]
	# An end whose junction is not raised lies on the ground, which in its junction area may be lower than at the
	# node itself: the profile follows the ground there instead of the node height (no step at the junction edge).
	var ns: Array = nodes[int(l.net)]
	if va <= float(ns[int(l.a)].ground) + RAISED:
		va = -INF
	if vb <= float(ns[int(l.b)].ground) + RAISED:
		vb = -INF
	var top := 0.0
	for k in n + 1:
		var s := step * k
		var p: Vector2 = Geo.sample(l.pts, l.cum, s)[0]
		var ground := terrain.sample(p.x, p.y)
		var f := clampf(s, u0, u1) - u0
		var h := ground
		var o := -1
		var ha := va - g * f
		var hb := vb - g * (lf - f)
		if not l.bridge:   # a ramp loses its height above the ground at least with its grade (see _carry)
			ha = minf(ha, ground + (va - float(l.ga)) - g * f)
			hb = minf(hb, ground + (vb - float(l.gb)) - g * (lf - f))
		if ha > h:
			h = ha
			o = oa
		if hb > h:
			h = hb
			o = ob
		for q in srcs:
			var flo := clampf(float(q[0]), u0, u1) - u0
			var fhi := clampf(float(q[1]), u0, u1) - u0
			var hq := cone(float(q[2]), maxf(0.0, maxf(flo - f, f - fhi)), g, crest)
			if hq > h:
				h = hq
				o = int(q[3])
		z[k] = h
		zo[k] = o
		gr[k] = ground
		top = maxf(top, h - ground)
	if top < RAISED:
		return []
	return [z, zo]


func _max_change(before: Dictionary) -> float:
	var m := 0.0
	var worst := -1
	for li in profiles:
		var a: PackedFloat32Array = profiles[li]
		var b = before.get(li)
		var d := 0.0
		if b == null or (b as PackedFloat32Array).size() != a.size():
			for x in a:
				d = maxf(d, x)
		else:
			for k in a.size():
				d = maxf(d, absf(a[k] - (b as PackedFloat32Array)[k]))
		if d > m:
			m = d
			worst = li
	for li in before:
		if not profiles.has(li) and m < 1.0:
			m = 1.0
			worst = li
	stats["worst_link"] = worst
	return m


## Profiles into decks: road edges and raised junctions into the terrain, railways and paths for CityMesher.
func _store() -> void:
	terrain.decks.clear()
	terrain.node_decks.clear()
	terrain.node_pos.clear()
	terrain.node_r.clear()
	var raised := 0
	var raised_m := 0.0
	var ramp_m := 0.0
	var by_net := [0.0, 0.0, 0.0]
	var top := 0.0
	for li in profiles:
		var l: Dictionary = links[li]
		var z: PackedFloat32Array = profiles[li]
		var n := z.size() - 1
		var gr := PackedFloat32Array()
		gr.resize(n + 1)
		var step := float(l.len) / maxf(1.0, n)
		var up := 0.0   # metres of this link raised above the ground
		for k in n + 1:
			var p: Vector2 = Geo.sample(l.pts, l.cum, step * k)[0]
			gr[k] = terrain.sample(p.x, p.y)
			top = maxf(top, z[k] - gr[k])
			if k > 0 and (z[k] - gr[k] > RAISED or z[k - 1] - gr[k - 1] > RAISED):
				up += step
		var dk := Terrain.make_deck(l.pts, l.cum, z, gr, float(l.hw) + 0.5)
		match int(l.net):
			ROAD:
				terrain.decks[int(l.id)] = dk
			RAIL:
				rail_decks[int(l.id)] = dk
			PATH:
				path_decks[int(l.id)] = dk
		raised += 1
		raised_m += up
		by_net[int(l.net)] += up
		if not l.bridge:
			ramp_m += up
	var v: PackedFloat32Array = _v[ROAD]
	for ni in v.size():
		if v[ni] > float(nodes[ROAD][ni].ground) + RAISED:
			terrain.node_decks[ni] = v[ni]
			terrain.node_pos[ni] = nodes[ROAD][ni].pos
			# its flat area reaches to where its roads leave it, across their width
			var r := 4.0
			for li in nodes[ROAD][ni].links:
				var l: Dictionary = links[li]
				var trim: float = float(l.u0) if int(l.a) == ni else float(l.len) - float(l.u1)
				r = maxf(r, Vector2(trim, float(l.hw)).length() + 1.0)
			terrain.node_r[ni] = r
	# highest surface of the map (mouse picking starts its ray above it, CameraRig.terrain_hit)
	var hi: float = terrain.info.get("max", 0.0)
	for li in profiles:
		for zz in (profiles[li] as PackedFloat32Array):
			hi = maxf(hi, zz)
	terrain.info["top"] = hi
	stats["raised"] = raised
	stats["raised_m"] = raised_m
	stats["ramp_m"] = ramp_m
	stats["by_net"] = by_net
	stats["max_height"] = top


# ------------------------------------------------------------------------------------------

## Small binary heap of [key, value] pairs, smallest key first.
class _Heap:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()

	func empty() -> bool:
		return keys.is_empty()

	func push(k: float, v: int) -> void:
		keys.append(k)
		vals.append(v)
		var i := keys.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> Array:
		var out := [keys[0], vals[0]]
		var last := keys.size() - 1
		_swap(0, last)
		keys.resize(last)
		vals.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return out

	func _swap(a: int, b: int) -> void:
		var tk := keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv := vals[a]
		vals[a] = vals[b]
		vals[b] = tv
