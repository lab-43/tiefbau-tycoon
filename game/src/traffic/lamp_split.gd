class_name LampSplit
extends RefCounted
## Recovers lamp glass that an extracted model does not carry as separate materials, so that its own
## glass can light up (TrafficModels._glass) instead of boxes stuck onto it (#2). Works on a model
## instance once at load time and returns replacement meshes {NodePath from the model root: ArrayMesh}
## in which the lamp triangles sit in extra surfaces with materials "<material>__light_head", ... .
## - donor(): the model shares its lamp geometry with another model that has split glass
##   (police car = hatchback body): triangles within 2 mm of the donor's glass of a function get it.
## - markers(): all lamps are one material (Scania): triangles go to the nearest light marker.

const SUFFIX := {"head": "__light_head", "tail": "__light_tail", "brake": "__light_brake", "reverse": "__light_reverse",
	"ind_l": "__indicator_l", "ind_r": "__indicator_r"}
const MARKER_FN := {"light_head_": "head", "light_tail_": "tail", "light_brake_": "brake", "light_reverse_": "reverse",
	"indicator_fl": "ind_l", "indicator_rl": "ind_l", "indicator_sl": "ind_l", "indicator_fr": "ind_r", "indicator_rr": "ind_r",
	"indicator_sr": "ind_r"}
const DONOR_TOL := 0.002       # m: a triangle centre this close to the donor's lamp glass is lamp glass
const MARKER_PART := 0.15      # m: a connected part whose centre is farther from every marker is no lamp (fog, roof)
const MARKER_TRI := 0.35       # m: per triangle, only markers this close count


## Lamp glass taken over from a donor model with the same lamp geometry.
static func donor(root: Node3D, donor_root: Node3D) -> Dictionary:
	var glass := {}   # function -> PackedVector3Array (triangles in model space)
	var bases := {}   # material names the donor's glass was split from
	for n in donor_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := xform_in(mi, donor_root)
		for si in mi.mesh.get_surface_count():
			var fn := _fn_of(mi.get_active_material(si))
			if fn == "":
				continue
			bases[mi.get_active_material(si).resource_name.get_slice("__", 0)] = true
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tris: PackedVector3Array = glass.get(fn, PackedVector3Array())
			for i in idx:
				tris.append(xf * vs[i])
			glass[fn] = tris
	var boxes := {}
	for fn in glass:
		var t: PackedVector3Array = glass[fn]
		var b := AABB(t[0], Vector3.ZERO)
		for v in t:
			b = b.expand(v)
		boxes[fn] = b.grow(DONOR_TOL * 2.0)
	var out := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := xform_in(mi, root)
		var groups := {}   # surface -> PackedStringArray (function per triangle, "" = keep)
		for si in mi.mesh.get_surface_count():
			var sm := mi.get_active_material(si)
			if sm == null or not bases.has(sm.resource_name):
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				continue
			var g := PackedStringArray()
			g.resize(idx.size() / 3)
			var any := false
			for t in range(idx.size() / 3):
				var c := (xf * vs[idx[t * 3]] + xf * vs[idx[t * 3 + 1]] + xf * vs[idx[t * 3 + 2]]) / 3.0
				var best := DONOR_TOL
				for fn in glass:
					if not (boxes[fn] as AABB).has_point(c):
						continue
					var d := _dist_to_tris(c, glass[fn])
					if d <= best:
						best = d
						g[t] = fn
						any = true
			if any:
				groups[si] = g
		if not groups.is_empty():
			out[root.get_path_to(mi)] = _split(mi, groups)
	return out


