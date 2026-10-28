class_name UndergroundView
extends Node3D
## Underground view (#31, key U or the view bar): the city dims, roads and railways below the surface show on
## top of it (chunk layers "under_*", made at bake time) and vehicles in tunnels appear as bright boxes.
## Off by default and not remembered: the game always starts with the normal view.

const ROAD := Color(1.0, 0.62, 0.22, 0.9)       # road tunnels: orange like the UI accent
const RAIL := Color(0.32, 0.86, 0.46, 0.85)     # S-Bahn and main line tunnels: green
const SUBWAY := Color(0.30, 0.60, 1.0, 0.85)    # U-Bahn: blue
const DIM := Color(0.02, 0.03, 0.06, 0.8)       # veil over the surface (AgX tonemapping eats much of it)
const CAR := Color(0.96, 0.96, 0.96, 1.0)
const OWN := Color(0.25, 0.92, 1.0, 1.0)        # company vehicles

static var on := false

var world: World
var _veil: MeshInstance3D
var _boxes: MultiMeshInstance3D


static func is_layer(lname: String) -> bool:
	return lname.begins_with("under_")


func setup(w: World) -> void:
	world = w
	var b := w.bounds
	# a large plane just below the lowest ground, drawn over the city without depth test: the camera is always
	# above it, and it lies close to the ground so the far plane cuts it about where it cuts the ground
	var low := 0.0
	if Terrain.cur:
		var hs: PackedFloat32Array = Terrain.cur.h
		for i in range(0, hs.size(), 7):
			low = minf(low, hs[i])
	var pm := PlaneMesh.new()
	pm.size = b.size * 4.0 + Vector2(4000, 4000)
	_veil = MeshInstance3D.new()
	_veil.name = "Veil"
	_veil.mesh = pm
	_veil.position = Vector3(b.get_center().x, low - 5.0, b.get_center().y)
	_veil.material_override = _flat(DIM, 1, false)
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_veil.extra_cull_margin = 16384.0
	add_child(_veil)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = 0
	_boxes = MultiMeshInstance3D.new()
	_boxes.name = "TunnelVehicles"
	_boxes.multimesh = mm
	_boxes.material_override = _flat(Color.WHITE, 20, true)
	_boxes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boxes.extra_cull_margin = 16384.0
	add_child(_boxes)
	apply()


static func _flat(c: Color, priority: int, vertex_color: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = priority
	m.vertex_color_use_as_albedo = vertex_color
	return m


func set_on(v: bool) -> void:
	on = v
	apply()


## Shows or hides the underground layers of every map chunk, the veil and the tunnel vehicles.
func apply() -> void:
	if world and world.city:
		for holder in world.city.get_children():
			for c in holder.get_children():
				if is_layer(String(c.name)):
					(c as Node3D).visible = on
	if _veil:
		_veil.visible = on
		_boxes.visible = on
	if not on and _boxes:
		_boxes.multimesh.instance_count = 0


func _process(_delta: float) -> void:
	if not on or world == null or world.traffic == null:
		return
	var tr := world.traffic
	var xs: Array = []
	var cols: Array = []
	for ag in tr.agents:
		if not tr.in_tunnel(ag):
			continue
		var p: Vector3 = ag.p_prev.lerp(ag.p_cur, tr.alpha)
		var yaw := lerp_angle(ag.yaw_prev, ag.yaw_cur, tr.alpha)
		var bs := Basis(Vector3.UP, yaw).scaled(Vector3(maxf(ag.width, 1.8), 1.6, ag.length))
		xs.append(Transform3D(bs, p + Vector3(0, 0.8, 0)))
		cols.append(OWN if ag.player != null else CAR)
	var mm := _boxes.multimesh
	if mm.instance_count != xs.size():
		mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
