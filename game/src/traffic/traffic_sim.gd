class_name TrafficSim
extends Node3D
## Microscopic traffic simulation (IDM car-following, junction control, closures and bottlenecks).
## Runs in fixed simulation steps; visuals are interpolated every frame.

const STEP := 0.1
const MAX_STEPS_PER_FRAME := 14
const S0 := 2.0          # IDM minimum gap
const T_HEAD := 1.2      # IDM time headway
const LOOKAHEAD := 90.0
const CYCLE := [24.0, 3.0, 2.0, 20.0, 3.0, 2.0]

var net: RoadNet
var router: Router
var agents: Array = []
var sim_time := 0.0
var focus := Vector3.ZERO
var radius := 700.0
var enabled := true
var max_traffic := 220
var density_scale := 1.0
var yaw_chord := 1.5      # body heading from the chord ±1.5 m around the agent (lanes, turn paths); 0 = plain tangent
var rng := RandomNumberGenerator.new()

var _acc := 0.0
var _next_id := 1
var _occ := {}            # occ key -> Array[[s, agent]] sorted by s
var _conn_occ := {}       # conn id -> Array[agent]
var _approach := {}       # conn id -> Array[[agent, dist, v]]
var _right_of := {}       # node -> {approach_end: approach_end_to_the_right}
var obstacles := {}       # lane key -> Array[{s0, s1, id}]
var detours := {}         # lane key -> Array[{s0, s1, pts: PackedVector2Array, zone: int, occ: String, vmax}]
var zones := {}           # bottleneck id -> {lanes: {lane_key: priority(int)}, inside: {lane_key: int}, last_lane, hold_t}
var stops_by_lane := {}   # lane key -> PackedFloat32Array of bus stop s
var jam_counter := {}     # tag -> accumulated vehicle-seconds of waiting near a site
var _models: Array = []   # Array[PackedScene or Mesh builders]
var _pool := {}           # model idx -> Array[Node3D]
var _cam: Camera3D
var _total_signals := 0
var _hq_edge := -1


func setup(n: RoadNet, bus_stops: Array) -> void:
	net = n
	router = Router.new()
	router.setup(n)
	rng.seed = 1234
	for ni in net.nodes.size():
		var nd: Dictionary = net.nodes[ni]
		if nd.ctrl == "rvl":
			_right_of[ni] = _compute_right_of(nd)
		if nd.ctrl == "signals":
			_total_signals += 1
	for bs in bus_stops:
		var near := router.nearest_lane(bs, 25.0, func(k): return net.edges[k >> 4].bus)
		if near.is_empty():
			continue
		var key: int = near.key
		if not stops_by_lane.has(key):
			stops_by_lane[key] = PackedFloat32Array()
		stops_by_lane[key].append(near.s)
	if net.hq_node >= 0:
		for er in net.nodes[net.hq_node].ends:
			_hq_edge = er >> 1
	TrafficModels.prepare()


func _compute_right_of(nd: Dictionary) -> Dictionary:
	var res := {}
	for inf in nd.infos:
		var heading: Vector2 = -inf.d
		var best := -1
		var best_score := INF
		for other in nd.infos:
			if other.ref == inf.ref:
				continue
			var d: Vector2 = other.d
			var cr := heading.x * d.y - heading.y * d.x
			var ang := atan2(cr, heading.dot(d))
			if ang > deg_to_rad(25.0) and ang < deg_to_rad(155.0):
				var sc := absf(ang - PI * 0.5)
				if sc < best_score:
					best_score = sc
					best = other.ref
		res[inf.ref] = best
	return res


# ------------------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------------------

## Returns [green_phase (0/1 or -1 for all red), amber: bool]
func signal_state(node: int) -> Array:
	var cyc := 0.0
	for c in CYCLE:
		cyc += c
	var t := fposmod(sim_time + float((node * 7919) % 50), cyc)
	if t < CYCLE[0]:
		return [0, false]
	t -= CYCLE[0]
	if t < CYCLE[1]:
		return [0, true]
	t -= CYCLE[1]
	if t < CYCLE[2]:
		return [-1, false]
	t -= CYCLE[2]
	if t < CYCLE[3]:
		return [1, false]
	t -= CYCLE[3]
	if t < CYCLE[4]:
		return [1, true]
	return [-1, false]


# ------------------------------------------------------------------------------------------
# Agents
# ------------------------------------------------------------------------------------------

func add_agent(kind: String, pieces: Array, start_s: float, player: Object = null) -> Agent:
	var ag := Agent.new()
	ag.id = _next_id
	_next_id += 1
	ag.kind = kind
	ag.route = pieces
	ag.pi = 0
	ag.s = start_s
	ag.player = player
	match kind:
		"truck":
			ag.length = 9.0
			ag.width = 2.5
			ag.vmax = 13.0
			ag.accel = 1.1
		"bus":
			ag.length = 12.0
			ag.width = 2.55
			ag.vmax = 13.0
			ag.accel = 1.0
		_:
			ag.length = 4.4
			ag.vmax = 15.5 + rng.randf_range(-1.5, 2.0)
			ag.accel = 2.1
	var pose := Router.piece_pose(pieces[0], start_s)
	ag.p_cur = Geo.v3(pose[0], 0.05 + Terrain.piece_y(pieces[0], pose[0]))
	ag.p_prev = ag.p_cur
	ag.pitch_cur = pitch_on(pieces[0], pose[0], pose[1], ag.length)
	ag.pitch_prev = ag.pitch_cur
	ag.yaw_cur = atan2(-pose[1].x, -pose[1].y)
	ag.yaw_prev = ag.yaw_cur
	agents.append(ag)
	if player == null:
		ag.model_idx = TrafficModels.pick(kind, rng)
		ag.visual = _take_visual(ag.model_idx)
		_place_visual(ag, 1.0)
	return ag


