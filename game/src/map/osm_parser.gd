class_name OsmParser
extends RefCounted
## Reads raw Overpass JSON responses (tiles + relations + bus routes), projects and classifies them.

var data := OsmData.new()
var _seen_ways := {}
var _seen_rels := {}
var progress_cb: Callable   # (files_done, files_total), called from the bake thread
var _seen_nodes := {}
var _synthetic_id := -1


func parse_dir(osm_dir: String, half_size: float) -> OsmData:
	data.bounds = Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0)
	var t0 := Time.get_ticks_msec()
	# every downloaded piece (tiles, relation batches, bus routes); objects that appear in
	# several pieces are only taken once
	var files: Array = Array(DirAccess.get_files_at(osm_dir)).filter(func(f: String):
		return f.ends_with(".json") and f != "complete.json" and not f.begins_with("ri_"))
	files.sort()
	for i in files.size():
		if progress_cb.is_valid():
			progress_cb.call(i, files.size())
		_parse_file(osm_dir.path_join(files[i]))
	data.stats = {"roads": data.roads.size(), "buildings": data.buildings.size(), "areas": data.areas.size(),
		"paths": data.paths.size(), "rails": data.rails.size(), "trees": data.trees.size(),
		"signals": data.signals.size(), "bus_ways": data.bus_way_ids.size(), "ms": Time.get_ticks_msec() - t0}
	return data


## Reads a .osm.pbf extract (Geofabrik) instead of downloaded Overpass pieces.
func parse_pbf(path: String, half_size: float, progress: Callable = Callable(), note: Callable = Callable()) -> OsmData:
	data.bounds = Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0)
	var t0 := Time.get_ticks_msec()
	var r := PbfReader.new()
	r.parser = self
	r.progress_cb = progress
	r.note_cb = note
	if not r.read(path, data.bounds):
		push_warning("pbf could not be read: " + path)
	data.stats = {"roads": data.roads.size(), "buildings": data.buildings.size(), "areas": data.areas.size(),
		"paths": data.paths.size(), "rails": data.rails.size(), "trees": data.trees.size(),
		"signals": data.signals.size(), "bus_ways": data.bus_way_ids.size(), "ms": Time.get_ticks_msec() - t0}
	return data


func _parse_file(path: String) -> void:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		push_warning("empty osm file " + path)
		return
	var doc = JSON.parse_string(txt)
	txt = ""
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("elements"):
		push_warning("invalid osm file " + path)
		return
	for el in doc["elements"]:
		match el.get("type", ""):
			"node":
				_node(el)
			"way":
				_way(el)
			"relation":
				_relation(el)


func _node(el: Dictionary) -> void:
	var id: int = int(el["id"])
	if _seen_nodes.has(id):
		return
	_seen_nodes[id] = true
	var tags: Dictionary = el.get("tags", {})
	var p := Geo.to_local(float(el["lat"]), float(el["lon"]))
	if not data.bounds.has_point(p):
		return
	var hw: String = tags.get("highway", "")
	match hw:
		"traffic_signals":
			data.signals[id] = p
		"crossing":
			var kind := "marked"
			var c: String = tags.get("crossing", "")
			if c == "traffic_signals":
				kind = "signals"
			elif c in ["zebra", "marked", "uncontrolled"] or tags.get("crossing_ref", "") == "zebra":
				kind = "zebra"
			elif c in ["unmarked", "no", "informal"]:
				kind = "none"
			data.crossings[id] = {"pos": p, "kind": kind}
		"stop", "give_way":
			data.give_way[id] = p
			if tags.get("highway", "") == "stop":
				data.stops[id] = true
		"bus_stop":
			data.bus_stops.append(p)
		"street_lamp":
			data.lamps.append(p)
	if tags.get("natural", "") == "tree":
		data.trees.append(p)


func _geom(el: Dictionary) -> PackedVector2Array:
	if el.has("pts"):
		return el.pts   # from a .pbf extract: already local coordinates
	var g: Array = el.get("geometry", [])
	var pts := PackedVector2Array()
	pts.resize(g.size())
	var i := 0
	for c in g:
		if c == null:
			continue
		pts[i] = Geo.to_local(float(c["lat"]), float(c["lon"]))
		i += 1
	if i != g.size():
		pts.resize(i)
	return pts


