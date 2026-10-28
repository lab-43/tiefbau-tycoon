class_name RoadNet
extends RefCounted
## Road graph built from OSM: junction nodes, edges with cross sections, junction polygons,
## lane polylines, junction connectors (turn movements) with conflict sets and traffic control.
##
## Conventions: 2D points are Vector2(x, z). Edge direction 0 = a->b, 1 = b->a.
## Lane index 0 = leftmost lane in travel direction. Lane key = edge*16 + dir*8 + lane.
## right_of(d) = Vector2(-d.y, d.x) (visual right when z points south).

const CLASS_RANK := {
	"motorway": 9, "trunk": 8, "primary": 7, "secondary": 6, "tertiary": 5, "busway": 4,
	"unclassified": 3, "residential": 3, "road": 3, "living_street": 2, "service": 1,
	"motorway_link": 8, "trunk_link": 7, "primary_link": 6, "secondary_link": 5, "tertiary_link": 4,
}
const LANE_WIDTH := {
	"motorway": 3.5, "trunk": 3.5, "primary": 3.25, "secondary": 3.1, "tertiary": 3.0, "busway": 3.25,
	"unclassified": 2.9, "residential": 2.85, "road": 2.9, "living_street": 2.75, "service": 2.6,
	"motorway_link": 3.5, "trunk_link": 3.4, "primary_link": 3.25, "secondary_link": 3.1, "tertiary_link": 3.0,
}
const CORNER_RADIUS := {9: 14.0, 8: 12.0, 7: 10.0, 6: 9.0, 5: 8.0, 4: 7.0, 3: 6.0, 2: 5.0, 1: 4.0}
const SHARP_MIN := 0.35       # below this angle (rad) between two roads their curbs meet in a point (a Y)
const CORNER_REACH := 35.0    # curb corners further out than this along a road are not built (near-parallel roads)
const PATH_HALF_W := 1.3      # junction asphalt reaches at least this far to each side of a turn path
const CLOSE_R := 2.0          # junction areas built by union are closed by this radius (no notches, slivers)
const ISLAND_OPEN := 0.75     # islands in a group area narrower than 1.5 m are filled, slivers removed
const MIN_TUNNEL := 25.0      # underground chains shorter than this stay on the surface (an underpass, not two portals)
const DEFAULT_SPEED_KMH := {
	"motorway": 100, "trunk": 70, "primary": 50, "secondary": 50, "tertiary": 50, "busway": 50,
	"unclassified": 50, "residential": 30, "road": 30, "living_street": 10, "service": 20,
	"motorway_link": 60, "trunk_link": 50, "primary_link": 40, "secondary_link": 40, "tertiary_link": 40,
}

var nodes: Array = []        # {pos, ends: Array[int] (edge*2+end), ctrl, osm_id, polygon, phases, under}
var edges: Array = []        # see _make_edge
var connectors: Array = []   # see _build_connectors
var lane_out: Dictionary = {}  # lane key -> Array[int] connector ids leaving the end of that lane
var lane_in: Dictionary = {}   # lane key -> Array[int] connector ids arriving at start of that lane
var lane_geo: Dictionary = {}  # lane key -> [pts: PackedVector2Array, cum: PackedFloat32Array]
var hq_node: int = -1          # node at the HQ gate (end of driveway)
var hq_edge: int = -1
var bounds := Rect2()
var merge_junctions := true    # group the OSM nodes of one real junction (JunctionMerge)
var timings := {}              # ms per build step (loading log)
var group_count := 0           # junctions made of several OSM nodes

var _osm_to_node := {}


# ------------------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------------------

