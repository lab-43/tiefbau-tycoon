class_name VehicleModels
extends RefCounted
## Loads the visual model for a vehicle type: an extracted GLB (res://assets/consim/<id>/<id>.glb)
## with its metadata JSON, or a procedural stand-in that uses the same canonical node names
## (turret, boom, stick, bucket, bucket_tip, tipper_body, milling_drum, conveyor, drum_front/rear,
## wheel_fl/fr/rl/rr..., fifth_wheel, kingpin, light_head_l/r, light_tail_l/r, indicator_*, beacon_*).

static func load_meta(model_id: String) -> Dictionary:
	var p := "res://assets/consim/%s/%s.json" % [model_id, model_id]
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


static func instance(model_id: String, def: Dictionary) -> Node3D:
	var p := "res://assets/consim/%s/%s.glb" % [model_id, model_id]
	if ResourceLoader.exists(p):
		var sc: PackedScene = load(p)
		if sc:
			var n: Node3D = sc.instantiate()
			n.set_meta("source", "glb")
			return n
	var root := Node3D.new()
	root.set_meta("source", "procedural")
	match def.get("category", ""):
		_:
			pass
	match model_id:
		"excavator_a918":
			_excavator(root, def)
		"truck_tipper":
			_tipper(root, def)
		"truck_flatbed":
			_flatbed(root, def)
		"tractor_tgx":
			_tractor(root, def)
		"trailer_lowbed":
			_lowbed(root)
		"cold_planer_bm2000":
			_planer(root, def)
		"roller_bw141":
			_roller(root, def)
		_:
			_van(root, def)
	return root