func remove_agent(ag: Agent) -> void:
	agents.erase(ag)
	if ag.visual and ag.player == null:
		_return_visual(ag.model_idx, ag.visual)
		ag.visual = null


func _take_visual(idx: int) -> Node3D:
	var arr: Array = _pool.get(idx, [])
	if not arr.is_empty():
		var v: Node3D = arr.pop_back()
		v.visible = true
		return v
	var node := TrafficModels.instance(idx)
	add_child(node)
	return node


func _return_visual(idx: int, v: Node3D) -> void:
	v.visible = false
	if not _pool.has(idx):
		_pool[idx] = []
	_pool[idx].append(v)


# ------------------------------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not enabled or net == null:
		return
	_acc += delta
	var steps := 0
	while _acc >= STEP and steps < MAX_STEPS_PER_FRAME:
		_acc -= STEP
		steps += 1
		_step(STEP)
	if steps == MAX_STEPS_PER_FRAME:
		_acc = 0.0
	var alpha := clampf(_acc / STEP, 0.0, 1.0)
	for ag in agents:
		if ag.player != null:
			ag.player.apply_agent_pose(ag, alpha)
		elif ag.visual:
			_place_visual(ag, alpha)


func _place_visual(ag: Agent, alpha: float) -> void:
	var p: Vector3 = ag.p_prev.lerp(ag.p_cur, alpha)
	ag.visual.position = p
	ag.visual.rotation.y = lerp_angle(ag.yaw_prev, ag.yaw_cur, alpha)
	ag.visual.rotation.x = lerpf(ag.pitch_prev, ag.pitch_cur, alpha)
	if ag.visual.has_meta("lights"):
		TrafficModels.set_lights(ag.visual, ag.braking, ag.turn_signal, sim_time)


func _step(dt: float) -> void:
	sim_time += dt
	_build_occupancy()
	for ag in agents:
		_drive(ag, dt)
	var i := agents.size() - 1
	while i >= 0:
		var ag: Agent = agents[i]
		if ag.despawn or (ag.finished and ag.player == null):
			remove_agent(ag)
		i -= 1
	_spawn_manage()


func _build_occupancy() -> void:
	for zid in zones:
		var z: Dictionary = zones[zid]
		z["waits_prev"] = z.get("waits_cur", {})
		z["waits_cur"] = {}
		z["inside"] = {}
	# zone occupancy is recounted every step (robust against despawns and route changes)
	for ag in agents:
		if ag.finished:
			continue
		var zp: Dictionary = ag.route[ag.pi]
		if zp.has("zone") and zones.has(zp.zone):
			var zi: Dictionary = zones[zp.zone].inside
			zi[zp.zone_lane] = zi.get(zp.zone_lane, 0) + 1
		elif ag.bottleneck_ok >= 0 and zones.has(ag.bottleneck_ok) and ag.pi + 1 < ag.route.size():
			# granted and approaching: holds the zone like a vehicle inside
			var zn: Dictionary = ag.route[ag.pi + 1]
			if zn.get("zone", -1) == ag.bottleneck_ok:
				var zi2: Dictionary = zones[ag.bottleneck_ok].inside
				zi2[zn.zone_lane] = zi2.get(zn.zone_lane, 0) + 1
	_occ.clear()
	_conn_occ.clear()
	_approach.clear()
	for ag in agents:
		if ag.finished:
			continue
		var pc: Dictionary = ag.route[ag.pi]
		var key: String = Router.piece_occ(pc, ag.s)
		if key != "":
			if not _occ.has(key):
				_occ[key] = []
			_occ[key].append([ag.s, ag])
		if pc.t == Agent.CONN:
			if not _conn_occ.has(pc.conn):
				_conn_occ[pc.conn] = []
			_conn_occ[pc.conn].append(ag)
		elif ag.pi + 1 < ag.route.size() and ag.route[ag.pi + 1].t == Agent.CONN:
			var dist: float = pc.s1 - ag.s
			if dist < 45.0:
				var ci: int = ag.route[ag.pi + 1].conn
				if not _approach.has(ci):
					_approach[ci] = []
				_approach[ci].append([ag, dist, ag.v])
	for k in _occ:
		var arr: Array = _occ[k]
		if arr.size() > 1:
			arr.sort_custom(func(x, y): return x[0] < y[0])


