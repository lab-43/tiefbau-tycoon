class_name Vehicle
extends Node3D
## A company vehicle or machine. Drives through the traffic simulation (shared with traffic), handles its
## lights, carries cargo and runs the articulated parts (excavator arm, tipper body, lowbed ramp).

signal arrived(v: Vehicle)

const TANK_L := {"transport": 300.0, "machine": 350.0}
const LIGHT_SUFFIX := {"__light_head": "head", "__light_tail": "tail", "__light_brake": "brake", "__indicator_l": "ind_l",
	"__indicator_r": "ind_r", "__light_reverse": "reverse", "__worklight": "work"}
const LIGHT_COLOR := {"head": Color(1.0, 0.95, 0.85), "tail": Color(1.0, 0.04, 0.02), "brake": Color(1.0, 0.04, 0.02),
	"ind_l": Color(1.0, 0.48, 0.0), "ind_r": Color(1.0, 0.48, 0.0), "reverse": Color(1.0, 1.0, 1.0),
	"work": Color(1.0, 0.98, 0.92), "beacon": Color(1.0, 0.3, 0.0)}
# LED beacons: bursts of 2 or 3 short flashes per cycle; the 2nd beacon of a pair runs half a cycle later
const FLASH_ON := 0.06
const FLASH_GAP := 0.07
const FLASH_CYCLE := 0.8
const BEACON_GLOW := 1.4       # emission while flashing; AgX turns much more into white-yellow
const BEACON_LAYER := 1 << 19  # render layer 20: beacon meshes, not lit by their own flash light
const BEACON_GLASS := Color(0.78, 0.27, 0.02, 0.85)   # amber dome, also visible while dark
const ROOF_BEACON_X := 0.45    # lateral offset of the roof beacons the game mounts itself (crew van)

var def_id := ""
var def: Dictionary = {}
var meta: Dictionary = {}
var vname := ""
var plate := ""
var model: Node3D
var trailer: Node3D
var trailer_meta := {}
var world: World
var agent: Agent
var state := "parked"          # parked | driving | waiting | working | loading | on_trailer
var status_text := "Abgestellt"
var dest_text := ""
var odometer_km := 0.0
var op_hours := 0.0
var fuel := 1.0
var condition := 1.0
var purchase_day := 1
var cargo := {"bulk": {}, "barriers": 0, "pipes_new": 0, "pipes_old": 0, "machine": null}
var crew_aboard := 0
var slot := -1
var site = null                # Site this vehicle is assigned to
var site_spot := ""            # spot id at the site ("van", "machine", "load", "stage", ...)
var carried_by: Vehicle = null
var light_mode := {"low": "auto", "beacon": "auto", "hazard": false, "work": false, "flash": "2"}
var auto_shuttle := true       # tipper: automatic haul trips for its site
var working := false
var reversing := false
var speed := 0.0
var selected := false
var on_arrive: Callable = Callable()
# geometry (vehicle frame, metres): front/rear extents from the origin
var front_ext := 2.5
var rear_ext := 2.5
var half_w := 1.1
var height := 3.0
# articulated parts
var rig: ExcavatorRig
var hyd: Array = []
var tip_deg := 0.0
var ramp_slide := 0.0
var ramp_deg := 0.0
var _tipper_body: Node3D
var _tailgate: Node3D
var _tipper_rest := Basis()
var _tailgate_rest := Basis()
var _ramp_slide_node: Node3D
var _ramp_node: Node3D
var _ramp_slide_rest := Vector3.ZERO
var _ramp_rest := Basis()
var _load_node: MeshInstance3D
var _load_box := AABB()
var _pipes_vis: Array = []
# lights
var _lmats := {}               # type -> Array[BaseMaterial3D]
var _lval := {}                # type -> last energy
var _spots: Array = []
var _work_spots: Array = []
var _beacons: Array = []       # [{key, node, mats: Array[BaseMaterial3D], light: OmniLight3D, offset, lit}]
var _flash_phase := randf() * FLASH_CYCLE
var beacon_freeze := -1        # tests/screenshots: -1 flash pattern, 0 always dark, 1 always lit
var low_on := false
var beacon_on := false
var work_on := false
# motion bookkeeping
var _wheels: Array = []        # [node, radius, steer, rest_basis]
var _wheel_angle := 0.0
var _steer := 0.0
var _body: StaticBody3D
var _sel_ring: MeshInstance3D
var _last_pos := Vector3.ZERO
var _yaw := 0.0
var _trailer_axle := Vector2.ZERO
var _trailer_len := 11.0
var _blink_t := 0.0
var _man_obs_id := -1
var _pending: Dictionary = {}  # maneuver waiting for a clear road: {pieces, s0, obs, label, cb}
var _pending_t := 0.0
static var _next_obs := 5000


func setup(w: World, id: String, display_name: String, plate_no: String) -> void:
	world = w
	def_id = id
	def = Balance.vehicle(id)
	vname = display_name
	plate = plate_no
	purchase_day = Clock.day
	var model_id: String = def.get("model", id)
	meta = VehicleModels.load_meta(model_id)
	model = VehicleModels.instance(model_id, def)
	model.name = "Model"
	add_child(model)
	if def.has("trailer"):
		trailer = VehicleModels.instance(def.trailer, def)
		trailer.name = "Trailer_" + plate_no.replace(" ", "_")
		trailer_meta = VehicleModels.load_meta(def.trailer)
		w.fleet.add_child(trailer)
		trailer.top_level = true
		var kp := RigUtil.find(trailer, "kingpin")
		var hitch_z := kp.position.z if kp else -11.5
		_trailer_len = absf(hitch_z) + 2.5
	_compute_extents()
	_collect_parts()
	_setup_lights()
	_build_pick_body()
	_build_selection_ring()
	_setup_rigs()
	_man_obs_id = _next_obs
	_next_obs += 1


func _compute_extents() -> void:
	var bmin: Array = meta.get("bbox_min", [])
	var bmax: Array = meta.get("bbox_max", [])
	if bmin.size() == 3 and bmax.size() == 3:
		front_ext = -float(bmin[2])
		rear_ext = float(bmax[2])
		half_w = maxf(absf(float(bmin[0])), float(bmax[0]))
		height = float(bmax[1])
	else:
		var L: float = def.get("length", 5.0)
		front_ext = L * 0.5
		rear_ext = L * 0.5
		half_w = def.get("width", 2.2) * 0.5
		height = def.get("height", 3.0)
	if has_ability("dig"):
		# the arm sticks out in the rest pose; use the undercarriage for spacing
		var wf := RigUtil.find(model, "wheel_fl")
		front_ext = (-wf.position.z + 0.9) if wf else 2.2
	half_w = minf(half_w, 1.35)