static func mat(c: Color, rough := 0.55, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func box(parent: Node3D, name: String, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


static func wheel(parent: Node3D, name: String, pos: Vector3, r: float, w: float) -> Node3D:
	var pv := pivot(parent, name, pos)
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = w
	c.radial_segments = 14
	mi.mesh = c
	mi.rotation = Vector3(0, 0, PI * 0.5)
	mi.material_override = mat(Color(0.07, 0.07, 0.07), 0.85)
	pv.add_child(mi)
	var hub := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = r * 0.55
	hc.bottom_radius = r * 0.55
	hc.height = w + 0.02
	hc.radial_segments = 10
	hub.mesh = hc
	hub.rotation = Vector3(0, 0, PI * 0.5)
	hub.material_override = mat(Color(0.75, 0.75, 0.74), 0.4, 0.6)
	pv.add_child(hub)
	return pv


static func marker(parent: Node3D, name: String, pos: Vector3) -> void:
	pivot(parent, name, pos)


static func _cab(root: Node3D, z_front: float, width: float, height: float, length: float, col: Color) -> void:
	box(root, "cab", Vector3(width, height, length), Vector3(0, 1.0 + height * 0.5, z_front + length * 0.5), mat(col, 0.4, 0.2))
	box(root, "windshield", Vector3(width - 0.2, height * 0.42, 0.06), Vector3(0, 1.0 + height * 0.68, z_front - 0.01), mat(Color(0.07, 0.09, 0.11), 0.05, 0.5))


static func _van(root: Node3D, def: Dictionary) -> void:
	var c: Color = def.get("color", Color.WHITE)
	var L: float = def.get("length", 5.4)
	box(root, "body", Vector3(2.0, 1.85, L - 0.8), Vector3(0, 1.45, 0.35), mat(c, 0.35, 0.2))
	box(root, "hood", Vector3(1.95, 0.9, 0.9), Vector3(0, 0.95, -L * 0.5 + 0.45), mat(c, 0.35, 0.2))
	box(root, "windshield", Vector3(1.8, 0.7, 0.06), Vector3(0, 1.75, -L * 0.5 + 0.92), mat(Color(0.07, 0.09, 0.11), 0.05, 0.5))
	box(root, "stripe", Vector3(2.02, 0.18, L - 0.9), Vector3(0, 1.05, 0.35), mat(UI.ACCENT, 0.5))
	for p in [["wheel_fl", -1.0, -1.6], ["wheel_fr", 1.0, -1.6], ["wheel_rl", -1.0, 1.75], ["wheel_rr", 1.0, 1.75]]:
		wheel(root, p[0], Vector3(p[1] * 0.88, 0.36, p[2]), 0.36, 0.24)
	_std_lights(root, L, 2.0, 0.85, 2.48)


static func _tipper(root: Node3D, def: Dictionary) -> void:
	var c: Color = def.get("color", UI.ACCENT)
	var L: float = def.get("length", 8.4)
	box(root, "chassis", Vector3(1.2, 0.35, L - 0.5), Vector3(0, 0.95, 0.2), mat(Color(0.12, 0.12, 0.12)))
	_cab(root, -L * 0.5, 2.5, 2.1, 2.3, Color(0.93, 0.93, 0.92))
	var tb := pivot(root, "tipper_body", Vector3(0, 1.2, L * 0.5 - 0.3))
	var bed_len := L - 3.0
	box(tb, "bed_floor", Vector3(2.4, 0.15, bed_len), Vector3(0, 0.1, -bed_len * 0.5), mat(c, 0.6))
	for sx in [-1.0, 1.0]:
		box(tb, "bed_side", Vector3(0.1, 1.1, bed_len), Vector3(sx * 1.17, 0.7, -bed_len * 0.5), mat(c, 0.6))
	box(tb, "bed_front", Vector3(2.4, 1.3, 0.12), Vector3(0, 0.8, -bed_len), mat(c, 0.6))
	box(tb, "bed_rear", Vector3(2.4, 1.05, 0.1), Vector3(0, 0.68, -0.05), mat(c, 0.6))
	marker(tb, "load_anchor", Vector3(0, 0.2, -bed_len * 0.5))
	for p in [["wheel_fl", -1.0, -L * 0.5 + 1.3], ["wheel_fr", 1.0, -L * 0.5 + 1.3], ["wheel_rl", -1.0, L * 0.5 - 2.4], ["wheel_rr", 1.0, L * 0.5 - 2.4], ["wheel_rl2", -1.0, L * 0.5 - 1.0], ["wheel_rr2", 1.0, L * 0.5 - 1.0]]:
		wheel(root, p[0], Vector3(p[1] * 1.05, 0.52, p[2]), 0.52, 0.35)
	_std_lights(root, L, 2.5, 1.0, 3.25)


static func _flatbed(root: Node3D, def: Dictionary) -> void:
	var L: float = def.get("length", 8.6)
	box(root, "chassis", Vector3(1.2, 0.35, L - 0.5), Vector3(0, 0.95, 0.2), mat(Color(0.12, 0.12, 0.12)))
	_cab(root, -L * 0.5, 2.5, 2.1, 2.3, Color(0.93, 0.93, 0.92))
	box(root, "crane", Vector3(0.6, 1.6, 0.8), Vector3(0, 2.0, -L * 0.5 + 2.8), mat(UI.ACCENT, 0.5))
	box(root, "deck", Vector3(2.45, 0.2, L - 3.6), Vector3(0, 1.3, 1.25), mat(Color(0.35, 0.33, 0.3), 0.8))
	for sx in [-1.0, 1.0]:
		box(root, "deck_side", Vector3(0.06, 0.45, L - 3.6), Vector3(sx * 1.2, 1.6, 1.25), mat(UI.ACCENT, 0.6))
	marker(root, "load_anchor", Vector3(0, 1.45, 1.25))
	for p in [["wheel_fl", -1.0, -L * 0.5 + 1.3], ["wheel_fr", 1.0, -L * 0.5 + 1.3], ["wheel_rl", -1.0, L * 0.5 - 1.6], ["wheel_rr", 1.0, L * 0.5 - 1.6]]:
		wheel(root, p[0], Vector3(p[1] * 1.05, 0.52, p[2]), 0.52, 0.35)
	_std_lights(root, L, 2.5, 1.0, 3.3)


static func _tractor(root: Node3D, def: Dictionary) -> void:
	var L: float = def.get("length", 7.0)
	box(root, "chassis", Vector3(1.2, 0.35, L - 0.4), Vector3(0, 0.95, 0.0), mat(Color(0.12, 0.12, 0.12)))
	_cab(root, -L * 0.5, 2.5, 2.6, 2.4, Color(0.93, 0.93, 0.92))
	box(root, "fifth_plate", Vector3(1.6, 0.12, 1.4), Vector3(0, 1.2, L * 0.5 - 1.6), mat(Color(0.2, 0.2, 0.2)))
	marker(root, "fifth_wheel", Vector3(0, 1.25, L * 0.5 - 1.6))
	for p in [["wheel_fl", -1.0, -L * 0.5 + 1.3], ["wheel_fr", 1.0, -L * 0.5 + 1.3], ["wheel_rl", -1.0, L * 0.5 - 1.9], ["wheel_rr", 1.0, L * 0.5 - 1.9], ["wheel_rl2", -1.0, L * 0.5 - 0.6], ["wheel_rr2", 1.0, L * 0.5 - 0.6]]:
		wheel(root, p[0], Vector3(p[1] * 1.05, 0.52, p[2]), 0.52, 0.35)
	box(root, "beacon_bar", Vector3(1.2, 0.12, 0.25), Vector3(0, 3.66, -L * 0.5 + 0.6), mat(Color(0.2, 0.2, 0.2)))
	marker(root, "beacon_1", Vector3(-0.45, 3.78, -L * 0.5 + 0.6))
	marker(root, "beacon_2", Vector3(0.45, 3.78, -L * 0.5 + 0.6))
	_std_lights(root, L, 2.5, 1.0, -1.0)


static func _lowbed(root: Node3D) -> void:
	var L := 15.0
	box(root, "gooseneck", Vector3(2.5, 0.5, 3.0), Vector3(0, 1.45, -L * 0.5 + 1.5), mat(UI.ACCENT, 0.6))
	box(root, "deck", Vector3(2.55, 0.35, 9.0), Vector3(0, 0.75, 0.3), mat(Color(0.2, 0.2, 0.21), 0.8))
	box(root, "rear", Vector3(2.55, 0.5, 2.6), Vector3(0, 1.0, L * 0.5 - 1.3), mat(UI.ACCENT, 0.6))
	marker(root, "kingpin", Vector3(0, 1.25, -L * 0.5 + 1.0))
	marker(root, "deck_anchor", Vector3(0, 0.95, 0.3))
	for i in 3:
		var z := L * 0.5 - 2.3 + i * 1.3 - 1.3
		wheel(root, "wheel_l%d" % i, Vector3(-1.0, 0.42, z), 0.42, 0.3)
		wheel(root, "wheel_r%d" % i, Vector3(1.0, 0.42, z), 0.42, 0.3)
	var rl := pivot(root, "ramp_left", Vector3(-0.8, 1.2, L * 0.5))
	box(rl, "ramp", Vector3(0.7, 0.08, 2.2), Vector3(0, 0, 1.1), mat(Color(0.3, 0.3, 0.3)))
	var rr := pivot(root, "ramp_right", Vector3(0.8, 1.2, L * 0.5))
	box(rr, "ramp", Vector3(0.7, 0.08, 2.2), Vector3(0, 0, 1.1), mat(Color(0.3, 0.3, 0.3)))
	rl.rotation.x = deg_to_rad(80)
	rr.rotation.x = deg_to_rad(80)
	marker(root, "light_tail_l", Vector3(-1.1, 0.9, L * 0.5 + 0.02))
	marker(root, "light_tail_r", Vector3(1.1, 0.9, L * 0.5 + 0.02))
	marker(root, "indicator_rl", Vector3(-1.2, 0.9, L * 0.5 + 0.02))
	marker(root, "indicator_rr", Vector3(1.2, 0.9, L * 0.5 + 0.02))


static func _excavator(root: Node3D, def: Dictionary) -> void:
	var yel: Color = def.get("color", Color(0.95, 0.78, 0.15))
	box(root, "undercarriage", Vector3(2.4, 0.7, 4.6), Vector3(0, 0.95, 0), mat(Color(0.18, 0.18, 0.18), 0.7))
	box(root, "blade", Vector3(2.5, 0.6, 0.25), Vector3(0, 0.55, 2.55), mat(yel, 0.6))
	for p in [["wheel_fl", -1.0, -1.45], ["wheel_fr", 1.0, -1.45], ["wheel_rl", -1.0, 1.45], ["wheel_rr", 1.0, 1.45]]:
		wheel(root, p[0], Vector3(p[1] * 1.0, 0.55, p[2]), 0.55, 0.45)
	var turret := pivot(root, "turret", Vector3(0, 1.35, 0.2))
	box(turret, "house", Vector3(2.45, 1.1, 3.4), Vector3(0, 0.55, 0.6), mat(yel, 0.5))
	box(turret, "counterweight", Vector3(2.45, 0.9, 0.7), Vector3(0, 0.7, 2.3), mat(Color(0.2, 0.2, 0.2), 0.6))
	box(turret, "cabin", Vector3(0.95, 1.5, 1.5), Vector3(-0.72, 1.6, -0.45), mat(yel, 0.5))
	box(turret, "cab_glass", Vector3(0.9, 0.9, 0.06), Vector3(-0.72, 1.85, -1.21), mat(Color(0.07, 0.09, 0.11), 0.05, 0.5))
	marker(turret, "beacon_1", Vector3(-0.72, 2.45, -0.2))
	marker(turret, "worklight_1", Vector3(-0.72, 2.3, -1.2))
	var boom := pivot(turret, "boom", Vector3(0.35, 0.9, -0.9))
	# boom goes forward-up then the stick hangs down
	var boom_len := 4.6
	var bm := box(boom, "boom_mesh", Vector3(0.45, 0.55, boom_len), Vector3(0, 0, -boom_len * 0.5), mat(yel, 0.5))
	boom.rotation.x = deg_to_rad(28.0)
	var stick := pivot(boom, "stick", Vector3(0, 0, -boom_len))
	var stick_len := 2.6
	box(stick, "stick_mesh", Vector3(0.36, 0.42, stick_len), Vector3(0, 0, -stick_len * 0.5), mat(yel, 0.5))
	stick.rotation.x = deg_to_rad(-95.0)
	var bucket := pivot(stick, "bucket", Vector3(0, 0, -stick_len))
	box(bucket, "bucket_back", Vector3(0.9, 0.7, 0.12), Vector3(0, -0.25, -0.05), mat(Color(0.25, 0.25, 0.25), 0.6))
	box(bucket, "bucket_floor", Vector3(0.9, 0.12, 0.85), Vector3(0, -0.58, -0.45), mat(Color(0.25, 0.25, 0.25), 0.6))
	for sx in [-0.45, 0.45]:
		box(bucket, "bucket_side", Vector3(0.06, 0.65, 0.85), Vector3(sx, -0.3, -0.45), mat(Color(0.25, 0.25, 0.25), 0.6))
	marker(bucket, "bucket_tip", Vector3(0, -0.62, -0.9))
	marker(bucket, "bucket_load", Vector3(0, -0.35, -0.42))
	bucket.rotation.x = deg_to_rad(-30.0)
	_std_lights(root, 4.8, 2.4, 1.0, -1.0)


static func _planer(root: Node3D, def: Dictionary) -> void:
	var yel: Color = def.get("color", Color(0.95, 0.8, 0.1))
	box(root, "frame", Vector3(2.5, 1.5, 6.5), Vector3(0, 1.45, 0.8), mat(yel, 0.5))
	box(root, "drum_housing", Vector3(2.4, 1.0, 1.4), Vector3(0, 0.8, 0.4), mat(Color(0.25, 0.25, 0.25), 0.6))
	var drum := pivot(root, "milling_drum", Vector3(0, 0.55, 0.4))
	var dm := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 0.5
	dc.bottom_radius = 0.5
	dc.height = 2.0
	dc.radial_segments = 16
	dm.mesh = dc
	dm.rotation = Vector3(0, 0, PI * 0.5)
	dm.material_override = mat(Color(0.3, 0.3, 0.3), 0.5, 0.6)
	drum.add_child(dm)
	box(root, "operator", Vector3(1.8, 1.2, 1.6), Vector3(0, 2.75, 1.0), mat(Color(0.2, 0.2, 0.2), 0.5))
	var conv := pivot(root, "conveyor", Vector3(0, 1.6, -2.4))
	box(conv, "belt", Vector3(0.8, 0.35, 7.5), Vector3(0, 0, -3.6), mat(Color(0.15, 0.15, 0.15), 0.6))
	conv.rotation.x = deg_to_rad(16.0)
	marker(conv, "conveyor_end", Vector3(0, 0.2, -7.3))
	for p in [["wheel_fl", -0.95, -1.0], ["wheel_fr", 0.95, -1.0], ["wheel_rl", -0.95, 2.9], ["wheel_rr", 0.95, 2.9]]:
		wheel(root, p[0], Vector3(p[1], 0.45, p[2]), 0.45, 0.5)
	marker(root, "beacon_1", Vector3(0, 3.5, 1.0))
	_std_lights(root, 6.5, 2.5, 1.2, -1.0)


static func _roller(root: Node3D, def: Dictionary) -> void:
	var yel: Color = def.get("color", Color(0.95, 0.8, 0.1))
	for d in [["drum_front", -1.15], ["drum_rear", 1.15]]:
		var pv := pivot(root, d[0], Vector3(0, 0.6, d[1]))
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.6
		c.bottom_radius = 0.6
		c.height = 1.4
		c.radial_segments = 18
		mi.mesh = c
		mi.rotation = Vector3(0, 0, PI * 0.5)
		mi.material_override = mat(Color(0.45, 0.45, 0.46), 0.35, 0.7)
		pv.add_child(mi)
		box(root, "drum_frame", Vector3(1.6, 0.5, 1.4), Vector3(0, 1.15, d[1]), mat(yel, 0.5))
	box(root, "body", Vector3(1.3, 0.8, 1.4), Vector3(0, 1.4, 0), mat(yel, 0.5))
	box(root, "rops", Vector3(1.3, 1.2, 0.08), Vector3(0, 2.3, 0.4), mat(Color(0.15, 0.15, 0.15), 0.5))
	box(root, "roof", Vector3(1.4, 0.06, 1.2), Vector3(0, 2.9, 0.0), mat(Color(0.15, 0.15, 0.15), 0.5))
	marker(root, "beacon_1", Vector3(0, 3.0, 0.0))
	_std_lights(root, 3.4, 1.5, 1.2, -1.0)


static func _std_lights(root: Node3D, L: float, W: float, y: float, roof_y: float) -> void:
	marker(root, "light_head_l", Vector3(-W * 0.5 + 0.25, y, -L * 0.5 - 0.02))
	marker(root, "light_head_r", Vector3(W * 0.5 - 0.25, y, -L * 0.5 - 0.02))
	marker(root, "light_tail_l", Vector3(-W * 0.5 + 0.2, y, L * 0.5 + 0.02))
	marker(root, "light_tail_r", Vector3(W * 0.5 - 0.2, y, L * 0.5 + 0.02))
	marker(root, "indicator_fl", Vector3(-W * 0.5 + 0.05, y, -L * 0.5 - 0.02))
	marker(root, "indicator_fr", Vector3(W * 0.5 - 0.05, y, -L * 0.5 - 0.02))
	marker(root, "indicator_rl", Vector3(-W * 0.5 + 0.05, y, L * 0.5 + 0.02))
	marker(root, "indicator_rr", Vector3(W * 0.5 - 0.05, y, L * 0.5 + 0.02))
	if roof_y > 0.0:
		marker(root, "beacon_1", Vector3(-0.5, roof_y, -L * 0.5 + 0.9))
		marker(root, "beacon_2", Vector3(0.5, roof_y, -L * 0.5 + 0.9))
