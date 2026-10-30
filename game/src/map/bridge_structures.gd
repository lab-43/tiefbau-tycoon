class_name BridgeStructures
extends RefCounted
## Bridge structures (#32, stage 2): piers under raised bridge decks and abutments where a bridge meets its ramp
## (or a raised junction) high above the ground. Deck undersides and edges come from the meshers
## (RoadMesher._bridge_sides / _bridge_junction, CityMesher._deck_sides); BridgeHeights gives the decks.
##
## Piers stand at the joints of a bridge (where its OSM ways meet) and in between at the spacing of its kind,
## at least half a spacing apart. They keep off what runs below: the asphalt of roads (with a margin), railways,
## paths, and water narrower than WATER_SPAN or under a cable-stayed span. A blocked pier moves along the bridge
## (up to SHIFT of the spacing), wide decks stand on several columns of which the free ones are built.
## Built into the mesher's "bridge" layer after the meshers ran (heights above the ground per vertex).

const SPAN := [32.0, 25.0, 20.0]   # pier spacing of road, railway and path bridges (m)
const BIG_SPAN := 50.0             # approach viaducts of cable-stayed and suspension bridges
const SHIFT := 0.35                # a blocked pier may move this share of the spacing along the bridge
const MIN_HEIGHT := 0.8            # decks lower than this above the ground need no pier or abutment
const WATER_SPAN := 80.0           # piers stand in water only under bridges over water at least this wide
const ROAD_GAP := 1.0              # m between a pier and the asphalt of a road below
const RAIL_GAP := 2.6              # m from a pier to the centre line of a railway below
const PATH_GAP := 0.5              # m beyond the half width of a path below
const WALL_T := 1.0                # wall piers: thickness along the bridge
const COLUMN := 1.2                # columns under wide road decks (square, m)
const WIDE := 13.0                 # decks wider than this stand on columns
const SMALL := 5.0                 # decks narrower than this (paths) stand on one slim column
const EMBED := 0.5                 # piers and abutments reach this far into the ground
const GRID := 25.0

var bh: BridgeHeights
var terrain: Terrain
var net: RoadNet
var asphalt: AsphaltIndex
var piers: Array = []        # {p, d (along the bridge), w (across), t (along), top, bottom, link}
var abutments: Array = []    # {p, d (into the bridge), w_top (half), w_foot (half), top, link}
var stats := {"piers": 0, "blocked": 0, "abutments": 0}

var _lines := {}             # Vector2i -> Array of [a, b, gap, link]: railways and paths that may be below
var _placed := {}            # Vector2i -> Array of [p, chain]
var _water_ok := {}          # link -> Array of [lo, hi]: water runs wide enough for piers


func _init(heights: BridgeHeights, roads: RoadNet, t: Terrain, asphalt_index: AsphaltIndex) -> void:
	bh = heights
	net = roads
	terrain = t
	asphalt = asphalt_index


func build(mesher: Object) -> void:
	var t0 := Time.get_ticks_msec()
	_index_lines()
	for c in bh.crossings:
		if int(c.lower) < 0 and not c.big and float(c.hi) - float(c.lo) >= WATER_SPAN:
			if not _water_ok.has(int(c.link)):
				_water_ok[int(c.link)] = []
			_water_ok[int(c.link)].append([float(c.lo), float(c.hi)])
	var keep_dm: Dictionary = terrain.mode_deck
	var keep_nm: int = terrain.mode_node
	terrain.mode_deck = {}
	terrain.mode_node = -1
	# joints first (every bridge needs them), then the piers in between
	for nid in 3:
		var ns: Array = bh.nodes[nid]
		for ni in ns.size():
			_joint(nid, ni, mesher)
	for li in bh.profiles:
		var l: Dictionary = bh.links[li]
		if not l.bridge:
			continue
		var dk := deck_of(li)
		if dk.is_empty():
			continue
		var span := span_of(li)
		var s0: float = l.u0
		var s1: float = l.u1
		var n := int(floor((s1 - s0) / span + 0.35))
		for k in range(1, n):
			_pier(li, dk, s0 + (s1 - s0) * k / n, span, mesher)
		for end in [[int(l.a), s0, 1.0], [int(l.b), s1, -1.0]]:
			if _land_end(int(l.net), int(end[0])):
				_abutment(li, dk, float(end[1]), float(end[2]), mesher)
	terrain.mode_deck = keep_dm
	terrain.mode_node = keep_nm
	stats["ms"] = Time.get_ticks_msec() - t0


