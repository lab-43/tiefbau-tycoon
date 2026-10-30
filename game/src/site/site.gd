class_name Site
extends Node3D
## A construction site for one job (pipe repair in a lane). Owns the closure kit, the excavation,
## the crew and the logistics of the vehicles assigned to it. The player triggers the work steps;
## the site runs them, waits for missing vehicles/material and reports its status.

signal changed(site: Site)

const STEPS := [
	{"id": "scout", "title": "Baustelle erkunden"},
	{"id": "closure", "title": "Absperrung aufbauen"},
	{"id": "dig", "title": "Graben ausheben"},
	{"id": "pipe", "title": "Rohr austauschen"},
	{"id": "refill", "title": "Verfüllen & verdichten"},
	{"id": "asphalt", "title": "Asphalt einbauen"},
	{"id": "demob", "title": "Maschinen abziehen"},
	{"id": "teardown", "title": "Absperrung abbauen"},
	{"id": "acceptance", "title": "Abnahme & Abrechnung"},
]
const BUCKET_BANK := 0.48      # m³ bank volume per bite (0.6 m³ bucket)
const BULKING := 1.25          # loose / bank

var world: World
var jm: Node
var job: Job
var lay: SiteLayout
var sid := 0
var phase := 0
var running := false
var retired := false
var auto_continue := false
var status := ""
var progress := 0.0
var sub := ""
var vehicles: Array = []
var spot_of := {}              # Vehicle -> spot id (exc | load | van | stage | lowbed | scout)
var in_place := {}             # Vehicle -> true while parked at its spot
var item_defs: Array = []
var item_nodes: Array = []
var plan: ClosurePlan            # the closure as planned (#9): standard template or the player's design
var plan_confirmed := false      # the player accepted a plan (or started the standard closure)
var build_when_ready := false    # build the accepted plan as soon as the crew is on site
var yellow_lines: Array = []     # PackedVector2Array per yellow marking of the plan
var yellow_fracs: Array = []     # laid fraction 0..1 per marking
var yellow_nodes: Array = []
## All yellow markings at once (debug tools, tests): the least laid fraction; setting it sets all.
var yellow_frac: float:
	get:
		var m := 1.0
		for f in yellow_fracs:
			m = minf(m, float(f))
		return m
	set(v):
		for i in yellow_fracs.size():
			yellow_fracs[i] = v
var _orphans: Array = []         # placed items a changed plan no longer contains (the crew collects them)
var kit_used := false            # the closure kit is out of the crew van (taken at the start, back after teardown)
# changing the closure while the works go on (#21): the work pauses, the crew rebuilds, the work goes on
var rebuild := false             # an accepted plan still has to be built during the works
var _rebuilding := false         # the crew is rebuilding right now
var _pending_plan: ClosurePlan = null   # accepted while a machine cycle ran; applied at the next safe point
var _moving := {}                # Vehicle -> true: re-parking inside the closure after a plan change (#22)
const WORK_STEPS := ["dig", "pipe", "refill", "asphalt", "demob"]
var workers: Array = []
var crew_van: Vehicle
var terrain: SiteTerrain
var pile_mat := ""
var pile_m3 := 0.0
var pile_node: MeshInstance3D
var needs: Array = []          # [{mat, m3, delivered, ordered}]
var traffic_on := false
var pipe_old: Node3D
var pipe_new: Node3D
var marker: Node3D
var spray: MeshInstance3D
var hit: StaticBody3D
var work_light: OmniLight3D
var layer := 0
var placed_since_compact := 0.0
var compacting := false
var stats := {"spoil_m3": 0.0, "jam_s": 0.0}
var _wtasks: Array = []
var _bite: Dictionary = {}
var _bite_done := 0.0
var _tip_busy := {}
var _orders := {}   # tipper -> [need, m3] material that is ordered or on the way
var _polygon := PackedVector2Array()
var _excav: Vehicle
var _fallback_t := 0.0
var _redispatch_t := 0.0


func setup(w: World, manager: Node, j: Job, layout: SiteLayout, id: int) -> void:
	world = w
	jm = manager
	job = j
	lay = layout
	sid = id
	name = "Site_%d" % id
	_polygon = lay.closure_polygon()
	plan = ClosurePlan.from_layout(lay)
	_apply_plan()
	terrain = SiteTerrain.new()
	add_child(terrain)
	var sand_top := -job.depth + 0.05 + job.pipe_d + 0.3
	terrain.setup(lay.trench_center(), lay.trench_dir(), job.length, job.width, job.depth, sand_top)
	_build_pipe_old()
	_build_marker()
	_build_hit()
	work_light = OmniLight3D.new()
	work_light.omni_range = 16.0
	work_light.light_color = Color(1.0, 0.95, 0.85)
	work_light.light_energy = 0.0
	work_light.shadow_enabled = false
	var tc := lay.trench_center()
	work_light.position = gw(tc, 6.0)
	add_child(work_light)
	_set_status("Ein Fahrzeug zur Baustelle schicken, um sie zu erkunden.")


func _build_pipe_old() -> void:
	pipe_old = SiteProps.pipe("old", job.length + 0.8, job.pipe_d)
	add_child(pipe_old)
	var c := lay.trench_center()
	pipe_old.global_transform = Transform3D(Basis(Vector3.UP, SiteLayout.yaw_of(lay.trench_dir())), gw(c, SiteTerrain.Y_ROAD - job.depth + 0.05))


