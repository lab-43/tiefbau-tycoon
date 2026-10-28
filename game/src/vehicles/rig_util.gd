class_name RigUtil
extends RefCounted
## Helpers for articulated vehicle models: hydraulic cylinders that aim at each other, telescopic stages,
## node lookup by canonical names and simple procedural mounds for bulk loads.


static func find(root: Node, name: String) -> Node3D:
	if root == null or name == "":
		return null
	if root.name == name:
		return root as Node3D
	return root.find_child(name, true, false) as Node3D


## Builds hydraulic entries from the asset JSON ("hydraulics": [{a, b, a_local_axis_to_b, b_local_axis_to_a}]).
static func setup_hydraulics(model: Node3D, meta: Dictionary) -> Array:
	var out: Array = []
	for h in meta.get("hydraulics", []):
		var a := find(model, h.get("a", ""))
		var b := find(model, h.get("b", ""))
		if a == null or b == null:
			continue
		var ax_a: Array = h.get("a_local_axis_to_b", [0, 0, -1])
		var ax_b: Array = h.get("b_local_axis_to_a", [0, 0, -1])
		var e := {"a": a, "b": b, "ax_a": Vector3(ax_a[0], ax_a[1], ax_a[2]).normalized(),
			"ax_b": Vector3(ax_b[0], ax_b[1], ax_b[2]).normalized(), "rest_a": a.basis, "rest_b": b.basis,
			"rest_len": float(h.get("rest_length_m", 0.0)), "stages": []}
		# telescopic stages (e.g. tipper cylinder): children named <a-prefix>_stageN
		var base_name := String(h.get("a", "")).trim_suffix("_a")
		for k in range(1, 6):
			var st := find(model, "%s_stage%d" % [base_name, k])
			if st == null:
				break
			e.stages.append([st, st.position])
		out.append(e)
	return out


static func aim(node: Node3D, rest: Basis, axis: Vector3, target_global: Vector3) -> void:
	var parent := node.get_parent() as Node3D
	if parent == null:
		return
	var pinv := parent.global_transform.affine_inverse()
	var local_target := pinv * target_global
	var dir := local_target - node.position
	if dir.length_squared() < 1e-8:
		return
	dir = dir.normalized()
	var rest_o := rest.orthonormalized()
	var cur_axis := (rest_o * axis).normalized()
	var q := Quaternion(cur_axis, dir)
	node.basis = Basis(q) * rest


static func update_hydraulics(entries: Array) -> void:
	for e in entries:
		var a: Node3D = e.a
		var b: Node3D = e.b
		var pa := a.global_position
		var pb := b.global_position
		aim(a, e.rest_a, e.ax_a, pb)
		aim(b, e.rest_b, e.ax_b, pa)
		if not e.stages.is_empty() and e.rest_len > 0.0:
			var ext := maxf(0.0, pa.distance_to(pb) - e.rest_len)
			var n: int = e.stages.size()
			for st in e.stages:
				var node: Node3D = st[0]
				var rest_pos: Vector3 = st[1]
				node.position = rest_pos + e.ax_a * (ext / float(n + 1))


## AABB of all meshes below node, expressed in node's local space.
static func local_aabb(node: Node3D) -> AABB:
	var inv := node.global_transform.affine_inverse()
	var res := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var ab := m.mesh.get_aabb()
		var xf := inv * m.global_transform
		for i in 8:
			var p := xf * ab.get_endpoint(i)
			if first:
				res = AABB(p, Vector3.ZERO)
				first = false
			else:
				res = res.expand(p)
	return res


## Smooth mound mesh (unit footprint 1x1 centred at origin, height 1). Scale it to the load volume.
static var _mound: ArrayMesh
static func mound_mesh() -> ArrayMesh:
	if _mound:
		return _mound
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var verts := []
	for j in n + 1:
		var row := []
		for i in n + 1:
			var x := float(i) / n - 0.5
			var z := float(j) / n - 0.5
			var fx := 1.0 - pow(absf(x) * 2.0, 2.2)
			var fz := 1.0 - pow(absf(z) * 2.0, 2.2)
			var h := maxf(0.0, fx * fz)
			h = pow(h, 0.7)
			row.append(Vector3(x, h, z))
		verts.append(row)
	for j in n:
		for i in n:
			var a: Vector3 = verts[j][i]
			var b: Vector3 = verts[j][i + 1]
			var c: Vector3 = verts[j + 1][i + 1]
			var d: Vector3 = verts[j + 1][i]
			for tri in [[a, b, c], [a, c, d]]:
				for v in tri:
					st.set_uv(Vector2(v.x, v.z))
					st.add_vertex(v)
	st.index()
	st.generate_normals()
	_mound = st.commit()
	return _mound


static var _bulk_mats := {}
static func bulk_material(mat: String) -> Material:
	if _bulk_mats.has(mat):
		return _bulk_mats[mat]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/bulk.gdshader")
	var col: Color = Balance.MATERIALS.get(mat, {}).get("color", Color(0.4, 0.33, 0.25))
	m.set_shader_parameter("base_color", col)
	m.set_shader_parameter("grain", 0.25 if mat in ["gravel", "rubble"] else 0.12)
	_bulk_mats[mat] = m
	return m
