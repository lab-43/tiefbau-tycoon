class_name PbfReader
extends RefCounted
## Reads an OpenStreetMap .osm.pbf extract (e.g. from Geofabrik) and hands the objects of the map
## area to an OsmParser, in the same form the Overpass answers have. Runs in the bake thread.
##
## Three passes over the file (each block is decompressed by Godot's zlib, the rest is GDScript):
##   1. relations: which multipolygons and bus routes exist, which ways they need
##   2. ways: node ids of the ways the multipolygons need (so their rings can be closed)
##   3. nodes + ways: node positions in the map area (+ margin) and the needed ones, then the ways
## Relations are assembled at the end.

const MARGIN := 800.0          # metres around the map whose nodes are kept (ways crossing the edge)

const WAY_KEYS := {
	"highway": null, "building": null, "landuse": null,
	"leisure": ["park", "garden", "playground", "pitch", "sports_centre", "golf_course"],
	"natural": ["water", "wood", "scrub", "grassland", "heath", "sand", "beach", "wetland"],
	"waterway": ["riverbank", "dock", "canal", "river"],
	"water": null, "amenity": ["parking"], "railway": ["rail", "light_rail", "subway", "tram"],
	"area:highway": null, "man_made": ["bridge"],
}
const NODE_KEYS := {
	"highway": ["traffic_signals", "stop", "give_way", "crossing", "bus_stop", "street_lamp"],
	"natural": ["tree"],
}
const REL_KEYS := {
	"building": null, "landuse": null, "leisure": ["park", "garden"],
	"natural": ["water", "wood", "scrub", "grassland", "wetland"], "waterway": ["riverbank"], "water": null,
	"man_made": ["bridge"],
}

var parser: OsmParser
var progress_cb: Callable      # (fraction 0..1, text)
var note_cb: Callable          # (text)
var bounds: Rect2              # map area in local metres
var stats := {}

var _path := ""
var _size := 0
var _pass_w := [0.12, 0.13, 0.75]
var _pass := 0
var _ext: Rect2                # map area + margin (local metres)
var _lat_min := 0.0            # map area + margin in degrees
var _lat_max := 0.0
var _lon_min := 0.0
var _lon_max := 0.0

var _rels: Array = []          # multipolygons: {id, tags, mem: [[type, ref, role]]}
var _bus: Array = []
var _need_ways := {}           # way id -> true (members of multipolygons)
var _member_refs := {}         # way id -> PackedInt64Array
var _need_nodes := {}          # node id -> true
var _nidx := {}                # node id -> index into _npos
var _npos := PackedVector2Array()
var _member_pts := {}          # way id -> PackedVector2Array (complete geometry of member ways)
var _ways_in := {}             # way id -> true (way touches the map area)


func read(path: String, map_bounds: Rect2) -> bool:
	_path = path
	bounds = map_bounds
	_ext = bounds.grow(MARGIN)
	var sw := Geo.to_latlon(Vector2(_ext.position.x, _ext.end.y))
	var ne := Geo.to_latlon(Vector2(_ext.end.x, _ext.position.y))
	_lat_min = sw.x
	_lon_min = sw.y
	_lat_max = ne.x
	_lon_max = ne.y
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	_size = f.get_length()
	f = null
	var t0 := Time.get_ticks_msec()
	_pass = 0
	if not _scan(1):
		return false
	_note("Auszug Durchlauf 1: %d Flächen-Relationen, %d Buslinien" % [_rels.size(), _bus.size()])
	_pass = 1
	if not _need_ways.is_empty():
		_scan(2)
	_note("Auszug Durchlauf 2: %d Wege für Flächen, %d Knoten" % [_member_refs.size(), _need_nodes.size()])
	_pass = 2
	_scan(3)
	_finish_relations()
	stats["ms"] = Time.get_ticks_msec() - t0
	_note("Auszug gelesen: %d Knoten im Gebiet, %d Wege im Kartenbereich" % [_npos.size(), _ways_in.size()])
	return true


# ------------------------------------------------------------------------------------------
# File / blocks
# ------------------------------------------------------------------------------------------

