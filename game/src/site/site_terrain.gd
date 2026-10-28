class_name SiteTerrain
extends Node3D
## Heightfield of an excavation pit in the road. Heights are relative to the road surface (0 = road level).
## The road shaders cut a hole of exactly this grid's size (global pit_aN / pit_bN), so the grid replaces the
## road surface there. Supports bites (dig), fills (by layer), levelling/compaction and volume bookkeeping.

const RES := 0.1
const MARGIN := 0.15
const Y_ROAD := 0.05
const ASPHALT := 0.12

var center := Vector2.ZERO
var dir := Vector2.RIGHT          # along the trench
var right := Vector2.DOWN
var L := 4.0                      # trench length (inner)
var W := 1.3
var depth := 1.8
var hl := 0.0
var hw := 0.0
var nu := 0
var nv := 0
var h := PackedFloat32Array()
var refill := PackedByteArray()
var compacted := PackedByteArray()
var fresh := PackedByteArray()
var sand_top := -1.2
var pit_slot := -1
var mi: MeshInstance3D
var mat: ShaderMaterial
var _dirty := true


func setup(c: Vector2, d: Vector2, length: float, width: float, dep: float, sand_level: float) -> void:
	center = c
	dir = d.normalized()
	right = Geo.right_of(dir)
	L = length
	W = width
	depth = dep
	sand_top = sand_level
	hl = L * 0.5 + MARGIN
	hw = W * 0.5 + MARGIN
	nu = int(ceil(hl * 2.0 / RES)) + 1
	nv = int(ceil(hw * 2.0 / RES)) + 1
	h.resize(nu * nv)
	h.fill(0.0)
	refill.resize(nu * nv)
	refill.fill(0)
	compacted.resize(nu * nv)
	compacted.fill(0)
	fresh.resize(nu * nv)
	fresh.fill(0)
	mi = MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mat = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/terrain.gdshader")
	mat.set_shader_parameter("sand_top", sand_top)
	mi.material_override = mat
	add_child(mi)
	_rebuild()


func cell_u(i: int) -> float:
	return -hl + i * (hl * 2.0) / (nu - 1)


func cell_v(j: int) -> float:
	return -hw + j * (hw * 2.0) / (nv - 1)


func idx(i: int, j: int) -> int:
	return j * nu + i


func inner(i: int, j: int) -> bool:
	return absf(cell_u(i)) <= L * 0.5 + 0.001 and absf(cell_v(j)) <= W * 0.5 + 0.001


func to_world(u: float, v: float, hh := 0.0) -> Vector3:
	var p := center + dir * u + right * v
	return Vector3(p.x, Terrain.at(p) + Y_ROAD + hh, p.y)


func local_of(p: Vector3) -> Vector2:
	var d := Vector2(p.x, p.z) - center
	return Vector2(d.dot(dir), d.dot(right))


func cell_area() -> float:
	return (hl * 2.0 / (nu - 1)) * (hw * 2.0 / (nv - 1))


## Enables the road cut-out for this pit (slot 0..3).
func set_hole(slot: int, on: bool) -> void:
	pit_slot = slot
	if slot < 0:
		return
	var a := Vector4(center.x, center.y, dir.x, dir.y)
	var b := Vector4(hl - RES * 0.5 * 0.0, hw, 1.0 if on else 0.0, 0.0)
	RenderingServer.global_shader_parameter_set("pit_a%d" % slot, a)
	RenderingServer.global_shader_parameter_set("pit_b%d" % slot, b)


# ------------------------------------------------------------------------------------------
# Volumes
# ------------------------------------------------------------------------------------------

func remaining_dig() -> float:
	var v := 0.0
	var a := cell_area()
	for j in nv:
		for i in nu:
			if inner(i, j):
				v += maxf(0.0, h[idx(i, j)] + depth) * a
	return v


func total_dig() -> float:
	return inner_area() * depth


