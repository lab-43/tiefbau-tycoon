extends SceneTree
## Excavator rig check (issue #3): drives the real excavator model through bucket poses and verifies that the
## bucket linkage stays closed (link_b meets the bucket pin, the bucket cylinder rod sits on the link joint) and
## that the linkage stays on the correct side. Headless: numbers only. Rendered (--shots=<dir>): side views.
## usage: godot --headless --path game -s res://test/rig_test.gd [-- --shots=/tmp/rig]

var shots := ""
var cam: Camera3D
var fails := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run.call_deferred()


func _run() -> void:
	var p := "res://assets/consim/excavator_a918/excavator_a918.glb"
	if not ResourceLoader.exists(p):
		print("RIG SKIP: private excavator model missing")
		quit(0)
		return
	var veh := Node3D.new()
	root.add_child(veh)
	var model: Node3D = (load(p) as PackedScene).instantiate()
	veh.add_child(model)
	var meta := VehicleModels.load_meta("excavator_a918")
	if shots != "":
		_scene()
	await process_frame
	var n := {}
	for k in ["stick", "bucket", "bucket_link_a", "bucket_link_b", "hyd_bucket_a", "hyd_bucket_b"]:
		n[k] = RigUtil.find(model, k)
	# rest-pose reference points (root space = model space)
	var fb: Dictionary = meta.bucket_linkage
	var B0 := Vector3(fb.B_link_a_pivot[0], fb.B_link_a_pivot[1], fb.B_link_a_pivot[2])
	var C0 := Vector3(fb.C_link_joint[0], fb.C_link_joint[1], fb.C_link_joint[2])
	var D0 := Vector3(fb.D_bucket_pin[0], fb.D_bucket_pin[1], fb.D_bucket_pin[2])
	var stick: Node3D = n.stick
	var bucket: Node3D = n.bucket
	var la: Node3D = n.bucket_link_a
	var lb: Node3D = n.bucket_link_b
	var B_st := stick.global_transform.affine_inverse() * B0
	var D_bk := bucket.global_transform.affine_inverse() * D0
	var D_lb := lb.global_transform.affine_inverse() * D0
	var C_la := la.global_transform.affine_inverse() * C0
	_report("rest", stick, bucket, la, lb, n, B_st, D_bk, D_lb, C_la, true)
	if shots != "":
		await _shot("rest", bucket.global_position)
		await _shot("rest_schild", RigUtil.find(model, "blade").global_position)
	_hyd = RigUtil.setup_hydraulics(model, meta)
	for e in _hyd:
		e.len_a = _reach(e.a, e.ax_a)
		e.len_b = _reach(e.b, e.ax_b)
	_check_hyd("rest", true)
	var rig := ExcavatorRig.new()
	rig.setup(veh, model, meta)
	if not rig.ok:
		print("RIG FAIL: setup")
		quit(1)
		return
	var poses := [["travel", 4.6, 2.0, -80.0], ["curl_90", 5.0, 1.5, -90.0], ["curl_60", 5.0, 1.5, -60.0],
		["curl_30", 5.0, 1.5, -30.0], ["b_0", 5.0, 1.5, 0.0], ["dump_30", 5.0, 1.5, 30.0], ["dump_60", 5.0, 1.5, 60.0],
		["dump_75", 5.0, 1.5, 75.0], ["dig_deep", 5.5, -1.5, 15.0, -18.0], ["blade_down", 5.0, 1.5, 0.0, -36.5],
		["lift", 5.0, 0.75, -85.0, -18.0], ["travel_back", 4.6, 2.0, -80.0, 0.0]]
	for ps in poses:
		# approach in small steps like the sequencer does (branch tracking of the four-bar needs continuity)
		var from_b := rad_to_deg(rig.bucket_angle)
		var from_bl := rad_to_deg(rig.blade_angle)
		var to_bl: float = ps[4] if ps.size() > 4 else from_bl
		var from := rig.polar_of(rig.tip_position())
		for i in range(1, 11):
			var w := float(i) / 10.0
			rig.blade_angle = deg_to_rad(lerpf(from_bl, to_bl, w))
			rig.reach_polar(0.0, lerpf(from.y, ps[1], w), lerpf(from.z, ps[2], w), deg_to_rad(lerpf(from_b, ps[3], w)))
		await process_frame
		_report(ps[0], stick, bucket, la, lb, n, B_st, D_bk, D_lb, C_la, false)
		_check_hyd(ps[0], false)
		if shots != "":
			await _shot(ps[0], bucket.global_position)
			if ps[0] == "blade_down":
				await _shot("blade_down_schild", RigUtil.find(model, "blade").global_position)
	# one big jump without intermediate steps (setup does this from the rest pose)
	rig.reach_polar(0.0, 5.0, 1.5, deg_to_rad(70.0))
	rig.reach_polar(0.0, 4.6, 2.0, deg_to_rad(-80.0))
	await process_frame
	_report("jump", stick, bucket, la, lb, n, B_st, D_bk, D_lb, C_la, false)
	print("RIG %s: %d Fehler" % ["OK" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


## Checks one pose and prints the key points in the arm plane (u = forward, v = up).
func _report(tag: String, stick: Node3D, bucket: Node3D, la: Node3D, lb: Node3D, n: Dictionary,
		B_st: Vector3, D_bk: Vector3, D_lb: Vector3, C_la: Vector3, rest: bool) -> void:
	var B := stick.global_transform * B_st
	var D := bucket.global_transform * D_bk        # pin on the bucket
	var Dl := lb.global_transform * D_lb           # where link_b ends
	var C := la.global_transform * C_la            # where link_a ends
	var Cb := lb.global_position                   # link_b pivot (child of link_a)
	var rod: Node3D = n.hyd_bucket_b
	var barrel: Node3D = n.hyd_bucket_a
	var P := bucket.global_position                # bucket hinge on the stick
	var gap_d := D.distance_to(Dl)
	var gap_c := C.distance_to(Cb)
	var gap_rod := rod.global_position.distance_to(Cb)
	# side test: C must stay on the same side of line B-D as at rest (the side away from the bucket)
	var side := _side(B, D, C)
	var bad := gap_d > 0.02 or gap_c > 0.02 or gap_rod > 0.02
	if not rest and side != _rest_side:
		bad = true
	if rest:
		_rest_side = side
	# the rod axis must point at the barrel and the barrel at the rod
	var ax_rod := (rod.global_transform.basis * Vector3(0, 0, -1)).normalized()
	var ax_bar := (barrel.global_transform.basis * Vector3(0, 0, -1)).normalized()
	var to_bar := (barrel.global_position - rod.global_position).normalized()
	var aim_err := rad_to_deg(maxf(ax_rod.angle_to(to_bar), ax_bar.angle_to(-to_bar)))
	if not rest and aim_err > 2.0:
		bad = true
	if bad and not rest:
		fails += 1
	print("RIG %-11s %s  D-Spalt %.3f  C-Spalt %.3f  Stange-C %.3f  Seite %d  Zielfehler %.1f°  P%s B%s C%s D%s" % [
		tag, "FEHLER" if bad and not rest else "ok", gap_d, gap_c, gap_rod, side, aim_err,
		_uv(P), _uv(B), _uv(Cb), _uv(D)])

var _rest_side := 0
var _hyd: Array = []


## How far the meshes of a cylinder half reach from its pivot along its aim axis (local space).
func _reach(node: Node3D, ax: Vector3) -> float:
	var inv := node.global_transform.affine_inverse()
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)   # RigUtil.local_aabb only looks at children; the cylinder halves are meshes themselves
	var m := 0.0
	for mi in meshes:
		var mm := mi as MeshInstance3D
		if mm.mesh == null:
			continue
		var ab := mm.mesh.get_aabb()
		var xf := inv * mm.global_transform
		for i in 8:
			m = maxf(m, (xf * ab.get_endpoint(i)).dot(ax))
	return m


## Every cylinder: both halves aim at each other, the rod stays inside the barrel and does not poke out behind it.
func _check_hyd(tag: String, rest: bool) -> void:
	var parts: Array = []
	for e in _hyd:
		var a: Node3D = e.a
		var b: Node3D = e.b
		var pa := a.global_position
		var pb := b.global_position
		var dist := pa.distance_to(pb)
		var ax_a: Vector3 = e.ax_a
		var ax_b: Vector3 = e.ax_b
		var da := (a.global_transform.basis * ax_a).normalized()
		var db := (b.global_transform.basis * ax_b).normalized()
		var err := rad_to_deg(maxf(da.angle_to((pb - pa).normalized()), db.angle_to((pa - pb).normalized())))
		var overlap: float = e.len_a + e.len_b - dist   # > 0: rod still inside the barrel
		var behind: float = e.len_b - dist              # > 0: rod end sticks out behind the barrel pivot
		var measured: bool = e.len_a + e.len_b > 0.01   # cylinder halves without meshes: aim check only
		if rest:
			# the exported prefab pose is the reference (blade: rod already reaches 7 cm past the barrel pivot)
			e.overlap0 = overlap
			e.behind0 = behind
		var bad: bool = not rest and (err > 2.0 or (measured and
			(overlap < minf(0.05, e.overlap0 - 0.01) or behind > maxf(0.05, e.behind0 + 0.01))))
		if bad:
			fails += 1
		parts.append("%s %s L%.2f/%.2f+%.2f W%.1f°" % [String(a.name).trim_prefix("hyd_").trim_suffix("_a"),
			"FEHLER" if bad else ("ref" if rest else "ok"), dist, e.len_a, e.len_b, err])
	print("HYD %-11s %s" % [tag, "  ".join(parts)])


func _side(a: Vector3, b: Vector3, c: Vector3) -> int:
	var ab := Vector2(-(b.z - a.z), b.y - a.y)
	var ac := Vector2(-(c.z - a.z), c.y - a.y)
	return 1 if ab.cross(ac) > 0.0 else -1


func _uv(p: Vector3) -> String:
	return "(%.2f,%.2f)" % [-p.z, p.y]


func _scene() -> void:
	root.size = Vector2i(1280, 960)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	root.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.6
	root.add_child(cam)
	cam.current = true


## Side view from +X (the arm sits at x = 0.147), centred on the bucket hinge.
func _shot(tag: String, focus: Vector3) -> void:
	cam.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), focus + Vector3(8.0, 0.0, -0.25))
	for i in 6:
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shots)
	img.save_png(shots.path_join("rig_%s.png" % tag))
