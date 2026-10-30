class_name PitPreview
extends Node3D
## Ghost of the pit under the mouse while the debug tool "Auftrag platzieren" is active (#33): the trench
## marked on the asphalt (outline, hatching), the room behind it where excavator and tipper stand, and a
## label with size and depth, reason or hints. Orange = a contract fits here,
## red = it does not (drawn where the click would be). Owned by PlaceJobTool, lives in the World.

const BAD := Color(0.92, 0.22, 0.16)
const RIM := 0.12              # m width of the outline on the asphalt

var _fill: MeshInstance3D
var _rim: MeshInstance3D
var _zone: MeshInstance3D
var _label: Label3D
var _mats := {}
var info := {}                 # last check_spot result (tests)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fill = _mesh_node()
	_rim = _mesh_node()
	_zone = _mesh_node()
	_label = Label3D.new()
	_label.font = UI.font(600)
	_label.font_size = 40
	_label.pixel_size = 0.012
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.width = 900.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_label)
	visible = false


func _mesh_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _mat(c: Color, see_through: bool) -> StandardMaterial3D:
	var k := "%s_%s" % [c.to_html(), see_through]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = see_through
	m.render_priority = 10 if see_through else 2
	_mats[k] = m
	return m


func hide_preview() -> void:
	visible = false
	info = {}


## Shows the result r of JobManager.check_spot for pipe (width) at the hovered map point p.
func show_result(r: Dictionary, pipe: Dictionary, net: RoadNet) -> void:
	info = r
	var L: float = r.get("L", 4.0)
	var D: float = r.get("D", 1.8)
	var W: float = pipe.get("width", 1.2)
	var ok: bool = r.get("ok", false)
	var col: Color = UI.ACCENT if ok else BAD
	var c := Vector2.ZERO
	var d := Vector2.RIGHT
	var zone := PackedVector2Array()
	if ok:
		var lay: SiteLayout = r.lay
		c = lay.trench_center()
		d = lay.trench_dir()
		# where excavator and tipper stand behind the pit (they reverse in from behind)
		zone = lay.lane_poly(lay.s_t1 + 0.3, lay.s_c1, func(_s): return 0.0, 1.0)
	elif r.has("probe"):
		var g: Array = net.lane_geo[int(r.probe.key)]
		var smp := Geo.sample(g[0], g[1], float(r.probe.s))
		c = smp[0]
		d = smp[1]
	else:
		visible = false
		return
	visible = true
	var rt := Geo.right_of(d)
	var corners := [c - d * L * 0.5 - rt * W * 0.5, c + d * L * 0.5 - rt * W * 0.5, c + d * L * 0.5 + rt * W * 0.5, c - d * L * 0.5 + rt * W * 0.5]
	_draw_box(_fill.mesh, corners, SiteTerrain.Y_ROAD + 0.02, SiteTerrain.Y_ROAD - D, Color(col, 0.32))
	_draw_rim(_rim.mesh, corners, SiteTerrain.Y_ROAD + 0.05, col)
	_fill.material_override = _mat(Color(col, 0.28), true)
	_rim.material_override = _mat(col, true)
	(_zone.mesh as ImmediateMesh).clear_surfaces()
	if zone.size() >= 2:
		_draw_dashed_frame(_zone.mesh, zone, 2.3, SiteTerrain.Y_ROAD + 0.05)
		_zone.material_override = _mat(Color(1, 1, 1, 0.75), true)
	var lines: Array = ["Graben %s × %s m, %s m tief" % [_n(L), _n(W), _n(D)]]
	if ok:
		lines.append("Linksklick: Auftrag hier platzieren")
		for h in r.get("hints", []):
			lines.append("· " + str(h))
	else:
		lines.append(str(r.get("error", "")))
	_label.text = "\n".join(lines)
	_label.modulate = Color(1, 1, 1) if ok else Color(1.0, 0.75, 0.7)
	_label.position = Site.gw(c, 4.5)


static func _n(x: float) -> String:
	return ("%.1f" % x).replace(".", ",")


## The pit as it is marked on the asphalt before digging: a filled rectangle with diagonal hatching (a
## see-through box below the road read like a box standing on it).
func _draw_box(im: ImmediateMesh, q: Array, y_top: float, _y_bot: float, _c: Color) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(im, Site.gw(q[0], y_top), Site.gw(q[1], y_top), Site.gw(q[2], y_top), Site.gw(q[3], y_top))
	im.surface_end()


func _draw_rim(im: ImmediateMesh, q: Array, y: float, _c: Color) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctr: Vector2 = (q[0] + q[2]) * 0.5
	for i in 4:
		var a: Vector2 = q[i]
		var b: Vector2 = q[(i + 1) % 4]
		var ai := a + (ctr - a).normalized() * RIM * 1.4
		var bi := b + (ctr - b).normalized() * RIM * 1.4
		_quad(im, Site.gw(a, y), Site.gw(b, y), Site.gw(bi, y), Site.gw(ai, y))
	# hatching across the pit every 0.6 m (q: 0→1 along the lane, 1→2 across)
	var along: Vector2 = q[1] - q[0]
	var across: Vector2 = q[3] - q[0]
	var ln := along.length()
	var w := across.length()
	var d := along / maxf(0.01, ln)
	var n := across / maxf(0.01, w)
	var k := -w
	while k < ln:
		var p0: Vector2 = q[0] + d * maxf(0.0, k)
		var off0 := maxf(0.0, -k)
		p0 += n * off0
		var t := minf(ln - maxf(0.0, k), w - off0)
		if t > 0.05:
			var p1 := p0 + (d + n) * t
			var hw := (Geo.right_of((d + n).normalized())) * 0.04
			_quad(im, Site.gw(p0 - hw, y), Site.gw(p1 - hw, y), Site.gw(p1 + hw, y), Site.gw(p0 + hw, y))
		k += 0.6
	im.surface_end()


## Dashed outline of a band of the given width along pts (where excavator and tipper will stand).
func _draw_dashed_frame(im: ImmediateMesh, pts: PackedVector2Array, width: float, y: float) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in pts.size():
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var n := Geo.right_of(d) * width * 0.5
		left.append(pts[i] - n)
		right.append(pts[i] + n)
	var last := pts.size() - 1
	var lines: Array = [left, right, PackedVector2Array([left[0], right[0]]), PackedVector2Array([left[last], right[last]])]
	for line: PackedVector2Array in lines:
		var cum := Geo.cumulative(line)
		var total: float = cum[cum.size() - 1]
		var s := 0.0
		while s < total:
			var seg := Geo.sub_polyline(line, cum, s, minf(total, s + 0.8))
			for k in seg.size() - 1:
				var a := seg[k]
				var b := seg[k + 1]
				var w := Geo.right_of((b - a).normalized()) * 0.05
				_quad(im, Site.gw(a - w, y), Site.gw(b - w, y), Site.gw(b + w, y), Site.gw(a + w, y))
			s += 1.4
	im.surface_end()


static func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		im.surface_add_vertex(v)
