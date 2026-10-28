class_name WorldMarkers
extends Control
## Screen markers ("HUD markers", #7) for the HQ, running sites, job offers and company vehicles.
## On screen a marker sits above its object once the camera is zoomed out; off screen it sticks to the
## edge of the free screen area with an arrow and the distance. Click = select + fly there, right
## click = send the selected vehicle there. Vehicles parked at the HQ or at their site are counted on
## that marker instead of stacking up. Also owns the view bar (marker groups, city buildings on/off,
## keys H and B). Created by the HUD as its first child so all HUD panels stay on top.
## The view settings are stored in <data>/ansicht.json.

const ON_SCREEN_FROM := 280.0     # camera distance (m) where on-screen markers start to fade in
const ON_SCREEN_FADE := 200.0     # ... and are fully visible this much further out
const MERGE_PX := 30.0            # markers of the same group closer than this become one
const EDGE_PAD := 10.0            # gap between edge markers and the border of the free area
const TOP_H := 54.0               # HUD top bar
const RAIL_W := 56.0              # HUD left rail
const BOTTOM_H := 66.0            # hint line + view bar
const BADGE_H := 30.0
const SETTINGS_FILE := "ansicht.json"
const GROUPS := [["vehicles", "truck", "Fahrzeuge"], ["sites", "construction", "Baustellen"],
	["offers", "clipboard-list", "Ausschreibungen"], ["hq", "house", "Zentrale"]]

static var view := {"markers": true, "vehicles": true, "sites": true, "offers": true, "hq": true, "buildings": true}
static var _view_loaded := false
static var persist := true        # tests switch this off so they never leave settings behind

var hud: HUD
var bar: PanelContainer
var free_rect := Rect2()          # screen area not covered by HUD panels; markers stay inside
var markers: Array = []           # MapMarker, the first `used` ones are in use this frame
var used := 0
var _btns := {}
var _layer: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _view_loaded:
		load_view()
	_layer = Control.new()
	_layer.name = "Markers"
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_build_bar()
	apply_buildings()


# ------------------------------------------------------------------------------------------
# View settings and the view bar
# ------------------------------------------------------------------------------------------

static func load_view() -> void:
	_view_loaded = true
	var path := Game.data_path(SETTINGS_FILE)
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		for k in view:
			if d.has(k):
				view[k] = bool(d[k])


static func save_view() -> void:
	if not persist:
		return
	var f := FileAccess.open(Game.data_path(SETTINGS_FILE), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(view, "\t"))


## Switch one view setting (markers, vehicles, sites, offers, hq, buildings) and remember it.
func set_view(key: String, on: bool) -> void:
	if not view.has(key):
		return
	view[key] = on
	save_view()
	if key == "buildings":
		apply_buildings()
	_sync_bar()


## Shows or hides the white city buildings (layer "building" of every map chunk). The HQ hall stays.
func apply_buildings() -> void:
	if Game.world == null or Game.world.city == null:
		return
	var on: bool = view.buildings
	for c in Game.world.city.get_children():
		var b := c.get_node_or_null("building") as Node3D
		if b:
			b.visible = on


func _build_bar() -> void:
	bar = PanelContainer.new()
	bar.name = "ViewBar"
	bar.add_theme_stylebox_override("panel", UI.flat(UI.BG, UI.LINE, 1, 3, Vector4(4, 4, 4, 4)))
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -12
	bar.offset_right = -12
	bar.offset_top = -12
	bar.offset_bottom = -12
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var h := UI.hbox(2)
	bar.add_child(h)
	_bar_button(h, "markers", "map-pin", "Markierungen ein/aus (H)")
	h.add_child(_bar_sep())
	for g in GROUPS:
		_bar_button(h, g[0], g[1], "%s markieren" % g[2])
	h.add_child(_bar_sep())
	_bar_button(h, "buildings", "building-2", "Gebäude ein/aus (B)")
	_sync_bar()


