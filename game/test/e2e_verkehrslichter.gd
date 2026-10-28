extends RefCounted
## e2e scenario "verkehrslichter" (tools/test.sh verkehrslichter), #2: one car of every traffic model in a row at the HQ. Models with their own
## lamp glass must light that glass (no boxes); all others must have every lamp box on the body surface
## (<= 6 cm). With --shots: close-ups front and rear by day and at night, brake and indicators on
## (--models=car_mpv,bus limits the close-ups; rendering is slow under xvfb).
var drv: Node            # the e2e driver (world, t, shot(), shot_queue)
var step := 0
var _vl_cars: Array = []
var _vl_shots: Array = []
var _vl_i := 0
var _vl_fail := 0
func tick(_delta: float) -> void:
	var world: World = drv.world
	match step:
		0:
			if drv.t < 1.5:
				return
			var tr: TrafficSim = world.traffic
			tr.enabled = false
			for ag in tr.agents.duplicate():
				if ag.player == null:
					tr.remove_agent(ag)
			for v in world.fleet.vehicles:
				(v as Node3D).visible = false
			var hq: Dictionary = world.hq_info
			var d2: Vector2 = hq.get("dir", Vector2.RIGHT)
			var n2: Vector2 = hq.get("normal", Vector2.DOWN)
			var gate: Vector2 = hq.get("gate", hq.lot_center)
			var base := Vector3(gate.x, 0.0, gate.y) + Vector3(n2.x, 0.0, n2.y) * 9.0
			var count := TrafficModels.entries.size()
			for i in count:
				var car := TrafficModels.instance(i)
				world.add_child(car)
				car.position = base + Vector3(d2.x, 0.0, d2.y) * (float(i) - (count - 1) * 0.5) * 3.8
				car.rotation.y = atan2(n2.x, n2.y)   # front (-Z) towards the street
				_vl_cars.append(car)
				_vl_check(i, car)
				var e: Dictionary = TrafficModels.entries[i]
				var only := ""
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--models="):
						only = a.substr(9)
				if only == "" or String(e.get("name", e.kind)) in only.split(","):
					_vl_shots.append(i)
				TrafficModels.set_lights(car, i % 2 == 0, -1 if i % 2 == 0 else 1, 0.1)
				_vl_check_state(i, car, Vector4(1.0 if i % 2 == 0 else 0.0, 1.0 if i % 2 == 0 else 0.0, 0.0 if i % 2 == 0 else 1.0, 0.0))
			Clock.set_speed(1)
			step = 1
		1:
			if not drv.shot_queue.is_empty():
				return
			if _vl_i < _vl_shots.size() * 4:
				var night := _vl_i >= _vl_shots.size() * 2
				if _vl_i == _vl_shots.size() * 2:
					Clock.minutes = 22.5 * 60.0
					world.day_night.update_now()
				var k := _vl_i % (_vl_shots.size() * 2)
				var ci: int = _vl_shots[k / 2]
				var car: Node3D = _vl_cars[ci]
				var fwd := -car.global_transform.basis.z
				var yaw := rad_to_deg(atan2(fwd.x, fwd.z)) + (35.0 if k % 2 == 0 else 180.0 - 35.0)
				var e: Dictionary = TrafficModels.entries[ci]
				var nm := String(e.get("name", e.kind))
				var len_m: float = {"car": 4.6, "truck": 9.0, "bus": 12.0}.get(e.kind, 5.0)
				var end_pt := car.global_position + fwd * len_m * (0.35 if k % 2 == 0 else -0.35) + Vector3(0, 0.8, 0)
				drv.shot("vlicht_%s_%02d_%s_%s" % ["nacht" if night else "tag", ci, nm, "vorne" if k % 2 == 0 else "hinten"],
					end_pt, 5.5 + len_m * 0.3, yaw, 18.0)
				_vl_i += 1
				return
			step = 2
		2:
			if not drv.shot_queue.is_empty():
				return
			if _vl_fail > 0:
				print("E2E FAIL verkehrslichter: %d Fehler" % _vl_fail)
				drv.get_tree().quit(1)
				return
			print("E2E OK verkehrslichter (%d Modelle)" % _vl_cars.size())
			drv.get_tree().quit(0)


