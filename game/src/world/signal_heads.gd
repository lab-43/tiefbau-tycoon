class_name SignalHeads
extends Node3D
## Traffic signal poles and heads at signalised junctions. Lamp colours follow TrafficSim.signal_state()
## (updated a few times per second for heads near the camera).

const RANGE := 650.0

var world: World
var heads: Array = []            # {pos: Vector3, node: int, phase: int}
var lamp_mm: MultiMesh
var _t := 0.0
static var _mats := {}


func setup(w: World) -> void:
	world = w
	var net := w.net
	for ni in net.nodes.size():
		var nd: Dictionary = net.nodes[ni]
		if nd.ctrl != "signals" or not nd.has("infos"):
			continue
		for inf in nd.infos:
			var e: int = inf.edge
			var dir_in := 1 if inf.start else 0
			if net.lane_count(e, dir_in) == 0:
				continue
			var d: Vector2 = inf.d
			var J: Vector2 = inf.get("p", nd.pos)   # merged junction groups: each road ends at its own point
			var p: Vector2 = J + d * (inf.s + 0.8) - Geo.right_of(d) * (inf.hw + 0.7)
			var gy := Terrain.cur.road_height(p, -1, ni) if Terrain.cur else 0.0
			heads.append({"pos": Vector3(p.x, gy, p.y), "yaw": atan2(d.x, d.y), "node": ni, "phase": nd.phases.get(inf.ref, 0)})
	_build()


func _mat(name: String, c: Color, unshaded := false) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
	_mats[name] = m
	return m


func _build() -> void:
	if heads.is_empty():
		return
	# static part: pole + housing
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.07
	pole.height = 3.4
	pole.radial_segments = 8
	st.append_from(pole, 0, Transform3D(Basis(), Vector3(0, 1.7, 0)))
	var box := BoxMesh.new()
	box.size = Vector3(0.32, 0.95, 0.24)
	st.append_from(box, 0, Transform3D(Basis(), Vector3(0, 2.85, 0.16)))
	var plate := BoxMesh.new()
	plate.size = Vector3(0.55, 1.2, 0.03)
	st.append_from(plate, 0, Transform3D(Basis(), Vector3(0, 2.85, 0.03)))
	var mesh := st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = heads.size()
	for i in heads.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, heads[i].yaw), heads[i].pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat("housing", Color(0.08, 0.085, 0.09))
	mmi.visibility_range_end = 1400.0
	add_child(mmi)
	# lamps: 3 per head, colour per instance
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.2)
	lamp_mm = MultiMesh.new()
	lamp_mm.transform_format = MultiMesh.TRANSFORM_3D
	lamp_mm.use_colors = true
	lamp_mm.mesh = q
	lamp_mm.instance_count = heads.size() * 3
	for i in heads.size():
		var b := Basis(Vector3.UP, heads[i].yaw)
		for k in 3:
			var off := Vector3(0, 3.15 - k * 0.3, 0.29)
			lamp_mm.set_instance_transform(i * 3 + k, Transform3D(b, heads[i].pos + b * off))
			lamp_mm.set_instance_color(i * 3 + k, Color(0.12, 0.12, 0.12))
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lamp_mm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lmi.material_override = lm
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lmi.visibility_range_end = 1400.0
	add_child(lmi)


func _process(delta: float) -> void:
	if lamp_mm == null or world.traffic == null:
		return
	_t += delta
	if _t < 0.2:
		return
	_t = 0.0
	var focus := world.camera_rig.target if world.camera_rig else Vector3.ZERO
	var off := Color(0.10, 0.10, 0.10)
	var red := Color(1.0, 0.08, 0.05) * 2.2
	var amber := Color(1.0, 0.55, 0.0) * 2.2
	var green := Color(0.1, 1.0, 0.45) * 2.2
	for i in heads.size():
		var h: Dictionary = heads[i]
		if Vector2(h.pos.x - focus.x, h.pos.z - focus.z).length() > RANGE:
			continue
		var st: Array = world.traffic.signal_state(h.node)
		var ph: int = h.phase
		var r := off
		var a := off
		var g := off
		if st[0] == ph:
			if st[1]:
				a = amber
			else:
				g = green
		else:
			r = red
		red.a = 1.0
		lamp_mm.set_instance_color(i * 3, r)
		lamp_mm.set_instance_color(i * 3 + 1, a)
		lamp_mm.set_instance_color(i * 3 + 2, g)