func build(data: OsmData, hq: Dictionary = {}) -> void:
	bounds = data.bounds
	var ways: Array = data.roads
	if not hq.is_empty():
		ways = _inject_driveway(ways, hq)
	# 1) count node usage
	var usage := {}
	for w in ways:
		var ids: PackedInt64Array = w.ids
		for i in ids.size():
			var nid := ids[i]
			var add := 2 if (i == 0 or i == ids.size() - 1) else 1
			usage[nid] = usage.get(nid, 0) + add
	# 2) split ways into raw edges at graph nodes
	var raw: Array = []
	for w in ways:
		var ids: PackedInt64Array = w.ids
		var pts: PackedVector2Array = w.pts
		var start := 0
		for i in range(1, ids.size()):
			if usage.get(ids[i], 0) >= 2 or i == ids.size() - 1:
				if i > start:
					raw.append({"ids": ids.slice(start, i + 1), "pts": pts.slice(start, i + 1), "way": w})
				start = i
	# 3) nodes
	for r in raw:
		for nid in [r.ids[0], r.ids[r.ids.size() - 1]]:
			if not _osm_to_node.has(nid):
				var p: Vector2 = r.pts[0] if nid == r.ids[0] else r.pts[r.pts.size() - 1]
				_osm_to_node[nid] = nodes.size()
				nodes.append({"pos": p, "ends": [], "ctrl": "none", "osm_id": nid, "polygon": PackedVector2Array(), "phases": {}})
	# 4) edges
	for r in raw:
		var a: int = _osm_to_node[r.ids[0]]
		var b: int = _osm_to_node[r.ids[r.ids.size() - 1]]
		if a == b and r.pts.size() < 4:
			continue
		var e := _make_edge(r, a, b, data)
		if e.is_empty():
			continue
		var ei := edges.size()
		edges.append(e)
		nodes[a].ends.append(ei * 2)
		nodes[b].ends.append(ei * 2 + 1)
	_merge_degree2()
	_compact()
	for e in edges:
		e.pts = Geo.chaikin(e.pts, 3, 0.75)
		e.cum = Geo.cumulative(e.pts)
		e.len = e.cum[e.cum.size() - 1]
	_short_tunnels()
	var t := Time.get_ticks_msec()
	if merge_junctions:
		group_count = JunctionMerge.run(self)
		if group_count > 0:
			_compact()
	_mark_under_nodes()
	timings["merge"] = Time.get_ticks_msec() - t
	_smooth_continuations()
	_mark_crossings(data)
	t = Time.get_ticks_msec()
	_junction_geometry()
	timings["geometry"] = Time.get_ticks_msec() - t
	_build_lanes()
	t = Time.get_ticks_msec()
	_build_connectors()
	timings["connectors"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	_finish_groups()
	timings["areas"] = Time.get_ticks_msec() - t
	_traffic_control(data)
	t = Time.get_ticks_msec()
	_conflicts()
	timings["conflicts"] = Time.get_ticks_msec() - t


func _inject_driveway(ways: Array, hq: Dictionary) -> Array:
	# hq: {gate: Vector2, road_way_index: int, seg: int, proj: Vector2}
	var out := ways.duplicate()
	var wi: int = hq.road_way_index
	var w: Dictionary = out[wi].duplicate()
	var ids: PackedInt64Array = w.ids.duplicate()
	var pts: PackedVector2Array = w.pts.duplicate()
	var seg: int = hq.seg
	ids.insert(seg + 1, -900000001)
	pts.insert(seg + 1, hq.proj)
	w.ids = ids
	w.pts = pts
	out[wi] = w
	out.append({"id": -900000000, "part": 0, "ids": PackedInt64Array([-900000001, -900000002]),
		"pts": PackedVector2Array([hq.proj, hq.gate]), "tags": {"highway": "service", "service": "driveway", "name": "Zufahrt Zentrale", "oneway": "no", "sidewalk": "no"}})
	return out


static func parse_width(v: String) -> float:
	if v == "":
		return 0.0
	var s := v.replace(",", ".").replace(" m", "").replace("m", "").strip_edges()
	return s.to_float() if s.is_valid_float() else 0.0


func _make_edge(r: Dictionary, a: int, b: int, data: OsmData) -> Dictionary:
	var tags: Dictionary = r.way.tags
	var cls: String = tags.get("highway", "residential")
	var pts: PackedVector2Array = r.pts
	# remove duplicate consecutive points
	var clean := PackedVector2Array()
	var ids := PackedInt64Array()
	for i in pts.size():
		if clean.is_empty() or pts[i].distance_to(clean[clean.size() - 1]) > 0.05:
			clean.append(pts[i])
			ids.append(r.ids[i])
	if clean.size() < 2:
		return {}
	var oneway_tag: String = tags.get("oneway", "")
	var oneway: bool = oneway_tag in ["yes", "1", "true"] or tags.get("junction", "") in ["roundabout", "circular"] \
		or (cls in ["motorway", "motorway_link"] and oneway_tag != "no")
	if oneway_tag in ["-1", "reverse"]:
		clean.reverse()
		ids.reverse()
		var t := a
		a = b
		b = t
		oneway = true
	var lw: float = LANE_WIDTH.get(cls, 2.9)
	var lanes := int(tags.get("lanes", "0")) if str(tags.get("lanes", "")).is_valid_int() else 0
	var lf := 1
	var lb := 1
	if oneway:
		lf = lanes if lanes > 0 else (2 if cls in ["motorway", "trunk"] else 1)
		lb = 0
	else:
		var tf: String = str(tags.get("lanes:forward", ""))
		var tb: String = str(tags.get("lanes:backward", ""))
		if tf.is_valid_int() and tb.is_valid_int():
			lf = maxi(1, tf.to_int())
			lb = maxi(1, tb.to_int())
		elif lanes >= 2:
			lf = int(ceil(lanes / 2.0))
			lb = maxi(1, lanes - lf)
	lf = clampi(lf, 0, 5)
	lb = clampi(lb, 0, 5)
	var width := parse_width(str(tags.get("width", "")))
	var narrow := false
	if not oneway and lanes == 1:
		narrow = true
	if cls == "service" and not oneway:
		narrow = true
	var lanes_total := lf + lb
	var lane_block := lanes_total * lw
	if narrow:
		lane_block = maxf(3.2, minf(width if width > 0.0 else 4.0, 5.0))
		lw = lane_block / 2.0
	# parking + cycle lanes
	var park_l := 0.0
	var park_r := 0.0
	for side in ["left", "right", "both"]:
		var pv := str(tags.get("parking:lane:" + side, tags.get("parking:" + side, "")))
		if pv in ["parallel", "lane", "street_side", "diagonal", "perpendicular", "marked", "yes"]:
			var pw := 2.0 if pv in ["parallel", "lane", "street_side", "marked", "yes"] else 4.5
			if side in ["left", "both"]:
				park_l = pw
			if side in ["right", "both"]:
				park_r = pw
	var cyc_l := 0.0
	var cyc_r := 0.0
	var cy := str(tags.get("cycleway", ""))
	var cyb := str(tags.get("cycleway:both", ""))
	if cy == "lane" or cyb == "lane":
		cyc_l = 1.5
		cyc_r = 1.5
	if str(tags.get("cycleway:left", "")) == "lane":
		cyc_l = 1.5
	if str(tags.get("cycleway:right", "")) == "lane":
		cyc_r = 1.5
	if oneway and cy == "lane" and cyb == "":
		cyc_l = 0.0
	var carriage := lane_block + park_l + park_r + cyc_l + cyc_r
	if width > 0.0 and width > carriage * 0.7 and width < carriage * 2.0 and not narrow:
		# scale lane width to match tagged width
		var extra := width - (park_l + park_r + cyc_l + cyc_r)
		if extra > 2.5 and lanes_total > 0:
			lw = clampf(extra / lanes_total, 2.5, 3.75)
			lane_block = lw * lanes_total
			carriage = lane_block + park_l + park_r + cyc_l + cyc_r
	# sidewalks (relative to a->b)
	var sw_default := 0.0
	if cls in ["primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "road",
			"primary_link", "secondary_link", "tertiary_link"]:
		sw_default = 2.2
	var sw_l := sw_default
	var sw_r := sw_default
	var swt := str(tags.get("sidewalk", ""))
	match swt:
		"both", "yes":
			sw_l = 2.2
			sw_r = 2.2
		"left":
			sw_l = 2.2
			sw_r = 0.0
		"right":
			sw_l = 0.0
			sw_r = 2.2
		"no", "none", "separate":
			sw_l = 0.0
			sw_r = 0.0
	for side in ["left", "right", "both"]:
		var sv := str(tags.get("sidewalk:" + side, ""))
		if sv in ["no", "separate", "none"]:
			if side in ["left", "both"]:
				sw_l = 0.0
			if side in ["right", "both"]:
				sw_r = 0.0
		elif sv == "yes":
			if side in ["left", "both"]:
				sw_l = 2.2
			if side in ["right", "both"]:
				sw_r = 2.2
	if oneway_tag in ["-1", "reverse"]:
		var t2 := sw_l
		sw_l = sw_r
		sw_r = t2
		var t3 := park_l
		park_l = park_r
		park_r = t3
		var t4 := cyc_l
		cyc_l = cyc_r
		cyc_r = t4
	var ms := str(tags.get("maxspeed", ""))
	var kmh: float = DEFAULT_SPEED_KMH.get(cls, 30)
	if ms.is_valid_int():
		kmh = ms.to_float()
	elif ms.ends_with("mph") and ms.split(" ")[0].is_valid_int():
		kmh = ms.split(" ")[0].to_float() * 1.609
	elif ms == "walk":
		kmh = 7.0
	elif ms.begins_with("DE:urban"):
		kmh = 50.0
	if tags.get("zone:maxspeed", "") == "DE:30" or tags.get("maxspeed:type", "") == "DE:zone30":
		kmh = 30.0
	var layer := int(tags.get("layer", "0")) if str(tags.get("layer", "0")).is_valid_int() else 0
	return {
		"a": a, "b": b, "pts": clean, "ids": ids, "cum": PackedFloat32Array(), "len": 0.0,
		"cls": cls, "rank": CLASS_RANK.get(cls, 3) + (20 if tags.get("junction", "") in ["roundabout", "circular"] else 0),
		"name": str(tags.get("name", tags.get("ref", ""))), "way": int(r.way.id),
		"oneway": oneway, "lf": lf, "lb": lb, "lw": lw, "narrow": narrow,
		"park_l": park_l, "park_r": park_r, "cyc_l": cyc_l, "cyc_r": cyc_r,
		"width": carriage, "sw_l": sw_l, "sw_r": sw_r,
		"speed": kmh / 3.6, "bridge": tags.get("bridge", "") in ["yes", "viaduct"], "layer": layer,
		"tunnel": tags.get("tunnel", "") == "yes", "under": is_under(tags),
		"bus": data.bus_way_ids.has(int(r.way.id)) or cls == "busway",
		"turn_f": str(tags.get("turn:lanes", tags.get("turn:lanes:forward", ""))) if true else "",
		"turn_b": str(tags.get("turn:lanes:backward", "")),
		"trim_a": 0.0, "trim_b": 0.0, "crossings": [], "signal_a": false, "signal_b": false,
		"giveway_a": false, "giveway_b": false, "stop_a": false, "stop_b": false, "sig": "",
	}


## Roads below the surface (#31): tunnels, indoor ways, and garage aisles or covered driveways below ground
## level. They get no surface mesh (the underground view draws them) and vehicles in them are hidden.
## Building passages and covered roads at ground level stay on the surface: the building hides them.
## Underpasses without a tunnel tag (layer < 0 on a street) are open to the sky and stay as well.
static func is_under(tags: Dictionary) -> bool:
	if str(tags.get("tunnel", "")) == "yes" or str(tags.get("indoor", "")) == "yes":
		return true
	var ls := str(tags.get("layer", "0"))
	if not ls.is_valid_int() or ls.to_int() >= 0 or str(tags.get("highway", "")) != "service":
		return false
	var lv := str(tags.get("level", "0")).split(";")[0]
	return str(tags.get("covered", "")) == "yes" or str(tags.get("service", "")) == "parking_aisle" \
		or (lv.is_valid_float() and lv.to_float() < 0.0)


## Underground chains (edges joined at nodes where only underground edges meet) shorter than MIN_TUNNEL go
## back to the surface: two portals and a hidden car for a few metres look worse than an underpass.
func _short_tunnels() -> void:
	var seen := {}
	for ei in edges.size():
		if not edges[ei].under or seen.has(ei):
			continue
		var chain := [ei]
		seen[ei] = true
		var total := 0.0
		var i := 0
		while i < chain.size():
			var e: Dictionary = edges[chain[i]]
			total += float(e.len)
			for ni in [e.a, e.b]:
				if not _all_under(ni):
					continue
				for end in nodes[ni].ends:
					var oj: int = end >> 1
					if not seen.has(oj):
						seen[oj] = true
						chain.append(oj)
			i += 1
		if total < MIN_TUNNEL:
			for ej in chain:
				edges[ej].under = false


func _all_under(ni: int) -> bool:
	var ends: Array = nodes[ni].ends
	if ends.is_empty():
		return false
	for end in ends:
		if not edges[end >> 1].under:
			return false
	return true


## Junctions where only underground roads meet are underground themselves (no surface area, hidden traffic).
func _mark_under_nodes() -> void:
	for ni in nodes.size():
		nodes[ni]["under"] = _all_under(ni)


## True if lane `key` belongs to a road below the surface.
func lane_under(key: int) -> bool:
	return edges[key >> 4].get("under", false)


func _signature(e: Dictionary) -> String:
	return "%s|%s|%d|%d|%.2f|%.1f|%.1f|%.1f|%.1f|%s|%d|%s|%s|%s" % [e.cls, e.oneway, e.lf, e.lb, e.lw, e.sw_l, e.sw_r,
		e.park_l + e.cyc_l, e.park_r + e.cyc_r, e.bridge, e.layer, e.bus, e.turn_f + e.turn_b, e.under]


## Merge chains through nodes of degree 2 when both edges have the same cross section.
func _merge_degree2() -> void:
	var removed := {}
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		if n.ends.size() != 2:
			continue
		var e1i: int = n.ends[0] >> 1
		var e2i: int = n.ends[1] >> 1
		if e1i == e2i or removed.has(e1i) or removed.has(e2i):
			continue
		var e1: Dictionary = edges[e1i]
		var e2: Dictionary = edges[e2i]
		# orient: e1 must end at ni, e2 must start at ni
		var e1_ends_here: bool = (n.ends[0] & 1) == 1
		var e2_starts_here: bool = (n.ends[1] & 1) == 0
		if e1.oneway or e2.oneway:
			# oneway edges keep their direction; require e1 -> ni -> e2 or e2 -> ni -> e1
			if e1_ends_here and e2_starts_here:
				pass
			elif (not e1_ends_here) and (not e2_starts_here):
				var t := e1i
				e1i = e2i
				e2i = t
				e1 = edges[e1i]
				e2 = edges[e2i]
			else:
				continue
			if not (e1.oneway and e2.oneway):
				continue
		else:
			if not e1_ends_here:
				_reverse_edge(e1i)
			if not e2_starts_here:
				_reverse_edge(e2i)
		if _signature(e1) != _signature(e2):
			continue
		if e1.name != e2.name and e1.name != "" and e2.name != "":
			continue
		# merge e2 into e1
		var pts: PackedVector2Array = e1.pts.duplicate()
		pts.append_array(e2.pts.slice(1))
		var ids: PackedInt64Array = e1.ids.duplicate()
		ids.append_array(e2.ids.slice(1))
		e1.pts = pts
		e1.ids = ids
		var old_b: int = e1.b
		e1.b = e2.b
		# rewire node e2.b end -> e1 end
		var nb: Dictionary = nodes[e2.b]
		for k in nb.ends.size():
			if nb.ends[k] == e2i * 2 + 1:
				nb.ends[k] = e1i * 2 + 1
		n.ends = []
		removed[e2i] = true
		e2["dead"] = true
		if old_b != ni:
			push_warning("merge orientation mismatch")


func _reverse_edge(ei: int) -> void:
	var e: Dictionary = edges[ei]
	# flip end bits in the node references of both endpoints
	for ni in [e.a, e.b]:
		var ends: Array = nodes[ni].ends
		for k in ends.size():
			if (ends[k] >> 1) == ei:
				ends[k] = ends[k] ^ 1
	var pts: PackedVector2Array = e.pts.duplicate()
	pts.reverse()
	var ids: PackedInt64Array = e.ids.duplicate()
	ids.reverse()
	e.pts = pts
	e.ids = ids
	var t: int = e.a
	e.a = e.b
	e.b = t
	var t2: float = e.sw_l
	e.sw_l = e.sw_r
	e.sw_r = t2
	var t3: float = e.park_l
	e.park_l = e.park_r
	e.park_r = t3
	var t4: float = e.cyc_l
	e.cyc_l = e.cyc_r
	e.cyc_r = t4
	var t5: int = e.lf
	e.lf = e.lb
	e.lb = t5
	var t6: String = e.turn_f
	e.turn_f = e.turn_b
	e.turn_b = t6


## Remove dead edges and unused nodes, re-index everything.
func _compact() -> void:
	var new_index := {}
	var ne: Array = []
	for i in edges.size():
		if edges[i].get("dead", false):
			continue
		new_index[i] = ne.size()
		ne.append(edges[i])
	edges = ne
	var node_index := {}
	var nn: Array = []
	for i in nodes.size():
		nodes[i].ends = []
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		for k in 2:
			var ni: int = e.a if k == 0 else e.b
			if not node_index.has(ni):
				node_index[ni] = nn.size()
				nn.append(nodes[ni])
			if k == 0:
				e.a = node_index[ni]
			else:
				e.b = node_index[ni]
	nodes = nn
	for ei in edges.size():
		nodes[edges[ei].a].ends.append(ei * 2)
		nodes[edges[ei].b].ends.append(ei * 2 + 1)
	_osm_to_node.clear()
	for i in nodes.size():
		_osm_to_node[nodes[i].osm_id] = i
		if nodes[i].has("group"):
			for id in nodes[i].osm_ids:
				_osm_to_node[id] = i
			continue
		var e0: Dictionary = edges[nodes[i].ends[0] >> 1]
		nodes[i].pos = e0.pts[0] if (nodes[i].ends[0] & 1) == 0 else e0.pts[e0.pts.size() - 1]


func _mark_crossings(data: OsmData) -> void:
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var ids: PackedInt64Array = e.ids
		# ids correspond to the original (unsmoothed) points; use positions from data dicts
		for k in ids.size():
			var nid := ids[k]
			if data.crossings.has(nid):
				var c: Dictionary = data.crossings[nid]
				var res := Geo.closest_on_polyline(e.pts, e.cum, c.pos)
				e.crossings.append({"s": res[1], "kind": c.kind})
			if data.signals.has(nid):
				var res2 := Geo.closest_on_polyline(e.pts, e.cum, data.signals[nid])
				if res2[1] < 40.0:
					e.signal_a = true
				if e.len - res2[1] < 40.0:
					e.signal_b = true
			if data.give_way.has(nid):
				var res3 := Geo.closest_on_polyline(e.pts, e.cum, data.give_way[nid])
				var stop: bool = data.stops.has(nid)
				if res3[1] < 25.0:
					e.giveway_a = true
					e.stop_a = e.stop_a or stop
				if e.len - res3[1] < 25.0:
					e.giveway_b = true
					e.stop_b = e.stop_b or stop
	# crossings on the pieces removed inside merged junction groups: drawn on the junction area
	for n in nodes:
		if not n.has("inner_lines"):
			continue
		var cr: Array = []
		for ln in n.inner_lines:
			var pts: PackedVector2Array = ln.pts
			var cum := Geo.cumulative(pts)
			for nid in ln.ids:
				if data.crossings.has(nid):
					var c: Dictionary = data.crossings[nid]
					var res := Geo.closest_on_polyline(pts, cum, c.pos)
					var smp := Geo.sample(pts, cum, res[1])
					cr.append({"p": smp[0], "d": smp[1], "hw": ln.hw, "kind": c.kind})
		n.erase("inner_lines")
		if not cr.is_empty():
			n["crossings"] = _dedupe_crossings(n, cr)


## A crossing node shared by two removed pieces came twice, with two directions, and was drawn as
## an X. Keep one per place: the one along the road whose end at the group lies nearest (the road
## the pedestrians cross there).
func _dedupe_crossings(n: Dictionary, cr: Array) -> Array:
	var out: Array = []
	for c in cr:
		var dup := -1
		for i in out.size():
			if (out[i].p as Vector2).distance_to(c.p) < 1.5:
				dup = i
		if dup < 0:
			out.append(c)
			continue
		var ref_d := _nearest_end_dir(n, c.p)
		if absf((c.d as Vector2).dot(ref_d)) > absf((out[dup].d as Vector2).dot(ref_d)):
			out[dup] = c
	return out


func _nearest_end_dir(n: Dictionary, p: Vector2) -> Vector2:
	var best := INF
	var d := Vector2.ZERO
	for er in n.ends:
		var e: Dictionary = edges[er >> 1]
		var pts: PackedVector2Array = e.pts
		if pts.size() < 2:
			continue
		var start: bool = (er & 1) == 0
		var q: Vector2 = pts[0] if start else pts[pts.size() - 1]
		var q2: Vector2 = pts[1] if start else pts[pts.size() - 2]
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			d = (q2 - q).normalized()
	return d


# ------------------------------------------------------------------------------------------
# Junction geometry
# ------------------------------------------------------------------------------------------

## Info about an edge end as seen from its node: direction leaving the node, half width, trims.
func end_info(end_ref: int) -> Dictionary:
	var e: Dictionary = edges[end_ref >> 1]
	var at_start := (end_ref & 1) == 0
	var probe := minf(6.0, e.len * 0.3)
	var d: Vector2
	if at_start:
		d = (Geo.sample(e.pts, e.cum, probe)[0] - e.pts[0]).normalized()
	else:
		d = (Geo.sample(e.pts, e.cum, e.len - probe)[0] - e.pts[e.pts.size() - 1]).normalized()
	# sidewalk widths relative to the direction leaving the node
	var sw_right: float = e.sw_r if at_start else e.sw_l
	var sw_left: float = e.sw_l if at_start else e.sw_r
	return {"d": d, "hw": e.width * 0.5, "sw_right": sw_right, "sw_left": sw_left, "edge": end_ref >> 1, "start": at_start,
		"rank": e.rank, "len": e.len}


## Road ends of node ni sorted around it, each with the setback it needs so that the curb corners to
## both neighbours fit (not yet clamped to the road length), and the corner points. In a merged
## junction group the ends start at different points (inf.p); otherwise all start at the node.
func star(ni: int) -> Dictionary:
	var n: Dictionary = nodes[ni]
	var k: int = n.ends.size()
	var J: Vector2 = n.pos
	var infos: Array = []
	for er in n.ends:
		var inf := end_info(er)
		var e: Dictionary = edges[er >> 1]
		var p: Vector2 = e.pts[0] if inf.start else e.pts[e.pts.size() - 1]
		var q: Vector2 = p + inf.d * 8.0 - J
		inf["ref"] = er
		inf["p"] = p
		inf["ang"] = atan2(q.y, q.x)
		inf["s"] = 0.6
		infos.append(inf)
	infos.sort_custom(func(x, y): return x.ang < y.ang)
	var corners: Array = []
	for i in k:
		var A: Dictionary = infos[i]
		var B: Dictionary = infos[(i + 1) % k]
		var alpha: float = fposmod(atan2(B.d.y, B.d.x) - atan2(A.d.y, A.d.x), TAU)
		if k == 1:
			alpha = TAU
		var nA := Geo.right_of(A.d)   # +90deg in angle sense, faces B
		var nB := Geo.right_of(B.d)
		var corner := {"conv": false, "c": Vector2.ZERO}
		if alpha < PI - 0.15:
			# line A: A.p + nA*hwA + dA*t1 ; line B: B.p - nB*hwB + dB*t2
			var p1: Vector2 = A.p + nA * A.hw
			var p2: Vector2 = B.p - nB * B.hw
			var res = Geometry2D.line_intersects_line(p1, A.d, p2, B.d)
			if res != null:
				var C: Vector2 = res
				var t1: float = (C - p1).dot(A.d)
				var t2: float = (C - p2).dot(B.d)
				if t1 < CORNER_REACH and t2 < CORNER_REACH:
					if alpha < SHARP_MIN:
						# a Y: the curbs meet in a point, cut both roads there without a rounded corner
						A.s = maxf(A.s, t1)
						B.s = maxf(B.s, t2)
					else:
						var r: float = CORNER_RADIUS.get(mini(A.rank, B.rank) % 20, 6.0)
						var tang: float = minf(r / maxf(0.05, tan(alpha * 0.5)), 22.0)
						A.s = maxf(A.s, t1 + tang)
						B.s = maxf(B.s, t2 + tang)
						corner = {"conv": true, "c": C}
		corners.append(corner)
	return {"infos": infos, "corners": corners}


func _junction_geometry() -> void:
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		var k: int = n.ends.size()
		if k < 2:
			continue
		if n.get("cont", false):
			_continuation_geometry(n)
			continue
		var st := star(ni)
		var infos: Array = st.infos
		var corners: Array = st.corners
		if n.has("group"):
			_clear_inner_pieces(n, infos)
			_pass_through_cuts(infos)
		# clamp setbacks
		for inf in infos:
			var e: Dictionary = edges[inf.edge]
			var lim: float = e.len * 0.45
			inf.s = clampf(inf.s, 0.0, maxf(0.0, lim))
			if inf.start:
				e.trim_a = inf.s
			else:
				e.trim_b = inf.s
			# the cut as the road mesh has it: point and direction on the real centre line, so that
			# the junction area meets the road surface exactly (no step on curved roads)
			var smp := Geo.sample(e.pts, e.cum, inf.s if inf.start else e.len - inf.s)
			inf["q"] = smp[0]
			inf["qd"] = smp[1] if inf.start else -(smp[1] as Vector2)
		# polygon
		var poly := PackedVector2Array()
		var corner_curves: Array = []
		var wedges: Array = []
		for i in k:
			var A: Dictionary = infos[i]
			var B: Dictionary = infos[(i + 1) % k]
			var nA := Geo.right_of(A.d)
			var nB := Geo.right_of(B.d)
			var a_left: Vector2 = A.q - Geo.right_of(A.qd) * A.hw
			var a_right: Vector2 = A.q + Geo.right_of(A.qd) * A.hw
			var b_left: Vector2 = B.q - Geo.right_of(B.qd) * B.hw
			poly.append(a_left)
			poly.append(a_right)
			var curve := PackedVector2Array([a_right])
			if corners[i].conv:
				var C: Vector2 = corners[i].c
				for t_i in range(1, 8):
					var t := t_i / 8.0
					var q := a_right * (1 - t) * (1 - t) + C * 2.0 * (1 - t) * t + b_left * t * t
					poly.append(q)
					curve.append(q)
			else:
				var outer_c = _outer_corner(A, B, nA, nB)
				if outer_c != null:
					poly.append(outer_c)
					curve.append(outer_c)
			curve.append(b_left)
			var sw := minf(A.sw_right, B.sw_left)
			corner_curves.append({"pts": curve, "sw": sw, "conv": corners[i].conv})
			if n.has("group"):
				var w := PackedVector2Array([A.p + nA * A.hw])
				w.append_array(curve)
				w.append(B.p - nB * B.hw)
				w.append(n.pos)
				wedges.append(w)
		n.corners = corner_curves
		n.infos = infos
		n.polygon = poly
		if n.has("group"):
			n["_pieces"] = _group_pieces(n, poly, infos, wedges)


## A member of a merged group where one road simply continues as another (e.g. 2 lanes become 3):
## the lanes shift sideways there. With the minimal cut the straight path had a metre of offset over
## a metre of length and the cars jerked (#5, Billhorner Brückenstraße). Cut back like a transition
## (`_continuation_geometry`) so that the shift spreads over several metres.
func _pass_through_cuts(infos: Array) -> void:
	var by_member := {}
	for inf in infos:
		var m := _member_of(inf.ref)
		if m >= 0:
			if not by_member.has(m):
				by_member[m] = []
			by_member[m].append(inf)
	for m in by_member:
		var pair: Array = by_member[m]
		if pair.size() != 2 or (pair[0].d as Vector2).dot(pair[1].d) > -0.9:
			continue
		var shift := _lane_shift(pair[0].ref, pair[1].ref)
		if shift < 0.3:
			continue
		var cut := minf(4.0 * shift + 1.0, 12.0)
		for inf in pair:
			inf.s = maxf(inf.s, cut)
		pair[0]["pass"] = pair[1].ref
		pair[1]["pass"] = pair[0].ref


## In a merged group a removed inner piece can cross an approach right at its end (a side road that
## crossed the sidewalk of a main road). Cut such an approach until its carriageway is clear of every
## inner piece running across it, so that its sidewalk does not lie on the side road.
func _clear_inner_pieces(n: Dictionary, infos: Array) -> void:
	var polys: Array = n.get("inner_polys", [])
	var dirs: Array = n.get("inner_dirs", [])
	if polys.is_empty():
		return
	for inf in infos:
		var e: Dictionary = edges[inf.edge]
		var across: Array = []
		for i in polys.size():
			if i < dirs.size() and absf((dirs[i] as Vector2).dot(inf.d)) > 0.9:
				continue   # runs along this road (e.g. its own continuation), not across
			across.append(polys[i])
		if across.is_empty():
			continue
		var s: float = inf.s
		var s_max: float = minf(e.len * 0.45, inf.s + 25.0)
		while s <= s_max:
			var smp := Geo.sample(e.pts, e.cum, s if inf.start else e.len - s)
			var r := Geo.right_of(smp[1])
			var hw: float = e.width * 0.5 - 0.2
			var seg := PackedVector2Array([smp[0] - r * hw, smp[0] + r * hw])
			var hit := false
			for poly in across:
				if not Geometry2D.intersect_polyline_with_polygon(seg, poly).is_empty():
					hit = true
					break
			if not hit:
				inf.s = s
				break
			s += 0.5


## A node with only two roads is no junction: the road just changes its cross section (lanes,
## sidewalks, name) or is split there. Its corner is rounded off here (quadratic curve through the
## node), and _continuation_geometry builds a smooth transition instead of a junction area.
func _smooth_continuations() -> void:
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		if n.ends.size() != 2 or n.has("group"):
			continue
		var ra: int = n.ends[0]
		var rb: int = n.ends[1]
		if (ra >> 1) == (rb >> 1):
			continue
		var pa := _pts_from_node(ra)
		var pb := _pts_from_node(rb)
		var cuma := Geo.cumulative(pa)
		var cumb := Geo.cumulative(pb)
		var la: float = cuma[cuma.size() - 1]
		var lb: float = cumb[cumb.size() - 1]
		if la < 0.5 or lb < 0.5:
			continue
		var da: Vector2 = (Geo.sample(pa, cuma, minf(6.0, la * 0.3))[0] - pa[0]).normalized()
		var db: Vector2 = (Geo.sample(pb, cumb, minf(6.0, lb * 0.3))[0] - pb[0]).normalized()
		var turn := absf((-da).angle_to(db))   # 0 = straight on
		if turn > deg_to_rad(100.0):
			continue   # hairpin: keep the plain junction corner
		n["cont"] = true
		if turn < deg_to_rad(3.0):
			continue
		var c: float = minf(minf(la, lb) * 0.3, clampf(turn * 12.0, 2.0, 10.0))
		var qa: Vector2 = Geo.sample(pa, cuma, c)[0]
		var qb: Vector2 = Geo.sample(pb, cumb, c)[0]
		var J: Vector2 = pa[0]
		var curve := PackedVector2Array()
		for i in 9:
			var t := i / 8.0
			curve.append(qa * (1.0 - t) * (1.0 - t) + J * 2.0 * (1.0 - t) * t + qb * t * t)
		var new_a := PackedVector2Array([curve[4], curve[3], curve[2], curve[1]])
		new_a.append_array(Geo.sub_polyline(pa, cuma, c, la))
		var new_b := PackedVector2Array([curve[4], curve[5], curve[6], curve[7]])
		new_b.append_array(Geo.sub_polyline(pb, cumb, c, lb))
		_set_pts_from_node(ra, new_a)
		_set_pts_from_node(rb, new_b)
		n.pos = curve[4]


## Centre line of the road at end `er`, starting at its node.
func _pts_from_node(er: int) -> PackedVector2Array:
	var e: Dictionary = edges[er >> 1]
	var pts: PackedVector2Array = e.pts.duplicate()
	if (er & 1) == 1:
		pts.reverse()
	return pts


func _set_pts_from_node(er: int, pts: PackedVector2Array) -> void:
	var e: Dictionary = edges[er >> 1]
	var p := pts.duplicate()
	if (er & 1) == 1:
		p.reverse()
	e.pts = p
	e.cum = Geo.cumulative(p)
	e.len = e.cum[e.cum.size() - 1]


## Transition at a node with two roads: both are cut back a little (more if the width changes, so
## that it changes gradually: 2.5 m per metre of width; 4 m per metre that lanes shift sideways; at
## most 20 m each), and the piece between
## them follows the joint centre line with width and sidewalks running from one road's to the other's.
func _continuation_geometry(n: Dictionary) -> void:
	var ra: int = n.ends[0]
	var rb: int = n.ends[1]
	var A: Dictionary = edges[ra >> 1]
	var B: Dictionary = edges[rb >> 1]
	var a_start := (ra & 1) == 0
	var b_start := (rb & 1) == 0
	# long enough for the width change and for lanes that continue a bit to the side (S curve at most 1:8)
	var cut := clampf(maxf(2.5 * absf(A.width - B.width) + 1.5, 4.0 * _lane_shift(ra, rb) + 1.0), 1.5, 20.0)
	var sa: float = minf(cut, A.len * 0.45)
	var sb: float = minf(cut, B.len * 0.45)
	if a_start:
		A.trim_a = sa
	else:
		A.trim_b = sa
	if b_start:
		B.trim_a = sb
	else:
		B.trim_b = sb
	# joint centre line from the cut on A through the node to the cut on B
	var pa := _pts_from_node(ra)
	var pb := _pts_from_node(rb)
	var P := Geo.sub_polyline(pa, Geo.cumulative(pa), 0.0, sa)
	P.reverse()
	var tail := Geo.sub_polyline(pb, Geo.cumulative(pb), 0.0, sb)
	for i in range(1, tail.size()):
		P.append(tail[i])
	P = Geo.densify(P, 1.0)
	var cum := Geo.cumulative(P)
	var L: float = cum[cum.size() - 1]
	# P runs from A towards B: A's right side is P's right side if the node is A's b end
	var a_r: float = A.sw_r if not a_start else A.sw_l
	var a_l: float = A.sw_l if not a_start else A.sw_r
	var b_r: float = B.sw_r if b_start else B.sw_l
	var b_l: float = B.sw_l if b_start else B.sw_r
	var hw := PackedFloat32Array()
	var out_r := PackedFloat32Array()
	var out_l := PackedFloat32Array()
	for i in P.size():
		var f := smoothstep(0.0, maxf(L, 0.01), cum[i])
		var h: float = lerpf(A.width, B.width, f) * 0.5
		hw.append(h)
		out_r.append(h + lerpf(a_r, b_r, f))
		out_l.append(-(h + lerpf(a_l, b_l, f)))
	var neg := PackedFloat32Array()
	for h in hw:
		neg.append(-h)
	var right := Geo.offset_polyline_var(P, hw)
	var left := Geo.offset_polyline_var(P, neg)
	var poly := left.duplicate()
	var rr := right.duplicate()
	rr.reverse()
	poly.append_array(rr)
	n.polygon = poly
	n.corners = []
	n.infos = []
	var sws: Array = []
	if a_r > 0.0 or b_r > 0.0:
		sws.append([right, Geo.offset_polyline_var(P, out_r), P, true])
	if a_l > 0.0 or b_l > 0.0:
		sws.append([left, Geo.offset_polyline_var(P, out_l), P, false])
	n["cont_sw"] = sws


## Largest sideways step a car makes going straight through a node with two roads (ends ra, rb), in
## both directions, each lane to the nearest lane on the other side (as _nearest_out_lane will map it).
func _lane_shift(ra: int, rb: int) -> float:
	var worst := 0.0
	for pair in [[ra, rb], [rb, ra]]:
		var ei: int = pair[0] >> 1
		var eo: int = pair[1] >> 1
		var dir_in := 0 if (pair[0] & 1) == 1 else 1     # travelling towards the node
		var dir_out := 0 if (pair[1] & 1) == 0 else 1    # travelling away from it
		var xs_out: Array = []
		for lo in lane_count(eo, dir_out):
			var x: float = lane_offset_fwd_frame(edges[eo], dir_out, lo)
			xs_out.append(x if dir_out == 0 else -x)
		if xs_out.is_empty():
			continue
		for li in lane_count(ei, dir_in):
			var xi: float = lane_offset_fwd_frame(edges[ei], dir_in, li)
			if dir_in == 1:
				xi = -xi
			var best := INF
			for xo in xs_out:
				best = minf(best, absf(xo - xi))
			worst = maxf(worst, best)
	return worst


## On the outer side of a bend (more than 180° between two neighbouring roads) the two curbs meet in
## a point behind the cuts. A straight line between the cuts would cut into the carriageway, so the
## polygon and the corner sidewalk go through that point. Returns null if there is no such point.
func _outer_corner(A: Dictionary, B: Dictionary, nA: Vector2, nB: Vector2):
	var alpha: float = fposmod(atan2(B.d.y, B.d.x) - atan2(A.d.y, A.d.x), TAU)
	if alpha < PI + 0.05:
		return null
	var p1: Vector2 = A.p + nA * A.hw
	var p2: Vector2 = B.p - nB * B.hw
	var res = Geometry2D.line_intersects_line(p1, A.d, p2, B.d)
	if res == null:
		return null
	var C: Vector2 = res
	var t1: float = (C - p1).dot(A.d)
	var t2: float = (C - p2).dot(B.d)
	if t1 > A.s or t2 > B.s or t1 < -CORNER_REACH or t2 < -CORNER_REACH:
		return null
	return C


## Pieces of the area of a merged junction group: the plain star polygon (if simple), the corner
## wedges, the removed inner road pieces and each road from its end at the group up to its cut.
func _group_pieces(n: Dictionary, star_poly: PackedVector2Array, infos: Array, wedges: Array) -> Array:
	var pieces: Array = []
	if not JunctionMerge.self_intersects(star_poly):
		pieces.append(star_poly)
	for w in wedges:
		if not JunctionMerge.self_intersects(w):
			pieces.append(w)
	for ip in n.get("inner_polys", []):
		pieces.append(ip)
	n["inner_roads"] = n.get("inner_polys", [])   # road surfaces of the removed pieces (RoadMarkings.sperrflaechen)
	n.erase("inner_polys")
	n.erase("inner_dirs")
	var by_ref := {}
	for inf in infos:
		by_ref[inf.ref] = inf
	for inf in infos:
		if inf.has("pass"):
			if inf.ref < inf.pass and by_ref.has(inf.pass):
				pieces.append(_taper_piece(inf, by_ref[inf.pass]))
			continue
		var e: Dictionary = edges[inf.edge]
		var cut: float = minf(e.len, inf.s + 0.3)
		var sub := Geo.sub_polyline(e.pts, e.cum, 0.0, cut) if inf.start else Geo.sub_polyline(e.pts, e.cum, e.len - cut, e.len)
		if sub.size() < 2:
			continue
		var hw: float = e.width * 0.5
		var left := Geo.offset_polyline(sub, -hw)
		var right := Geo.offset_polyline(sub, hw)
		right.reverse()
		left.append_array(right)
		pieces.append(left)
	return pieces


## Carriageway between the cuts of a pass-through member (`_pass_through_cuts`): one strip along both
## centre lines whose width runs smoothly from the one road to the other, instead of two rectangles
## that meet with a step.
func _taper_piece(A: Dictionary, B: Dictionary) -> PackedVector2Array:
	var line := PackedVector2Array()
	for k in 2:
		var inf: Dictionary = A if k == 0 else B
		var e: Dictionary = edges[inf.edge]
		var cut: float = minf(e.len, inf.s + 0.3)
		var sub := Geo.sub_polyline(e.pts, e.cum, 0.0, cut) if inf.start else Geo.sub_polyline(e.pts, e.cum, e.len - cut, e.len)
		# A runs towards the member, B away from it
		if (k == 0) == inf.start:
			sub.reverse()
		if k == 1 and not line.is_empty() and sub.size() > 0 and sub[0].distance_to(line[line.size() - 1]) < 0.01:
			sub.remove_at(0)
		line.append_array(sub)
	if line.size() < 2:
		return PackedVector2Array()
	var cum := Geo.cumulative(line)
	var total: float = maxf(0.01, cum[cum.size() - 1])
	var wa: float = edges[A.edge].width * 0.5
	var wb: float = edges[B.edge].width * 0.5
	var offs := PackedFloat32Array()
	for c in cum:
		var t: float = c / total
		offs.append(lerpf(wa, wb, t * t * (3.0 - 2.0 * t)))
	var neg := PackedFloat32Array()
	for o in offs:
		neg.append(-o)
	var left := Geo.offset_polyline_var(line, neg)
	var right := Geo.offset_polyline_var(line, offs)
	right.reverse()
	left.append_array(right)
	return left


## After the turn paths exist: the area of each merged junction group is the union of its pieces and
## of every turn path widened to a lane, closed by CLOSE_R so that slivers and notches disappear.
## Holes larger than 20 m² (islands) stay. A plain junction keeps its star polygon unless a turn path
## leaves it (odd angles, different road widths); then it is built the same way.
func _finish_groups() -> void:
	for n in nodes:
		var pieces: Array = []
		if n.has("_pieces"):
			pieces = n._pieces
			n.erase("_pieces")
		elif n.ends.size() >= 2 and n.has("conns") and _paths_leave(n):
			pieces = _group_pieces(n, n.polygon, n.infos, [])
		else:
			continue
		# a strip along each turn path that leaves the plain star polygon (paths inside it are covered)
		var star_ok: bool = n.polygon.size() >= 3 and not JunctionMerge.self_intersects(n.polygon)
		for ci in n.get("conns", []):
			var c: Dictionary = connectors[ci]
			if c.turn == "U" or (star_ok and not _path_leaves(c.pts, n.polygon)):
				continue
			for b in Geometry2D.offset_polyline(c.pts, PATH_HALF_W, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT):
				if not Geometry2D.is_polygon_clockwise(b):
					pieces.append(b)
		_group_polygon(n, pieces)


## Does a turn path of plain junction n run outside its star polygon?
func _paths_leave(n: Dictionary) -> bool:
	var poly: PackedVector2Array = n.polygon
	if poly.size() < 3:
		return true
	for ci in n.conns:
		var c: Dictionary = connectors[ci]
		if c.turn != "U" and _path_leaves(c.pts, poly):
			return true
	return false


## Part of the path lies outside the polygon. Sampled every 2 m: long straight paths have few
## points, and their segments can cut a concave group area between two points inside it.
func _path_leaves(pts: PackedVector2Array, poly: PackedVector2Array) -> bool:
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps: int = maxi(1, ceili(a.distance_to(b) / 2.0))
		for k in range(1 if i == 0 else 0, steps):
			if not Geometry2D.is_point_in_polygon(a.lerp(b, float(k) / steps), poly):
				return true
	return false


func _group_polygon(n: Dictionary, pieces: Array) -> void:
	var u := JunctionMerge.union_all(pieces)
	var outers: Array = u[0]
	if outers.is_empty():
		return
	var bi := 0
	for i in outers.size():
		if absf(Geo.polygon_area(outers[i])) > absf(Geo.polygon_area(outers[bi])):
			bi = i
	var best: PackedVector2Array = outers[bi]
	var grown := Geometry2D.offset_polygon(best, CLOSE_R, Geometry2D.JOIN_ROUND)
	if grown.size() >= 1:
		var shrunk := Geometry2D.offset_polygon(grown[0], -CLOSE_R, Geometry2D.JOIN_ROUND)
		if shrunk.size() >= 1 and not Geometry2D.is_polygon_clockwise(shrunk[0]):
			# the arcs are chords, so the closing cuts off convex corners by up to a metre: add the
			# original back (a closing must never lose area, else notches appear at every road mouth)
			var closed: PackedVector2Array = shrunk[0]
			for r in Geometry2D.merge_polygons(closed, best):
				if not Geometry2D.is_polygon_clockwise(r) and absf(Geo.polygon_area(r)) > absf(Geo.polygon_area(closed)):
					closed = r
			best = closed
	# islands stay open, except where a piece (e.g. a turn path through a gap in the median) covers them
	var holes: Array = []
	for h in u[1]:
		var parts: Array = [h]
		for pc in pieces:
			var nxt: Array = []
			for part in parts:
				for r in Geometry2D.clip_polygons(part, pc):
					if not Geometry2D.is_polygon_clockwise(r):
						nxt.append(r)
			parts = nxt
		for part in parts:
			# opening: thin bridges and slivers left by the clipping go, they would show as specks
			for sp in Geometry2D.offset_polygon(part, -ISLAND_OPEN, Geometry2D.JOIN_MITER):
				if Geometry2D.is_polygon_clockwise(sp):
					continue
				for g in Geometry2D.offset_polygon(sp, ISLAND_OPEN, Geometry2D.JOIN_MITER):
					if not Geometry2D.is_polygon_clockwise(g) and absf(Geo.polygon_area(g)) > 20.0 \
							and Geometry2D.is_point_in_polygon(Geo.polygon_centroid(g), best):
						holes.append(g)
	n.polygon = best
	n["holes"] = holes
	n["area"] = true   # built by union: sidewalks next to it are clipped against it (RoadMesher)
	var extra: Array = []
	for i in outers.size():
		if i != bi and absf(Geo.polygon_area(outers[i])) > 2.0:
			extra.append(outers[i])
	n["extra_polys"] = extra


# ------------------------------------------------------------------------------------------
# Lanes
# ------------------------------------------------------------------------------------------

static func lane_key(edge: int, dir: int, lane: int) -> int:
	return edge * 16 + dir * 8 + lane


func lane_count(edge: int, dir: int) -> int:
	var e: Dictionary = edges[edge]
	return e.lf if dir == 0 else e.lb


## Lateral offset (right positive, relative to the a->b direction) of a lane center.
func lane_offset_fwd_frame(e: Dictionary, dir: int, lane: int) -> float:
	var lf: int = e.lf
	var lb: int = e.lb
	var lw: float = e.lw
	# lane block is centered between parking/cycle strips
	var shift: float = ((e.park_l + e.cyc_l) - (e.park_r + e.cyc_r)) * 0.5
	var total := (lf + lb) * lw
	var x_div := -total * 0.5 + lb * lw + shift
	if e.oneway:
		x_div = -total * 0.5 + shift
		return x_div + (lane + 0.5) * lw
	if dir == 0:
		return x_div + (lane + 0.5) * lw
	return x_div - (lane + 0.5) * lw


func _build_lanes() -> void:
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var s0: float = e.trim_a
		var s1: float = e.len - e.trim_b
		if s1 - s0 < 0.3:
			var mid: float = (e.trim_a + e.len - e.trim_b) * 0.5
			s0 = maxf(0.0, mid - 0.15)
			s1 = minf(e.len, mid + 0.15)
		var center := Geo.sub_polyline(e.pts, e.cum, s0, s1, 0.0)
		for dir in 2:
			var nl := lane_count(ei, dir)
			for li in nl:
				var off := lane_offset_fwd_frame(e, dir, li)
				var lp := Geo.drop_backtracks(Geo.offset_polyline(center, off))
				if dir == 1:
					lp.reverse()
				lane_geo[lane_key(ei, dir, li)] = [lp, Geo.cumulative(lp)]


## Turn movements allowed per lane from turn:lanes ("left|through;right").
static func parse_turn_lanes(v: String, n: int) -> Array:
	var res: Array = []
	if v == "":
		return res
	var parts := v.split("|")
	if parts.size() != n:
		return res
	for p in parts:
		var s := {}
		for t in p.split(";"):
			t = t.strip_edges()
			if t in ["left", "slight_left", "sharp_left"]:
				s["L"] = true
			elif t in ["right", "slight_right", "sharp_right"]:
				s["R"] = true
			elif t in ["reverse"]:
				s["U"] = true
			else:
				s["S"] = true
		res.append(s)
	return res


func _build_connectors() -> void:
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		var ends: Array = n.ends
		var deg := ends.size()
		for er_in in ends:
			var ein: int = er_in >> 1
			var e_in: Dictionary = edges[ein]
			# traffic entering this node on edge ein travels in dir 0 if node is b, dir 1 if node is a
			var dir_in := 0 if (er_in & 1) == 1 else 1
			var n_in := lane_count(ein, dir_in)
			if n_in == 0:
				continue
			var key_last := lane_key(ein, dir_in, 0)
			var geo_in: Array = lane_geo.get(key_last, [])
			if geo_in.is_empty():
				continue
			var pin: PackedVector2Array = geo_in[0]
			var d_in := (pin[pin.size() - 1] - pin[maxi(0, pin.size() - 2)]).normalized()
			var moves: Array = []  # {er_out, turn, ang}
			for er_out in ends:
				var eout: int = er_out >> 1
				var dir_out := 0 if (er_out & 1) == 0 else 1
				if lane_count(eout, dir_out) == 0:
					continue
				if n.has("reach") and not _group_reaches(n, er_in, er_out):
					continue
				var geo_out: Array = lane_geo.get(lane_key(eout, dir_out, 0), [])
				if geo_out.is_empty():
					continue
				var pout: PackedVector2Array = geo_out[0]
				var d_out := (pout[mini(1, pout.size() - 1)] - pout[0]).normalized()
				var cr := d_in.x * d_out.y - d_in.y * d_out.x
				var ang := atan2(cr, d_in.dot(d_out))
				var turn := "S"
				if er_out == er_in or absf(ang) > deg_to_rad(155.0):
					turn = "U"
				elif ang > deg_to_rad(35.0):
					turn = "R"
				elif ang < deg_to_rad(-35.0):
					turn = "L"
				moves.append({"er_out": er_out, "edge": eout, "dir": dir_out, "turn": turn, "ang": ang})
			var non_u := moves.filter(func(m): return m.turn != "U")
			if not non_u.is_empty():
				moves = non_u
				# if no straight move exists, treat the move closest to straight as S for lane assignment
				var has_s := moves.any(func(m): return m.turn == "S")
				if not has_s:
					var best = moves[0]
					for m in moves:
						if absf(m.ang) < absf(best.ang):
							best = m
					best.turn = "S"
			var turn_tags := parse_turn_lanes(e_in.turn_f if dir_in == 0 else e_in.turn_b, n_in)
			for m in moves:
				var n_out := lane_count(m.edge, m.dir)
				var lanes_for_move: Array = []
				if not turn_tags.is_empty():
					for li in n_in:
						if turn_tags[li].has(m.turn) or (m.turn == "U" and turn_tags[li].has("L")):
							lanes_for_move.append(li)
				if lanes_for_move.is_empty():
					if n_in == 1:
						lanes_for_move = [0]
					elif m.turn == "R":
						lanes_for_move = [n_in - 1]
					elif m.turn in ["L", "U"]:
						lanes_for_move = [0]
					else:
						for li in n_in:
							lanes_for_move.append(li)
				for li in lanes_for_move:
					var lo := 0
					if m.turn == "R":
						lo = n_out - 1
					elif m.turn in ["L", "U"]:
						lo = 0
					elif absf(m.ang) < deg_to_rad(35.0):
						lo = _nearest_out_lane(ein, dir_in, li, m.edge, m.dir)
					else:
						if n_in == n_out:
							lo = li
						elif n_in > 1:
							lo = int(round(float(li) * float(n_out - 1) / float(n_in - 1)))
						else:
							lo = n_out - 1
					lo = clampi(lo, 0, n_out - 1)
					_add_connector(ni, ein, dir_in, li, m.edge, m.dir, lo, m.turn)
			# safety: every incoming lane needs at least one way out
			for li in n_in:
				var k := lane_key(ein, dir_in, li)
				if not lane_out.has(k) and not moves.is_empty():
					var m0 = moves[0]
					_add_connector(ni, ein, dir_in, li, m0.edge, m0.dir, 0, m0.turn)


## Path from p0 (heading t0) to p3 (heading t3), points about 0.75 m apart. A turn becomes straight
## - circular arc - straight with the largest radius that fits: constant curvature, no tight spot in
## the middle (a cubic curve had one, cars jerked there). Nearly straight moves, and lanes that do not
## meet in front of both ends, get a smooth cubic S curve.
static func turn_path(p0: Vector2, t0: Vector2, p3: Vector2, t3: Vector2) -> PackedVector2Array:
	var phi := absf(t0.angle_to(t3))
	if phi > deg_to_rad(8.0) and phi < deg_to_rad(175.0):
		var res = Geometry2D.line_intersects_line(p0, t0, p3, t3)
		if res != null:
			var X: Vector2 = res
			var a := (X - p0).dot(t0)
			var b := (p3 - X).dot(t3)
			if a > 0.3 and b > 0.3:
				var T := minf(a, b)
				var r := T / tan(phi * 0.5)
				var A := X - t0 * T
				var B := X + t3 * T
				var side := 1.0 if (t0.x * t3.y - t0.y * t3.x) > 0.0 else -1.0
				var C: Vector2 = A + Geo.right_of(t0) * r * side
				var a0 := (A - C).angle()
				var sweep := wrapf((B - C).angle() - a0, -PI, PI)
				var out := PackedVector2Array([p0])
				if a - T > 0.05:
					out.append(A)
				var n := clampi(int(ceil(absf(sweep) * r / 0.75)), 2, 96)
				for i in range(1, n):
					out.append(C + Vector2.from_angle(a0 + sweep * float(i) / n) * r)
				if b - T > 0.05:
					out.append(B)
				out.append(p3)
				return out
	var dist := p0.distance_to(p3)
	if dist < 4.0 and ((p3 - p0).dot(t0) <= 0.0 or (p3 - p0).dot(t3) <= 0.0):
		# the exit starts beside or behind the entry end: a curve would loop on the spot (the car spun)
		return PackedVector2Array([p0, p3])
	var kk := clampf(dist * 0.42, 0.5, 30.0)
	var c1 := p0 + t0 * kk
	var c2 := p3 - t3 * kk
	var steps := clampi(int(dist / 0.75), 4, 64)
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p3 * t * t * t)
	return pts


