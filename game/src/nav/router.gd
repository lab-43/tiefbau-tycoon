class_name Router
extends RefCounted
## Route planning on the lane graph (A* over edge-directions) and assembly of drivable pieces.
## Piece types: LANE (lane key, s in lane coordinates), BLEND (lane change from key to key2, lane coordinates),
## CONN (junction connector), POLY (free polyline, off the road graph).

const BLEND := 3
const CELL := 120.0

var net: RoadNet
var edir_out := {}      # edir -> Array[[conn_id, to_edir]]
var lane_grid := {}     # Vector2i -> Array[lane key]
var conn_vmax := {}     # conn id -> speed (route cost; driving uses the piece speed and its bend profile)
var _conn_prof := {}    # conn id -> Array[[s_from, s_to, v]] (lazy, see conn_profile)
var _lane_prof := {}    # lane key -> the same for the bends of a lane

const A_TURN := 2.8     # m/s², lateral acceleration in the bends of turn paths


func setup(n: RoadNet) -> void:
	net = n
	for ci in net.connectors.size():
		var c: Dictionary = net.connectors[ci]
		var from_edir: int = c.from >> 3
		var to_edir: int = c.to >> 3
		if not edir_out.has(from_edir):
			edir_out[from_edir] = []
		edir_out[from_edir].append([ci, to_edir])
		conn_vmax[ci] = _curve_speed(c)
	for key in net.lane_geo:
		var pts: PackedVector2Array = net.lane_geo[key][0]
		var seen := {}
		for i in range(0, pts.size(), 1):
			var cell := Vector2i(int(floor(pts[i].x / CELL)), int(floor(pts[i].y / CELL)))
			if not seen.has(cell):
				seen[cell] = true
				if not lane_grid.has(cell):
					lane_grid[cell] = []
				lane_grid[cell].append(key)


func _curve_speed(c: Dictionary) -> float:
	var pts: PackedVector2Array = c.pts
	if pts.size() < 3:
		return 14.0
	var d0 := (pts[1] - pts[0]).normalized()
	var d1 := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var theta := absf(d0.angle_to(d1))
	var e_from: Dictionary = net.edges[c.from >> 4]
	var e_to: Dictionary = net.edges[c.to >> 4]
	var limit := minf(e_from.speed, e_to.speed)
	if theta < 0.15:
		return limit
	var r: float = maxf(2.0, c.len / theta)
	return clampf(sqrt(2.3 * r), 2.5, limit)


func edge_speed(key: int) -> float:
	return net.edges[key >> 4].speed


func lane_len(key: int) -> float:
	var g: Array = net.lane_geo[key]
	var cum: PackedFloat32Array = g[1]
	return cum[cum.size() - 1]


## Nearest lane to a point. filter(key) -> bool optional.
func nearest_lane(p: Vector2, max_d := 80.0, filter: Callable = Callable()) -> Dictionary:
	var best := {}
	var best_d := max_d
	var c := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
	var r := int(ceil(max_d / CELL))
	var checked := {}
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for key in lane_grid.get(c + Vector2i(dx, dz), []):
				if checked.has(key):
					continue
				checked[key] = true
				if filter.is_valid() and not filter.call(key):
					continue
				var g: Array = net.lane_geo[key]
				var res := Geo.closest_on_polyline(g[0], g[1], p)
				if res[0] < best_d:
					best_d = res[0]
					best = {"key": key, "s": res[1], "dist": res[0], "point": res[2]}
	return best


func lane_piece(key: int, s0: float, s1: float) -> Dictionary:
	var g: Array = net.lane_geo[key]
	var pc := Agent.make_piece(Agent.LANE, key, g[0], g[1], s0, s1, edge_speed(key), "L%d" % key)
	if not _lane_prof.has(key):
		# wide window: OSM roads have small kinks at their nodes, only real bends count
		_lane_prof[key] = curve_profile(g[0], edge_speed(key), 6.0)
	pc["vprof"] = _lane_prof[key]
	return pc


func conn_piece(ci: int) -> Dictionary:
	var c: Dictionary = net.connectors[ci]
	var pc := Agent.make_piece(Agent.CONN, ci, c.pts, c.cum, 0.0, c.len, _conn_limit(c), "C%d" % ci, ci, c.node)
	pc["vprof"] = conn_profile(ci)
	return pc


func _conn_limit(c: Dictionary) -> float:
	return minf(net.edges[c.from >> 4].speed, net.edges[c.to >> 4].speed)


## Speed limits in the bends of turn path ci: [[s_from, s_to, v], …]. Cars brake for the bend and
## speed up after it. One speed for the whole path either raced through the tight arc of a
## straight–arc–straight path (its mean radius is much larger) or crawled along its straights (#5).
## Computed on first use: a city has some 10⁵ turn paths.
func conn_profile(ci: int) -> Array:
	if not _conn_prof.has(ci):
		var c: Dictionary = net.connectors[ci]
		_conn_prof[ci] = curve_profile(c.pts, _conn_limit(c))
	return _conn_prof[ci]


