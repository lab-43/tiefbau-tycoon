class_name HQ
extends Node3D
## Company headquarters on the chosen lot: paved yard, hall, material bays, parking slots, fence, sign.

var lot := PackedVector2Array()
var gate := Vector2.ZERO
var normal := Vector2.ZERO      # points from the road into the lot
var along := Vector2.ZERO       # along the road
var slots: Array = []           # [{pos: Vector3, yaw: float, used_by: Object}]
var bays: Dictionary = {}       # material -> Vector3 position of the bay mouth (truck rear goes here)
var bay_u: Dictionary = {}      # material -> u coordinate of the bay centre
var bay_piles: Dictionary = {}  # material -> MeshInstance3D
var company_name := ""
var level := 0.0                # height of the levelled yard (#8: the ground is flattened under the lot)


func setup(hq: Dictionary, cname: String) -> void:
	company_name = cname
	lot = hq.lot
	gate = hq.gate
	normal = hq.normal
	along = Geo.left_of(normal)
	level = Terrain.at(Geo.polygon_centroid(lot))
	_build()


func local_to_world(u: float, v: float) -> Vector3:
	# u along the road (from gate), v depth into the lot
	var p := gate + along * u + normal * v
	return Vector3(p.x, level, p.y)


func yaw_facing(dir2: Vector2) -> float:
	# yaw so that the node's -Z points along dir2
	return atan2(-dir2.x, -dir2.y)