## For a straight-on move: the lane of the exit road that lies closest to the straight continuation of
## entry lane li (fewest sideways metres). Index matching shifted cars by several metres where the two
## roads have different widths or lane counts.
func _nearest_out_lane(e_in: int, d_in: int, li: int, e_out: int, d_out: int) -> int:
	var g: Array = lane_geo[lane_key(e_in, d_in, li)]
	var pin: PackedVector2Array = g[0]
	var cin: PackedFloat32Array = g[1]
	var p0 := pin[pin.size() - 1]
	var t0 := (p0 - (Geo.sample(pin, cin, cin[cin.size() - 1] - 3.0)[0] as Vector2)).normalized()
	var r := Geo.right_of(t0)
	var best := 0
	var best_x := INF
	for lo in lane_count(e_out, d_out):
		var go: Array = lane_geo.get(lane_key(e_out, d_out, lo), [])
		if go.is_empty():
			continue
		var x := absf(((go[0] as PackedVector2Array)[0] - p0).dot(r))
		if x < best_x - 0.01:
			best_x = x
			best = lo
	return best


## In a merged junction group: can traffic entering at road end er_in leave at er_out along the
## removed inner pieces (in their travel direction)?
func _group_reaches(n: Dictionary, er_in: int, er_out: int) -> bool:
	var m_in := _member_of(er_in)
	var m_out := _member_of(er_out)
	var r: Dictionary = n.reach.get(m_in, {})
	return r.has(m_out)


