class_name World
extends Node3D
## The playable world: city, environment, HQ, traffic, fleet, jobs and sites.

var map_service: MapService
var net: RoadNet
var router: Router
var city: Node3D
var hq: HQ
var traffic: TrafficSim
var camera_rig: CameraRig
var day_night: DayNight
var env_node: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fleet: Fleet
var jobs: JobManager
var light_pool: LightPool
var signals_view: SignalHeads
var bounds := Rect2()
var hq_info := {}
var tool: Object = null          # active placement tool (receives input first)
var marker_command: Callable     # screen markers (#7): right click on a marker -> true if handled
var _terrain: Terrain = null     # ground heights of this map (#8)


func setup(ms: MapService) -> void:
	map_service = ms
	# the world reacts to input while paused; the simulation children pause with the tree
	process_mode = Node.PROCESS_MODE_ALWAYS
	net = ms.net
	bounds = ms.bake_result.bounds
	hq_info = ms.bake_result.hq
	Geo.setup(Game.map_meta.center_lat, Game.map_meta.center_lon)
	_terrain = ms.bake_result.get("terrain")
	Terrain.activate(_terrain)
	# environment
	env_node = WorldEnvironment.new()
	env_node.environment = DayNight.make_environment()
	add_child(env_node)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 900.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.shadow_blur = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	add_child(moon)
	day_night = DayNight.new()
	day_night.latitude = Game.map_meta.center_lat
	add_child(day_night)
	day_night.setup(env_node, sun, moon)
	# city
	city = ms.city_root
	add_child(city)
	# traffic & routing
	traffic = TrafficSim.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(net, ms.bake_result.get("bus_stops", []))
	router = traffic.router
	# headquarters
	hq = HQ.new()
	hq.name = "HQ"
	add_child(hq)
	if not hq_info.is_empty():
		hq.setup(hq_info, Game.company.name)
	# fleet + jobs
	fleet = Fleet.new()
	fleet.name = "Fleet"
	add_child(fleet)
	fleet.setup(self)
	jobs = JobManager.new()
	jobs.name = "Jobs"
	add_child(jobs)
	jobs.setup(self)
	light_pool = LightPool.new()
	light_pool.name = "LightPool"
	add_child(light_pool)
	light_pool.setup(self, ms.bake_result.lamps)
	signals_view = SignalHeads.new()
	signals_view.name = "Signals"
	add_child(signals_view)
	signals_view.setup(self)
	for n in [traffic, fleet, jobs, light_pool, signals_view, day_night, city, hq]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	# camera
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.bounds = bounds
	camera_rig.clicked_right.connect(_on_right_click)
	var start := Vector3.ZERO
	if not hq_info.is_empty():
		var lc: Vector2 = hq_info.lot_center
		start = Vector3(lc.x, Terrain.at(lc), lc.y)
	camera_rig.set_view(start, 150.0, -35.0, 50.0)


func new_game_setup() -> void:
	fleet.spawn_start_fleet()
	jobs.generate_initial_offers()


func _process(_delta: float) -> void:
	if traffic and camera_rig:
		traffic.focus = camera_rig.target
		traffic.radius = clampf(camera_rig.distance * 2.2, 450.0, 1100.0)
	RenderingServer.global_shader_parameter_set("night", day_night.night if day_night else 0.0)


# ------------------------------------------------------------------------------------------
# Input: selection and commands
# ------------------------------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if tool and tool.has_method("on_left_click"):
			if tool.on_left_click(ev.position):
				get_viewport().set_input_as_handled()
				return
		var hit := pick(ev.position)
		Game.select(hit)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and tool and tool.has_method("on_mouse_move"):
		tool.on_mouse_move(ev.position)


func _on_right_click(screen: Vector2) -> void:
	if tool and tool.has_method("on_right_click"):
		tool.on_right_click(screen)
		return
	if marker_command.is_valid() and marker_command.call(screen):
		return
	var gp = camera_rig.ground_point(screen)
	if gp == null:
		return
	var target := pick(screen)
	Events.context_command.emit(gp, target)
	if Game.selected is Vehicle and is_instance_valid(Game.selected):
		(Game.selected as Vehicle).command_at(gp, target)


## Raycast against pickable bodies (vehicles, sites). Returns the owner object or null.
func pick(screen: Vector2) -> Object:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 6000.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.collision_mask = 0b10
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return null
	var col: Object = res.collider
	if col.has_meta("owner_obj"):
		return col.get_meta("owner_obj")
	return null


func ground_at_mouse() -> Variant:
	return camera_rig.ground_point(get_viewport().get_mouse_position())


# ------------------------------------------------------------------------------------------
# Save / load
# ------------------------------------------------------------------------------------------

func _exit_tree() -> void:
	# road cut-outs are global shader state: clear them for the next game
	for i in 4:
		RenderingServer.global_shader_parameter_set("pit_b%d" % i, Vector4.ZERO)
	# ground heights belong to this map (#8); a newer map may already have its own
	if _terrain != null and Terrain.cur == _terrain:
		Terrain.activate(null)


func save_state() -> Dictionary:
	return {"fleet": fleet.save_state(), "jobs": jobs.save_state(), "camera": [camera_rig.target, camera_rig.distance, camera_rig.yaw, camera_rig.pitch]}


func load_state(d: Dictionary) -> void:
	fleet.load_state(d.get("fleet", {}))
	jobs.load_state(d.get("jobs", {}))
	# vehicles that worked on a site
	for vd in d.get("fleet", {}).get("vehicles", []):
		var sid: int = vd.get("site", -1)
		if sid < 0 or not jobs.sites.has(sid):
			continue
		var v := fleet.by_plate(vd.plate)
		if v and v.carried_by == null:
			jobs.sites[sid].restore_vehicle(v, vd.get("spot", ""), vd.get("in_place", false))
	for s in jobs.sites.values():
		s.post_load()
	if d.has("camera"):
		var c: Array = d.camera
		camera_rig.set_view(c[0], c[1], rad_to_deg(c[2]), rad_to_deg(c[3]))
