class_name PropsMeshes
extends RefCounted
## Procedural low-poly meshes for instanced props (trees, street lamps).

static var _tree: Mesh
static var _lamp: Mesh


static func tree() -> Mesh:
	if _tree:
		return _tree
	var st := SurfaceTool.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 3.2
	trunk.radial_segments = 6
	trunk.rings = 1
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.6, 0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, Mats.get_mat("trunk"))
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blobs := [[Vector3(0, 5.2, 0), 2.6], [Vector3(0.9, 4.4, 0.5), 1.8], [Vector3(-0.8, 4.6, -0.6), 1.9], [Vector3(0.2, 6.4, -0.2), 1.7]]
	for b in blobs:
		var s := SphereMesh.new()
		s.radius = b[1]
		s.height = b[1] * 1.8
		s.radial_segments = 8
		s.rings = 5
		st2.append_from(s, 0, Transform3D(Basis(), b[0]))
	st2.generate_normals()
	st2.commit(mesh)
	mesh.surface_set_material(1, Mats.get_mat("foliage"))
	_tree = mesh
	return mesh


static func lamp() -> Mesh:
	if _lamp:
		return _lamp
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = 7.0
	pole.radial_segments = 6
	pole.rings = 1
	st.append_from(pole, 0, Transform3D(Basis(), Vector3(0, 3.5, 0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 1.4)
	st.append_from(arm, 0, Transform3D(Basis(), Vector3(0, 6.95, -0.65)))
	var mesh := st.commit()
	mesh.surface_set_material(0, Mats.get_mat("lamp_pole"))
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := BoxMesh.new()
	head.size = Vector3(0.35, 0.12, 0.7)
	st2.append_from(head, 0, Transform3D(Basis(), Vector3(0, 6.88, -1.35)))
	st2.commit(mesh)
	mesh.surface_set_material(1, Mats.get_mat("lamp_head"))
	_lamp = mesh
	return mesh