func _collect_parts() -> void:
	_wheels.clear()
	for root in [model, trailer]:
		if root == null:
			continue
		for n in root.find_children("wheel_*", "Node3D", true, false):
			var nm := String(n.name)
			var r := 0.5
			var steer := nm == "wheel_fl" or nm == "wheel_fr"
			var md: Dictionary = meta if root == model else trailer_meta
			for wd in md.get("wheels", []):
				if wd.get("node", "") == nm:
					r = float(wd.get("radius", 0.5))
					steer = bool(wd.get("steer", steer))
			if root == trailer:
				r = 0.41
				steer = false
			_wheels.append([n, r, steer and root == model, (n as Node3D).basis])


func part(name: String) -> Node3D:
	return RigUtil.find(model, name)


func has_ability(a: String) -> bool:
	return a in def.get("abilities", [])


func category() -> String:
	return def.get("category", "transport")


func is_machine() -> bool:
	return category() == "machine"


func kind_slot() -> String:
	if def_id == "tractor_lowbed":
		return "lowbed"
	if front_ext + rear_ext > 7.5:
		return "truck"
	return "small"


# ------------------------------------------------------------------------------------------
# Lights
# ------------------------------------------------------------------------------------------

func _setup_lights() -> void:
	for t in LIGHT_COLOR:
		_lmats[t] = []
		_lval[t] = -1.0
	# the crew van model has no beacons: mount two on the front of its roof (before the material scan)
	if def_id == "van_crew" and model.find_children("beacon_*", "Node3D", true, false).is_empty():
		_mount_roof_beacons()
	for root in [model, trailer]:
		if root == null:
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				var m := m3.get_active_material(si)
				if m == null:
					continue
				var nm := m.resource_name
				var t := ""
				for suf in LIGHT_SUFFIX:
					if nm.ends_with(suf):
						t = LIGHT_SUFFIX[suf]
				if nm.begins_with("RotLight_ReflectorGlass"):
					t = "beacon"
				if t == "" or not (m is BaseMaterial3D):
					continue
				var dm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				dm.emission_enabled = true
				dm.emission = LIGHT_COLOR[t]
				dm.emission_energy_multiplier = 0.0
				m3.set_surface_override_material(si, dm)
				if t == "beacon":
					dm.albedo_color = BEACON_GLASS
					_beacon_of(m3, root).mats.append(dm)
				else:
					_lmats[t].append(dm)
	# headlight beams
	for n in model.find_children("light_head_*", "Node3D", true, false):
		var sp := SpotLight3D.new()
		sp.spot_range = 34.0
		sp.spot_angle = 30.0
		sp.spot_attenuation = 0.8
		sp.light_energy = 0.0
		sp.light_color = Color(1.0, 0.94, 0.82)
		sp.shadow_enabled = false
		sp.rotation.x = deg_to_rad(-7.0)
		n.add_child(sp)
		_spots.append(sp)
	for n in model.find_children("worklight_*", "Node3D", true, false):
		if _work_spots.size() >= 3:
			break
		var wl := SpotLight3D.new()
		wl.spot_range = 20.0
		wl.spot_angle = 60.0
		wl.light_energy = 0.0
		wl.light_color = Color(1.0, 0.97, 0.9)
		wl.rotation.x = deg_to_rad(-30.0)
		n.add_child(wl)
		_work_spots.append(wl)
	# procedural models: emissive blobs at the markers
	if model.get_meta("source", "") == "procedural":
		var mk := {"light_head_": "head", "light_tail_": "tail", "indicator_fl": "ind_l", "indicator_rl": "ind_l",
			"indicator_fr": "ind_r", "indicator_rr": "ind_r", "beacon_": "beacon"}
		for n in model.find_children("*", "Node3D", true, false):
			for pre in mk:
				if String(n.name).begins_with(pre):
					var t2: String = mk[pre]
					var mi2 := MeshInstance3D.new()
					var b := BoxMesh.new()
					b.size = Vector3(0.22, 0.14, 0.06)
					mi2.mesh = b
					var bm2 := StandardMaterial3D.new()
					bm2.albedo_color = LIGHT_COLOR[t2] * 0.4
					bm2.emission_enabled = true
					bm2.emission = LIGHT_COLOR[t2]
					bm2.emission_energy_multiplier = 0.0
					mi2.material_override = bm2
					n.add_child(mi2)
					if t2 == "beacon":
						bm2.albedo_color = BEACON_GLASS
						_beacon_of(n, model).mats.append(bm2)
					else:
						_lmats[t2].append(bm2)
	# LED flash beacons: one light per beacon of the vehicle itself (max 2), trailers only glow
	var lights := 0
	for i in _beacons.size():
		var b: Dictionary = _beacons[i]
		b.offset = 0.5 * FLASH_CYCLE if i % 2 == 1 else 0.0
		# the flash light sits right inside the dome: it must not light the dome and reflector itself
		# (that washed them out to white), so they live on their own render layer
		var bn: Node3D = b.node
		for mi in bn.find_children("*", "MeshInstance3D", true, false) + ([bn] if bn is MeshInstance3D else []):
			(mi as MeshInstance3D).layers = BEACON_LAYER
		if lights < 2 and model.is_ancestor_of(b.node):
			var ol := OmniLight3D.new()
			ol.omni_range = 9.0
			ol.omni_attenuation = 1.4
			ol.light_color = LIGHT_COLOR.beacon
			ol.light_energy = 0.0
			ol.light_cull_mask = 0xFFFFF & ~BEACON_LAYER
			ol.shadow_enabled = false
			ol.position.y = 0.7    # above the dome: lights the surroundings, no hot spot on the own roof
			(b.node as Node3D).add_child(ol)
			b.light = ol
			lights += 1


## Groups beacon materials by the beacon they belong to: the ancestor named beacon_<n>[_…] below root.
func _beacon_of(n: Node, root: Node3D) -> Dictionary:
	var key := ""
	var holder: Node3D = n as Node3D
	var p: Node = n
	while p != null and p != root:
		var nm := String(p.name)
		if nm.begins_with("beacon_"):
			key = "%s/beacon_%s" % [root.name, nm.get_slice("_", 1)]
			holder = p as Node3D
		p = p.get_parent()
	if key == "":
		key = "%s/%s" % [root.name, n.name]
	for b in _beacons:
		if b.key == key:
			return b
	var nb := {"key": key, "node": holder, "mats": [], "light": null, "offset": 0.0, "lit": false}
	_beacons.append(nb)
	return nb