## Bends of a polyline slower than `limit`: v = √(A_TURN·r), r from the heading change over ±half_win
## metres (a lone kink counts as a bend of that length, not as a radius of zero).
static func curve_profile(pts: PackedVector2Array, limit: float, half_win := 1.5) -> Array:
	var p := Geo.densify(pts, 0.5)
	var cum := Geo.cumulative(p)
	var n := p.size()
	var res: Array = []
	if n < 3:
		return res
	var i := 0
	var k := 1
	for j in range(1, n - 1):
		# segment (i, i+1) ends half_win before vertex j, segment (k-1, k) starts half_win after it
		while i + 2 <= j and cum[j] - cum[i + 2] >= half_win:
			i += 1
		k = maxi(k, j + 1)
		while k < n - 1 and cum[k - 1] - cum[j] < half_win:
			k += 1
		var d0 := p[i + 1] - p[i]
		var d1 := p[k] - p[k - 1]
		if d0.length_squared() < 1e-6 or d1.length_squared() < 1e-6:
			continue
		var dh := absf(d0.angle_to(d1))
		if dh < 0.01:
			continue
		var span := maxf(0.5, (cum[k - 1] + cum[k] - cum[i] - cum[i + 1]) * 0.5)
		var v := clampf(sqrt(A_TURN * span / dh), 2.5, limit)
		if v > limit - 0.3:
			continue
		if not res.is_empty() and res[-1][1] >= cum[j] - 0.75:
			res[-1][1] = cum[j]
			res[-1][2] = minf(res[-1][2], v)
		else:
			res.append([cum[j], cum[j], v])
	return res


func blend_piece(key_a: int, key_b: int, s0: float, s1: float) -> Dictionary:
	var g: Array = net.lane_geo[key_a]
	var pc := Agent.make_piece(BLEND, key_a, g[0], g[1], s0, s1, edge_speed(key_a), "L%d" % key_a)
	pc["key2"] = key_b
	var g2: Array = net.lane_geo[key_b]
	pc["pts2"] = g2[0]
	pc["cum2"] = g2[1]
	pc["occ2"] = "L%d" % key_b
	pc["mid"] = (s0 + s1) * 0.5
	return pc


static func poly_piece(pts: PackedVector2Array, vmax: float, rev := false, tag := "") -> Dictionary:
	var cum := Geo.cumulative(pts)
	var pc := Agent.make_piece(Agent.POLY, -1, pts, cum, 0.0, cum[cum.size() - 1], vmax, "")
	pc.rev = rev
	pc.tag = tag
	return pc


## Position and direction on any piece at s.
static func piece_pose(pc: Dictionary, s: float) -> Array:
	if pc.t == BLEND:
		var a := Geo.sample(pc.pts, pc.cum, s)
		var cum2: PackedFloat32Array = pc.cum2
		var cum1: PackedFloat32Array = pc.cum
		var s2: float = s * cum2[cum2.size() - 1] / maxf(0.01, cum1[cum1.size() - 1])
		var b := Geo.sample(pc.pts2, pc.cum2, s2)
		var t := clampf((s - pc.s0) / maxf(0.01, pc.s1 - pc.s0), 0.0, 1.0)
		var w := t * t * (3.0 - 2.0 * t)
		var p: Vector2 = (a[0] as Vector2).lerp(b[0], w)
		var d: Vector2 = ((a[1] as Vector2).lerp(b[1], w) + ((b[0] as Vector2) - (a[0] as Vector2)) * (6.0 * t * (1.0 - t)) / maxf(1.0, pc.s1 - pc.s0)).normalized()
		return [p, d]
	var smp := Geo.sample(pc.pts, pc.cum, s)
	var dd: Vector2 = smp[1]
	if pc.rev:
		dd = -dd
	return [smp[0], dd]


static func piece_occ(pc: Dictionary, s: float) -> String:
	if pc.t == BLEND:
		return pc.occ if s < pc.mid else pc.occ2
	return pc.occ


# ------------------------------------------------------------------------------------------
# A*
# ------------------------------------------------------------------------------------------

## Returns an array of edirs [start, ..., dest] or [] if unreachable.
const LOOP_GOAL := -7

