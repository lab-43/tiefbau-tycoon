class_name BucketLoad
extends MeshInstance3D
## Bulk load (soil, gravel ...) shown in an excavator bucket (issue #11). Child of the bucket node, owned by
## ExcavatorRig. setup() finds the cavity and the opening of the bucket from the bucket's own meshes:
## cross-sections across the hinge axis (bucket-local x), seen in the hinge plane as (u = -z, v = y).
## No fixed coordinates, so it works for every bucket model (lesson anbauteile-auf-oberflaeche).
## set_volume() builds a body that fills the cavity up to the lips and heaps out of the opening;
## a part-filled bucket shows a lower surface inside the cavity.

const PLANES := 5              # cross-sections across the bucket width (within ±35 % of it)
const RAYS := 120              # rays around the inner point that look for the opening
const SAMPLES := 24            # cavity depth samples along the opening
const MIN_CLEAR := 0.04        # the inner point keeps this distance to every wall (m)
const LIP_INSET := 0.02        # the load ends this far inside the lips (m)
const HEAP := 0.25             # heap height of a full bucket, share of the smaller opening side
const GRID_S := 16             # surface grid along the opening
const GRID_W := 10             # surface grid across the bucket

static var _cache := {}        # mesh instance id -> analysis (all excavators of a model share their meshes)
static var _g_mean := -1.0

var ok := false
var capacity := 0.6            # m³ that show as a full, heaped bucket (asset JSON bucket_capacity_m3)
var a := Vector2.ZERO          # opening: first lip (hinge plane, bucket space)
var e := Vector2.ZERO          # unit direction from lip a to the other lip
var n := Vector2.ZERO          # unit normal of the opening, pointing out of the cavity
var span := 0.0                # lip to lip (m)
var x_lo := 0.0                # inner faces of the side walls (bucket x)
var x_hi := 0.0
var depth := PackedFloat32Array()   # cavity depth below the opening at SAMPLES cell centres
var struck := 0.0              # cavity volume up to the opening (m³)
var heap_full := 0.0           # heap volume of a full bucket (m³)
var _shown := -1


## Analyses the bucket. Call before or after adding this node as a child of the bucket.
func setup(bucket: Node3D) -> void:
	position = Vector3.ZERO
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	var key := _cache_key(bucket)
	var info: Dictionary = _cache.get(key, {})
	if info.is_empty():
		info = _analyze(_triangles(bucket, self))
		if key != 0:
			_cache[key] = info
	ok = bool(info.get("ok", false))
	if not ok:
		push_warning("BucketLoad: Öffnung der Schaufel nicht gefunden (%s)" % info.get("why", "?"))
		return
	a = info.a
	e = info.e
	n = info.n
	span = info.span
	x_lo = info.x_lo
	x_hi = info.x_hi
	depth = info.depth
	var w := x_hi - x_lo
	var area := 0.0
	for d in depth:
		area += d * span / SAMPLES
	struck = area * w
	heap_full = _mound_mean() * span * w * HEAP * minf(span, w)


## Shows m3 of loose material (0 hides the load). Rebuilds only when the shown amount changes by 1 %.
func set_volume(m3: float) -> void:
	var f := clampf(m3 / maxf(0.05, capacity), 0.0, 1.2)
	var q := int(roundf(f * 100.0))
	if q == _shown:
		return
	_shown = q
	visible = ok and q > 0
	if visible:
		mesh = _build(q / 100.0 * (struck + heap_full))


## Share of a full bucket currently shown (0..1.2).
func shown_fill() -> float:
	return maxf(0.0, _shown / 100.0)


## World-space y of the opening normal: 1 = opening faces straight up, -1 = faces down (material falls out).
func opening_up() -> float:
	if not ok:
		return 1.0
	return (global_transform.basis * _v3(0.0, n)).normalized().y


## Cavity point in bucket space below the middle of the opening (for tests).
func cavity_point() -> Vector3:
	var mid := a + e * (span * 0.5) - n * (_depth_at(span * 0.5) * 0.5)
	return _v3((x_lo + x_hi) * 0.5, mid)


# ------------------------------------------------------------------------------------------
# Load body
# ------------------------------------------------------------------------------------------

