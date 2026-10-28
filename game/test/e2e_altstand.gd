extends RefCounted
## e2e scenario "altstand" (tools/test.sh altstand, #23): a save from an older map build. Every map build
## (BAKE_VERSION) numbers the roads anew, so the lane keys stored in jobs no longer fit. Phase "altstand_save"
## accepts two offers and writes a save whose keys look like an old build's: one active job points to a key that
## does not exist (release builds crashed on it), the other to an existing lane of another street (would put the
## site in the wrong place), and every offer to a missing key. Phase "altstand_load" loads it and checks that all
## jobs are back at their saved place. Driven by e2e_driver.gd (_altstand_test).

const EXPECT_FILE := "e2e_altstand.json"
const TOL := 0.5

var drv: Node
var step := 0
var fails := 0
var t_mark := 0.0


func ok(cond: bool, what: String) -> void:
	print("ALT %-4s %s" % ["ok" if cond else "FAIL", what])
	if not cond:
		fails += 1


func tick(_delta: float) -> void:
	if drv.scenario == "altstand_save":
		_save_phase()
	else:
		_load_phase()


func _save_phase() -> void:
	var jm: JobManager = drv.world.jobs
	match step:
		0:
			if drv.t < 1.0:
				return
			# the two nearest offers become sites
			for k in 2:
				if jm.offers.is_empty():
					var mo := jm._make_offer()
					if mo:
						jm.offers.append(mo)
				if jm.offers.is_empty():
					ok(false, "kein Angebot")
					_finish("")
					return
				var best: Job = jm.offers[0]
				for o in jm.offers:
					if (o as Job).distance_m < best.distance_m:
						best = o
				ok(jm.accept(best), "Angebot %d angenommen" % best.id)
			while jm.offers.size() < 2:
				var extra := jm._make_offer()
				if extra == null:
					break
				jm.offers.append(extra)
			t_mark = drv.t
			step = 1
		1:
			if drv.t < t_mark + 2.0:
				return
			var net: RoadNet = drv.world.net
			var data: Dictionary = Game.save_data()
			var jd: Dictionary = data.world.jobs
			var expect := {"active": {}, "offers": jd.offers.size()}
			var missing := (net.edges.size() + 100) << 4 | 7
			var i := 0
			for a in jd.active:
				expect.active[str(a.id)] = [a.center.x, a.center.y]
				if i == 0:
					a.key = missing
				else:
					a.key = _other_street(net, int(a.key))
				i += 1
			for o in jd.offers:
				o.key = missing
			ok(jd.active.size() == 2, "zwei laufende Aufträge im Spielstand")
			var f := FileAccess.open_compressed(Game.SAVE_DIR.path_join("spielstand.sav"), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
			f.store_var(data, false)
			f.close()
			var ef := FileAccess.open(Game.data_path(EXPECT_FILE), FileAccess.WRITE)
			ef.store_string(JSON.stringify(expect))
			ef.close()
			print("ALT Spielstand mit alten Schlüsseln geschrieben: ", JSON.stringify(expect))
			_finish("E2E OK altstand_save")


## A right-lane key of another, far away street.
func _other_street(net: RoadNet, key: int) -> int:
	var here: Array = net.lane_geo[key]
	var p: Vector2 = (here[0] as PackedVector2Array)[0]
	for k in net.lane_geo:
		var g: Array = net.lane_geo[k]
		if (int(k) >> 4) != (key >> 4) and (g[0] as PackedVector2Array)[0].distance_to(p) > 300.0:
			return int(k)
	return key


func _load_phase() -> void:
	var jm: JobManager = drv.world.jobs
	var txt := FileAccess.get_file_as_string(Game.data_path(EXPECT_FILE))
	var expect = JSON.parse_string(txt)
	if not expect is Dictionary:
		ok(false, "Erwartungsdatei fehlt (erst altstand_save laufen lassen)")
		_finish("")
		return
	for id_s in expect.active:
		var c := Vector2(float(expect.active[id_s][0]), float(expect.active[id_s][1]))
		var site: Site = jm.sites.get(int(id_s))
		ok(site != null, "Auftrag %s nach dem Laden wieder da" % id_s)
		if site:
			var d := site.lay.trench_center().distance_to(c)
			ok(d < TOL, "Auftrag %s an derselben Stelle (%.2f m daneben)" % [id_s, d])
	ok(jm.offers.size() == int(expect.offers), "Angebote erhalten (%d von %d)" % [jm.offers.size(), int(expect.offers)])
	for o in jm.offers:
		var lay := SiteLayout.new()
		ok(lay.setup(drv.world.net, (o as Job).key, (o as Job).s0, (o as Job).length, (o as Job).width,
			(o as Job).depth, (o as Job).pipe_d), "Angebot %d lässt sich annehmen" % (o as Job).id)
	_finish("E2E OK altstand")


func _finish(ok_line: String) -> void:
	if fails == 0 and ok_line != "":
		print(ok_line)
		drv.get_tree().quit(0)
	else:
		print("E2E FAIL altstand: %d Fehler" % fails)
		drv.get_tree().quit(1)