func _build() -> void:
	# yard pavement
	var yard := MeshLayer.new()
	yard.polygon_up(lot, level + 0.045, 1.0)
	var ym := yard.commit()
	var ymi := MeshInstance3D.new()
	ymi.mesh = ym
	ymi.material_override = Mats.get_mat("area_paved")
	ymi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ymi)
	# hall at the back left
	var hall_center := local_to_world(-19.0, 39.0)
	var hall := _box(Vector3(26, 9, 20), hall_center + Vector3(0, 4.5, 0), Color(0.93, 0.93, 0.92))
	hall.rotation.y = yaw_facing(normal)
	# orange doors facing the yard
	for i in 3:
		var dpos := local_to_world(-28.0 + i * 8.5, 28.9) + Vector3(0, 2.4, 0)
		var door := _box(Vector3(5.5, 4.8, 0.2), dpos, UI.ACCENT)
		door.rotation.y = yaw_facing(normal)
	# roof band with company name
	var lbl := Label3D.new()
	lbl.text = company_name.to_upper()
	lbl.font = UI.font(700)
	lbl.font_size = 180
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.06, 0.06, 0.06)
	lbl.outline_size = 0
	lbl.position = local_to_world(-19.0, 28.85) + Vector3(0, 7.6, 0)
	lbl.rotation.y = yaw_facing(normal)
	lbl.double_sided = false
	add_child(lbl)
	var stripe := _box(Vector3(26.2, 0.6, 0.15), local_to_world(-19.0, 28.88) + Vector3(0, 6.0, 0), UI.ACCENT)
	stripe.rotation.y = yaw_facing(normal)
	# material bays at the back right: sand, gravel, asphalt, soil (dump)
	var mats := ["sand", "gravel", "asphalt", "soil"]
	for i in mats.size():
		var u := 7.0 + i * 6.5
		var c := local_to_world(u, 44.5)
		bay_u[mats[i]] = u
		# concrete walls (3 sides)
		for w in [[-3.1, 0.0, 0.3, 6.0], [3.1, 0.0, 0.3, 6.0], [0.0, 3.0, 6.5, 0.3]]:
			var p := local_to_world(u + w[0], 44.5 + w[1])
			var wall := _box(Vector3(w[2], 2.2, w[3]), p + Vector3(0, 1.1, 0), Color(0.62, 0.61, 0.59))
			wall.rotation.y = yaw_facing(normal)
		var pile := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.4
		cone.bottom_radius = 2.6
		cone.height = 1.7
		cone.radial_segments = 12
		pile.mesh = cone
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Balance.MATERIALS[mats[i]].color
		pm.roughness = 1.0
		pile.material_override = pm
		pile.position = c + Vector3(0, 0.85, 0)
		pile.scale = Vector3(1, 1, 0.9)
		add_child(pile)
		bay_piles[mats[i]] = pile
		bays[mats[i]] = local_to_world(u, 41.0)
	# pipe rack and barrier storage (front right)
	for k in 4:
		var pr := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.09
		cyl.bottom_radius = 0.09
		cyl.height = 6.0
		cyl.radial_segments = 8
		pr.mesh = cyl
		var pm2 := StandardMaterial3D.new()
		pm2.albedo_color = Color(0.12, 0.25, 0.65)
		pr.material_override = pm2
		pr.position = local_to_world(-24.0, 6.0 + k * 0.25) + Vector3(0, 0.1 + (k % 2) * 0.17, 0)
		pr.basis = Basis.looking_at(Vector3(along.x, 0, along.y), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		add_child(pr)
	bays["pipes"] = local_to_world(-24.0, 9.0)
	bays["barriers"] = local_to_world(-18.0, 9.0)
	_barrier_stack(local_to_world(-17.0, 5.5))
	# parking slots, all facing the road; vehicles pull through from the back of the yard
	slots.clear()
	for u in [-10.0, -15.0, -20.0, -25.0]:
		slots.append({"pos": local_to_world(u, 20.0), "yaw": yaw_facing(-normal), "used_by": null, "kind": "small", "len": 9.0, "w": 4.6, "u": u, "v": 20.0})
	for u in [16.0, 21.0, 26.0]:
		slots.append({"pos": local_to_world(u, 22.0), "yaw": yaw_facing(-normal), "used_by": null, "kind": "truck", "len": 12.0, "w": 4.6, "u": u, "v": 22.0})
	slots.append({"pos": local_to_world(9.0, 21.0), "yaw": yaw_facing(normal), "used_by": null, "kind": "lowbed", "len": 28.0, "w": 4.8, "u": 9.0, "v": 21.0})
	# second low-loader (#24, Nooteboom); appended last so saved slot indices stay valid
	slots.append({"pos": local_to_world(31.0, 21.0), "yaw": yaw_facing(normal), "used_by": null, "kind": "lowbed", "len": 28.0, "w": 4.8, "u": 31.0, "v": 21.0})
	_slot_lines()
	_fence()


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _barrier_stack(p: Vector3) -> void:
	for k in 5:
		_box(Vector3(2.0, 0.1, 1.0), p + Vector3(0, 0.1 + k * 0.12, 0), Color(0.85, 0.1, 0.08) if k % 2 == 0 else Color(0.95, 0.95, 0.95))


func _slot_lines() -> void:
	var l := MeshLayer.new()
	for s in slots:
		var c: Vector3 = s.pos
		var w: float = s.w
		var len: float = s.len
		var fwd := Vector3(sin(s.yaw) * -1.0, 0, cos(s.yaw) * -1.0)
		var right := Vector3(-fwd.z, 0, fwd.x)
		for side in [-1.0, 1.0]:
			var a: Vector3 = c + right * side * w * 0.5 - fwd * len * 0.5
			var b: Vector3 = c + right * side * w * 0.5 + fwd * len * 0.5
			var off := right * 0.06
			l.quad(a - off + Vector3(0, 0.06, 0), a + off + Vector3(0, 0.06, 0), b + off + Vector3(0, 0.06, 0), b - off + Vector3(0, 0.06, 0), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = l.commit()
	mi.material_override = Mats.get_mat("mark")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _fence() -> void:
	var l := MeshLayer.new()
	var n := lot.size()
	for i in n:
		var a := lot[i]
		var b := lot[(i + 1) % n]
		var mid := (a + b) * 0.5
		var segs := [[a, b]]
		# leave the gate open on the front edge
		if mid.distance_to(gate) < 1.0:
			var dir := (b - a).normalized()
			segs = [[a, gate - dir * 6.0], [gate + dir * 6.0, b]]
		for s in segs:
			var p0: Vector2 = s[0]
			var p1: Vector2 = s[1]
			var d := (p1 - p0)
			if d.length() < 0.5:
				continue
			var nn := Geo.right_of(d.normalized())
			var y0 := level - 0.5
			var y1 := level + 2.0
			l.quad(Geo.v3(p0, y0), Geo.v3(p1, y0), Geo.v3(p1, y1), Geo.v3(p0, y1), Vector3(nn.x, 0, nn.y))
			l.quad(Geo.v3(p0, y0), Geo.v3(p1, y0), Geo.v3(p1, y1), Geo.v3(p0, y1), -Vector3(nn.x, 0, nn.y))
	var mi := MeshInstance3D.new()
	mi.mesh = l.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.57, 0.58, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


func free_slot(kind: String) -> int:
	var order := {"small": ["small", "truck", "lowbed"], "truck": ["truck", "lowbed"], "lowbed": ["lowbed"]}
	for k in order.get(kind, ["small", "truck", "lowbed"]):
		for i in slots.size():
			if slots[i].used_by == null and slots[i].kind == k:
				return i
	return -1


func in_lot(p: Vector2) -> bool:
	return lot.size() > 2 and Geometry2D.is_point_in_polygon(p, lot)


func to_uv(p: Vector2) -> Vector2:
	var d := p - gate
	return Vector2(d.dot(along), d.dot(normal))


func uv(u: float, v: float) -> Vector2:
	return gate + along * u + normal * v


static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, step := 1.0) -> PackedVector2Array:
	var approx := p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)
	var n := maxi(4, int(approx / step))
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var a := p0.lerp(p1, t)
		var b := p1.lerp(p2, t)
		var c := p2.lerp(p3, t)
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out