func _mount_roof_beacons() -> void:
	var mounts := VehicleModels.roof_mounts(String(def.get("model", def_id)), model, [-ROOF_BEACON_X, ROOF_BEACON_X])
	for i in mounts.size():
		var bb := VehicleModels.beacon_body()
		bb.name = "beacon_%d_body" % (i + 1)
		bb.position = mounts[i]
		model.add_child(bb)


## Beacon mount points in vehicle space (for tests: each must sit on the model's surface).
func beacon_nodes() -> Array:
	var out: Array = []
	for b in _beacons:
		if model.is_ancestor_of(b.node):
			out.append(b.node)
	return out


## True while an LED beacon running the n-flash pattern is lit at time t (seconds).
static func flash_lit(t: float, n: int) -> bool:
	var ph := fposmod(t, FLASH_CYCLE)
	var k := int(ph / (FLASH_ON + FLASH_GAP))
	return k < n and ph - k * (FLASH_ON + FLASH_GAP) < FLASH_ON


func _update_beacons(night: float) -> void:
	var n := 3 if str(light_mode.get("flash", "2")) == "3" else 2
	var now := Time.get_ticks_msec() * 0.001 + _flash_phase   # real time: same rhythm at every game speed
	for b in _beacons:
		var lit: bool = beacon_on and flash_lit(now + float(b.offset), n)
		if beacon_freeze >= 0:
			lit = beacon_freeze == 1
		if lit == b.lit:
			continue
		b.lit = lit
		for m in b.mats:
			(m as BaseMaterial3D).emission_energy_multiplier = BEACON_GLOW if lit else 0.0
		if b.light:
			(b.light as OmniLight3D).light_energy = (0.1 + night * 0.4) if lit else 0.0


func _set_light(t: String, v: float) -> void:
	if absf(_lval.get(t, -1.0) - v) < 0.01:
		return
	_lval[t] = v
	for m in _lmats.get(t, []):
		(m as BaseMaterial3D).emission_energy_multiplier = v


func _update_lights(delta: float) -> void:
	_blink_t += delta
	var night: float = world.day_night.night if world and world.day_night else 0.0
	var driving := state == "driving"
	var active := driving or state == "working" or state == "loading" or working
	match light_mode.low:
		"on":
			low_on = true
		"off":
			low_on = false
		_:
			low_on = active and night > 0.2
	match light_mode.beacon:
		"on":
			beacon_on = true
		"off":
			beacon_on = false
		_:
			beacon_on = working or state == "working" or state == "loading" or (site != null and state != "parked") \
				or (driving and (is_machine() or cargo.machine != null))
	work_on = light_mode.work or (night > 0.3 and (working or state == "working"))
	_set_light("head", (2.2 if low_on else (0.35 if driving else 0.0)))
	for sp in _spots:
		sp.light_energy = 2.4 if low_on else 0.0
	var brake := agent != null and agent.braking and driving
	var has_brake: bool = not _lmats.brake.is_empty()
	var tail := 1.2 if low_on else (0.4 if driving else 0.0)
	if has_brake:
		_set_light("tail", tail)
		_set_light("brake", 3.0 if brake else 0.0)
	else:
		_set_light("tail", 3.0 if brake else tail)
	_set_light("reverse", 2.5 if (reversing and (driving or state == "loading")) else 0.0)
	var blink := fmod(_blink_t, 0.8) < 0.4
	var turn := agent.turn_signal if (agent and driving and not reversing) else 0
	var left_on: bool = light_mode.hazard or turn < 0
	var right_on: bool = light_mode.hazard or turn > 0
	_set_light("ind_l", 3.0 if (left_on and blink) else 0.0)
	_set_light("ind_r", 3.0 if (right_on and blink) else 0.0)
	_set_light("work", 3.0 if work_on else 0.0)
	for wl in _work_spots:
		wl.light_energy = 3.2 if work_on else 0.0
	_update_beacons(night)


# ------------------------------------------------------------------------------------------
# Picking, selection
# ------------------------------------------------------------------------------------------

func _build_pick_body() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 0b10
	_body.collision_mask = 0
	_body.set_meta("owner_obj", self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(half_w * 2.0 + 0.4, height, front_ext + rear_ext + 0.4)
	cs.shape = bs
	cs.position = Vector3(0, height * 0.5, (rear_ext - front_ext) * 0.5)
	_body.add_child(cs)
	add_child(_body)
	if trailer:
		var tb := StaticBody3D.new()
		tb.collision_layer = 0b10
		tb.collision_mask = 0
		tb.set_meta("owner_obj", self)
		var cs2 := CollisionShape3D.new()
		var bs2 := BoxShape3D.new()
		bs2.size = Vector3(3.0, 2.6, 20.0)
		cs2.shape = bs2
		cs2.position = Vector3(0, 1.3, -3.4)
		tb.add_child(cs2)
		trailer.add_child(tb)


func _build_selection_ring() -> void:
	_sel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	var L := maxf(front_ext, rear_ext)
	tm.inner_radius = L + 0.5
	tm.outer_radius = L + 0.8
	tm.rings = 48
	tm.ring_segments = 4
	_sel_ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = UI.ACCENT
	m.emission_enabled = true
	m.emission = UI.ACCENT
	m.emission_energy_multiplier = 1.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_ring.material_override = m
	_sel_ring.position = Vector3(0, 0.12, (rear_ext - front_ext) * 0.5)
	_sel_ring.scale = Vector3(1, 0.05, 1)
	_sel_ring.visible = false
	_sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sel_ring)


func set_selected(v: bool) -> void:
	selected = v
	_sel_ring.visible = v


# ------------------------------------------------------------------------------------------
# Articulated parts: excavator rig, tipper, lowbed ramp, load visuals
# ------------------------------------------------------------------------------------------

func _setup_rigs() -> void:
	if has_ability("dig") and model.get_meta("source", "") == "glb":
		rig = ExcavatorRig.new()
		rig.setup(self, model, meta)
		if not rig.ok:
			rig = null
	else:
		hyd = RigUtil.setup_hydraulics(model, meta)
	_tipper_body = part("tipper_body")
	if _tipper_body:
		_tipper_rest = _tipper_body.basis
		_tailgate = part("tailgate")
		if _tailgate:
			_tailgate_rest = _tailgate.basis
		_load_box = RigUtil.local_aabb(_tipper_body)
		_load_node = MeshInstance3D.new()
		_load_node.mesh = RigUtil.mound_mesh()
		_load_node.visible = false
		_tipper_body.add_child(_load_node)
	if trailer:
		_ramp_slide_node = RigUtil.find(trailer, "ramp_slide")
		_ramp_node = RigUtil.find(trailer, "ramp")
		if _ramp_slide_node:
			_ramp_slide_rest = _ramp_slide_node.position
		if _ramp_node:
			_ramp_rest = _ramp_node.basis
	update_load_visual()


