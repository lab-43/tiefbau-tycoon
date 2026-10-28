extends SceneTree
# Prints useful geometry facts of extracted vehicle models.

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	for id in ["excavator_a918", "truck_tipper", "truck_flatbed", "tractor_tgx", "trailer_lowbed", "van_crew"]:
		var ps: PackedScene = load("res://assets/consim/%s/%s.glb" % [id, id])
		var m: Node3D = ps.instantiate()
		root.add_child(m)
		print("== ", id)
		var mats := {}
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(si)
				if mat and ("__" in mat.resource_name or "Glass" in mat.resource_name):
					mats[mat.resource_name] = str(mat.get_meta("extras", "")) if mat.has_meta("extras") else "-"
		print("  light mats: ", mats)
		for nm in ["turret", "boom", "boom2", "stick", "bucket", "bucket_tip", "tipper_body", "fifth_wheel", "kingpin", "ramp", "ramp_slide", "wheel_fl", "wheel_rl", "crane_column", "body"]:
			var n := m.find_child(nm, true, false) as Node3D
			if n:
				print("  %s: pos=%s parent=%s" % [nm, str(m.global_transform.affine_inverse() * n.global_position), n.get_parent().name])
		var markers := []
		for n in m.find_children("*", "Node3D", true, false):
			if n.name.begins_with("light_") or n.name.begins_with("beacon_") or n.name.begins_with("worklight") or n.name.begins_with("indicator"):
				markers.append(n.name)
		print("  markers: ", markers)
		# height profile along z for |x|<1.1 (top surface)
		var prof := {}
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = m.global_transform.affine_inverse() * mi.global_transform
			for si in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for v in verts:
					var p := xf * v
					if absf(p.x) < 1.0:
						var zb := int(floor(p.z))
						prof[zb] = maxf(prof.get(zb, -1.0), p.y)
		var keys := prof.keys()
		keys.sort()
		var line := ""
		for k in keys:
			line += "%d:%.2f " % [k, prof[k]]
		print("  top profile: ", line)
		if id == "truck_tipper":
			var tb := m.find_child("tipper_body", true, false) as Node3D
			print("  tipper aabb local: ", RigUtil.local_aabb(tb))
		if id == "excavator_a918":
			var b := m.find_child("bucket", true, false) as Node3D
			print("  bucket aabb local: ", RigUtil.local_aabb(b))
	quit()
