extends RefCounted
## e2e scenario "fahrzeuge" (tools/test.sh fahrzeuge, #24): the new machines (Liebherr R 938 crawler excavator,
## Nooteboom low-loader train, MAN tipper with loading crane, Bobcat S550). Buys each at HQ, checks wheels/tracks
## on the ground, lights on the model surface and joint poses within the asset limits, loads the R 938 and the S550
## onto the Nooteboom and off again, lets the R 938 dig a trench at a site and takes pictures by day and night.
## Works with the private models and with the procedural stand-ins (CI). Driven by e2e_driver.gd (_fahrzeuge_test).

const NEW := ["truck_tipper_crane", "excavator_r938", "loader_s550", "tractor_nooteboom"]
const GROUND_TOL := 0.05      # wheels / tracks: contact point within 5 cm of the ground
const LIGHT_TOL := 0.10       # light markers: lamp centre within 10 cm of the model surface
const BEACON_TOL := 0.06      # beacons: base on the surface below (as e2e:leuchten)

var drv: Node                 # the e2e driver (world, t, shot(), shot_queue, _dump())
var step := 0
var fails := 0
var v_new := {}               # def id -> Vehicle
var t_mark := 0.0
var shot_i := 0
var site: Site
var phase_seen := -1
var log_t := 0.0
var rig_min := {}             # joint name -> lowest angle seen while digging (deg)
var rig_max := {}
var dig_shots := 0
var load_round := 0           # 0: R 938, 1: S550
var deck_checked := false
var seen_dig := false


