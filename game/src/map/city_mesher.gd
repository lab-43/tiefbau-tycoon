class_name CityMesher
extends RefCounted
## Buildings (white massing), landuse areas, water, footpaths, railways, trees, lamps.

const Y := {"farmland": 0.010, "residential": 0.012, "industrial": 0.014, "commercial": 0.014, "grass": 0.018,
	"park": 0.020, "cemetery": 0.020, "forest": 0.022, "pitch": 0.026, "sand": 0.024, "paved": 0.030}
# Water lies on top of all landuse areas (harbour landuse often overlaps the basins) and below ballast,
# paths and roads. It must stay above the opaque base ground plane at y = 0, which hides anything below it.
const WATER_Y := 0.031
const BALLAST_Y := 0.032
const PATH_Y := 0.04

var data: OsmData
var net: RoadNet
var chunk_size := 500.0
var origin := Vector2.ZERO
var chunks := {}         # Vector2i -> {layer_name: MeshLayer}
var trees := {}          # Vector2i -> Array[Transform3D]
var lamps := {}          # Vector2i -> Array[Transform3D]
var hq_rect := PackedVector2Array()
var rng := RandomNumberGenerator.new()
var terrain: Terrain = null   # ground heights (#8); null = flat map
var tree_stats := {}          # real (OSM) trees: count, moved off the road, dropped (#30, loading log)

# Trees off the road (#30): a real tree on the carriageway moves out to this far beside the curb, unless
# that is further than TREE_MAX_SHIFT away (then it is a mapping error far inside the road and is dropped).
const TREE_CURB_MARGIN := 1.0
const TREE_MAX_SHIFT := 5.0
const REAL_TREE_CELL := 8.0
const STREET_TREE_GAP := 6.0   # made-up street trees keep this far from real ones
const LAMP_ABOVE := 2.0        # a lamp this high above the ground (bridge, ramp) stands above whatever lies below
var _asphalt: AsphaltIndex
var _real_trees := {}         # Vector2i (REAL_TREE_CELL cells) -> Array[Vector2]
var portals: TunnelPortals = null   # railway tunnels register their portals here (#31)
var rail_decks := {}          # rail way index -> deck (BridgeHeights, #32)
var path_decks := {}          # path way index -> deck


func _init(d: OsmData, n: RoadNet, chunk: float) -> void:
	data = d
	net = n
	chunk_size = chunk
	origin = d.bounds.position
	rng.seed = 4242


func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / chunk_size)), int(floor((p.y - origin.y) / chunk_size)))


func layer(ck: Vector2i, name: String, colors := false) -> MeshLayer:
	if not chunks.has(ck):
		chunks[ck] = {}
	var c: Dictionary = chunks[ck]
	if not c.has(name):
		var l := MeshLayer.new()
		l.use_colors = colors
		l.use_uvs = false   # no map shader reads UVs (they use world positions): saves memory and map file size
		# buildings get their own base height, water lies flat at its level
		if name != "building" and name != "water":
			l.terrain = terrain
		c[name] = l
	return c[name]


var progress_cb: Callable   # (fraction 0..1, part name), called from the bake thread

func build_all() -> void:
	_buildings()
	_report(0.6, "Flächen")
	_areas()
	_report(0.75, "Wege")
	_paths()
	_report(0.85, "Gleise")
	_rails()
	_under_rails()
	_report(0.9, "Bäume")
	_trees()
	_report(0.95, "Laternen")
	_lamps()


func _report(f: float, part: String) -> void:
	if progress_cb.is_valid():
		progress_cb.call(f, part)


# ------------------------------------------------------------------------------------------

static func building_height(tags: Dictionary, id: int) -> float:
	var h := RoadNet.parse_width(str(tags.get("height", "")))
	if h > 2.0 and h < 400.0:
		return h
	var lv := str(tags.get("building:levels", ""))
	if lv.is_valid_float():
		var roof_lv := str(tags.get("roof:levels", "0"))
		return maxf(3.0, lv.to_float() * 3.2 + (roof_lv.to_float() * 2.2 if roof_lv.is_valid_float() else 0.0) + 0.8)
	var b: String = tags.get("building", "yes")
	match b:
		"house", "detached", "semidetached_house", "terrace", "bungalow", "farm":
			return 7.5
		"residential", "apartments", "dormitory":
			return 15.0
		"commercial", "office", "retail", "hotel", "civic", "public", "government":
			return 16.0
		"industrial", "warehouse", "manufacture", "hangar", "factory":
			return 9.0
		"garage", "garages", "carport", "shed", "hut", "kiosk", "service", "toilets", "container", "cabin":
			return 3.0
		"roof":
			return 4.0
		"church", "cathedral", "chapel", "mosque", "synagogue", "temple":
			return 22.0
		"school", "university", "college", "hospital", "kindergarten":
			return 13.0
		"train_station", "transportation":
			return 12.0
	var hsh := absi(id * 2654435761) % 1000
	return 9.0 + float(hsh) / 1000.0 * 8.0