func set_tip(deg: float) -> void:
	tip_deg = clampf(deg, 0.0, 47.0)
	if _tipper_body:
		_tipper_body.basis = _tipper_rest * Basis(Vector3.RIGHT, deg_to_rad(tip_deg))
		if _tailgate:
			_tailgate.basis = _tailgate_rest * Basis(Vector3.RIGHT, deg_to_rad(-clampf(tip_deg * 1.1, 0.0, 60.0)))
		RigUtil.update_hydraulics(hyd)


func set_ramp(slide_m: float, deg: float) -> void:
	ramp_slide = clampf(slide_m, 0.0, 4.68)
	ramp_deg = clampf(deg, 0.0, 20.0)
	if _ramp_slide_node:
		_ramp_slide_node.position = _ramp_slide_rest + Vector3(0, 0, ramp_slide)
	if _ramp_node:
		_ramp_node.basis = _ramp_rest * Basis(Vector3.RIGHT, deg_to_rad(ramp_deg))


func tween_tip(to_deg: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_method(set_tip, tip_deg, to_deg, dur).set_trans(Tween.TRANS_SINE)
	return tw


func tween_ramp(slide_to: float, deg_to: float, dur: float) -> Tween:
	var tw := create_tween()
	var s0 := ramp_slide
	var d0 := ramp_deg
	tw.tween_method(func(t): set_ramp(lerpf(s0, slide_to, t), lerpf(d0, deg_to, t)), 0.0, 1.0, dur)
	return tw


func update_load_visual() -> void:
	if _load_node:
		var m3 := bulk_m3()
		_load_node.visible = m3 > 0.05
		if _load_node.visible:
			var cap := maxf(1.0, bulk_capacity())
			var f := clampf(m3 / cap, 0.0, 1.0)
			var box := _load_box
			var inner := Vector3(box.size.x - 0.35, box.size.y - 0.2, box.size.z - 0.4)
			var lf := clampf(0.35 + f * 0.65, 0.2, 1.0)
			_load_node.scale = Vector3(inner.x, maxf(0.05, inner.y * 0.95 * sqrt(f)), inner.z * lf)
			_load_node.position = Vector3(box.get_center().x, box.position.y + 0.15, box.get_center().z - inner.z * (1.0 - lf) * 0.5)
			_load_node.material_override = RigUtil.bulk_material(bulk_main())
	if has_ability("pipes"):
		var want: int = int(cargo.pipes_new) + int(cargo.pipes_old)
		while _pipes_vis.size() > want:
			(_pipes_vis.pop_back() as Node3D).queue_free()
		var idx := 0
		for kind in ["new", "old"]:
			var n: int = cargo.pipes_new if kind == "new" else cargo.pipes_old
			for k in n:
				if idx >= _pipes_vis.size():
					var p := SiteProps.pipe(kind, 4.0, 0.4)
					model.add_child(p)
					_pipes_vis.append(p)
				var pn: Node3D = _pipes_vis[idx]
				pn.position = Vector3(-0.5 + (idx % 3) * 0.5, 1.22 + (idx / 3) * 0.42, 0.5)
				idx += 1


# ------------------------------------------------------------------------------------------
# Placement and posing
# ------------------------------------------------------------------------------------------

func place(pos: Vector3, yaw: float) -> void:
	position = Vector3(pos.x, 0.0, pos.z)
	rotation = Vector3(0.0, yaw, 0.0)
	_yaw = yaw
	_last_pos = position
	if trailer:
		var fw := Vector2(-sin(yaw), -cos(yaw))
		_trailer_axle = _hitch_point() - fw * _trailer_len
		_update_trailer()


func forward2() -> Vector2:
	return Vector2(-sin(rotation.y), -cos(rotation.y))


func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func point_ahead(d: float) -> Vector2:
	return pos2() + forward2() * d


func _hitch_point() -> Vector2:
	var fw := part("fifth_wheel")
	if fw == null:
		fw = part("fifth")
	var lp := fw.position if fw else Vector3(0, 1.2, 1.2)
	var p := transform * lp
	return Vector2(p.x, p.z)


func _update_trailer() -> void:
	if trailer == null:
		return
	var hitch := _hitch_point()
	var d := hitch - _trailer_axle
	var dl := d.length()
	if dl > 0.001:
		_trailer_axle = hitch - d / dl * _trailer_len
	var dir := (hitch - _trailer_axle).normalized()
	var yaw := atan2(-dir.x, -dir.y)
	var kp := RigUtil.find(trailer, "kingpin")
	var kp_local := kp.position if kp else Vector3(0, 1.25, -11.5)
	var basis := Basis(Vector3.UP, yaw)
	var origin := Vector3(hitch.x, 0.0, hitch.y) - basis * Vector3(kp_local.x, 0.0, kp_local.z)
	trailer.global_transform = Transform3D(basis, origin)


func apply_agent_pose(ag: Agent, alpha: float) -> void:
	var p: Vector3 = ag.p_prev.lerp(ag.p_cur, alpha)
	p.y = 0.0
	position = p
	rotation.y = lerp_angle(ag.yaw_prev, ag.yaw_cur, alpha)
	speed = ag.v


func _process(delta: float) -> void:
	if carried_by == null:
		var moved := position.distance_to(_last_pos)
		if moved > 0.0001 and moved < 50.0:
			odometer_km += moved / 1000.0
			var dir := position - _last_pos
			var fwd3 := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
			var sgn := 1.0 if dir.dot(fwd3) >= 0.0 else -1.0
			_wheel_angle += sgn * moved
			var dyaw := wrapf(rotation.y - _yaw, -PI, PI)
			var target_steer := clampf(dyaw / maxf(0.02, moved) * 2.6 * sgn, -0.6, 0.6)
			_steer = lerpf(_steer, target_steer, 0.25)
			fuel = maxf(0.0, fuel - moved / 1000.0 * float(def.get("fuel_l_100km", 25.0)) / 100.0 / TANK_L.get(category(), 300.0))
		else:
			_steer = lerpf(_steer, 0.0, 0.05)
		_yaw = rotation.y
		_last_pos = position
	if delta > 0.0 and (state == "working" or working):
		op_hours += delta * Clock.GAME_SECONDS_PER_REAL_SECOND / 3600.0
		fuel = maxf(0.0, fuel - delta * Clock.GAME_SECONDS_PER_REAL_SECOND / 3600.0 * float(def.get("op_l_h", 4.0)) / TANK_L.get(category(), 300.0))
	for w in _wheels:
		var n: Node3D = w[0]
		var r: float = w[1]
		var rb: Basis = w[3]
		var spin := Basis(Vector3.RIGHT, -_wheel_angle / r)
		if w[2]:
			n.basis = Basis(Vector3.UP, _steer) * rb * spin
		else:
			n.basis = rb * spin
	if trailer:
		_update_trailer()
	if cargo.machine != null:
		var m: Vehicle = cargo.machine
		if m.carried_by == self:
			m.global_transform = deck_transform()
	if rig:
		rig.update(delta)
	if not _pending.is_empty():
		_pending_t += delta
		if _road_clear(_pending.obs) or _pending_t > 25.0:
			var p: Dictionary = _pending
			_pending = {}
			_launch(p.pieces, p.s0, p.label, p.cb)
	_update_lights(delta)


# ------------------------------------------------------------------------------------------
# Driving
# ------------------------------------------------------------------------------------------

func is_busy() -> bool:
	return state == "working" or state == "loading" or carried_by != null


func can_drive() -> bool:
	if carried_by != null:
		Events.warn("%s steht auf dem Tieflader – erst abladen" % vname)
		return false
	if state == "loading":
		Events.warn("%s wird gerade be- oder entladen" % vname)
		return false
	return true


## Core driving request.
## dest: {key, s} where the road part ends ({} = no road part); tail: pieces appended after the road part;
## pre: pieces that start at the current pose (replaces the automatic way onto the road; start_lane = where pre ends);
## obs: {key, s0, s1} lane range blocked for traffic (and waited on until clear) before moving.
func drive_plan(dest: Dictionary, label: String, tail: Array = [], cb: Callable = Callable(), pre: Array = [], obs: Dictionary = {}, start_lane: Dictionary = {}) -> bool:
	if not can_drive():
		return false
	var leaving_site = site if (site and (state == "working" or (site.in_place.has(self)))) else null
	working = false
	var router := world.router
	var pieces: Array = []
	var start := {}
	if pre.is_empty():
		start = _start_point()
		if start.has("blocked"):
			return false
		if start.is_empty() and not dest.is_empty():
			Events.warn("%s findet keine Straße" % vname)
			return false
		if not start.is_empty():
			pieces = start.pre.duplicate()
			if start.has("obs") and obs.is_empty():
				obs = start.obs
	else:
		_free_slot()
		_drop_agent()
		pieces = pre.duplicate()
		start = start_lane
	if not dest.is_empty():
		var plan := []
		if start.is_empty():
			Events.warn("%s findet keine Straße" % vname)
			return false
		if start.key == dest.key and dest.s >= start.s - 0.01:
			if dest.s - start.s > 0.05:
				plan = [router.lane_piece(start.key, start.s, dest.s)]
		else:
			plan = router.plan(start.key, start.s, dest.key, dest.s, _avoid_edges())
			if plan.is_empty():
				Events.warn("%s: keine Route nach %s gefunden" % [vname, label])
				status_text = "Keine Route"
				state = "parked"
				Events.vehicle_changed.emit(self)
				return false
		var first_lane := true
		for pc in plan:
			for ep in world.traffic.expand_detours(pc):
				if first_lane and ep.t == Agent.LANE and not pieces.is_empty():
					ep.tag = "clear"
					first_lane = false
				pieces.append(ep)
	pieces.append_array(tail)
	if leaving_site and is_instance_valid(leaving_site):
		leaving_site.on_vehicle_leaving(self)
	if pieces.is_empty():
		_arrive(label, cb)
		return true
	var s0: float = pieces[0].s0
	if start.has("s0"):
		s0 = start.s0
	if not obs.is_empty():
		world.traffic.set_obstacle(obs.key, obs.s0, obs.s1, _man_obs_id)
		if not _road_clear(obs):
			_pending = {"pieces": pieces, "s0": s0, "obs": obs, "label": label, "cb": cb}
			_pending_t = 0.0
			state = "waiting"
			status_text = "Wartet auf freie Fahrbahn"
			Events.vehicle_changed.emit(self)
			return true
	_launch(pieces, s0, label, cb)
	if start.has("v0") and agent:
		agent.v = start.v0
	return true


func _launch(pieces: Array, s0: float, label: String, cb: Callable) -> void:
	_start_agent(pieces, s0)
	reversing = pieces[0].get("rev", false)
	dest_text = label
	status_text = "Fährt nach " + label
	on_arrive = cb
	state = "driving"
	Events.vehicle_changed.emit(self)


func _road_clear(obs: Dictionary) -> bool:
	if obs.is_empty():
		return true
	return world.traffic.lane_clear(obs.key, obs.s0, obs.s1, agent)


func _avoid_edges() -> Dictionary:
	var av := {}
	if not def.get("road_legal", true):
		for ei in world.net.edges.size():
			if world.net.edges[ei].cls in ["motorway", "trunk", "motorway_link", "trunk_link"]:
				av[ei] = true
	return av


## Drive to a world position on the road network and pull over there.
func drive_to(target: Vector3, label: String, cb: Callable = Callable()) -> bool:
	var dest := world.router.nearest_lane(Vector2(target.x, target.z), 150.0, func(k): return _lane_ok(k))
	if dest.is_empty():
		Events.warn("Ziel nicht erreichbar")
		return false
	var key: int = dest.key
	var ln := world.router.lane_len(key)
	var s: float = clampf(dest.s, 2.0, maxf(2.0, ln - 14.0))
	var tail := [pull_over_piece(key, s)]
	return drive_plan({"key": key, "s": s}, label, tail, cb)


func pull_over_piece(key: int, s: float, lateral := 2.2, length := 12.0) -> Dictionary:
	var g: Array = world.net.lane_geo[key]
	var ln := world.router.lane_len(key)
	var pts := PackedVector2Array()
	var n := 12
	for i in n + 1:
		var t := float(i) / n
		var ss := s + t * length
		var smp := Geo.sample(g[0], g[1], minf(ss, ln))
		var p: Vector2 = smp[0]
		var d: Vector2 = smp[1]
		if ss > ln:
			p += d * (ss - ln)
		var w := t * t * (3.0 - 2.0 * t)
		pts.append(p + Geo.right_of(d) * lateral * w)
	return Router.poly_piece(pts, 3.5)


func _lane_ok(key: int) -> bool:
	var e: Dictionary = world.net.edges[key >> 4]
	if (key >> 4) == world.traffic._hq_edge:
		return false
	if not def.get("road_legal", true) and e.cls in ["motorway", "trunk", "motorway_link", "trunk_link"]:
		return false
	return true


func drive_to_hq(cb: Callable = Callable()) -> bool:
	var old_site = site
	var ok := _drive_to_hq(cb)
	if ok and old_site and is_instance_valid(old_site) and site == old_site:
		old_site.release_vehicle(self)
	return ok


func _drive_to_hq(cb: Callable) -> bool:
	var arr := _hq_arrival_lane()
	if arr.is_empty():
		return drive_to(world.hq.gate_world(), "Zentrale", cb)
	var slot_i := slot if slot >= 0 else world.hq.free_slot(kind_slot())
	if world.hq.in_lot(pos2()) and state != "driving":
		# already in the yard: just park
		if slot_i >= 0:
			_free_slot()
			world.hq.slots[slot_i].used_by = self
			slot = slot_i
			place(world.hq.slots[slot_i].pos, world.hq.slots[slot_i].yaw)
		_arrive("Zentrale", cb)
		return true
	if slot_i < 0:
		return drive_plan(arr, "Zentrale", [], cb)
	var g: Array = world.net.lane_geo[arr.key]
	var end := Geo.sample(g[0], g[1], arr.s)
	var path := world.hq.arrival_path(slot_i, end[0], end[1])
	var ok := drive_plan(arr, "Zentrale", [Router.poly_piece(path, 3.5)], func(v):
		v._park_in_slot(slot_i)
		if cb.is_valid():
			cb.call(v))
	if ok:
		world.hq.slots[slot_i].used_by = self
		slot = slot_i
	return ok


func _park_in_slot(slot_i: int) -> void:
	slot = slot_i
	world.hq.slots[slot_i].used_by = self
	place(world.hq.slots[slot_i].pos, world.hq.slots[slot_i].yaw)


## Yard maneuver at HQ: reverse into a material bay. cb is called when the rear is at the bay.
func drive_to_bay(mat: String, cb: Callable) -> bool:
	var hq := world.hq
	if hq.in_lot(pos2()) and state != "driving":
		var bm := hq.bay_maneuver(mat, rear_ext, pos2(), forward2())
		var fwd := Router.poly_piece(bm.fwd, 3.0)
		var rev := Router.poly_piece(bm.rev, 1.6, true, "rev")
		rev["cusp"] = true
		_free_slot()
		return drive_plan({}, "Materiallager", [], func(v): v._bay_arrived(bm, cb), [fwd, rev])
	var arr := _hq_arrival_lane()
	if arr.is_empty():
		return false
	var g: Array = world.net.lane_geo[arr.key]
	var end := Geo.sample(g[0], g[1], arr.s)
	var bm2 := hq.bay_maneuver(mat, rear_ext, end[0], end[1])
	var fwd2 := Router.poly_piece(bm2.fwd, 3.5)
	var rev2 := Router.poly_piece(bm2.rev, 1.6, true, "rev")
	rev2["cusp"] = true
	return drive_plan(arr, "Materiallager", [fwd2, rev2], func(v): v._bay_arrived(bm2, cb))


func _bay_arrived(bm: Dictionary, cb: Callable) -> void:
	place(bm.pos, bm.yaw)
	if cb.is_valid():
		cb.call(self)


func _hq_arrival_lane() -> Dictionary:
	var net := world.net
	var hn: int = net.hq_node
	if hn < 0:
		return {}
	for er in net.nodes[hn].ends:
		var e: int = er >> 1
		var at_b: bool = (er & 1) == 1
		var dir := 0 if at_b else 1
		if net.lane_count(e, dir) > 0:
			var key := RoadNet.lane_key(e, dir, 0)
			return {"key": key, "s": world.router.lane_len(key)}
	return {}


func _hq_departure_lane() -> Dictionary:
	var net := world.net
	var hn: int = net.hq_node
	if hn < 0:
		return {}
	for er in net.nodes[hn].ends:
		var e: int = er >> 1
		var at_a: bool = (er & 1) == 0
		var dir := 0 if at_a else 1
		if net.lane_count(e, dir) > 0:
			return {"key": RoadNet.lane_key(e, dir, 0), "s": 0.0}
	return {}


func _smooth_join(p0: Vector2, d0: Vector2, target: Vector2, target_dir: Vector2) -> PackedVector2Array:
	var k := clampf(p0.distance_to(target) * 0.4, 1.0, 10.0)
	return HQ.bezier(p0, p0 + d0 * k, target - target_dir * k, target)


func _free_slot() -> void:
	if slot >= 0 and slot < world.hq.slots.size() and world.hq.slots[slot].used_by == self:
		world.hq.slots[slot].used_by = null
	slot = -1


func _drop_agent() -> void:
	if agent:
		world.traffic.remove_agent(agent)
		agent = null
	_pending = {}
	world.traffic.clear_obstacles(_man_obs_id)


## Where does the vehicle join the road network? Returns {key, s, pre: Array[piece], [obs], [s0], [v0]}.
func _start_point() -> Dictionary:
	var router := world.router
	# re-plan while driving on a lane: continue from the current lane position
	if agent and not agent.finished and state == "driving":
		var pc: Dictionary = agent.route[agent.pi]
		if pc.t == Agent.LANE and not pc.has("orig_s0"):
			var res := {"key": pc.key, "s": agent.s, "pre": [], "v0": agent.v, "s0": agent.s}
			_drop_agent()
			return res
	_drop_agent()
	var p := pos2()
	var fwd := forward2()
	# leaving a construction site: the site knows the way out
	if site and site.has_method("exit_plan"):
		var ex: Dictionary = site.exit_plan(self)
		if not ex.is_empty():
			_free_slot()
			return ex
	# leaving the HQ yard
	var hq := world.hq
	if hq.in_lot(p):
		var dep := _hq_departure_lane()
		if not dep.is_empty():
			_free_slot()
			var lane_pts: PackedVector2Array = world.net.lane_geo[dep.key][0]
			var lane_cum: PackedFloat32Array = world.net.lane_geo[dep.key][1]
			var join_s := minf(4.0, lane_cum[lane_cum.size() - 1] * 0.5)
			var lj := Geo.sample(lane_pts, lane_cum, join_s)
			var path := hq.departure_path(p, fwd)
			var gate_dir := -hq.normal
			path = HQ.join(path, _smooth_join(path[path.size() - 1], gate_dir, lj[0], lj[1]))
			return {"key": dep.key, "s": join_s, "pre": [Router.poly_piece(path, 4.0)]}
	_free_slot()
	var near := router.nearest_lane(p + fwd * 6.0, 120.0, func(k):
		if not _lane_ok(k):
			return false
		var g: Array = world.net.lane_geo[k]
		var r := Geo.closest_on_polyline(g[0], g[1], p)
		var smp := Geo.sample(g[0], g[1], r[1])
		return (smp[1] as Vector2).dot(fwd) > 0.2)
	if near.is_empty():
		near = router.nearest_lane(p, 200.0, func(k): return _lane_ok(k))
	if near.is_empty():
		return {}
	var key: int = near.key
	var ln := router.lane_len(key)
	var s_join: float = minf(near.s + 9.0, ln - 0.5)
	var g2: Array = world.net.lane_geo[key]
	var jp := Geo.sample(g2[0], g2[1], s_join)
	var join2 := _smooth_join(p, fwd, jp[0], jp[1])
	return {"key": key, "s": s_join, "pre": [Router.poly_piece(join2, 3.5)]}


func _start_agent(pieces: Array, s0: float) -> void:
	if agent:
		world.traffic.remove_agent(agent)
	agent = world.traffic.add_agent("player", pieces, s0, self)
	agent.length = front_ext + rear_ext + (14.0 if trailer else 0.0)
	agent.width = half_w * 2.0
	agent.vmax = float(def.get("max_kmh", 50.0)) / 3.6
	agent.accel = def.get("accel", 1.5)
	agent.decel = 2.5
	agent.p_cur = Vector3(position.x, 0.05, position.z)
	agent.p_prev = agent.p_cur
	var pose := Router.piece_pose(pieces[0], s0)
	agent.yaw_cur = atan2(-pose[1].x, -pose[1].y)
	agent.yaw_prev = rotation.y
	if pieces[0].get("rev", false):
		agent.hold = 0.6
	if pieces[0].has("obs"):
		on_piece_enter(agent, pieces[0])


func on_piece_enter(_ag: Agent, pc: Dictionary) -> void:
	reversing = pc.get("rev", false)
	if pc.has("obs"):
		var o: Dictionary = pc.obs
		world.traffic.set_obstacle(o.key, o.s0, o.s1, _man_obs_id)
	if pc.get("tag", "") == "clear":
		world.traffic.clear_obstacles(_man_obs_id)
	if pc.has("event") and site:
		site.on_vehicle_event(self, pc.event)


func on_route_finished(ag: Agent) -> void:
	if ag != agent:
		return
	_arrive(dest_text, on_arrive)


func _arrive(label: String, cb: Callable) -> void:
	state = "parked"
	speed = 0.0
	reversing = false
	dest_text = label
	status_text = "Angekommen: " + label
	if agent:
		world.traffic.remove_agent(agent)
		agent = null
	world.traffic.clear_obstacles(_man_obs_id)
	if label == "Zentrale" and world.hq.in_lot(pos2()):
		status_text = "In der Zentrale"
		_refuel()
	on_arrive = Callable()
	Events.vehicle_changed.emit(self)
	arrived.emit(self)
	if cb.is_valid():
		cb.call(self)


func on_route_changed(_ag: Agent) -> void:
	pass


func stop_now() -> void:
	_drop_agent()
	state = "parked"
	speed = 0.0
	reversing = false
	status_text = "Angehalten"
	on_arrive = Callable()
	Events.vehicle_changed.emit(self)


func at_hq() -> bool:
	return world.hq.in_lot(pos2()) and state != "driving"


func _refuel() -> void:
	var liters: float = (1.0 - fuel) * TANK_L.get(category(), 300.0)
	if liters > 1.0:
		Game.spend(liters * Balance.DIESEL_EUR_L, "Diesel %s" % vname, true)
		fuel = 1.0


## Right-click command from the player.
func command_at(gp: Vector3, target: Object) -> void:
	if not can_drive():
		return
	if target is Vehicle and target != self:
		var tv := target as Vehicle
		if tv.def_id == "tractor_lowbed" and is_machine():
			tv.load_machine(self)
			return
	var p2 := Vector2(gp.x, gp.z)
	var site_hit = target if (target != null and target.has_method("send_vehicle")) else world.jobs.site_at(p2)
	if site_hit:
		site_hit.send_vehicle(self)
		return
	if world.hq.in_lot(p2):
		drive_to_hq()
		return
	var old_site = site
	if drive_to(gp, "Zielpunkt") and old_site and is_instance_valid(old_site) and site == old_site:
		old_site.release_vehicle(self)


# ------------------------------------------------------------------------------------------
# Lowbed: carry machines
# ------------------------------------------------------------------------------------------

const DECK_Y := 1.01
const DECK_Z := -1.6
const DECK_END_Z := 6.0
const RAMP_END_Z := 8.7


func deck_transform() -> Transform3D:
	if trailer == null:
		return global_transform
	return trailer.global_transform * Transform3D(Basis(), Vector3(0, DECK_Y, DECK_Z))


## Machine pose along the loading path: dist = distance from the deck spot towards the rear (trailer frame).
func _ramp_pose(dist: float) -> Transform3D:
	var z := DECK_Z + dist
	var y := DECK_Y
	var pitch := 0.0
	var ramp_len := RAMP_END_Z - DECK_END_Z
	if z > DECK_END_Z:
		var t := clampf((z - DECK_END_Z) / ramp_len, 0.0, 1.0)
		y = lerpf(DECK_Y, 0.0, t)
		if t < 1.0:
			pitch = -atan2(DECK_Y, ramp_len) * sin(t * PI) * 1.2
	return trailer.global_transform * Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(0, y, z))


