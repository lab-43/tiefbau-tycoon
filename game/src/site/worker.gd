class_name Worker
extends Node3D
## A construction worker (orange high-vis, white helmet). Walks along straight paths and plays simple
## activity poses. Driven by the site: walk_to(), then do(action, seconds).

signal reached(w: Worker)
signal done(w: Worker)

const SPEED := 1.7

var target := Vector3.ZERO
var path: Array = []           # Vector3 waypoints
var walking := false
var action := ""
var action_t := 0.0
var carry: Node3D = null
var tool_node: Node3D = null
var busy := false
var task: Dictionary = {}
var _phase := 0.0
var _legs: Array = []
var _arms: Array = []
var _torso: Node3D
var _cb: Callable = Callable()

static var _mats := {}


static func _m(name: String, c: Color, rough := 0.8) -> StandardMaterial3D:
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[name] = m
	return _mats[name]


func _ready() -> void:
	_build()


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build() -> void:
	var trousers := _m("trousers", Color(0.16, 0.18, 0.22))
	var vest := _m("vest", Color(1.0, 0.42, 0.05), 0.6)
	var stripe := _m("stripe", Color(0.85, 0.86, 0.84), 0.3)
	var skin := _m("skin", Color(0.86, 0.66, 0.52))
	var helmet := _m("helmet", Color(0.96, 0.96, 0.94), 0.4)
	var boots := _m("boots", Color(0.12, 0.1, 0.08))
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, 0.9, 0)
		add_child(hip)
		_box(hip, Vector3(0.14, 0.84, 0.16), Vector3(0, -0.44, 0), trousers)
		_box(hip, Vector3(0.15, 0.1, 0.26), Vector3(0, -0.86, -0.04), boots)
		_legs.append(hip)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.9, 0)
	add_child(_torso)
	_box(_torso, Vector3(0.4, 0.58, 0.24), Vector3(0, 0.3, 0), vest)
	_box(_torso, Vector3(0.41, 0.05, 0.25), Vector3(0, 0.18, 0), stripe)
	_box(_torso, Vector3(0.41, 0.05, 0.25), Vector3(0, 0.36, 0), stripe)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.24
	sm.radial_segments = 10
	sm.rings = 6
	head.mesh = sm
	head.position = Vector3(0, 0.74, 0)
	head.material_override = skin
	_torso.add_child(head)
	var hel := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.135
	hm.height = 0.15
	hm.is_hemisphere = true
	hm.radial_segments = 10
	hm.rings = 4
	hel.mesh = hm
	hel.position = Vector3(0, 0.79, 0)
	hel.material_override = helmet
	_torso.add_child(hel)
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.25 * side, 0.55, 0)
		_torso.add_child(sh)
		_box(sh, Vector3(0.1, 0.56, 0.12), Vector3(0, -0.27, 0), vest)
		_box(sh, Vector3(0.08, 0.1, 0.08), Vector3(0, -0.58, 0), skin)
		_arms.append(sh)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Walk to a point (y is used: walk down into a pit by giving a lower y). cb(worker) on arrival.
func walk_to(p: Vector3, cb: Callable = Callable()) -> void:
	path = [p]
	walking = true
	_cb = cb


func walk_path(points: Array, cb: Callable = Callable()) -> void:
	path = points.duplicate()
	walking = not path.is_empty()
	_cb = cb
	if not walking and cb.is_valid():
		cb.call(self)


## Play an activity for seconds, then cb(worker). action: idle | work | place | dig | compact | rake | cut
func act(a: String, seconds: float, cb: Callable = Callable()) -> void:
	action = a
	action_t = seconds
	_cb = cb


func set_tool(n: Node3D) -> void:
	if tool_node:
		tool_node.queue_free()
	tool_node = n
	if n:
		add_child(n)
		n.position = Vector3(0, 0, -0.55)


func hold(n: Node3D) -> void:
	carry = n
	if n:
		if n.get_parent():
			n.get_parent().remove_child(n)
		add_child(n)
		n.position = Vector3(0, 0.25, -0.35)
		n.rotation = Vector3.ZERO
		n.scale = Vector3.ONE * 0.75


func release_carry() -> Node3D:
	var n := carry
	carry = null
	if n:
		n.scale = Vector3.ONE
	return n


func face(p: Vector3) -> void:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z)
	if d.length() > 0.05:
		rotation.y = atan2(-d.x, -d.y)


func _process(delta: float) -> void:
	var anim_speed := 0.0
	if walking and not path.is_empty():
		var p: Vector3 = path[0]
		var to := p - position
		var dist := Vector2(to.x, to.z).length()
		var step := SPEED * delta
		if dist <= step:
			position = p
			path.pop_front()
			if path.is_empty():
				walking = false
				reached.emit(self)
				var cb := _cb
				_cb = Callable()
				if cb.is_valid():
					cb.call(self)
		else:
			var dir := Vector3(to.x, 0, to.z).normalized()
			position += dir * step
			position.y = lerpf(position.y, p.y, clampf(step / maxf(dist, 0.01), 0.0, 1.0))
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.25)
			anim_speed = 1.0
	elif action != "":
		action_t -= delta
		if action_t <= 0.0:
			var a := action
			action = ""
			done.emit(self)
			var cb2 := _cb
			_cb = Callable()
			if cb2.is_valid():
				cb2.call(self)
			if a == "":
				pass
	_phase += delta * (7.5 if anim_speed > 0.0 else 0.0)
	var swing := sin(_phase) * 0.5 * anim_speed
	if _legs.size() == 2:
		(_legs[0] as Node3D).rotation.x = swing
		(_legs[1] as Node3D).rotation.x = -swing
	if _arms.size() == 2:
		var arm_base := 0.0
		var t := Time.get_ticks_msec() * 0.001
		match action:
			"place", "dig", "cut":
				arm_base = -0.9 + sin(t * 6.0) * 0.25
				_torso.rotation.x = -0.35
			"compact":
				arm_base = -0.6
				_torso.rotation.x = -0.1
				position.x += sin(t * 40.0) * 0.002
			"rake":
				arm_base = -0.7 + sin(t * 3.0) * 0.35
				_torso.rotation.x = -0.25
			_:
				_torso.rotation.x = lerpf(_torso.rotation.x, 0.0, 0.2)
		if carry:
			arm_base = -1.2
		(_arms[0] as Node3D).rotation.x = -swing * 0.8 + arm_base
		(_arms[1] as Node3D).rotation.x = swing * 0.8 + arm_base