func find_edirs(start_key: int, start_s: float, dest_key: int, dest_s: float, avoid_edges: Dictionary = {}) -> Array:
	var start := start_key >> 3
	var dest := dest_key >> 3
	if start == dest and dest_s >= start_s - 0.5:
		return [start]
	var dest_pt: Vector2 = Geo.sample(net.lane_geo[dest_key][0], net.lane_geo[dest_key][1], dest_s)[0]
	var g := {start: 0.0}
	var came := {}
	var heap: Array = [[0.0, start]]
	var closed := {}
	var start_len := lane_len(start_key)
	var iterations := 0
	while not heap.is_empty() and iterations < 60000:
		iterations += 1
		var cur: Array = _heap_pop(heap)
		var u: int = cur[1]
		if closed.has(u):
			continue
		closed[u] = true
		if u == LOOP_GOAL:
			var path := _reconstruct(came, u)
			path[path.size() - 1] = dest
			return path
		if u == dest and u != start:
			return _reconstruct(came, u)
		var u_key := u * 8
		var ulen := start_len - start_s if u == start else lane_len(u_key)
		var speed: float = maxf(4.0, net.edges[u >> 1].speed)
		var gu: float = g[u]
		for pair in edir_out.get(u, []):
			var ci: int = pair[0]
			var v: int = pair[1]
			if v == dest and dest == start:
				# destination lies behind the start on the same road: loop around the block
				var c0: Dictionary = net.connectors[ci]
				var cost0: float = gu + ulen / speed + c0.len / maxf(3.0, conn_vmax.get(ci, 8.0)) + (2.0 if c0.turn != "S" else 0.0)
				if cost0 < g.get(LOOP_GOAL, INF):
					g[LOOP_GOAL] = cost0
					came[LOOP_GOAL] = [u, ci]
					_heap_push(heap, [cost0, LOOP_GOAL])
				continue
			if closed.has(v) or avoid_edges.has(v >> 1):
				continue
			var c: Dictionary = net.connectors[ci]
			var cost: float = gu + ulen / speed + c.len / maxf(3.0, conn_vmax.get(ci, 8.0)) + (2.0 if c.turn != "S" else 0.0)
			if cost < g.get(v, INF):
				g[v] = cost
				came[v] = [u, ci]
				var vkey := v * 8
				var vp: Vector2 = net.lane_geo[vkey][0][0] if net.lane_geo.has(vkey) else Vector2.ZERO
				_heap_push(heap, [cost + vp.distance_to(dest_pt) / 16.0, v])
	return []


func _reconstruct(came: Dictionary, u: int) -> Array:
	var path := [u]
	while came.has(u):
		u = came[u][0]
		path.push_front(u)
	return path


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and h[l][0] < h[m][0]:
				m = l
			if r < n and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top


## Build pieces from start lane position to destination lane position. Returns [] if no route.
func plan(start_key: int, start_s: float, dest_key: int, dest_s: float, avoid_edges: Dictionary = {}) -> Array:
	var edirs := find_edirs(start_key, start_s, dest_key, dest_s, avoid_edges)
	if edirs.is_empty():
		return []
	var pieces: Array = []
	var cur_key := start_key
	var cur_s := start_s
	for i in edirs.size():
		var ed: int = edirs[i]
		var is_last := i == edirs.size() - 1
		if is_last:
			var target_key := dest_key
			if (target_key >> 3) != ed:
				target_key = cur_key
			_append_lane_run(pieces, cur_key, target_key, cur_s, dest_s)
			break
		var next_ed: int = edirs[i + 1]
		# pick connector: prefer from current lane
		var best_ci := -1
		var best_score := INF
		for pair in edir_out.get(ed, []):
			if pair[1] != next_ed:
				continue
			var c: Dictionary = net.connectors[pair[0]]
			var from_lane: int = c.from & 7
			var score: float = absf(from_lane - (cur_key & 7)) * 10.0
			# on the last transition prefer arriving on the destination lane
			if i + 1 == edirs.size() - 1:
				score += absf((c.to & 7) - (dest_key & 7)) * 3.0
			if score < best_score:
				best_score = score
				best_ci = pair[0]
		if best_ci < 0:
			return []
		var cc: Dictionary = net.connectors[best_ci]
		var exit_key: int = cc.from
		var end_s := lane_len(exit_key)
		_append_lane_run(pieces, cur_key, exit_key, cur_s, end_s)
		pieces.append(conn_piece(best_ci))
		cur_key = cc.to
		cur_s = 0.0
	return pieces


## Lane run on one edge-direction from key_a at s0 to key_b at s1, with a lane change blend if needed.
func _append_lane_run(pieces: Array, key_a: int, key_b: int, s0: float, s1: float) -> void:
	if s1 - s0 < 0.05:
		if key_a == key_b or s1 - s0 < 0.0:
			return
	if key_a == key_b:
		pieces.append(lane_piece(key_a, s0, s1))
		return
	var length := s1 - s0
	if length < 12.0:
		pieces.append(blend_piece(key_a, key_b, s0, s1))
		return
	var blend_len := clampf(length * 0.5, 12.0, 40.0)
	var b0 := s0 + (length - blend_len) * 0.35
	var b1 := b0 + blend_len
	if b0 - s0 > 0.1:
		pieces.append(lane_piece(key_a, s0, b0))
	pieces.append(blend_piece(key_a, key_b, b0, b1))
	if s1 - b1 > 0.1:
		var lb_len := lane_len(key_b)
		var la_len := lane_len(key_a)
		var scale := lb_len / maxf(0.01, la_len)
		pieces.append(lane_piece(key_b, b1 * scale, s1 * scale))
