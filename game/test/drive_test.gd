extends Node
## Calm driving check (#5): runs the traffic simulation on junction fixtures (testdata/kreuzungen).
## Counts per km driven:
##   twitches  – the turn rate of the body changes by more than 2° within one step (0.1 s): the body
##               jerked at a kink of a lane or turn path,
##   too fast  – lateral acceleration above 4.5 m/s² (a car racing through a tight bend).
## U-turns are left out. The same traffic without heading smoothing (TrafficSim.yaw_chord = 0) is
## printed for comparison.
## usage: godot --headless --path game res://test/drive_test.tscn -- --fixtures=<dir> [--only=a,b] [--seconds=40] [--chord=m] [--v]
## (a scene, not -s: TrafficSim needs the Clock autoload)  ·  tools/test.sh fahren
## Prints "FAHREN OK …" or "FAHREN FAIL …" (exit code 1).

const MAX_TWITCH_PER_KM := 1.0
const MAX_FAST_PER_KM := 2.5
const TWITCH := 0.035      # rad, change of the per-step yaw between two steps
const A_LAT := 4.5         # m/s²


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var dir: String = args.get("fixtures", "")
	var only: PackedStringArray = str(args.get("only", "meldung5_billhorn,deichtorplatz,willy_brandt")).split(",", false)
	var seconds: float = float(args.get("seconds", "40"))
	var verbose: bool = args.has("v")
	var spec = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("kreuzungen.json")))
	if typeof(spec) != TYPE_DICTIONARY:
		print("FAHREN FAIL kreuzungen.json fehlt")
		get_tree().quit(1)
		return
	var tot := {"glatt": [0.0, 0, 0], "roh": [0.0, 0, 0]}
	for fx in spec.kreuzungen:
		if not (str(fx.id) in only):
			continue
		Geo.setup(float(fx.lat), float(fx.lon))
		var data := OsmParser.new().parse_pbf(dir.path_join(fx.id + ".osm.pbf"), 300.0)
		var net := RoadNet.new()
		net.build(data, {})
		for variant in ["glatt", "roh"]:
			var r := _run(net, float(args.get("chord", "-1")) if variant == "glatt" else 0.0, seconds, verbose and variant == "glatt")
			for i in 3:
				tot[variant][i] += r[i]
			print("  %s %s: %.1f km, %d Rucke, %d zu schnell" % [fx.id, variant, r[0], r[1], r[2]])
	var km: float = maxf(0.01, tot.glatt[0])
	var tw: float = tot.glatt[1] / km
	var fast: float = tot.glatt[2] / km
	var tw_raw: float = tot.roh[1] / maxf(0.01, tot.roh[0])
	var msg := "%.2f Rucke/km (ohne Glättung %.2f), %.2f zu schnell/km, %.1f km" % [tw, tw_raw, fast, km]
	if km < 1.0:
		print("FAHREN FAIL kaum gefahren (%.2f km)" % km)
		get_tree().quit(1)
	elif tw > MAX_TWITCH_PER_KM or fast > MAX_FAST_PER_KM:
		print("FAHREN FAIL ", msg, " (Grenzen %.1f / %.1f)" % [MAX_TWITCH_PER_KM, MAX_FAST_PER_KM])
		get_tree().quit(1)
	else:
		print("FAHREN OK ", msg)
		get_tree().quit(0)


## Returns [km driven, twitches, too fast].
func _run(net: RoadNet, chord: float, seconds: float, verbose: bool) -> Array:
	var sim := TrafficSim.new()
	add_child(sim)
	sim.setup(net, [])
	if chord >= 0.0:
		sim.yaw_chord = chord
	sim.radius = 220.0
	sim.max_traffic = 60
	var km := 0.0
	var twitches := 0
	var fast := 0
	var last := {}   # agent id -> yaw change of its previous step
	var steps := int(seconds / TrafficSim.STEP)
	for i in steps:
		sim._step(TrafficSim.STEP)
		var now := {}
		for ag: Agent in sim.agents:
			var ds := Vector2(ag.p_cur.x - ag.p_prev.x, ag.p_cur.z - ag.p_prev.z).length()
			if ds < 0.05 or ds > 5.0:
				continue
			var dyaw := wrapf(ag.yaw_cur - ag.yaw_prev, -PI, PI)
			now[ag.id] = dyaw
			km += ds / 1000.0
			var pc: Dictionary = ag.route[ag.pi]
			if pc.t == Agent.CONN and net.connectors[pc.conn].turn == "U":
				continue
			var v := ds / TrafficSim.STEP
			var what := ""
			if last.has(ag.id) and absf(dyaw - last[ag.id]) > TWITCH:
				twitches += 1
				what = "Ruck"
			elif v * v * absf(dyaw) / ds > A_LAT:
				fast += 1
				what = "schnell"
			if verbose and what != "":
				var kind: String = ["LANE", "CONN", "POLY", "BLEND"][pc.t] + ("_" + str(net.connectors[pc.conn].turn) if pc.t == Agent.CONN else "")
				print("    %s %s v=%.1f r=%.1f d=%.1f° bei %s s=%.1f/%.1f" % [what, kind, v, ds / maxf(0.0001, absf(dyaw)),
					rad_to_deg(dyaw - last.get(ag.id, 0.0)), str(Vector2(ag.p_cur.x, ag.p_cur.z).round()), ag.s - pc.s0, pc.s1 - pc.s0])
		last = now
	sim.free()
	return [km, twitches, fast]
