class_name ExcavatorRig
extends RefCounted
## Arm control for an excavator model with canonical nodes (turret, boom, [boom2], stick, bucket, bucket_tip).
## All hinges rotate about their local X axis, the turret about local Y (asset convention, see docs/consim_assets.md).
## Planar CCD-IK places the bucket tip; the bucket joint angle is set directly. A four-bar linkage (bucket_link_a/b)
## and hydraulic cylinders follow. A small sequencer runs work cycles (pick -> lift -> swing -> drop).

signal cycle_event(kind: String, data: Dictionary)   # "bite", "picked", "dropped", "done"

var veh: Node3D
var model: Node3D
var turret: Node3D
var chain: Array = []          # [Node3D] hinge joints solved by IK (boom, boom2, stick)
var bucket: Node3D
var tip: Node3D
var blade: Node3D
var link_a: Node3D
var link_b: Node3D
var hyd: Array = []
var lim := {}                  # node name -> [min_rad, max_rad]
var rest := {}                 # node -> Basis
var angles := {}               # node -> current hinge angle (rad)
var yaw := 0.0
var bucket_angle := 0.0
var blade_angle := 0.0
var ok := false
var load_node: MeshInstance3D
var load_m3 := 0.0
var load_mat := "soil"
var hook_item: Node3D = null   # item hanging on the bucket (pipe), keeps a fixed world yaw
var hook_yaw := 0.0
var hook_drop := 0.9
# planar rest geometry in turret space (u = -z forward, v = y up)
var _piv: Array = []           # PackedVector2 pivots per joint (chain + bucket)
var _vec: Array = []           # rest vectors between consecutive pivots, last = bucket pivot -> tip
var _bx := 0.0
var _B_stick := Vector3.ZERO   # four-bar points in local frames
var _C_rest_root := Vector3.ZERO
var _D_bucket := Vector3.ZERO
var _C_linka := Vector3.ZERO
var _D_linkb := Vector3.ZERO
var _len_bc := 0.0
var _len_cd := 0.0
var _has_fourbar := false
var _fb_side := 1.0            # assembly branch of the four-bar: side of C relative to B->D in the arm plane (rest pose)
# sequencer
var _seq: Array = []           # list of keyframes {dur, yaw, r, h, bucket, ev}
var _seq_i := -1
var _seq_t := 0.0
var _from := {}
var busy := false


