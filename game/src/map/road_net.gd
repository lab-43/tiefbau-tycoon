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
const DEFAULT_SPEED_KMH := {
	"motorway": 100, "trunk": 70, "primary": 50, "secondary": 50, "tertiary": 50, "busway": 50,
	"unclassified": 50, "residential": 30, "road": 30, "living_street": 10, "service": 20,
	"motorway_link": 60, "trunk_link": 50, "primary_link": 40, "secondary_link": 40, "tertiary_link": 40,
}

var nodes: Array = []        # {pos, ends: Array[int] (edge*2+end), ctrl, osm_id, polygon, phases}
var edges: Array = []        # see _make_edge
var connectors: Array = []   # see _build_connectors
var lane_out: Dictionary = {}  # lane key -> Array[int] connector ids leaving the end of that lane
var lane_in: Dictionary = {}   # lane key -> Array[int] connector ids arriving at start of that lane
var lane_geo: Dictionary = {}  # lane key -> [pts: PackedVector2Array, cum: PackedFloat32Array]
var hq_node: int = -1          # node at the HQ gate (end of driveway)
var hq_edge: int = -1
var bounds := Rect2()

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
		e.pts = Geo.chaikin(e.pts, 2, 3.0)
		e.cum = Geo.cumulative(e.pts)
		e.len = e.cum[e.cum.size() - 1]
	_mark_crossings(data)
	_junction_geometry()
	_build_lanes()
	_build_connectors()
	_traffic_control(data)
	_conflicts()


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
	if tags.get("tunnel", "") in ["yes", "building_passage"] and cls in ["motorway", "trunk", "motorway_link", "trunk_link"]:
		return {}
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
		"tunnel": tags.get("tunnel", "") == "yes",
		"bus": data.bus_way_ids.has(int(r.way.id)) or cls == "busway",
		"turn_f": str(tags.get("turn:lanes", tags.get("turn:lanes:forward", ""))) if true else "",
		"turn_b": str(tags.get("turn:lanes:backward", "")),
		"trim_a": 0.0, "trim_b": 0.0, "crossings": [], "signal_a": false, "signal_b": false,
		"giveway_a": false, "giveway_b": false, "sig": "",
	}


func _signature(e: Dictionary) -> String:
	return "%s|%s|%d|%d|%.2f|%.1f|%.1f|%.1f|%.1f|%s|%d|%s|%s" % [e.cls, e.oneway, e.lf, e.lb, e.lw, e.sw_l, e.sw_r,
		e.park_l + e.cyc_l, e.park_r + e.cyc_r, e.bridge, e.layer, e.bus, e.turn_f + e.turn_b]


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
				if res3[1] < 25.0:
					e.giveway_a = true
				if e.len - res3[1] < 25.0:
					e.giveway_b = true


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