func _build_marker() -> void:
	marker = Node3D.new()
	add_child(marker)
	var c := lay.trench_center()
	marker.position = gw(c, 0.0)
	var lbl := Label3D.new()
	lbl.text = "Auftrag %d" % job.id
	lbl.font = UI.font(700)
	lbl.font_size = 64
	lbl.pixel_size = 0.02
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.modulate = UI.ACCENT
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = false
	lbl.position = Vector3(0, 9.0, 0)
	marker.add_child(lbl)
	var pin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.02
	cm.height = 6.0
	pin.mesh = cm
	pin.position = Vector3(0, 4.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = UI.ACCENT
	m.emission_enabled = true
	m.emission = UI.ACCENT
	m.emission_energy_multiplier = 0.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pin.material_override = m
	pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(pin)


func _build_hit() -> void:
	hit = StaticBody3D.new()
	hit.collision_layer = 0b10
	hit.collision_mask = 0
	hit.set_meta("owner_obj", self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var length := lay.s_taper1 - lay.s0 + 6.0
	var mid := (lay.s0 + lay.s_taper1) * 0.5
	var p := lay.lane_pt(mid, 0.3)
	# tall enough for the slope along the site (#8)
	var rise := absf(Terrain.at(lay.lane_pt(lay.s0, 0.3)) - Terrain.at(lay.lane_pt(lay.s_taper1, 0.3)))
	bs.size = Vector3(lay.lw + 2.0, 0.6 + rise, length)
	cs.shape = bs
	hit.position = gw(p, 0.3)
	hit.rotation.y = SiteLayout.yaw_of(lay.lane_dir(mid))
	hit.add_child(cs)
	add_child(hit)
	# marker pin is clickable too
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(3.0, 10.0, 3.0)
	cs2.shape = bs2
	var tc := lay.trench_center()
	var pin_body := StaticBody3D.new()
	pin_body.collision_layer = 0b10
	pin_body.collision_mask = 0
	pin_body.set_meta("owner_obj", self)
	pin_body.position = gw(tc, 5.0)
	pin_body.add_child(cs2)
	add_child(pin_body)


func set_selected(_v: bool) -> void:
	pass


func contains(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, _polygon)


## World point at map position p, y metres above the ground (#8: ground heights; 0 = road base level).
static func gw(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, Terrain.at(p) + y, p.y)


func center3() -> Vector3:
	var c := lay.trench_center()
	return gw(c, 0.0)


func step_id() -> String:
	return STEPS[mini(phase, STEPS.size() - 1)].id


func _set_status(t: String) -> void:
	if t != status:
		status = t
		changed.emit(self)
		Events.site_changed.emit(self)


func _complete(id: String) -> void:
	if step_id() != id:
		return
	running = false
	sub = ""
	progress = 0.0
	phase += 1
	Events.ok("%s: %s abgeschlossen" % [job.short_title(), STEPS[phase - 1].title])
	_after_phase_change()
	changed.emit(self)
	Events.site_changed.emit(self)
	Events.job_changed.emit(job)


func _after_phase_change() -> void:
	match step_id():
		"closure":
			_set_status("Kolonnenbus mit Absperrmaterial schicken und Absperrung aufbauen.")
		"dig":
			_set_status("Bagger in Position bringen, Kipper für den Aushub schicken, dann Graben starten.")
		"pipe":
			_set_status("Pritschen-LKW mit neuem Rohr schicken, dann Rohr tauschen.")
		"refill":
			_set_status("Sand und Schotter mit dem Kipper anliefern, dann verfüllen.")
		"asphalt":
			_set_status("Asphalt anliefern, dann einbauen.")
		"demob":
			_set_status("Bagger, Kipper und Pritsche zur Zentrale schicken.")
			_check_demob()
		"teardown":
			_set_status("Absperrung abbauen.")
		"acceptance":
			_do_acceptance()
	_redispatch_waiting()


# ------------------------------------------------------------------------------------------
# UI: steps and actions
# ------------------------------------------------------------------------------------------

func steps_view() -> Array:
	var out: Array = []
	for i in STEPS.size():
		var st := "todo"
		if i < phase:
			st = "done"
		elif i == phase:
			st = "active"
		out.append({"title": STEPS[i].title, "state": st, "running": running and i == phase})
	return out


func actions() -> Array:
	var out: Array = []
	match step_id():
		"closure":
			if can_edit_plan() == "":
				out.append(_action("plan", "Plan ändern" if plan_confirmed else "Absperrung planen", ""))
			out.append(_action("closure", "Absperrung aufbauen" if plan_confirmed else "Standard-Absperrung aufbauen", _can_closure()))
		"dig":
			out.append(_action("dig", "Graben ausheben", _can_dig()))
		"pipe":
			out.append(_action("pipe", "Rohr austauschen", _can_pipe()))
		"refill":
			out.append(_action("refill", "Verfüllen & verdichten", _can_refill()))
		"asphalt":
			out.append(_action("asphalt", "Asphalt einbauen", _can_asphalt()))
		"demob":
			out.append(_action("demob", "Maschinen zur Zentrale", "" if _machines_on_site().size() > 0 else "Keine Maschinen vor Ort"))
		"teardown":
			out.append(_action("teardown", "Absperrung abbauen", _can_teardown()))
	if step_id() in WORK_STEPS:
		# #21: the closure can be changed during the works (also while a step runs: it pauses)
		var why := can_edit_plan()
		out.append({"id": "plan", "label": "Absperrung ändern", "enabled": why == "", "reason": why})
	return out


func _action(id: String, label: String, block: String) -> Dictionary:
	if block == "" and id in WORK_STEPS and work_paused():
		block = "Die Absperrung wird umgebaut"
	return {"id": id, "label": label, "enabled": block == "" and not running, "reason": block if not running else "läuft…"}


func do_action(id: String) -> void:
	if running:
		return
	if id in WORK_STEPS and work_paused():
		Events.warn("Die Absperrung wird umgebaut")
		return
	var block := ""
	match id:
		"closure":
			block = _can_closure()
			if block == "":
				_start_closure()
		"dig":
			block = _can_dig()
			if block == "":
				_start_dig()
		"pipe":
			block = _can_pipe()
			if block == "":
				_start_pipe()
		"refill":
			block = _can_refill()
			if block == "":
				_start_refill()
		"asphalt":
			block = _can_asphalt()
			if block == "":
				_start_asphalt()
		"demob":
			_demob_send_home(true)
		"teardown":
			block = _can_teardown()
			if block == "":
				_start_teardown()
	if block != "":
		Events.warn(block)
	changed.emit(self)


# ------------------------------------------------------------------------------------------
# Vehicles: assignment, spots, routing
# ------------------------------------------------------------------------------------------

func role(v: Vehicle) -> String:
	if v.has_ability("crew"):
		return "crew"
	if v.has_ability("dig"):
		return "dig"
	if v.has_ability("bulk"):
		return "bulk"
	if v.has_ability("pipes"):
		return "pipes"
	if v.has_ability("lowbed"):
		return "lowbed"
	return "other"


func send_vehicle(v: Vehicle) -> void:
	if not v.can_drive():
		return
	if v.site != null and v.site != self:
		v.site.release_vehicle(v)
	if v.state in ["driving", "waiting"]:
		v.stop_now()
	if not vehicles.has(v):
		vehicles.append(v)
	v.site = self
	_dispatch(v)
	changed.emit(self)


## After loading a save: re-attach a vehicle that worked here.
func restore_vehicle(v: Vehicle, spot: String, was_in_place: bool) -> void:
	if not vehicles.has(v):
		vehicles.append(v)
	v.site = self
	if was_in_place and spot != "":
		spot_of[v] = spot
		in_place[v] = true
		v.status_text = "Baustelle %s" % job.short_title()
		if spot == "van":
			crew_van = v
			_ensure_workers()
		elif spot in ["exc", "load"]:
			v.state = "working"
			if v.has_ability("dig"):
				_excav = v
				_connect_rig(v)
			elif role(v) == "bulk":
				_tipper_next.call_deferred(v)
	else:
		_dispatch.call_deferred(v)


func release_vehicle(v: Vehicle) -> void:
	if v == crew_van:
		_crew_board()
		crew_van = null
	vehicles.erase(v)
	_moving.erase(v)
	spot_of.erase(v)
	in_place.erase(v)
	_tip_busy.erase(v)
	_cancel_order(v)
	if v.site == self:
		v.site = null
	v.working = false
	if v.rig and v.rig.cycle_event.is_connected(_on_rig_event):
		v.rig.cycle_event.disconnect(_on_rig_event)
	if v == _excav:
		_excav = null
		if running and step_id() in ["dig", "pipe", "refill", "asphalt"]:
			running = false
			_set_status("Bagger abgezogen – Arbeit unterbrochen.")
	if step_id() == "demob":
		_check_demob.call_deferred()
	_redispatch_waiting.call_deferred()
	changed.emit(self)


## Called when a vehicle that is working here drives off on its own command.
func on_vehicle_leaving(v: Vehicle) -> void:
	in_place.erase(v)
	if _moving.has(v) and v.state != "driving":
		return   # only moving to its new spot inside the closure (#22)
	_moving.erase(v)   # sent away (also while it was moving to its new spot)
	spot_of.erase(v)
	v.working = false
	if v == crew_van:
		_crew_board()
	if v == _excav:
		if v.rig and v.rig.cycle_event.is_connected(_on_rig_event):
			v.rig.cycle_event.disconnect(_on_rig_event)
		if v.rig:
			v.rig.travel_pose()
		_excav = null
		if running and step_id() in ["dig", "pipe", "refill", "asphalt"]:
			running = false
			_set_status("Bagger abgezogen – Arbeit unterbrochen.")
	changed.emit(self)


func on_vehicle_event(_v: Vehicle, _ev: String) -> void:
	pass


func occupant(spot: String) -> Vehicle:
	for v in spot_of:
		if spot_of[v] == spot and is_instance_valid(v):
			return v
	return null


func _stage_index(v: Vehicle) -> int:
	var i := 0
	for o in spot_of:
		if o != v and spot_of[o] == "stage":
			i += 1
	return i


func _dispatch(v: Vehicle) -> void:
	if v.state == "loading" or v.carried_by != null:
		return
	var r := role(v)
	if r == "crew":
		_go_van_spot(v)
		return
	if r == "lowbed":
		_dispatch_lowbed(v)
		return
	if r == "pipes":
		_flatbed_next(v)
		return
	if phase == 0:
		_go_stage(v)
		return
	match r:
		"dig":
			if phase >= 6:
				_return_to_hq(v)
			elif traffic_on and (occupant("exc") == null or occupant("exc") == v) and (occupant("load") == null or step_id() == "closure"):
				_go_slot(v, "exc", lay.s_exc, lay.exc_lat)
			else:
				_go_stage(v)
		"bulk":
			_tipper_next(v)
		_:
			_go_stage(v)


func _pipe_swapped() -> bool:
	return phase > 3


## Flatbed: fetch a new pipe at HQ if needed, wait near the site, reverse in for the pipe swap.
func _flatbed_next(v: Vehicle) -> void:
	if v.state in ["loading", "driving", "waiting"]:
		return
	if _pipe_swapped():
		if v.cargo.pipes_old > 0 or not v.at_hq():
			_return_to_hq(v)
		return
	if v.cargo.pipes_new <= 0:
		if v.at_hq():
			_load_pipes_at_hq(v)
		else:
			v._drive_to_hq(func(veh):
				if veh.site == self:
					_load_pipes_at_hq(veh))
			spot_of.erase(v)
			in_place.erase(v)
			v.status_text = "Holt neues Rohr in der Zentrale"
		return
	if phase == 0:
		_go_stage(v)
	elif step_id() == "pipe" and traffic_on and occupant("load") == null:
		_go_slot(v, "load", lay.load_s(v.rear_ext), lay.load_lat)
	else:
		_go_stage(v)


func _go_van_spot(v: Vehicle) -> void:
	var vp := lay.van_pose()
	crew_van = v
	var sp := lay.van_spot()   # on K, or on a lane next to it if the street is short (#33)
	var appr: float = sp.appr
	v.drive_plan({"key": sp.key, "s": float(sp.s) - appr}, job.short_title(), [v.pull_over_piece(sp.key, float(sp.s) - appr, SiteLayout.CURB, appr)], func(veh):
		veh.place(gw(vp.pos, 0.0), vp.yaw)
		_arrived(veh, "van"))
	_reserve(v, "van")


func _reserve(v: Vehicle, spot: String) -> void:
	spot_of[v] = spot
	in_place.erase(v)


func _go_stage(v: Vehicle) -> void:
	if spot_of.get(v, "") == "stage" and in_place.has(v):
		return
	# already parked at the curb behind the site (e.g. just unloaded from the low-loader): wait right there
	if v.state == "parked" and _behind_site(v) and v.pos2().distance_to(lay.lane_pt(lay.stage_s(0), SiteLayout.CURB)) < 70.0:
		var r: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], v.pos2())
		if r[0] > 1.2:
			_reserve(v, "stage")
			_arrived(v, "stage")
			return
	var sp := lay.stage_spot(_stage_index(v), v.rear_ext)
	if sp.is_empty():
		# no free kerb near the site (#33): wait in the HQ until the site calls the vehicle
		_reserve(v, "stage")
		if v.at_hq() and v.state == "parked":
			_arrived(v, "stage")
			v.status_text = "Wartet in der Zentrale auf %s" % job.short_title()
		elif not v._drive_to_hq(func(veh):
				if veh.site == self and spot_of.get(veh, "") == "stage":
					_arrived(veh, "stage")
					veh.status_text = "Wartet in der Zentrale auf %s" % job.short_title()):
			spot_of.erase(v)
		return
	var appr: float = sp.appr
	if v.drive_plan({"key": sp.key, "s": float(sp.s) - appr}, job.short_title() + " (wartet)", [v.pull_over_piece(sp.key, float(sp.s) - appr, SiteLayout.CURB, appr)], func(veh): _arrived(veh, "stage")):
		_reserve(v, "stage")


## Lateral offset along a manoeuvre that ends at (sb, lb): from la it blends smoothly over the last
## `blend` m before sb (the spots of #22 may lie off the lane centre).
static func _lat_blend(sa: float, la: float, sb: float, lb: float, blend := 10.0) -> Callable:
	var span := maxf(0.5, minf(blend, absf(sb - sa)))
	return func(s: float) -> float:
		var t := clampf(1.0 - absf(sb - s) / span, 0.0, 1.0)
		return lerpf(la, lb, t * t * (3.0 - 2.0 * t))


## Tail entry: road to a stop point behind the closure, then reverse along the closed lane into the slot.
func _go_slot(v: Vehicle, spot: String, slot_s: float, slot_lat := 0.0) -> void:
	var obs_s0 := lay.s_det1 - 4.0
	# already waiting at the curb behind the site → reverse directly from there
	if v.state == "parked" and v.pos2().distance_to(lay.lane_pt(lay.stage_s(0), SiteLayout.CURB)) < 60.0 and _behind_site(v):
		var p0 := v.pos2()
		var s_here: float = Geo.closest_on_polyline(lay._g[0], lay._g[1], p0)[1]
		var join_s := s_here - 7.0
		var a := HQ.bezier(p0, p0 - v.forward2() * 4.0, lay.lane_pt(join_s + 3.0), lay.lane_pt(join_s))
		var b := lay.lane_poly(join_s, slot_s, _lat_blend(join_s, 0.0, slot_s, slot_lat))
		var path := HQ.join(a, b)
		var pc := Router.poly_piece(path, 1.8, true, "rev")
		if v.drive_plan({}, job.short_title(), [], func(veh): _slot_arrived(veh, spot, slot_s, slot_lat), [pc], {"key": lay.key, "s0": obs_s0, "s1": s_here + 6.0}):
			_reserve(v, spot)
		return
	var s_stop := minf(lay.s_det1 + 3.0 + v.front_ext, lay.len_k - 1.0)
	var rev_pts := lay.lane_poly(s_stop, slot_s, _lat_blend(s_stop, 0.0, slot_s, slot_lat))
	var rev := Router.poly_piece(rev_pts, 1.8, true, "rev")
	rev["cusp"] = true
	var ok: bool = v.drive_plan({"key": lay.key, "s": s_stop}, job.short_title(), [rev], func(veh): _slot_arrived(veh, spot, slot_s, slot_lat))
	if ok:
		_reserve(v, spot)
	if ok and v.agent:
		# block traffic behind once the vehicle is on the last lane piece before reversing
		for i in range(v.agent.route.size() - 1, -1, -1):
			var pc2: Dictionary = v.agent.route[i]
			if pc2.t == Agent.LANE and pc2.key == lay.key:
				pc2["obs"] = {"key": lay.key, "s0": obs_s0, "s1": s_stop + 3.0}
				pc2.tag = "obs"
				break


func _behind_site(v: Vehicle) -> bool:
	var r: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], v.pos2())
	# a machine backed off the low-loader stands with its rear in the tail taper (#24): past the work
	# zone is enough, otherwise it drives around the block (1.2 km at walking pace for the R 938)
	if r[1] > lay.tail_s() - lay.taper_out and r[0] < 6.0:
		return true
	if lay.post_key >= 0:
		var gp: Array = world.net.lane_geo[lay.post_key]
		var rp: Array = Geo.closest_on_polyline(gp[0], gp[1], v.pos2())
		return rp[0] < 6.0 and rp[1] < 45.0 and r[1] > lay.len_k - 1.0
	return false


func _slot_arrived(v: Vehicle, spot: String, slot_s: float, slot_lat := 0.0) -> void:
	_moving.erase(v)
	var p := lay.pose(slot_s, slot_lat)
	v.place(gw(p.pos, 0.0), p.yaw)
	_arrived(v, spot)


## Where a vehicle at one of the machine spots belongs under the plan in force: {s, lat}.
func _spot_target(v: Vehicle, spot: String) -> Dictionary:
	if spot == "exc":
		return {"s": lay.s_exc, "lat": lay.exc_lat}
	if role(v) == "bulk" and phase > 2:
		return {"s": lay.dump_s(v.rear_ext), "lat": lay.pile_lat}
	return {"s": lay.load_s(v.rear_ext), "lat": lay.load_lat}