func setup(vehicle: Node3D, mdl: Node3D, meta: Dictionary) -> void:
	veh = vehicle
	model = mdl
	var names: Dictionary = meta.get("nodes", {})
	turret = RigUtil.find(model, names.get("turret", "turret"))
	var boom := RigUtil.find(model, names.get("boom", "boom"))
	var boom2 := RigUtil.find(model, names.get("boom2", "boom2"))
	var stick := RigUtil.find(model, names.get("stick", "stick"))
	bucket = RigUtil.find(model, names.get("bucket", "bucket"))
	tip = RigUtil.find(model, names.get("bucket_tip", "bucket_tip"))
	blade = RigUtil.find(model, names.get("blade", "blade"))
	link_a = RigUtil.find(model, names.get("bucket_link_a", "bucket_link_a"))
	link_b = RigUtil.find(model, names.get("bucket_link_b", "bucket_link_b"))
	if turret == null or boom == null or stick == null or bucket == null or tip == null:
		push_warning("ExcavatorRig: missing nodes in %s" % model.name)
		return
	chain = [boom]
	if boom2:
		chain.append(boom2)
	chain.append(stick)
	var jl: Dictionary = meta.get("joint_limits_deg", {})
	for n in chain + [bucket]:
		var l: Array = jl.get(String(n.name), [-120.0, 120.0])
		lim[n] = [deg_to_rad(float(l[0])), deg_to_rad(float(l[1]))]
		rest[n] = n.basis
		angles[n] = 0.0
	rest[turret] = turret.basis
	if blade:
		rest[blade] = blade.basis
		var bl: Array = jl.get("blade", [-36.5, 0.0])
		lim[blade] = [deg_to_rad(float(bl[0])), deg_to_rad(float(bl[1]))]
	# planar rest geometry (model must be in the rest pose and inside the tree)
	var tinv := turret.global_transform.affine_inverse()
	var pts: Array = []
	for n in chain + [bucket, tip]:
		var lp: Vector3 = tinv * (n as Node3D).global_position
		pts.append(Vector2(-lp.z, lp.y))
		if n == chain[0]:
			_bx = lp.x
	_piv = []
	_vec = []
	for i in pts.size():
		_piv.append(pts[i])
		if i > 0:
			_vec.append(pts[i] - pts[i - 1])
	# four-bar linkage
	var fb: Dictionary = meta.get("bucket_linkage", {})
	if link_a and link_b and fb.has("B_link_a_pivot"):
		var to_g := func(a: Array) -> Vector3: return model.global_transform * Vector3(a[0], a[1], a[2])
		var B: Vector3 = to_g.call(fb.B_link_a_pivot)
		var C: Vector3 = to_g.call(fb.C_link_joint)
		var D: Vector3 = to_g.call(fb.D_bucket_pin)
		_B_stick = stick.global_transform.affine_inverse() * B
		_D_bucket = bucket.global_transform.affine_inverse() * D
		_C_linka = link_a.global_transform.affine_inverse() * C
		_D_linkb = link_b.global_transform.affine_inverse() * D
		_len_bc = B.distance_to(C)
		_len_cd = C.distance_to(D)
		# B, C, D never become collinear within the joint limits, so the branch never changes: keep the rest one.
		# (Picking the solution nearest to the last C flipped it after the first big jump, issue #3.)
		var tinv0 := turret.global_transform.affine_inverse()
		var b0 := tinv0 * B
		var c0 := tinv0 * C
		var d0 := tinv0 * D
		var bd := Vector2(-(d0.z - b0.z), d0.y - b0.y)
		var bc := Vector2(-(c0.z - b0.z), c0.y - b0.y)
		_fb_side = 1.0 if bd.cross(bc) >= 0.0 else -1.0
		rest[link_a] = link_a.basis
		rest[link_b] = link_b.basis
		_has_fourbar = true
	hyd = RigUtil.setup_hydraulics(model, meta)
	# load mound inside the bucket
	load_node = MeshInstance3D.new()
	load_node.mesh = RigUtil.mound_mesh()
	load_node.visible = false
	load_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bucket.add_child(load_node)
	var ab := RigUtil.local_aabb(bucket)
	var c := ab.get_center()
	load_node.position = Vector3(c.x, c.y, c.z)
	load_node.set_meta("size", ab.size)
	ok = true
	travel_pose(true)


# ------------------------------------------------------------------------------------------
# Kinematics
# ------------------------------------------------------------------------------------------

static func _rot(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))


## Planar FK: returns [pivot positions of chain joints..., bucket pivot, tip] for given chain angles + bucket angle.
func _fk(th: Array, bth: float) -> Array:
	var out: Array = [_piv[0]]
	var acc := 0.0
	var p: Vector2 = _piv[0]
	for i in chain.size():
		acc += th[i]
		p = p + _rot(_vec[i], acc)
		out.append(p)
	acc += bth
	out.append(p + _rot(_vec[chain.size()], acc))
	return out


func _solve_planar(target: Vector2, bth: float) -> void:
	var th: Array = []
	for n in chain:
		th.append(angles[n])
	var order: Array = []
	for i in range(chain.size() - 1, -1, -1):
		order.append(i)
	for it in 14:
		for i in order:
			var pos := _fk(th, bth)
			var e: Vector2 = pos[pos.size() - 1]
			var pj: Vector2 = pos[i]
			var a1 := (e - pj).angle()
			var a2 := (target - pj).angle()
			var d := wrapf(a2 - a1, -PI, PI)
			var n: Node3D = chain[i]
			th[i] = clampf(th[i] + d, lim[n][0], lim[n][1])
		var pos2 := _fk(th, bth)
		if (pos2[pos2.size() - 1] as Vector2).distance_to(target) < 0.01:
			break
	for i in chain.size():
		angles[chain[i]] = th[i]


