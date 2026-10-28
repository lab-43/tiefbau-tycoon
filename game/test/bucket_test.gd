extends SceneTree
## Bucket load check (issue #11): the soil in the excavator bucket must sit in the cavity and heap out of the
## opening. Runs on the procedural stand-in bucket (always) and on the real model (if the private assets exist).
## Checks: opening found, plausible volume, no load point behind a bucket wall (each point sees the middle of the
## load without crossing the bucket), the load surface faces up while carrying, the bucket empties while tipping.
## A counter-check runs the same wall test on the old placement (box centre, bucket +Y), which must fail.
## usage: godot --headless --path game -s res://test/bucket_test.gd [-- --shots=/tmp/schaufel]  (shots need rendering)

var shots := ""
var cam: Camera3D
var fails := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run.call_deferred()


func _run() -> void:
	if shots != "":
		_scene()
	var models := [["ersatz", false]]
	if ResourceLoader.exists("res://assets/consim/excavator_a918/excavator_a918.glb"):
		models.append(["a918", true])
	else:
		print("SCHAUFEL Hinweis: privates Baggermodell fehlt, nur Ersatzmodell geprüft")
	for m in models:
		await _check_model(m[0], m[1])
	print("SCHAUFEL %s: %d Fehler" % ["OK" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _check_model(tag: String, glb: bool) -> void:
	var veh := Node3D.new()
	root.add_child(veh)
	var model: Node3D
	var meta := {}
	if glb:
		model = (load("res://assets/consim/excavator_a918/excavator_a918.glb") as PackedScene).instantiate()
		meta = VehicleModels.load_meta("excavator_a918")
	else:
		model = Node3D.new()
		VehicleModels._excavator(model, {})
	veh.add_child(model)
	await process_frame
	var t0 := Time.get_ticks_msec()
	var rig := ExcavatorRig.new()
	rig.setup(veh, model, meta)
	var ms := Time.get_ticks_msec() - t0
	var ld := rig.load_node
	if not rig.ok or ld == null or not ld.ok:
		_fail(tag, "Öffnung der Schaufel nicht gefunden")
		veh.queue_free()
		return
	var full := ld.struck + ld.heap_full
	print("SCHAUFEL %s Analyse %d ms · Öffnung %.2f m × %.2f m · Hohlraum %.2f m³ + Haufen %.2f m³ (Nenn %.2f m³)" % [
		tag, ms, ld.span, ld.x_hi - ld.x_lo, ld.struck, ld.heap_full, ld.capacity])
	if full < ld.capacity * 0.4 or full > ld.capacity * 2.5:
		_fail(tag, "Volumen unplausibel (%.2f m³ statt etwa %.2f m³)" % [full, ld.capacity])
	var tris := BucketLoad._triangles(rig.bucket, ld)
	rig.set_load(ld.capacity, "soil")
	var ref := _cavity_ref(tag, tris, _mesh_points(ld, Transform3D.IDENTITY), _top_normal(ld))
	if ref == Vector3.INF:
		veh.queue_free()
		await process_frame
		return
	# no load point behind a bucket wall, at every fill level
	for f in [1.0, 0.35, 1.2]:
		rig.set_load(ld.capacity * f, "soil")
		_check_inside(tag, "Füllung %d %%" % int(f * 100.0), tris, _mesh_points(ld, Transform3D.IDENTITY), ref)
	# counter-check on the real model: the old mound (box centre, growing along bucket +Y) pokes out of the back
	# (the box-shaped stand-in bucket happens to open towards +Y, there the old placement was fine)
	if glb:
		var old := RigUtil.local_aabb(rig.bucket)
		var old_xf := Transform3D(Basis.from_scale(Vector3(old.size.x * 0.85, old.size.y * 0.55, old.size.z * 0.75)),
			old.get_center())
		var old_pts := PackedVector3Array()
		for p in RigUtil.mound_mesh().get_faces():
			old_pts.append(old_xf * p)
		_check_inside(tag, "Gegenprobe alte Platzierung", tris, old_pts, ref, true)
	if not glb:
		# the box-shaped stand-in hangs upside down in the carry pose (its open side is bucket +Y), carry and tip
		# are only checked on the real model
		veh.queue_free()
		await process_frame
		return
	# carrying: the load surface faces up; tipping: the bucket empties before "dropped"
	rig.set_load(ld.capacity, "soil")
	_pose(rig, 5.0, 2.5, -88.0)
	var up := _surface_up(ld)
	print("SCHAUFEL %s Tragen: Oberfläche zeigt %.2f nach oben, Öffnung %.2f" % [tag, up, ld.opening_up()])
	if up < 0.5:
		_fail(tag, "Erde zeigt beim Tragen nicht nach oben (%.2f)" % up)
	if shots != "":
		await _shot("%s_tragen" % tag, rig)
	var seen := {"start": -1.0, "dropped": -1.0}
	var on_ev := func(kind: String, _d: Dictionary) -> void:
		if kind == "dropped":
			seen.dropped = ld.shown_fill() if ld.visible else 0.0
	rig.cycle_event.connect(on_ev)
	rig.run([{"dur": 1.6, "yaw": 0.0, "r": 5.0, "h": 2.5, "bucket": 55.0, "ev": "dropped", "pour": true}])
	var mid_shot := false
	for i in 200:
		rig.update(0.02)
		if seen.start < 0.0:
			seen.start = ld.shown_fill()
		if shots != "" and not mid_shot and ld.shown_fill() < 0.6 and ld.visible:
			mid_shot = true
			await _shot("%s_kippen" % tag, rig)
		if not rig.busy:
			break
	rig.cycle_event.disconnect(on_ev)
	print("SCHAUFEL %s Kippen: am Anfang %.2f, beim Abwurf %.2f" % [tag, seen.start, seen.dropped])
	if seen.start < 0.9:
		_fail(tag, "Schaufel ist am Anfang des Kippens schon leer (%.2f)" % seen.start)
	if seen.dropped > 0.05:
		_fail(tag, "Erde bleibt beim Auskippen in der Schaufel (%.2f)" % seen.dropped)
	veh.queue_free()
	await process_frame


## A point inside the cavity: from the middle of the load go against its top surface normal ("down" into the
## bucket) halfway to the first wall. The load must rest on the bucket there, and the point must be enclosed by the
## bucket on most sides. Returns Vector3.INF on failure.
func _cavity_ref(tag: String, tris: PackedVector3Array, pts: PackedVector3Array, top: Vector3) -> Vector3:
	if pts.is_empty() or top == Vector3.ZERO:
		_fail(tag, "keine Erde sichtbar")
		return Vector3.INF
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var down := -top
	var t_down := BucketLoad._ray3(tris, c, down)
	if t_down == INF:
		_fail(tag, "Erde liegt auf nichts auf (unter ihrer Oberfläche ist keine Schaufel)")
		return Vector3.INF
	var ref := c + down * t_down * 0.5
	var hits := 0
	var dirs := 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dy == 0 and dz == 0:
					continue
				dirs += 1
				if BucketLoad._ray3(tris, ref, Vector3(dx, dy, dz).normalized()) < INF:
					hits += 1
	print("SCHAUFEL %s Bezugspunkt im Hohlraum: von %d Richtungen %d durch die Schaufel begrenzt" % [tag, dirs, hits])
	if hits < dirs * 0.6:
		_fail(tag, "Erde liegt nicht in der Schaufel")
		return Vector3.INF
	return ref


## Every load point must see the cavity point without crossing a bucket wall. Walls closer than WALL_TOL to the
## point are ignored: the tooth adapters on the lip reach a few cm into the soil (the soil covers them), the old
## placement stuck 10-30 cm out of the back. expect_fail: counter-check that must be flagged.
const WALL_TOL := 0.06
func _check_inside(tag: String, what: String, tris: PackedVector3Array, pts: PackedVector3Array, ref: Vector3,
		expect_fail := false) -> void:
	if pts.is_empty():
		_fail(tag, "%s: keine Erde sichtbar" % what)
		return
	var uniq := {}
	for p in pts:
		uniq[Vector3i((p * 200.0).round())] = p
	var outside := 0
	for p: Vector3 in uniq.values():
		var to_r := ref - p
		var dist := to_r.length()
		if dist < WALL_TOL + 0.02:
			continue
		var d := to_r / dist
		if BucketLoad._ray3(tris, p + d * WALL_TOL, d) < dist - WALL_TOL - 0.01:
			outside += 1
	var bad := outside > 0
	print("SCHAUFEL %s %-28s %s  %d Punkte, davon hinter einer Wand: %d" % [tag, what,
		("erkannt" if bad else "NICHT ERKANNT") if expect_fail else ("FEHLER" if bad else "ok"), uniq.size(), outside])
	if bad != expect_fail:
		fails += 1


func _mesh_points(mi: MeshInstance3D, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi.mesh == null or not mi.visible:
		return out
	for p in mi.mesh.get_faces():
		out.append(xf * p)
	return out


## Mean normal of the load's top surface (surface 0) in bucket space.
func _top_normal(ld: BucketLoad) -> Vector3:
	if ld.mesh == null or ld.mesh.get_surface_count() == 0:
		return Vector3.ZERO
	var nm: PackedVector3Array = ld.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var sum := Vector3.ZERO
	for v in nm:
		sum += v
	return sum.normalized()


## World y of the load's mean top surface normal: 1 = faces straight up.
func _surface_up(ld: BucketLoad) -> float:
	var nb := _top_normal(ld)
	if nb == Vector3.ZERO:
		return -1.0
	return (ld.global_transform.basis * nb).normalized().y


func _pose(rig: ExcavatorRig, r: float, h: float, bucket_deg: float) -> void:
	var from := rig.polar_of(rig.tip_position())
	var fb := rad_to_deg(rig.bucket_angle)
	for i in range(1, 11):
		var w := float(i) / 10.0
		rig.reach_polar(0.0, lerpf(from.y, r, w), lerpf(from.z, h, w), deg_to_rad(lerpf(fb, bucket_deg, w)))


func _fail(tag: String, msg: String) -> void:
	fails += 1
	print("SCHAUFEL %s FEHLER: %s" % [tag, msg])


func _scene() -> void:
	root.size = Vector2i(900, 700)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.current = true


## Two views of the bucket: from the side (+X) and from above-front.
func _shot(tag: String, rig: ExcavatorRig) -> void:
	var f: Vector3 = rig.bucket.global_position + Vector3(0, 0, -0.6)
	for v in [["seite", Vector3(4.0, 0.3, 0.0)], ["oben", Vector3(2.5, 3.0, -1.9)]]:
		cam.look_at_from_position(f + v[1], f, Vector3.UP)
		for i in 6:
			await process_frame
		DirAccess.make_dir_recursive_absolute(shots)
		root.get_texture().get_image().save_png(shots.path_join("schaufel_%s_%s.png" % [tag, v[0]]))
