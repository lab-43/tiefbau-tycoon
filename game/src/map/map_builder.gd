class_name MapBuilder
extends RefCounted
## Bakes a map from raw OSM files: parse -> road network -> meshes. Runs in a worker thread.
## The scene-tree part (creating MeshInstances) happens on the main thread in build_scene().

const CHUNK := 500.0
const BAKE_VERSION := 9   # 4: water on top of the base ground, no bank walls (#4); 5: merged junctions (#5); 6: smooth transitions (#5); 7: arc turn paths, islands (#5); 8: ground heights (#8); 9: markings after RMS (#5)
const GROUND_Y := 0.0     # opaque base ground plane; flat map layers below it are invisible (test/layer_test.gd)

var progress := 0.0
var step := ""
var result := {}
var _mutex := Mutex.new()


func set_step(s: String, p: float) -> void:
	_mutex.lock()
	step = s
	progress = p
	_mutex.unlock()


var _notes: Array = []
var _t0 := 0


## A line for the loading screen log (thread safe).
func note(s: String) -> void:
	_mutex.lock()
	_notes.append("%s (nach %s)" % [s, ("%.1f s" % ((Time.get_ticks_msec() - _t0) / 1000.0)).replace(".", ",")])
	_mutex.unlock()


func take_notes() -> Array:
	_mutex.lock()
	var n := _notes.duplicate()
	_notes.clear()
	_mutex.unlock()
	return n


func get_status() -> Array:
	_mutex.lock()
	var r := [step, progress]
	_mutex.unlock()
	return r


var _read_end := 0.24


## Later steps share the rest of the bar after reading (reading a .pbf takes longer than JSON).
func _p(x: float) -> float:
	return _read_end + (x - 0.24) * (1.0 - _read_end) / 0.76


## meta: {center_lat, center_lon, size_m, hq: {x, z} (local) optional}
## pbf: path of a Geofabrik extract; empty = read the downloaded Overpass pieces in osm_dir.
func bake(meta: Dictionary, osm_dir: String, pbf := "") -> Dictionary:
	Geo.setup(meta.center_lat, meta.center_lon)
	_t0 = Time.get_ticks_msec()
	set_step("Kartendaten lesen", 0.02)
	var parser := OsmParser.new()
	var data: OsmData
	if pbf != "":
		_read_end = 0.5
		data = parser.parse_pbf(pbf, meta.size_m * 0.5,
			func(f: float, what: String): set_step("Auszug lesen: %s (%d %%)" % [what, int(f * 100.0)], 0.02 + 0.48 * f),
			func(t: String): note(t))
	else:
		_read_end = 0.24
		parser.progress_cb = func(i: int, n: int): set_step("Kartendaten lesen (Datei %d von %d)" % [i + 1, n], 0.02 + 0.22 * i / maxf(1.0, n))
		data = parser.parse_dir(osm_dir, meta.size_m * 0.5)
	note("Kartendaten gelesen: %d Straßenzüge, %d Gebäude, %d Flächen, %d Wege, %d Bäume, %d Ampeln" % [data.roads.size(), data.buildings.size(), data.areas.size(), data.paths.size(), data.trees.size(), data.signals.size()])
	set_step("Zentrale planen", _p(0.25))
	var hq := {}
	if meta.has("hq"):
		hq = plan_hq(data, Vector2(meta.hq.x, meta.hq.z))
	set_step("Geländehöhen aufbereiten", _p(0.27))
	var terrain := TerrainBake.build(meta, data, hq, func(t: String): note(t))
	set_step("Straßennetz berechnen (%d Straßenzüge)" % data.roads.size(), _p(0.30))
	var net := RoadNet.new()
	net.build(data, hq)
	if not hq.is_empty():
		for ni in net.nodes.size():
			if net.nodes[ni].osm_id == -900000002:
				net.hq_node = ni
	note("Straßennetz: %d Kreuzungen (%d aus mehreren OSM-Knoten zusammengefasst), %d Abschnitte, %d Fahrstreifen" % [net.nodes.size(), net.group_count, net.edges.size(), net.lane_geo.size()])
	if terrain:
		TerrainBake.add_decks(terrain, net)
	set_step("Straßen modellieren", _p(0.55))
	var rm := RoadMesher.new(net, CHUNK, data.bounds.position)
	rm.terrain = terrain
	rm.progress_cb = func(f: float): set_step("Straßen modellieren (%d %%)" % int(f * 100.0), _p(0.55 + 0.15 * f))
	rm.build_all()
	note("Straßen modelliert: %d Kacheln" % rm.chunks.size())
	set_step("Gebäude und Flächen modellieren", _p(0.70))
	var cm := CityMesher.new(data, net, CHUNK)
	cm.terrain = terrain
	if not hq.is_empty():
		cm.hq_rect = hq.lot
	cm.progress_cb = func(f: float, part: String): set_step("Stadt modellieren: %s" % part, _p(0.70 + 0.2 * f))
	cm.build_all()
	note("Stadt modelliert: %d Kacheln" % cm.chunks.size())
	if terrain:
		set_step("Boden modellieren", _p(0.88))
		TerrainBake.ground_layers(terrain, cm.chunks, CHUNK, data.bounds.position, float(meta.size_m))
	set_step("Fertigstellen", _p(0.90))
	result = {"net": net, "roads": rm.chunks, "city": cm.chunks, "trees": cm.trees, "lamps": cm.lamps,
		"bounds": data.bounds, "hq": hq, "stats": data.stats, "bus_stops": data.bus_stops, "terrain": terrain}
	set_step("Fertig", 1.0)
	return result