func _apply() -> void:
	turret.basis = Basis(Vector3.UP, yaw) * rest[turret]
	for n in chain:
		(n as Node3D).basis = rest[n] * Basis(Vector3.RIGHT, angles[n])
	bucket.basis = rest[bucket] * Basis(Vector3.RIGHT, bucket_angle)
	if blade:
		blade.basis = rest[blade] * Basis(Vector3.RIGHT, blade_angle)
	if _has_fourbar:
		_solve_fourbar()
	RigUtil.update_hydraulics(hyd)
	if hook_item:
		hook_item.global_transform = Transform3D(Basis(Vector3.UP, hook_yaw), tip.global_position - Vector3(0, hook_drop, 0))


func _solve_fourbar() -> void:
	var stick: Node3D = chain[chain.size() - 1]
	var B: Vector3 = stick.global_transform * _B_stick
	var D: Vector3 = bucket.global_transform * _D_bucket
	# circle-circle intersection in the arm plane
	var tinv := turret.global_transform.affine_inverse()
	var b2 := tinv * B
	var d2 := tinv * D
	var pb := Vector2(-b2.z, b2.y)
	var pd := Vector2(-d2.z, d2.y)
	var dist := pb.distance_to(pd)
	if dist < 0.001 or dist > _len_bc + _len_cd or dist < absf(_len_bc - _len_cd):
		return
	var a := (_len_bc * _len_bc - _len_cd * _len_cd + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, _len_bc * _len_bc - a * a))
	var dir := (pd - pb) / dist
	var mid := pb + dir * a
	var perp := Vector2(-dir.y, dir.x)     # left of B->D: cross(dir, perp) = +1
	var pc := mid + perp * (h * _fb_side)
	var C := turret.global_transform * Vector3(b2.x, pc.y, -pc.x)
	_hinge_to(link_a, _C_linka, C)
	_hinge_to(link_b, _D_linkb, D)


## Rotate node about its local X (rest frame) so that its local point lp points at target (global).
func _hinge_to(node: Node3D, lp: Vector3, target: Vector3) -> void:
	var parent := node.get_parent() as Node3D
	var rb: Basis = rest[node]
	var pinv := parent.global_transform.affine_inverse()
	var t := pinv * target - node.position
	var d0 := rb * lp
	var ax := rb.x.normalized()
	var t_p := t - ax * t.dot(ax)
	var d_p := d0 - ax * d0.dot(ax)
	if t_p.length_squared() < 1e-8 or d_p.length_squared() < 1e-8:
		return
	var ang := d_p.signed_angle_to(t_p, ax)
	node.basis = Basis(ax, ang) * rb


## Place the bucket tip at a world position with a given bucket joint angle. Turret yaw is solved too.
func reach_world(target: Vector3, bucket_rad: float, keep_yaw := false) -> void:
	if not ok:
		return
	if not keep_yaw:
		var parent := turret.get_parent() as Node3D
		var lt: Vector3 = parent.global_transform.affine_inverse() * target - turret.position
		var r := Vector2(lt.x, lt.z).length()
		yaw = atan2(-lt.x, -lt.z)
		if r > absf(_bx) + 0.01:
			yaw += asin(clampf(_bx / r, -1.0, 1.0))
	bucket_angle = clampf(bucket_rad, lim[bucket][0], lim[bucket][1])
	turret.basis = Basis(Vector3.UP, yaw) * rest[turret]
	var tl: Vector3 = turret.global_transform.affine_inverse() * target
	_solve_planar(Vector2(-tl.z, tl.y), bucket_angle)
	_apply()