func load_machine(m: Vehicle, cb: Callable = Callable()) -> bool:
	if def_id != "tractor_lowbed" or trailer == null:
		return false
	if cargo.machine != null:
		Events.warn("Der Tieflader ist schon beladen")
		return false
	if state == "driving" or m.state == "driving":
		Events.warn("Beide Fahrzeuge müssen stehen")
		return false
	var behind := trailer.global_transform * Vector3(0, 0, RAMP_END_Z + m.front_ext + 2.0)
	var behind2 := Vector2(behind.x, behind.z)
	if m.pos2().distance_to(behind2) > 3.5 or m.forward2().dot(forward2()) < 0.8:
		# machine drives up behind the trailer first (in line with it)
		var dirv := forward2()
		var start_p := m.pos2()
		var path := HQ.bezier(start_p, start_p + m.forward2() * 4.0, behind2 - dirv * 6.0, behind2)
		var ok := m.drive_plan({}, "Tieflader", [], func(v): load_machine(v, cb), [Router.poly_piece(path, 2.5)])
		if ok:
			m.status_text = "Fährt zum Tieflader"
		return ok
	cargo.machine = m
	if m.site:
		m.site.release_vehicle(m)
	m.state = "loading"
	m.status_text = "Fährt auf den Tieflader"
	state = "loading"
	var start_dist := RAMP_END_Z + m.front_ext + 2.0 - DECK_Z
	var tw := create_tween()
	tw.tween_callback(func(): light_mode.hazard = true)
	tw.tween_subtween(tween_ramp(4.68, 20.0, 4.0))
	var start_tf := m.global_transform
	tw.tween_method(func(t): m.global_transform = start_tf.interpolate_with(_ramp_pose(start_dist), t), 0.0, 1.0, 0.5)
	tw.tween_method(func(d): m.global_transform = _ramp_pose(d), start_dist, 0.0, start_dist / 1.1)
	tw.tween_callback(func():
		m.carried_by = self
		m.state = "on_trailer"
		m.status_text = "Auf %s" % vname)
	tw.tween_subtween(tween_ramp(0.0, 0.0, 4.0))
	tw.tween_callback(func():
		state = "parked"
		light_mode.hazard = false
		status_text = "Beladen: %s" % m.vname
		Events.ok("%s auf %s verladen" % [m.vname, vname])
		Events.vehicle_changed.emit(m)
		Events.vehicle_changed.emit(self)
		if cb.is_valid():
			cb.call(m))
	return true


