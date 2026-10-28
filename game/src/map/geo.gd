class_name Geo
extends RefCounted
## Local tangent-plane projection around the map center.
## 2D map coordinates are Vector2(x, z): x = east (m), z = south (m) (Godot: -Z is north).
## right(d) of a travel direction d in this plane is Vector2(-d.y, d.x); left(d) = Vector2(d.y, -d.x).

const R := 6378137.0
static var lat0: float = 53.55
static var lon0: float = 9.99
static var _cos0: float = cos(deg_to_rad(53.55))


static func setup(center_lat: float, center_lon: float) -> void:
	lat0 = center_lat
	lon0 = center_lon
	_cos0 = cos(deg_to_rad(center_lat))


static func to_local(lat: float, lon: float) -> Vector2:
	return Vector2(R * deg_to_rad(lon - lon0) * _cos0, -R * deg_to_rad(lat - lat0))


static func to_latlon(p: Vector2) -> Vector2:
	# returns Vector2(lat, lon)
	return Vector2(lat0 - rad_to_deg(p.y / R), lon0 + rad_to_deg(p.x / (R * _cos0)))


static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


static func left_of(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x)


static func v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Polyline helpers -------------------------------------------------------------------------

static func polyline_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


static func cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(pts.size())
	var l := 0.0
	if pts.size() > 0:
		c[0] = 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
		c[i] = l
	return c


## Point and tangent at arc length s along a polyline (with precomputed cumulative lengths).
static func sample(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Array:
	var n := pts.size()
	if n == 0:
		return [Vector2.ZERO, Vector2.RIGHT]
	if n == 1:
		return [pts[0], Vector2.RIGHT]
	if s <= 0.0:
		return [pts[0], (pts[1] - pts[0]).normalized()]
	var total := cum[n - 1]
	if s >= total:
		return [pts[n - 1], (pts[n - 1] - pts[n - 2]).normalized()]
	# binary search
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	var t := 0.0 if seg <= 0.0001 else (s - cum[lo]) / seg
	var d := pts[hi] - pts[lo]
	var dl := d.length()
	return [pts[lo].lerp(pts[hi], t), d / dl if dl > 0.0001 else Vector2.RIGHT]


## Sub-polyline between arc lengths s0..s1 (s0 < s1), resampled so that segments are <= step.
static func sub_polyline(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, step: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 2 or s1 <= s0:
		return out
	out.append(sample(pts, cum, s0)[0])
	for i in range(1, n - 1):
		if cum[i] > s0 + 0.01 and cum[i] < s1 - 0.01:
			out.append(pts[i])
	out.append(sample(pts, cum, s1)[0])
	if step > 0.0:
		return densify(out, step)
	return out


static func densify(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() == 0:
		return out
	out.append(pts[0])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		var k := int(ceil(d / step))
		for j in range(1, k + 1):
			out.append(a.lerp(b, float(j) / float(k)))
	return out


## Chaikin corner cutting, keeps endpoints. Smooths the angular look of OSM ways.
static func chaikin(pts: PackedVector2Array, iterations: int = 2, min_seg: float = 4.0) -> PackedVector2Array:
	var cur := pts
	for _it in iterations:
		if cur.size() < 3:
			return cur
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		for i in range(cur.size() - 1):
			var a := cur[i]
			var b := cur[i + 1]
			if a.distance_to(b) < min_seg:
				if i > 0:
					nxt.append(a)
				continue
			var q := a.lerp(b, 0.25)
			var r := a.lerp(b, 0.75)
			if i > 0:
				nxt.append(q)
			if i < cur.size() - 2:
				nxt.append(r)
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


## Offset a polyline laterally (positive = right of travel direction) with miter joins.
static func offset_polyline(pts: PackedVector2Array, off: float, miter_limit: float = 3.0) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	out.resize(n)
	if n < 2:
		if n == 1:
			out[0] = pts[0]
		return out
	for i in n:
		var d_in := Vector2.ZERO
		var d_out := Vector2.ZERO
		if i > 0:
			d_in = (pts[i] - pts[i - 1]).normalized()
		if i < n - 1:
			d_out = (pts[i + 1] - pts[i]).normalized()
		if i == 0:
			d_in = d_out
		if i == n - 1:
			d_out = d_in
		var r_in := right_of(d_in)
		var r_out := right_of(d_out)
		var m := r_in + r_out
		var ml := m.length()
		if ml < 0.0001:
			out[i] = pts[i] + r_out * off
			continue
		m /= ml
		var cos_half := m.dot(r_out)
		var scale := 1.0 / maxf(cos_half, 1.0 / miter_limit)
		out[i] = pts[i] + m * off * scale
	return out


static func point_in_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func polygon_centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(1.0, float(poly.size()))


## Closest point on polyline: returns [distance, arc_length_s, point, segment_index]
static func closest_on_polyline(pts: PackedVector2Array, cum: PackedFloat32Array, p: Vector2) -> Array:
	var best_d := INF
	var best_s := 0.0
	var best_p := Vector2.ZERO
	var best_i := 0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_p = q
			best_i = i
			best_s = cum[i] + a.distance_to(q)
	return [sqrt(best_d), best_s, best_p, best_i]