func _member_of(er: int) -> int:
	var e: Dictionary = edges[er >> 1]
	return int(e.get("mem_a" if (er & 1) == 0 else "mem_b", -1))


func _add_connector(ni: int, e_from: int, d_from: int, l_from: int, e_to: int, d_to: int, l_to: int, turn: String) -> void:
	var k_from := lane_key(e_from, d_from, l_from)
	var k_to := lane_key(e_to, d_to, l_to)
	for ci in lane_out.get(k_from, []):
		if connectors[ci].to == k_to:
			return
	var gi: Array = lane_geo[k_from]
	var go: Array = lane_geo[k_to]
	var pin: PackedVector2Array = gi[0]
	var pout: PackedVector2Array = go[0]
	var p0 := pin[pin.size() - 1]
	var p3 := pout[0]
	# directions over the last / first 3 m of the lanes (one short end segment can point anywhere)
	var cin: PackedFloat32Array = gi[1]
	var cout: PackedFloat32Array = go[1]
	var t0 := (p0 - (Geo.sample(pin, cin, cin[cin.size() - 1] - 3.0)[0] as Vector2)).normalized()
	var t3 := ((Geo.sample(pout, cout, 3.0)[0] as Vector2) - p3).normalized()
	if t0 == Vector2.ZERO:
		t0 = (p0 - pin[maxi(0, pin.size() - 2)]).normalized()
	if t3 == Vector2.ZERO:
		t3 = (pout[mini(1, pout.size() - 1)] - p3).normalized()
	var dist := p0.distance_to(p3)
	var pts := PackedVector2Array()
	if turn == "U" and dist < 4.0:
		# turn around: semicircle-ish loop
		var mid := (p0 + p3) * 0.5 + t0 * 3.5
		pts = PackedVector2Array([p0, p0 + t0 * 2.5, mid, p3 + (-t3) * -0.0 + t0 * 2.5, p3])
	else:
		pts = turn_path(p0, t0, p3, t3)
	var cum := Geo.cumulative(pts)
	var ci := connectors.size()
	connectors.append({"node": ni, "from": k_from, "to": k_to, "pts": pts, "cum": cum, "len": cum[cum.size() - 1],
		"turn": turn, "conflicts": PackedInt32Array(), "phase": -1, "yield_to": PackedInt32Array(), "major": true,
		"approach_end": e_from * 2 + (1 if d_from == 0 else 0)})
	if not lane_out.has(k_from):
		lane_out[k_from] = []
	lane_out[k_from].append(ci)
	if not lane_in.has(k_to):
		lane_in[k_to] = []
	lane_in[k_to].append(ci)
	if not nodes[ni].has("conns"):
		nodes[ni]["conns"] = []
	nodes[ni].conns.append(ci)


