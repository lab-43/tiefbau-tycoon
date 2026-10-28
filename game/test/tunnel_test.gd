extends Node
## Tunnels below the surface (#31) on the Deichtorplatz fixture (Deichtortunnel, south end of the Wallringtunnel):
##   asphalt   – points on the centre lines of tunnels lie on surface asphalt only where a street or junction
##               area on the surface is there anyway (the same check with the tunnels drawn on top must find them),
##   portals   – the tunnels have portals, the two tubes of a tunnel end share one,
##   layers    – the underground view has its roads (and U-Bahn / S-Bahn tracks where the fixture has some),
##   traffic   – cars drive through the tunnels, their models are hidden inside and shown outside,
##   pick      – a point above a tunnel finds the street on the surface, not the tunnel (Router.nearest_lane).
## usage: godot --headless --path game res://test/tunnel_test.tscn -- --fixtures=<dir> [--seconds=90]
## (a scene, not -s: TrafficSim needs the Clock autoload)  ·  tools/test.sh tunnel
## Prints "TUNNEL OK …" or "TUNNEL FAIL …" (exit code 1).

const FIXTURE := "deichtorplatz"

var fails: Array = []


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var dir: String = args.get("fixtures", "")
	var seconds: float = float(args.get("seconds", "90"))
	var spec = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("kreuzungen.json")))
	if typeof(spec) != TYPE_DICTIONARY:
		print("TUNNEL FAIL kreuzungen.json fehlt")
		get_tree().quit(1)
		return
	var fx := {}
	for f in spec.kreuzungen:
		if f.id == FIXTURE:
			fx = f
	Geo.setup(float(fx.lat), float(fx.lon))
	var data := OsmParser.new().parse_pbf(dir.path_join(FIXTURE + ".osm.pbf"), 300.0)
	var net := RoadNet.new()
	net.build(data, {})
	var portals := TunnelPortals.new()
	var rm := RoadMesher.new(net, 500.0, data.bounds.position)
	rm.portals = portals
	rm.build_all()
	var cm := CityMesher.new(data, net, 500.0)
	cm.portals = portals
	cm.build_all()
	portals.build(net, data.rails, cm)
	var trees_before := 0
	for ck in cm.trees:
		trees_before += cm.trees[ck].size()
	var cleared := portals.clear_xforms(cm.trees) + portals.clear_xforms(cm.lamps)
	var on_portal := 0
	for by in [cm.trees, cm.lamps]:
		for ck in by:
			for x: Transform3D in by[ck]:
				if portals.covers(Vector2(x.origin.x, x.origin.z)):
					on_portal += 1
	print("  Bäume %d, auf Portalen entfernt %d, noch auf Portalen %d" % [trees_before, cleared, on_portal])
	if on_portal > 0:
		fails.append("%d Bäume oder Laternen auf Portalen" % on_portal)
	var under := 0
	for e in net.edges:
		if e.under:
			under += 1
	print("  Tunnelabschnitte %d (%.0f m), Knoten unter der Erde %d, Gleise im Tunnel %d, Portale %d (aus %d Röhrenenden)" % [
		under, rm.under_stats.m, rm.under_stats.nodes, data.under_rails.size(), portals.built, portals.specs.size()])
	if under < 4:
		fails.append("nur %d Tunnelabschnitte" % under)
	# --- asphalt
	var bad := _asphalt_over_tunnels(net, rm, portals)
	print("  Asphalt über Tunneln ohne Straße darüber: %d von %d Punkten" % [bad[0], bad[1]])
	if bad[1] < 20:
		fails.append("zu wenige Prüfpunkte (%d)" % bad[1])
	if bad[0] > 0:
		fails.append("%d Punkte Asphalt über Tunneln" % bad[0])
	# --- portals and layers
	var counts := {}
	for chunks in [rm.chunks, cm.chunks]:
		for ck in chunks:
			for lname in chunks[ck]:
				counts[lname] = int(counts.get(lname, 0)) + (chunks[ck][lname] as MeshLayer).indices.size() / 3
	print("  Dreiecke: under_road %d, under_subway %d, under_rail %d, portal %d, portal_dark %d, portal_green %d" % [
		counts.get("under_road", 0), counts.get("under_subway", 0), counts.get("under_rail", 0), counts.get("portal", 0),
		counts.get("portal_dark", 0), counts.get("portal_green", 0)])
	if portals.built < 2 or portals.built >= portals.specs.size():
		fails.append("Portale: %d Bauwerke aus %d Röhrenenden (Röhren nicht zusammengefasst?)" % [portals.built, portals.specs.size()])
	if int(counts.get("portal", 0)) == 0 or int(counts.get("portal_dark", 0)) == 0:
		fails.append("Portale ohne Geometrie")
	if int(counts.get("under_road", 0)) == 0:
		fails.append("keine Tunnel in der Untergrund-Ansicht")
	# --- traffic and picking
	_traffic(net, seconds)
	_pick(net)
	# --- the check sees tunnels drawn on the surface (as before #31)
	for e in net.edges:
		e.under = false
	for n in net.nodes:
		n.under = false
	var rm2 := RoadMesher.new(net, 500.0, data.bounds.position)
	rm2.build_all()
	var raw := _asphalt_over_tunnels(net, rm2, portals, true)
	print("  Gegenprobe mit Tunneln auf der Oberfläche: %d von %d Punkten" % [raw[0], raw[1]])
	if raw[0] < raw[1] / 3:
		fails.append("Gegenprobe findet die Tunnel nicht (%d von %d)" % [raw[0], raw[1]])
	if fails.is_empty():
		print("TUNNEL OK %d Tunnelabschnitte, %d Portale, Asphalt darüber %d/%d" % [under, portals.built, bad[0], bad[1]])
		get_tree().quit(0)
	else:
		print("TUNNEL FAIL ", "; ".join(fails))
		get_tree().quit(1)