func _way(el: Dictionary) -> void:
	var id: int = int(el["id"])
	if _seen_ways.has(id):
		return
	_seen_ways[id] = true
	var tags: Dictionary = el.get("tags", {})
	var pts := _geom(el)
	if pts.size() < 2:
		return
	var hw: String = tags.get("highway", "")
	if hw != "" and tags.get("area", "") != "yes":
		if OsmData.DRIVABLE.has(hw):
			if tags.get("access", "") in ["no", "private"] and hw != "service":
				pass
			var ids := PackedInt64Array()
			for n in el.get("nodes", []):
				ids.append(int(n))
			if ids.size() != pts.size():
				return
			_add_road(id, ids, pts, tags)
		elif OsmData.PATHS.has(hw) and tags.get("tunnel", "") == "" and tags.get("indoor", "") == "":
			_add_clipped_lines(data.paths, id, pts, tags)
		return
	if tags.has("building") and tags.get("building", "") != "no":
		if pts.size() >= 4 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
			var outer := pts.slice(0, pts.size() - 1)
			if data.bounds.has_point(Geo.polygon_centroid(outer)) and tags.get("location", "") != "underground":
				data.buildings.append({"id": id, "outer": outer, "holes": [], "tags": tags})
		return
	var rw: String = tags.get("railway", "")
	if rw in ["rail", "light_rail", "subway", "tram"]:
		# a track through a building stays on the surface (the building hides it), as building passages of roads
		if tags.get("tunnel", "") in ["", "building_passage"] and tags.get("layer", "0").to_int() >= 0:
			_add_clipped_lines(data.rails, id, pts, tags)
		else:
			_add_clipped_lines(data.under_rails, id, pts, tags)
		return
	var kind := OsmData.area_kind(tags)
	if kind != "" and pts.size() >= 4 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
		_add_area(id, kind, pts.slice(0, pts.size() - 1), [], tags)


func _add_area(id: int, kind: String, outer: PackedVector2Array, holes: Array, tags: Dictionary) -> void:
	var bpoly := PackedVector2Array([data.bounds.position, Vector2(data.bounds.end.x, data.bounds.position.y),
		data.bounds.end, Vector2(data.bounds.position.x, data.bounds.end.y)])
	var r := Rect2(outer[0], Vector2.ZERO)
	for p in outer:
		r = r.expand(p)
	if not r.intersects(data.bounds):
		return
	if data.bounds.encloses(r):
		data.areas.append({"id": id, "kind": kind, "outer": outer, "holes": holes, "tags": tags})
		return
	for clipped in Geometry2D.intersect_polygons(outer, bpoly):
		if Geometry2D.is_polygon_clockwise(clipped) != Geometry2D.is_polygon_clockwise(outer) and clipped.size() > 0:
			pass
		data.areas.append({"id": id, "kind": kind, "outer": clipped, "holes": holes, "tags": tags})


## Clip a road way to the map rectangle, splitting into inside runs. Boundary cut points get synthetic ids.
func _add_road(id: int, ids: PackedInt64Array, pts: PackedVector2Array, tags: Dictionary) -> void:
	var b := data.bounds
	var n := pts.size()
	var run_ids := PackedInt64Array()
	var run_pts := PackedVector2Array()
	var part := 0
	for i in n:
		var inside := b.has_point(pts[i])
		if inside:
			if run_pts.is_empty() and i > 0:
				var cut := _clip_point(pts[i - 1], pts[i], b)
				run_pts.append(cut)
				run_ids.append(_synthetic_id)
				_synthetic_id -= 1
			run_pts.append(pts[i])
			run_ids.append(ids[i])
		else:
			if not run_pts.is_empty():
				var cut := _clip_point(pts[i], pts[i - 1], b)
				run_pts.append(cut)
				run_ids.append(_synthetic_id)
				_synthetic_id -= 1
				if run_pts.size() >= 2:
					data.roads.append({"id": id, "part": part, "ids": run_ids, "pts": run_pts, "tags": tags})
					part += 1
				run_ids = PackedInt64Array()
				run_pts = PackedVector2Array()
	if run_pts.size() >= 2:
		data.roads.append({"id": id, "part": part, "ids": run_ids, "pts": run_pts, "tags": tags})


func _add_clipped_lines(target: Array, id: int, pts: PackedVector2Array, tags: Dictionary) -> void:
	var b := data.bounds.grow(-1.0)
	var run := PackedVector2Array()
	for i in pts.size():
		if b.has_point(pts[i]):
			if run.is_empty() and i > 0:
				run.append(_clip_point(pts[i - 1], pts[i], b))
			run.append(pts[i])
		elif not run.is_empty():
			run.append(_clip_point(pts[i], pts[i - 1], b))
			if run.size() >= 2:
				target.append({"id": id, "pts": run, "tags": tags})
			run = PackedVector2Array()
	if run.size() >= 2:
		target.append({"id": id, "pts": run, "tags": tags})


