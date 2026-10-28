class_name Terrain
extends RefCounted
## Ground heights of the map (#8): a smoothed height grid in local metres, sampled bilinearly. The same grid
## is a global shader texture, so the GPU computes the exact same surface per pixel (common.gdshaderinc).
## Also holds the bridge decks: a bridge does not follow the ground but runs straight between its ends.
## Terrain.cur is the terrain of the loaded map (null = flat map, height 0 everywhere).
## Built by TerrainBake in the bake thread, saved with the baked map.

static var cur: Terrain = null

var origin := Vector2.ZERO        # local x/z of grid node (0, 0)
var cell := 10.0
var nx := 0
var nz := 0
var h := PackedFloat32Array()     # row-major, index = j * nx + i
var info := {}                    # source, attribution, statistics (shown in the log)
# bridges: edge index -> [h_a, h_b, a(Vector2), b(Vector2), land_a, land_b, trim_a, trim_b, blend, half width, pts]
var decks := {}
var node_decks := {}              # node index on a bridge (not touching land) -> deck height
var node_pos := {}                # same nodes -> position (for surface_near)
# set by the meshers while they build a bridge (deck array as in decks) or a junction on a bridge (bake thread)
var mode_deck: Array = []
var mode_node := -1

var _inv := 0.1


func setup(o: Vector2, c: float, w: int, d: int, heights: PackedFloat32Array) -> void:
	origin = o
	cell = c
	_inv = 1.0 / c
	nx = w
	nz = d
	h = heights


func is_empty() -> bool:
	return nx < 2 or nz < 2


## Height of the ground at local (x, z), bilinear between the grid nodes, clamped at the border.
func sample(x: float, z: float) -> float:
	var gx := clampf((x - origin.x) * _inv, 0.0, nx - 1.0)
	var gz := clampf((z - origin.y) * _inv, 0.0, nz - 1.0)
	var i := mini(int(gx), nx - 2)
	var j := mini(int(gz), nz - 2)
	var fx := gx - i
	var fz := gz - j
	var k := j * nx + i
	var a := h[k]
	var b := h[k + 1]
	var c := h[k + nx]
	var d := h[k + nx + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## Height gradient (dh/dx, dh/dz) of the bilinear surface.
func gradient(x: float, z: float) -> Vector2:
	var gx := clampf((x - origin.x) * _inv, 0.0, nx - 1.0)
	var gz := clampf((z - origin.y) * _inv, 0.0, nz - 1.0)
	var i := mini(int(gx), nx - 2)
	var j := mini(int(gz), nz - 2)
	var fx := gx - i
	var fz := gz - j
	var k := j * nx + i
	var a := h[k]
	var b := h[k + 1]
	var c := h[k + nx]
	var d := h[k + nx + 1]
	return Vector2(lerpf(b - a, d - c, fz), lerpf(c - a, d - b, fx)) * _inv


var _ng := PackedVector2Array()   # gradient per node (central differences), built on first use


## Smooth surface normal: node gradients (central differences) interpolated bilinearly, so the light has no
## facets at the grid lines.
func normal(x: float, z: float) -> Vector3:
	if _ng.is_empty():
		_build_gradients()
	var gx := clampf((x - origin.x) * _inv, 0.0, nx - 1.0)
	var gz := clampf((z - origin.y) * _inv, 0.0, nz - 1.0)
	var i := mini(int(gx), nx - 2)
	var j := mini(int(gz), nz - 2)
	var fx := gx - i
	var fz := gz - j
	var k := j * nx + i
	var g := _ng[k].lerp(_ng[k + 1], fx).lerp(_ng[k + nx].lerp(_ng[k + nx + 1], fx), fz)
	return Vector3(-g.x, 1.0, -g.y).normalized()


func _build_gradients() -> void:
	_ng.resize(nx * nz)
	var inv2 := _inv * 0.5
	for j in nz:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, nz - 1)
		var sz := inv2 * 2.0 / (j1 - j0)
		for i in nx:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, nx - 1)
			_ng[j * nx + i] = Vector2((h[j * nx + i1] - h[j * nx + i0]) * inv2 * 2.0 / (i1 - i0),
				(h[j1 * nx + i] - h[j0 * nx + i]) * sz)