func _scan(mode: int) -> bool:
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return false
	f.big_endian = true
	var last_report := 0
	while f.get_position() + 4 <= _size:
		var hlen := f.get_32()
		if hlen <= 0 or hlen > 64 * 1024:
			push_warning("pbf: bad header length")
			return false
		var hb := f.get_buffer(hlen)
		var htype := ""
		var dsize := 0
		var p := 0
		while p < hb.size():
			var key := _vi(hb, p)
			p = _np
			var fld := key >> 3
			var wt := key & 7
			if fld == 1 and wt == 2:
				var ln := _vi(hb, p)
				p = _np
				htype = hb.slice(p, p + ln).get_string_from_ascii()
				p += ln
			elif fld == 3 and wt == 0:
				dsize = _vi(hb, p)
				p = _np
			else:
				p = _skip(hb, p, wt)
		var blob := f.get_buffer(dsize)
		if htype != "OSMData":
			continue
		var raw := _unblob(blob)
		if raw.is_empty():
			continue
		_block(raw, mode)
		var pos := f.get_position()
		if pos - last_report > 1_000_000 and progress_cb.is_valid():
			last_report = pos
			var done := 0.0
			for i in _pass:
				done += _pass_w[i]
			done += _pass_w[_pass] * float(pos) / maxf(1.0, _size)
			progress_cb.call(done, ["Flächen und Buslinien", "Flächenränder", "Straßen, Gebäude und Knoten"][_pass])
	return true


func _unblob(b: PackedByteArray) -> PackedByteArray:
	var p := 0
	var raw_size := 0
	var data := PackedByteArray()
	var zipped := false
	while p < b.size():
		var key := _vi(b, p)
		p = _np
		var fld := key >> 3
		var wt := key & 7
		if wt == 2:
			var ln := _vi(b, p)
			p = _np
			if fld == 1:
				data = b.slice(p, p + ln)
			elif fld == 3:
				data = b.slice(p, p + ln)
				zipped = true
			p += ln
		elif fld == 2 and wt == 0:
			raw_size = _vi(b, p)
			p = _np
		else:
			p = _skip(b, p, wt)
	if zipped:
		return data.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	return data


## One PrimitiveBlock.
func _block(b: PackedByteArray, mode: int) -> void:
	var p := 0
	var n := b.size()
	var st := Vector2i(-1, -1)
	var groups: Array = []
	var gran := 100
	var lat_off := 0
	var lon_off := 0
	while p < n:
		var key := _vi(b, p)
		p = _np
		var fld := key >> 3
		var wt := key & 7
		if wt == 2:
			var ln := _vi(b, p)
			p = _np
			if fld == 1:
				st = Vector2i(p, p + ln)
			elif fld == 2:
				groups.append(Vector2i(p, p + ln))
			p += ln
		elif wt == 0:
			var v := _vi(b, p)
			p = _np
			match fld:
				17:
					gran = v
				19:
					lat_off = v
				20:
					lon_off = v
		else:
			p = _skip(b, p, wt)
	var strings: Array = []
	for g in groups:
		var gp: int = g.x
		var gkey := _vi(b, gp)
		var gtype := gkey >> 3   # 1 nodes, 2 dense, 3 ways, 4 relations
		match mode:
			1:
				if gtype == 4:
					if strings.is_empty():
						strings = _strings(b, st)
					_relations(b, g, strings)
			2:
				if gtype == 3:
					_member_ways(b, g)
			3:
				if gtype == 2:
					if strings.is_empty():
						strings = _strings(b, st)
					_dense(b, g, strings, gran, lat_off, lon_off)
				elif gtype == 3:
					if strings.is_empty():
						strings = _strings(b, st)
					_ways(b, g, strings)


func _strings(b: PackedByteArray, r: Vector2i) -> Array:
	var out: Array = []
	if r.x < 0:
		return out
	var p := r.x
	while p < r.y:
		var key := _vi(b, p)
		p = _np
		if (key & 7) == 2:
			var ln := _vi(b, p)
			p = _np
			out.append(b.slice(p, p + ln).get_string_from_utf8())
			p += ln
		else:
			p = _skip(b, p, key & 7)
	return out


# ------------------------------------------------------------------------------------------
# Pass 1: relations
# ------------------------------------------------------------------------------------------