## Area of the diggable cells (the grid discretisation is slightly larger than L × W).
func inner_area() -> float:
	var n := 0
	for j in nv:
		for i in nu:
			if inner(i, j):
				n += 1
	return n * cell_area()


func fill_needed(top: float) -> float:
	var v := 0.0
	var a := cell_area()
	for j in nv:
		for i in nu:
			if inner(i, j):
				v += maxf(0.0, top - h[idx(i, j)]) * a
	return v


func mean_height() -> float:
	var s := 0.0
	var n := 0
	for j in nv:
		for i in nu:
			if inner(i, j):
				s += h[idx(i, j)]
				n += 1
	return s / maxf(1.0, float(n))


func min_height() -> float:
	var m := 0.0
	for j in nv:
		for i in nu:
			if inner(i, j):
				m = minf(m, h[idx(i, j)])
	return m


# ------------------------------------------------------------------------------------------
# Digging
# ------------------------------------------------------------------------------------------

## Picks the next bite: returns {u0, u1, v, depth_start} (local), u0 = far end (away from the machine),
## machine_u = local u of the excavator turret (bites are dragged towards it).
func next_bite(machine_u: float) -> Dictionary:
	var lanes := [0.0] if W < 1.0 else [-W * 0.22, W * 0.22]
	var strip := 1.3
	var best := {}
	var best_score := -1.0
	var sgn := signf(machine_u) if machine_u != 0.0 else 1.0
	var u_far := -sgn * L * 0.5
	var u := u_far
	while (u - u_far) * sgn <= L + 0.01:
		var ua := u
		var ub := u + sgn * strip
		ub = clampf(ub, -L * 0.5, L * 0.5)
		for v in lanes:
			var rem := _strip_remaining(ua, ub, v, 0.45)
			if rem < 0.02:
				continue
			# prefer deep remaining material, then the far end
			var dist_bonus := 1.0 - absf(ua - u_far) / (L + 0.01) * 0.25
			var score := rem * dist_bonus
			if score > best_score:
				best_score = score
				best = {"u0": ua, "u1": ub, "v": v}
		u += sgn * 0.6
	if best.is_empty():
		return {}
	best["top"] = _strip_top(best.u0, best.u1, best.v, 0.45)
	return best


func _strip_remaining(ua: float, ub: float, v: float, half_w: float) -> float:
	var rem := 0.0
	var lo := minf(ua, ub)
	var hi := maxf(ua, ub)
	for j in nv:
		var cv := cell_v(j)
		if absf(cv - v) > half_w:
			continue
		for i in nu:
			var cu := cell_u(i)
			if cu < lo or cu > hi or not inner(i, j):
				continue
			rem += maxf(0.0, h[idx(i, j)] + depth)
	return rem * cell_area()


func _strip_top(ua: float, ub: float, v: float, half_w: float) -> float:
	var top := -depth
	var lo := minf(ua, ub)
	var hi := maxf(ua, ub)
	for j in nv:
		if absf(cell_v(j) - v) > half_w:
			continue
		for i in nu:
			var cu := cell_u(i)
			if cu < lo or cu > hi or not inner(i, j):
				continue
			top = maxf(top, h[idx(i, j)])
	return top