## A changed plan moved this machine's spot (#22): it drives there directly inside the closure,
## forwards or in reverse, without leaving the site (the work step stays as it is).
func _repark(v: Vehicle, spot: String) -> void:
	var tgt := _spot_target(v, spot)
	var lc := lay.lane_coords(v.pos2())
	var t_s: float = tgt.s
	var t_lat: float = tgt.lat
	if Vector2(lc.x, lc.y).distance_to(Vector2(t_s, t_lat)) < 0.3:
		return
	var rev: bool = t_s < lc.x
	var path := lay.lane_poly(lc.x, t_s, _lat_blend(lc.x, lc.y, t_s, t_lat, 1.0e6), 0.5)
	path[0] = v.pos2()
	var pc := Router.poly_piece(path, 1.5, rev, "rev" if rev else "")
	_moving[v] = true
	if not v.drive_plan({}, job.short_title(), [], func(veh): _slot_arrived(veh, spot, t_s, t_lat), [pc]):
		_moving.erase(v)
	else:
		spot_of[v] = spot


func _arrived(v: Vehicle, spot: String) -> void:
	if not vehicles.has(v):
		return
	in_place[v] = true
	spot_of[v] = spot
	v.status_text = "Baustelle %s" % job.short_title()
	if spot in ["exc", "load"]:
		v.state = "working"
	if v.has_ability("dig") and spot == "exc":
		_excav = v
		if v.rig:
			v.rig.travel_pose()
		_redispatch_waiting.call_deferred()
	# scouting
	if step_id() == "scout" and v.pos2().distance_to(lay.trench_center()) < 120.0:
		_scouted()
	if spot == "van":
		_ensure_workers()
	if role(v) == "bulk":
		_tipper_arrived(v)
	if role(v) == "lowbed":
		_lowbed_arrived(v)
	Events.vehicle_changed.emit(v)
	changed.emit(self)
	if auto_continue:
		_auto_step.call_deferred()


func exit_plan(v: Vehicle) -> Dictionary:
	var spot: String = spot_of.get(v, "")
	if spot == "van" and v.pos2().distance_to(lay.van_pose().pos as Vector2) < 6.0:
		# pull out into the lane before the detour starts (or, behind the site or on a lane next to it,
		# before that lane ends, #33)
		var vs := lay.van_spot()
		var vk: int = vs.key
		var vsv: float = vs.s
		var sj := minf(vsv + 9.0, lay.s_det0 - 1.5)
		if vk != lay.key or vsv > lay.s_det1:
			sj = minf(vsv + 9.0, lay.kerb_len(vk) - 0.5)
		var a := v.pos2()
		var join := HQ.bezier(a, a + v.forward2() * 3.0, lay.kerb_pt(vk, sj - 3.0), lay.kerb_pt(vk, sj))
		in_place.erase(v)
		spot_of.erase(v)
		var o0 := vsv - 28.0
		if vk == lay.key and vsv > lay.s_det1:
			o0 = maxf(o0, lay.s_det1 + 0.5)
		return {"key": vk, "s": sj, "pre": [Router.poly_piece(join, 3.0)], "obs": {"key": vk, "s0": o0, "s1": sj + 2.0}}
	if not (spot in ["exc", "load"]) or not contains(v.pos2()):
		return {}
	var r: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], v.pos2())
	var s_here: float = r[1]
	# anything parked between this vehicle and the tail blocks the way
	for o in spot_of:
		if o == v or not is_instance_valid(o) or not contains(o.pos2()) or o.state == "driving":
			continue
		if spot_of.get(o, "") in ["exc", "load"]:
			var ro: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], o.pos2())
			if ro[1] > s_here + 1.0:
				Events.warn("%s: Weg blockiert durch %s" % [v.vname, o.vname])
				return {"blocked": true}
	var s_exit := maxf(lay.s_det1 + 3.0 + v.rear_ext, s_here + 6.0)
	s_exit = minf(s_exit, lay.len_k - 1.0)
	var lat_here: float = lay.lane_coords(v.pos2()).y
	var pts := lay.lane_poly(s_here, s_exit, _lat_blend(s_exit, 0.0, s_here, lat_here))
	pts[0] = v.pos2()
	var pc := Router.poly_piece(pts, 3.0)
	in_place.erase(v)
	spot_of.erase(v)
	v.state = "parked"
	return {"key": lay.key, "s": s_exit, "pre": [pc], "obs": {"key": lay.key, "s0": lay.s_det1 - 4.0, "s1": s_exit + 4.0}}


func _redispatch_waiting() -> void:
	for v in vehicles.duplicate():
		if not is_instance_valid(v):
			continue
		var sp: String = spot_of.get(v, "")
		if sp == "load" and in_place.has(v) and role(v) == "bulk" and step_id() == "dig" and _excavator() == null and not _tip_busy.has(v):
			_go_stage(v)
			continue
		if sp == "lowbed" and in_place.has(v) and v.state == "parked" and v.cargo.machine == null and phase >= 6 and _excavator() != null and v.can_carry(_excavator()):
			_lowbed_arrived(v)
			continue
		if spot_of.get(v, "") == "stage" and in_place.has(v) and v.state == "parked":
			var r := role(v)
			if r == "dig" and phase < 6 and traffic_on and occupant("exc") == null and occupant("load") == null:
				_go_slot(v, "exc", lay.s_exc, lay.exc_lat)
			elif r == "pipes":
				if (step_id() == "pipe" and traffic_on and occupant("load") == null) or v.cargo.pipes_new <= 0 or _pipe_swapped():
					_flatbed_next(v)
			elif r == "bulk" and v.auto_shuttle:
				_tipper_next(v)


func _machines_on_site() -> Array:
	return vehicles.filter(func(v): return is_instance_valid(v) and role(v) in ["dig", "bulk", "pipes", "lowbed"])


func _check_demob() -> void:
	if step_id() != "demob":
		return
	for v in world.fleet.vehicles:
		if not is_instance_valid(v) or v == crew_van or v.carried_by != null:
			continue
		var inside: bool = contains(v.pos2()) and (lay.van_pose().pos as Vector2).distance_to(v.pos2()) > 8.0
		if inside or (v.site == self and spot_of.get(v, "") in ["exc", "load"]):
			_set_status("Noch Fahrzeuge in der Absperrung: %s" % v.vname)
			return
	_complete("demob")


# ------------------------------------------------------------------------------------------
# Crew
# ------------------------------------------------------------------------------------------

func crew_present() -> bool:
	return crew_van != null and in_place.has(crew_van) and spot_of.get(crew_van, "") == "van" and (crew_van.crew_aboard > 0 or not workers.is_empty())


func _ensure_workers() -> void:
	if crew_van == null or not workers.is_empty() or crew_van.crew_aboard <= 0:
		return
	var n := crew_van.crew_aboard
	crew_van.crew_aboard = 0
	var cp := lay.crew_point()
	for i in n:
		var w := Worker.new()
		add_child(w)
		w.position = gw(Vector2(cp.x + i * 0.7 - 0.7, cp.y), 0.05)
		w.rotation.y = SiteLayout.yaw_of(lay.van_dir())
		workers.append(w)
	crew_van.light_mode.hazard = true


func _crew_board() -> void:
	if crew_van == null:
		return
	if not workers.is_empty():
		crew_van.crew_aboard += workers.size()
		for w in workers:
			if w.carry:
				w.carry.queue_free()
			w.queue_free()
		workers.clear()
		_wtasks.clear()
		if running and step_id() in ["closure", "teardown", "pipe", "refill", "asphalt"]:
			running = false
			_set_status("Kolonne abgezogen – Arbeit unterbrochen.")
	crew_van.light_mode.hazard = false
	compacting = false


func _idle_workers() -> Array:
	return workers.filter(func(w): return not w.busy)


func _worker_home(w: Worker, i: int) -> void:
	var cp := lay.crew_point()
	var d := lay.van_dir()
	var p := cp + d * (i * 0.8 - 0.8)
	w.walk_to(gw(p, 0.05))


# ------------------------------------------------------------------------------------------
# Scouting
# ------------------------------------------------------------------------------------------

func _scouted() -> void:
	_build_spray()
	job.scouted = true
	_complete("scout")


func _build_spray() -> void:
	if spray:
		return
	var c := lay.trench_center()
	var d := lay.trench_dir()
	var r := Geo.right_of(d)
	var hl := job.length * 0.5 + 0.1
	var hw := job.width * 0.5 + 0.1
	var corners := [c - d * hl - r * hw, c + d * hl - r * hw, c + d * hl + r * hw, c - d * hl + r * hw, c - d * hl - r * hw]
	var pts := PackedVector2Array()
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var segs := int(a.distance_to(b) / 0.5)
		for k in segs:
			pts.append(a.lerp(b, float(k) / segs))
	pts.append(corners[4])
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.35, 0.05)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.3, 0.0)
	m.emission_energy_multiplier = 0.25
	m.roughness = 0.9
	spray = SiteProps.ribbon(pts, 0.07, 0.066, m)
	add_child(spray)


# ------------------------------------------------------------------------------------------
# Closure setup / teardown (crew tasks)
# ------------------------------------------------------------------------------------------

func _can_closure() -> String:
	if item_defs.is_empty() and yellow_lines.is_empty():
		return "Der Plan ist leer"
	if not crew_present():
		return "Kolonnenbus ist nicht vor Ort"
	if crew_van.cargo.barriers <= 0 and not kit_used:
		return "Kein Absperrmaterial im Kolonnenbus"
	return ""


func _placed_count() -> int:
	var n := 0
	for nd in item_nodes:
		if nd != null:
			n += 1
	return n


func _start_closure() -> void:
	_ensure_workers()
	if not kit_used and crew_van.cargo.barriers > 0:
		crew_van.cargo.barriers -= 1
		kit_used = true
	plan_confirmed = true
	build_when_ready = false
	running = true
	_wtasks.clear()
	for o in _orphans:
		if is_instance_valid(o):
			_wtasks.append({"type": "collect", "node": o})
	for t in _build_sequence():
		if t.type == "place" and item_nodes[t.i] != null:
			continue
		if t.type == "yellow_on" and float(yellow_fracs[t.l]) >= 1.0:
			continue
		_wtasks.append(t)
	_set_status("Kolonne baut die Absperrung auf …")


## Build order: the items in plan order; the yellow markings before the pit fences (standard
## closure) or at the end (player plan). Teardown runs it backwards.
func _build_sequence() -> Array:
	var seq: Array = []
	var lines_at := item_defs.size()
	if not plan.custom:
		for i in item_defs.size():
			if item_defs[i].group == "pit":
				lines_at = i
				break
	for i in item_defs.size() + 1:
		if i == lines_at:
			for l in yellow_lines.size():
				seq.append({"type": "yellow_on", "l": l})
		if i < item_defs.size():
			seq.append({"type": "place", "i": i})
	return seq


func _start_teardown() -> void:
	_ensure_workers()
	running = true
	_wtasks.clear()
	var seq := _build_sequence()
	seq.reverse()
	for t in seq:
		if t.type == "place" and item_nodes[t.i] != null:
			_wtasks.append({"type": "remove", "i": t.i})
		elif t.type == "yellow_on" and float(yellow_fracs[t.l]) > 0.0:
			_wtasks.append({"type": "yellow_off", "l": t.l})
	for o in _orphans:
		if is_instance_valid(o):
			_wtasks.append({"type": "collect", "node": o})
	_set_status("Kolonne baut die Absperrung ab …")


func _can_teardown() -> String:
	if not crew_present():
		return "Kolonnenbus ist nicht vor Ort"
	for v in vehicles:
		if is_instance_valid(v) and spot_of.get(v, "") in ["exc", "load"]:
			return "Erst alle Maschinen abziehen"
	return ""


# ------------------------------------------------------------------------------------------
# Closure plan (#9): designed by the player in the ClosureDesigner
# ------------------------------------------------------------------------------------------

## Empty if the plan can be changed now, else the reason.
func can_edit_plan() -> String:
	var st := step_id()
	if st == "closure":
		return "Die Kolonne baut gerade auf" if running else ""
	if st in WORK_STEPS:
		return "Die Absperrung wird gerade umgebaut" if _rebuilding or _pending_plan != null else ""
	if st == "scout":
		return "Erst die Baustelle erkunden"
	return "Die Absperrung wird abgebaut"


