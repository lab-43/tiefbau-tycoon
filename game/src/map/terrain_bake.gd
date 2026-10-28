class_name TerrainBake
extends RefCounted
## Builds the Terrain of a map in the bake thread (#8): decodes the downloaded Terrarium tiles (TerrainSource),
## resamples them onto a 10 m grid in local metres and makes the surface smooth (the tiles come in 25 cm
## steps). Water areas lie flat at their own level with the bed just below; the ground meets them along the
## shore. The HQ yard is levelled and bridge decks run straight between their ends.
## Also builds the ground mesh (layer "ground" per chunk) that replaces the flat ground plane.

const COARSE := 10.0           # the land is smoothed on this grid (m) ...
const CELL := 5.0              # ... and stored on this one (fine enough for narrow canals and the shore)
const MARGIN := 300.0          # the grid reaches this far beyond the map
const SIGMA := 1.5             # smoothing of the land in coarse cells (Gaussian, ~15 m)
const BED := 1.0               # ground below the water level under water areas
const HQ_BLEND := 30.0         # the levelled yard blends into the ground over this distance
const GROUND_STEP := 4         # ground mesh: one vertex every GROUND_STEP grid nodes (the GPU draws the exact surface)
const SKIRT := 0.3             # ground mesh reaches size * SKIRT beyond the grid (horizon)

var note: Callable


## meta: center_lat, center_lon, size_m and either terrain_dir (downloaded tiles) or terrain = "synthetic".
## Returns null if there are no heights (the map stays flat).
static func build(meta: Dictionary, data: OsmData, hq: Dictionary, note_cb: Callable) -> Terrain:
	var tb := TerrainBake.new()
	tb.note = note_cb
	return tb._build(meta, data, hq)


func _note(s: String) -> void:
	if note.is_valid():
		note.call(s)