func _buildings() -> void:
	var bi := 0
	var bn := maxi(1, data.buildings.size())
	for b in data.buildings:
		bi += 1
		if bi % 400 == 0:
			_report(0.6 * bi / bn, "Gebäude %d/%d" % [bi, bn])
		var outer: PackedVector2Array = b.outer
		if outer.size() < 3:
			continue
		var c := Geo.polygon_centroid(outer)
		if not hq_rect.is_empty() and Geometry2D.is_point_in_polygon(c, hq_rect):
			continue
		if not hq_rect.is_empty() and not Geometry2D.intersect_polygons(outer, hq_rect).is_empty():
			continue
		var area := absf(Geo.polygon_area(outer))
		if area < 6.0:
			continue
		var h := building_height(b.tags, b.id)
		var ck := chunk_of(c)
		var l := layer(ck, "building", true)
		var v := float(absi(b.id * 40503) % 100) / 100.0
		var wall_col := Color(0.90 + v * 0.07, 0.90 + v * 0.065, 0.895 + v * 0.06)
		var roof_col := Color(0.80 + v * 0.06, 0.80 + v * 0.06, 0.80 + v * 0.055)
		var is_roof_only: bool = b.tags.get("building", "") == "roof"
		# on slopes: the roof is h above the mean ground of the outline, the walls reach below its lowest point
		var g_lo := 0.0
		var g_mean := 0.0
		if terrain:
			g_lo = INF
			for p in outer:
				var gh := terrain.sample(p.x, p.y)
				g_lo = minf(g_lo, gh)
				g_mean += gh
			g_mean /= outer.size()
			g_lo -= 0.6
		var top := g_mean + h
		var base := top - 0.4 if is_roof_only else g_lo
		_walls(l, outer, base, top, wall_col)
		for hole in b.holes:
			_walls(l, hole, base, top, wall_col, true)
		l.polygon_up(outer, top, 0.0, roof_col, b.holes)


## Extruded walls; normals point away from the polygon interior (or into it for holes).
func _walls(l: MeshLayer, ring: PackedVector2Array, y0: float, y1: float, col: Color, hole := false) -> void:
	var n := ring.size()
	# signed area > 0 means counter-clockwise in (x,z) math orientation -> interior on the left of edges
	var ccw := Geo.polygon_area(ring) > 0.0
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var d := b - a
		var dl := d.length()
		if dl < 0.01:
			continue
		d /= dl
		# for a CCW ring (math orientation), outward normal = (d.y, -d.x)
		var out := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		if hole:
			out = -out
		var nn := Vector3(out.x, 0, out.y)
		l.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), nn,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


func _areas() -> void:
	var levels: Dictionary = terrain.info.get("water_levels", {}) if terrain else {}
	for ai in data.areas.size():
		var a: Dictionary = data.areas[ai]
		var kind: String = a.kind
		var outer: PackedVector2Array = a.outer
		if outer.size() < 3:
			continue
		var ck := chunk_of(Geo.polygon_centroid(outer))
		if kind == "water":
			var l := layer(ck, "water")
			l.polygon_up(outer, WATER_Y + float(levels.get(ai, 0.0)), 0.05, Color.WHITE, a.holes)
		else:
			var y: float = Y.get(kind, 0.015)
			var l2 := layer(ck, "area_" + kind)
			l2.polygon_up(outer, y, 0.1, Color.WHITE, a.holes)