## Unload the carried machine backwards over the ramp. cb(machine) when it stands on the ground behind.
func unload_machine(cb: Callable = Callable()) -> Vehicle:
	var m: Vehicle = cargo.machine
	if m == null:
		return null
	if state == "driving":
		Events.warn("Erst anhalten")
		return null
	state = "loading"
	m.state = "loading"
	m.status_text = "Wird abgeladen"
	var end_dist := RAMP_END_Z + m.front_ext + 2.0 - DECK_Z
	var tw := create_tween()
	tw.tween_callback(func(): light_mode.hazard = true)
	tw.tween_subtween(tween_ramp(4.68, 20.0, 4.0))
	tw.tween_callback(func():
		m.carried_by = null
		m.reversing = true)
	tw.tween_method(func(d): m.global_transform = _ramp_pose(d), 0.0, end_dist, end_dist / 1.1)
	tw.tween_callback(func():
		cargo.machine = null
		var tf := m.global_transform
		m.place(tf.origin, rotation.y)
		m.reversing = false
		m.state = "parked"
		m.status_text = "Abgeladen")
	tw.tween_subtween(tween_ramp(0.0, 0.0, 4.0))
	tw.tween_callback(func():
		state = "parked"
		light_mode.hazard = false
		status_text = "Leer"
		Events.vehicle_changed.emit(m)
		Events.vehicle_changed.emit(self)
		if cb.is_valid():
			cb.call(m))
	return m


