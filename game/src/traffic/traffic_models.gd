class_name TrafficModels
extends RefCounted
## Visual templates for traffic vehicles: extracted Construction Simulator cars if available,
## otherwise simple procedural cars/trucks/buses. Lights (meta "lights"): models with their own lamp
## glass light that glass (carlamp shader); the others get lamp boxes set onto the body surface.

static var entries: Array = []   # {kind, scene: PackedScene or null, length, color}
static var _mats := {}
static var _ready := false
const LAMP_FN := {"__light_head": 0, "__light_tail": 1, "__light_brake": 2, "__indicator_l": 3, "__indicator_r": 4,
	"__light_reverse": 5}
const BOX_SIZE := {"head": Vector2(0.32, 0.14), "tail": Vector2(0.3, 0.14), "ind_l": Vector2(0.1, 0.1), "ind_r": Vector2(0.1, 0.1)}
const BOX_MAT := {"head": "head", "tail": "tail", "ind_l": "ind", "ind_r": "ind"}
static var _lamp_mats := {}      # "<material id>_<fn>_<tail_brakes>" -> ShaderMaterial (shared by all cars)
static var _spots := {}          # entry index -> Array of [kind, Transform3D] for lamp boxes

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
	if e.scene != null:
		var inst: Node3D = e.scene.instantiate()
		root.add_child(inst)
		if e.kind == "car":
			_tint(inst)
		var glass := _glass(e, inst)
		if not glass.is_empty():
			root.set_meta("lights", {"glass": glass})
			return root
	else:
		match e.kind:
			"car":
				_proc_car(root, e.color)
			"truck":
				_proc_truck(root, e.color)
			"bus":
				_proc_bus(root, e.color)
	_add_lights(root, idx)
	return root


## The model's own lamp glass (materials *__light_head / __light_tail / __light_brake / __indicator_l/r)
## switched to the shared carlamp shader. Returns the MeshInstances carrying it, [] if the model lacks
## head, tail-or-brake or indicator glass (then it gets lamp boxes instead).
static func _glass(e: Dictionary, inst: Node3D) -> Array:
	if not e.has("lamp_fns"):
		var found := {}
		for sf in _lamp_surfaces(inst):
			found[sf[2]] = true
		var complete: bool = found.has(0) and (found.has(1) or found.has(2)) and found.has(3) and found.has(4)
		e["lamp_fns"] = found if complete else {}
	var fns: Dictionary = e.lamp_fns
	if fns.is_empty():
		return []
	var meshes: Array = []
	for sf in _lamp_surfaces(inst):
		var mi: MeshInstance3D = sf[0]
		var orig := mi.get_active_material(sf[1]) as BaseMaterial3D
		mi.set_surface_override_material(sf[1], _lamp_mat(orig, sf[2], not fns.has(2)))
		if not meshes.has(mi):
			meshes.append(mi)
	return meshes


## [MeshInstance3D, surface index, lamp function] for every lamp glass surface of a model.
static func _lamp_surfaces(inst: Node3D) -> Array:
	var out: Array = []
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			if m == null or not (m is BaseMaterial3D):
				continue
			for suf in LAMP_FN:
				if m.resource_name.ends_with(suf):
					out.append([mi, si, LAMP_FN[suf]])
	return out


static func _lamp_mat(orig: BaseMaterial3D, fn: int, tail_brakes: bool) -> ShaderMaterial:
	var key := "%d_%d_%s" % [orig.get_instance_id(), fn, tail_brakes]
	if _lamp_mats.has(key):
		return _lamp_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/carlamp.gdshader")
	m.set_shader_parameter("albedo_tex", orig.albedo_texture)
	m.set_shader_parameter("albedo", orig.albedo_color)
	m.set_shader_parameter("use_normal", orig.normal_enabled and orig.normal_texture != null)
	m.set_shader_parameter("normal_tex", orig.normal_texture)
	m.set_shader_parameter("normal_scale", orig.normal_scale)
	m.set_shader_parameter("rough_tex", orig.roughness_texture)
	m.set_shader_parameter("rough_channel", _channel(orig.roughness_texture_channel))
	m.set_shader_parameter("roughness", orig.roughness)
	m.set_shader_parameter("metal_tex", orig.metallic_texture)
	m.set_shader_parameter("metal_channel", _channel(orig.metallic_texture_channel))
	m.set_shader_parameter("metallic", orig.metallic)
	m.set_shader_parameter("use_ao", orig.ao_enabled and orig.ao_texture != null)
	m.set_shader_parameter("ao_tex", orig.ao_texture)
	m.set_shader_parameter("ao_channel", _channel(orig.ao_texture_channel))
	m.set_shader_parameter("specular", orig.metallic_specular)
	m.set_shader_parameter("fn", fn)
	m.set_shader_parameter("tail_brakes", tail_brakes)
	_lamp_mats[key] = m
	return m


static func _channel(c: int) -> Vector4:
	match c:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return Vector4(0.333333, 0.333333, 0.333333, 0)


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


static func _add_lights(root: Node3D, idx: int) -> void:
	var lights := {"head": [], "tail": [], "ind_l": [], "ind_r": []}
	for sp in _lamp_spots(root, idx):
		var kind: String = sp[0]
		lights[kind].append(_quad(root, sp[1], BOX_SIZE[kind], light_mat(BOX_MAT[kind])))
	root.set_meta("lights", lights)