func summary() -> String:
	return "Brückenbauwerke: %d Pfeiler, %d Widerlager, %d Pfeiler fanden keinen Platz (%d ms)" % [stats.piers,
		stats.abutments, stats.blocked, int(stats.get("ms", 0))]


## The deck of bridge link li (road edge, railway or path), or {}.
func deck_of(li: int) -> Dictionary:
	var l: Dictionary = bh.links[li]
	match int(l.net):
		BridgeHeights.ROAD:
			return terrain.decks.get(int(l.id), {})
		BridgeHeights.RAIL:
			return bh.rail_decks.get(int(l.id), {})
	return bh.path_decks.get(int(l.id), {})


## Pier spacing along bridge link li.
func span_of(li: int) -> float:
	if bh.big_chains.has(bh.chain[li]):
		return BIG_SPAN
	return SPAN[int(bh.links[li].net)]


## Half width of the structure of bridge link li (carriageway, sidewalks and parapet).
func half_of(li: int) -> float:
	var l: Dictionary = bh.links[li]
	match int(l.net):
		BridgeHeights.ROAD:
			var e: Dictionary = net.edges[int(l.id)]
			return float(e.width) * 0.5 + maxf(float(e.sw_l), float(e.sw_r)) + 0.35
		BridgeHeights.RAIL:
			return 2.3
	return maxf(float(l.hw), 1.0) + 0.3


## A bridge end that leads onto something that is no bridge (a ramp, the ground, a raised junction) or nowhere.
func _land_end(nid: int, ni: int) -> bool:
	var ls: Array = bh.nodes[nid][ni].links
	if ls.size() <= 1:
		return true
	for li in ls:
		if not bh.links[li].bridge:
			return true
	return false


# ------------------------------------------------------------------------------------------
# Piers
# ------------------------------------------------------------------------------------------

## A pier where bridge links meet (a joint of OSM ways or a junction on a bridge).
func _joint(nid: int, ni: int, mesher: Object) -> void:
	var ls: Array = bh.nodes[nid][ni].links
	if ls.size() < 2 or _land_end(nid, ni):
		return
	# the widest link carries the pier, across its direction, at its end
	var best := -1
	for li in ls:
		if bh.profiles.has(li) and (best < 0 or half_of(li) > half_of(best)):
			best = li
	if best < 0:
		return
	var l: Dictionary = bh.links[best]
	var dk := deck_of(best)
	if dk.is_empty():
		return
	var s: float = l.u0 if int(l.a) == ni else l.u1
	if nid == BridgeHeights.ROAD and float(l.u1) - float(l.u0) > 1.0:
		s = 0.0 if int(l.a) == ni else float(l.len)   # under the middle of the junction
	_pier(best, dk, s, span_of(best), mesher)


## Try to build a pier for bridge link li around arc length s (moving along the bridge if blocked).
func _pier(li: int, dk: Dictionary, s: float, span: float, mesher: Object) -> void:
	var l: Dictionary = bh.links[li]
	var ch: int = bh.chain[li]
	var half := half_of(li)
	var depth: float = dk.get("depth", BridgeHeights.DEPTH[int(l.net)])
	var total: float = l.len
	var shifts := [0.0]
	var step := 2.0
	while step <= span * SHIFT:
		shifts.append(step)
		shifts.append(-step)
		step += 2.0
	for sh in shifts:
		var sp := clampf(s + float(sh), 0.0, total)
		var smp := Geo.sample(l.pts, l.cum, sp)
		var p: Vector2 = smp[0]
		if _near_pier(p, ch, span * 0.5):
			return   # a joint or a neighbour already carries this part of the bridge
		var d: Vector2 = smp[1]
		var top := Terrain.deck_h(dk, sp) - depth
		var parts := _parts(half)
		var ok: Array = []
		for part in parts:
			var c: Vector2 = p + Geo.right_of(d) * float(part[0])
			if _free(c, d, float(part[1]), float(part[2]), li, sp):
				ok.append([c, part])
		# a wall stands or not as a whole; of several columns the free ones are enough if at least half stand
		if ok.is_empty() or ok.size() * 2 < parts.size():
			continue
		var built := false
		for o in ok:
			if _build_pier(o[0], d, float(o[1][1]), float(o[1][2]), top, li, mesher):
				built = true
		if built:
			_remember(p, ch)
			stats.piers += 1
		return
	stats.blocked += 1