func _build(vol: float) -> ArrayMesh:
	var w := x_hi - x_lo
	var level := 0.0           # surface below the opening (m, into the cavity)
	var bump := 0.0            # height of the domed surface above level
	var s0 := 0.0
	var s1 := span
	if vol >= struck:
		bump = minf((vol - struck) / maxf(1e-4, _mound_mean() * span * w), 0.45 * minf(span, w))
	else:
		# level so that the cavity below it holds vol
		var lo := 0.0
		var hi := _max_depth()
		for it in 24:
			var mid := (lo + hi) * 0.5
			if _vol_below(mid) * w > vol:
				lo = mid
			else:
				hi = mid
		level = (lo + hi) * 0.5
		bump = minf(0.06 * minf(span, w) * vol / maxf(1e-4, struck), level)
		var sr := _span_below(level)
		s0 = sr.x
		s1 = sr.y
	var am := ArrayMesh.new()
	if s1 - s0 < 0.01:
		return am
	# surface: dome over the opening (or over the part of the cavity below level)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var out := _v3(0.0, n)
	var grid: Array = []
	for j in GRID_S + 1:
		var row: Array = []
		var s := lerpf(s0, s1, float(j) / GRID_S)
		var gs := float(j) / GRID_S - 0.5
		for i in GRID_W + 1:
			var gw := float(i) / GRID_W - 0.5
			var h := -level + bump * _mound(gw, gs)
			row.append(_v3(lerpf(x_lo, x_hi, float(i) / GRID_W), a + e * s + n * h))
		grid.append(row)
	for j in GRID_S:
		for i in GRID_W:
			var p00: Vector3 = grid[j][i]
			var p10: Vector3 = grid[j][i + 1]
			var p11: Vector3 = grid[j + 1][i + 1]
			var p01: Vector3 = grid[j + 1][i]
			_tri(st, p00, p10, p11, out)
			_tri(st, p00, p11, p01, out)
	st.index()
	st.generate_normals()
	st.commit(am)
	# side walls down to the shell: show the material where the side plates are cut back
	var sw := SurfaceTool.new()
	sw.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [0, 1]:
		var x: float = x_hi if side == 1 else x_lo
		var wout := Vector3(1.0 if side == 1 else -1.0, 0.0, 0.0)
		for j in GRID_S:
			var sa := lerpf(s0, s1, float(j) / GRID_S)
			var sb := lerpf(s0, s1, float(j + 1) / GRID_S)
			var ta := _v3(x, a + e * sa - n * level)
			var tb := _v3(x, a + e * sb - n * level)
			var ba := _v3(x, a + e * sa - n * maxf(level, _depth_at(sa)))
			var bb := _v3(x, a + e * sb - n * maxf(level, _depth_at(sb)))
			_tri(sw, ta, tb, bb, wout)
			_tri(sw, ta, bb, ba, wout)
	sw.generate_normals()
	sw.commit(am)
	return am


## Adds a triangle that faces out (Godot: front faces are clockwise seen from the viewer).
static func _tri(st: SurfaceTool, p: Vector3, q: Vector3, r: Vector3, out: Vector3) -> void:
	if (q - p).cross(r - p).dot(out) > 0.0:
		var t := q
		q = r
		r = t
	st.add_vertex(p)
	st.add_vertex(q)
	st.add_vertex(r)


## Same shape as RigUtil.mound_mesh(): 1 in the middle, 0 at the edges of the unit square.
static func _mound(x: float, z: float) -> float:
	var fx := 1.0 - pow(absf(x) * 2.0, 2.2)
	var fz := 1.0 - pow(absf(z) * 2.0, 2.2)
	return pow(maxf(0.0, fx * fz), 0.7)


static func _mound_mean() -> float:
	if _g_mean < 0.0:
		var sum := 0.0
		for j in 40:
			for i in 40:
				sum += _mound((i + 0.5) / 40.0 - 0.5, (j + 0.5) / 40.0 - 0.5)
		_g_mean = sum / 1600.0
	return _g_mean


## Cavity depth at distance s from lip a (0 at both lips, linear between the samples).
func _depth_at(s: float) -> float:
	var ds := span / SAMPLES
	var x := s / ds - 0.5
	if x <= 0.0:
		return depth[0] * clampf(s / (ds * 0.5), 0.0, 1.0)
	if x >= SAMPLES - 1:
		return depth[SAMPLES - 1] * clampf((span - s) / (ds * 0.5), 0.0, 1.0)
	var i := int(x)
	return lerpf(depth[i], depth[i + 1], x - i)


func _max_depth() -> float:
	var m := 0.0
	for d in depth:
		m = maxf(m, d)
	return m


## Hinge-plane area of the cavity deeper than level.
func _vol_below(level: float) -> float:
	var steps := SAMPLES * 4
	var ds := span / steps
	var area := 0.0
	for k in steps:
		area += maxf(0.0, _depth_at((k + 0.5) * ds) - level) * ds
	return area