## Gap to the next vehicle ahead along the agent's route: returns [gap, leader_speed]
func _leader(ag: Agent) -> Array:
	var pc: Dictionary = ag.route[ag.pi]
	var key: String = Router.piece_occ(pc, ag.s)
	var best_gap := INF
	var lead_v := 0.0
	if key != "":
		var arr: Array = _occ.get(key, [])
		for e in arr:
			if e[0] > ag.s + 0.01 and e[1] != ag:
				var other: Agent = e[1]
				best_gap = (e[0] - other.length * 0.5) - (ag.s + ag.length * 0.5)
				lead_v = other.v
				break
	if best_gap < INF:
		return [best_gap, lead_v]
	var dist: float = pc.s1 - ag.s
	var i := ag.pi + 1
	while i < ag.route.size() and dist < LOOKAHEAD:
		var nx: Dictionary = ag.route[i]
		var k2: String = nx.occ
		if k2 != "":
			var arr2: Array = _occ.get(k2, [])
			for e in arr2:
				if e[0] >= nx.s0 - 0.5 and e[1] != ag:
					var other2: Agent = e[1]
					return [dist + (e[0] - nx.s0) - other2.length * 0.5 - ag.length * 0.5, other2.v]
		dist += nx.s1 - nx.s0
		i += 1
	return [INF, 0.0]


func _drive(ag: Agent, dt: float) -> void:
	if ag.finished:
		ag.v = 0.0
		return
	if ag.player == null:
		_extend_route(ag)
	else:
		if ag.hold > 0.0:
			ag.hold -= dt
			ag.v = 0.0
			ag.braking = true
			ag.p_prev = ag.p_cur
			ag.yaw_prev = ag.yaw_cur
			return
		if ag.stop_at_end and ag.remaining_route() < 0.3 and ag.v < 0.8:
			ag.v = 0.0
			ag.finished = true
			ag.player.on_route_finished.call_deferred(ag)
			return
		# direction change (forward <-> reverse): stop at the end of the piece, pause, continue
		if ag.pi + 1 < ag.route.size() and ag.route[ag.pi + 1].get("cusp", false):
			var te: float = ag.route[ag.pi].s1 - ag.s
			if te < 0.3 and ag.v < 0.4:
				ag.pi += 1
				ag.s = ag.route[ag.pi].s0
				ag.v = 0.0
				ag.hold = 0.9
				if ag.player.has_method("on_piece_enter"):
					ag.player.on_piece_enter(ag, ag.route[ag.pi])
				return
	var pc: Dictionary = ag.route[ag.pi]
	var v0: float = minf(ag.vmax, _speed_cap(pc, ag.s, 0.0))
	# anticipate slower pieces and bends ahead
	var dist_ahead: float = pc.s1 - ag.s
	var j := ag.pi + 1
	while j < ag.route.size() and dist_ahead < 70.0:
		var nx: Dictionary = ag.route[j]
		v0 = minf(v0, _speed_cap(nx, nx.s0, dist_ahead))
		dist_ahead += nx.s1 - nx.s0
		j += 1
	var lead := _leader(ag)
	var gap: float = lead[0]
	var lv: float = lead[1]
	# stop targets
	var stop_d := INF
	var reason := ""
	# junction clearance
	if ag.pi + 1 < ag.route.size():
		var nxt: Dictionary = ag.route[ag.pi + 1]
		var to_end: float = pc.s1 - ag.s
		if nxt.t == Agent.CONN and to_end < 40.0:
			if ag.permitted_conn != nxt.conn:
				if _may_enter(ag, nxt.conn, to_end):
					ag.permitted_conn = nxt.conn
				else:
					stop_d = to_end - ag.length * 0.5 - 0.4
					reason = "junction"
	# closures on the current and the following lane pieces
	var jam_id := -1
	# safety net: a company vehicle that has been stuck for a minute ignores closures/bottlenecks
	if ag.player != null and ag.wait_t > 60.0:
		ag.ignore_t = 20.0  # keep ignoring for a while, not just for one step
	ag.ignore_t = maxf(0.0, ag.ignore_t - dt)
	var give_up := ag.ignore_t > 0.0
	var obs := _obstacle_ahead(ag) if not give_up else [INF, -1]
	if obs[0] < stop_d:
		stop_d = obs[0]
		reason = "closure"
		jam_id = obs[1]
	# bottleneck zones
	var bz := _bottleneck_stop(ag) if not give_up else [INF, -1]
	if bz[0] < stop_d:
		stop_d = bz[0]
		reason = "bottleneck"
		jam_id = bz[1]
	# bus stops
	if ag.kind == "bus":
		var bs := _bus_stop_ahead(ag)
		if bs < stop_d:
			stop_d = bs
			reason = "busstop"
	# route end / cusp
	if ag.player != null:
		if ag.stop_at_end:
			# the IDM keeps S0 to a standing obstacle; route ends and cusps are reached exactly
			var rem := ag.remaining_route() + S0 - 0.15
			if rem < stop_d:
				stop_d = rem
				reason = "end"
		if ag.pi + 1 < ag.route.size() and ag.route[ag.pi + 1].get("cusp", false):
			var te2: float = pc.s1 - ag.s + S0 - 0.15
			if te2 < stop_d:
				stop_d = te2
				reason = "cusp"
	if stop_d < gap:
		gap = stop_d
		lv = 0.0
	# IDM
	var v := ag.v
	var acc := ag.accel * (1.0 - pow(v / maxf(0.5, v0), 4.0))
	if gap < INF:
		var ss: float = S0 + v * T_HEAD + v * (v - lv) / (2.0 * sqrt(ag.accel * ag.decel))
		acc -= ag.accel * pow(maxf(ss, 0.0) / maxf(gap, 0.1), 2.0)
	acc = clampf(acc, -8.0, ag.accel)
	if gap < 0.3:
		acc = minf(acc, -6.0)
	ag.a = acc
	ag.braking = acc < -0.7 or (v < 0.3 and gap < 8.0)
	v = maxf(0.0, v + acc * dt)
	var ds := v * dt
	if gap < INF:
		ds = minf(ds, maxf(0.0, gap - 0.05))
		if ds < v * dt * 0.5 and gap < 0.5:
			v = minf(v, ds / dt)
	ag.v = v
	if v < 0.2:
		ag.wait_t += dt
		if reason == "bus" or reason == "busstop":
			pass
	else:
		ag.wait_t = 0.0
	ag.yielding = reason == "junction"
	ag.reason = reason
	if jam_id >= 0 and v < 0.5:
		jam_counter[jam_id] = jam_counter.get(jam_id, 0.0) + dt
	_advance(ag, ds)
	_update_signals(ag)
	# pose
	ag.p_prev = ag.p_cur
	ag.yaw_prev = ag.yaw_cur
	var pose := Router.piece_pose(ag.route[ag.pi], ag.s)
	var dvec: Vector2 = _smooth_dir(ag, pose[0], pose[1])
	ag.p_cur = Geo.v3(pose[0], 0.05 + Terrain.piece_y(ag.route[ag.pi], pose[0]))
	ag.yaw_cur = atan2(-dvec.x, -dvec.y)
	ag.pitch_prev = ag.pitch_cur
	ag.pitch_cur = pitch_on(ag.route[ag.pi], pose[0], dvec, ag.length)


