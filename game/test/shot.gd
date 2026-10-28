extends SceneTree
## Usage: godot --path game -s res://test/shot.gd -- --scene=res://x.tscn --out=/tmp/x.png --frames=30 [--size=1280x720]
var frames := 30
var out := "/tmp/shot.png"
var count := 0

func _init() -> void:
	var scene_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="): scene_path = a.substr(8)
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			root.size = Vector2i(int(p[0]), int(p[1]))
	if scene_path != "":
		var sc: PackedScene = load(scene_path)
		root.add_child.call_deferred(sc.instantiate())

func _process(_delta: float) -> bool:
	count += 1
	if count == frames:
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("SHOT ", out, " ", img.get_size())
		quit()
	return false