# ------------------------------------------------------------------------------------------
# Cargo helpers
# ------------------------------------------------------------------------------------------

func bulk_m3() -> float:
	var t := 0.0
	for k in cargo.bulk:
		t += cargo.bulk[k]
	return t


func bulk_capacity() -> float:
	return float(def.get("bulk_capacity_m3", 0.0))


func bulk_main() -> String:
	var best := "soil"
	var bv := 0.0
	for k in cargo.bulk:
		if cargo.bulk[k] > bv:
			bv = cargo.bulk[k]
			best = k
	return best


func add_bulk(mat: String, m3: float) -> void:
	cargo.bulk[mat] = maxf(0.0, cargo.bulk.get(mat, 0.0) + m3)
	if cargo.bulk[mat] < 0.01:
		cargo.bulk.erase(mat)
	update_load_visual()
	Events.vehicle_changed.emit(self)


func cargo_text() -> String:
	var parts: Array = []
	for k in cargo.bulk:
		if cargo.bulk[k] > 0.05:
			parts.append("%.1f m³ %s" % [cargo.bulk[k], Balance.MATERIALS[k].name])
	if cargo.barriers > 0:
		parts.append("Absperrmaterial (%d Teile)" % cargo.barriers)
	if cargo.pipes_new > 0:
		parts.append("1 neues Rohr" if cargo.pipes_new == 1 else "%d neue Rohre" % cargo.pipes_new)
	if cargo.pipes_old > 0:
		parts.append("1 Altrohr" if cargo.pipes_old == 1 else "%d Altrohre" % cargo.pipes_old)
	if cargo.machine != null:
		parts.append((cargo.machine as Vehicle).vname)
	if crew_aboard > 0:
		parts.append("Kolonne (%d)" % crew_aboard)
	return ", ".join(parts) if not parts.is_empty() else "leer"