## First and last s where the cavity is deeper than level.
func _span_below(level: float) -> Vector2:
	var steps := SAMPLES * 4
	var ds := span / steps
	var first := -1.0
	var last := -1.0
	for k in steps + 1:
		var s := k * ds
		if _depth_at(s) > level:
			if first < 0.0:
				first = s
			last = s
	if first < 0.0:
		return Vector2.ZERO
	return Vector2(maxf(0.0, first - ds * 0.5), minf(span, last + ds * 0.5))


static func _v3(x: float, p: Vector2) -> Vector3:
	return Vector3(x, p.y, -p.x)


# ------------------------------------------------------------------------------------------
# Analysis
# ------------------------------------------------------------------------------------------

static func _cache_key(bucket: Node3D) -> int:
	for node in bucket.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh and not (mi is BucketLoad):
			return mi.mesh.get_instance_id()
	return 0


## All triangles below bucket in bucket space (3 vertices each).
static func _triangles(bucket: Node3D, skip: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	var inv := bucket.global_transform.affine_inverse()
	for node in bucket.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == skip or mi is BucketLoad or mi.mesh == null:
			continue
		var xf := inv * mi.global_transform
		for p in mi.mesh.get_faces():
			out.append(xf * p)
	return out


static func _analyze(tris: PackedVector3Array) -> Dictionary:
	if tris.size() < 12:
		return {"ok": false, "why": "kein Modell"}
	var xmin := INF
	var xmax := -INF
	for p in tris:
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
	var xc := (xmin + xmax) * 0.5
	var planes: Array = []
	var bb := Rect2()
	var first := true
	for k in PLANES:
		var x := xc + (float(k) / (PLANES - 1) - 0.5) * 0.7 * (xmax - xmin)
		var sg := _section(tris, x)
		planes.append(sg)
		for p in sg:
			if first:
				bb = Rect2(p, Vector2.ZERO)
				first = false
			else:
				bb = bb.expand(p)
	var center: PackedVector2Array = planes[PLANES / 2]
	if center.size() < 6:
		return {"ok": false, "why": "kein Schnitt"}
	var diag := bb.size.length()
	# 1. a point inside the cavity: most rays hit a wall (not too close), some leave through the opening
	var p_in := Vector2.INF
	var best := -1.0
	for gy in range(1, 8):
		for gx in range(1, 8):
			var o := bb.position + bb.size * Vector2(gx / 8.0, gy / 8.0)
			var hits := 0
			var sum := 0.0
			var bad := false
			for k in 16:
				var t := _ray(center, o, Vector2.from_angle(TAU * k / 16.0))
				if t < MIN_CLEAR:
					bad = true
					break
				if t < diag:
					hits += 1
					sum += t
			if bad or hits == 16 or hits < 6:
				continue
			var score := hits + sum / (diag * 16.0)
			if score > best:
				best = score
				p_in = o
	if best < 0.0:
		return {"ok": false, "why": "kein Hohlraum"}
	# 2. the opening: the largest run of rays that leave the bucket (median over the planes, so teeth and
	#    mounting ears that only some sections cut do not count as walls)
	var esc: Array[bool] = []
	for k in RAYS:
		esc.append(_median_ray(planes, p_in, Vector2.from_angle(TAU * k / RAYS)) > diag)
	var run_start := -1
	var run_len := 0
	for k in RAYS:
		if not esc[k] or esc[(k - 1 + RAYS) % RAYS]:
			continue
		var m := 0
		while m < RAYS and esc[(k + m) % RAYS]:
			m += 1
		if m > run_len:
			run_len = m
			run_start = k
	if run_start < 0 or run_len > RAYS * 0.6:
		return {"ok": false, "why": "keine Öffnung"}
	# 3. the lips: last directions on both sides of the run that still hit the bucket
	var step := TAU / RAYS
	var ang1 := _edge(planes, p_in, (run_start - 1) * step, run_start * step, diag)
	var ang2 := _edge(planes, p_in, (run_start + run_len) * step, (run_start + run_len - 1) * step, diag)
	var lip1 := p_in + Vector2.from_angle(ang1) * _median_ray(planes, p_in, Vector2.from_angle(ang1))
	var lip2 := p_in + Vector2.from_angle(ang2) * _median_ray(planes, p_in, Vector2.from_angle(ang2))
	var sp := lip1.distance_to(lip2)
	if sp < 0.1 * diag:
		return {"ok": false, "why": "Öffnung zu klein"}
	var dir := (lip2 - lip1) / sp
	# the grazing rays end on the very edge of the lips (and on the teeth roots): keep the load just inside
	lip1 += dir * LIP_INSET
	lip2 -= dir * LIP_INSET
	sp -= 2.0 * LIP_INSET
	var nrm := Vector2(-dir.y, dir.x)
	if nrm.dot(p_in - lip1) > 0.0:
		nrm = -nrm
	# 4. cavity depth below the opening (nearest wall over all planes, so nothing pokes through)
	var dep := PackedFloat32Array()
	for i in SAMPLES:
		var o := lip1 + dir * ((i + 0.5) / SAMPLES * sp) + nrm * 0.002
		var t := INF
		for sg in planes:
			t = minf(t, _ray(sg, o, -nrm))
		dep.append(clampf(t - 0.002, 0.0, diag) if t < INF else 0.0)
	# 5. inner faces of the side walls, seen from the middle of the cavity
	var im := 0
	for i in SAMPLES:
		if dep[i] > dep[im]:
			im = i
	var q2 := lip1 + dir * ((im + 0.5) / SAMPLES * sp) - nrm * dep[im] * 0.5
	var q := Vector3(xc, q2.y, -q2.x)
	var tp := _ray3(tris, q, Vector3.RIGHT)
	var tm := _ray3(tris, q, Vector3.LEFT)
	var xh: float = (xc + tp - 0.01) if tp < INF else xmax - 0.02
	var xl: float = (xc - tm + 0.01) if tm < INF else xmin + 0.02
	if xh - xl < 0.1:
		return {"ok": false, "why": "Schaufel zu schmal"}
	return {"ok": true, "a": lip1, "e": dir, "n": nrm, "span": sp, "x_lo": xl, "x_hi": xh, "depth": dep,
		"inner": p_in}


## Cross-section of the triangles with the plane x = xc as segments (pairs of points in (u, v)).
static func _section(tris: PackedVector3Array, xc: float) -> PackedVector2Array:
	var segs := PackedVector2Array()
	for i in range(0, tris.size(), 3):
		var cnt := 0
		var s0 := Vector2.ZERO
		var s1 := Vector2.ZERO
		for k in 3:
			var p: Vector3 = tris[i + k]
			var r: Vector3 = tris[i + (k + 1) % 3]
			var dp := p.x - xc
			var dr := r.x - xc
			if (dp < 0.0) != (dr < 0.0):
				var c := p.lerp(r, dp / (dp - dr))
				if cnt == 0:
					s0 = Vector2(-c.z, c.y)
				else:
					s1 = Vector2(-c.z, c.y)
				cnt += 1
		if cnt == 2:
			segs.append(s0)
			segs.append(s1)
	return segs


## Distance along d (unit) from o to the first segment, INF if none.
static func _ray(segs: PackedVector2Array, o: Vector2, d: Vector2) -> float:
	var best := INF
	for i in range(0, segs.size(), 2):
		var p: Vector2 = segs[i]
		var r: Vector2 = segs[i + 1] - p
		var den := d.cross(r)
		if absf(den) < 1e-12:
			continue
		var w := p - o
		var t := w.cross(r) / den
		if t <= 1e-4 or t >= best:
			continue
		var u := w.cross(d) / den
		if u >= 0.0 and u <= 1.0:
			best = t
	return best


static func _median_ray(planes: Array, o: Vector2, d: Vector2) -> float:
	var ts: Array[float] = []
	for sg in planes:
		ts.append(_ray(sg, o, d))
	ts.sort()
	return ts[ts.size() / 2]


## Bisects between a direction that hits the bucket (hit) and one that leaves it (miss); returns the last hit angle.
static func _edge(planes: Array, o: Vector2, hit: float, miss: float, diag: float) -> float:
	for it in 10:
		var mid := (hit + miss) * 0.5
		if _median_ray(planes, o, Vector2.from_angle(mid)) > diag:
			miss = mid
		else:
			hit = mid
	return hit


## Distance along d (unit) from o to the first triangle, INF if none (Möller-Trumbore).
static func _ray3(tris: PackedVector3Array, o: Vector3, d: Vector3) -> float:
	var best := INF
	for i in range(0, tris.size(), 3):
		var v0: Vector3 = tris[i]
		var e1: Vector3 = tris[i + 1] - v0
		var e2: Vector3 = tris[i + 2] - v0
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := o - v0
		var u := tv.dot(pv) * inv
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var v := d.dot(qv) * inv
		if v < 0.0 or u + v > 1.0:
			continue
		var t := e2.dot(qv) * inv
		if t > 1e-4 and t < best:
			best = t
	return best