func _paths() -> void:
	for pi in data.paths.size():
		var p: Dictionary = data.paths[pi]
		var hw: String = p.tags.get("highway", "")
		var w := 2.0
		var layer_name := "path"
		match hw:
			"cycleway":
				w = 2.0
				layer_name = "cycleway"
			"pedestrian":
				w = 6.0
			"steps":
				w = 2.0
			"track":
				w = 3.0
				layer_name = "track"
		var tw := RoadNet.parse_width(str(p.tags.get("width", "")))
		if tw > 0.5 and tw < 12.0:
			w = tw
		var pts := Geo.chaikin(p.pts, 1, 2.0)
		var dk: Dictionary = path_decks.get(pi, {})
		if not dk.is_empty():
			pts = Geo.densify(pts, 3.0)
		var ck := chunk_of(pts[pts.size() >> 1])
		var l := layer(ck, layer_name)
		if terrain:
			terrain.mode_deck = dk
		_flat_strip(l, pts, w, PATH_Y)
		if not dk.is_empty():
			# a raised path (ramp, beside a raised road) on an embankment; bridges and stairs are concrete
			if str(p.tags.get("bridge", "")) in ["", "no"] and p.tags.get("highway", "") != "steps":
				_embankment_line(ck, dk, pts, w * 0.5)
			else:
				_deck_sides(ck, pts, w * 0.5, 1.1)
	if terrain:
		terrain.mode_deck = {}


func _flat_strip(l: MeshLayer, pts: PackedVector2Array, w: float, y: float) -> void:
	if pts.size() < 2:
		return
	var a := Geo.offset_polyline(pts, -w * 0.5)
	var b := Geo.offset_polyline(pts, w * 0.5)
	for i in range(pts.size() - 1):
		l.quad(Geo.v3(a[i], y), Geo.v3(b[i], y), Geo.v3(b[i + 1], y), Geo.v3(a[i + 1], y), Vector3.UP, a[i], b[i], b[i + 1], a[i + 1])


func _rails() -> void:
	for ri in data.rails.size():
		var r: Dictionary = data.rails[ri]
		if terrain:
			terrain.mode_deck = rail_decks.get(ri, {})
		var pts := Geo.chaikin(r.pts, 2, 3.0)
		var dk: Dictionary = rail_decks.get(ri, {})
		if not dk.is_empty():
			pts = Geo.densify(pts, 3.0)   # the ballast follows the profile of a raised track (#32)
		var ck := chunk_of(pts[pts.size() >> 1])
		var is_tram: bool = r.tags.get("railway", "") == "tram"
		if not is_tram:
			_flat_strip(layer(ck, "ballast"), pts, 3.4, BALLAST_Y)
		var rl := layer(ck, "rail")
		# rails use a plain material without the per-pixel ground height: short pieces, so they do not dip
		# into the ballast on crests (#8)
		var rpts := Geo.densify(pts, 5.0) if terrain else pts
		for off in [-0.72, 0.72]:
			var line := Geo.offset_polyline(rpts, off)
			_flat_strip(rl, line, 0.08, 0.075 if is_tram else 0.12)
		if not dk.is_empty():
			if str(r.tags.get("bridge", "")) in ["", "no"]:
				_embankment_line(ck, dk, pts, 1.9)
			else:
				_deck_sides(ck, pts, 2.0, 1.0)
	if terrain:
		terrain.mode_deck = {}


## Sides of a raised deck (railway and path bridges, #32): concrete from 1.2 m below the surface up to a
## parapet of `parapet` metres, `hw` to either side of the centre line. Built while terrain.mode_deck is set.
func _deck_sides(ck: Vector2i, pts: PackedVector2Array, hw: float, parapet: float) -> void:
	var cb := layer(ck, "bridge")
	for side in [1.0, -1.0]:
		var line := Geo.offset_polyline(pts, (hw + 0.3) * side)
		var line_in := Geo.offset_polyline(pts, hw * side)
		for i in range(line.size() - 1):
			var a := line[i]
			var b := line[i + 1]
			var nout: Vector2 = Geo.right_of((b - a).normalized()) * side
			var n := Vector3(nout.x, 0, nout.y)
			cb.quad(Geo.v3(a, -1.2), Geo.v3(b, -1.2), Geo.v3(b, parapet), Geo.v3(a, parapet), n)
			cb.quad(Geo.v3(line_in[i], 0.0), Geo.v3(line_in[i + 1], 0.0), Geo.v3(line_in[i + 1], parapet),
				Geo.v3(line_in[i], parapet), -n)
			cb.quad(Geo.v3(line_in[i], parapet), Geo.v3(line_in[i + 1], parapet), Geo.v3(b, parapet), Geo.v3(a, parapet), Vector3.UP)