func eta_minutes() -> float:
	if agent == null or state != "driving":
		return 0.0
	var rem := agent.remaining_route()
	var v := maxf(4.0, minf(agent.vmax, 11.0))
	return rem / v * Clock.GAME_SECONDS_PER_REAL_SECOND / 60.0


func save_state() -> Dictionary:
	return {"def": def_id, "name": vname, "plate": plate, "pos": global_position, "yaw": rotation.y,
		"odo": odometer_km, "hours": op_hours, "fuel": fuel, "cond": condition, "bought": purchase_day,
		"cargo": {"bulk": cargo.bulk, "barriers": cargo.barriers, "pipes_new": cargo.pipes_new, "pipes_old": cargo.pipes_old},
		"slot": slot, "lights": light_mode, "auto": auto_shuttle,
		"crew": crew_aboard + (site.workers.size() if site and site.crew_van == self else 0),
		"carried_by": carried_by.plate if carried_by else "",
		"site": site.job.id if site else -1, "spot": site.spot_of.get(self, "") if site else "",
		"in_place": site.in_place.has(self) if site else false}


func load_state(d: Dictionary) -> void:
	odometer_km = d.get("odo", 0.0)
	op_hours = d.get("hours", 0.0)
	fuel = d.get("fuel", 1.0)
	condition = d.get("cond", 1.0)
	purchase_day = d.get("bought", 1)
	var c: Dictionary = d.get("cargo", {})
	cargo.bulk = c.get("bulk", {})
	cargo.barriers = c.get("barriers", 0)
	cargo.pipes_new = c.get("pipes_new", 0)
	cargo.pipes_old = c.get("pipes_old", 0)
	light_mode.merge(d.get("lights", {}), true)   # keeps defaults for keys older saves lack (flash)
	crew_aboard = d.get("crew", 0)
	auto_shuttle = d.get("auto", true)
	place(d.pos, d.yaw)
	slot = d.get("slot", -1)
	if slot >= 0 and slot < world.hq.slots.size():
		world.hq.slots[slot].used_by = self
	update_load_visual()