func _bar_button(parent: Control, key: String, icon_name: String, tip: String) -> void:
	var b := UI.icon_button(icon_name, tip, true)
	b.custom_minimum_size = Vector2(34, 34)
	# quieter than the rail: "on" = orange icon on grey, "off" = dim icon
	b.add_theme_stylebox_override("pressed", UI.flat(UI.BG3, Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	b.add_theme_stylebox_override("hover_pressed", UI.flat(UI.LINE, Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	b.add_theme_stylebox_override("disabled", UI.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	b.add_theme_color_override("icon_normal_color", UI.DIM)
	b.add_theme_color_override("icon_hover_color", UI.MUTED)
	b.add_theme_color_override("icon_pressed_color", UI.ACCENT)
	b.add_theme_color_override("icon_hover_pressed_color", UI.ACCENT)
	b.add_theme_color_override("icon_disabled_color", UI.LINE)
	b.toggled.connect(func(on: bool): set_view(key, on))
	parent.add_child(b)
	_btns[key] = b


func _bar_sep() -> ColorRect:
	var s := ColorRect.new()
	s.color = UI.LINE
	s.custom_minimum_size = Vector2(1, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _sync_bar() -> void:
	for k in _btns:
		var b: Button = _btns[k]
		b.set_pressed_no_signal(bool(view[k]))
		b.disabled = k in ["vehicles", "sites", "offers", "hq"] and not view.markers


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match (ev as InputEventKey).keycode:
		KEY_B:
			set_view("buildings", not view.buildings)
			Events.info("Gebäude " + ("eingeblendet" if view.buildings else "ausgeblendet"))
			get_viewport().set_input_as_handled()
		KEY_H:
			set_view("markers", not view.markers)
			Events.info("Markierungen " + ("eingeblendet" if view.markers else "ausgeblendet"))
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------------------
# Markers
# ------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	used = 0
	var w := Game.world as World
	if w == null or w.camera_rig == null or hud == null:
		_hide_unused()
		return
	bar.offset_right = -12.0 - (float(HUD.RIGHT_W) if hud.right.visible else 0.0)
	bar.offset_left = bar.offset_right
	var l := RAIL_W + (float(HUD.LEFT_W) if hud.left.visible else 0.0)
	var r := size.x - (float(HUD.RIGHT_W) if hud.right.visible else 0.0)
	free_rect = Rect2(l, TOP_H, maxf(40.0, r - l), maxf(40.0, size.y - TOP_H - BOTTOM_H))
	if view.markers:
		_place(_collect(w), w)
	_hide_unused()


## Everything that gets a marker this frame, most important first.
func _collect(w: World) -> Array:
	var out: Array = []
	var sel: Object = Game.selected
	var hq_e := {}
	var site_e := {}
	if view.hq and not w.hq_info.is_empty():
		var lc: Vector2 = w.hq_info.get("lot_center", Vector2.ZERO)
		hq_e = _entry("hq", null, Vector3(lc.x, 10.0, lc.y), "house", 0)
		hq_e.title = "Zentrale"
		out.append(hq_e)
	if view.sites:
		for s in w.jobs.all_sites():
			var site: Site = s
			if site.retired:
				continue
			var e := _entry("site", site, site.center3() + Vector3(0, 2.5, 0), "construction", 1)
			e.title = site.job.location()
			e.selected = sel == site
			site_e[site] = e
			out.append(e)
	if view.offers:
		for j in w.jobs.offers:
			var job: Job = j
			var e2 := _entry("offer", job, Vector3(job.center.x, 0.5, job.center.y), "clipboard-list", 3)
			e2.title = Balance.money(job.pay)
			out.append(e2)
	if view.vehicles:
		for veh in w.fleet.vehicles:
			var v: Vehicle = veh
			if not is_instance_valid(v) or v.carried_by != null:
				continue
			if v != sel:
				# parked at the HQ or at its spot on the site: counted there
				if not hq_e.is_empty() and v.at_hq():
					hq_e.members.append(v)
					continue
				if v.site != null and site_e.has(v.site) and v.site.in_place.has(v):
					site_e[v.site].members.append(v)
					continue
			var e3 := _entry("vehicle", v, v.global_position + Vector3(0, v.height + 0.8, 0), _vehicle_icon(v), 2)
			e3.title = v.vname
			e3.selected = v == sel
			e3.members.append(v)
			out.append(e3)
	out.sort_custom(func(a, b): return a.selected and not b.selected or (a.selected == b.selected and a.prio < b.prio))
	return out


func _entry(kind: String, obj: Object, p3: Vector3, icon_name: String, prio: int) -> Dictionary:
	return {"kind": kind, "obj": obj, "p3": p3, "icon": icon_name, "prio": prio, "title": "", "selected": false, "members": []}


func _place(entries: Array, w: World) -> void:
	var cam := w.camera_rig.camera
	var dist := w.camera_rig.distance
	var tgt := w.camera_rig.target
	var fade := clampf((dist - ON_SCREEN_FROM) / ON_SCREEN_FADE, 0.0, 1.0)
	var c := free_rect.get_center()
	var placed: Array = []        # MapMarker of this frame
	for e in entries:
		var p3: Vector3 = e.p3
		var behind := cam.is_position_behind(p3)
		var sp := Vector2.ZERO if behind else cam.unproject_position(p3)
		var on_screen := not behind and free_rect.has_point(sp)
		var alpha := 1.0
		if on_screen and e.kind != "offer":
			alpha = fade
		if alpha <= 0.02:
			continue
		var d := sp - c
		if behind:
			# behind the (tilted) camera: use its local direction, mostly "below the screen"
			var loc: Vector3 = cam.global_transform.affine_inverse() * p3
			d = Vector2(loc.x, -loc.y)
		if d.length() < 0.001:
			d = Vector2(0, 1)
		# same group close together on screen: one marker with a count
		var anchor := sp
		var merged := false
		if e.kind in ["vehicle", "offer"] and not e.selected:
			var probe := sp if on_screen else _edge_point(d.normalized(), 40.0, BADGE_H)
			for pm in placed:
				var m: MapMarker = pm
				if m.kind == e.kind and not m.selected and m.anchor.distance_to(probe) < MERGE_PX:
					m.members.append_array(e.members)
					m.extra += 1
					merged = true
					break
		if merged:
			continue
		var mk := _next_marker()
		mk.kind = e.kind
		mk.obj = e.obj
		mk.focus = Vector3(p3.x, 0.0, p3.z)
		mk.icon_tex = UI.icon(e.icon)
		mk.selected = e.selected
		mk.members = e.members.duplicate()
		mk.extra = 0
		mk.edge = not on_screen
		mk.dir = d.normalized()
		mk.modulate.a = alpha
		var meters := Vector2(p3.x - tgt.x, p3.z - tgt.z).length()
		mk.dist_text = _dist_text(meters)
		mk.title = e.title
		_style(mk, e)
		if on_screen:
			mk.text = mk.title if (e.kind != "vehicle" or e.selected) else ""
		else:
			mk.text = mk.dist_text
		var bw := mk.badge_width()
		if not on_screen:
			anchor = _edge_point(mk.dir, bw, BADGE_H)
			anchor = _avoid_edge_overlap(anchor, bw, placed)
		else:
			anchor = _avoid_stack_overlap(anchor, bw, placed)
		mk.anchor = anchor
		mk.layout(bw)
		placed.append(mk)
	for pm in placed:
		var m2: MapMarker = pm
		m2.update_tip()
		m2.queue_redraw()


## Point on the border of the free area (inset by half a badge) in direction dir from its centre.
func _edge_point(dir: Vector2, bw: float, bh: float) -> Vector2:
	var inner := free_rect.grow_individual(-(bw * 0.5 + EDGE_PAD), -(bh * 0.5 + EDGE_PAD + 8.0), -(bw * 0.5 + EDGE_PAD), -(bh * 0.5 + EDGE_PAD))
	var c := inner.get_center()
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, inner.size.x * 0.5 / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, inner.size.y * 0.5 / absf(dir.y))
	if t == INF:
		t = 0.0
	return c + dir * t


## Slides an edge marker along the border while it overlaps another edge marker.
func _avoid_edge_overlap(p: Vector2, bw: float, placed: Array) -> Vector2:
	var inner := free_rect.grow_individual(-(bw * 0.5 + EDGE_PAD), -(BADGE_H * 0.5 + EDGE_PAD + 8.0), -(bw * 0.5 + EDGE_PAD), -(BADGE_H * 0.5 + EDGE_PAD))
	var vertical := absf(p.x - inner.position.x) < 1.0 or absf(p.x - inner.end.x) < 1.0
	var q := p
	for i in 9:
		var rect := Rect2(q - Vector2(bw * 0.5, BADGE_H * 0.5), Vector2(bw, BADGE_H)).grow(3.0)
		var hit := false
		for pm in placed:
			var m: MapMarker = pm
			if m.edge and m.get_rect().intersects(rect):
				hit = true
				break
		if not hit:
			return q
		var k := floorf((i + 2) * 0.5) * (1.0 if i % 2 == 0 else -1.0)
		q = p + (Vector2(0, (BADGE_H + 6.0) * k) if vertical else Vector2((bw + 6.0) * k, 0))
		q.x = clampf(q.x, inner.position.x, inner.end.x)
		q.y = clampf(q.y, inner.position.y, inner.end.y)
	return q


## On screen: a marker that would cover a more important one (e.g. the selected vehicle at the HQ)
## is stacked above it.
func _avoid_stack_overlap(p: Vector2, bw: float, placed: Array) -> Vector2:
	var q := p
	for i in 4:
		var rect := Rect2(q - Vector2(bw * 0.5, BADGE_H + 8.0), Vector2(bw, BADGE_H)).grow(2.0)
		var hit := false
		for pm in placed:
			var m: MapMarker = pm
			if not m.edge and m.get_rect().intersects(rect):
				hit = true
				break
		if not hit:
			return q
		q.y -= BADGE_H + 6.0
	return q


func _style(mk: MapMarker, e: Dictionary) -> void:
	match e.kind:
		"hq":
			mk.bg = UI.TEXT
			mk.fg = Color(0.04, 0.04, 0.04)
		"site":
			mk.bg = UI.ACCENT
			mk.fg = Color(0.04, 0.04, 0.04)
		"offer":
			mk.bg = UI.BG_SOLID
			mk.fg = UI.ACCENT
		_:
			mk.bg = UI.BG_SOLID
			var v: Vehicle = e.obj
			match v.state:
				"driving":
					mk.fg = UI.TEXT
				"working", "loading":
					mk.fg = UI.ACCENT
				_:
					mk.fg = UI.MUTED


func _next_marker() -> MapMarker:
	if used >= markers.size():
		var m := MapMarker.new()
		m.wm = self
		m.name = "M%d" % markers.size()
		_layer.add_child(m)
		markers.append(m)
	var mk: MapMarker = markers[used]
	used += 1
	mk.visible = true
	return mk


func _hide_unused() -> void:
	for i in range(used, markers.size()):
		var m: MapMarker = markers[i]
		if m.visible:
			m.visible = false
			m.obj = null
			m.members = []


func _dist_text(m: float) -> String:
	if m < 950.0:
		return "%d m" % (int(round(m / 10.0)) * 10)
	return ("%.1f km" % (m / 1000.0)).replace(".", ",")


func _vehicle_icon(v: Vehicle) -> String:
	if v.has_ability("crew"):
		return "users"
	if v.has_ability("dig"):
		return "construction"
	if v.has_ability("lowbed"):
		return "navigation"
	return "truck"


## Marker input: left = select / fly there, right = send the selected vehicle there.
func on_marker_input(m: MapMarker, ev: InputEventMouseButton) -> void:
	var w := Game.world as World
	if w == null:
		return
	var rig := w.camera_rig
	if ev.button_index == MOUSE_BUTTON_LEFT:
		var far := clampf(rig.distance * 0.5, 70.0, 320.0)
		match m.kind:
			"hq":
				Events.request_focus.emit(m.focus, minf(rig.distance, 220.0))
			"site":
				Game.select(m.obj)
				Events.request_focus.emit((m.obj as Site).center3(), minf(rig.distance, 160.0))
			"offer":
				if hud and hud.left_mode != "jobs":
					hud.open_left("jobs")
				Events.request_focus.emit(m.focus, minf(rig.distance, 260.0))
			"vehicle":
				if m.members.size() > 1:
					# a group: fly there and zoom in so the group splits up
					var sum := Vector3.ZERO
					for mv in m.members:
						sum += (mv as Vehicle).global_position
					Events.request_focus.emit(sum / m.members.size(), maxf(60.0, rig.distance * 0.35))
				elif is_instance_valid(m.obj):
					Game.select(m.obj)
					Events.request_focus.emit((m.obj as Vehicle).global_position, far)
	elif ev.button_index == MOUSE_BUTTON_RIGHT:
		if not (Game.selected is Vehicle) or not is_instance_valid(Game.selected):
			Events.info("Erst ein Fahrzeug wählen, dann mit Rechtsklick auf die Markierung hinschicken")
			return
		var sel := Game.selected as Vehicle
		match m.kind:
			"hq":
				sel.command_at(m.focus, null)
			"site":
				sel.command_at((m.obj as Site).center3(), m.obj)
			"vehicle":
				if m.members.size() == 1 and m.obj != sel and is_instance_valid(m.obj):
					sel.command_at((m.obj as Vehicle).global_position, m.obj)


## One marker on screen. Draws itself; the parent WorldMarkers fills it every frame.
class MapMarker extends Control:
	var wm: WorldMarkers
	var kind := ""
	var obj: Object = null
	var focus := Vector3.ZERO
	var icon_tex: Texture2D
	var title := ""
	var text := ""
	var dist_text := ""
	var members: Array = []       # vehicles counted on this marker
	var extra := 0                # merged markers of the same group (offers)
	var selected := false
	var edge := false
	var dir := Vector2.DOWN
	var anchor := Vector2.ZERO
	var bg := UI.BG_SOLID
	var fg := UI.TEXT
	var _hover := false
	var _sb := StyleBoxFlat.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_sb.set_corner_radius_all(4)
		_sb.anti_aliasing = true
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())

	func count() -> int:
		# number shown in the bubble: vehicles parked at the HQ / site, or the size of a group
		if kind in ["hq", "site"]:
			return members.size()
		if kind == "offer":
			return extra + 1 if extra > 0 else 0
		return members.size() if members.size() > 1 else 0

	func badge_width() -> float:
		var t := text
		if kind == "vehicle" and _hover and not edge and t == "" and members.size() == 1:
			t = (members[0] as Vehicle).vname
		if t == "":
			return WorldMarkers.BADGE_H
		return WorldMarkers.BADGE_H + UI.font(600).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 9.0

	func layout(bw: float) -> void:
		size = Vector2(bw, WorldMarkers.BADGE_H)
		if edge:
			position = anchor - size * 0.5
		else:
			position = anchor - Vector2(bw * 0.5, WorldMarkers.BADGE_H + 8.0)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		_sb.bg_color = bg.lightened(0.12) if _hover else bg
		_sb.border_color = UI.ACCENT if kind != "site" else UI.TEXT
		_sb.set_border_width_all(2 if selected else 0)
		var cen := size * 0.5
		if edge:
			# arrow outside the badge, pointing at the object
			var t := INF
			if absf(dir.x) > 0.0001:
				t = minf(t, cen.x / absf(dir.x))
			if absf(dir.y) > 0.0001:
				t = minf(t, cen.y / absf(dir.y))
			var base := cen + dir * (t + 2.0)
			var side := Vector2(-dir.y, dir.x) * 6.0
			draw_colored_polygon(PackedVector2Array([base + side, base + dir * 8.0, base - side]), bg)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(cen.x - 6.0, size.y - 1.0), Vector2(cen.x + 6.0, size.y - 1.0), Vector2(cen.x, size.y + 8.0)]), bg)
		_sb.draw(get_canvas_item(), r)
		if icon_tex:
			draw_texture_rect(icon_tex, Rect2(6, 6, 18, 18), false, fg)
		var t2 := text
		if kind == "vehicle" and _hover and not edge and t2 == "" and members.size() == 1:
			t2 = (members[0] as Vehicle).vname
		if t2 != "":
			var f := UI.font(600)
			var y := (size.y + f.get_ascent(12) - f.get_descent(12)) * 0.5
			draw_string(f, Vector2(WorldMarkers.BADGE_H - 1.0, y), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fg)
		var n := count()
		if n > 0:
			var bc := Vector2(size.x - 2.0, 1.0)
			var ns := str(n)
			var f2 := UI.font(700)
			var nw := f2.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var rad := maxf(8.0, nw * 0.5 + 4.0)
			draw_circle(bc, rad, UI.BG_SOLID if kind == "site" else UI.ACCENT)
			draw_string(f2, Vector2(bc.x - nw * 0.5, bc.y + 3.5), ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.TEXT if kind == "site" else Color(0.04, 0.04, 0.04))

	func update_tip() -> void:
		var lines: Array = []
		match kind:
			"hq":
				lines.append("Zentrale" + ("  ·  " + dist_text if edge else ""))
				if not members.is_empty():
					lines.append("%d Fahrzeug%s hier: %s" % [members.size(), "" if members.size() == 1 else "e", _names()])
				lines.append("Klick: hinfliegen · Rechtsklick: gewähltes Fahrzeug heimschicken")
			"site":
				var s: Site = obj
				if is_instance_valid(s):
					lines.append("Baustelle %s · %s" % [s.job.short_title(), s.job.location()] + ("  ·  " + dist_text if edge else ""))
					lines.append("%d/%d %s: %s" % [s.phase + 1, Site.STEPS.size(), Site.STEPS[mini(s.phase, Site.STEPS.size() - 1)].title, s.status])
				if not members.is_empty():
					lines.append("Vor Ort: " + _names())
				lines.append("Klick: öffnen · Rechtsklick: gewähltes Fahrzeug hinschicken")
			"offer":
				var j: Job = obj
				lines.append("Ausschreibung: %s · %s" % [j.title(), j.location()] + ("  ·  " + dist_text if edge else ""))
				lines.append(title + (" (+%d weitere in der Nähe)" % extra if extra > 0 else ""))
				lines.append("Klick: zeigen")
			_:
				if members.size() > 1:
					lines.append("%d Fahrzeuge%s" % [members.size(), "  ·  " + dist_text if edge else ""])
					for mv in members:
						lines.append("%s · %s" % [(mv as Vehicle).vname, (mv as Vehicle).status_text])
					lines.append("Klick: hinfliegen")
				elif members.size() == 1:
					var v: Vehicle = members[0]
					lines.append(v.vname + ("  ·  " + dist_text if edge else ""))
					lines.append(v.status_text)
					lines.append("Klick: auswählen · Rechtsklick: gewähltes Fahrzeug hinschicken (z. B. auf Tieflader)")
		var tip := "\n".join(lines)
		if tip != tooltip_text:
			tooltip_text = tip

	func _names() -> String:
		var parts: Array = []
		for mv in members:
			parts.append((mv as Vehicle).vname)
		return ", ".join(parts)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			accept_event()
			wm.on_marker_input(self, ev as InputEventMouseButton)