## Heading for the body: the chord between the route points yaw_chord behind and ahead of the agent.
## Lane and turn path polylines have small kinks (OSM nodes, joints between pieces); the tangent jumps
## there and the car would twitch (#5). Only on road pieces: manoeuvres (POLY, reversing, cusps) keep
## the exact tangent.
func _smooth_dir(ag: Agent, p: Vector2, tangent: Vector2) -> Vector2:
	if yaw_chord <= 0.0:
		return tangent
	var back: Variant = _route_point(ag, -yaw_chord)
	var ahead: Variant = _route_point(ag, yaw_chord)
	var a: Vector2 = back if back != null else p
	var b: Vector2 = ahead if ahead != null else p
	if (back == null and ahead == null) or a.distance_squared_to(b) < 0.25:
		return tangent
	# on an arc the chord is parallel to the tangent in its middle; where the line backtracks (a joint
	# that overshoots by a few centimetres) the tangent points backwards, the chord does not
	return (b - a).normalized()


## Point at arc length offset ds from the agent along its route, or null when a manoeuvre piece,
## a cusp or the end of the known route is in the way.
func _route_point(ag: Agent, ds: float) -> Variant:
	var i := ag.pi
	var s := ag.s + ds
	for _guard in 8:
		var pc: Dictionary = ag.route[i]
		if pc.t == Agent.POLY or pc.get("rev", false):
			return null
		if s > pc.s1:
			if i + 1 >= ag.route.size() or ag.route[i + 1].get("cusp", false):
				return null
			s = ag.route[i + 1].s0 + (s - pc.s1)
			i += 1
		elif s < pc.s0:
			if i == 0 or pc.get("cusp", false):
				return null
			s = ag.route[i - 1].s1 - (pc.s0 - s)
			i -= 1
		else:
			return Router.piece_pose(pc, s)[0]
	return null


## Highest speed allowed now for piece pc whose position s lies `ahead` metres in front of the agent:
## its own speed and the bends of its profile (Router.conn_profile), braking at 2 m/s².
func _speed_cap(pc: Dictionary, s: float, ahead: float) -> float:
	var cap: float = sqrt(pc.vmax * pc.vmax + 4.0 * ahead)
	for sec in pc.get("vprof", []):
		if sec[1] < s or sec[0] > pc.s1:   # passed, or behind the end of a partial lane piece
			continue
		cap = minf(cap, sqrt(sec[2] * sec[2] + 4.0 * (ahead + maxf(0.0, sec[0] - s))))
	return cap


func _advance(ag: Agent, ds: float) -> void:
	ag.s += ds
	while ag.s > ag.route[ag.pi].s1:
		var over: float = ag.s - ag.route[ag.pi].s1
		if ag.pi + 1 >= ag.route.size():
			ag.s = ag.route[ag.pi].s1
			ag.finished = true
			if ag.player:
				ag.player.on_route_finished.call_deferred(ag)
			return
		if ag.route[ag.pi + 1].get("cusp", false):
			ag.s = ag.route[ag.pi].s1
			return
		var leaving: Dictionary = ag.route[ag.pi]
		if leaving.t == Agent.CONN:
			ag.permitted_conn = -1
		ag.pi += 1
		var entering: Dictionary = ag.route[ag.pi]
		ag.s = entering.s0 + over
		if entering.has("zone") and entering.zone >= 0:
			_zone_enter(ag, entering)
		if leaving.has("zone") and leaving.zone >= 0:
			_zone_leave(ag, leaving)
		if ag.player and entering.tag != "" and ag.player.has_method("on_piece_enter"):
			ag.player.on_piece_enter(ag, entering)
	# trim consumed pieces for long-lived agents
	if ag.pi > 6 and ag.player == null:
		ag.route = ag.route.slice(ag.pi - 1)
		ag.pi = 1