## Lamp glass of one material split at the model's light markers.
static func markers(root: Node3D, material_name: String) -> Dictionary:
	var marks: Array = []   # [function, position]
	for n in root.find_children("*", "Node3D", true, false):
		for pre in MARKER_FN:
			if String(n.name).begins_with(pre):
				marks.append([MARKER_FN[pre], xform_in(n, root).origin])
	var out := {}
	if marks.is_empty():
		return out
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := xform_in(mi, root)
		var groups := {}
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			if m == null or m.resource_name != material_name:
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var part := _parts(vs, idx)
			var centre := {}   # part -> [sum, count]
			for t in range(idx.size() / 3):
				var c := (xf * vs[idx[t * 3]] + xf * vs[idx[t * 3 + 1]] + xf * vs[idx[t * 3 + 2]]) / 3.0
				var acc: Array = centre.get(part[t], [Vector3.ZERO, 0])
				centre[part[t]] = [acc[0] + c, acc[1] + 1]
			var g := PackedStringArray()
			g.resize(idx.size() / 3)
			for t in range(idx.size() / 3):
				var acc: Array = centre[part[t]]
				var pc: Vector3 = acc[0] / float(acc[1])
				if _nearest(marks, pc)[1] > MARKER_PART:
					continue
				var c := (xf * vs[idx[t * 3]] + xf * vs[idx[t * 3 + 1]] + xf * vs[idx[t * 3 + 2]]) / 3.0
				var nm: Array = _nearest(marks, c)
				if nm[1] <= MARKER_TRI:
					g[t] = nm[0]
			groups[si] = g
		if not groups.is_empty():
			out[root.get_path_to(mi)] = _split(mi, groups)
	return out


## Transform of node n in the space of its ancestor root (also outside the scene tree).
static func xform_in(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _fn_of(m: Material) -> String:
	if m == null:
		return ""
	for fn in SUFFIX:
		if m.resource_name.ends_with(SUFFIX[fn]):
			return fn
	return ""


## Copy of mi's mesh with the triangles of each surface in `groups` moved into one surface per function.
static func _split(mi: MeshInstance3D, groups: Dictionary) -> ArrayMesh:
	var src := mi.mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var mat := mi.get_active_material(si)
		if not groups.has(si):
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			continue
		var g: PackedStringArray = groups[si]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := {}   # function -> PackedInt32Array
		for t in range(idx.size() / 3):
			var ix: PackedInt32Array = per.get(g[t], PackedInt32Array())
			ix.append(idx[t * 3])
			ix.append(idx[t * 3 + 1])
			ix.append(idx[t * 3 + 2])
			per[g[t]] = ix
		for fn in per:
			var a2 := arr.duplicate()
			a2[Mesh.ARRAY_INDEX] = per[fn]
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			var m2 := mat
			if fn != "" and mat != null:
				m2 = mat.duplicate() as Material
				m2.resource_name = mat.resource_name + SUFFIX[fn]
			out.surface_set_material(out.get_surface_count() - 1, m2)
	return out


## Connected part (shared vertex index or position) per triangle.
static func _parts(vs: PackedVector3Array, idx: PackedInt32Array) -> PackedInt32Array:
	var up := PackedInt32Array()
	up.resize(vs.size())
	for i in vs.size():
		up[i] = i
	var at := {}
	for i in vs.size():
		var k := Vector3i(roundi(vs[i].x * 1000.0), roundi(vs[i].y * 1000.0), roundi(vs[i].z * 1000.0))
		if at.has(k):
			_union(up, i, at[k])
		else:
			at[k] = i
	for t in range(idx.size() / 3):
		_union(up, idx[t * 3], idx[t * 3 + 1])
		_union(up, idx[t * 3], idx[t * 3 + 2])
	var out := PackedInt32Array()
	out.resize(idx.size() / 3)
	for t in range(idx.size() / 3):
		out[t] = _root(up, idx[t * 3])
	return out


static func _root(up: PackedInt32Array, i: int) -> int:
	while up[i] != i:
		up[i] = up[up[i]]
		i = up[i]
	return i


static func _union(up: PackedInt32Array, a: int, b: int) -> void:
	var ra := _root(up, a)
	var rb := _root(up, b)
	if ra != rb:
		up[ra] = rb


static func _nearest(marks: Array, p: Vector3) -> Array:
	var best := INF
	var fn := ""
	for m in marks:
		var d := p.distance_to(m[1])
		if d < best:
			best = d
			fn = m[0]
	return [fn, best]


static func _dist_to_tris(p: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var d := (p - a).dot(n)
		var bc := Geometry3D.get_triangle_barycentric_coords(p - n * d, a, b, c)
		if bc.x >= 0.0 and bc.y >= 0.0 and bc.z >= 0.0:
			best = minf(best, absf(d))
		else:
			best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b)))
			best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
			best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))
	return best