func _junction_geometry() -> void:
	for ni in nodes.size():
		var n: Dictionary = nodes[ni]
		var k: int = n.ends.size()
		if k < 2:
			continue
		var J: Vector2 = n.pos
		var infos: Array = []
		for er in n.ends:
			var inf := end_info(er)
			inf["ref"] = er
			inf["ang"] = atan2(inf.d.y, inf.d.x)
			inf["s"] = 0.6
			infos.append(inf)
		infos.sort_custom(func(x, y): return x.ang < y.ang)
		var corners: Array = []
		for i in k:
			var A: Dictionary = infos[i]
			var B: Dictionary = infos[(i + 1) % k]
			var alpha: float = B.ang - A.ang
			if i == k - 1:
				alpha += TAU
			if k == 1:
				alpha = TAU
			var nA := Geo.right_of(A.d)   # +90deg in angle sense
			var nB := Geo.right_of(B.d)
			var corner := {"conv": false, "c": Vector2.ZERO}
			if alpha < PI - 0.15:
				# line A: J + nA*hwA + dA*t1 ; line B: J - nB*hwB + dB*t2
				var p1: Vector2 = J + nA * A.hw
				var p2: Vector2 = J - nB * B.hw
				var res = Geometry2D.line_intersects_line(p1, A.d, p2, B.d)
				if res != null:
					var C: Vector2 = res
					var t1: float = (C - p1).dot(A.d)
					var t2: float = (C - p2).dot(B.d)
					var r: float = CORNER_RADIUS.get(mini(A.rank, B.rank) % 20, 6.0)
					var tang: float = minf(r / maxf(0.05, tan(alpha * 0.5)), 22.0)
					A.s = maxf(A.s, t1 + tang)
					B.s = maxf(B.s, t2 + tang)
					corner = {"conv": true, "c": C}
			corners.append(corner)
		# clamp setbacks
		for inf in infos:
			var e: Dictionary = edges[inf.edge]
			var other_is_junction := true
			var lim: float = e.len * (0.45 if other_is_junction else 0.9)
			inf.s = clampf(inf.s, 0.0, maxf(0.0, lim))
			if inf.start:
				e.trim_a = inf.s
			else:
				e.trim_b = inf.s
		# polygon
		var poly := PackedVector2Array()
		var corner_curves: Array = []
		for i in k:
			var A: Dictionary = infos[i]
			var B: Dictionary = infos[(i + 1) % k]
			var nA := Geo.right_of(A.d)
			var nB := Geo.right_of(B.d)
			var a_left: Vector2 = J + A.d * A.s - nA * A.hw
			var a_right: Vector2 = J + A.d * A.s + nA * A.hw
			var b_left: Vector2 = J + B.d * B.s - nB * B.hw
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
			curve.append(b_left)
			var sw := minf(A.sw_right, B.sw_left)
			corner_curves.append({"pts": curve, "sw": sw, "conv": corners[i].conv})
		n.polygon = poly
		n.corners = corner_curves
		n.infos = infos


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
				var lp := Geo.offset_polyline(center, off)
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
	var t0 := (p0 - pin[maxi(0, pin.size() - 2)]).normalized()
	var p3 := pout[0]
	var t3 := (pout[mini(1, pout.size() - 1)] - p3).normalized()
	var dist := p0.distance_to(p3)
	var pts := PackedVector2Array()
	if turn == "U" and dist < 4.0:
		# turn around: semicircle-ish loop
		var mid := (p0 + p3) * 0.5 + t0 * 3.5
		pts = PackedVector2Array([p0, p0 + t0 * 2.5, mid, p3 + (-t3) * -0.0 + t0 * 2.5, p3])
	else:
		var kk := clampf(dist * 0.42, 0.5, 30.0)
		var c1 := p0 + t0 * kk
		var c2 := p3 - t3 * kk
		var steps := clampi(int(dist / 1.5), 3, 24)
		for i in steps + 1:
			var t := float(i) / steps
			var u := 1.0 - t
			pts.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p3 * t * t * t)
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
		for i in cs.size():
			for j in range(i + 1, cs.size()):
				var a: Dictionary = connectors[cs[i]]
				var b: Dictionary = connectors[cs[j]]
				if a.from == b.from:
					continue
				var conflict: bool = a.to == b.to
				if not conflict and (a.from >> 3) != (b.from >> 3):
					conflict = _polylines_intersect(a.pts, b.pts)
				if conflict:
					a.conflicts.append(cs[j])
					b.conflicts.append(cs[i])


## The node end (edge*2+end) through which a connector enters the junction.
func _approach_end(c: Dictionary) -> int:
	var e: int = c.from >> 4
	var dir: int = (c.from >> 3) & 1
	# dir 0 travels a->b, enters at end b (=1); dir 1 enters at end a (=0)
	return e * 2 + (1 if dir == 0 else 0)


static func _polylines_intersect(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	# ignore the first/last 0.5 m so that connectors sharing a start/end don't count
	for i in range(a.size() - 1):
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
		if e.cls in exclude_classes:
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