func _relations(b: PackedByteArray, g: Vector2i, strings: Array) -> void:
	var p := g.x
	while p < g.y:
		var key := _vi(b, p)
		p = _np
		if (key >> 3) != 4 or (key & 7) != 2:
			p = _skip(b, p, key & 7)
			continue
		var ln := _vi(b, p)
		p = _np
		var end := p + ln
		var id := 0
		var keys := PackedInt64Array()
		var vals := PackedInt64Array()
		var roles := PackedInt64Array()
		var mems := PackedInt64Array()
		var types := PackedInt64Array()
		var q := p
		while q < end:
			var k2 := _vi(b, q)
			q = _np
			var fld := k2 >> 3
			var wt := k2 & 7
			if fld == 1 and wt == 0:
				id = _vi(b, q)
				q = _np
			elif wt == 2 and fld in [2, 3, 8, 9, 10]:
				var l2 := _vi(b, q)
				q = _np
				var arr := _packed(b, q, q + l2, fld == 9)
				match fld:
					2:
						keys = arr
					3:
						vals = arr
					8:
						roles = arr
					9:
						mems = arr
					10:
						types = arr
				q += l2
			else:
				q = _skip(b, q, wt)
		p = end
		var tags := {}
		for i in keys.size():
			tags[strings[keys[i]]] = strings[vals[i]] if i < vals.size() else ""
		var t: String = tags.get("type", "")
		var is_mp: bool = t == "multipolygon" and _match(tags, REL_KEYS)
		var is_bus: bool = t == "route" and tags.get("route", "") == "bus"
		if not (is_mp or is_bus):
			continue
		var mem: Array = []
		for i in mems.size():
			var ty: int = types[i] if i < types.size() else 0
			mem.append([ty, mems[i], strings[roles[i]] if i < roles.size() else ""])
			if is_mp and ty == 1:
				_need_ways[mems[i]] = true
		if is_mp:
			_rels.append({"id": id, "tags": tags, "mem": mem})
		else:
			_bus.append({"id": id, "tags": tags, "mem": mem})


# ------------------------------------------------------------------------------------------
# Pass 2: node ids of the ways multipolygons need
# ------------------------------------------------------------------------------------------

func _member_ways(b: PackedByteArray, g: Vector2i) -> void:
	var p := g.x
	while p < g.y:
		var key := _vi(b, p)
		p = _np
		if (key >> 3) != 3 or (key & 7) != 2:
			p = _skip(b, p, key & 7)
			continue
		var ln := _vi(b, p)
		p = _np
		var end := p + ln
		var id := -1
		var refs_r := Vector2i(-1, -1)
		var q := p
		while q < end:
			var k2 := _vi(b, q)
			q = _np
			var fld := k2 >> 3
			var wt := k2 & 7
			if fld == 1 and wt == 0:
				id = _vi(b, q)
				q = _np
				if not _need_ways.has(id):
					break
			elif fld == 8 and wt == 2:
				var l2 := _vi(b, q)
				q = _np
				refs_r = Vector2i(q, q + l2)
				q += l2
			else:
				q = _skip(b, q, wt)
		p = end
		if id < 0 or not _need_ways.has(id) or refs_r.x < 0:
			continue
		var refs := _packed(b, refs_r.x, refs_r.y, true)
		_member_refs[id] = refs
		for r in refs:
			_need_nodes[r] = true


# ------------------------------------------------------------------------------------------
# Pass 3: nodes (dense) and ways
# ------------------------------------------------------------------------------------------