## The work is paused for a changed closure (#21): no new machine cycles or crew jobs of the step.
func work_paused() -> bool:
	return step_id() in WORK_STEPS and (rebuild or _pending_plan != null)


## A changed plan can be applied: no excavator cycle, compaction pass or crew job of the step is
## under way. The pipe swap (crew in the trench, pipe on the hook) is finished first.
func _safe_for_rebuild() -> bool:
	if not running:
		return true
	if step_id() == "pipe":
		return false
	if compacting:
		return false
	if _excav and is_instance_valid(_excav) and _excav.rig and _excav.rig.busy:
		return false
	for w in workers:
		if w.busy:
			return false
	return true


func _start_rebuild() -> void:
	_rebuilding = true
	_ensure_workers()
	_wtasks.clear()
	for o in _orphans:
		if is_instance_valid(o):
			_wtasks.append({"type": "collect", "node": o})
	for t in _build_sequence():
		if t.type == "place" and item_nodes[t.i] != null:
			continue
		if t.type == "yellow_on" and float(yellow_fracs[t.l]) >= 1.0:
			continue
		_wtasks.append(t)
	_set_status("Arbeit pausiert – die Kolonne baut die Absperrung um …")
	changed.emit(self)


func _finish_rebuild() -> void:
	_rebuilding = false
	rebuild = false
	for i in workers.size():
		_worker_home(workers[i], i)
	if not traffic_on:
		_traffic_activate()
	_set_status("Absperrung umgebaut – die Arbeit geht weiter." if running else "Absperrung umgebaut.")
	if not running:
		_after_phase_change()
	Events.ok("%s: Absperrung umgebaut" % job.short_title())
	changed.emit(self)
	Events.site_changed.emit(self)


func _apply_plan() -> void:
	item_defs = plan.defs(lay)
	item_nodes.clear()
	item_nodes.resize(item_defs.size())
	yellow_lines = plan.lines.duplicate()
	yellow_fracs.clear()
	for _l in yellow_lines:
		yellow_fracs.append(0.0)
	lay.apply_extent(plan.extent(lay))
	_polygon = lay.closure_polygon()
	_update_yellow()


## Accepts a new plan. Items that already stand and are still planned stay; the crew collects the
## others before it builds. build: the crew starts as soon as it is on site.
func set_plan(p: ClosurePlan, build := true) -> void:
	if can_edit_plan() != "":
		return
	var works := step_id() in WORK_STEPS
	if works and not _safe_for_rebuild():
		# a machine cycle or the pipe swap is under way: the work pauses at its next safe point
		_pending_plan = p
		_set_status("Neuer Absperrplan – die Arbeit pausiert, sobald der laufende Arbeitsgang fertig ist.")
		changed.emit(self)
		Events.site_changed.emit(self)
		return
	var ext_new: Dictionary = p.extent(lay)
	var van_moves: bool = crew_van != null and is_instance_valid(crew_van) and spot_of.get(crew_van, "") == "van" \
		and (absf(float(ext_new.van) - lay.s_van) > 0.5 or (float(ext_new.van) < 0.0 and \
		lay.plan_kerb(ext_new).van.get("rear", -1.0) != lay.kerb.van.get("rear", -1.0)))
	var van_driving := false
	if van_moves:
		# the crew gets in, the van reverses along the curb to its new spot ahead of the taper
		_crew_board()
		van_driving = _reverse_van_to(float(ext_new.van))
	var old_defs := item_defs
	var old_nodes := item_nodes.duplicate()
	var old_lines := yellow_lines
	var old_fracs := yellow_fracs.duplicate()
	plan = p
	_apply_plan()
	var used := {}
	for i in old_defs.size():
		var n: Node3D = old_nodes[i]
		if n == null:
			continue
		var od: Dictionary = old_defs[i]
		var hit := -1
		for j in item_defs.size():
			var nd: Dictionary = item_defs[j]
			if not used.has(j) and nd.kind == od.kind and (nd.pos as Vector2).distance_to(od.pos) < 0.05 \
					and absf(angle_difference(float(nd.yaw), float(od.yaw))) < 0.03:
				hit = j
				break
		if hit >= 0:
			used[hit] = true
			item_nodes[hit] = n
			if not is_equal_approx(float(od.get("phase", 0.0)), float(item_defs[hit].get("phase", 0.0))):
				SiteProps.set_phase(n, float(item_defs[hit].phase))
		else:
			_orphans.append(n)
	for l in yellow_lines.size():
		for k in old_lines.size():
			if old_lines[k] == yellow_lines[l]:
				yellow_fracs[l] = old_fracs[k]
	_update_yellow()
	# machines already at their spots move to the new ones (#22)
	for mv in in_place.keys():
		if is_instance_valid(mv) and spot_of.get(mv, "") in ["exc", "load"] and not _tip_busy.has(mv) and mv.state != "loading":
			_repark(mv, spot_of[mv])
	# re-register the detour with the new geometry; a running detour stays (old items still stand)
	var was_on := traffic_on
	if traffic_on:
		_traffic_deactivate()
	if was_on or _traffic_should_be_on():
		_traffic_activate()
	if van_moves and not van_driving and is_instance_valid(crew_van):
		var vp := lay.van_pose()
		crew_van.place(gw(vp.pos, 0.0), vp.yaw)
		_arrived(crew_van, "van")
	plan_confirmed = true
	build_when_ready = build and not works
	if works:
		rebuild = true
		if crew_present() and not van_moves:
			_set_status("Plan übernommen – die Arbeit pausiert, die Kolonne baut um.")
		elif van_moves:
			_set_status("Plan übernommen – die Arbeit pausiert, der Kolonnenbus parkt um.")
		else:
			_set_status("Plan übernommen – die Arbeit pausiert. Kolonnenbus schicken, dann baut die Kolonne um.")
	elif crew_present() and not van_moves:
		_set_status("Plan übernommen – die Kolonne baut ihn auf.")
	elif van_moves:
		_set_status("Plan übernommen – der Kolonnenbus parkt vor der neuen Verschwenkung um.")
	else:
		_set_status("Plan übernommen. Kolonnenbus schicken, dann baut die Kolonne ihn auf.")
	changed.emit(self)
	Events.site_changed.emit(self)


## The new van spot lies behind the van on the same curb: reverse there (traffic waits behind a
## safety zone) instead of driving around the block.
func _reverse_van_to(new_s: float) -> bool:
	var v := crew_van
	var r: Array = Geo.closest_on_polyline(lay._g[0], lay._g[1], v.pos2())
	var s_here: float = r[1]
	if new_s < 0.0 or lay.s_van < 0.0 or new_s > s_here - 0.5 or (s_here > lay.s_det1) != (new_s > lay.s_det1):
		return false   # to or from a lane next to K or across the closure (#33), or forwards: placed directly
	var path := lay.lane_poly(s_here, new_s, func(_s): return SiteLayout.CURB, 1.0)
	path[0] = v.pos2()
	var pc := Router.poly_piece(path, 1.8, true, "rev")
	var ok := v.drive_plan({}, job.short_title(), [], func(veh):
		var vp := lay.van_pose()
		veh.place(gw(vp.pos, 0.0), vp.yaw)
		_arrived(veh, "van"), [pc], {"key": lay.key, "s0": new_s - 8.0, "s1": s_here + 6.0})
	if ok:
		_reserve(v, "van")
	return ok


## Traffic is shifted while an item stands in K; plans without any item in K still close the lane
## while the work runs (dig … demob) and until their teardown is finished.
func _traffic_should_be_on() -> bool:
	if _any_in_lane_placed():
		return true
	if phase < 2 or phase > 7:
		return false
	if phase < 7:
		return true
	for d in item_defs:
		if d.get("in_lane", false):
			return false
	return _placed_count() > 0 or _lines_count(0.001) > 0


func _orphans_state() -> Array:
	var out: Array = []
	for o in _orphans:
		if is_instance_valid(o) and o.has_meta("kind"):
			var gp: Vector3 = o.global_position
			out.append([str(o.get_meta("kind")), gp.x, gp.z, o.global_rotation.y])
	return out


## Debug tools: drop items that a changed plan no longer contains at once.
func clear_orphans() -> void:
	for o in _orphans:
		if is_instance_valid(o):
			o.queue_free()
	_orphans.clear()


func _tick_crew_tasks() -> void:
	if workers.is_empty():
		return
	for w in _idle_workers():
		if _wtasks.is_empty():
			break
		# yellow tape needs the line items first; keep order but let others continue
		var t: Dictionary = _wtasks.pop_front()
		_run_task(w, t)
	var total := 0
	var done := 0
	var any_busy := false
	for w in workers:
		if w.busy:
			any_busy = true
	if _rebuilding:
		if _wtasks.is_empty() and not any_busy:
			_finish_rebuild()
		return
	if step_id() == "closure":
		total = item_defs.size() + yellow_lines.size()
		done = _placed_count() + _lines_count(1.0)
		progress = float(done) / maxf(1.0, total)
		if _wtasks.is_empty() and not any_busy:
			for i in workers.size():
				_worker_home(workers[i], i)
			if not traffic_on:
				_traffic_activate()   # the work zone needs the detour even if no item stands in the lane
			_complete("closure")
	elif step_id() == "teardown":
		total = item_defs.size() + yellow_lines.size()
		done = total - _placed_count() - _lines_count(0.001)
		progress = float(done) / maxf(1.0, total)
		if _wtasks.is_empty() and not any_busy:
			if kit_used:
				crew_van.cargo.barriers += 1
				kit_used = false
			if traffic_on:
				_traffic_deactivate()
			for i in workers.size():
				_worker_home(workers[i], i)
			_complete("teardown")


func _run_task(w: Worker, t: Dictionary) -> void:
	w.busy = true
	var cp := lay.crew_point()
	var cp3 := gw(cp, 0.05)
	match t.type:
		"place":
			var i: int = t.i
			var d: Dictionary = item_defs[i]
			var node := SiteProps.item(d.kind, d.phase)
			w.walk_to(cp3, func(_w):
				w.hold(node)
				var target := gw(d.pos, 0.05)
				var approach := target + Vector3(sin(d.yaw), 0, cos(d.yaw)) * 0.9
				w.walk_to(approach, func(_w2):
					w.face(target)
					w.act("place", 1.3, func(_w3):
						var n2 := w.release_carry()
						if n2.get_parent():
							n2.get_parent().remove_child(n2)
						add_child(n2)
						n2.global_transform = Transform3D(Basis(Vector3.UP, d.yaw), gw(d.pos, 0.05))
						item_nodes[i] = n2
						if d.get("in_lane", false) and not traffic_on:
							_traffic_activate()
						w.busy = false)))
		"remove":
			var i2: int = t.i
			var d2: Dictionary = item_defs[i2]
			var target2 := gw(d2.pos, 0.05)
			var approach2 := target2 + Vector3(sin(d2.yaw), 0, cos(d2.yaw)) * 0.9
			w.walk_to(approach2, func(_w):
				w.face(target2)
				w.act("place", 1.1, func(_w2):
					var n3: Node3D = item_nodes[i2]
					item_nodes[i2] = null
					if n3:
						w.hold(n3)
					if d2.get("in_lane", false) and traffic_on and not _any_in_lane_placed():
						_traffic_deactivate()
					w.walk_to(cp3, func(_w3):
						var c := w.release_carry()
						if c:
							c.queue_free()
						w.busy = false)))
		"yellow_on":
			var li: int = t.l
			var pts: PackedVector2Array = yellow_lines[li]
			var path: Array = []
			for k in pts.size():
				path.append(gw(pts[k], 0.05))
			w.walk_to(path[0], func(_w):
				w.act("place", 1.0, func(_w2):
					w.set_meta("tape", li)
					w.walk_path(path, func(_w3):
						w.remove_meta("tape")
						yellow_fracs[li] = 1.0
						_update_yellow()
						w.busy = false)))
		"yellow_off":
			var li2: int = t.l
			var pts2: PackedVector2Array = yellow_lines[li2]
			var path2: Array = []
			for k in range(pts2.size() - 1, -1, -1):
				path2.append(gw(pts2[k], 0.05))
			w.walk_to(path2[0], func(_w):
				w.set_meta("untape", li2)
				w.walk_path(path2, func(_w3):
					w.remove_meta("untape")
					yellow_fracs[li2] = 0.0
					_update_yellow()
					w.busy = false))
		"collect":
			var on: Node3D = t.node
			if not is_instance_valid(on):
				w.busy = false
				return
			var tp := on.global_position
			var oy := on.global_rotation.y
			w.walk_to(gw(Vector2(tp.x, tp.z), 0.05) + Vector3(sin(oy), 0, cos(oy)) * 0.9, func(_w):
				w.face(tp)
				w.act("place", 1.1, func(_w2):
					_orphans.erase(on)
					if is_instance_valid(on):
						w.hold(on)
					w.walk_to(cp3, func(_w3):
						var c2 := w.release_carry()
						if c2:
							c2.queue_free()
						w.busy = false)))


