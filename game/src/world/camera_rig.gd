class_name CameraRig
extends Node3D
## Shapez-2-style strategy camera.
## WASD/arrows pan, Shift faster, Q/E rotate, mouse wheel zooms to cursor, RMB drag grabs the map,
## RMB short click = context command, MMB drag rotates (x) and tilts (y), F follows the selection.

signal clicked_right(screen_pos: Vector2)

const MIN_DIST := 7.0
const MAX_DIST := 4200.0

var camera: Camera3D
var target := Vector3.ZERO
var yaw := deg_to_rad(-30.0)
var pitch := deg_to_rad(52.0)
var distance := 380.0
var bounds := Rect2(-3000, -3000, 6000, 6000)
var follow: Node3D = null
var input_enabled := true

var _t_target := Vector3.ZERO
var _t_yaw := 0.0
var _t_pitch := 0.0
var _t_distance := 380.0
var _rmb_down := false
var _rmb_moved := 0.0
var _rmb_time := 0
var _rmb_start := Vector2.ZERO
var _grab_point := Vector3.ZERO
var _grab_valid := false
var _mmb_down := false
var _last_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 42.0
	add_child(camera)
	camera.current = true
	_t_target = target
	_t_yaw = yaw
	_t_pitch = pitch
	_t_distance = distance
	Events.request_focus.connect(focus_on)
	_apply()


func set_view(t: Vector3, dist: float, yaw_deg: float = -30.0, pitch_deg: float = 52.0, instant := true) -> void:
	_t_target = t
	_t_distance = clampf(dist, MIN_DIST, MAX_DIST)
	_t_yaw = deg_to_rad(yaw_deg)
	_t_pitch = deg_to_rad(pitch_deg)
	if instant:
		target = _t_target
		distance = _t_distance
		yaw = _t_yaw
		pitch = _t_pitch
		_apply()


func focus_on(pos: Vector3, dist: float) -> void:
	follow = null
	_t_target = Vector3(pos.x, 0.0, pos.z)
	if dist > 0.0:
		_t_distance = clampf(dist, MIN_DIST, MAX_DIST)


func _min_pitch_for(dist: float) -> float:
	var t := clampf((dist - 60.0) / 1800.0, 0.0, 1.0)
	return deg_to_rad(lerpf(18.0, 50.0, t))


## Ground point (y = 0 plane) under a screen position.
func ground_point(screen: Vector2, plane_y := 0.0) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return null
	return from + dir * t


func _unhandled_input(ev: InputEvent) -> void:
	if not input_enabled:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var factor := 0.84 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.84
					_zoom_at(mb.position, factor)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_rmb_down = true
					_rmb_moved = 0.0
					_rmb_time = Time.get_ticks_msec()
					_rmb_start = mb.position
					var gp = ground_point(mb.position)
					_grab_valid = gp != null
					if _grab_valid:
						_grab_point = gp
				else:
					if _rmb_down and _rmb_moved < 7.0 and Time.get_ticks_msec() - _rmb_time < 450:
						clicked_right.emit(mb.position)
					_rmb_down = false
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE:
				_mmb_down = mb.pressed
				get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _rmb_down:
			_rmb_moved += mm.relative.length()
			if _grab_valid and _rmb_moved >= 4.0:
				follow = null
				_drag_to(mm.position)
			get_viewport().set_input_as_handled()
		elif _mmb_down:
			_t_yaw -= mm.relative.x * 0.0055
			_t_pitch = clampf(_t_pitch + mm.relative.y * 0.0045, _min_pitch_for(_t_distance), deg_to_rad(88.0))
			get_viewport().set_input_as_handled()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_F and follow == null and Game.selected is Node3D:
			follow = Game.selected
		elif ev.keycode == KEY_F and follow != null:
			follow = null


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before = ground_point(screen)
	var new_dist := clampf(_t_distance * factor, MIN_DIST, MAX_DIST)
	if before != null and follow == null:
		# move target toward cursor proportionally so the point under the cursor stays put
		var k := 1.0 - new_dist / _t_distance
		var tgt_flat := Vector3(_t_target.x, 0.0, _t_target.z)
		var bp: Vector3 = before
		_t_target = tgt_flat + (Vector3(bp.x, 0.0, bp.z) - tgt_flat) * k
	_t_distance = new_dist
	_t_pitch = maxf(_t_pitch, _min_pitch_for(_t_distance))


func _drag_to(screen: Vector2) -> void:
	# keep the grabbed ground point under the cursor (computed with the current target camera)
	_apply_values(_t_target, _t_yaw, _t_pitch, _t_distance)
	var now = ground_point(screen)
	_apply_values(target, yaw, pitch, distance)
	if now == null:
		return
	var delta: Vector3 = _grab_point - now
	delta.y = 0.0
	_t_target += delta
	target += delta


func _process(delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	var dt := 0.016 if _last_usec == 0 else clampf(float(now_usec - _last_usec) / 1_000_000.0, 0.0, 0.1)
	_last_usec = now_usec
	if input_enabled and not _text_focus():
		var move := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if move != Vector2.ZERO:
			follow = null
			var speed := _t_distance * 0.95 * (2.6 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			var fwd := Vector3(-sin(_t_yaw), 0.0, -cos(_t_yaw))
			var right := Vector3(cos(_t_yaw), 0.0, -sin(_t_yaw))
			_t_target += (right * move.x + fwd * -move.y) * speed * dt
		if Input.is_key_pressed(KEY_Q):
			_t_yaw += 1.6 * dt
		if Input.is_key_pressed(KEY_E):
			_t_yaw -= 1.6 * dt
		if Input.is_key_pressed(KEY_PAGEUP):
			_t_pitch = clampf(_t_pitch + 0.9 * dt, _min_pitch_for(_t_distance), deg_to_rad(88.0))
		if Input.is_key_pressed(KEY_PAGEDOWN):
			_t_pitch = clampf(_t_pitch - 0.9 * dt, _min_pitch_for(_t_distance), deg_to_rad(88.0))
	if follow and is_instance_valid(follow):
		var fp: Vector3 = follow.center3() if follow.has_method("center3") else follow.global_position
		_t_target = Vector3(fp.x, 0.0, fp.z)
	elif follow:
		follow = null
	_t_target.x = clampf(_t_target.x, bounds.position.x, bounds.end.x)
	_t_target.z = clampf(_t_target.z, bounds.position.y, bounds.end.y)
	var k := 1.0 - exp(-dt * 12.0)
	var kz := 1.0 - exp(-dt * 9.0)
	target = target.lerp(_t_target, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	distance = lerpf(distance, _t_distance, kz)
	_apply()


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _apply() -> void:
	_apply_values(target, yaw, pitch, distance)
	camera.near = clampf(distance * 0.003, 0.05, 4.0)
	camera.far = clampf(distance * 10.0, 2500.0, 16000.0)


func _apply_values(t: Vector3, y: float, p: float, d: float) -> void:
	var offset := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d
	camera.global_position = t + offset
	camera.look_at(t, Vector3.UP)