func _dense(b: PackedByteArray, g: Vector2i, strings: Array, gran: int, lat_off: int, lon_off: int) -> void:
	# the DenseNodes message is the (only) field 2 of this group
	var p := g.x
	_vi(b, p)   # field key of the DenseNodes message
	p = _np
	var ln := _vi(b, p)
	p = _np
	var end := p + ln
	var r_id := Vector2i(-1, -1)
	var r_lat := Vector2i(-1, -1)
	var r_lon := Vector2i(-1, -1)
	var r_kv := Vector2i(-1, -1)
	while p < end:
		var k2 := _vi(b, p)
		p = _np
		var wt := k2 & 7
		if wt != 2:
			p = _skip(b, p, wt)
			continue
		var l2 := _vi(b, p)
		p = _np
		match k2 >> 3:
			1:
				r_id = Vector2i(p, p + l2)
			8:
				r_lat = Vector2i(p, p + l2)
			9:
				r_lon = Vector2i(p, p + l2)
			10:
				r_kv = Vector2i(p, p + l2)
		p += l2
	if r_id.x < 0 or r_lat.x < 0 or r_lon.x < 0:
		return
	# map area + margin in raw block units
	var g9 := float(gran)
	var la0 := int(floor((_lat_min * 1e9 - lat_off) / g9))
	var la1 := int(ceil((_lat_max * 1e9 - lat_off) / g9))
	var lo0 := int(floor((_lon_min * 1e9 - lon_off) / g9))
	var lo1 := int(ceil((_lon_max * 1e9 - lon_off) / g9))
	var need := _need_nodes
	var nidx := _nidx
	var pi := r_id.x
	var pa := r_lat.x
	var po := r_lon.x
	var pk := r_kv.x
	var kend := r_kv.y
	var id := 0
	var lat := 0
	var lon := 0
	var c := 0
	var v := 0
	var s := 0
	while pi < r_id.y:
		# id (sint64, delta)
		v = 0
		s = 0
		while true:
			c = b[pi]
			pi += 1
			v |= (c & 0x7f) << s
			if c < 128:
				break
			s += 7
		id += (v >> 1) ^ -(v & 1)
		v = 0
		s = 0
		while true:
			c = b[pa]
			pa += 1
			v |= (c & 0x7f) << s
			if c < 128:
				break
			s += 7
		lat += (v >> 1) ^ -(v & 1)
		v = 0
		s = 0
		while true:
			c = b[po]
			po += 1
			v |= (c & 0x7f) << s
			if c < 128:
				break
			s += 7
		lon += (v >> 1) ^ -(v & 1)
		# tags: key/value string ids until 0
		var kv_from := pk
		var has_tags := false
		if pk >= 0 and pk < kend:
			while true:
				var kk := _vi(b, pk)
				pk = _np
				if kk == 0:
					break
				has_tags = true
				_vi(b, pk)
				pk = _np
		var inside := lat >= la0 and lat <= la1 and lon >= lo0 and lon <= lo1
		if not inside and not need.has(id):
			continue
		var lat_d := (lat_off + gran * lat) * 1e-9
		var lon_d := (lon_off + gran * lon) * 1e-9
		var lp := Geo.to_local(lat_d, lon_d)
		nidx[id] = _npos.size()
		_npos.append(lp)
		if has_tags and bounds.has_point(lp):
			var tags := {}
			var q := kv_from
			while true:
				var kk := _vi(b, q)
				q = _np
				if kk == 0:
					break
				var vv := _vi(b, q)
				q = _np
				tags[strings[kk]] = strings[vv]
			if _match(tags, NODE_KEYS):
				parser._node({"id": id, "lat": lat_d, "lon": lon_d, "tags": tags})


func _ways(b: PackedByteArray, g: Vector2i, strings: Array) -> void:
	var nidx := _nidx
	var npos := _npos
	var p := g.x
	while p < g.y:
		var key := _vi(b, p)
		p = _np
		if (key >> 3) != 3 or (key & 7) != 2:
			p = _skip(b, p, key & 7)
			continue
		var ln := _vi(b, p)
		p = _np
		var end := p + ln
		var id := 0
		var keys := PackedInt64Array()
		var vals := PackedInt64Array()
		var refs_r := Vector2i(-1, -1)
		var q := p
		while q < end:
			var k2 := _vi(b, q)
			q = _np
			var fld := k2 >> 3
			var wt := k2 & 7
			if fld == 1 and wt == 0:
				id = _vi(b, q)
				q = _np
			elif wt == 2 and (fld == 2 or fld == 3 or fld == 8):
				var l2 := _vi(b, q)
				q = _np
				if fld == 8:
					refs_r = Vector2i(q, q + l2)
				elif fld == 2:
					keys = _packed(b, q, q + l2, false)
				else:
					vals = _packed(b, q, q + l2, false)
				q += l2
			else:
				q = _skip(b, q, wt)
		p = end
		var member := _need_ways.has(id)
		var tags := {}
		for i in keys.size():
			tags[strings[keys[i]]] = strings[vals[i]] if i < vals.size() else ""
		var wanted := _match(tags, WAY_KEYS)
		if not (wanted or member) or refs_r.x < 0:
			continue
		# geometry from the kept nodes; a way may leave the kept area: then keep the longest run of
		# consecutive kept nodes that reaches into the map (ids and points stay aligned)
		var runs: Array = []
		var ids := PackedInt64Array()
		var pts := PackedVector2Array()
		var run_in := false
		var complete := true
		var ref := 0
		var pr := refs_r.x
		var c := 0
		var v := 0
		var s := 0
		while pr < refs_r.y:
			v = 0
			s = 0
			while true:
				c = b[pr]
				pr += 1
				v |= (c & 0x7f) << s
				if c < 128:
					break
				s += 7
			ref += (v >> 1) ^ -(v & 1)
			var ix: int = nidx.get(ref, -1)
			if ix < 0:
				complete = false
				if pts.size() > 0:
					runs.append([pts, ids, run_in])
				pts = PackedVector2Array()
				ids = PackedInt64Array()
				run_in = false
				continue
			var lp := npos[ix]
			pts.append(lp)
			ids.append(ref)
			if not run_in and bounds.has_point(lp):
				run_in = true
		if not complete:
			if pts.size() > 0:
				runs.append([pts, ids, run_in])
			var best: Array = []
			for r in runs:
				if best.is_empty() or (r[2] and not best[2]) or (r[2] == best[2] and r[0].size() > best[0].size()):
					best = r
			if best.is_empty():
				continue
			pts = best[0]
			ids = best[1]
			run_in = best[2]
		if member and complete:
			_member_pts[id] = pts
		if run_in:
			_ways_in[id] = true
			if wanted and pts.size() >= 2:
				parser._way({"id": id, "nodes": ids, "pts": pts, "tags": tags})