# ------------------------------------------------------------------------------------------
# Traffic control + conflicts
# ------------------------------------------------------------------------------------------

func _traffic_control(data: OsmData) -> void:
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		var deg: int = n.ends.size()
		if deg <= 2:
			n.ctrl = "none"
			continue
		var has_signal: bool = data.signals.has(n.osm_id)
		for id in n.get("osm_ids", []):
			if data.signals.has(id):
				has_signal = true
		var ranks := []
		for er in n.ends:
			var e: Dictionary = edges[er >> 1]
			var at_start: bool = (er & 1) == 0
			if (at_start and e.signal_a) or ((not at_start) and e.signal_b):
				has_signal = true
			var r: int = e.rank
			if (at_start and e.giveway_a) or ((not at_start) and e.giveway_b):
				r -= 10
			ranks.append(r)
		if has_signal:
			n.ctrl = "signals"
			_assign_phases(n)
			continue
		var mx: int = ranks.max()
		var count_max := ranks.count(mx)
		if count_max < ranks.size():
			n.ctrl = "priority"
			n["major_ends"] = []
			for i in deg:
				if ranks[i] == mx:
					n.major_ends.append(n.ends[i])
			# if only one major approach, the second best also counts as major (bending main road)
			if n.major_ends.size() == 1:
				var second := -999
				for i in deg:
					if ranks[i] != mx:
						second = maxi(second, ranks[i])
				for i in deg:
					if ranks[i] == second and n.major_ends.size() < 2:
						n.major_ends.append(n.ends[i])
		else:
			n.ctrl = "rvl"