func ok(cond: bool, what: String) -> void:
	print("FAHRZEUGE %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func _v(id: String) -> Vehicle:
	return v_new.get(id, null)


func tick(delta: float) -> void:
	var w: World = drv.world
	match step:
		0:
			if drv.t < 1.5:
				return
			DebugTools.add_money(2000000.0)
			for id in NEW:
				var v: Vehicle = w.fleet.buy(id)
				ok(v != null, "%s gekauft" % id)
				if v == null:
					_end()
					return
				v_new[id] = v
				ok(v.slot >= 0 and w.hq.in_lot(v.pos2()), "%s steht an der Zentrale (Stellplatz %d)" % [id, v.slot])
				print("FAHRZEUGE %s Modell=%s Anhänger=%s" % [id, v.model.get_meta("source", ""), v.trailer.get_meta("source", "") if v.trailer else "-"])
				if v.trailer:
					var kp := RigUtil.find(v.trailer, "kingpin")
					var fw := v.fifth_wheel()
					print("FAHRZEUGE %s Auflieger-Neigung %.2f°, Königszapfen %.3f m, Sattelkupplung %.3f m (Abstand %.3f m)" % [id,
						rad_to_deg(-v.trailer.global_transform.basis.z.angle_to(Vector3(v.trailer.global_transform.basis.z.x, 0, v.trailer.global_transform.basis.z.z)) * signf(v.trailer.global_transform.basis.z.y)),
						kp.global_position.y if kp else -1.0, fw.global_position.y if fw else -1.0,
						kp.global_position.distance_to(fw.global_position) if kp and fw else -1.0])
			for id in NEW:
				_check_ground(v_new[id], "Zentrale")
				_check_lights(v_new[id])
				_check_joints(v_new[id])
			Clock.set_speed(1)
			Clock.minutes = 11.0 * 60.0
			t_mark = drv.t
			step = 1
		1:
			# pictures at HQ: overview + every new machine, by day
			if not drv.shot_queue.is_empty() or drv.t < t_mark + 2.0:
				return
			if _hq_shots("tag"):
				Clock.minutes = 22.0 * 60.0
				t_mark = drv.t
				shot_i = 0
				step = 2
		2:
			if not drv.shot_queue.is_empty() or drv.t < t_mark + 4.0:
				return
			if _hq_shots("nacht"):
				Clock.minutes = 10.0 * 60.0
				Clock.set_speed(drv.speed)
				step = 3
		3:
			# the old lowbed (32 t) must refuse the 39 t crawler
			var lb: Vehicle = null
			for v in w.fleet.vehicles:
				if v.def_id == "tractor_lowbed":
					lb = v
			var ex := _v("excavator_r938")
			ok(lb != null and not lb.can_carry(ex) and not lb.load_machine(ex) and ex.carried_by == null,
				"Tieflader 32 t lehnt den Raupenbagger (%.0f t) ab" % float(ex.def.weight_t))
			ok(_v("tractor_nooteboom").can_carry(ex), "Nooteboom (%.0f t) trägt den Raupenbagger" % float(_v("tractor_nooteboom").def.load_t))
			load_round = 0
			_start_load()
			step = 4
		4:
			var nb := _v("tractor_nooteboom")
			var m := _machine()
			if not deck_checked and m.state == "loading" and nb.ramp_slide > 4.6:
				deck_checked = true
				drv.shot("fahrzeuge_rampe_%s" % m.def_id, nb.trailer.global_transform * Vector3(0, 1.0, float(nb._deck.end_z)), 20.0, rad_to_deg(nb.rotation.y) + 120.0, 22.0)
			if m.carried_by == nb and nb.state == "parked" and nb.cargo.machine == m:
				var deck: Transform3D = nb.deck_transform()
				ok(m.global_position.distance_to(deck.origin) < 0.05, "%s steht auf dem Deck (Abstand %.3f m)" % [m.def_id, m.global_position.distance_to(deck.origin)])
				var lo := _lowest(m)
				var deck_y: float = deck.origin.y
				ok(lo < 9.0 and absf(lo - deck_y) <= GROUND_TOL, "%s: Räder/Ketten auf dem Deck (%.3f m über Deck)" % [m.def_id, lo - deck_y])
				drv.shot("fahrzeuge_verladen_%s" % m.def_id, deck.origin + Vector3(0, 1.5, 0), 24.0, rad_to_deg(nb.rotation.y) + 140.0, 30.0)
				nb.unload_machine()
				step = 5
		5:
			var nb2 := _v("tractor_nooteboom")
			var m2 := _machine()
			if nb2.cargo.machine == null and nb2.state == "parked" and m2.carried_by == null and m2.state == "parked":
				ok(absf(m2.global_position.y) < 0.01, "%s wieder auf dem Boden" % m2.def_id)
				_check_ground(m2, "abgeladen")
				if load_round == 0:
					load_round = 1
					_start_load()
					step = 4
				else:
					step = 6
		6:
			if not drv.shot_queue.is_empty():
				return
			_start_site()
			step = 7
		7:
			_watch_site(delta)


# ------------------------------------------------------------------------------------------
# Low-loader
# ------------------------------------------------------------------------------------------

func _machine() -> Vehicle:
	return _v("excavator_r938") if load_round == 0 else _v("loader_s550")


func _start_load() -> void:
	deck_checked = false
	var nb := _v("tractor_nooteboom")
	var m := _machine()
	var started := nb.load_machine(m)
	ok(started, "%s fährt auf den Nooteboom" % m.def_id)
	if not started:
		_end()


# ------------------------------------------------------------------------------------------
# Site: the R 938 comes on the Nooteboom and digs the trench
# ------------------------------------------------------------------------------------------

func _start_site() -> void:
	var w: World = drv.world
	var jm := w.jobs
	var j: Job = jm.offers[0]
	for o in jm.offers:
		if o.distance_m < j.distance_m:
			j = o
	jm.accept(j)
	site = jm.site_of(j)
	print("FAHRZEUGE Auftrag %d %s (%.0f m)" % [j.id, j.location(), j.distance_m])
	DebugTools.finish_step(site)    # scout
	DebugTools.finish_step(site)    # closure, instantly
	ok(site.traffic_on and site.step_id() == "dig", "Absperrung steht, nächster Schritt Graben (ist %s)" % site.step_id())
	var nb := _v("tractor_nooteboom")
	var ex := _v("excavator_r938")
	load_round = 0
	nb.load_machine(ex, func(_m):
		site.send_vehicle(nb))
	site.send_vehicle(_v("truck_tipper_crane"))
	for v in w.fleet.vehicles:
		if v.def_id == "truck_tipper":
			site.send_vehicle(v)
	site.auto_continue = true


func _watch_site(delta: float) -> void:
	var ex := _v("excavator_r938")
	if site.phase != phase_seen:
		phase_seen = site.phase
		print("[%7.1f] PHASE %d %s | %s" % [drv.t, site.phase, site.step_id(), site.status])
	if ex.rig and site.running and site.step_id() == "dig":
		for n in ex.rig.chain + [ex.rig.bucket]:
			var nm := String((n as Node3D).name)
			var a: float = rad_to_deg(ex.rig.bucket_angle if n == ex.rig.bucket else float(ex.rig.angles[n]))
			rig_min[nm] = minf(rig_min.get(nm, a), a)
			rig_max[nm] = maxf(rig_max.get(nm, a), a)
	if site.step_id() == "dig" and site.running and dig_shots == 0 and site.progress > 0.25 and drv.shot_queue.is_empty():
		Clock.set_speed(1)
		drv.shot("fahrzeuge_graben_tag", site.center3() + Vector3(0, 1.0, 0), 30.0, -55.0, 35.0)
		dig_shots = 1
		t_mark = drv.t
	elif dig_shots == 1 and drv.shot_queue.is_empty():
		Clock.minutes = 22.0 * 60.0
		t_mark = drv.t
		dig_shots = 2
	elif dig_shots == 2 and drv.shot_queue.is_empty() and drv.t > t_mark + 4.0:
		drv.shot("fahrzeuge_graben_nacht", site.center3() + Vector3(0, 1.0, 0), 30.0, -55.0, 35.0)
		dig_shots = 3
	elif dig_shots == 3 and drv.shot_queue.is_empty():
		Clock.minutes = 11.0 * 60.0
		Clock.set_speed(drv.speed)
		dig_shots = 4
	log_t += delta
	if log_t > 30.0:
		log_t = 0.0
		drv._dump()
	if site.step_id() == "dig":
		seen_dig = true
	if seen_dig and site.step_id() != "dig":
		if dig_shots in [1, 2, 3]:
			return
		ok(site.terrain.remaining_dig() < 0.05, "Graben ausgehoben (Rest %.2f m³)" % site.terrain.remaining_dig())
		if ex.rig:
			ok(site.stats.spoil_m3 > 0.5, "Aushub in Kipper verladen (%.1f m³)" % site.stats.spoil_m3)
			var jl: Dictionary = ex.meta.get("joint_limits_deg", {})
			for nm in rig_min:
				var l: Array = jl.get(nm, [-180.0, 180.0])
				ok(rig_min[nm] >= float(l[0]) - 0.01 and rig_max[nm] <= float(l[1]) + 0.01,
					"R 938 %s beim Graben %.1f..%.1f° in den Grenzen [%.0f, %.0f]" % [nm, rig_min[nm], rig_max[nm], float(l[0]), float(l[1])])
			ok(not rig_min.is_empty(), "R 938 hat mit dem Gestänge gegraben")
		else:
			print("FAHRZEUGE Hinweis: Ersatzmodell ohne Gestänge – Aushub über den vereinfachten Ablauf")
		_end()


# ------------------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------------------

## Wheels: hub height minus radius = ground; crawler tracks: lowest point of the chain meshes = ground.
func _check_ground(v: Vehicle, where: String) -> void:
	var worst := 0.0
	var n := 0
	for wd in v._wheels:
		var wn: Node3D = wd[0]
		var gap: float = wn.global_position.y - float(wd[1])
		n += 1
		if absf(gap) > absf(worst):
			worst = gap
	for tn in ["track_l", "track_r"]:
		var tr := v.part(tn)
		if tr:
			n += 1
			var lo := _lowest_of(tr)
			if absf(lo) > absf(worst):
				worst = lo
	ok(n > 0 and absf(worst) <= GROUND_TOL, "%s %s: %d Räder/Ketten auf dem Boden (größte Abweichung %.3f m)" % [v.def_id, where, n, worst])


## Lowest point of a machine's wheels or tracks (global y).
func _lowest(v: Vehicle) -> float:
	var lo := 10.0
	for wd in v._wheels:
		lo = minf(lo, (wd[0] as Node3D).global_position.y - float(wd[1]))
	for tn in ["track_l", "track_r"]:
		var tr := v.part(tn)
		if tr:
			lo = minf(lo, _lowest_of(tr))
	return lo


func _lowest_of(node: Node3D, skip_prefix := "") -> float:
	var lo := 10.0
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null or (skip_prefix != "" and _under_prefix(m, node, skip_prefix)):
			continue
		var xf := m.global_transform
		for v in m.mesh.get_faces():   # vertices, not the box: a rotated box reaches far below a tilted ramp
			lo = minf(lo, (xf * v).y)
	return lo


func _under_prefix(n: Node, top: Node, prefix: String) -> bool:
	var p := n
	while p != null and p != top:
		if String(p.name).begins_with(prefix):
			return true
		p = p.get_parent()
	return false


## Lamp markers sit at the lamp glass (within LIGHT_TOL of a model triangle), beacons on the surface below them.
func _check_lights(v: Vehicle) -> void:
	for root in [v.model, v.trailer]:
		if root == null:
			continue
		var r3 := root as Node3D
		var faces := VehicleModels.model_faces(r3)
		var inv := r3.global_transform.affine_inverse()
		var worst := 0.0
		var worst_n := ""
		var count := 0
		for n in r3.find_children("*", "Node3D", true, false):
			var nm := String(n.name)
			if n is MeshInstance3D or not (nm.begins_with("light_") or nm.begins_with("indicator_") or nm.begins_with("worklight_")):
				continue
			var d := _dist_to_faces(faces, inv * (n as Node3D).global_position)
			count += 1
			if d > worst:
				worst = d
				worst_n = nm
		if count > 0:
			ok(worst <= LIGHT_TOL, "%s%s: %d Lichtmarker an der Oberfläche (weitester %s %.3f m)" % [v.def_id, " Anhänger" if root == v.trailer else "", count, worst_n, worst])
	for b in v._beacons:
		var bn: Node3D = b.node
		var root2: Node3D = v.model if v.model.is_ancestor_of(bn) else v.trailer
		if root2 == null:
			continue
		var p: Vector3 = root2.global_transform.affine_inverse() * bn.global_position
		var sy := VehicleModels.surface_y(root2, p.x, p.z, p.y + 0.02, [bn])
		ok(sy > -INF and absf(p.y - sy) <= BEACON_TOL, "%s Rundumleuchte %s sitzt auf (Abstand %.3f m)" % [v.def_id, bn.name, p.y - sy])


## Joint limits from the asset JSON: rest pose inside them and the game's own poses stay within (tipper,
## ramps, rig). Loader: the arm limits lift the cutting edge high and never push it into the ground.
func _check_joints(v: Vehicle) -> void:
	var jl: Dictionary = v.meta.get("joint_limits_deg", {})
	for k in jl:
		var l: Array = jl[k]
		ok(float(l[0]) <= 0.0 and float(l[1]) >= 0.0, "%s Gelenk %s: Ruhelage in [%.0f, %.0f]" % [v.def_id, k, float(l[0]), float(l[1])])
	if v._tipper_body:
		v.set_tip(90.0)
		var lim: Array = jl.get("tipper_body", [0.0, 47.0])
		ok(v.tip_deg <= float(lim[1]) + 0.01, "%s Kippbrücke max %.0f° (Grenze %.0f°)" % [v.def_id, v.tip_deg, float(lim[1])])
		v.set_tip(0.0)
	if v.trailer:
		var tl: Dictionary = v.trailer_meta.get("joint_limits_deg", {})
		for h in v._ramp_hinges:
			var hl: Array = tl.get(String((h[0] as Node3D).name), [-180.0, 180.0])
			var a := rad_to_deg(float(h[2]))
			ok(a >= float(hl[0]) - 0.01 and a <= float(hl[1]) + 0.01, "%s Rampe %s öffnet %.1f° in [%.0f, %.0f]" % [v.def_id, (h[0] as Node3D).name, a, float(hl[0]), float(hl[1])])
		# opened ramp end on the ground (the ramp itself; its rotating beacons sit on the far end and point down)
		if not v._ramp_hinges.is_empty():
			v.set_ramp(4.68, 20.0)
			var lo := 10.0
			for h in v._ramp_hinges:
				lo = minf(lo, _lowest_of(h[0], "beacon_"))
			ok(absf(lo) <= GROUND_TOL, "%s Rampe offen: Ende am Boden (%.3f m, Neigung %.2f°)" % [v.def_id, lo, rad_to_deg(v._trailer_pitch)])
			v.set_ramp(0.0, 0.0)
	var arm := v.part("loader_arm")
	var tip := v.part("bucket_tip")
	if arm and tip and jl.has("loader_arm"):
		var rest := arm.basis
		var hi := 0.0
		var lo2 := 10.0
		for deg in [float(jl.loader_arm[0]), float(jl.loader_arm[1])]:
			arm.basis = rest * Basis(Vector3.RIGHT, deg_to_rad(deg))
			hi = maxf(hi, tip.global_position.y)
			lo2 = minf(lo2, tip.global_position.y)
		arm.basis = rest
		ok(lo2 > -0.15 and hi > 2.0, "%s Hubarm: Schneide %.2f..%.2f m über Boden" % [v.def_id, lo2, hi])


## Smallest distance from p to the triangles (flat array, 3 vertices each), with a cheap box pre-filter.
static func _dist_to_faces(faces: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var lo := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
		var hi := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
		var dx := maxf(maxf(lo.x - p.x, p.x - hi.x), 0.0)
		var dy := maxf(maxf(lo.y - p.y, p.y - hi.y), 0.0)
		var dz := maxf(maxf(lo.z - p.z, p.z - hi.z), 0.0)
		if dx * dx + dy * dy + dz * dz >= best * best:
			continue
		best = minf(best, p.distance_to(_closest_on_tri(p, a, b, c)))
	return best


## Closest point on triangle abc to p (Ericson, Real-Time Collision Detection 5.1.5).
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


# ------------------------------------------------------------------------------------------
# Pictures at HQ
# ------------------------------------------------------------------------------------------

## One picture per call (the driver takes it 8 frames later); true when all are done.
func _hq_shots(tag: String) -> bool:
	var w: World = drv.world
	if shot_i == 0:
		var lc: Vector2 = w.hq_info.lot_center
		drv.shot("fahrzeuge_zentrale_%s" % tag, Vector3(lc.x, 0, lc.y), 70.0, -30.0, 45.0)
		for id in NEW:
			_v(id).light_mode.beacon = "on" if tag == "nacht" else "auto"
			_v(id).beacon_freeze = 1 if tag == "nacht" else -1
		shot_i = 1
		return false
	if shot_i <= NEW.size():
		var v := _v(NEW[shot_i - 1])
		var big := v.trailer != null
		var focus := v.global_position + Vector3(0, 1.6, 0)
		if big:
			focus = v.global_position.lerp(v.trailer.global_position, 0.5) + Vector3(0, 1.4, 0)
		drv.shot("fahrzeuge_%s_%s" % [v.def_id, tag], focus, 26.0 if big else (16.0 if v.def_id != "loader_s550" else 8.0),
			rad_to_deg(v.rotation.y + PI) + 40.0, 28.0)
		shot_i += 1
		return false
	for id in NEW:
		_v(id).light_mode.beacon = "auto"
		_v(id).beacon_freeze = -1
	shot_i = 0
	return true


func _end() -> void:
	Clock.set_speed(1)
	if fails > 0:
		print("E2E FAIL fahrzeuge: %d Fehler" % fails)
		drv.get_tree().quit(1)
		return
	print("E2E OK fahrzeuge")
	drv.get_tree().quit(0)