## Footprints under a deck of half width half: [offset across, width across, thickness along].
static func _parts(half: float) -> Array:
	var w := half * 2.0
	if w <= SMALL:
		return [[0.0, 0.8, 0.8]]
	if w <= WIDE:
		return [[0.0, w * 0.55, WALL_T]]
	var n := clampi(int(ceil(w * 0.75 / 7.0)) + 1, 2, 5)
	var res: Array = []
	for i in n:
		res.append([lerpf(-w * 0.36, w * 0.36, float(i) / (n - 1)), COLUMN, COLUMN])   # lint-ok: n >= 2 (clampi)
	return res


## The footprint (centre c, w across, t along d) keeps off roads, railways, paths and narrow water below.
func _free(c: Vector2, d: Vector2, w: float, t: float, li: int, s: float) -> bool:
	var r := Geo.right_of(d)
	var pts: Array = []
	for i in 5:
		var fx := lerpf(-0.5, 0.5, i / 4.0)
		for j in 3:
			var fy := lerpf(-0.5, 0.5, j / 2.0)
			pts.append(c + r * (w * fx) + d * (t * fy))
	for q: Vector2 in pts:
		# roads: the pier and a margin around it off the asphalt
		if asphalt != null:
			for off in [Vector2.ZERO, r * ROAD_GAP, -r * ROAD_GAP, d * ROAD_GAP, -d * ROAD_GAP]:
				if asphalt.on_asphalt(q + off):
					return false
		for item in _lines.get(Vector2i(floori(q.x / GRID), floori(q.y / GRID)), []):
			if int(item[3]) == li:
				continue
			var cp := Geometry2D.get_closest_point_to_segment(q, item[0], item[1])
			if cp.distance_to(q) < float(item[2]) and not _raised(int(item[3]), cp):
				return false
		if not is_nan(bh._water_at(q)):
			var ok := false
			for run in _water_ok.get(li, []):
				if s >= float(run[0]) and s <= float(run[1]):
					ok = true
			if not ok:
				return false
	return true


## Railway or path link li2 runs above the ground at p (a bridge or ramp itself: no obstacle on the ground).
func _raised(li2: int, p: Vector2) -> bool:
	if not bh.profiles.has(li2):
		return false
	var dk := deck_of(li2)
	return not dk.is_empty() and terrain.deck_at(dk, p) - terrain.sample(p.x, p.y) > 1.5


