class_name TrafficModels
extends RefCounted
## Visual templates for traffic vehicles: extracted Construction Simulator cars if available,
## otherwise simple procedural cars/trucks/buses. Each instance carries light quads (meta "lights").

static var entries: Array = []   # {kind, scene: PackedScene or null, length, color}
static var _mats := {}
static var _ready := false

const PALETTE := [Color(0.92, 0.92, 0.91), Color(0.08, 0.08, 0.09), Color(0.62, 0.63, 0.65), Color(0.14, 0.2, 0.36),
	Color(0.55, 0.08, 0.07), Color(0.36, 0.37, 0.38), Color(0.82, 0.82, 0.8), Color(0.2, 0.28, 0.22)]


static func prepare() -> void:
	if _ready:
		return
	_ready = true
	entries.clear()
	var dir := "res://assets/consim"
	if DirAccess.dir_exists_absolute(dir):
		for d in DirAccess.get_directories_at(dir):
			var kind := ""
			if d.begins_with("car_"):
				kind = "car"
			elif d.begins_with("truck_traffic"):
				kind = "truck"
			elif d.begins_with("bus"):
				kind = "bus"
			if kind == "":
				continue
			var path := "%s/%s/%s.glb" % [dir, d, d]
			if ResourceLoader.exists(path):
				entries.append({"kind": kind, "scene": load(path), "name": d})
	var has := {}
	for e in entries:
		has[e.kind] = true
	for i in 6:
		if not has.has("car"):
			entries.append({"kind": "car", "scene": null, "color": PALETTE[i]})
	if not has.has("truck"):
		entries.append({"kind": "truck", "scene": null, "color": Color(0.9, 0.9, 0.88)})
		entries.append({"kind": "truck", "scene": null, "color": Color(0.15, 0.3, 0.6)})
	if not has.has("bus"):
		entries.append({"kind": "bus", "scene": null, "color": Color(0.85, 0.12, 0.1)})


static func pick(kind: String, rng: RandomNumberGenerator) -> int:
	var idx: Array = []
	for i in entries.size():
		if entries[i].kind == kind:
			idx.append(i)
	if idx.is_empty():
		return 0
	return idx[rng.randi() % idx.size()]


static func light_mat(name: String) -> ShaderMaterial:
	if _mats.has(name):
		return _mats[name]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/carlight.gdshader")
	match name:
		"head":
			m.set_shader_parameter("color", Color(1.0, 0.95, 0.85))
			m.set_shader_parameter("base", 0.35)
			m.set_shader_parameter("night_gain", 1.0)
		"tail":
			m.set_shader_parameter("color", Color(0.9, 0.05, 0.03))
			m.set_shader_parameter("base", 0.2)
			m.set_shader_parameter("night_gain", 0.45)
		"ind":
			m.set_shader_parameter("color", Color(1.0, 0.55, 0.05))
			m.set_shader_parameter("base", 0.15)
	_mats[name] = m
	return m