## True while an item that blocks the closed lane stands (traffic is shifted around the site).
func _any_in_lane_placed() -> bool:
	for i in item_defs.size():
		if item_defs[i].get("in_lane", false) and item_nodes[i] != null:
			return true
	return false


## Number of yellow markings laid at least to fraction f.
func _lines_count(f: float) -> int:
	var n := 0
	for x in yellow_fracs:
		if float(x) >= f:
			n += 1
	return n


func _update_yellow() -> void:
	for n in yellow_nodes:
		if is_instance_valid(n):
			n.queue_free()
	yellow_nodes.clear()
	for l in yellow_lines.size():
		var f := clampf(float(yellow_fracs[l]), 0.0, 1.0)
		if f <= 0.001:
			continue
		var pl: PackedVector2Array = yellow_lines[l]
		var cum := Geo.cumulative(pl)
		var pts := Geo.sub_polyline(pl, cum, 0.0, cum[cum.size() - 1] * f)
		if pts.size() < 2:
			continue
		var node := SiteProps.ribbon(pts, 0.15, 0.068, Mats.get_mat("mark_yellow"))
		add_child(node)
		yellow_nodes.append(node)


func _track_tape() -> void:
	# grow / shrink the yellow line behind the worker walking along it
	for w in workers:
		var mk := "tape" if w.has_meta("tape") else ("untape" if w.has_meta("untape") else "")
		if mk == "":
			continue
		var l := int(w.get_meta(mk))
		if l < 0 or l >= yellow_lines.size():
			continue
		var pl: PackedVector2Array = yellow_lines[l]
		var cum := Geo.cumulative(pl)
		var r: Array = Geo.closest_on_polyline(pl, cum, Vector2(w.position.x, w.position.z))
		var f: float = float(r[1]) / maxf(0.01, cum[cum.size() - 1])
		if absf(f - float(yellow_fracs[l])) > 0.02:
			yellow_fracs[l] = f
			_update_yellow()


# ------------------------------------------------------------------------------------------
# Traffic
# ------------------------------------------------------------------------------------------

func _traffic_activate() -> void:
	if traffic_on:
		return
	traffic_on = true
	var tr := world.traffic
	if plan.full:
		# full road closure (#20): both lanes blocked at the site, no through traffic on the road;
		# background vehicles already on it in front of the barrier stop there (TrafficSim lets them vanish)
		tr.set_obstacle(lay.key, lay.obst0, lay.obst1, 1000 + sid)
		var a2: float = lay.lane2_coords(lay.lane_pt(lay.obst0)).x
		var b2: float = lay.lane2_coords(lay.lane_pt(lay.obst1)).x
		tr.set_obstacle(lay.key2, minf(a2, b2), maxf(a2, b2), 1000 + sid)
		tr.close_edges(closed_edges(), 1000 + sid)
		# the site's own vehicles still pass the work area (to the stage behind it): the detour of K
		# without a bottleneck zone, background traffic never reaches it
		tr.set_detour(lay.key, lay.s_det0, lay.s_det1, lay.detour_pts(), 100 + sid, 5.0)
		_redispatch_waiting()
		return
	var zone := 100 + sid
	var prio := {lay.key: 0, lay.key2: (1 if lay.oncoming else 0)}
	if not lay.two_way:
		tr.set_zone(zone, prio)   # bottleneck (oncoming) or zipper (same direction)
	tr.set_obstacle(lay.key, lay.obst0, lay.obst1, 1000 + sid)
	tr.set_detour(lay.key, lay.s_det0, lay.s_det1, lay.detour_pts(), zone, 7.0)
	tr.set_detour(lay.key2, lay.s2_a, lay.s2_b, lay.zone2_pts(), zone, 7.0)
	_redispatch_waiting()


## Kind of traffic control of the plan in force, for the site panel.
func closure_kind() -> String:
	if plan and plan.full:
		return "Vollsperrung"
	if lay.two_way:
		return "Verschwenkung, beide Richtungen frei" if lay.oncoming else "Fahrstreifensperrung ohne Einfädeln"
	return "Engstelle mit Z 208/308" if lay.oncoming else "Fahrstreifensperrung"


## Roads (edges) a full closure shuts: the site's road, and the other carriageway if it is a separate way.
func closed_edges() -> Array:
	var out: Array = [lay.key >> 4]
	if (lay.key2 >> 4) != (lay.key >> 4):
		out.append(lay.key2 >> 4)
	return out


func _traffic_deactivate() -> void:
	if not traffic_on:
		return
	traffic_on = false
	var tr := world.traffic
	tr.clear_obstacles(1000 + sid)
	tr.clear_detours(100 + sid)
	tr.open_edges(1000 + sid)
	stats.jam_s = tr.jam_counter.get(1000 + sid, 0.0) + tr.jam_counter.get(100 + sid, 0.0)


# ------------------------------------------------------------------------------------------
# Digging
# ------------------------------------------------------------------------------------------

func _excavator() -> Vehicle:
	var v := occupant("exc")
	if v and in_place.has(v):
		return v
	return null


func _tipper_at_load() -> Vehicle:
	var v := occupant("load")
	if v and in_place.has(v) and role(v) == "bulk" and not _tip_busy.has(v):
		return v
	return null


func _can_dig() -> String:
	if not traffic_on or _placed_count() < item_defs.size():
		return "Erst die Absperrung aufbauen"
	if _excavator() == null:
		return "Bagger ist nicht in Position"
	return ""


func _start_dig() -> void:
	running = true
	sub = "dig"
	_excav = _excavator()
	_excav.working = true
	_connect_rig(_excav)
	terrain.set_hole(jm.pit_slot_of(self), true)
	_set_status("Bagger hebt den Graben aus …")


func _connect_rig(ex: Vehicle) -> void:
	if ex.rig and not ex.rig.cycle_event.is_connected(_on_rig_event):
		ex.rig.cycle_event.connect(_on_rig_event)


func _turret_u() -> float:
	if _excav == null:
		return 4.0
	var tp := _excav.rig.turret.global_position if _excav.rig else _excav.global_position
	return terrain.local_of(tp).x


func _tick_dig(delta: float) -> void:
	var ex := _excavator()
	if ex == null:
		_set_status("Bagger fehlt.")
		return
	_excav = ex
	if ex.rig and ex.rig.busy:
		return
	var remaining := terrain.remaining_dig()
	progress = 1.0 - remaining / maxf(0.01, terrain.total_dig())
	if remaining < 0.04:
		_finish_dig()
		return
	var tip := _tipper_at_load()
	if tip == null or tip.bulk_m3() > tip.bulk_capacity() - 0.55:
		if tip and tip.auto_shuttle and not _tip_busy.has(tip):
			_tipper_next(tip)
		_set_status("Bagger wartet auf einen leeren Kipper.")
		ex.working = false
		return
	ex.working = true
	_set_status("Bagger hebt den Graben aus – %d %%" % int(progress * 100.0))
	_bite = terrain.next_bite(_turret_u())
	if _bite.is_empty():
		_finish_dig()
		return
	_bite_done = 0.0
	if ex.rig == null:
		_fallback_t += delta
		if _fallback_t > 6.0:
			_fallback_t = 0.0
			var got := terrain.dig_strip(_bite, BUCKET_BANK)
			tip.add_bulk("soil", got * BULKING)
		return
	var top: float = _bite.top
	var bottom := maxf(top - 0.5, -job.depth)
	var pick := terrain.to_world(_bite.u0, _bite.v, top)
	var pick_to := terrain.to_world(_bite.u1, _bite.v, bottom)
	var drop := _tipper_drop_point(tip)
	ex.rig.set_meta("cycle", {"kind": "dig", "target": tip})
	ex.rig.material_cycle(pick, pick_to, drop, drop.y + 0.2, 1.0)


func _tipper_drop_point(t: Vehicle) -> Vector3:
	if t._tipper_body:
		var c := t._load_box.get_center()
		var top := t._load_box.position.y + t._load_box.size.y
		var p := t._tipper_body.global_transform * Vector3(c.x, top, c.z + 0.6)
		return p
	return t.global_position + Vector3(0, 3.0, 0)


func _on_rig_event(kind: String, data: Dictionary) -> void:
	if _excav == null or _excav.rig == null:
		return
	var cyc: Dictionary = _excav.rig.get_meta("cycle", {})
	match cyc.get("kind", ""):
		"dig":
			match kind:
				"progress":
					var t: float = data.t
					var want := BUCKET_BANK * t - _bite_done
					if want > 0.0 and not _bite.is_empty():
						_bite_done += terrain.dig_strip(_bite, want)
					_excav.rig.set_load(_bite_done * BULKING, "soil")   # the bucket fills during the bite (#11)
				"picked":
					_excav.rig.set_load(_bite_done * BULKING, "soil")
				"dropped":
					var tgt: Vehicle = cyc.get("target")
					var loose := _bite_done * BULKING
					if is_instance_valid(tgt) and in_place.has(tgt):
						tgt.add_bulk("soil", loose)
					stats.spoil_m3 += loose
					_excav.rig.set_load(0.0, "soil")
		"fill":
			match kind:
				"progress":
					var tf: float = data.t
					_excav.rig.set_load(minf(0.6, pile_m3) * tf, pile_mat)   # the bucket fills in the pile (#11)
				"picked":
					var amt: float = minf(0.6, pile_m3)
					pile_m3 -= amt
					_update_pile()
					_excav.rig.set_load(amt, pile_mat)
					cyc["amount"] = amt
					_excav.rig.set_meta("cycle", cyc)
				"dropped":
					var amt2: float = cyc.get("amount", 0.0)
					var spot: Vector2 = cyc.get("spot", Vector2.ZERO)
					var top: float = cyc.get("top", 0.0)
					var placed := terrain.fill_at(spot, amt2 / BULKING, top, cyc.get("fresh", false))
					placed_since_compact += placed
					_excav.rig.set_load(0.0, pile_mat)
					var excess := amt2 / BULKING - placed
					if excess > 0.01:
						pile_m3 += excess * BULKING
						_update_pile()
		"pipe_out":
			match kind:
				"hooked":
					pipe_old.queue_free()
					pipe_old = SiteProps.pipe("old", job.length - 0.3, job.pipe_d)
					add_child(pipe_old)
					_excav.rig.hook_item = pipe_old
					_excav.rig.hook_yaw = SiteLayout.yaw_of(lay.trench_dir())
					_excav.rig.hook_drop = 0.9
				"released":
					_excav.rig.hook_item = null
					if pipe_old:
						pipe_old.queue_free()
						pipe_old = null
					var fb: Vehicle = cyc.get("target")
					if is_instance_valid(fb):
						fb.cargo.pipes_old += 1
						fb.update_load_visual()
		"pipe_in":
			match kind:
				"hooked":
					var fb2: Vehicle = cyc.get("target")
					if is_instance_valid(fb2):
						fb2.cargo.pipes_new = maxi(0, fb2.cargo.pipes_new - 1)
						fb2.update_load_visual()
					pipe_new = SiteProps.pipe("new", job.length - 0.3, job.pipe_d)
					add_child(pipe_new)
					_excav.rig.hook_item = pipe_new
					_excav.rig.hook_yaw = SiteLayout.yaw_of(lay.trench_dir())
				"released":
					_excav.rig.hook_item = null
					var c := lay.trench_center()
					pipe_new.global_transform = Transform3D(Basis(Vector3.UP, SiteLayout.yaw_of(lay.trench_dir())), gw(c, SiteTerrain.Y_ROAD - job.depth + 0.05))
	if kind == "done":
		_excav.rig.set_meta("cycle", {})


