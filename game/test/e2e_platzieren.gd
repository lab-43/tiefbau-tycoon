extends RefCounted
## e2e scenario "platzieren" (#33): samples points along every street lane of the map and asks the
## job manager whether a contract could be placed there (debug "Auftrag platzieren"). Prints the share
## of good spots and the reasons for the others.

var drv: Node
var step := 0


func tick(_delta: float) -> void:
	var w: World = drv.world
	var jm: JobManager = w.jobs
	if step == 0:
		if drv.t < 1.0:
			return
		step = 1
		var net: RoadNet = w.net
		var reasons := {}
		var n := 0
		var good := 0
		for key in net.lane_geo:
			var ei: int = key >> 4
			var e: Dictionary = net.edges[ei]
			if e.cls in ["motorway", "motorway_link", "trunk", "trunk_link", "service"]:
				continue
			if e.get("under", false):
				continue
			var g: Array = net.lane_geo[key]
			var cum: PackedFloat32Array = g[1]
			var ln: float = cum[cum.size() - 1]
			var s := 5.0
			while s < ln - 5.0:
				var p: Vector2 = Geo.sample(g[0], cum, s)[0]
				n += 1
				var r: Dictionary = jm.offer_at(p)
				if r.has("job"):
					good += 1
					jm.offers.erase(r.job)
				else:
					var why: String = str(r.error).replace("Hier geht keine Baustelle: ", "")
					var rx := RegEx.create_from_string("[0-9]+ m")
					why = rx.sub(why, "N m", true)
					if why.begins_with("Hinter der Grube"):
						var en: int = net.lane_end_node(key)
						why += " [Ende: %s]" % ("Übergang" if net.nodes[en].ends.size() == 2 else "Kreuzung")
					reasons[why] = int(reasons.get(why, 0)) + 1
				s += 25.0
		print("PLATZ %d Stellen, %d gehen (%.0f %%)" % [n, good, 100.0 * good / maxf(1.0, n)])
		var ks := reasons.keys()
		ks.sort_custom(func(a, b): return reasons[a] > reasons[b])
		for k in ks:
			print("PLATZ   %5d  %s" % [reasons[k], k])
		print("E2E OK platzieren")
		drv.get_tree().quit(0)