func _assign_phases(n: Dictionary) -> void:
	# group approaches into two axes
	var infos: Array = n.infos
	var best = infos[0]
	for inf in infos:
		if inf.rank > best.rank:
			best = inf
	var axis: Vector2 = best.d
	var phases := {}
	for inf in infos:
		var c := absf(inf.d.dot(axis))
		phases[inf.ref] = 0 if c > 0.7 else 1
	n.phases = phases


func _conflicts() -> void:
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		if not n.has("conns"):
			continue
		var cs: Array = n.conns
		for i in cs.size():
			var ca: Dictionary = connectors[cs[i]]
			if n.ctrl == "signals":
				ca.phase = n.phases.get(ca.approach_end, 0)
		var boxes: Array = []
		for ci in cs:
			boxes.append(_bbox(connectors[ci].pts))
		for i in cs.size():
			for j in range(i + 1, cs.size()):
				var a: Dictionary = connectors[cs[i]]
				var b: Dictionary = connectors[cs[j]]
				if a.from == b.from:
					continue
				var conflict: bool = a.to == b.to
				if not conflict and (a.from >> 3) != (b.from >> 3) and (boxes[i] as Rect2).intersects(boxes[j], true):
					conflict = _polylines_intersect(a.pts, b.pts, boxes[j])
				if conflict:
					a.conflicts.append(cs[j])
					b.conflicts.append(cs[i])


