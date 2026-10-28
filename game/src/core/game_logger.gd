class_name GameLogger
extends Logger
## Writes everything the engine logs (print, warnings, errors with GDScript backtraces) to
## <data>/logs/spiel.log, so agents can read it next to the issues (portable mode puts it into the
## shared userdata folder). Keeps the last 5 sessions (spiel.log, spiel.1.log …). Thread-safe.

var _f: FileAccess
var _mutex := Mutex.new()
var path := ""


func open(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	path = dir.path_join("spiel.log")
	for i in range(4, 0, -1):
		var older := dir.path_join("spiel.%d.log" % i)
		var newer := dir.path_join("spiel.log" if i == 1 else "spiel.%d.log" % (i - 1))
		if FileAccess.file_exists(newer):
			DirAccess.rename_absolute(newer, older)
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f:
		_f.store_line("Baustellen Manager %s · %s · %s" % [Game.version_text(), OS.get_name(), Time.get_datetime_string_from_system()])


func _log_message(message: String, error: bool) -> void:
	_write(("FEHLER " if error else "") + message.strip_edges(false, true))


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind: String = ["FEHLER", "WARNUNG", "SKRIPTFEHLER", "SHADERFEHLER"][clampi(error_type, 0, 3)]
	var msg := "%s %s (%s:%d %s)" % [kind, rationale if rationale != "" else code, file, line, function]
	for bt in script_backtraces:
		if not bt.is_empty():
			msg += "\n" + bt.format(2)
	_write(msg)


func _write(s: String) -> void:
	_mutex.lock()
	if _f:
		_f.store_line("[%s] %s" % [Time.get_time_string_from_system(), s])
		_f.flush()
	_mutex.unlock()