func _update_signals(ag: Agent) -> void:
	ag.turn_signal = 0
	var dist: float = ag.route[ag.pi].s1 - ag.s
	var i := ag.pi
	if ag.route[i].t == Agent.CONN:
		ag.turn_signal = _turn_dir(ag.route[i])
		return
	var j := i + 1
	while j < ag.route.size() and dist < 35.0:
		var pc: Dictionary = ag.route[j]
		if pc.t == Agent.CONN:
			ag.turn_signal = _turn_dir(pc)
			return
		if pc.t == Router.BLEND:
			ag.turn_signal = 1 if (pc.key2 & 7) > (pc.key & 7) else -1
			return
		dist += pc.s1 - pc.s0
		j += 1
	if ag.route[i].t == Router.BLEND:
		var b: Dictionary = ag.route[i]
		ag.turn_signal = 1 if (b.key2 & 7) > (b.key & 7) else -1


func _turn_dir(pc: Dictionary) -> int:
	var c: Dictionary = net.connectors[pc.conn]
	if c.turn == "L" or c.turn == "U":
		return -1
	if c.turn == "R":
		return 1
	return 0


# ------------------------------------------------------------------------------------------
# Junction rules
# ------------------------------------------------------------------------------------------

func _may_enter(ag: Agent, ci: int, to_end: float) -> bool:
	var c: Dictionary = net.connectors[ci]
	var nd: Dictionary = net.nodes[c.node]
	# don't block the junction: room on the target lane
	var tkey := "L%d" % c.to
	var arr: Array = _occ.get(tkey, [])
	for e in arr:
		var o: Agent = e[1]
		if e[0] - o.length * 0.5 < ag.length + 2.5 and o.v < 1.5 and o != ag:
			return false
		break
	# conflicting connectors occupied
	for cj in c.conflicts:
		var occ: Array = _conn_occ.get(cj, [])
		for o in occ:
			if o != ag:
				return false
	if ag.wait_t > 25.0:
		return true
	match nd.ctrl:
		"signals":
			var st := signal_state(c.node)
			if st[0] != c.phase:
				return false
			if st[1] and to_end > 8.0:
				return false
			if c.turn == "L" or c.turn == "U":
				for cj in c.conflicts:
					var oc: Dictionary = net.connectors[cj]
					if oc.phase == c.phase and oc.turn in ["S", "R"]:
						for e2 in _approach.get(cj, []):
							if e2[1] < 28.0 and e2[0] != ag:
								return false
			return true
		"priority":
			var major: bool = c.approach_end in nd.get("major_ends", [])
			for cj in c.conflicts:
				var oc2: Dictionary = net.connectors[cj]
				var o_major: bool = oc2.approach_end in nd.get("major_ends", [])
				if major and not o_major:
					continue
				if major and o_major:
					# left turn from the main road yields to oncoming traffic
					if not (c.turn in ["L", "U"] and oc2.turn in ["S", "R"]):
						continue
				for e3 in _approach.get(cj, []):
					var other: Agent = e3[0]
					if other == ag:
						continue
					if e3[1] < 30.0 + e3[2] * 2.0 and (e3[2] > 1.0 or e3[1] < 6.0) and not other.yielding:
						return false
			return true
		"rvl":
			var right: int = _right_of.get(c.node, {}).get(c.approach_end, -1)
			if right < 0:
				return true
			for cj in c.conflicts:
				var oc3: Dictionary = net.connectors[cj]
				if oc3.approach_end != right:
					continue
				for e4 in _approach.get(cj, []):
					var other2: Agent = e4[0]
					if other2 == ag:
						continue
					if e4[1] < 22.0:
						# deadlock breaker: if the other is itself waiting long, alternate by id
						if other2.yielding and ag.wait_t > 4.0 and other2.wait_t > 4.0 and ag.id < other2.id:
							continue
						return false
			return true
	return true


# ------------------------------------------------------------------------------------------
# Closures, detours and bottlenecks (used by construction sites)
# ------------------------------------------------------------------------------------------

func set_obstacle(lane_key: int, s0: float, s1: float, id: int) -> void:
	if not obstacles.has(lane_key):
		obstacles[lane_key] = []
	for o in obstacles[lane_key]:
		if o.id == id:
			o.s0 = s0
			o.s1 = s1
			return
	obstacles[lane_key].append({"s0": s0, "s1": s1, "id": id})