func _finish_dig() -> void:
	if _excav and _excav.rig:
		_excav.rig.travel_pose()
	# material needs for the refill
	var sand_top: float = terrain.sand_top
	var pipe_vol := PI * pow(job.pipe_d * 0.5, 2.0) * job.length
	var sand := maxf(0.5, (terrain.fill_needed(sand_top) - pipe_vol) * BULKING)
	var area := terrain.inner_area()
	var gravel := maxf(0.5, (area * (-SiteTerrain.ASPHALT - sand_top)) * BULKING)
	var asphalt := maxf(0.3, area * SiteTerrain.ASPHALT * BULKING)
	needs = [{"mat": "sand", "m3": snappedf(sand * 1.06 + 0.2, 0.1), "delivered": 0.0, "ordered": 0.0},
		{"mat": "gravel", "m3": snappedf(gravel * 1.06 + 0.3, 0.1), "delivered": 0.0, "ordered": 0.0},
		{"mat": "asphalt", "m3": snappedf(asphalt * 1.1 + 0.15, 0.1), "delivered": 0.0, "ordered": 0.0}]
	_complete("dig")
	# tippers: take the spoil away and fetch material
	for v in vehicles:
		if is_instance_valid(v) and role(v) == "bulk" and v.auto_shuttle:
			_tipper_next(v)


# ------------------------------------------------------------------------------------------
# Pipe swap
# ------------------------------------------------------------------------------------------

func _flatbed_at_load() -> Vehicle:
	var v := occupant("load")
	if v and in_place.has(v) and role(v) == "pipes":
		return v
	return null


func _can_pipe() -> String:
	if pipe_new != null:
		return "" if crew_present() else "Kolonne ist nicht vor Ort"
	if _excavator() == null:
		return "Bagger ist nicht in Position"
	var fb := _flatbed_at_load()
	if fb == null:
		return "Pritschen-LKW mit neuem Rohr fehlt"
	if fb.cargo.pipes_new <= 0:
		return "Kein neues Rohr geladen"
	if not crew_present():
		return "Kolonne ist nicht vor Ort"
	return ""


func _start_pipe() -> void:
	running = true
	_ensure_workers()
	if pipe_new != null:
		# new pipe already lies in the trench (resumed after an interruption)
		_finish_pipe()
		return
	_excav = _excavator()
	_connect_rig(_excav)
	sub = "workers_in" if pipe_old != null else "lift_new"
	var c := lay.trench_center()
	var d := lay.trench_dir()
	var floor_y := SiteTerrain.Y_ROAD - job.depth
	var ws := _idle_workers()
	var n := mini(2, ws.size())
	var count := [0]
	for k in n:
		var w: Worker = ws[k]
		w.busy = true
		var end := c + d * (job.length * 0.5 - 0.35) * (1.0 if k == 0 else -1.0)
		var edge := c + d * (job.length * 0.5 + 0.5) * (1.0 if k == 0 else -1.0) + Geo.right_of(d) * (job.width * 0.5 + 0.6)
		w.walk_path([gw(edge, 0.05), gw(end, floor_y)], func(_w):
			w.face(gw(c, floor_y))
			w.act("cut", 8.0, func(_w2):
				count[0] += 1
				if count[0] >= n and sub == "workers_in":
					sub = "lift_old"))
	if n == 0 and sub == "workers_in":
		sub = "lift_old"
	_set_status("Kolonne legt das Rohr frei und trennt das Altrohr …")


func _tick_pipe(_delta: float) -> void:
	var ex := _excavator()
	if ex == null:
		return
	var fb := _flatbed_at_load()
	match sub:
		"lift_old":
			if fb == null:
				_set_status("Pritsche fehlt.")
				return
			if pipe_old == null:
				sub = "lift_new"
				return
			sub = "lifting_old"
			progress = 0.35
			_set_status("Bagger hebt das Altrohr heraus …")
			if ex.rig:
				ex.rig.set_meta("cycle", {"kind": "pipe_out", "target": fb})
				ex.rig.lift_cycle(pipe_old.global_position + Vector3(0, job.pipe_d, 0), _bed_point(fb))
			else:
				pipe_old.queue_free()
				fb.cargo.pipes_old += 1
		"lifting_old":
			if ex.rig == null or not ex.rig.busy:
				sub = "lift_new"
		"lift_new":
			if fb == null:
				return
			sub = "lifting_new"
			progress = 0.6
			_set_status("Bagger setzt das neue Rohr ein …")
			var c := lay.trench_center()
			if ex.rig:
				ex.rig.set_meta("cycle", {"kind": "pipe_in", "target": fb})
				ex.rig.lift_cycle(_bed_point(fb), gw(c, SiteTerrain.Y_ROAD - job.depth + 0.05 + job.pipe_d))
			else:
				fb.cargo.pipes_new -= 1
				pipe_new = SiteProps.pipe("new", job.length - 0.3, job.pipe_d)
				add_child(pipe_new)
				pipe_new.global_transform = Transform3D(Basis(Vector3.UP, SiteLayout.yaw_of(lay.trench_dir())), gw(c, SiteTerrain.Y_ROAD - job.depth + 0.05))
		"lifting_new":
			if ex.rig == null or not ex.rig.busy:
				sub = "connect"
				progress = 0.8
				_set_status("Kolonne verbindet das neue Rohr …")
				var ws := workers.filter(func(w): return w.busy)
				var cnt := [0]
				if ws.is_empty():
					sub = "out"
				for w in ws:
					w.act("work", 10.0, func(_w):
						cnt[0] += 1
						if cnt[0] >= ws.size():
							sub = "out")
		"out":
			sub = "climbing"
			var ws2 := workers.filter(func(w): return w.busy)
			var cnt2 := [0]
			var c2 := lay.trench_center()
			var d2 := lay.trench_dir()
			if ws2.is_empty():
				_finish_pipe()
				return
			for i in ws2.size():
				var w: Worker = ws2[i]
				var edge := c2 + d2 * (job.length * 0.5 + 0.5) * (1.0 if i == 0 else -1.0) + Geo.right_of(d2) * (job.width * 0.5 + 0.6)
				w.walk_to(gw(edge, 0.05), func(_w):
					w.busy = false
					_worker_home(w, i)
					cnt2[0] += 1
					if cnt2[0] >= ws2.size():
						_finish_pipe())


func _bed_point(fb: Vehicle) -> Vector3:
	return fb.global_transform * Vector3(0, 1.25 + job.pipe_d, 0.5)


func _finish_pipe() -> void:
	if _excav and _excav.rig:
		_excav.rig.travel_pose()
	_complete("pipe")
	var fb := _flatbed_at_load()
	if fb:
		_return_to_hq(fb)
	for v in vehicles:
		if is_instance_valid(v) and role(v) == "bulk" and v.auto_shuttle:
			_tipper_next(v)


# ------------------------------------------------------------------------------------------
# Refill and asphalt
# ------------------------------------------------------------------------------------------

func _layer_top() -> float:
	return terrain.sand_top if layer == 0 else -SiteTerrain.ASPHALT


func _layer_mat() -> String:
	return "sand" if layer == 0 else "gravel"


func _can_refill() -> String:
	if _excavator() == null:
		return "Bagger ist nicht in Position"
	if not crew_present():
		return "Kolonne ist nicht vor Ort (Verdichten)"
	if pile_m3 < 0.2 and not _tipper_bringing():
		return "Kein Material vor Ort – Kipper schicken"
	return ""


func _tipper_bringing() -> bool:
	for v in vehicles:
		if is_instance_valid(v) and role(v) == "bulk":
			return true
	return false


var _refill_total := 1.0
func _start_refill() -> void:
	_refill_total = maxf(0.1, terrain.fill_needed(-SiteTerrain.ASPHALT))
	compacting = false
	running = true
	_ensure_workers()
	_excav = _excavator()
	_connect_rig(_excav)
	sub = "fill"
	_set_status("Graben wird verfüllt …")


func _tick_refill(_delta: float) -> void:
	var ex := _excavator()
	if ex == null:
		_set_status("Bagger fehlt.")
		return
	if compacting or (ex.rig and ex.rig.busy):
		return
	var top := _layer_top()
	var need := terrain.fill_needed(top)
	var full_vol := terrain.fill_needed(-SiteTerrain.ASPHALT) + 0.001
	progress = clampf(1.0 - full_vol / maxf(0.01, _refill_total), 0.0, 1.0)
	if need < 0.04 or placed_since_compact > 1.1:
		if placed_since_compact > 0.05 or need < 0.04:
			_compaction_pass(func():
				if terrain.fill_needed(top) < 0.04:
					layer += 1
					if layer > 1:
						_finish_refill())
			return
	if pile_m3 < 0.05:
		# small shortfall after all deliveries: level out what is there and go on
		var mat_need: Dictionary = {}
		for n in needs:
			if n.mat == _layer_mat():
				mat_need = n
		var all_delivered: bool = mat_need.is_empty() or mat_need.delivered >= mat_need.m3 - 0.05
		if all_delivered and need < 0.45:
			placed_since_compact = 0.1
			_compaction_pass(func():
				layer += 1
				if layer > 1:
					_finish_refill())
			return
		if all_delivered and not mat_need.is_empty() and mat_need.get("ordered", 0.0) < 0.05:
			# order the missing amount
			mat_need.m3 = mat_need.delivered + snappedf(need * BULKING + 0.3, 0.1)
			for v in vehicles:
				if is_instance_valid(v) and role(v) == "bulk" and v.auto_shuttle:
					_tipper_next(v)
		_set_status("Warte auf %s (Kipper)." % Balance.MATERIALS[_layer_mat()].name)
		ex.working = false
		return
	ex.working = true
	_set_status("Verfüllen: %s, lagenweise verdichten …" % Balance.MATERIALS[_layer_mat()].name)
	var spot := terrain.lowest_spot(top)
	var drop := terrain.surface_world(spot)
	var pc := lay.pile_center()
	var pile_top := gw(pc, 0.05 + _pile_height() * 0.7)
	if ex.rig == null:
		var amt := minf(0.6, pile_m3)
		pile_m3 -= amt
		_update_pile()
		placed_since_compact += terrain.fill_at(spot, amt / BULKING, top)
		return
	ex.rig.set_meta("cycle", {"kind": "fill", "spot": spot, "top": top, "fresh": false})
	var dl := Geo.v3(lay.lane_dir(lay.s_exc))
	ex.rig.material_cycle(pile_top + dl * 0.7, pile_top - Vector3(0, 0.35, 0) - dl * 0.7, drop, maxf(drop.y, Terrain.at3(drop.x, drop.z)) + 0.6, 1.0)


func _compaction_pass(after: Callable) -> void:
	if workers.is_empty():
		after.call()
		return
	compacting = true
	var w: Worker = workers[workers.size() - 1]
	w.busy = true
	var c := lay.trench_center()
	var d := lay.trench_dir()
	var r := Geo.right_of(d)
	var hgt := terrain.mean_height()
	var y := SiteTerrain.Y_ROAD + hgt
	var plate := SiteProps.plate_compactor()
	var edge := c + d * (job.length * 0.5 + 0.6) + r * (job.width * 0.5 + 0.6)
	var path: Array = []
	var lanes := [-job.width * 0.25, job.width * 0.25]
	for li in lanes.size():
		var v: float = lanes[li]
		var a := c + d * (job.length * 0.5 - 0.35) + r * v
		var b := c - d * (job.length * 0.5 - 0.35) + r * v
		if li % 2 == 1:
			var tmp := a
			a = b
			b = tmp
		path.append(gw(a, y))
		path.append(gw(b, y))
	_set_status("Verdichten mit der Rüttelplatte …")
	w.walk_to(gw(edge, 0.05), func(_w):
		w.set_tool(plate)
		w.action = "compact"
		w.walk_path(path, func(_w2):
			w.act("compact", 2.0, func(_w3):
				w.set_tool(null)
				terrain.compact(1.0)
				placed_since_compact = 0.0
				w.walk_to(gw(edge, 0.05), func(_w4):
					w.busy = false
					_worker_home(w, workers.find(w))
					compacting = false
					after.call()))))