## The node end (edge*2+end) through which a connector enters the junction.
func _approach_end(c: Dictionary) -> int:
	var e: int = c.from >> 4
	var dir: int = (c.from >> 3) & 1
	# dir 0 travels a->b, enters at end b (=1); dir 1 enters at end a (=0)
	return e * 2 + (1 if dir == 0 else 0)


static func _bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r


static func _polylines_intersect(a: PackedVector2Array, b: PackedVector2Array, b_box := Rect2()) -> bool:
	# ignore the first/last 0.5 m so that connectors sharing a start/end don't count
	var use_box := b_box.size != Vector2.ZERO
	for i in range(a.size() - 1):
		if use_box and not Rect2(a[i], Vector2.ZERO).expand(a[i + 1]).intersects(b_box, true):
			continue
		for j in range(b.size() - 1):
			var r = Geometry2D.segment_intersects_segment(a[i], a[i + 1], b[j], b[j + 1])
			if r != null:
				var p: Vector2 = r
				if p.distance_to(a[0]) < 0.3 and p.distance_to(b[0]) < 0.3:
					continue
				return true
	return false


# ------------------------------------------------------------------------------------------
# Queries
# ------------------------------------------------------------------------------------------

func lane_end_node(key: int) -> int:
	var e: Dictionary = edges[key >> 4]
	return e.b if ((key >> 3) & 1) == 0 else e.a