# ------------------------------------------------------------------------------------------
# Relations
# ------------------------------------------------------------------------------------------

func _finish_relations() -> void:
	var n_mp := 0
	for r in _rels:
		var members: Array = []
		var touches := false
		for m in r.mem:
			if m[0] != 1:
				continue
			var pts: PackedVector2Array = _member_pts.get(m[1], PackedVector2Array())
			if pts.size() < 2:
				continue
			if not touches and _ways_in.has(m[1]):
				touches = true
			if not touches:
				# member ways that are not stored as "in the map" may still cross it
				var bb := Rect2(pts[0], Vector2.ZERO)
				for pt in pts:
					bb = bb.expand(pt)
				touches = bb.intersects(bounds)
			members.append({"type": "way", "ref": m[1], "role": m[2], "pts": pts})
		if touches and not members.is_empty():
			parser._relation({"type": "relation", "id": r.id, "tags": r.tags, "members": members})
			n_mp += 1
	var n_bus := 0
	for r in _bus:
		var members: Array = []
		var touches := false
		for m in r.mem:
			if m[0] == 1:
				members.append({"type": "way", "ref": m[1], "role": m[2]})
				if _ways_in.has(m[1]):
					touches = true
		if touches:
			parser._relation({"type": "relation", "id": r.id, "tags": r.tags, "members": members})
			n_bus += 1
	stats["relations"] = n_mp
	stats["bus"] = n_bus


# ------------------------------------------------------------------------------------------
# Protobuf helpers
# ------------------------------------------------------------------------------------------

var _np := 0   # position after the last _vi()


func _vi(b: PackedByteArray, p: int) -> int:
	var v := 0
	var s := 0
	while true:
		var c := b[p]
		p += 1
		v |= (c & 0x7f) << s
		if c < 128:
			break
		s += 7
	_np = p
	return v


func _skip(b: PackedByteArray, p: int, wt: int) -> int:
	match wt:
		0:
			_vi(b, p)
			return _np
		1:
			return p + 8
		2:
			var ln := _vi(b, p)
			return _np + ln
		5:
			return p + 4
	return b.size()   # unknown wire type: give up on this message


## Packed varints; zigzag+delta for sint64 delta-coded fields (way refs, member ids).
func _packed(b: PackedByteArray, p: int, end: int, delta: bool) -> PackedInt64Array:
	var out := PackedInt64Array()
	var acc := 0
	while p < end:
		var v := 0
		var s := 0
		while true:
			var c := b[p]
			p += 1
			v |= (c & 0x7f) << s
			if c < 128:
				break
			s += 7
		if delta:
			acc += (v >> 1) ^ -(v & 1)
			out.append(acc)
		else:
			out.append(v)
	return out


static func _match(tags: Dictionary, spec: Dictionary) -> bool:
	for k in spec:
		if tags.has(k):
			var allowed = spec[k]
			if allowed == null or tags[k] in allowed:
				return true
	return false


func _note(s: String) -> void:
	if note_cb.is_valid():
		note_cb.call(s)
