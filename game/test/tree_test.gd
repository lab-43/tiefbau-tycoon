extends SceneTree
## Trees and street lamps off the road (#30: real street trees stood on the asphalt, the game draws the
## carriageway wider than it is). Bakes the Utrecht .pbf and checks every tree and lamp against the triangles
## of the baked asphalt meshes (what the player sees, independent of AsphaltIndex), and that only a few real
## trees were dropped. Lamps high up on a bridge or ramp stand above the ground asphalt and are not counted.
## usage: godot --headless --path game -s res://test/tree_test.gd -- <utrecht.osm.pbf>   (tools/test.sh baeume)
## Prints "BAEUME OK" and exits 0, or "BAEUME FAIL [...]" and exits 1 (also after a script error, via watchdog).

const CELL := 10.0
const MAX_DROPPED := 0.03   # share of the real trees that may be left out (deep inside a road)
const WATCHDOG_S := 240.0

var _done := false


func _initialize() -> void:
	# a script error below would leave Godot running until the outer timeout; fail early instead
	create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	var pbf: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://").path_join("../testdata/utrecht.osm.pbf")
	var t0 := Time.get_ticks_msec()
	var meta := {"center_lat": 52.0907, "center_lon": 5.1214, "size_m": 6000.0}
	var res: Dictionary = MapBuilder.new().bake(meta, "", pbf)
	var bad: Array = []
	# a script error inside a function only aborts that function (it returns false), the caller goes on
	if not _check(res, bad):
		bad.append("Prüfung abgebrochen (Skriptfehler?)")
	_done = true
	if bad.is_empty():
		print("BAEUME OK in %d ms" % (Time.get_ticks_msec() - t0))
		quit(0)
	else:
		print("BAEUME FAIL ", bad)
		quit(1)


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("BAEUME FAIL nach %d s nicht fertig (Skriptfehler?)" % int(WATCHDOG_S))
	quit(1)


func _check(res: Dictionary, bad: Array) -> bool:
	# triangles of the ground asphalt (bridge decks are separate "asphalt_deck" layers) in a grid
	var grid := {}
	var tris := 0
	for ck in res.roads:
		var l: MeshLayer = res.roads[ck].get("asphalt")
		if l == null:
			continue
		for i in range(0, l.indices.size(), 3):
			var a := Vector2(l.verts[l.indices[i]].x, l.verts[l.indices[i]].z)
			var b := Vector2(l.verts[l.indices[i + 1]].x, l.verts[l.indices[i + 1]].z)
			var c := Vector2(l.verts[l.indices[i + 2]].x, l.verts[l.indices[i + 2]].z)
			var r := Rect2(a, Vector2.ZERO).expand(b).expand(c)
			for gx in range(int(floor(r.position.x / CELL)), int(floor(r.end.x / CELL)) + 1):
				for gz in range(int(floor(r.position.y / CELL)), int(floor(r.end.y / CELL)) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					grid[k].append([a, b, c])
			tris += 1
	if tris == 0:
		bad.append("keine Fahrbahn-Dreiecke in der Testkarte")
	var total := 0
	for kind in [["trees", "Bäumen"], ["lamps", "Laternen"]]:
		var n := 0
		var on_road: Array = []
		for ck in res[kind[0]]:
			for tf in res[kind[0]][ck]:
				var p := Vector2((tf as Transform3D).origin.x, (tf as Transform3D).origin.z)
				n += 1
				if (tf as Transform3D).origin.y > CityMesher.LAMP_ABOVE:
					continue   # on a bridge or ramp above the ground asphalt (the test map is flat, #32)
				for t in grid.get(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), []):
					if Geometry2D.point_is_inside_triangle(p, t[0], t[1], t[2]):
						on_road.append(p)
						break
		if not on_road.is_empty():
			bad.append("%d von %d %s stehen auf der Fahrbahn, z. B. %s" % [on_road.size(), n, kind[1], str(on_road.slice(0, 5))])
		if kind[0] == "trees":
			total = n
	var st: Dictionary = res.get("tree_stats", {})
	var osm: int = int(st.get("osm", 0))
	if osm < 100:
		bad.append("Testkarte hat nur %d echte Bäume – Prüfung ohne Aussage" % osm)
	elif float(st.get("dropped", 0)) > osm * MAX_DROPPED:
		bad.append("%d von %d echten Bäumen weggelassen (mehr als %d %%)" % [int(st.dropped), osm, int(MAX_DROPPED * 100.0)])
	print("BAEUME %d Bäume, %d Fahrbahn-Dreiecke, echte Bäume %s" % [total, tris, str(st)])
	return true