## Target expressed as (yaw relative to the body, horizontal radius from the turret axis, height above ground).
func reach_polar(y: float, r: float, h: float, bucket_rad: float) -> void:
	if not ok:
		return
	yaw = y
	bucket_angle = clampf(bucket_rad, lim[bucket][0], lim[bucket][1])
	turret.basis = Basis(Vector3.UP, yaw) * rest[turret]
	var ground_y := veh.global_position.y
	var tg := turret.global_transform
	var axis_origin := tg.origin
	var fwd := -tg.basis.z.normalized()
	var right := tg.basis.x.normalized()
	var world_t := axis_origin + fwd * sqrt(maxf(0.0, r * r - _bx * _bx)) + right * _bx
	world_t.y = ground_y + h
	var tl: Vector3 = tg.affine_inverse() * world_t
	_solve_planar(Vector2(-tl.z, tl.y), bucket_angle)
	_apply()


## Converts a world point into (yaw, r, h) relative to this excavator.
func polar_of(p: Vector3) -> Vector3:
	var parent := turret.get_parent() as Node3D
	var lt: Vector3 = parent.global_transform.affine_inverse() * p - turret.position
	var r := Vector2(lt.x, lt.z).length()
	var y := atan2(-lt.x, -lt.z)
	if r > absf(_bx) + 0.01:
		y += asin(clampf(_bx / r, -1.0, 1.0))
	return Vector3(y, r, p.y - veh.global_position.y)


func tip_position() -> Vector3:
	return tip.global_position if tip else Vector3.ZERO


func travel_pose(instant := false) -> void:
	if not ok:
		return
	if instant:
		yaw = 0.0
		blade_angle = 0.0
		reach_polar(0.0, 4.6, 2.0, deg_to_rad(-80.0))
	else:
		run([{"dur": 2.0, "yaw": 0.0, "r": 4.6, "h": 2.0, "bucket": -80.0, "blade": 0.0}])


func set_load(m3: float, mat: String) -> void:
	load_m3 = m3
	load_mat = mat
	if load_node == null:
		return
	load_node.visible = m3 > 0.01
	if load_node.visible:
		var sz: Vector3 = load_node.get_meta("size", Vector3(0.9, 0.7, 0.8))
		var f := clampf(m3 / 0.6, 0.15, 1.2)
		load_node.scale = Vector3(sz.x * 0.85, sz.y * 0.55 * f, sz.z * 0.75)
		load_node.material_override = RigUtil.bulk_material(mat)


# ------------------------------------------------------------------------------------------
# Sequencer
# ------------------------------------------------------------------------------------------

## Run keyframes: each {dur, yaw, r, h, bucket(deg), blade(deg, optional), ev(optional String), data}.
func run(frames: Array) -> void:
	_seq = frames
	_seq_i = 0
	_seq_t = 0.0
	_from = {"yaw": yaw, "pos": polar_of(tip_position()), "bucket": bucket_angle, "blade": blade_angle}
	busy = true


func stop() -> void:
	_seq = []
	_seq_i = -1
	busy = false


