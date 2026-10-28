extends SceneTree
## Compiles every GDScript of the project with the autoloads registered (unlike --check-only).
## Used by tools/check.sh. Prints "COMPILE FAIL <path>" for scripts that do not load; the engine
## prints the parse errors itself ("SCRIPT ERROR: ... at: GDScript::reload (res://file:line)").

func _initialize() -> void:
	var files: Array = []
	var only := OS.get_cmdline_user_args()
	if only.is_empty():
		_collect("res://src", files)
		_collect("res://test", files)
	else:
		for f in only:
			files.append(f if f.begins_with("res://") else "res://" + f)
	var bad := 0
	for f in files:
		var s: Script = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or not s.can_instantiate():
			bad += 1
			print("COMPILE FAIL ", f)
	print("COMPILE DONE files=%d failed=%d" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and f != "compile_all.gd":  # reloading the running script breaks the VM
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
