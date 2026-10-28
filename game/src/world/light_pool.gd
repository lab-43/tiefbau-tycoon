class_name LightPool
extends Node3D
## A small pool of real OmniLights moved to the street lamps closest to the camera at night.
## (Lamp heads themselves glow via the emissive lamp material everywhere.)

const POOL := 28
const HEAD_OFFSET := Vector3(0, 6.75, -1.35)

var world: World
var lamps: PackedVector3Array = PackedVector3Array()
var lights: Array = []
var _grid := {}
var _t := 0.0


func setup(w: World, lamp_chunks: Dictionary) -> void:
	world = w
	for ck in lamp_chunks:
		for xf in lamp_chunks[ck]:
			var t: Transform3D = xf
			var p := t * HEAD_OFFSET
			var idx := lamps.size()
			lamps.append(p)
			var cell := Vector2i(int(floor(p.x / 100.0)), int(floor(p.z / 100.0)))
			if not _grid.has(cell):
				_grid[cell] = PackedInt32Array()
			_grid[cell].append(idx)
	for i in POOL:
		var l := OmniLight3D.new()
		l.omni_range = 17.0
		l.omni_attenuation = 1.2
		l.light_color = Color(1.0, 0.82, 0.58)
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		lights.append(l)


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	var night: float = world.day_night.night if world.day_night else 0.0
	if night < 0.12 or lamps.is_empty():
		for l in lights:
			l.visible = false
		return
	var cam := world.camera_rig
	var focus := cam.target
	var r := clampf(cam.distance * 1.4, 120.0, 420.0)
	var c := Vector2i(int(floor(focus.x / 100.0)), int(floor(focus.z / 100.0)))
	var n := int(ceil(r / 100.0))
	var cand: Array = []
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for idx in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var p := lamps[idx]
				var d := Vector2(p.x - focus.x, p.z - focus.z).length()
				if d < r:
					cand.append([d, idx])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in lights.size():
		var l: OmniLight3D = lights[i]
		if i < cand.size():
			l.visible = true
			l.position = lamps[cand[i][1]]
			l.light_energy = 1.6 * night
		else:
			l.visible = false