func update(delta: float) -> void:
	if not ok or _seq_i < 0 or _seq.is_empty():
		return
	var kf: Dictionary = _seq[_seq_i]
	_seq_t += delta
	var dur: float = maxf(0.05, kf.get("dur", 1.0))
	var t := clampf(_seq_t / dur, 0.0, 1.0)
	var w := t * t * (3.0 - 2.0 * t)
	var p0: Vector3 = _from.pos
	var y1: float = kf.get("yaw", p0.x)
	var y := lerp_angle(_from.yaw, y1, w)
	var r := lerpf(p0.y, kf.get("r", p0.y), w)
	var h := lerpf(p0.z, kf.get("h", p0.z), w)
	var bk := lerpf(_from.bucket, deg_to_rad(kf.get("bucket", rad_to_deg(_from.bucket))), w)
	if kf.has("blade"):
		blade_angle = lerpf(_from.blade, deg_to_rad(kf.blade), w)
	reach_polar(y, r, h, bk)
	if kf.has("progress"):
		cycle_event.emit("progress", {"t": t, "kf": kf})
	if t >= 1.0:
		if kf.has("ev"):
			cycle_event.emit(kf.ev, kf.get("data", {}))
		_seq_i += 1
		_seq_t = 0.0
		_from = {"yaw": yaw, "pos": Vector3(y1, kf.get("r", p0.y), kf.get("h", p0.z)), "bucket": bucket_angle, "blade": blade_angle}
		if _seq_i >= _seq.size():
			_seq_i = -1
			busy = false
			cycle_event.emit("done", {})


## Standard dig/move cycle: bite at pick (world), drop at drop (world). pick_depth is how deep the tip goes below pick.y.
func material_cycle(pick: Vector3, pick_to: Vector3, drop: Vector3, drop_h: float, speed := 1.0) -> void:
	var a := polar_of(pick)
	var b := polar_of(pick_to)
	var d := polar_of(drop)
	var sp := 1.0 / maxf(0.2, speed)
	run([
		{"dur": 2.2 * sp, "yaw": a.x, "r": a.y, "h": a.z + 1.3, "bucket": 25.0, "blade": -18.0},
		{"dur": 1.0 * sp, "yaw": a.x, "r": a.y, "h": a.z - 0.05, "bucket": 15.0},
		{"dur": 2.4 * sp, "yaw": b.x, "r": b.y, "h": b.z, "bucket": -65.0, "ev": "bite", "progress": true},
		{"dur": 1.3 * sp, "yaw": b.x, "r": b.y - 0.3, "h": maxf(b.z, 0.0) + 2.0, "bucket": -88.0, "ev": "picked"},
		{"dur": 2.4 * sp, "yaw": d.x, "r": d.y, "h": drop_h + 0.9, "bucket": -88.0},
		{"dur": 1.6 * sp, "yaw": d.x, "r": d.y, "h": drop_h + 0.8, "bucket": 55.0, "ev": "dropped"},
		{"dur": 0.6 * sp, "yaw": d.x, "r": d.y, "h": drop_h + 1.2, "bucket": 20.0},
	])


## Lift cycle for pipes: hook at pick, set down at drop. The item is attached between "picked" and "dropped".
func lift_cycle(pick: Vector3, drop: Vector3, speed := 1.0) -> void:
	var a := polar_of(pick)
	var d := polar_of(drop)
	var sp := 1.0 / maxf(0.2, speed)
	run([
		{"dur": 2.4 * sp, "yaw": a.x, "r": a.y, "h": a.z + 2.2, "bucket": -85.0, "blade": -18.0},
		{"dur": 1.6 * sp, "yaw": a.x, "r": a.y, "h": a.z + 0.75, "bucket": -85.0},
		{"dur": 2.5 * sp, "yaw": a.x, "r": a.y, "h": a.z + 0.75, "bucket": -85.0, "ev": "hooked"},
		{"dur": 2.2 * sp, "yaw": a.x, "r": a.y, "h": maxf(a.z, 0.0) + 3.0, "bucket": -85.0},
		{"dur": 3.2 * sp, "yaw": d.x, "r": d.y, "h": maxf(d.z, 0.0) + 3.0, "bucket": -85.0},
		{"dur": 2.0 * sp, "yaw": d.x, "r": d.y, "h": d.z + 0.75, "bucket": -85.0},
		{"dur": 1.8 * sp, "yaw": d.x, "r": d.y, "h": d.z + 0.75, "bucket": -85.0, "ev": "released"},
		{"dur": 1.6 * sp, "yaw": d.x, "r": d.y, "h": maxf(d.z, 0.0) + 2.5, "bucket": -80.0},
	])
