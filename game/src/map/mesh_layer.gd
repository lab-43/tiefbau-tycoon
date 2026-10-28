class_name MeshLayer
extends RefCounted
## Accumulates triangles for one material and commits them into an ArrayMesh surface.
## Godot front faces are clockwise as seen by the viewer; front normal = (c - a) x (b - a).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var use_colors := false
var use_uvs := true


func is_empty() -> bool:
	return indices.is_empty()


func _v(p: Vector3, n: Vector3, uv: Vector2, c: Color) -> int:
	var i := verts.size()
	verts.append(p)
	normals.append(n)
	if use_uvs:
		uvs.append(uv)
	if use_colors:
		colors.append(c)
	return i


## Triangle facing direction n (vertex order fixed automatically).
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, col := Color.WHITE) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	var ia := _v(a, n, ua, col)
	var ib := _v(b, n, ub, col)
	var ic := _v(c, n, uc, col)
	indices.append(ia)
	indices.append(ib)
	indices.append(ic)


## Quad a-b-c-d (in order around the quad) facing n.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO, col := Color.WHITE) -> void:
	var flip := (c - a).cross(b - a).dot(n) < 0.0
	var ia := _v(a, n, ua, col)
	var ib := _v(b, n, ub, col)
	var ic := _v(c, n, uc, col)
	var id := _v(d, n, ud, col)
	if flip:
		indices.append_array(PackedInt32Array([ia, ic, ib, ia, id, ic]))
	else:
		indices.append_array(PackedInt32Array([ia, ib, ic, ia, ic, id]))


## Flat horizontal polygon at height y facing up (uses world xz as uv * uv_scale).
func polygon_up(poly: PackedVector2Array, y: float, uv_scale: float = 1.0, col := Color.WHITE, holes: Array = []) -> bool:
	var idx := triangulate(poly, holes)
	var pts := poly
	if not holes.is_empty() and idx.size() > 0 and idx[0] < 0:
		pass
	if idx.is_empty():
		return false
	var src: PackedVector2Array = _last_points
	var base := verts.size()
	for p in src:
		_v(Vector3(p.x, y, p.y), Vector3.UP, p * uv_scale, col)
	for t in range(0, idx.size(), 3):
		var a := src[idx[t]]
		var b := src[idx[t + 1]]
		var c := src[idx[t + 2]]
		# up-facing needs positive signed area in (x,z) math orientation
		var cr := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if cr >= 0.0:
			indices.append_array(PackedInt32Array([base + idx[t], base + idx[t + 1], base + idx[t + 2]]))
		else:
			indices.append_array(PackedInt32Array([base + idx[t], base + idx[t + 2], base + idx[t + 1]]))
	return true


var _last_points := PackedVector2Array()


## Triangulate a polygon with optional holes (holes are bridged into the outer ring).
func triangulate(outer: PackedVector2Array, holes: Array = []) -> PackedInt32Array:
	var ring := outer
	if not holes.is_empty():
		ring = bridge_holes(outer, holes)
	_last_points = ring
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.is_empty() and not holes.is_empty():
		_last_points = outer
		idx = Geometry2D.triangulate_polygon(outer)
	if idx.is_empty():
		# last resort: delaunay filtered by inside test
		var d := Geometry2D.triangulate_delaunay(_last_points)
		var keep := PackedInt32Array()
		for t in range(0, d.size(), 3):
			var c := (_last_points[d[t]] + _last_points[d[t + 1]] + _last_points[d[t + 2]]) / 3.0
			if Geometry2D.is_point_in_polygon(c, outer):
				keep.append_array(PackedInt32Array([d[t], d[t + 1], d[t + 2]]))
		idx = keep
	return idx


## Connect each hole to the outer ring with a zero-width bridge (classic ear-clipping prep).
static func bridge_holes(outer: PackedVector2Array, holes: Array) -> PackedVector2Array:
	var ring := outer.duplicate()
	if Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	var hs: Array = []
	for h in holes:
		var hh: PackedVector2Array = h.duplicate()
		if not Geometry2D.is_polygon_clockwise(hh):
			hh.reverse()
		hs.append(hh)
	# process holes by max x descending
	hs.sort_custom(func(a, b): return _max_x(a) > _max_x(b))
	for h in hs:
		var hi := 0
		for i in h.size():
			if h[i].x > h[hi].x:
				hi = i
		var hp: Vector2 = h[hi]
		# nearest ring vertex visible-ish (closest by distance with x >= hp.x preferred)
		var best := -1
		var best_d := INF
		for i in ring.size():
			var d := ring[i].distance_squared_to(hp)
			if ring[i].x >= hp.x - 0.001:
				d *= 0.5
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			continue
		var merged := PackedVector2Array()
		for i in best + 1:
			merged.append(ring[i])
		for k in h.size() + 1:
			merged.append(h[(hi + k) % h.size()])
		for i in range(best, ring.size()):
			merged.append(ring[i])
		ring = merged
	return ring


static func _max_x(p: PackedVector2Array) -> float:
	var m := -INF
	for q in p:
		m = maxf(m, q.x)
	return m


func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if indices.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	if use_uvs:
		arr[Mesh.ARRAY_TEX_UV] = uvs
	if use_colors:
		arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh
