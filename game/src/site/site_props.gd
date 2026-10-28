class_name SiteProps
extends RefCounted
## Construction site props: barrier models (FS25 German road safety set, private use), procedural signs
## 208/308/250 on the real sign stand, pipes, plate compactor, yellow temporary markings.

const BARRIERS := {
	"schranke": "res://assets/barriers/01_absperrschranke.glb",
	"fence": "res://assets/barriers/01_absperrschranke.glb",
	"bake": "res://assets/barriers/02_leitbake.glb",
	"cone": "res://assets/barriers/04_leitkegel.glb",
	"z123": "res://assets/barriers/05_z123.glb",
	"z274": "res://assets/barriers/06_z274.glb",
	"z208": "res://assets/barriers/05_z123.glb",
	"z308": "res://assets/barriers/05_z123.glb",
	"z250": "res://assets/barriers/05_z123.glb",
}
const LABEL := {"schranke": "Absperrschranke", "fence": "Absperrgitter", "bake": "Leitbake", "cone": "Leitkegel",
	"z123": "Zeichen 123", "z274": "Zeichen 274", "z208": "Zeichen 208", "z308": "Zeichen 308",
	"z250": "Zeichen 250"}

static var _scenes := {}
static var _warn_mat: ShaderMaterial
static var _sign_tex := {}


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


static func warn_mat() -> ShaderMaterial:
	if _warn_mat == null:
		_warn_mat = ShaderMaterial.new()
		_warn_mat.shader = load("res://assets/shaders/warnlight.gdshader")
	return _warn_mat


## Barrier item. Faces +Z (towards approaching traffic when yawed with yaw_facing(travel_dir)).
## Absperrschranke/fence origin is at its left end and extends 2.14 m along +X.
static func item(kind: String, phase := 0.0) -> Node3D:
	var ps := _scene(BARRIERS.get(kind, ""))
	var n: Node3D
	if ps:
		n = ps.instantiate()
	else:
		n = _fallback(kind)
	n.set_meta("kind", kind)
	var lights_on := kind in ["schranke", "bake"]
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in ["schranke", "fence"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m3.mesh.get_surface_count():
			var mat := m3.get_active_material(si)
			if mat and mat.resource_name == "statics_emissive_mat":
				m3.set_surface_override_material(si, warn_mat())
				m3.set_instance_shader_parameter("phase", phase)
				m3.set_instance_shader_parameter("on", 1.0 if lights_on else 0.0)
	if kind in ["fence", "cone"]:
		for w in n.find_children("Warnleuchte*", "Node3D", true, false):
			w.visible = false
	if kind in ["z208", "z308", "z250"]:
		for nm in ["Dreieck_900mm", "2-123"]:
			var hide := n.find_child(nm, true, false)
			if hide:
				hide.visible = false
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.62, 0.62)
		face.mesh = q
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = sign_texture(kind)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		fm.alpha_scissor_threshold = 0.5
		fm.roughness = 0.6
		fm.cull_mode = BaseMaterial3D.CULL_BACK
		face.material_override = fm
		face.position = Vector3(0, 2.62, 0.035)
		n.add_child(face)
		var back := MeshInstance3D.new()
		back.mesh = q
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.55, 0.56, 0.57)
		bm.albedo_texture = sign_texture(kind)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		bm.alpha_scissor_threshold = 0.5
		back.material_override = bm
		back.position = Vector3(0, 2.62, 0.028)
		back.rotation.y = PI
		n.add_child(back)
	return n


## Changes the running-light phase of an item's warning lights (a changed closure plan, #9).
static func set_phase(n: Node3D, phase: float) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			if m3.get_surface_override_material(si) == warn_mat():
				m3.set_instance_shader_parameter("phase", phase)


static func _fallback(kind: String) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	match kind:
		"schranke", "fence":
			b.size = Vector3(2.0, 0.25, 0.05)
			mi.position = Vector3(1.0, 1.0, 0)
		"bake":
			b.size = Vector3(0.25, 1.0, 0.05)
			mi.position = Vector3(0, 0.7, 0)
		_:
			b.size = Vector3(0.6, 0.6, 0.05)
			mi.position = Vector3(0, 2.2, 0)
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.12, 0.08)
	mi.material_override = m
	n.add_child(mi)
	return n