func _finish_refill() -> void:
	if _excav and _excav.rig:
		_excav.rig.travel_pose()
	# leftovers are spread on site by the crew
	pile_m3 = 0.0
	pile_mat = ""
	_pile_base = 0.0
	_update_pile()
	# sand and gravel are no longer needed: a tipper still bringing some must not tip it onto the
	# asphalt spot (its pile blocked the asphalt delivery for good)
	for n in needs:
		if n.mat != "asphalt":
			n.m3 = n.delivered
			n["ordered"] = 0.0
	_complete("refill")
	for v in vehicles:
		if is_instance_valid(v) and role(v) == "bulk" and v.auto_shuttle:
			_tipper_next(v)


func _can_asphalt() -> String:
	if not crew_present():
		return "Kolonne ist nicht vor Ort"
	if pile_mat != "asphalt" or pile_m3 < 0.2:
		return "Asphalt-Mischgut fehlt – Kipper schicken"
	return ""


func _start_asphalt() -> void:
	compacting = false
	running = true
	_ensure_workers()
	_excav = _excavator()
	if _excav:
		_connect_rig(_excav)
	sub = "place"
	_set_status("Asphalt wird eingebaut …")


func _tick_asphalt(_delta: float) -> void:
	match sub:
		"place":
			var ex := _excavator()
			var need := terrain.fill_needed(0.0)
			progress = 0.6 * (1.0 - need / maxf(0.01, terrain.inner_area() * SiteTerrain.ASPHALT))
			if need < 0.03 or pile_m3 < 0.02:
				sub = "rake"
				return
			if ex and ex.rig:
				if ex.rig.busy:
					return
				var spot := terrain.lowest_spot(0.0)
				var drop := terrain.surface_world(spot)
				var pc := lay.pile_center()
				var pile_top := gw(pc, 0.05 + _pile_height() * 0.7)
				ex.rig.set_meta("cycle", {"kind": "fill", "spot": spot, "top": 0.0, "fresh": true})
				ex.rig.material_cycle(pile_top, pile_top - Vector3(0, 0.3, 0) - Geo.v3(lay.lane_dir(lay.s_exc)) * 0.8, drop, maxf(drop.y, Terrain.at3(drop.x, drop.z)) + 0.6, 1.0)
			else:
				# crew shovels it in
				var amt := minf(0.15, pile_m3)
				pile_m3 -= amt
				_update_pile()
				terrain.fill_at(terrain.lowest_spot(0.0), amt / BULKING, 0.0, true)
		"rake":
			sub = "raking"
			_set_status("Kolonne verteilt den Asphalt …")
			var ws := _idle_workers()
			var cnt := [0]
			var n := mini(2, ws.size())
			if n == 0:
				sub = "compact"
				return
			var c := lay.trench_center()
			var d := lay.trench_dir()
			for k in n:
				var w: Worker = ws[k]
				w.busy = true
				var side := Geo.right_of(d) * (job.width * 0.5 + 0.45) * (1.0 if k == 0 else -1.0)
				var a := c + d * job.length * 0.5 + side
				var b := c - d * job.length * 0.5 + side
				w.walk_path([gw(a, 0.05)], func(_w):
					w.action = "rake"
					w.walk_path([gw(b, 0.05), gw(a, 0.05)], func(_w2):
						w.act("rake", 3.0, func(_w3):
							w.busy = false
							cnt[0] += 1
							if cnt[0] >= n:
								sub = "compact")))
		"compact":
			sub = "compacting"
			progress = 0.85
			_compaction_pass(func():
				terrain.set_fresh_all()
				terrain.compact(1.0)
				_finish_asphalt())


func _finish_asphalt() -> void:
	pile_m3 = 0.0
	pile_mat = ""
	_update_pile()
	_complete("asphalt")


# ------------------------------------------------------------------------------------------
# Material pile
# ------------------------------------------------------------------------------------------

func _pile_dims() -> Vector2:
	return Vector2(3.0, maxf(1.6, lay.lw - 0.5))


func _pile_height() -> float:
	var dm := _pile_dims()
	return pile_m3 / (dm.x * dm.y * 0.42)


func _update_pile() -> void:
	pile_m3 = maxf(pile_m3, 0.0)
	if pile_m3 <= 0.02:
		if pile_node:
			pile_node.visible = false
		return
	if pile_node == null:
		pile_node = MeshInstance3D.new()
		pile_node.mesh = RigUtil.mound_mesh()
		add_child(pile_node)
	pile_node.visible = true
	var dm := _pile_dims()
	var pc := lay.pile_center()
	pile_node.global_transform = Transform3D(Basis(Vector3.UP, SiteLayout.yaw_of(lay.lane_dir(lay.s_exc))).scaled(Vector3(dm.y, _pile_height(), dm.x)), gw(pc, 0.04))
	pile_node.material_override = RigUtil.bulk_material(pile_mat if pile_mat != "" else "soil")


# ------------------------------------------------------------------------------------------
# Tipper logistics (automatic shuttle)
# ------------------------------------------------------------------------------------------

func _next_need() -> Dictionary:
	for n in needs:
		if n.delivered < n.m3 - 0.05:
			return n
	return {}


func _orderable_need() -> Dictionary:
	for n in needs:
		if n.delivered + n.get("ordered", 0.0) < n.m3 - 0.05:
			return n
	return {}


func _tipper_next(v: Vehicle) -> void:
	if not is_instance_valid(v) or v.site != self:
		return
	if _tip_busy.has(v) or v.state in ["loading", "driving", "waiting"]:
		return
	var load := v.bulk_m3()
	var mat := v.bulk_main()
	var cap := v.bulk_capacity()
	var digging := phase <= 2
	if digging and phase >= 1:
		if load > 0.05 and mat != "soil":
			_go_stage(v)
			return
		if load > cap - 0.55:
			_haul_to_hq(v)
			return
		if occupant("load") == null or occupant("load") == v:
			if not (in_place.has(v) and spot_of.get(v, "") == "load"):
				# the excavator has to be in its slot first (it reverses in past the loading slot)
				if _excavator() != null:
					_go_slot(v, "load", lay.load_s(v.rear_ext), lay.load_lat)
				else:
					_go_stage(v)
			return
		_go_stage(v)
		return
	if phase == 0:
		_go_stage(v)
		return
	# after digging: remove leftover spoil, then deliver materials
	if load > 0.05 and mat == "soil":
		_haul_to_hq(v)
		return
	var need := _next_need()
	if need.is_empty():
		if load > 0.05:
			_haul_to_hq(v)
		elif not v.at_hq():
			_return_to_hq(v)
		return
	if load > 0.05 and mat == need.mat:
		var ready := phase >= 4 and (pile_m3 < 0.05 or pile_mat == mat) and (occupant("load") == null or occupant("load") == v)
		if need.mat == "asphalt":
			ready = phase >= 5 and (pile_m3 < 0.05 or pile_mat == mat) and (occupant("load") == null or occupant("load") == v)
		if ready:
			if in_place.has(v) and spot_of.get(v, "") == "load":
				_tip_here(v)
			else:
				_go_slot(v, "load", lay.dump_s(v.rear_ext), lay.pile_lat)
		else:
			_go_stage(v)
		return
	if load > 0.05:
		# keep a load that is needed later if another tipper can bring the current material
		var later := false
		for n in needs:
			if n.mat == mat and n.delivered < n.m3 - 0.05:
				later = true
		var others := vehicles.filter(func(o): return is_instance_valid(o) and o != v and role(o) == "bulk" and (o.bulk_m3() < 0.05 or o.bulk_main() == need.mat)).size()
		if later and others > 0:
			_go_stage(v)
		else:
			_haul_to_hq(v)
		return
	var on := _orderable_need()
	if on.is_empty():
		_go_stage(v)
		return
	_fetch_material(v, on)


func _tipper_arrived(v: Vehicle) -> void:
	if spot_of.get(v, "") == "load" and v.auto_shuttle:
		var need := _next_need()
		if phase > 2 and not need.is_empty() and v.bulk_main() == need.mat and v.bulk_m3() > 0.05:
			_tip_here(v)
		elif phase > 2 and v.bulk_m3() > 0.05:
			_tipper_next.call_deferred(v)   # the load is no longer needed here (the step ended on the way)


func _tip_here(v: Vehicle) -> void:
	_tip_busy[v] = true
	_pile_base = pile_m3 if (pile_mat == v.bulk_main() or pile_m3 < 0.02) else pile_m3
	var mat := v.bulk_main()
	var m3 := v.bulk_m3()
	v.state = "working"
	v.working = true
	v.status_text = "Kippt %s ab" % Balance.MATERIALS[mat].name
	var tw := v.create_tween()
	tw.tween_subtween(v.tween_tip(45.0, 5.0))
	var prev := [0.0]
	tw.tween_method(func(t):
		var remain: float = m3 * (1.0 - t)
		v.cargo.bulk = {mat: remain} if remain > 0.01 else {}
		v.update_load_visual()
		pile_mat = mat
		pile_m3 += m3 * t - prev[0]
		prev[0] = m3 * t
		_update_pile(), 0.0, 1.0, 4.0)
	tw.tween_subtween(v.tween_tip(0.0, 4.0))
	tw.tween_callback(func():
		_tip_busy.erase(v)
		v.working = false
		v.cargo.bulk = {}
		v.update_load_visual()
		for n in needs:
			if n.mat == mat:
				n.delivered += m3
				break
		_cancel_order(v)
		_pile_base = pile_m3
		Events.info("%s: %.1f m³ %s abgeladen" % [job.short_title(), m3, Balance.MATERIALS[mat].name])
		changed.emit(self)
		if v.auto_shuttle:
			_tipper_next(v))


var _pile_base := 0.0
func _pile_set_from_delivery(mat: String, amount: float) -> void:
	pile_mat = mat
	pile_m3 = _pile_base + amount
	_update_pile()


func _cancel_order(v: Vehicle) -> void:
	if _orders.has(v):
		var o: Array = _orders[v]
		o[0]["ordered"] = maxf(0.0, o[0].get("ordered", 0.0) - o[1])
		_orders.erase(v)


func _haul_to_hq(v: Vehicle) -> void:
	_cancel_order(v)
	v.drive_to_bay("soil", func(veh): _dump_at_hq(veh))
	spot_of.erase(v)
	in_place.erase(v)
	v.status_text = "Fährt Aushub zur Zentrale"


func _dump_at_hq(v: Vehicle) -> void:
	var mat := v.bulk_main()
	var m3 := v.bulk_m3()
	v.state = "loading"
	v.status_text = "Kippt Aushub ab"
	var tw := v.create_tween()
	tw.tween_subtween(v.tween_tip(45.0, 5.0))
	tw.tween_method(func(t):
		v.cargo.bulk = {mat: m3 * (1.0 - t)} if t < 0.99 else {}
		v.update_load_visual(), 0.0, 1.0, 3.0)
	tw.tween_subtween(v.tween_tip(0.0, 4.0))
	tw.tween_callback(func():
		v.state = "parked"
		v.cargo.bulk = {}
		v.update_load_visual()
		var t_total := Balance.material_t(mat if mat != "" else "soil", m3)
		var cost: float = t_total * float(Balance.MATERIALS.get(mat, Balance.MATERIALS.soil).dispose_t)
		Game.spend(cost, "Entsorgung %.1f t %s" % [t_total, Balance.MATERIALS.get(mat, Balance.MATERIALS.soil).name], true)
		job.costs += cost
		if v.site == self and v.auto_shuttle:
			_tipper_next(v)
		elif v.site == null:
			v.drive_to_hq()
		elif v.site != self:
			v.site._dispatch(v))


