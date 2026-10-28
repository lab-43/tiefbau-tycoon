class_name Agent
extends RefCounted
## One simulated road user (traffic car, truck, bus or a player vehicle).
## Position is (piece index, arc length s on that piece's polyline).

enum { LANE, CONN, POLY }

var id := 0
var kind := "car"            # car | truck | bus | player
var length := 4.5
var width := 1.8
var vmax := 13.9
var accel := 2.0
var decel := 3.0
var route: Array = []        # pieces (Dictionary)
var pi := 0
var s := 0.0
var v := 0.0
var a := 0.0
var visual: Node3D
var player: Object = null    # Vehicle node for player agents
var model_idx := 0
var wait_t := 0.0
var ignore_t := 0.0   # safety net: seconds left in which closures/bottlenecks are ignored
var in_conn := -1
var turn_signal := 0         # -1 left, 1 right
var braking := false
var finished := false
var despawn := false
var dwell := 0.0
var served_stops := {}
var stop_at_end := true
var permitted_conn := -1     # connector the agent got clearance for
var yielding := false
var stuck_t := 0.0
var bottleneck := -1         # bottleneck zone id currently inside
var bottleneck_ok := -1      # zone the agent got permission for
var hold := 0.0              # forced standstill (gear change at a cusp)
var zone_wait := -1          # zone the agent is currently queued at
var reason := ""             # why the agent is braking (debug/UI)
# interpolation
var p_prev := Vector3.ZERO
var p_cur := Vector3.ZERO
var yaw_prev := 0.0
var yaw_cur := 0.0


static func make_piece(type: int, key: int, pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, vmax: float, occ: String, conn := -1, node := -1) -> Dictionary:
	return {"t": type, "key": key, "pts": pts, "cum": cum, "s0": s0, "s1": s1, "vmax": vmax, "occ": occ,
		"conn": conn, "node": node, "rev": false, "tag": ""}


func piece() -> Dictionary:
	return route[pi]


func remaining_on_piece() -> float:
	return route[pi].s1 - s


func pose() -> Array:
	var pc: Dictionary = route[pi]
	var smp := Geo.sample(pc.pts, pc.cum, s)
	var d: Vector2 = smp[1]
	if pc.rev:
		d = -d
	return [smp[0], d]


func remaining_route() -> float:
	var r: float = route[pi].s1 - s
	for i in range(pi + 1, route.size()):
		r += route[i].s1 - route[i].s0
	return r