## Removes up to `volume` m³ (bank) from the strip, partially (fraction of a bite). Returns removed volume.
func dig_strip(b: Dictionary, volume: float) -> float:
	var lo := minf(b.u0, b.u1)
	var hi := maxf(b.u0, b.u1)
	var cells: Array = []
	for j in nv:
		var cv := cell_v(j)
		var wv := 1.0 - clampf((absf(cv - b.v) - 0.3) / 0.2, 0.0, 1.0)
		if wv <= 0.0:
			continue
		for i in nu:
			var cu := cell_u(i)
			if cu < lo - 0.1 or cu > hi + 0.1 or not inner(i, j):
				continue
			var wu := 1.0 - clampf((maxf(lo - cu, cu - hi)) / 0.1, 0.0, 1.0)
			cells.append([idx(i, j), wv * wu])
	if cells.is_empty():
		return 0.0
	var a := cell_area()
	var removed := 0.0
	# iterative: lower all cells by a common step weighted by w until the volume is reached
	for it in 6:
		var want := volume - removed
		if want <= 0.0005:
			break
		var wsum := 0.0
		for c in cells:
			if h[c[0]] > -depth + 0.001:
				wsum += c[1]
		if wsum <= 0.0:
			break
		var step := want / (wsum * a)
		for c in cells:
			var k: int = c[0]
			var cur := h[k]
			var nh := maxf(-depth, cur - step * c[1])
			removed += (cur - nh) * a
			h[k] = nh
			refill[k] = 0
	_dirty = true
	return removed


# ------------------------------------------------------------------------------------------
# Filling
# ------------------------------------------------------------------------------------------

## Deposits `volume` m³ (bank) around a local point, never above `top`. Most of it settles to the lowest cells.
func fill_at(local_p: Vector2, volume: float, top: float, mark_fresh := false) -> float:
	var a := cell_area()
	var placed := 0.0
	# 60 % as a mound near the drop point
	var mound := volume * 0.6
	var cells: Array = []
	var wsum := 0.0
	for j in nv:
		for i in nu:
			if not inner(i, j):
				continue
			var d := Vector2(cell_u(i), cell_v(j)).distance_to(local_p)
			if d < 1.1:
				var w := exp(-d * d / 0.35)
				cells.append([idx(i, j), w])
				wsum += w
	if wsum > 0.0:
		for c in cells:
			var k: int = c[0]
			var add: float = mound * c[1] / wsum / a
			var nh := minf(top, h[k] + add)
			placed += (nh - h[k]) * a
			if nh > h[k] + 0.0001:
				h[k] = nh
				refill[k] = 1
				compacted[k] = 0
				if mark_fresh:
					fresh[k] = 1
	# the rest levels out (lowest cells first)
	var rest := volume - placed
	for it in 30:
		if rest <= 0.0005:
			break
		var low := INF
		var count := 0
		for j in nv:
			for i in nu:
				if inner(i, j) and h[idx(i, j)] < top - 0.0005:
					low = minf(low, h[idx(i, j)])
		if low == INF:
			break
		var band := low + 0.05
		for j in nv:
			for i in nu:
				if inner(i, j) and h[idx(i, j)] <= band and h[idx(i, j)] < top:
					count += 1
		if count == 0:
			break
		var dh := minf(rest / (count * a), 0.05)
		for j in nv:
			for i in nu:
				var k2 := idx(i, j)
				if inner(i, j) and h[k2] <= band and h[k2] < top:
					var nh2 := minf(top, h[k2] + dh)
					rest -= (nh2 - h[k2]) * a
					placed += (nh2 - h[k2]) * a
					h[k2] = nh2
					refill[k2] = 1
					compacted[k2] = 0
					if mark_fresh:
						fresh[k2] = 1
	_dirty = true
	return placed


## Lowest point (local) of the trench surface below `top`, for choosing drop points.
func lowest_spot(top: float) -> Vector2:
	var best := Vector2.ZERO
	var bh := INF
	for j in range(1, nv - 1, 2):
		for i in range(1, nu - 1, 2):
			if not inner(i, j):
				continue
			var hh := h[idx(i, j)]
			if hh < top and hh < bh:
				bh = hh
				best = Vector2(cell_u(i), cell_v(j))
	return best


## Levels and compacts the trench surface: a pass of the plate compactor. strength 0..1 per pass.
func compact(strength := 1.0) -> void:
	var m := mean_height()
	for j in nv:
		for i in nu:
			if inner(i, j):
				var k := idx(i, j)
				h[k] = lerpf(h[k], m, 0.6 * strength)
				compacted[k] = 1
	_dirty = true