func _build(meta: Dictionary, data: OsmData, hq: Dictionary) -> Terrain:
	var t0 := Time.get_ticks_msec()
	var b := data.bounds.grow(MARGIN)
	# coarse grid (smoothing) and fine grid (stored); the fine grid has a node on every coarse node
	var cx := int(ceil(b.size.x / COARSE)) + 1
	var cz := int(ceil(b.size.y / COARSE)) + 1
	var f := int(round(COARSE / CELL))
	var nx := (cx - 1) * f + 1
	var nz := (cz - 1) * f + 1
	var raw := PackedFloat32Array()
	var info := {}
	if String(meta.get("terrain", "")) == "synthetic":
		raw = _synthetic(b.position, cx, cz)
		info = {"source": "synthetic", "name": "Testgelände", "attribution": ""}
	else:
		var dir := String(meta.get("terrain_dir", ""))
		if dir == "":
			return null
		var mf := TerrainSource.read_manifest(dir)
		if mf.is_empty():
			return null
		var mosaic := _decode(dir, mf)
		if mosaic.is_empty():
			_note("Geländehöhen: Kacheln unlesbar – die Karte bleibt flach.")
			return null
		raw = _resample(mosaic, mf, b.position, cx, cz)
		info = {"source": mf.get("source", ""), "name": mf.get("name", ""), "attribution": mf.get("attribution", ""),
			"zoom": mf.get("zoom", 0)}
	# water on the coarse grid: one level per water area (median of the heights inside)
	var cwater := PackedByteArray()
	cwater.resize(cx * cz)
	var levels := {}
	var water_areas: Array = []
	for ai in data.areas.size():
		var a: Dictionary = data.areas[ai]
		if a.kind != "water" or a.outer.size() < 3:
			continue
		water_areas.append(ai)
		var cells := _raster(a.outer, a.holes, b.position, cx, cz, COARSE)
		var vals: Array = []
		for k in cells:
			vals.append(raw[k])
			cwater[k] = 1
		var lv := 0.0
		if vals.is_empty():
			var c := Geo.polygon_centroid(a.outer)
			lv = _bilin(raw, b.position, cx, cz, COARSE, c.x, c.y)
		else:
			vals.sort()
			lv = vals[int(vals.size() * 0.5)]
		levels[ai] = lv
	# land: smoothed without the water (water heights would pull the shore down), then onto the fine grid
	var wl := PackedFloat32Array()
	wl.resize(cx * cz)
	var vm := PackedFloat32Array()
	vm.resize(cx * cz)
	for k in cx * cz:
		var w := 0.0 if cwater[k] else 1.0
		wl[k] = w
		vm[k] = raw[k] * w
	_gauss(vm, cx, cz, SIGMA)
	_gauss(wl, cx, cz, SIGMA)
	var land := PackedFloat32Array()
	land.resize(cx * cz)
	for k in cx * cz:
		land[k] = vm[k] / wl[k] if wl[k] > 0.02 else raw[k]
	var hgt := PackedFloat32Array()
	hgt.resize(nx * nz)
	for j in nz:
		var gz := float(j) / f
		var cj := mini(int(gz), cz - 2)
		var tz := gz - cj
		for i in nx:
			var gx := float(i) / f
			var ci := mini(int(gx), cx - 2)
			var tx := gx - ci
			var k := cj * cx + ci
			hgt[j * nx + i] = lerpf(lerpf(land[k], land[k + 1], tx), lerpf(land[k + cx], land[k + cx + 1], tx), tz)
	# water on the fine grid: the bed lies just below the level. Nodes next to land keep the land height, so the
	# bank lies inside the water area and roads along a quay do not sink.
	var water := PackedByteArray()
	water.resize(nx * nz)
	var level := PackedFloat32Array()
	level.resize(nx * nz)
	for ai in water_areas:
		var a: Dictionary = data.areas[ai]
		for k in _raster(a.outer, a.holes, b.position, nx, nz, CELL):
			water[k] = 1
			level[k] = levels[ai]
	var nwater := 0
	for j in range(1, nz - 1):
		for i in range(1, nx - 1):
			var k := j * nx + i
			if water[k] and water[k - 1] and water[k + 1] and water[k - nx] and water[k + nx]:
				hgt[k] = minf(level[k] - BED, hgt[k])
				nwater += 1
	# levelled yard for the HQ
	if hq.has("lot"):
		_level_hq(hgt, b.position, nx, nz, hq.lot)
	var t := Terrain.new()
	t.setup(b.position, CELL, nx, nz, hgt)
	var lo := INF
	var hi := -INF
	for v in land:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	info["min"] = lo
	info["max"] = hi
	info["water_levels"] = levels
	t.info = info
	_note("Geländehöhen: %d × %d Punkte im %s-m-Raster, Land %.0f bis %.0f m über NHN, %d Wasserflächen (%d ms)" % [
		nx, nz, str(CELL), lo, hi, levels.size(), Time.get_ticks_msec() - t0])
	return t


# ------------------------------------------------------------------------------------------
# Tiles
# ------------------------------------------------------------------------------------------

## All tiles of the manifest as one height mosaic: [heights, width, height, tile size].
func _decode(dir: String, mf: Dictionary) -> Array:
	var x0 := int(mf.x0)
	var x1 := int(mf.x1)
	var y0 := int(mf.y0)
	var y1 := int(mf.y1)
	var tsz := 0
	var mosaic := PackedFloat32Array()
	var mw := 0
	var mh := 0
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var path := dir.path_join(TerrainSource.tile_name(mf, tx, ty))
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.is_empty():
				return []
			var img := Image.new()
			var err := img.load_webp_from_buffer(bytes) if String(mf.get("ext", "webp")) == "webp" else img.load_png_from_buffer(bytes)
			if err != OK or img.get_width() != img.get_height():
				return []
			if tsz == 0:
				tsz = img.get_width()
				mw = (x1 - x0 + 1) * tsz
				mh = (y1 - y0 + 1) * tsz
				mosaic.resize(mw * mh)
			elif img.get_width() != tsz:
				return []
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
			var d := img.get_data()
			var ox := (tx - x0) * tsz
			var oy := (ty - y0) * tsz
			var k := 0
			for py in tsz:
				var row := (oy + py) * mw + ox
				for px in tsz:
					mosaic[row + px] = d[k] * 256.0 + d[k + 1] + d[k + 2] / 256.0 - 32768.0
					k += 3
	return [mosaic, mw, mh, tsz]