## Where the lamp boxes of a model go: at its light markers (or default spots for procedural models),
## pushed onto the body surface and turned to face along it. Cached per model.
static func _lamp_spots(root: Node3D, idx: int) -> Array:
	if _spots.has(idx):
		return _spots[idx]
	var out: Array = []
	var faces := VehicleModels.model_faces(root)
	if faces.is_empty():
		return out
	var box := AABB(faces[0], Vector3.ZERO)
	for v in faces:
		box = box.expand(v)
	var names := {"light_head_": "head", "light_tail_": "tail", "light_brake_": "tail", "indicator_fl": "ind_l",
		"indicator_rl": "ind_l", "indicator_fr": "ind_r", "indicator_rr": "ind_r"}
	var want: Array = []   # [kind, nominal position]
	for n in root.find_children("*", "Node3D", true, false):
		for pre in names:
			if String(n.name).begins_with(pre):
				want.append([names[pre], _pos_in(n, root)])
	if want.is_empty():
		var y := clampf(box.size.y * 0.42, 0.55, 1.1)
		var cx := box.get_center().x
		for side in [-1.0, 1.0]:
			var hx: float = cx + side * (box.size.x * 0.5 - 0.28)
			var ix: float = cx + side * (box.size.x * 0.5 - 0.06)
			var ik := "ind_l" if side < 0 else "ind_r"
			want.append(["head", Vector3(hx, y, box.position.z)])
			want.append(["tail", Vector3(hx, y + 0.05, box.end.z)])
			want.append([ik, Vector3(ix, y, box.position.z)])
			want.append([ik, Vector3(ix, y + 0.05, box.end.z)])
	for w in want:
		var p: Vector3 = w[1]
		var lift := 0.012
		if String(w[0]).begins_with("ind") and _overlaps_lamp(want, w):
			lift = 0.034   # indicator in the same spot as a head/tail box: in front of it, else it is hidden
		out.append([w[0], _on_surface(faces, box, p, p.z < box.get_center().z, lift)])
	_spots[idx] = out
	return out


static func _overlaps_lamp(want: Array, ind: Array) -> bool:
	var p: Vector3 = ind[1]
	for o in want:
		var q: Vector3 = o[1]
		if (o[0] == "head" or o[0] == "tail") and signf(q.z) == signf(p.z) and absf(q.y - p.y) < 0.12 \
				and absf(q.x - p.x) < (BOX_SIZE[o[0]].x + BOX_SIZE[ind[0]].x) * 0.5:
			return true
	return false


## A lamp box transform at nominal position p: shot along the vehicle axis from outside onto the
## body (front lamps from the front, rear lamps from behind), `lift` proud of the surface and facing
## out along the hit triangle (straight out if that is more than 60 deg off). If nothing is hit
## within 35 cm of p, p itself.
static func _on_surface(faces: PackedVector3Array, box: AABB, p: Vector3, front: bool, lift: float) -> Transform3D:
	var dir := Vector3.BACK if front else Vector3.FORWARD
	var o := Vector3(p.x, p.y, box.position.z - 1.0 if front else box.end.z + 1.0)
	var best := INF
	var hit := p
	var nrm := -dir
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if minf(a.x, minf(b.x, c.x)) > p.x or maxf(a.x, maxf(b.x, c.x)) < p.x:
			continue
		if minf(a.y, minf(b.y, c.y)) > p.y or maxf(a.y, maxf(b.y, c.y)) < p.y:
			continue
		var h = Geometry3D.ray_intersects_triangle(o, dir, a, b, c)
		if h == null:
			continue
		var d := absf((h as Vector3).z - o.z)
		if d < best:
			best = d
			hit = h
			nrm = (b - a).cross(c - a).normalized()
	if best == INF or absf(hit.z - p.z) > 0.35:
		return Transform3D(Basis(), p)
	if nrm.dot(dir) > 0.0:
		nrm = -nrm
	if nrm.dot(-dir) < 0.5:
		nrm = -dir
	var x := Vector3.UP.cross(nrm).normalized()
	return Transform3D(Basis(x, nrm.cross(x), nrm), hit + nrm * lift)


## Position of node n in the space of its ancestor root (works outside the scene tree).
static func _pos_in(n: Node, root: Node) -> Vector3:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf.origin


static func _quad(root: Node3D, xf: Transform3D, size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(size.x, size.y, 0.02)
	mi.mesh = b
	mi.transform = xf
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func set_lights(v: Node3D, braking: bool, turn: int, t: float) -> void:
	var lights: Dictionary = v.get_meta("lights")
	var b := 1.0 if braking else 0.0
	var blink := 1.0 if fmod(t, 0.8) < 0.4 else 0.0
	var l := blink if turn < 0 else 0.0
	var r := blink if turn > 0 else 0.0
	var val := Vector4(b, l, r, 0.0)
	if lights.get("val", Vector4(-1, -1, -1, -1)) == val:
		return
	lights["val"] = val
	for mi in lights.get("glass", []):
		(mi as MeshInstance3D).set_instance_shader_parameter("lamp", val)
	for q in lights.get("tail", []):
		q.set_instance_shader_parameter("on", b)
	for q in lights.get("ind_l", []):
		q.set_instance_shader_parameter("on", l)
	for q in lights.get("ind_r", []):
		q.set_instance_shader_parameter("on", r)


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