func set_fresh_all() -> void:
	for j in nv:
		for i in nu:
			if inner(i, j):
				fresh[idx(i, j)] = 1
				refill[idx(i, j)] = 1
				h[idx(i, j)] = 0.0
	_dirty = true


func surface_world(local_p: Vector2) -> Vector3:
	var i := clampi(int(round((local_p.x + hl) / (hl * 2.0) * (nu - 1))), 0, nu - 1)
	var j := clampi(int(round((local_p.y + hw) / (hw * 2.0) * (nv - 1))), 0, nv - 1)
	return to_world(local_p.x, local_p.y, h[idx(i, j)])


# ------------------------------------------------------------------------------------------
# Mesh
# ------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _dirty:
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nu * nv)
	norms.resize(nu * nv)
	cols.resize(nu * nv)
	var du := hl * 2.0 / (nu - 1)
	var dv := hw * 2.0 / (nv - 1)
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D()
	for j in nv:
		for i in nu:
			var k := idx(i, j)
			var wp := to_world(cell_u(i), cell_v(j), h[k])
			verts[k] = inv * wp
			var hx0 := h[idx(maxi(i - 1, 0), j)]
			var hx1 := h[idx(mini(i + 1, nu - 1), j)]
			var hz0 := h[idx(i, maxi(j - 1, 0))]
			var hz1 := h[idx(i, mini(j + 1, nv - 1))]
			var gu := (hx1 - hx0) / (du * 2.0)
			var gv := (hz1 - hz0) / (dv * 2.0)
			var n2 := -dir * gu - right * gv
			if Terrain.cur != null:
				n2 -= Terrain.cur.gradient(wp.x, wp.z)   # the road under the pit slopes too (#8)
			norms[k] = inv.basis * Vector3(n2.x, 1.0, n2.y).normalized()
			cols[k] = Color(float(refill[k]), float(compacted[k]), float(fresh[k]), 1.0)
	var idxs := PackedInt32Array()
	for j in nv - 1:
		for i in nu - 1:
			var a := idx(i, j)
			var b := idx(i + 1, j)
			var c := idx(i + 1, j + 1)
			var d := idx(i, j + 1)
			# winding: Godot front faces are clockwise from the viewer; up-facing
			var pa := verts[a]
			var pb := verts[b]
			var pc := verts[c]
			if (pc - pa).cross(pb - pa).y >= 0.0:
				idxs.append_array([a, b, c, a, c, d])
			else:
				idxs.append_array([a, c, b, a, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idxs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m


func save_state() -> Dictionary:
	return {"h": h, "refill": refill, "compacted": compacted, "fresh": fresh}


func load_state(d: Dictionary) -> void:
	if d.has("h") and (d.h as PackedFloat32Array).size() == h.size():
		h = d.h
		refill = d.refill
		compacted = d.compacted
		fresh = d.fresh
		_dirty = true


# ------------------------------------------------------------------------------------------
# Debug (instant steps, see src/debug/debug_tools.gd)
# ------------------------------------------------------------------------------------------

## Excavates the whole trench at once. Returns the removed bank volume (m³).
func dig_all() -> float:
	var a := cell_area()
	var v := 0.0
	for j in nv:
		for i in nu:
			if inner(i, j):
				var k := idx(i, j)
				v += maxf(0.0, h[k] + depth) * a
				h[k] = minf(h[k], -depth)
				refill[k] = 0
				compacted[k] = 0
				fresh[k] = 0
	_dirty = true
	return v


## Fills every trench cell up to top (relative to the road) and compacts it. Returns the volume.
func fill_all(top: float) -> float:
	var a := cell_area()
	var v := 0.0
	for j in nv:
		for i in nu:
			if inner(i, j):
				var k := idx(i, j)
				if h[k] < top:
					v += (top - h[k]) * a
					h[k] = top
					refill[k] = 1
				compacted[k] = 1
	_dirty = true
	return v
