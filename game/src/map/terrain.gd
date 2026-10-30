class_name Terrain
extends RefCounted
## Ground heights of the map (#8): a smoothed height grid in local metres, sampled bilinearly. The same grid
## is a global shader texture, so the GPU computes the exact same surface per pixel (common.gdshaderinc).
## Also holds the decks (#32): bridges and their approach ramps do not follow the ground; their height is a profile
## along the centre line, computed by BridgeHeights. Maps without heights get a flat terrain (flat = true, height 0
## everywhere) so their bridges can rise as well. Terrain.cur is the terrain of the loaded map (null before one is
## loaded). Built by TerrainBake (or flat_for) in the bake thread, saved with the baked map.

static var cur: Terrain = null

var origin := Vector2.ZERO        # local x/z of grid node (0, 0)
var cell := 10.0
var nx := 0
var nz := 0
var h := PackedFloat32Array()     # row-major, index = j * nx + i
var info := {}                    # source, attribution, statistics (shown in the log)
var flat := false                 # no height data: everything at 0, only the decks rise (#32)
# raised road edges (bridges, approach ramps): edge index -> deck (make_deck)
var decks := {}
var node_decks := {}              # raised junction (on a bridge or a ramp) -> height of its flat area
var node_pos := {}                # same nodes -> position (for surface_near)
var node_r := {}                  # same nodes -> radius of their flat area (NODE_R if missing)
var node_poly := {}               # same nodes -> outline of their flat area (convex hull; circle if missing)
# set by the meshers while they build a deck (a deck dictionary) or a raised junction (bake thread)
var mode_deck := {}
var mode_node := -1

const DECK_STEP := 2.0            # profile stations at most this far apart (m)
const DECK_CELL := 12.0           # cells of the per-deck segment index

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