static func join(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := a.duplicate()
	for i in b.size():
		if out.is_empty() or out[out.size() - 1].distance_to(b[i]) > 0.05:
			out.append(b[i])
	return out


## Forward path from the gate (coming in on the driveway) through the back of the yard into a slot.
func arrival_path(slot_i: int, from_p: Vector2, from_d: Vector2) -> PackedVector2Array:
	var s: Dictionary = slots[slot_i]
	var su: float = s.u
	var sv: float = s.v
	var half: float = s.len * 0.5
	var inner := uv(0.0, 5.0)
	var path := bezier(from_p, from_p + from_d * 2.5, inner - normal * 2.5, inner)
	if s.kind == "lowbed":
		path = join(path, bezier(inner, uv(0.0, 10.0), uv(su, 8.0), uv(su, 13.0)))
		return join(path, PackedVector2Array([uv(su, sv)]))
	var top := sv + half + maxf(7.0, absf(su) * 0.55)
	top = minf(top, 28.0 if su < 0.0 else 36.0)
	var c1 := uv(0.0, top)
	var c2 := uv(su, top)
	var end := uv(su, sv)
	path = join(path, bezier(inner, c1, c2, uv(su, sv + half * 0.4)))
	path = join(path, PackedVector2Array([end]))
	return path


## Forward path from anywhere in the yard out through the gate. Ends at the gate heading out.
func departure_path(from_p: Vector2, from_d: Vector2) -> PackedVector2Array:
	var g := gate - normal * 1.0
	var d := from_p.distance_to(g)
	var k := clampf(d * 0.4, 3.0, 14.0)
	if from_d.dot(g - from_p) < 0.0:
		k = 5.0   # facing away from the gate: turn around at the back of the yard
	return bezier(from_p, from_p + from_d * k, g + normal * maxf(k, 6.0), g)


## Reverse-in maneuver to a material bay. Returns {fwd, rev, pos, yaw}: forward path to the turning point,
## then reverse path so that the vehicle's rear ends at the bay mouth.
func bay_maneuver(mat: String, rear_ext: float, from_p: Vector2, from_d: Vector2) -> Dictionary:
	var bu: float = bay_u.get(mat, 10.0)
	var f := -normal
	var final_p := uv(bu, 40.6 - rear_ext)
	var R := 7.0
	var side := -along
	var turn_p := final_p + f * R + side * R
	var k := clampf(from_p.distance_to(turn_p) * 0.4, 3.0, 12.0)
	var fwd := bezier(from_p, from_p + from_d * k, turn_p - side * k, turn_p)
	var rev := bezier(turn_p, turn_p - side * R * 0.55, final_p + f * R * 0.55, final_p)
	return {"fwd": fwd, "rev": rev, "pos": Vector3(final_p.x, level, final_p.y), "yaw": yaw_facing(f)}


func gate_world() -> Vector3:
	return Vector3(gate.x, level, gate.y)

