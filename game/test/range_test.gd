extends SceneTree
## Checks that the city meshes with a visibility range sit where their geometry is. Godot measures
## visibility_range from the node's origin, not from the mesh; with all chunks at the map origin,
## markings vanished 900 m from the map centre (#5).
## usage: godot --headless --path game -s res://test/range_test.gd -- <file.osm.pbf>   (tools/test.sh sichtweite)
## Prints "RANGE OK <n>" or "RANGE FAIL …" (exit code 1).

func _initialize() -> void:
	var pbf: String = OS.get_cmdline_user_args()[0]
	var mb := MapBuilder.new()
	var res := mb.bake({"center_lat": 52.0907, "center_lon": 5.1214, "size_m": 3000.0}, "", pbf)
	var root := MapBuilder.create_city_root(res)
	for group in ["roads", "city"]:
		for ck in res[group]:
			MapBuilder.add_chunk_layers(root, ck, res[group][ck])
	var checked := 0
	var bad: Array = []
	for holder in root.get_children():
		for mi in holder.get_children():
			if not (mi is MeshInstance3D) or mi.visibility_range_end <= 0.0:
				continue
			var c: Vector3 = mi.position + mi.mesh.get_aabb().get_center()
			var d := Vector2(c.x - mi.position.x, c.z - mi.position.z).length()
			checked += 1
			if d > MapBuilder.CHUNK:
				bad.append("%s/%s: Ursprung %.0f m neben der Geometrie" % [holder.name, mi.name, d])
	root.free()
	if checked == 0:
		print("RANGE FAIL keine Meshes mit Sichtweite gefunden")
		quit(1)
	elif bad.is_empty():
		print("RANGE OK %d" % checked)
		quit(0)
	else:
		print("RANGE FAIL ", bad.slice(0, 5))
		quit(1)
