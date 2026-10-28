extends Node
## Top-level flow: main menu -> company setup -> loading -> world (+HUD). Also handles continue/load.

var ui_root: Control
var layer: CanvasLayer
var world: Node3D
var hud: Control
var map_service: MapService
var _screen: Control
var _reporter: IssueReporter
var _issues: IssueBrowser


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "Baustellen Manager"
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.theme = UI.theme()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--e2e="):
			var drv: Node = load("res://test/e2e_driver.gd").new()
			drv.name = "E2E"
			add_child(drv)
	Events.open_issues.connect(open_issue_browser)
	Events.report_issue.connect(open_reporter)
	if "--autostart" in args:
		_autostart.call_deferred()
	else:
		show_menu()


func _clear_screen() -> void:
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null


func show_menu() -> void:
	_clear_screen()
	var m := MainMenu.new()
	m.new_game.connect(show_setup)
	m.continue_game.connect(continue_game)
	m.quit.connect(func(): get_tree().quit())
	m.open_issues.connect(open_issue_browser)
	_screen = m
	ui_root.add_child(m)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		open_reporter()


## F8 anywhere (menu, loading screen, game): report a bug or wish with screenshot and context.
func open_reporter() -> void:
	if _reporter and is_instance_valid(_reporter):
		return
	if _issues and is_instance_valid(_issues):
		_issues.queue_free()
	var r := IssueReporter.new()
	if world and Game.world:
		r.origin = "welt"
	elif _screen is LoadingScreen and map_service and is_instance_valid(map_service):
		r.origin = "ladebildschirm"
		var lines := PackedStringArray()
		for l in map_service.log_lines.slice(maxi(0, map_service.log_lines.size() - 80)):
			lines.append("[%05.1f] %s" % [l[0], l[2]])
		r.extra_context = {"step": map_service.step_text, "progress": map_service.frac, "log": "\n".join(lines),
			"log_file": map_service.log_path}
	else:
		r.origin = "menue"
	_reporter = r
	ui_root.add_child(r)
	r.start()


func open_issue_browser() -> void:
	if _issues and is_instance_valid(_issues):
		return
	var b := IssueBrowser.new()
	b.report_requested.connect(func():
		b.queue_free()
		open_reporter.call_deferred())
	_issues = b
	ui_root.add_child(b)


func show_setup() -> void:
	_clear_screen()
	var s := SetupScreen.new()
	s.back.connect(show_menu)
	s.create.connect(start_new)
	_screen = s
	ui_root.add_child(s)


func _autostart() -> void:
	# developer/test path: found a company on the fixture without menus
	var meta := {"id": "dev_" + (Game.dev_fixture if Game.dev_fixture != "" else "map"), "name": "Utrecht",
		"center_lat": 52.0907, "center_lon": 5.1214, "size_m": 6000.0}
	var hq := Vector2(-650.0, 420.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hq="):
			var p := a.substr(5).split(",")
			hq = Vector2(float(p[0]), float(p[1]))
	meta["hq"] = {"x": hq.x, "z": hq.y}
	start_new("Muster Tiefbau GmbH", meta)


func start_new(company_name: String, meta: Dictionary) -> void:
	Game.new_company(company_name, meta)
	Clock.day = 1
	Clock.minutes = 8.0 * 60.0
	Clock.day_of_year = 105
	await _load_world(false)


## Loads a save file from anywhere (used to reproduce issues: issues/<n>/spielstand.sav).
func load_save_file(path: String) -> bool:
	var d := Game.read_save_file(path)
	if d.is_empty():
		return false
	Game.apply_save_header(d)
	await _load_world(true)
	return true


func continue_game() -> void:
	var d := Game.read_save()
	if d.is_empty():
		Events.error("Kein Spielstand gefunden")
		return
	Game.apply_save_header(d)
	await _load_world(true)


func _load_world(from_save: bool, ls: LoadingScreen = null) -> void:
	if ls == null or not is_instance_valid(ls):
		_clear_screen()
		ls = LoadingScreen.new()
		ls.set_title(Game.company.name, Game.map_meta.get("name", ""))
		_screen = ls
		ui_root.add_child(ls)
	if map_service and is_instance_valid(map_service):
		map_service.queue_free()
	var svc := MapService.new()
	svc.name = "MapService"
	map_service = svc
	add_child(svc)
	ls.attach(svc)
	var done := [false, false, ""]
	svc.finished.connect(func(ok, msg):
		done[0] = true
		done[1] = ok
		done[2] = msg)
	# cancel: back to the menu right away; the service stops at its next checkpoint
	var on_cancel := func():
		svc.cancel()
		show_menu()
	ls.cancel_pressed.connect(on_cancel)
	svc.prepare(Game.map_meta)
	while not done[0]:
		await get_tree().process_frame
	if is_instance_valid(ls) and ls.cancel_pressed.is_connected(on_cancel):
		ls.cancel_pressed.disconnect(on_cancel)
	if svc.cancelled:
		svc.queue_free()
		if map_service == svc:
			map_service = null
		return
	if not is_instance_valid(ls):
		return
	if not done[1]:
		ls.show_error(done[2], func(): show_menu(), func(): _load_world(from_save, ls))
		return
	svc.step_text = "Welt, Fuhrpark und Verkehr starten …"
	await get_tree().process_frame
	await get_tree().process_frame
	world = World.new()
	world.name = "World"
	add_child(world)
	move_child(world, 0)
	world.setup(map_service)
	if from_save and not Game.pending_load.is_empty():
		world.load_state(Game.pending_load)
		Game.pending_load = {}
	else:
		world.new_game_setup()
	Game.world = world
	hud = HUD.new()
	hud.quit_to_menu.connect(_quit_to_menu)
	ui_root.add_child(hud)
	_clear_screen()
	Clock.running = true
	Clock.set_speed(1)
	Events.world_ready.emit()


func _quit_to_menu() -> void:
	Clock.stop()
	Game.world = null
	Game.selected = null
	if hud:
		hud.queue_free()
	if world:
		world.queue_free()
	if map_service:
		map_service.queue_free()
	await get_tree().process_frame
	show_menu()