## True if no agent occupies lane `key` between s0 and s1 (exclude = an agent to ignore).
func lane_clear(key: int, s0: float, s1: float, exclude: Agent = null) -> bool:
	for ag in agents:
		if ag == exclude or ag.finished:
			continue
		var pc: Dictionary = ag.route[ag.pi]
		var k := -1
		if pc.t == Agent.LANE:
			k = pc.key
		elif pc.t == Router.BLEND:
			k = pc.key if ag.s < pc.mid else pc.key2
		if k != key:
			continue
		if ag.s + ag.length * 0.5 > s0 and ag.s - ag.length * 0.5 < s1:
			return false
	return true


func clear_obstacles(id: int) -> void:
	for k in obstacles.keys():
		var arr: Array = obstacles[k]
		for i in range(arr.size() - 1, -1, -1):
			if arr[i].id == id:
				arr.remove_at(i)
		if arr.is_empty():
			obstacles.erase(k)


## [distance from the agent's front to the first obstacle ahead, obstacle id] ([INF, -1] if none).
func _obstacle_ahead(ag: Agent) -> Array:
	if obstacles.is_empty():
		return [INF, -1]
	var dist := 0.0
	var i := ag.pi
	# a company vehicle never waits for the safety area it set up for its own manoeuvre
	var own_id := -1
	if ag.player != null:
		own_id = int(ag.player.get("_man_obs_id"))
	while i < ag.route.size() and dist < LOOKAHEAD:
		var pc: Dictionary = ag.route[i]
		if pc.t == Agent.LANE or pc.t == Router.BLEND:
			var key: int = pc.key
			if obstacles.has(key):
				for o in obstacles[key]:
					if o.id == own_id:
						continue
					var from_s: float = ag.s if i == ag.pi else pc.s0
					if i == ag.pi and ag.s > o.s0 + 0.5:
						continue  # already inside (closure appeared around it): let it leave
					if o.s1 > from_s and o.s0 < pc.s1:
						var d: float = dist + maxf(0.0, o.s0 - from_s) - ag.length * 0.5 - 1.0
						return [maxf(0.0, d), o.id]
		dist += pc.s1 - (ag.s if i == ag.pi else pc.s0)
		i += 1
	return [INF, -1]


func set_detour(lane_key: int, s0: float, s1: float, pts: PackedVector2Array, zone: int, vmax: float) -> void:
	if not detours.has(lane_key):
		detours[lane_key] = []
	detours[lane_key] = detours[lane_key].filter(func(d): return d.zone != zone)
	detours[lane_key].append({"s0": s0, "s1": s1, "pts": pts, "zone": zone, "vmax": vmax, "occ": "Z%d_%d" % [zone, lane_key]})
	_refresh_routes()


func clear_detours(zone: int) -> void:
	for k in detours.keys():
		detours[k] = detours[k].filter(func(d): return d.zone != zone)
		if detours[k].is_empty():
			detours.erase(k)
	zones.erase(zone)
	_refresh_routes()


func set_zone(zone: int, lane_priorities: Dictionary) -> void:
	zones[zone] = {"lanes": lane_priorities, "inside": {}, "hold": -1, "hold_t": 0.0}


## Re-split future lane pieces of all agents so new/removed detours apply.
func _refresh_routes() -> void:
	for ag in agents:
		if ag.finished:
			continue
		var cur: Dictionary = ag.route[ag.pi]
		if cur.t == Agent.POLY and cur.has("zone"):
			continue  # inside a detour right now: leave it
		var past: Array = ag.route.slice(0, ag.pi)
		var cur_tag := ""
		var logical_cur := cur
		if cur.t == Agent.LANE and cur.has("orig_s0"):
			cur_tag = "%d_%.2f" % [cur.key, cur.orig_s0]
			logical_cur = router.lane_piece(cur.key, cur.orig_s0, cur.orig_s1)
		var logical_rest: Array = []
		var last_tag := cur_tag
		for k in range(ag.pi + 1, ag.route.size()):
			var pc: Dictionary = ag.route[k]
			if pc.t == Agent.POLY and pc.has("zone"):
				continue
			if pc.t == Agent.LANE and pc.has("orig_s0"):
				var tag := "%d_%.2f" % [pc.key, pc.orig_s0]
				if tag == last_tag:
					continue
				last_tag = tag
				pc = router.lane_piece(pc.key, pc.orig_s0, pc.orig_s1)
			else:
				last_tag = ""
			logical_rest.append(pc)
		var new_route: Array = past
		var exp := expand_detours(logical_cur) if logical_cur.t == Agent.LANE else [logical_cur]
		var placed := false
		for idx in exp.size():
			var e: Dictionary = exp[idx]
			if ag.s >= e.s0 - 0.01 and ag.s <= e.s1 + 0.01 and e.t != Agent.POLY:
				new_route = new_route + exp.slice(idx)
				placed = true
				break
		if not placed:
			new_route = new_route + [cur]
		var new_pi := past.size()
		for pc2 in logical_rest:
			new_route.append_array(expand_detours(pc2))
		ag.route = new_route
		ag.pi = new_pi
		if ag.player:
			ag.player.on_route_changed(ag)


static func _merge_lane_runs(pieces: Array) -> Array:
	return pieces


