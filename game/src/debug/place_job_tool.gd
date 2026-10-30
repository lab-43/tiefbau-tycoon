class_name PlaceJobTool
extends RefCounted
## World tool (World.tool) of the debug menu: the next left click on the map places a contract there.
## While active, a PitPreview shows under the mouse where the pit would go and whether it fits (#33).
## Emits done(Vector2 point) on a left click on the ground, done(null) on a right click (cancel).

signal done(p: Variant)
signal preview_changed(text: String, ok: bool)

var pipe_i := 0                # the same pipe (trench width) for the preview and the contract
var click_y := NAN             # height of the last click (a bridge deck or the ground)
var preview: PitPreview
var _last_screen := Vector2(-1, -1)
var _last_p := Vector2(INF, INF)
var _last_ms := -1000


func _init() -> void:
	pipe_i = randi() % JobManager.PIPES.size()


func on_left_click(screen: Vector2) -> bool:
	var gp = Game.world.camera_rig.ground_point(screen)
	if gp == null:
		return true
	click_y = gp.y
	done.emit(Vector2(gp.x, gp.z))
	return true


func on_right_click(_screen: Vector2) -> void:
	done.emit(null)


func on_mouse_move(screen: Vector2) -> void:
	_last_screen = screen
	update_preview()


## Re-checks the spot under the mouse (also called every frame: the camera may move under it).
func update_preview() -> void:
	var w: World = Game.world
	if w == null or _last_screen.x < 0.0:
		return
	if preview == null or not is_instance_valid(preview):
		preview = PitPreview.new()
		preview.name = "PitPreview"
		w.add_child(preview)
	var gp = w.camera_rig.ground_point(_last_screen)
	if gp == null:
		preview.hide_preview()
		_last_p = Vector2(INF, INF)
		preview_changed.emit("", false)
		return
	var p := Vector2(gp.x, gp.z)
	var now := Time.get_ticks_msec()
	if p.distance_to(_last_p) < 0.25 or now - _last_ms < 40:
		return
	_last_p = p
	_last_ms = now
	var pipe: Dictionary = JobManager.PIPES[pipe_i]
	var r: Dictionary = w.jobs.check_spot(p, pipe, 4.0, 1.8, gp.y)
	preview.show_result(r, pipe, w.net)
	var txt := "Grube passt hierher." if r.ok else str(r.error)
	if r.ok and not (r.hints as Array).is_empty():
		txt += " " + " · ".join(r.hints)
	preview_changed.emit(txt, r.ok)


func dispose() -> void:
	if preview and is_instance_valid(preview):
		preview.get_parent().remove_child(preview)
		preview.queue_free()
	preview = null