## Point where segment outside->inside crosses the rectangle border.
func _clip_point(outside: Vector2, inside: Vector2, b: Rect2) -> Vector2:
	var t_best := 0.0
	var d := inside - outside
	for axis in 2:
		var lo := b.position[axis]
		var hi := b.end[axis]
		if absf(d[axis]) < 0.000001:
			continue
		for edge in [lo, hi]:
			var t: float = (edge - outside[axis]) / d[axis]
			if t >= 0.0 and t <= 1.0:
				var q := outside + d * t
				var other := 1 - axis
				if q[other] >= b.position[other] - 0.01 and q[other] <= b.end[other] + 0.01:
					t_best = maxf(t_best, t)
	return outside + d * t_best


func _relation(el: Dictionary) -> void:
	var rid := int(el.get("id", 0))
	if _seen_rels.has(rid):
		return
	if el.has("tags"):
		_seen_rels[rid] = true
	var tags: Dictionary = el.get("tags", {})
	var t: String = tags.get("type", "")
	if t == "route" and tags.get("route", "") == "bus":
		for m in el.get("members", []):
			if m.get("type", "") == "way":
				data.bus_way_ids[int(m["ref"])] = true
		return
	if t != "multipolygon":
		return
	var outers: Array = []
	var inners: Array = []
	for m in el.get("members", []):
		if m.get("type", "") != "way" or not (m.has("geometry") or m.has("pts")):
			continue
		var pts := _geom(m)
		if pts.size() < 2:
			continue
		if m.get("role", "") == "inner":
			inners.append(pts)
		else:
			outers.append(pts)
	var outer_rings := _assemble_rings(outers)
	var inner_rings := _assemble_rings(inners)
	var is_building: bool = tags.has("building") and tags.get("building", "") != "no"
	var kind := "" if is_building else OsmData.area_kind(tags)
	if not is_building and kind == "":
		return
	for ring in outer_rings:
		var holes: Array = []
		for h in inner_rings:
			if h.size() > 2 and Geometry2D.is_point_in_polygon(h[0], ring):
				holes.append(h)
		if is_building:
			if data.bounds.has_point(Geo.polygon_centroid(ring)):
				data.buildings.append({"id": int(el["id"]), "outer": ring, "holes": holes, "tags": tags})
		else:
			_add_area(int(el["id"]), kind, ring, holes, tags)


## Join open way segments into closed rings by matching endpoints.
static func _assemble_rings(segs: Array) -> Array:
	var rings: Array = []
	var open: Array = []
	for s in segs:
		if s.size() >= 4 and s[0].distance_to(s[s.size() - 1]) < 0.05:
			rings.append(s.slice(0, s.size() - 1))
		else:
			open.append(s)
	var guard := 0
	while not open.is_empty() and guard < 100000:
		guard += 1
		var cur: PackedVector2Array = open.pop_back()
		var progressed := true
		while progressed:
			progressed = false
			if cur[0].distance_to(cur[cur.size() - 1]) < 0.05 and cur.size() >= 4:
				break
			for i in range(open.size() - 1, -1, -1):
				var o: PackedVector2Array = open[i]
				var tail := cur[cur.size() - 1]
				var head := cur[0]
				if tail.distance_to(o[0]) < 0.05:
					cur.append_array(o.slice(1))
				elif tail.distance_to(o[o.size() - 1]) < 0.05:
					var r := o.duplicate()
					r.reverse()
					cur.append_array(r.slice(1))
				elif head.distance_to(o[o.size() - 1]) < 0.05:
					var c2 := o.duplicate()
					c2.append_array(cur.slice(1))
					cur = c2
				elif head.distance_to(o[0]) < 0.05:
					var r2 := o.duplicate()
					r2.reverse()
					r2.append_array(cur.slice(1))
					cur = r2
				else:
					continue
				open.remove_at(i)
				progressed = true
				break
		if cur.size() >= 4 and cur[0].distance_to(cur[cur.size() - 1]) < 0.05:
			rings.append(cur.slice(0, cur.size() - 1))
		elif cur.size() >= 3:
			rings.append(cur)  # unclosed (clipped by data extent) - treat as closed best effort
	return rings