## Split a lane piece around detours. Returns one or more pieces.
func expand_detours(pc: Dictionary) -> Array:
	if pc.t != Agent.LANE or not detours.has(pc.key):
		return [pc]
	var out: Array = []
	var cur_s: float = pc.s0
	var dlist: Array = detours[pc.key].duplicate()
	dlist.sort_custom(func(a, b): return a.s0 < b.s0)
	for d in dlist:
		if d.s1 <= cur_s or d.s0 >= pc.s1:
			continue
		if d.s0 < cur_s - 0.5:
			continue  # starting inside a detour: keep the lane (rare)
		if d.s0 - cur_s > 0.05:
			var lp := router.lane_piece(pc.key, cur_s, d.s0)
			lp["orig_s0"] = pc.s0
			lp["orig_s1"] = pc.s1
			out.append(lp)
		var pp := Router.poly_piece(d.pts, d.vmax)
		pp.occ = d.occ
		pp["zone"] = d.zone
		pp["zone_lane"] = pc.key
		out.append(pp)
		cur_s = d.s1
	if pc.s1 - cur_s > 0.05:
		var lp2 := router.lane_piece(pc.key, cur_s, pc.s1)
		lp2["orig_s0"] = pc.s0
		lp2["orig_s1"] = pc.s1
		out.append(lp2)
	return out


func _bottleneck_stop(ag: Agent) -> Array:
	if zones.is_empty():
		return [INF, -1]
	var pc: Dictionary = ag.route[ag.pi]
	if pc.has("zone"):
		return [INF, -1]
	if ag.pi + 1 >= ag.route.size():
		return [INF, -1]
	var nx: Dictionary = ag.route[ag.pi + 1]
	if not nx.has("zone") or not zones.has(nx.zone):
		return [INF, -1]
	var to_end: float = pc.s1 - ag.s
	if to_end > 45.0:
		return [INF, -1]
	if ag.bottleneck_ok == nx.zone:
		return [INF, -1]
	var z: Dictionary = zones[nx.zone]
	var my_lane: int = nx.zone_lane
	var my_prio: int = z.lanes.get(my_lane, 0)
	var stop := [maxf(0.0, to_end - ag.length * 0.5 - 0.5), nx.zone]
	var waits_prev: Dictionary = z.get("waits_prev", {})
	var waits_cur: Dictionary = z.get("waits_cur", {})
	z["waits_cur"] = waits_cur
	# anyone from another lane inside?
	for lk in z.inside:
		if lk != my_lane and z.inside[lk] > 0:
			waits_cur[my_lane] = maxf(waits_cur.get(my_lane, 0.0), ag.wait_t)
			return stop
	# fairness: a queue on another lane that has waited long goes first
	var mine: float = maxf(waits_prev.get(my_lane, 0.0), ag.wait_t)
	for lk in waits_prev:
		if lk != my_lane and waits_prev[lk] > 14.0 and waits_prev[lk] > mine + 2.0:
			waits_cur[my_lane] = maxf(waits_cur.get(my_lane, 0.0), ag.wait_t)
			return stop
	# priority side approaching? (308 side has priority over 208 side)
	if my_prio < 1 and ag.wait_t < 20.0:
		for other in agents:
			if other == ag or other.finished or other.pi + 1 >= other.route.size():
				continue
			var onx: Dictionary = other.route[other.pi + 1]
			if onx.has("zone") and onx.zone == nx.zone and onx.zone_lane != my_lane:
				var od: float = other.route[other.pi].s1 - other.s
				if od < 35.0 and z.lanes.get(onx.zone_lane, 0) > my_prio and other.v > 0.5:
					waits_cur[my_lane] = maxf(waits_cur.get(my_lane, 0.0), ag.wait_t)
					return stop
	ag.bottleneck_ok = nx.zone
	z.inside[my_lane] = z.inside.get(my_lane, 0) + 1
	return [INF, -1]


func _zone_enter(ag: Agent, pc: Dictionary) -> void:
	if not zones.has(pc.zone):
		return
	pass


func _zone_leave(ag: Agent, pc: Dictionary) -> void:
	ag.bottleneck_ok = -1
	if not zones.has(pc.zone):
		return
	pass


func _bus_stop_ahead(ag: Agent) -> float:
	var pc: Dictionary = ag.route[ag.pi]
	if pc.t != Agent.LANE or not stops_by_lane.has(pc.key):
		return INF
	for s in stops_by_lane[pc.key]:
		var sk := "%d_%d" % [pc.key, int(s)]
		if ag.served_stops.has(sk):
			continue
		var d: float = s - ag.s
		if d < -1.0:
			continue
		if d < 1.5 and ag.v < 0.3:
			ag.dwell += STEP
			if ag.dwell > 14.0:
				ag.served_stops[sk] = true
				ag.dwell = 0.0
				return INF
		return maxf(0.0, d)
	return INF


# ------------------------------------------------------------------------------------------
# Spawning / random walk
# ------------------------------------------------------------------------------------------

func traffic_count() -> int:
	var n := 0
	for ag in agents:
		if ag.player == null:
			n += 1
	return n


func _daytime_factor() -> float:
	var h := Clock.hour()
	if h < 5.0:
		return 0.18
	if h < 6.5:
		return 0.35
	if h < 9.0:
		return 1.0
	if h < 15.5:
		return 0.72
	if h < 18.5:
		return 1.0
	if h < 21.0:
		return 0.6
	return 0.32