func _vl_check(i: int, car: Node3D) -> void:
	var e: Dictionary = TrafficModels.entries[i]
	var nm := "%s#%d" % [e.get("name", e.kind), i]
	var lights: Dictionary = car.get_meta("lights", {})
	var glass: Array = lights.get("glass", [])
	if not glass.is_empty():
		var fns := {}
		for mi in glass:
			var m3 := mi as MeshInstance3D
			for si in m3.mesh.get_surface_count():
				var sm := m3.get_active_material(si) as ShaderMaterial
				if sm and sm.shader and sm.shader.resource_path.ends_with("carlamp.gdshader"):
					fns[int(sm.get_shader_parameter("fn"))] = true
		var boxes := car.find_children("*", "MeshInstance3D", false, false).filter(func(c): return (c as MeshInstance3D).mesh is BoxMesh)
		var ok: bool = fns.has(0) and (fns.has(1) or fns.has(2)) and fns.has(3) and fns.has(4) and boxes.is_empty()
		print("VLICHT %-4s %s Lampenglas, Funktionen %s, Kästen %d" % ["ok" if ok else "FAIL", nm, fns.keys(), boxes.size()])
		if not ok:
			_vl_fail += 1
		return
	var quads: Array = []
	for kind in ["head", "tail", "ind_l", "ind_r"]:
		var q: Array = lights.get(kind, [])
		if q.size() < 2:
			print("VLICHT FAIL %s: nur %d × %s" % [nm, q.size(), kind])
			_vl_fail += 1
		quads.append_array(q)
	var faces := VehicleModels.model_faces(car, quads)
	for q in quads:
		var qn := q as MeshInstance3D
		var c: Vector3 = qn.transform.origin
		var nrm: Vector3 = qn.transform.basis.z.normalized()
		var o := c + nrm * 0.5
		var best := INF
		for fi in range(0, faces.size() - 2, 3):
			var h = Geometry3D.ray_intersects_triangle(o, -nrm, faces[fi], faces[fi + 1], faces[fi + 2])
			if h != null:
				best = minf(best, o.distance_to(h))
		var gap := best - 0.5   # > 0: box centre in front of the body
		var ok := best < INF and gap >= -0.03 and gap <= 0.06
		print("VLICHT %-4s %s Kasten bei (%.2f, %.2f, %.2f) Abstand zur Karosserie %.3f m" % ["ok" if ok else "FAIL", nm, c.x, c.y, c.z, gap if best < INF else INF])
		if not ok:
			_vl_fail += 1


## Glass cars: the lamp state really reaches the meshes, and indicator glass is on its side (left = -x).
func _vl_check_state(i: int, car: Node3D, want: Vector4) -> void:
	var e: Dictionary = TrafficModels.entries[i]
	var nm := "%s#%d" % [e.get("name", e.kind), i]
	for mi in car.get_meta("lights", {}).get("glass", []):
		var m3 := mi as MeshInstance3D
		var got = m3.get_instance_shader_parameter("lamp")
		if not (got is Vector4) or not (got as Vector4).is_equal_approx(want):
			print("VLICHT FAIL %s: lamp %s statt %s" % [nm, got, want])
			_vl_fail += 1
		var xf := LampSplit.xform_in(m3, car)
		for si in m3.mesh.get_surface_count():
			var sm := m3.get_active_material(si) as ShaderMaterial
			if sm == null:
				continue
			var fn := int(sm.get_shader_parameter("fn"))
			if fn != 3 and fn != 4:
				continue
			var arr := m3.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]   # split meshes keep all vertices: count the used ones
			var sx := 0.0
			for k in idx:
				sx += (xf * vs[k]).x
			var left := sx < 0.0
			if left != (fn == 3):
				print("VLICHT FAIL %s: Blinkerglas %s liegt auf der falschen Seite (x %.2f)" % [nm, "links" if fn == 3 else "rechts", sx / maxf(1.0, idx.size())])
				_vl_fail += 1