## Height of whatever the mesher is building right now: a bridge deck or the ground.
func surface(x: float, z: float) -> float:
	if not mode_deck.is_empty():
		return deck_at(mode_deck, Vector2(x, z))
	if mode_node >= 0:
		return float(node_decks.get(mode_node, sample(x, z)))
	return sample(x, z)


func surface_normal(x: float, z: float) -> Vector3:
	if not mode_deck.is_empty() or (mode_node >= 0 and node_decks.has(mode_node)):
		return Vector3.UP
	return normal(x, z)


## Deck height of bridge edge ei at p. Not a bridge: the ground.
func deck_height(ei: int, p: Vector2) -> float:
	var dk: Array = decks.get(ei, [])
	if dk.is_empty():
		return sample(p.x, p.y)
	return deck_at(dk, p)


## A deck [h_a, h_b, a, b, land_a, land_b, trim_a, trim_b, blend]: straight between a and b, blended into
## the ground near land ends (so the bridge meets the junction or the path exactly).
func deck_at(dk: Array, p: Vector2) -> float:
	var a: Vector2 = dk[2]
	var b: Vector2 = dk[3]
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.01)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	var deck := lerpf(float(dk[0]), float(dk[1]), t)
	var w := 1.0
	var s := t * sqrt(len2)
	var total := sqrt(len2)
	var bl: float = dk[8]
	var ta: float = dk[6]
	var tb: float = dk[7]
	if dk[4]:
		w = minf(w, smoothstep(ta, ta + bl, s))
	if dk[5]:
		w = minf(w, smoothstep(tb, tb + bl, total - s))
	if w >= 1.0:
		return deck
	return lerpf(sample(p.x, p.y), deck, w)


func is_bridge(ei: int) -> bool:
	return decks.has(ei)


var _bgrid := {}
var _bgrid_ready := false
const BGRID := 50.0


func _index_bridges() -> void:
	_bgrid_ready = true
	for ei in decks:
		var dk: Array = decks[ei]
		var hw: float = dk[9] if dk.size() > 9 else 8.0
		var pts: PackedVector2Array = dk[10] if dk.size() > 10 else PackedVector2Array([dk[2], dk[3]])
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		r = r.grow(hw + 2.0)
		_grid_add(r, ei)
	# junctions on a bridge: id -1 - node
	for ni in node_pos:
		var np: Vector2 = node_pos[ni]
		_grid_add(Rect2(np, Vector2.ZERO).grow(NODE_R + 2.0), -1 - int(ni))


const NODE_R := 18.0


func _grid_add(r: Rect2, id: int) -> void:
	for gx in range(floori(r.position.x / BGRID), floori(r.end.x / BGRID) + 1):
		for gz in range(floori(r.position.y / BGRID), floori(r.end.y / BGRID) + 1):
			var k := Vector2i(gx, gz)
			if not _bgrid.has(k):
				_bgrid[k] = []
			_bgrid[k].append(id)


## Surface at p for something that is now at height `hint`: the ground, or a bridge deck at p if that is
## closer to hint (a car on a bridge stays on it, a car under the bridge stays on the ground).
func surface_near(p: Vector2, hint: float) -> float:
	var best := sample(p.x, p.y)
	if decks.is_empty():
		return best
	if not _bgrid_ready:
		_index_bridges()
	var bd := absf(best - hint)
	for ei in _bgrid.get(Vector2i(floori(p.x / BGRID), floori(p.y / BGRID)), []):
		if ei < 0:
			var ni := -1 - int(ei)
			if (node_pos[ni] as Vector2).distance_to(p) <= NODE_R:
				var hn: float = node_decks[ni]
				if absf(hn - hint) < bd:
					bd = absf(hn - hint)
					best = hn
			continue
		var dk: Array = decks[ei]
		var hw: float = dk[9] if dk.size() > 9 else 8.0
		var pts: PackedVector2Array = dk[10] if dk.size() > 10 else PackedVector2Array([dk[2], dk[3]])
		var near := false
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) <= hw + 1.0:
				near = true
				break
		if not near:
			continue
		var hd := deck_at(dk, p)
		if absf(hd - hint) < bd:
			bd = absf(hd - hint)
			best = hd
	return best