## Choose the HQ lot next to the nearest suitable road and plan the driveway.
static func plan_hq(data: OsmData, click: Vector2) -> Dictionary:
	var best := {}
	var best_d := 400.0
	for wi in data.roads.size():
		var w: Dictionary = data.roads[wi]
		var cls: String = w.tags.get("highway", "")
		if not (cls in ["residential", "unclassified", "tertiary", "secondary", "service", "primary"]):
			continue
		if w.tags.get("service", "") in ["parking_aisle", "driveway"]:
			continue
		var pts: PackedVector2Array = w.pts
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(click, pts[i], pts[i + 1])
			var d := q.distance_to(click)
			# prefer a projection away from segment ends (so the driveway node is a clean T)
			var seg_len := pts[i].distance_to(pts[i + 1])
			if seg_len < 12.0:
				continue
			var t := pts[i].distance_to(q) / seg_len
			if t < 0.15 or t > 0.85:
				q = pts[i].lerp(pts[i + 1], clampf(t, 0.15, 0.85))
				d = q.distance_to(click)
			if d < best_d:
				best_d = d
				best = {"road_way_index": wi, "seg": i, "proj": q, "dir": (pts[i + 1] - pts[i]).normalized()}
	if best.is_empty():
		return {}
	var d: Vector2 = best.dir
	var n := Geo.right_of(d)
	if (click - best.proj).dot(n) < 0.0:
		n = -n
	var front := 9.5
	var gate: Vector2 = best.proj + n * front
	var hw := 34.0
	var depth := 50.0
	var lot := PackedVector2Array([gate - d * hw, gate + d * hw, gate + d * hw + n * depth, gate - d * hw + n * depth])
	best["gate"] = gate
	best["normal"] = n
	best["lot"] = lot
	best["lot_center"] = gate + n * depth * 0.5
	return best


# ------------------------------------------------------------------------------------------
# Main-thread scene creation
# ------------------------------------------------------------------------------------------

const RANGE := {"mark": 900.0, "curb": 1300.0, "sidewalk": 2200.0, "rail": 1200.0, "path": 2200.0, "cycleway": 2200.0,
	"bridge": 2500.0}
const NO_SHADOW := {"ground": 1, "asphalt": 1, "mark": 1, "sidewalk": 1, "path": 1, "cycleway": 1, "water": 1, "ballast": 1, "rail": 1,
	"area_grass": 1, "area_park": 1, "area_forest": 1, "area_pitch": 1, "area_cemetery": 1, "area_farmland": 1,
	"area_industrial": 1, "area_commercial": 1, "area_residential": 1, "area_paved": 1, "area_sand": 1, "track": 1}


## Creates the static city node tree. Call repeatedly (it yields work in batches) until it returns true.
static func create_city_root(res: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "City"
	if res.get("terrain") != null:
		return root   # the ground comes as chunk layers "ground" (TerrainBake.ground_layers)
	var b: Rect2 = res.bounds
	# base ground
	var gm := PlaneMesh.new()
	gm.size = b.size * 1.6
	gm.subdivide_depth = 0
	gm.subdivide_width = 0
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = gm
	g.position = Vector3(b.get_center().x, GROUND_Y, b.get_center().y)
	g.material_override = Mats.get_mat("ground")
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	return root


static func add_chunk_layers(root: Node3D, ck: Vector2i, layers: Dictionary) -> void:
	var holder_name := "c_%d_%d" % [ck.x, ck.y]
	var holder: Node3D = root.get_node_or_null(holder_name)
	if holder == null:
		holder = Node3D.new()
		holder.name = holder_name
		root.add_child(holder)
	for lname in layers:
		var l: MeshLayer = layers[lname]
		if l.is_empty():
			continue
		var mesh := ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		# Visibility ranges count from the node's origin, not from the mesh: the node goes into its
		# chunk and the vertices become relative to it. At the map origin, markings vanished 900 m
		# from the map centre and curbs 1300 m from it (#5).
		var verts: PackedVector3Array = l.verts
		var c: Vector3 = (verts[0] + verts[verts.size() / 2] + verts[verts.size() - 1]) / 3.0
		c.y = 0.0
		arr[Mesh.ARRAY_VERTEX] = Transform3D(Basis(), -c) * verts
		arr[Mesh.ARRAY_NORMAL] = l.normals
		if l.use_uvs and l.uvs.size() == l.verts.size():
			arr[Mesh.ARRAY_TEX_UV] = l.uvs
		if l.use_colors:
			arr[Mesh.ARRAY_COLOR] = l.colors
		arr[Mesh.ARRAY_INDEX] = l.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		var mi := MeshInstance3D.new()
		mi.name = lname
		mi.mesh = mesh
		mi.position = c
		mi.material_override = Mats.get_mat(lname)
		var base := String(lname).trim_suffix("_deck")
		if NO_SHADOW.has(base):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if RANGE.has(base):
			mi.visibility_range_end = RANGE[base]
			mi.visibility_range_end_margin = 60.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mi)


static func add_instances(root: Node3D, ck: Vector2i, kind: String, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var holder_name := "c_%d_%d" % [ck.x, ck.y]
	var holder: Node3D = root.get_node_or_null(holder_name)
	if holder == null:
		holder = Node3D.new()
		holder.name = holder_name
		root.add_child(holder)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PropsMeshes.tree() if kind == "trees" else PropsMeshes.lamp()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = kind
	mmi.multimesh = mm
	if kind == "lamps":
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 1500.0
	else:
		mmi.visibility_range_end = 2600.0
	holder.add_child(mmi)