## Sign faces drawn procedurally (Zeichen 208: round, red rim, red arrow up / black arrow down;
## Zeichen 308: blue square, white arrow up / red arrow down; Zeichen 250: round, red rim, white).
static func sign_texture(kind: String) -> Texture2D:
	if _sign_tex.has(kind):
		return _sign_tex[kind]
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var red := Color(0.78, 0.07, 0.09)
	var white := Color(0.97, 0.97, 0.96)
	var black := Color(0.05, 0.05, 0.06)
	var blue := Color(0.0, 0.32, 0.65)
	for y in S:
		for x in S:
			var u := (x + 0.5) / S * 2.0 - 1.0
			var v := (y + 0.5) / S * 2.0 - 1.0
			var c := Color(0, 0, 0, 0)
			if kind == "z250":
				var r0 := sqrt(u * u + v * v)
				if r0 <= 1.0:
					c = red if r0 > 0.78 else white
			elif kind == "z208":
				var r := sqrt(u * u + v * v)
				if r <= 1.0:
					c = red if r > 0.8 else white
					# left: red arrow up, right: black arrow down
					if _arrow(u + 0.27, v, true, 0.52, 0.11):
						c = red
					if _arrow(u - 0.27, v, false, 0.52, 0.11):
						c = black
			else:
				if absf(u) < 0.97 and absf(v) < 0.97:
					c = blue
					if absf(u) > 0.9 or absf(v) > 0.9:
						c = white
					if _arrow(u + 0.25, v, true, 0.62, 0.14):
						c = white
					if _arrow(u - 0.32, v, false, 0.42, 0.09):
						c = red
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_sign_tex[kind] = tex
	return tex


## Arrow centred at origin, pointing up (image v negative) if up. half_len: half length, w: shaft half width.
static func _arrow(u: float, v: float, up: bool, half_len: float, w: float) -> bool:
	var t := -v if up else v      # along the arrow, positive = towards the tip
	if t < -half_len or t > half_len:
		return false
	var head := half_len * 0.42
	if t > half_len - head:
		var k := (half_len - t) / head
		return absf(u) < w * 2.6 * k
	return absf(u) < w


## Pipe segment along Z (centred), bottom at y = 0. kind: "new" | "old".
static func pipe(kind: String, length: float, diameter := 0.4) -> Node3D:
	var id := "pipe_new_10m" if kind == "new" else "pipe_old_10m"
	var ps := _scene("res://assets/consim/%s/%s.glb" % [id, id])
	var holder := Node3D.new()
	holder.set_meta("kind", "pipe_" + kind)
	if ps:
		var p: Node3D = ps.instantiate()
		p.scale = Vector3(diameter / 1.1, diameter / 1.1, length / 10.0)
		holder.add_child(p)
	else:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = diameter * 0.5
		cm.bottom_radius = diameter * 0.5
		cm.height = length
		mi.mesh = cm
		mi.rotation.x = PI * 0.5
		mi.position.y = diameter * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.15, 0.35, 0.75) if kind == "new" else Color(0.35, 0.3, 0.27)
		mi.material_override = m
		holder.add_child(mi)
	return holder


static func plate_compactor() -> Node3D:
	var n := Node3D.new()
	var base := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.45, 0.08, 0.6)
	base.mesh = b
	base.position.y = 0.04
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.2, 0.2)
	base.material_override = m
	n.add_child(base)
	var eng := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = Vector3(0.35, 0.3, 0.32)
	eng.mesh = b2
	eng.position = Vector3(0, 0.25, 0.05)
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = Color(0.95, 0.75, 0.1)
	eng.material_override = m2
	n.add_child(eng)
	var handle := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.015
	c.bottom_radius = 0.015
	c.height = 1.0
	handle.mesh = c
	handle.position = Vector3(0, 0.55, 0.45)
	handle.rotation.x = deg_to_rad(-50.0)
	handle.material_override = m
	n.add_child(handle)
	return n


## Ribbon mesh along a polyline (temporary yellow marking 0.12 m), y slightly above white markings.
static func ribbon(pts: PackedVector2Array, width: float, y: float, mat: Material) -> MeshInstance3D:
	var l := MeshLayer.new()
	if Terrain.cur != null:
		# on slopes (#8): short pieces lifted onto the ground
		l.terrain = Terrain.cur
		pts = Geo.densify(pts, 3.0)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a)
		if d.length() < 0.01:
			continue
		var n := Geo.right_of(d.normalized()) * width * 0.5
		var n0 := n
		var n1 := n
		if i > 0:
			var dp := (a - pts[i - 1]).normalized()
			n0 = Geo.right_of((dp + d.normalized()).normalized()) * width * 0.5
		if i + 2 < pts.size():
			var dn := (pts[i + 2] - b).normalized()
			n1 = Geo.right_of((d.normalized() + dn).normalized()) * width * 0.5
		l.quad(Geo.v3(a - n0, y), Geo.v3(a + n0, y), Geo.v3(b + n1, y), Geo.v3(b - n1, y), Vector3.UP)
	var mi := MeshInstance3D.new()
	if not l.is_empty():
		mi.mesh = l.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