static func _std(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func instance(idx: int) -> Node3D:
	var e: Dictionary = entries[idx]
	var root := Node3D.new()
	var length := 4.4
	var width := 1.8
	var height := 1.5
	if e.scene != null:
		var inst: Node3D = e.scene.instantiate()
		root.add_child(inst)
		if e.kind == "car":
			_tint(inst)
		var aabb := _aabb(inst)
		length = aabb.size.z
		width = aabb.size.x
		height = aabb.size.y
	else:
		match e.kind:
			"car":
				_proc_car(root, e.color)
			"truck":
				_proc_truck(root, e.color)
				length = 9.0
				width = 2.5
				height = 3.4
			"bus":
				_proc_bus(root, e.color)
				length = 12.0
				width = 2.55
				height = 3.1
	_add_lights(root, length, width, height)
	return root


static func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		if first:
			box = bb
			first = false
		else:
			box = box.merge(bb)
	return box


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _wheels(parent: Node3D, xs: float, zs: Array, r: float) -> void:
	var m := _std(Color(0.06, 0.06, 0.06), 0.8)
	for z in zs:
		for side in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = r
			c.bottom_radius = r
			c.height = 0.25
			c.radial_segments = 10
			mi.mesh = c
			mi.rotation = Vector3(0, 0, PI * 0.5)
			mi.position = Vector3(xs * side, r, z)
			mi.material_override = m
			parent.add_child(mi)


static func _proc_car(root: Node3D, col: Color) -> void:
	var body := _std(col, 0.35, 0.3)
	var glass := _std(Color(0.08, 0.1, 0.12), 0.1, 0.4)
	_box(root, Vector3(1.78, 0.62, 4.35), Vector3(0, 0.62, 0), body)
	_box(root, Vector3(1.62, 0.52, 2.2), Vector3(0, 1.18, 0.25), glass)
	_box(root, Vector3(1.55, 0.06, 2.0), Vector3(0, 1.46, 0.25), body)
	_wheels(root, 0.82, [-1.35, 1.35], 0.32)


static func _proc_truck(root: Node3D, col: Color) -> void:
	var cab := _std(Color(0.92, 0.92, 0.9), 0.4, 0.2)
	var box := _std(col, 0.6)
	_box(root, Vector3(2.45, 2.3, 2.2), Vector3(0, 1.75, -3.3), cab)
	_box(root, Vector3(2.2, 0.5, 1.0), Vector3(0, 2.0, -4.42), _std(Color(0.1, 0.12, 0.14), 0.1))
	_box(root, Vector3(2.5, 2.7, 6.4), Vector3(0, 2.05, 1.1), box)
	_wheels(root, 1.1, [-3.2, 1.0, 2.4], 0.5)


static func _proc_bus(root: Node3D, col: Color) -> void:
	var b := _std(col, 0.4, 0.2)
	_box(root, Vector3(2.5, 2.6, 11.9), Vector3(0, 1.65, 0), b)
	_box(root, Vector3(2.52, 1.0, 11.0), Vector3(0, 2.15, 0.3), _std(Color(0.07, 0.08, 0.1), 0.1, 0.3))
	_wheels(root, 1.1, [-4.0, 3.6], 0.5)


static func _add_lights(root: Node3D, length: float, width: float, height: float) -> void:
	var lights := {"head": [], "tail": [], "ind_l": [], "ind_r": []}
	var y := clampf(height * 0.42, 0.55, 1.1)
	var hz := -length * 0.5 - 0.02
	var tz := length * 0.5 + 0.02
	for side in [-1.0, 1.0]:
		var hx: float = side * (width * 0.5 - 0.28)
		var h := _quad(root, Vector3(hx, y, hz), Vector2(0.32, 0.14), light_mat("head"))
		lights.head.append(h)
		var t := _quad(root, Vector3(hx, y + 0.05, tz), Vector2(0.3, 0.14), light_mat("tail"))
		lights.tail.append(t)
		var key := "ind_l" if side < 0 else "ind_r"
		lights[key].append(_quad(root, Vector3(side * (width * 0.5 - 0.06), y, hz), Vector2(0.1, 0.1), light_mat("ind")))
		lights[key].append(_quad(root, Vector3(side * (width * 0.5 - 0.06), y + 0.05, tz), Vector2(0.1, 0.1), light_mat("ind")))
	root.set_meta("lights", lights)


static func _quad(root: Node3D, pos: Vector3, size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(size.x, size.y, 0.05)
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func set_lights(v: Node3D, braking: bool, turn: int, t: float) -> void:
	var lights: Dictionary = v.get_meta("lights")
	var b := 1.0 if braking else 0.0
	for q in lights.tail:
		q.set_instance_shader_parameter("on", b)
	var blink := 1.0 if fmod(t, 0.8) < 0.4 else 0.0
	for q in lights.ind_l:
		q.set_instance_shader_parameter("on", blink if turn < 0 else 0.0)
	for q in lights.ind_r:
		q.set_instance_shader_parameter("on", blink if turn > 0 else 0.0)


static var _tints := {}
static var _tint_i := 0
## Car paint variation: materials flagged extras.paint get one of the palette colours.
static func _tint(inst: Node3D) -> void:
	_tint_i += 1
	var col: Color = PALETTE[(_tint_i * 7 + 3) % PALETTE.size()]
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for si in m3.mesh.get_surface_count():
			var m := m3.get_active_material(si)
			if m == null or not (m is BaseMaterial3D):
				continue
			var ex = m.get_meta("extras", {})
			if not (ex is Dictionary and ex.get("paint", false)):
				continue
			var key := "%d_%s" % [m.get_instance_id(), col.to_html()]
			if not _tints.has(key):
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = col
				_tints[key] = d
			m3.set_surface_override_material(si, _tints[key])