## A terrain without heights for maps whose height tiles could not be loaded (and offline test maps): sample()
## is 0 everywhere, but it carries the decks so bridges still rise (#32). The shaders treat it as flat.
static func flat_for(bounds: Rect2) -> Terrain:
	var t := Terrain.new()
	var b := bounds.grow(2000.0)
	var c := maxf(b.size.x, b.size.y)
	t.setup(b.position, c, 2, 2, PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	t.flat = true
	t.info = {"source": "flach", "name": "flach", "attribution": "", "min": 0.0, "max": 0.0}
	return t


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


## Height of whatever the mesher is building right now: a deck or the ground.
func surface(x: float, z: float) -> float:
	if not mode_deck.is_empty():
		return deck_at(mode_deck, Vector2(x, z))
	if mode_node >= 0:
		return node_height(mode_node, Vector2(x, z))
	return sample(x, z)


## Height of a raised junction at p (never below the ground). Not raised: the ground.
func node_height(ni: int, p: Vector2) -> float:
	var g := sample(p.x, p.y)
	if not node_decks.has(ni):
		return g
	return maxf(float(node_decks[ni]), g)


func surface_normal(x: float, z: float) -> Vector3:
	if not mode_deck.is_empty() or (mode_node >= 0 and node_decks.has(mode_node)):
		return Vector3.UP
	return normal(x, z)


## Deck height of road edge ei at p. Not raised: the ground.
func deck_height(ei: int, p: Vector2) -> float:
	var dk: Dictionary = decks.get(ei, {})
	if dk.is_empty():
		return sample(p.x, p.y)
	return deck_at(dk, p)


## A deck: the height profile h along a centre line (pts, cum), stations evenly spaced from s = 0 to the end, and
## the ground under the centre line at the same stations (g). hw: half width (sidewalks included).
## lv: the required height at the same stations (may lie below the ground; h = max(lv, ground)), empty = h.
static func make_deck(pts: PackedVector2Array, cum: PackedFloat32Array, h: PackedFloat32Array, g: PackedFloat32Array,
		hw: float, lv := PackedFloat32Array()) -> Dictionary:
	var total: float = cum[cum.size() - 1]
	return {"pts": pts, "cum": cum, "h": h, "g": g, "lv": lv if lv.size() == h.size() else h, "hw": hw,
		"step": total / maxf(1.0, h.size() - 1.0)}


## Height of deck dk at p: flat across the road at the required height where p lies across the centre line, but
## never below the ground. Where a ramp comes down to the ground it follows the ground across the road (as roads
## do), and its edges meet a junction area (flat at its height, never below the ground) without a step.
func deck_at(dk: Dictionary, p: Vector2) -> float:
	var s := deck_s(dk, p)
	return maxf(_deck_lerp(dk.get("lv", dk.h), float(dk.step), s), sample(p.x, p.y))   # (no lv: map baked before)


## Profile height at arc length s.
static func deck_h(dk: Dictionary, s: float) -> float:
	return _deck_lerp(dk.h, float(dk.step), s)


## Ground under the centre line at arc length s.
static func deck_g(dk: Dictionary, s: float) -> float:
	return _deck_lerp(dk.g, float(dk.step), s)


static func _deck_lerp(a: PackedFloat32Array, step: float, s: float) -> float:
	if a.size() < 2:
		return a[0] if a.size() == 1 else 0.0
	var f := clampf(s / maxf(step, 0.001), 0.0, a.size() - 1.0)
	var i := mini(int(f), a.size() - 2)
	return lerpf(a[i], a[i + 1], f - i)


## Arc length of the point of the centre line of dk nearest to p.
func deck_s(dk: Dictionary, p: Vector2) -> float:
	return deck_ds(dk, p).y


## [distance, arc length] of the nearest point of the centre line of dk to p (segment index per DECK_CELL cell).
func deck_ds(dk: Dictionary, p: Vector2) -> Vector2:
	var pts: PackedVector2Array = dk.pts
	var cum: PackedFloat32Array = dk.cum
	if not dk.has("_g"):
		_index_deck(dk)
	var cands = (dk._g as Dictionary).get(Vector2i(floori(p.x / DECK_CELL), floori(p.y / DECK_CELL)))
	var best := INF
	var bs := 0.0
	if cands == null:
		cands = range(pts.size() - 1)   # far from the deck (should not happen while meshing it)
	for i in cands:
		var a := pts[i]
		var b := pts[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			bs = cum[i] + a.distance_to(q)
	return Vector2(sqrt(best), bs)


## Segment index of a deck: every segment in the cells its box (grown by the half width) touches.
func _index_deck(dk: Dictionary) -> void:
	var pts: PackedVector2Array = dk.pts
	var grow: float = float(dk.get("hw", 6.0)) + 4.0
	var g := {}
	for i in pts.size() - 1:
		var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(grow)
		for gx in range(floori(r.position.x / DECK_CELL), floori(r.end.x / DECK_CELL) + 1):
			for gz in range(floori(r.position.y / DECK_CELL), floori(r.end.y / DECK_CELL) + 1):
				var k := Vector2i(gx, gz)
				if not g.has(k):
					g[k] = PackedInt32Array()
				var arr: PackedInt32Array = g[k]
				arr.append(i)
				g[k] = arr
	dk["_g"] = g


func is_bridge(ei: int) -> bool:
	return decks.has(ei)


var _bgrid := {}
var _bgrid_ready := false
const BGRID := 50.0


func _index_bridges() -> void:
	_bgrid_ready = true
	for ei in decks:
		var dk: Dictionary = decks[ei]
		var hw: float = dk.hw
		var pts: PackedVector2Array = dk.pts
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		r = r.grow(hw + 2.0)
		_grid_add(r, ei)
	# junctions on a bridge: id -1 - node
	for ni in node_pos:
		var np: Vector2 = node_pos[ni]
		_grid_add(Rect2(np, Vector2.ZERO).grow(float(node_r.get(ni, NODE_R)) + 2.0), -1 - int(ni))


const NODE_R := 18.0


func _grid_add(r: Rect2, id: int) -> void:
	for gx in range(floori(r.position.x / BGRID), floori(r.end.x / BGRID) + 1):
		for gz in range(floori(r.position.y / BGRID), floori(r.end.y / BGRID) + 1):
			var k := Vector2i(gx, gz)
			if not _bgrid.has(k):
				_bgrid[k] = []
			_bgrid[k].append(id)


## p lies on the flat area of raised junction ni.
func _on_node(ni: int, p: Vector2) -> bool:
	if (node_pos[ni] as Vector2).distance_to(p) > float(node_r.get(ni, NODE_R)):
		return false
	var poly = node_poly.get(ni)
	return poly == null or Geometry2D.is_point_in_polygon(p, poly)


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
			if _on_node(ni, p):
				var hn: float = node_height(ni, p)
				if absf(hn - hint) < bd:
					bd = absf(hn - hint)
					best = hn
			continue
		var dk: Dictionary = decks[ei]
		var ds := deck_ds(dk, p)
		if ds.x > float(dk.hw):   # (hw: road, sidewalks and half a metre)
			continue
		var hd := deck_at(dk, p)
		if absf(hd - hint) < bd:
			bd = absf(hd - hint)
			best = hd
	return best


## Heights of all raised road surfaces at p (bridge decks, ramps, raised junction areas), without the ground.
func raised_at(p: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if decks.is_empty():
		return out
	if not _bgrid_ready:
		_index_bridges()
	for ei in _bgrid.get(Vector2i(floori(p.x / BGRID), floori(p.y / BGRID)), []):
		if ei < 0:
			if _on_node(-1 - int(ei), p):
				out.append(node_height(-1 - int(ei), p))
			continue
		var dk: Dictionary = decks[ei]
		if deck_ds(dk, p).x <= float(dk.hw):
			out.append(deck_at(dk, p))
	return out


## Height of the road surface at p for a vehicle on lane key `key` (edge = key >> 4) or at junction `node`.
func road_height(p: Vector2, key: int = -1, node: int = -1) -> float:
	if key >= 0 and decks.has(key >> 4):
		return deck_height(key >> 4, p)
	if node >= 0 and node_decks.has(node):
		return node_height(node, p)
	return sample(p.x, p.y)


# ------------------------------------------------------------------------------------------
# Static access for the running game
# ------------------------------------------------------------------------------------------

## Height of the road under a vehicle on route piece pc (Router/Agent piece) at p: decks for lanes of a raised
## road and raised junctions, otherwise the ground.
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


## Highest surface at p: a bridge deck above the ground, otherwise the ground (mouse picking). 0 on flat maps.
static func top(p: Vector2) -> float:
	if cur == null:
		return 0.0
	return cur.surface_near(p, 1.0e6)


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
	if cur.flat:
		RenderingServer.global_shader_parameter_set("terrain_rect", Vector4(0, 0, 0.1, 0))   # shaders: flat map
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
	var dks := {}
	for ei in decks:
		var dk: Dictionary = (decks[ei] as Dictionary).duplicate()
		dk.erase("_g")   # segment index, rebuilt on first use
		dks[ei] = dk
	return {"origin": origin, "cell": cell, "nx": nx, "nz": nz, "h": h, "info": info, "decks": dks,
		"node_decks": node_decks, "node_pos": node_pos, "node_r": node_r, "node_poly": node_poly, "flat": flat}


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
	t.node_r = d.get("node_r", {})
	t.node_poly = d.get("node_poly", {})
	t.flat = bool(d.get("flat", false))
	return null if t.is_empty() else t