## Embankment of a raised track or path that is no bridge (#32): grass slopes 1 : 1.5 down to the ground.
func _embankment_line(ck: Vector2i, dk: Dictionary, pts: PackedVector2Array, hw: float) -> void:
	var keep: Dictionary = terrain.mode_deck
	terrain.mode_deck = {}
	var l := layer(ck, "embankment")
	for side in [1.0, -1.0]:
		var tops := Geo.offset_polyline(pts, hw * side)
		var feet := PackedVector2Array()
		var ht := PackedFloat32Array()   # top height above its own ground (the edge of the deck, cross-slopes)
		for i in pts.size():
			var r := terrain.deck_at(dk, tops[i]) - terrain.sample(tops[i].x, tops[i].y)
			var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			feet.append(tops[i] + Geo.right_of(d) * side * (maxf(r, 0.0) * 1.5 + 0.05))
			ht.append(r - 0.02)
		for i in pts.size() - 1:
			if ht[i] < 0.05 and ht[i + 1] < 0.05:
				continue
			var out: Vector2 = Geo.right_of((pts[i + 1] - pts[i]).normalized()) * side
			var n := (Vector3.UP * 1.5 + Vector3(out.x, 0.0, out.y)).normalized()
			l.quad(Geo.v3(tops[i], maxf(ht[i], 0.0)), Geo.v3(tops[i + 1], maxf(ht[i + 1], 0.0)), Geo.v3(feet[i + 1], 0.0),
				Geo.v3(feet[i], 0.0), n)
	terrain.mode_deck = keep


## Railways below the surface (#31): a band per track for the underground view (U-Bahn blue, other trains
## green) and a portal where a track comes up to a railway on the surface.
func _under_rails() -> void:
	var ends := {}    # rounded end point of a surface railway -> its indices
	for ri in data.rails.size():
		var pts: PackedVector2Array = data.rails[ri].pts
		for p in [pts[0], pts[pts.size() - 1]]:
			var k := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
			if not ends.has(k):
				ends[k] = []
			ends[k].append(ri)
	for r in data.under_rails:
		var raw: PackedVector2Array = r.pts
		if raw.size() < 2:
			continue
		var pts := Geo.chaikin(raw, 2, 3.0)
		var lname := "under_subway" if r.tags.get("railway", "") == "subway" else "under_rail"
		_flat_strip(layer(chunk_of(pts[pts.size() >> 1]), lname), pts, 3.0, 0.1)
		if portals == null:
			continue
		var cum := Geo.cumulative(raw)
		var total: float = cum[cum.size() - 1]
		for at_end in [false, true]:
			var p: Vector2 = raw[raw.size() - 1] if at_end else raw[0]
			var k := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
			if not ends.has(k) or total < 4.0:
				continue
			var q: Vector2 = Geo.sample(raw, cum, total - 3.0 if at_end else 3.0)[0]
			var own: Array = []
			for ri in ends[k]:
				own.append(TunnelPortals.rail_owner(ri))
			portals.add(p, q - p, 2.2, 2.2, "rail", own)


# ------------------------------------------------------------------------------------------
# Vegetation and lamps
# ------------------------------------------------------------------------------------------

func _add_tree(p: Vector2, scale: float) -> void:
	if not data.bounds.has_point(p):
		return
	if not hq_rect.is_empty() and Geometry2D.is_point_in_polygon(p, hq_rect):
		return
	var ck := chunk_of(p)
	if not trees.has(ck):
		trees[ck] = []
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
	trees[ck].append(Transform3D(b, Vector3(p.x, terrain.sample(p.x, p.y) if terrain else 0.0, p.y)))