## Samples the mosaic (Web Mercator pixels) at the local grid nodes.
func _resample(m: Array, mf: Dictionary, o: Vector2, nx: int, nz: int) -> PackedFloat32Array:
	var mosaic: PackedFloat32Array = m[0]
	var mw: int = m[1]
	var mh: int = m[2]
	var tsz: int = m[3]
	var world := pow(2.0, float(mf.zoom)) * tsz
	var x0 := float(mf.x0) * tsz
	var y0 := float(mf.y0) * tsz
	# lon depends only on x, lat only on z (Geo is an equirectangular tangent plane)
	var col := PackedFloat32Array()
	col.resize(nx)
	for i in nx:
		var ll := Geo.to_latlon(Vector2(o.x + i * COARSE, 0.0))
		col[i] = (ll.y + 180.0) / 360.0 * world - x0 - 0.5
	var row := PackedFloat32Array()
	row.resize(nz)
	for j in nz:
		var ll := Geo.to_latlon(Vector2(0.0, o.y + j * COARSE))
		var s := sin(deg_to_rad(ll.x))
		row[j] = (0.5 - log((1.0 + s) / (1.0 - s)) / (4.0 * PI)) * world - y0 - 0.5
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for j in nz:
		var fy := clampf(row[j], 0.0, mh - 1.001)
		var py := int(fy)
		var ty := fy - py
		for i in nx:
			var fx := clampf(col[i], 0.0, mw - 1.001)
			var px := int(fx)
			var tx := fx - px
			var k := py * mw + px
			out[j * nx + i] = lerpf(lerpf(mosaic[k], mosaic[k + 1], tx), lerpf(mosaic[k + mw], mosaic[k + mw + 1], tx), ty)
	return out


