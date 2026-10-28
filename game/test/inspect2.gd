extends SceneTree
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	for id in ["tractor_tgx", "trailer_lowbed", "truck_tipper"]:
		var m: Node3D = (load("res://assets/consim/%s/%s.glb" % [id, id]) as PackedScene).instantiate()
		root.add_child(m)
		var names := []
		for n in m.find_children("*", "Node3D", true, false):
			if not (n is MeshInstance3D):
				names.append("%s<%s>" % [n.name, n.get_parent().name])
		print(id, ": ", " ".join(names.slice(0, 80)))
	quit()