## Mesh one pier: a box from below the ground up to the underside of the deck. False if the deck is low.
func _build_pier(c: Vector2, d: Vector2, w: float, t: float, top: float, li: int, mesher: Object) -> bool:
	var r := Geo.right_of(d)
	var corners := [c - r * (w * 0.5) - d * (t * 0.5), c + r * (w * 0.5) - d * (t * 0.5),
		c + r * (w * 0.5) + d * (t * 0.5), c - r * (w * 0.5) + d * (t * 0.5)]
	var lo := INF
	var hi := -INF
	for q: Vector2 in corners:
		var g := terrain.sample(q.x, q.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	if top - hi < MIN_HEIGHT:
		return false
	var bottom := lo - EMBED
	var l: MeshLayer = mesher.layer(mesher.chunk_of(c), "bridge")
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var out := Geo.right_of((b - a).normalized())
		if out.dot((a + b) * 0.5 - c) < 0.0:
			out = -out
		l.quad(_at(a, bottom), _at(b, bottom), _at(b, top), _at(a, top), Vector3(out.x, 0.0, out.y))
	piers.append({"p": c, "d": d, "w": w, "t": t, "top": top, "bottom": bottom, "link": li})
	return true


## Map point q at world height y as a vertex of a layer that lifts its vertices onto the ground.
func _at(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y - terrain.sample(q.x, q.y), q.y)


func _near_pier(p: Vector2, ch: int, dist: float) -> bool:
	var k := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	for gx in range(k.x - 2, k.x + 3):
		for gz in range(k.y - 2, k.y + 3):
			for item in _placed.get(Vector2i(gx, gz), []):
				if int(item[1]) == ch and (item[0] as Vector2).distance_to(p) < dist:
					return true
	return false


func _remember(p: Vector2, ch: int) -> void:
	var k := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	if not _placed.has(k):
		_placed[k] = []
	_placed[k].append([p, ch])


func _index_lines() -> void:
	for li in bh.links.size():
		var l: Dictionary = bh.links[li]
		if int(l.net) == BridgeHeights.ROAD:
			continue   # roads: the asphalt index
		var gap: float = RAIL_GAP if int(l.net) == BridgeHeights.RAIL else float(l.hw) + PATH_GAP
		var pts: PackedVector2Array = l.pts
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var rect := Rect2(a, Vector2.ZERO).expand(b).grow(gap)
			for gx in range(floori(rect.position.x / GRID), floori(rect.end.x / GRID) + 1):
				for gz in range(floori(rect.position.y / GRID), floori(rect.end.y / GRID) + 1):
					var k := Vector2i(gx, gz)
					if not _lines.has(k):
						_lines[k] = []
					_lines[k].append([a, b, gap, li])


# ------------------------------------------------------------------------------------------
# Abutments
# ------------------------------------------------------------------------------------------

## Where bridge link li ends on land at arc length s (dir +1: the bridge lies at larger s): a concrete front from
## the underside of the deck down into the ground, as wide as the embankment behind it at its foot.
func _abutment(li: int, dk: Dictionary, s: float, dir: float, mesher: Object) -> void:
	var l: Dictionary = bh.links[li]
	var smp := Geo.sample(l.pts, l.cum, s)
	var p: Vector2 = smp[0]
	var d: Vector2 = (smp[1] as Vector2) * dir
	var depth: float = dk.get("depth", BridgeHeights.DEPTH[int(l.net)])
	var top := Terrain.deck_h(dk, s) - depth
	var g := terrain.sample(p.x, p.y)
	var h := top - g
	if h < MIN_HEIGHT:
		return
	var half := half_of(li)
	var foot := half + h * 1.5
	var r := Geo.right_of(d)
	var front := p + d * 0.05
	var tl := front - r * half
	var tr := front + r * half
	var bl := front - r * foot
	var br := front + r * foot
	var lay: MeshLayer = mesher.layer(mesher.chunk_of(p), "bridge")
	var n := Vector3(d.x, 0.0, d.y)
	# front: a trapezoid, its sides follow the slopes of the embankment behind it
	lay.quad(_at(bl, terrain.sample(bl.x, bl.y) - EMBED), _at(br, terrain.sample(br.x, br.y) - EMBED), _at(tr, top),
		_at(tl, top), n)
	# the bearing shelf: a strip under the deck end
	var back := -d * 1.2
	lay.quad(_at(tl, top), _at(tr, top), _at(tr + back, top), _at(tl + back, top), Vector3.UP)
	abutments.append({"p": p, "d": d, "w_top": half, "w_foot": foot, "top": top, "link": li})
	stats.abutments += 1


## Removes trees (or lamps) that would stand in a pier. Returns how many.
func clear_xforms(by_chunk: Dictionary) -> int:
	if piers.is_empty():
		return 0
	var cells := {}
	for i in piers.size():
		var pc: Vector2 = piers[i].p
		var k := Vector2i(floori(pc.x / GRID), floori(pc.y / GRID))
		if not cells.has(k):
			cells[k] = []
		cells[k].append(i)
	var n := 0
	for ck in by_chunk:
		var keep: Array = []
		for x: Transform3D in by_chunk[ck]:
			var q := Vector2(x.origin.x, x.origin.z)
			if _in_pier(q, cells):
				n += 1
			else:
				keep.append(x)
		by_chunk[ck] = keep
	return n


func _in_pier(q: Vector2, cells: Dictionary) -> bool:
	var k := Vector2i(floori(q.x / GRID), floori(q.y / GRID))
	for gx in range(k.x - 1, k.x + 2):
		for gz in range(k.y - 1, k.y + 2):
			for i in cells.get(Vector2i(gx, gz), []):
				var pr: Dictionary = piers[i]
				var v: Vector2 = q - pr.p
				var d: Vector2 = pr.d
				if absf(v.dot(d)) <= float(pr.t) * 0.5 + 1.0 and absf(v.dot(Geo.right_of(d))) <= float(pr.w) * 0.5 + 1.0:
					return true
	return false