## Gentle hills for tests (--terrain=synthetic): up to ±8 m, a slope across the map, no steps.
func _synthetic(o: Vector2, nx: int, nz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := o.x + i * COARSE
			var z := o.y + j * COARSE
			out[j * nx + i] = 6.0 + 5.0 * sin(x / 190.0) * cos(z / 260.0) + 3.0 * sin((x + z) / 420.0) + x * 0.004
	return out


# ------------------------------------------------------------------------------------------
# Grid helpers
# ------------------------------------------------------------------------------------------

static func _bilin(a: PackedFloat32Array, o: Vector2, nx: int, nz: int, cell: float, x: float, z: float) -> float:
	var gx := clampf((x - o.x) / cell, 0.0, nx - 1.001)
	var gz := clampf((z - o.y) / cell, 0.0, nz - 1.001)
	var i := int(gx)
	var j := int(gz)
	var k := j * nx + i
	return lerpf(lerpf(a[k], a[k + 1], gx - i), lerpf(a[k + nx], a[k + nx + 1], gx - i), gz - j)


## Node indices inside a polygon with holes (even-odd scanline per node row).
static func _raster(outer: PackedVector2Array, holes: Array, o: Vector2, nx: int, nz: int, cell: float) -> PackedInt32Array:
	var rings: Array = [outer]
	rings.append_array(holes)
	var r := Rect2(outer[0], Vector2.ZERO)
	for p in outer:
		r = r.expand(p)
	var j0 := clampi(int(ceil((r.position.y - o.y) / cell)), 0, nz - 1)
	var j1 := clampi(int(floor((r.end.y - o.y) / cell)), 0, nz - 1)
	var out := PackedInt32Array()
	if j1 < j0:
		return out
	# crossings per row
	var xs: Array = []
	xs.resize(j1 - j0 + 1)
	for jj in xs.size():
		xs[jj] = PackedFloat32Array()
	for ring in rings:
		var pts: PackedVector2Array = ring
		var n := pts.size()
		for e in n:
			var a := pts[e]
			var c := pts[(e + 1) % n]
			if a.y == c.y:
				continue
			var lo := minf(a.y, c.y)
			var hi := maxf(a.y, c.y)
			var ja := maxi(j0, int(ceil((lo - o.y) / cell)))
			var jb := mini(j1, int(ceil((hi - o.y) / cell)) - 1)
			for j in range(ja, jb + 1):
				var z := o.y + j * cell
				if z < lo or z >= hi:
					continue
				var t := (z - a.y) / (c.y - a.y)
				var arr: PackedFloat32Array = xs[j - j0]
				arr.append(a.x + (c.x - a.x) * t)
				xs[j - j0] = arr
	for jj in xs.size():
		var arr: PackedFloat32Array = xs[jj]
		if arr.size() < 2:
			continue
		arr.sort()
		var j := j0 + jj
		var q := 0
		while q + 1 < arr.size():
			var i0 := maxi(0, int(ceil((arr[q] - o.x) / cell)))
			var i1 := mini(nx - 1, int(floor((arr[q + 1] - o.x) / cell)))
			for i in range(i0, i1 + 1):
				out.append(j * nx + i)
			q += 2
	return out


## Separable Gaussian blur in place (sigma in cells), clamped at the border.
static func _gauss(a: PackedFloat32Array, nx: int, nz: int, sigma: float) -> void:
	var r := int(ceil(sigma * 2.5))
	var w := PackedFloat32Array()
	var sum := 0.0
	for q in range(-r, r + 1):
		var v := exp(-0.5 * q * q / (sigma * sigma))
		w.append(v)
		sum += v
	for q in w.size():
		w[q] /= sum
	var tmp := PackedFloat32Array()
	tmp.resize(a.size())
	for j in nz:
		var row := j * nx
		for i in nx:
			var s := 0.0
			for q in range(-r, r + 1):
				s += a[row + clampi(i + q, 0, nx - 1)] * w[q + r]
			tmp[row + i] = s
	for j in nz:
		for i in nx:
			var s := 0.0
			for q in range(-r, r + 1):
				s += tmp[clampi(j + q, 0, nz - 1) * nx + i] * w[q + r]
			a[j * nx + i] = s


## The HQ lot becomes level at its mean height and blends into the ground around it.
static func _level_hq(hgt: PackedFloat32Array, o: Vector2, nx: int, nz: int, lot: PackedVector2Array) -> void:
	var r := Rect2(lot[0], Vector2.ZERO)
	for p in lot:
		r = r.expand(p)
	var rr := r.grow(HQ_BLEND + CELL)
	var i0 := clampi(int(floor((rr.position.x - o.x) / CELL)), 0, nx - 1)
	var i1 := clampi(int(ceil((rr.end.x - o.x) / CELL)), 0, nx - 1)
	var j0 := clampi(int(floor((rr.position.y - o.y) / CELL)), 0, nz - 1)
	var j1 := clampi(int(ceil((rr.end.y - o.y) / CELL)), 0, nz - 1)
	var sum := 0.0
	var n := 0
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if Geometry2D.is_point_in_polygon(o + Vector2(i, j) * CELL, lot):
				sum += hgt[j * nx + i]
				n += 1
	if n == 0:
		var c := (lot[0] + lot[2]) * 0.5
		sum = _bilin(hgt, o, nx, nz, CELL, c.x, c.y)
		n = 1
	var lv := sum / n
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := o + Vector2(i, j) * CELL
			var d := 0.0
			if not Geometry2D.is_point_in_polygon(p, lot):
				d = INF
				for e in lot.size():
					var q := Geometry2D.get_closest_point_to_segment(p, lot[e], lot[(e + 1) % lot.size()])
					d = minf(d, q.distance_to(p))
			var k := j * nx + i
			hgt[k] = lerpf(lv, hgt[k], smoothstep(CELL * 0.5, HQ_BLEND, d))


# ------------------------------------------------------------------------------------------
# Bridges
# ------------------------------------------------------------------------------------------

## Deck heights: nodes touching a normal road sit on the ground, nodes inside a bridge (junctions on a viaduct)
## get the length-weighted mean of their neighbours (a straight deck for a simple bridge).
static func add_decks(t: Terrain, net: RoadNet) -> void:
	var on_bridge := {}     # node -> true if every edge of the node is a bridge
	var deg := {}
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		for ni in [e.a, e.b]:
			deg[ni] = int(deg.get(ni, 0)) + 1
			if not on_bridge.has(ni):
				on_bridge[ni] = true
			if not e.bridge:
				on_bridge[ni] = false
	var hn := {}
	var inner: Array = []
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if not e.bridge:
			continue
		for ni in [e.a, e.b]:
			if hn.has(ni) or inner.has(ni):
				continue
			var p: Vector2 = net.nodes[ni].pos
			if on_bridge[ni] and int(deg[ni]) > 1:
				inner.append(ni)
				hn[ni] = t.sample(p.x, p.y)
			else:
				hn[ni] = t.sample(p.x, p.y)
	# Gauss-Seidel on the bridge graph (only inner nodes move)
	var nb := {}
	for ni in inner:
		nb[ni] = []
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if not e.bridge:
			continue
		var w := 1.0 / maxf(1.0, float(e.len))
		if nb.has(e.a):
			nb[e.a].append([e.b, w])
		if nb.has(e.b):
			nb[e.b].append([e.a, w])
	# long chains converge slowly (about n² sweeps): sweep until nothing moves by more than 0.1 mm
	for it in 20000:
		var moved := 0.0
		for ni in inner:
			var s := 0.0
			var ws := 0.0
			for pair in nb[ni]:
				s += float(hn[pair[0]]) * float(pair[1])
				ws += float(pair[1])
			if ws > 0.0:
				moved = maxf(moved, absf(s / ws - float(hn[ni])))
				hn[ni] = s / ws
		if moved < 0.0001:
			break
	for ni in inner:
		t.node_decks[ni] = hn[ni]
		t.node_pos[ni] = net.nodes[ni].pos
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if not e.bridge:
			continue
		var pts: PackedVector2Array = e.pts
		var a := pts[0]
		var bb := pts[pts.size() - 1]
		var land_a: bool = not inner.has(e.a)
		var land_b: bool = not inner.has(e.b)
		var free_len: float = maxf(0.0, float(e.len) - float(e.trim_a) - float(e.trim_b))
		var blend := clampf(free_len / 3.0, 1.0, 12.0)
		var hw := float(e.width) * 0.5 + maxf(float(e.sw_r), float(e.sw_l)) + 0.5
		t.decks[ei] = [float(hn[e.a]), float(hn[e.b]), a, bb, land_a, land_b, float(e.trim_a), float(e.trim_b), blend, hw, pts]


## Decks for bridge ways of paths or rails ({pts, tags}): ways are joined at shared end points, ends that meet
## a normal way (or nothing) sit on the ground, the others are interpolated along the chain.
## Returns {way index: deck array (see Terrain.deck_at)}.
static func line_decks(t: Terrain, lines: Array) -> Dictionary:
	var ends := {}       # rounded end point -> [bridge ways, other ways]
	var bridges: Array = []
	for li in lines.size():
		var w: Dictionary = lines[li]
		var pts: PackedVector2Array = w.pts
		if pts.size() < 2:
			continue
		var br: bool = String(w.tags.get("bridge", "")) in ["yes", "viaduct", "boardwalk", "cantilever"]
		if br:
			bridges.append(li)
		for p in [pts[0], pts[pts.size() - 1]]:
			var key := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
			var c: Array = ends.get(key, [0, 0])
			c[0 if br else 1] += 1
			ends[key] = c
	var hk := {}
	var inner := {}
	var nb := {}
	for li in bridges:
		var pts: PackedVector2Array = lines[li].pts
		var ka := Vector2i(roundi(pts[0].x * 2.0), roundi(pts[0].y * 2.0))
		var kb := Vector2i(roundi(pts[pts.size() - 1].x * 2.0), roundi(pts[pts.size() - 1].y * 2.0))
		var w := 1.0 / maxf(1.0, pts[0].distance_to(pts[pts.size() - 1]))
		for pair in [[ka, kb, pts[0]], [kb, ka, pts[pts.size() - 1]]]:
			var k: Vector2i = pair[0]
			var p: Vector2 = pair[2]
			if not hk.has(k):
				hk[k] = t.sample(p.x, p.y)
			var c: Array = ends[k]
			if c[1] == 0 and c[0] >= 2:
				inner[k] = true
				if not nb.has(k):
					nb[k] = []
				nb[k].append([pair[1], w])
	for it in 20000:
		var moved := 0.0
		for k in inner:
			var s := 0.0
			var ws := 0.0
			for q in nb[k]:
				s += float(hk[q[0]]) * float(q[1])
				ws += float(q[1])
			moved = maxf(moved, absf(s / ws - float(hk[k])))
			hk[k] = s / ws
		if moved < 0.0001:
			break
	var out := {}
	for li in bridges:
		var pts: PackedVector2Array = lines[li].pts
		var ka := Vector2i(roundi(pts[0].x * 2.0), roundi(pts[0].y * 2.0))
		var kb := Vector2i(roundi(pts[pts.size() - 1].x * 2.0), roundi(pts[pts.size() - 1].y * 2.0))
		var a := pts[0]
		var b := pts[pts.size() - 1]
		out[li] = [float(hk[ka]), float(hk[kb]), a, b, not inner.has(ka), not inner.has(kb), 0.0, 0.0,
			clampf(a.distance_to(b) / 3.0, 1.0, 12.0)]
	return out


# ------------------------------------------------------------------------------------------
# Ground mesh
# ------------------------------------------------------------------------------------------

## Ground surface as chunked grid meshes (layer "ground"), plus a coarse skirt beyond the grid up to the horizon.
static func ground_layers(t: Terrain, chunks: Dictionary, chunk: float, chunk_origin: Vector2, map_size: float) -> void:
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var skirt := map_size * SKIRT
	var gx1 := t.origin.x + (t.nx - 1) * t.cell
	var gz1 := t.origin.y + (t.nz - 1) * t.cell
	for q in [4, 3, 2, 1]:
		xs.append(t.origin.x - skirt * q / 4.0)
		zs.append(t.origin.y - skirt * q / 4.0)
	for i in range(0, t.nx, GROUND_STEP):
		xs.append(t.origin.x + i * t.cell)
	if xs[xs.size() - 1] < gx1 - 0.01:
		xs.append(gx1)
	for j in range(0, t.nz, GROUND_STEP):
		zs.append(t.origin.y + j * t.cell)
	if zs[zs.size() - 1] < gz1 - 0.01:
		zs.append(gz1)
	for q in [1, 2, 3, 4]:
		xs.append(gx1 + skirt * q / 4.0)
		zs.append(gz1 + skirt * q / 4.0)
	# heights + normals once per vertex
	var nxv := xs.size()
	var nzv := zs.size()
	var pos := PackedVector3Array()
	pos.resize(nxv * nzv)
	var nrm := PackedVector3Array()
	nrm.resize(nxv * nzv)
	for j in nzv:
		for i in nxv:
			var x := xs[i]
			var z := zs[j]
			pos[j * nxv + i] = Vector3(x, t.sample(x, z), z)
			nrm[j * nxv + i] = t.normal(x, z)
	var local := {}   # chunk -> {grid vertex -> index in the chunk's layer} (shared vertices, 4x smaller)
	for j in nzv - 1:
		for i in nxv - 1:
			var c := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
			var ck := Vector2i(int(floor((c.x - chunk_origin.x) / chunk)), int(floor((c.y - chunk_origin.y) / chunk)))
			if not chunks.has(ck):
				chunks[ck] = {}
			var lay: Dictionary = chunks[ck]
			if not lay.has("ground"):
				var nl := MeshLayer.new()
				nl.use_uvs = false
				lay["ground"] = nl
				local[ck] = {}
			var l: MeshLayer = lay["ground"]
			var lm: Dictionary = local[ck]
			var k0 := j * nxv + i
			var q := PackedInt32Array()
			for k in [k0, k0 + 1, k0 + nxv + 1, k0 + nxv]:
				if not lm.has(k):
					lm[k] = l.verts.size()
					l.verts.append(pos[k])
					l.normals.append(nrm[k])
				q.append(lm[k])
			# up-facing: (x,z) counter-clockwise as seen from above = clockwise in Godot's front-face rule
			l.indices.append_array(PackedInt32Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