## Height of the road surface at p for a vehicle on lane key `key` (edge = key >> 4) or at junction `node`.
func road_height(p: Vector2, key: int = -1, node: int = -1) -> float:
	if key >= 0 and decks.has(key >> 4):
		return deck_height(key >> 4, p)
	if node >= 0 and node_decks.has(node):
		return node_decks[node]
	return sample(p.x, p.y)


# ------------------------------------------------------------------------------------------
# Static access for the running game
# ------------------------------------------------------------------------------------------

## Height of the road under a vehicle on route piece pc (Router/Agent piece) at p: bridge decks for lanes of a
## bridge and junctions on a bridge, otherwise the ground. 0 on flat maps.
static func piece_y(pc: Dictionary, p: Vector2) -> float:
	if cur == null:
		return 0.0
	var t: int = pc.t
	if t == Agent.LANE or t == Router.BLEND:
		return cur.road_height(p, int(pc.key))
	if t == Agent.CONN:
		return cur.road_height(p, -1, int(pc.node))
	return cur.sample(p.x, p.y)


## Ground or bridge deck at p, whichever is closer to hint (see surface_near). 0 on flat maps.
static func near(p: Vector2, hint: float) -> float:
	if cur == null:
		return 0.0
	return cur.surface_near(p, hint)


## Ground height at p (0 on flat maps).
static func at(p: Vector2) -> float:
	if cur == null:
		return 0.0
	return cur.sample(p.x, p.y)


static func at3(x: float, z: float) -> float:
	if cur == null:
		return 0.0
	return cur.sample(x, z)


static func normal_at(p: Vector2) -> Vector3:
	if cur == null:
		return Vector3.UP
	return cur.normal(p.x, p.y)


## Makes t the terrain of the running game and hands the grid to the shaders (null = flat).
static func activate(t: Terrain) -> void:
	if t != null and t == cur:
		return
	cur = t if t != null and not t.is_empty() else null
	if cur == null:
		RenderingServer.global_shader_parameter_set("terrain_rect", Vector4(0, 0, 0.1, 0))
		return
	var img := Image.create_from_data(cur.nx, cur.nz, false, Image.FORMAT_RF, cur.h.to_byte_array())
	var tex := ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("terrain_tex", tex)
	RenderingServer.global_shader_parameter_set("terrain_rect", Vector4(cur.origin.x, cur.origin.y, 1.0 / cur.cell, 1.0))
	RenderingServer.global_shader_parameter_set("terrain_size", Vector4(cur.nx, cur.nz, cur.cell, 0.0))


# ------------------------------------------------------------------------------------------
# Save (inside the baked map)
# ------------------------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"origin": origin, "cell": cell, "nx": nx, "nz": nz, "h": h, "info": info, "decks": decks,
		"node_decks": node_decks, "node_pos": node_pos}


static func deserialize(d: Dictionary) -> Terrain:
	if d.is_empty():
		return null
	var t := Terrain.new()
	t.setup(d.get("origin", Vector2.ZERO), float(d.get("cell", 10.0)), int(d.get("nx", 0)), int(d.get("nz", 0)),
		d.get("h", PackedFloat32Array()))
	t.info = d.get("info", {})
	t.decks = d.get("decks", {})
	t.node_decks = d.get("node_decks", {})
	t.node_pos = d.get("node_pos", {})
	return null if t.is_empty() else t