func _spawn_manage() -> void:
	var target := int(clampf(PI * radius * radius / 7500.0, 25.0, float(max_traffic)) * _daytime_factor() * density_scale)
	if Clock.speed_index >= 3:
		target = int(target * 0.6)
	var count := 0
	for ag in agents:
		if ag.player != null:
			continue
		count += 1
		if Vector2(ag.p_cur.x - focus.x, ag.p_cur.z - focus.z).length() > radius * 1.3:
			ag.despawn = true
		elif ag.wait_t > 70.0 and ag.visual and not _visible(ag.p_cur):
			ag.despawn = true
		elif ag.wait_t > 150.0:
			ag.despawn = true
	var tries := 0
	while count < target and tries < 6:
		tries += 1
		if _try_spawn():
			count += 1


func _visible(p: Vector3) -> bool:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return false
	return _cam.is_position_in_frustum(p) and _cam.global_position.distance_to(p) < 900.0


func _try_spawn() -> bool:
	var ang := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	var p := Vector2(focus.x + cos(ang) * r, focus.z + sin(ang) * r)
	var cell := Vector2i(int(floor(p.x / Router.CELL)), int(floor(p.y / Router.CELL)))
	var keys: Array = router.lane_grid.get(cell, [])
	if keys.is_empty():
		return false
	var key: int = keys[rng.randi() % keys.size()]
	var e: Dictionary = net.edges[key >> 4]
	if (key >> 4) == _hq_edge:
		return false
	if e.cls in ["service", "living_street"] and rng.randf() < 0.8:
		return false
	var ln := router.lane_len(key)
	if ln < 12.0:
		return false
	var s := rng.randf_range(2.0, ln - 2.0)
	var occ: Array = _occ.get("L%d" % key, [])
	for o in occ:
		if absf(o[0] - s) < 16.0:
			return false
	if obstacles.has(key):
		for ob in obstacles[key]:
			if s > ob.s0 - 20.0 and s < ob.s1 + 5.0:
				return false
	var kind := "car"
	var roll := rng.randf()
	if e.bus and roll < 0.12:
		kind = "bus"
	elif roll < 0.1:
		kind = "truck"
	var pieces := expand_detours(router.lane_piece(key, 0.0, ln))
	# start piece must contain s
	var start_idx := 0
	for i in pieces.size():
		if s >= pieces[i].s0 and s <= pieces[i].s1 and pieces[i].t == Agent.LANE:
			start_idx = i
			break
	if pieces[start_idx].t != Agent.LANE:
		return false
	var ag := add_agent(kind, pieces.slice(start_idx), s)
	ag.v = minf(ag.vmax, e.speed) * 0.6
	return true


func _extend_route(ag: Agent) -> void:
	var guard := 0
	while ag.route.size() - ag.pi < 4 and guard < 4:
		guard += 1
		var last: Dictionary = ag.route[ag.route.size() - 1]
		if last.t == Agent.CONN:
			var c: Dictionary = net.connectors[last.conn]
			var ln := router.lane_len(c.to)
			for p in expand_detours(router.lane_piece(c.to, 0.0, ln)):
				ag.route.append(p)
			continue
		var key := -1
		if last.t == Agent.LANE:
			key = last.key
		elif last.t == Router.BLEND:
			key = last.key2
		elif last.t == Agent.POLY and last.has("zone_lane"):
			key = last.zone_lane
		if key < 0:
			return
		var outs: Array = net.lane_out.get(key, [])
		if outs.is_empty():
			ag.despawn = ag.player == null and ag.route.size() - ag.pi <= 1
			return
		var ci := _choose_conn(ag, outs)
		ag.route.append(router.conn_piece(ci))


func _choose_conn(ag: Agent, outs: Array) -> int:
	var total := 0.0
	var weights: Array = []
	for ci in outs:
		var c: Dictionary = net.connectors[ci]
		var e: Dictionary = net.edges[c.to >> 4]
		var w := 1.0
		if c.turn == "S":
			w *= 2.4
		elif c.turn == "U":
			w *= 0.05
		w *= 1.0 + float(e.rank % 20) * 0.35
		if e.cls in ["service", "living_street"]:
			w *= 0.08
		if (c.to >> 4) == _hq_edge:
			w *= 0.000001
		if ag.kind == "bus":
			w *= 6.0 if e.bus else 0.2
		if ag.kind == "truck" and e.cls in ["residential", "living_street", "service"]:
			w *= 0.3
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in outs.size():
		r -= weights[i]
		if r <= 0.0:
			return outs[i]
	return outs[outs.size() - 1]


## Nose-up angle of a vehicle of length l at p heading d on route piece pc (0 on flat maps, #8).
static func pitch_on(pc: Dictionary, p: Vector2, d: Vector2, l: float) -> float:
	if Terrain.cur == null:
		return 0.0
	var half := maxf(1.0, l * 0.4)
	return atan2(Terrain.piece_y(pc, p + d * half) - Terrain.piece_y(pc, p - d * half), half * 2.0)
