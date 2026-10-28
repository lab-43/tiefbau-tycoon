extends SceneTree
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	for f in ["01_absperrschranke", "02_leitbake", "05_z123", "06_z274"]:
		var m: Node3D = (load("res://assets/barriers/%s.glb" % f) as PackedScene).instantiate()
		root.add_child(m)
		var acc := {}
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = m.global_transform.affine_inverse() * mi.global_transform
			for si in mi.mesh.get_surface_count():
				var mt = mi.get_active_material(si)
				if mt == null or not ("reflector" in mt.resource_name or "decal" in mt.resource_name.to_lower()):
					continue
				var arr: Array = mi.mesh.surface_get_arrays(si)
				var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var sum := Vector3.ZERO
				for n in nr:
					sum += xf.basis * n
				acc[mt.resource_name + "@" + mi.name] = (sum / max(1, nr.size()))
		print(f)
		for k in acc:
			print("   ", k, " avg normal ", acc[k])
	quit()
