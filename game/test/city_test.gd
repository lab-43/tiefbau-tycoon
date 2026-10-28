extends Node3D
## Bakes the Utrecht fixture and frames a camera. Args: --cam=px,py,pz,tx,ty,tz  --hq=x,z
func _ready() -> void:
	var cam_args := [0.0, 2400.0, 1800.0, 0.0, 0.0, 0.0]
	var hq := Vector2(INF, INF)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			cam_args = Array(a.substr(6).split(",")).map(func(x): return float(x))
		if a.begins_with("--hq="):
			var p := a.substr(5).split(",")
			hq = Vector2(float(p[0]), float(p[1]))
	var meta := {"center_lat": 52.0907, "center_lon": 5.1214, "size_m": 6000.0}
	if hq.x != INF:
		meta["hq"] = {"x": hq.x, "z": hq.y}
	var t0 := Time.get_ticks_msec()
	var mb := MapBuilder.new()
	var res := mb.bake(meta, "res://test_fixtures/utrecht/osm")
	var t1 := Time.get_ticks_msec()
	var root := MapBuilder.create_city_root(res)
	add_child(root)
	for ck in res.roads:
		MapBuilder.add_chunk_layers(root, ck, res.roads[ck])
	for ck in res.city:
		MapBuilder.add_chunk_layers(root, ck, res.city[ck])
	for ck in res.trees:
		MapBuilder.add_instances(root, ck, "trees", res.trees[ck])
	for ck in res.lamps:
		MapBuilder.add_instances(root, ck, "lamps", res.lamps[ck])
	var t2 := Time.get_ticks_msec()
	var net: RoadNet = res.net
	print("BAKE ms=", t1 - t0, " scene ms=", t2 - t1, " nodes=", net.nodes.size(), " edges=", net.edges.size(), " conns=", net.connectors.size(), " lanes=", net.lane_geo.size(), " stats=", res.stats)
	var ctrl := {}
	for n in net.nodes:
		ctrl[n.ctrl] = ctrl.get(n.ctrl, 0) + 1
	print("CTRL ", ctrl)
	var focus := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--focus="):
			focus = a.substr(8)
	if focus != "":
		var best := -1
		var best_d := INF
		for ni in net.nodes.size():
			var n: Dictionary = net.nodes[ni]
			if n.ctrl == focus and n.ends.size() >= 4:
				var d: float = n.pos.length()
				if d < best_d and d > float(cam_args[0]):
					best_d = d
					best = ni
		if best >= 0:
			var P: Vector2 = net.nodes[best].pos
			print("FOCUS node ", best, " at ", P, " ends=", net.nodes[best].ends.size())
			cam_args = [P.x + 35.0, 45.0, P.y + 45.0, P.x, 0.0, P.y]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.45, 0.62, 0.85)
	psm.sky_horizon_color = Color(0.78, 0.84, 0.9)
	psm.ground_horizon_color = Color(0.78, 0.84, 0.9)
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 3.0
	e.ssao_intensity = 2.5
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.fog_enabled = true
	e.fog_density = 0.000015
	e.fog_light_color = Color(0.8, 0.85, 0.9)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1200.0
	add_child(sun)
	var cam := Camera3D.new()
	cam.far = 12000.0
	cam.near = 0.5
	cam.fov = 40.0
	add_child(cam)
	cam.position = Vector3(cam_args[0], cam_args[1], cam_args[2])
	cam.look_at(Vector3(cam_args[3], cam_args[4], cam_args[5]))
	cam.current = true
