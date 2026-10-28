extends SceneTree
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	for f in ["01_absperrschranke", "02_leitbake", "04_leitkegel", "05_z123", "06_z274", "07_plantafel"]:
		var m: Node3D = (load("res://assets/barriers/%s.glb" % f) as PackedScene).instantiate()
		root.add_child(m)
		var ab := RigUtil.local_aabb(m)
		var names := []
		for n in m.find_children("*", "Node3D", true, false):
			names.append(String(n.name))
		var mats := {}
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var mt = mi.get_active_material(si)
				if mt: mats[mt.resource_name] = 1
		var tris := 0
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_len(si) if mi.mesh.surface_get_format(si) & Mesh.ARRAY_FORMAT_INDEX == 0 else mi.mesh.surface_get_array_index_len(si)
		print(f, " aabb=", ab, " tris~", tris / 3, "\n   nodes=", names.slice(0, 30), "\n   mats=", mats.keys())
	quit()
