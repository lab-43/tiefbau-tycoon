extends SceneTree
## Junction bench ("Kreuzungs-Prüfstand"): builds the road network and road meshes for small fixed
## OSM extracts (testdata/kreuzungen) and exports the result as JSON for tools/kreuzungen.py, which
## measures gaps, overlaps, lane kinks and markings and draws top-down pictures.
## usage: godot --headless --path game -s res://test/junction_bench.gd -- --fixtures=<dir> --out=<dir> [--only=a,b]
## Prints "BENCH OK <n>" when every fixture was exported, exit code 1 otherwise.

const LAYERS := ["asphalt", "sidewalk", "mark"]


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var dir: String = args.get("fixtures", "")
	var out: String = args.get("out", "")
	if dir == "" or out == "":
		print("usage: -- --fixtures=<dir> --out=<dir> [--only=a,b]")
		quit(2)
		return
	var only: PackedStringArray = str(args.get("only", "")).split(",", false)
	var spec = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("kreuzungen.json")))
	if typeof(spec) != TYPE_DICTIONARY:
		print("BENCH FAIL kreuzungen.json fehlt oder ist kaputt")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var half: float = float(spec.get("ausschnitt_halbe_kante_m", 300.0))
	var done := 0
	var failed: Array = []
	for fx in spec.kreuzungen:
		var fid: String = fx.id
		if not only.is_empty() and not (fid in only):
			continue
		var t0 := Time.get_ticks_msec()
		var res := _bake_one(dir.path_join(fid + ".osm.pbf"), float(fx.lat), float(fx.lon), half)
		if res.is_empty():
			failed.append(fid)
			continue
		res["id"] = fid
		res["name"] = fx.name
		res["radius_m"] = float(fx.get("radius_m", 150.0))
		res["ms"] = Time.get_ticks_msec() - t0
		var f := FileAccess.open(out.path_join(fid + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(res))
		f.close()
		print("  %s: %d Knoten, %d Abschnitte, %d Verbindungen (%d ms)" % [fid, res.nodes.size(), res.edges.size(), res.connectors.size(), res.ms])
		done += 1
	if failed.is_empty() and done > 0:
		print("BENCH OK %d" % done)
		quit(0)
	else:
		print("BENCH FAIL ", failed)
		quit(1)


func _bake_one(pbf: String, lat: float, lon: float, half: float) -> Dictionary:
	if not FileAccess.file_exists(pbf):
		print("fehlt: ", pbf)
		return {}
	Geo.setup(lat, lon)
	var parser := OsmParser.new()
	var data := parser.parse_pbf(pbf, half)
	var net := RoadNet.new()
	net.build(data, {})
	var rm := RoadMesher.new(net, MapBuilder.CHUNK, data.bounds.position)
	rm.build_all()
	var win := half - 40.0
	var layers := {}
	for ln in LAYERS:
		layers[ln] = PackedFloat32Array()
	for ck in rm.chunks:
		var c: Dictionary = rm.chunks[ck]
		for ln in LAYERS:
			if c.has(ln):
				_append_tris(layers[ln], c[ln], win)
	var lay_out := {}
	for ln in LAYERS:
		lay_out[ln] = Array(layers[ln])
	var nodes: Array = []
	for ni in net.nodes.size():
		var n: Dictionary = net.nodes[ni]
		var p: Vector2 = n.pos
		if absf(p.x) > win or absf(p.y) > win:
			continue
		nodes.append({"idx": ni, "pos": [p.x, p.y], "deg": n.ends.size(), "ctrl": n.ctrl, "group": int(n.get("group", 0)),
			"cont": n.get("cont", false), "area": n.get("area", false), "poly": _flat(n.get("polygon", PackedVector2Array()))})
	var edges: Array = []
	for e in net.edges:
		if not _near(e.pts, win):
			continue
		edges.append({"cls": e.cls, "len": e.len, "oneway": e.oneway, "lf": e.lf, "lb": e.lb, "lw": e.lw, "width": e.width,
			"name": e.name, "trim_a": e.trim_a, "trim_b": e.trim_b, "pts": _flat(e.pts)})
	var lanes: Array = []
	for key in net.lane_geo:
		var g: Array = net.lane_geo[key]
		if not _near(g[0], win):
			continue
		lanes.append({"key": key, "cls": net.edges[key >> 4].cls, "pts": _flat(g[0])})
	var conns: Array = []
	for ci in net.connectors.size():
		var c: Dictionary = net.connectors[ci]
		if not _near(c.pts, win):
			continue
		conns.append({"from": c.from, "to": c.to, "turn": c.turn, "node": c.node, "pts": _flat(c.pts)})
	return {"half": half, "window": win, "layers": lay_out, "nodes": nodes, "edges": edges, "lanes": lanes,
		"connectors": conns, "osm_roads": _osm_roads(data, win), "mark_stats": rm.marks.stats}


## Raw OSM centre lines (for the picture), only car roads.
func _osm_roads(data: OsmData, win: float) -> Array:
	var res: Array = []
	for w in data.roads:
		var pts: PackedVector2Array = w.pts
		if _near(pts, win):
			res.append({"cls": str(w.tags.get("highway", "")), "oneway": str(w.tags.get("oneway", "")), "pts": _flat(pts)})
	return res


## Horizontal triangles of a mesh layer as flat x,z lists (only triangles touching the window).
func _append_tris(dst: PackedFloat32Array, l: MeshLayer, win: float) -> void:
	var v := l.verts
	var idx := l.indices
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		# skip vertical faces (curbs, bridge sides)
		if absf(a.y - b.y) > 0.001 or absf(a.y - c.y) > 0.001:
			continue
		if minf(minf(absf(a.x), absf(b.x)), absf(c.x)) > win or minf(minf(absf(a.z), absf(b.z)), absf(c.z)) > win:
			continue
		dst.append_array(PackedFloat32Array([a.x, a.z, b.x, b.z, c.x, c.z]))


func _near(pts: PackedVector2Array, win: float) -> bool:
	for p in pts:
		if absf(p.x) <= win and absf(p.y) <= win:
			return true
	return false


func _flat(pts: PackedVector2Array) -> Array:
	var r: Array = []
	for p in pts:
		r.append(snappedf(p.x, 0.001))
		r.append(snappedf(p.y, 0.001))
	return r