func approach_end_of_lane(key: int) -> int:
	var e: int = key >> 4
	var dir: int = (key >> 3) & 1
	return e * 2 + (1 if dir == 0 else 0)


## Find the closest drivable lane to a point: returns {key, s, dist, point}
func nearest_lane(p: Vector2, max_dist: float = 60.0, exclude_classes: Array = []) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for key in lane_geo:
		var e: Dictionary = edges[key >> 4]
		if e.cls in exclude_classes or e.get("under", false):
			continue
		var g: Array = lane_geo[key]
		var pts: PackedVector2Array = g[0]
		# quick reject by bounding distance to first point
		if pts[0].distance_to(p) - e.len > best_d:
			continue
		var r := Geo.closest_on_polyline(pts, g[1], p)
		if r[0] < best_d:
			best_d = r[0]
			best = {"key": key, "s": r[1], "dist": r[0], "point": r[2]}
	return best


func serialize() -> Dictionary:
	return {"nodes": nodes, "edges": edges, "connectors": connectors, "lane_out": lane_out, "lane_in": lane_in,
		"lane_geo": lane_geo, "hq_node": hq_node, "bounds": bounds}


func deserialize(d: Dictionary) -> void:
	nodes = d.nodes
	edges = d.edges
	connectors = d.connectors
	lane_out = d.lane_out
	lane_in = d.lane_in
	lane_geo = d.lane_geo
	hq_node = d.hq_node
	bounds = d.bounds