func _trees() -> void:
	# Real trees (Hamburg maps every street tree, often in the parking strip between the bays) stand where
	# the game draws a wider carriageway: move them out to the sidewalk, drop the few deep in the road (#30).
	_asphalt = AsphaltIndex.new(net, terrain)
	var moved := 0
	var dropped := 0
	for t in data.trees:
		var sc := rng.randf_range(0.8, 1.25)
		var spot = _asphalt.clear_spot(t, TREE_CURB_MARGIN, TREE_MAX_SHIFT)
		if spot == null:
			dropped += 1
			continue
		if spot != t:
			moved += 1
		_add_tree(spot, sc)
		var rc := Vector2i(int(floor(spot.x / REAL_TREE_CELL)), int(floor(spot.y / REAL_TREE_CELL)))
		if not _real_trees.has(rc):
			_real_trees[rc] = []
		_real_trees[rc].append(spot)
	tree_stats = {"osm": data.trees.size(), "moved": moved, "dropped": dropped}
	for a in data.areas:
		var density := 0.0
		match a.kind:
			"forest":
				density = 1.0 / 70.0
			"park", "cemetery":
				density = 1.0 / 260.0
			"grass":
				density = 1.0 / 900.0
		if density <= 0.0:
			continue
		var outer: PackedVector2Array = a.outer
		var area := absf(Geo.polygon_area(outer))
		var count := mini(int(area * density), 600)
		var r := Rect2(outer[0], Vector2.ZERO)
		for p in outer:
			r = r.expand(p)
		var tries := 0
		var placed := 0
		while placed < count and tries < count * 4:
			tries += 1
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			if Geometry2D.is_point_in_polygon(p, outer) and not _asphalt.on_asphalt(p):
				_add_tree(p, rng.randf_range(0.75, 1.3))
				placed += 1
	# street trees along residential streets with sidewalks
	for e in net.edges:
		if not (e.cls in ["residential", "living_street", "tertiary", "secondary"]) or e.bridge or e.get("under", false):
			continue
		if e.sw_r <= 0.0 and e.sw_l <= 0.0:
			continue
		var s: float = e.trim_a + 6.0
		var side := 1.0
		while s < e.len - e.trim_b - 6.0:
			if rng.randf() < 0.55:
				var smp := Geo.sample(e.pts, e.cum, s)
				var r := Geo.right_of(smp[1])
				var off: float = e.width * 0.5 + (e.sw_r if side > 0 else e.sw_l) * 0.5
				var p: Vector2 = smp[0] + r * off * side
				if ((side > 0 and e.sw_r > 0) or (side < 0 and e.sw_l > 0)) and not _asphalt.on_asphalt(p) \
						and not _near_real_tree(p):
					_add_tree(p, rng.randf_range(0.7, 1.05))
			s += rng.randf_range(10.0, 16.0)
			side = -side


## True if a real (OSM) tree stands within STREET_TREE_GAP of p.
func _near_real_tree(p: Vector2) -> bool:
	var c := Vector2i(int(floor(p.x / REAL_TREE_CELL)), int(floor(p.y / REAL_TREE_CELL)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q in _real_trees.get(c + Vector2i(dx, dz), []):
				if (q as Vector2).distance_to(p) < STREET_TREE_GAP:
					return true
	return false


func _lamps() -> void:
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		if e.cls in ["motorway", "service", "track"] or e.tunnel or e.get("under", false):
			continue
		var spacing := 32.0 if e.cls in ["primary", "secondary", "trunk"] else 38.0
		var both: bool = e.width > 11.0
		var s: float = e.trim_a + 8.0
		var side := 1.0
		while s < e.len - e.trim_b - 4.0:
			var smp := Geo.sample(e.pts, e.cum, s)
			var d: Vector2 = smp[1]
			var r := Geo.right_of(d)
			for sd in ([1.0, -1.0] if both else [side]):
				var sw: float = e.sw_r if sd > 0 else e.sw_l
				var off: float = e.width * 0.5 + (sw - 0.45 if sw > 0.0 else 0.6)
				var p: Vector2 = smp[0] + r * off * sd
				var ly := terrain.deck_height(ei, p) if terrain else 0.0
				# not on a neighbouring road or junction area (#30); a lamp high up on a bridge or ramp (#32) may
				# stand above one
				var above := terrain != null and ly - terrain.sample(p.x, p.y) > LAMP_ABOVE
				if _asphalt != null and not above and _asphalt.on_asphalt(p):
					continue
				var ck := chunk_of(p)
				if not lamps.has(ck):
					lamps[ck] = []
				# lamp arm points toward the road (-r*sd)
				var toward: Vector2 = -r * sd
				var basis := Basis.looking_at(Vector3(toward.x, 0, toward.y), Vector3.UP)
				lamps[ck].append(Transform3D(basis, Vector3(p.x, ly, p.y)))
			s += spacing
			side = -side
