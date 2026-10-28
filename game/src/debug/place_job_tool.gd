class_name PlaceJobTool
extends RefCounted
## World tool (World.tool) of the debug menu: the next left click on the map places a contract there.
## Emits done(Vector2 point) on a left click on the ground, done(null) on a right click (cancel).

signal done(p: Variant)


func on_left_click(screen: Vector2) -> bool:
	var gp = Game.world.camera_rig.ground_point(screen)
	if gp == null:
		return true
	done.emit(Vector2(gp.x, gp.z))
	return true


func on_right_click(_screen: Vector2) -> void:
	done.emit(null)