func _fetch_material(v: Vehicle, need: Dictionary) -> void:
	var amount := minf(v.bulk_capacity(), need.m3 - need.delivered - need.get("ordered", 0.0))
	amount = maxf(0.3, amount)
	v.status_text = "Holt %s in der Zentrale" % Balance.MATERIALS[need.mat].name
	_cancel_order(v)
	need["ordered"] = need.get("ordered", 0.0) + amount
	_orders[v] = [need, amount]
	v.drive_to_bay(need.mat, func(veh): _load_at_hq(veh, need, amount))
	spot_of.erase(v)
	in_place.erase(v)


func _load_at_hq(v: Vehicle, need: Dictionary, amount: float) -> void:
	v.state = "loading"
	v.status_text = "Wird beladen: %s" % Balance.MATERIALS[need.mat].name
	var tw := v.create_tween()
	tw.tween_method(func(t):
		v.cargo.bulk = {need.mat: amount * t}
		v.update_load_visual(), 0.0, 1.0, 8.0)
	tw.tween_callback(func():
		v.state = "parked"
		var t_total := Balance.material_t(need.mat, amount)
		var cost: float = t_total * float(Balance.MATERIALS[need.mat].price_t)
		Game.spend(cost, "Material %.1f t %s" % [t_total, Balance.MATERIALS[need.mat].name], true)
		job.costs += cost
		if v.site == self:
			_tipper_next(v)
		elif v.site == null:
			v.drive_to_hq()
		else:
			v.site._dispatch(v))


func _return_to_hq(v: Vehicle) -> void:
	v.drive_to_hq(func(veh):
		if veh.cargo.pipes_old > 0:
			veh.cargo.pipes_old = 0
			veh.update_load_visual()
			Game.spend(120.0, "Entsorgung Altrohr", true)
			job.costs += 120.0)


func _load_pipes_at_hq(v: Vehicle) -> void:
	v.state = "loading"
	v.status_text = "Lädt neues Rohr"
	var tw := v.create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(func():
		v.state = "parked"
		v.cargo.pipes_new += 1
		v.update_load_visual()
		var cost := Balance.PIPE_PRICE_PER_M * (job.length + 1.0) * (1.0 + job.pipe_d * 2.0)
		Game.spend(cost, "Rohr %s" % job.pipe_name, true)
		job.costs += cost
		if v.site == self:
			_flatbed_next(v))


# ------------------------------------------------------------------------------------------
# Lowbed
# ------------------------------------------------------------------------------------------

func _lowbed_back(v: Vehicle = null) -> float:
	return v.lowbed_back() if v else 21.5


func _dispatch_lowbed(v: Vehicle) -> void:
	var sp := lay.lowbed_spot(_lowbed_back(v))   # behind the closure, or on the lane out of K (#33)
	if sp.is_empty():
		# no room for a low-loader at this site: the machine drives itself, the low-loader stays home
		if v.cargo.machine != null:
			Events.warn("%s: kein Platz für den Tieflader – die Maschine fährt selbst hin" % job.short_title())
			v.unload_machine(func(mach):
				release_vehicle(v)
				send_vehicle(mach))
		else:
			Events.warn("%s: kein Platz für den Tieflader – der Bagger fährt selbst zurück" % job.short_title())
			release_vehicle(v)
		return
	var label := job.short_title()
	var appr: float = sp.appr
	v.drive_plan({"key": sp.key, "s": float(sp.s) - appr}, label, [v.pull_over_piece(sp.key, float(sp.s) - appr, SiteLayout.CURB, appr)], func(veh): _arrived(veh, "lowbed"))
	_reserve(v, "lowbed")


func _lowbed_arrived(v: Vehicle) -> void:
	if v.cargo.machine != null:
		var m: Vehicle = v.cargo.machine
		v.unload_machine(func(mach):
			send_vehicle(mach)
			# the empty lowbed goes home
			release_vehicle(v)
			v.drive_to_hq())
	else:
		var ex := _excavator()
		if ex and phase >= 6 and v.can_carry(ex):
			release_vehicle(ex)
			ex.state = "parked"
			v.load_machine(ex, func(_m):
				release_vehicle(v)
				v.drive_to_hq())
		elif ex and phase >= 6:
			Events.warn("%s ist zu schwer für %s – der Bagger fährt selbst zurück" % [ex.vname, v.vname])
			release_vehicle(v)
			v.drive_to_hq()


# ------------------------------------------------------------------------------------------
# Acceptance
# ------------------------------------------------------------------------------------------

func _do_acceptance() -> void:
	running = false
	jm.finish_job(self)


# ------------------------------------------------------------------------------------------
# Frame update
# ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_track_tape()
	var night: float = world.day_night.night if world.day_night else 0.0
	work_light.light_energy = (2.5 * night) if (running and night > 0.15) else 0.0
	marker.visible = phase < 2
	if running and not (work_paused() and step_id() in ["dig", "refill", "asphalt"]):
		match step_id():
			"closure", "teardown":
				_tick_crew_tasks()
			"dig":
				_tick_dig(delta)
			"pipe":
				_tick_pipe(delta)
			"refill":
				_tick_refill(delta)
			"asphalt":
				_tick_asphalt(delta)
	if _rebuilding:
		_tick_crew_tasks()
	elif running and work_paused() and step_id() != "pipe":
		_set_status("Arbeit pausiert – " + ("die Absperrung wird gleich umgebaut." if crew_present() else "Kolonnenbus schicken, die Kolonne baut die Absperrung um."))
	_redispatch_t += delta
	if _redispatch_t > 2.0:
		_redispatch_t = 0.0
		if step_id() == "demob":
			_check_demob()
		_redispatch_waiting()
		if build_when_ready and not running and step_id() == "closure" and _can_closure() == "":
			do_action("closure")
		if _pending_plan != null and _safe_for_rebuild():
			var pp := _pending_plan
			_pending_plan = null
			set_plan(pp, true)
		if rebuild and not _rebuilding and crew_present():
			_start_rebuild()
		if auto_continue and not running:
			_auto_step()


func _auto_step() -> void:
	if running:
		return
	for a in actions():
		if a.enabled and a.id != "demob" and a.id != "plan":
			do_action(a.id)
			return
	if step_id() == "demob" and not _machines_on_site().is_empty():
		_demob_send_home(false)


## Sends the machines home. An empty low-loader on site picks up the excavator instead.
func _demob_send_home(all: bool) -> void:
	var ex0 := _excavator()
	var lowbed_waiting := vehicles.any(func(o): return is_instance_valid(o) and role(o) == "lowbed" and o.cargo.machine == null and (ex0 == null or o.can_carry(ex0)))
	for v in _machines_on_site():
		if role(v) == "lowbed" or v.state == "loading" or v.carried_by != null:
			continue
		if role(v) == "dig" and lowbed_waiting:
			continue
		if all or in_place.has(v) or spot_of.get(v, "") == "stage":
			v.drive_to_hq()


func remove_site() -> void:
	if traffic_on:
		_traffic_deactivate()
	for v in vehicles.duplicate():
		if is_instance_valid(v):
			release_vehicle(v)
	terrain.set_hole(jm.pit_slot_of(self), false)


func save_state() -> Dictionary:
	var placed := []
	for n in item_nodes:
		placed.append(n != null)
	return {"phase": phase, "placed": placed, "yellow": yellow_frac, "yellow_fracs": yellow_fracs.duplicate(),
		"plan": plan.to_dict() if plan.custom else {}, "plan_ok": plan_confirmed, "plan_build": build_when_ready,
		"kit": kit_used, "orphans": _orphans_state(), "terrain": terrain.save_state(),
		"pile_mat": pile_mat, "pile_m3": pile_m3, "needs": needs, "layer": layer, "auto": auto_continue,
		"pipe_old": pipe_old != null, "pipe_new": pipe_new != null,
		"rebuild": rebuild or _rebuilding, "plan_pending": _pending_plan.to_dict() if _pending_plan else {}}


func load_state(d: Dictionary) -> void:
	phase = d.get("phase", 0)
	var pd: Dictionary = d.get("plan", {})
	if not pd.is_empty():
		plan = ClosurePlan.from_dict(pd)
		_apply_plan()
	var placed: Array = d.get("placed", [])
	plan_confirmed = bool(d.get("plan_ok", placed.has(true) or phase > 1))
	build_when_ready = bool(d.get("plan_build", false))
	kit_used = bool(d.get("kit", placed.has(true) or (phase > 1 and phase < 8)))
	for o in d.get("orphans", []):
		var oa: Array = o
		if oa.size() >= 4 and ClosurePlan.KINDS.has(str(oa[0])):
			var on := SiteProps.item(str(oa[0]))
			add_child(on)
			on.global_transform = Transform3D(Basis(Vector3.UP, float(oa[3])), gw(Vector2(float(oa[1]), float(oa[2])), 0.05))
			_orphans.append(on)
	for i in mini(placed.size(), item_defs.size()):
		if placed[i]:
			var df: Dictionary = item_defs[i]
			var node := SiteProps.item(df.kind, df.phase)
			add_child(node)
			node.global_transform = Transform3D(Basis(Vector3.UP, df.yaw), gw(df.pos, 0.05))
			item_nodes[i] = node
	var yf: Array = d.get("yellow_fracs", [])
	for i in yellow_fracs.size():
		yellow_fracs[i] = float(yf[i]) if i < yf.size() else float(d.get("yellow", 0.0))
	_update_yellow()
	if _traffic_should_be_on():
		_traffic_activate()
	terrain.load_state(d.get("terrain", {}))
	if phase >= 2:
		terrain.set_hole(jm.pit_slot_of(self), true)
	if phase >= 1:
		_build_spray()
	pile_mat = d.get("pile_mat", "")
	pile_m3 = d.get("pile_m3", 0.0)
	_pile_base = pile_m3
	_update_pile()
	needs = d.get("needs", [])
	for n in needs:
		n["ordered"] = 0.0
	layer = d.get("layer", 0)
	auto_continue = d.get("auto", false)
	# a closure change during the works (#21): the crew picks it up again when it is on site
	rebuild = bool(d.get("rebuild", false))
	var ppd: Dictionary = d.get("plan_pending", {})
	if not ppd.is_empty():
		_pending_plan = ClosurePlan.from_dict(ppd)
	if not d.get("pipe_old", true) and pipe_old:
		pipe_old.queue_free()
		pipe_old = null
	if d.get("pipe_new", false):
		pipe_new = SiteProps.pipe("new", job.length - 0.3, job.pipe_d)
		add_child(pipe_new)
		var c := lay.trench_center()
		pipe_new.global_transform = Transform3D(Basis(Vector3.UP, SiteLayout.yaw_of(lay.trench_dir())), gw(c, SiteTerrain.Y_ROAD - job.depth + 0.05))


## Called by World after vehicles are re-attached to the loaded site.
func post_load() -> void:
	# material that is on the trucks counts as ordered
	for v in vehicles:
		if is_instance_valid(v) and role(v) == "bulk" and v.bulk_m3() > 0.05:
			for n in needs:
				if n.mat == v.bulk_main():
					n["ordered"] = n.get("ordered", 0.0) + v.bulk_m3()
					_orders[v] = [n, v.bulk_m3()]
					break
	match step_id():
		"closure":
			_set_status("Kolonnenbus mit Absperrmaterial schicken und Absperrung aufbauen.")
		"demob":
			_check_demob()
		_:
			_after_phase_change()


## After acceptance: drop everything heavy but keep the node alive for late vehicle callbacks.
func retire() -> void:
	retired = true
	running = false
	for c in get_children():
		c.queue_free()
	process_mode = Node.PROCESS_MODE_DISABLED
	vehicles.clear()
	spot_of.clear()
	in_place.clear()
	needs.clear()