var _probe: Array = []   # [point, edge] along the tunnels, collected on the first call


## Points every 4 m on the centre lines of the tunnels (away from the portals) that lie on asphalt where no
## street or junction area of the surface is. Returns [bad points, points].
func _asphalt_over_tunnels(net: RoadNet, rm: RoadMesher, portals: TunnelPortals, again := false) -> Array:
	if not again:
		for ei in net.edges.size():
			var e: Dictionary = net.edges[ei]
			if not e.under:
				continue
			var s: float = e.trim_a + 8.0
			while s < e.len - e.trim_b - 8.0:
				_probe.append(Geo.sample(e.pts, e.cum, s)[0])
				s += 4.0
	var tris := {}   # 10 m cell -> Array[PackedVector2Array]
	for ck in rm.chunks:
		for lname in ["asphalt", "asphalt_deck"]:
			var l: MeshLayer = rm.chunks[ck].get(lname)
			if l == null:
				continue
			for t in range(0, l.indices.size(), 3):
				var a := Vector2(l.verts[l.indices[t]].x, l.verts[l.indices[t]].z)
				var b := Vector2(l.verts[l.indices[t + 1]].x, l.verts[l.indices[t + 1]].z)
				var c := Vector2(l.verts[l.indices[t + 2]].x, l.verts[l.indices[t + 2]].z)
				var r := Rect2(a, Vector2.ZERO).expand(b).expand(c)
				for gx in range(floori(r.position.x / 10.0), floori(r.end.x / 10.0) + 1):
					for gz in range(floori(r.position.y / 10.0), floori(r.end.y / 10.0) + 1):
						var k := Vector2i(gx, gz)
						if not tris.has(k):
							tris[k] = []
						tris[k].append(PackedVector2Array([a, b, c]))
	var bad := 0
	for q in _probe:
		var on := false
		for tri in tris.get(Vector2i(floori(q.x / 10.0), floori(q.y / 10.0)), []):
			if Geometry2D.point_is_inside_triangle(q, tri[0], tri[1], tri[2]):
				on = true
				break
		if on and not portals._hit(q, {}):
			bad += 1
	return [bad, _probe.size()]


## Runs traffic around the tunnels: models hidden exactly while in_tunnel, and some cars get through.
func _traffic(net: RoadNet, seconds: float) -> void:
	var sim := TrafficSim.new()
	add_child(sim)
	sim.setup(net, [])
	sim.radius = 260.0
	sim.max_traffic = 90
	var inside := {}
	var through := 0
	var entered := 0
	var wrong := 0
	for i in int(seconds / TrafficSim.STEP):
		sim._step(TrafficSim.STEP)
		for ag: Agent in sim.agents:
			if ag.visual == null:
				continue
			sim._place_visual(ag, 1.0)
			var t := sim.in_tunnel(ag)
			if ag.visual.visible == t:
				wrong += 1
			if t and not inside.has(ag.id):
				inside[ag.id] = true
				entered += 1
			elif not t and inside.has(ag.id):
				inside.erase(ag.id)
				through += 1
	print("  Verkehr: %d Fahrten in einen Tunnel, %d wieder heraus, %d falsch gezeigt/versteckt" % [entered, through, wrong])
	if entered < 3 or through < 1:
		fails.append("kaum Verkehr durch die Tunnel (%d hinein, %d heraus)" % [entered, through])
	if wrong > 0:
		fails.append("%d Mal Fahrzeug im Tunnel sichtbar oder draußen versteckt" % wrong)
	sim.free()


## A point above the middle of the longest tunnel: nearest_lane finds a surface lane, with under = true the tunnel.
func _pick(net: RoadNet) -> void:
	var router := Router.new()
	router.setup(net)
	var best := -1
	for ei in net.edges.size():
		if net.edges[ei].under and (best < 0 or net.edges[ei].len > net.edges[best].len):
			best = ei
	if best < 0:
		return
	var e: Dictionary = net.edges[best]
	var mid: Vector2 = Geo.sample(e.pts, e.cum, e.len * 0.5)[0]
	var top := router.nearest_lane(mid, 60.0)
	var down := router.nearest_lane(mid, 60.0, Callable(), true)
	var top_ok := top.is_empty() or not net.lane_under(int(top.key))
	var down_ok := not down.is_empty() and net.lane_under(int(down.key))
	print("  Klick über dem Tunnel: Oberfläche %s, mit Tunneln %s" % ["ok" if top_ok else "TUNNEL", "Tunnel" if down_ok else "nicht gefunden"])
	if not top_ok or not down_ok:
		fails.append("nearest_lane über dem Tunnel")
