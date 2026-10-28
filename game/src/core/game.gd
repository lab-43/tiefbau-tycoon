extends Node
## Global game state: company, money, map, fleet, jobs, selection. Owns save/load.

## Where saves, maps, downloads, issues and logs live. Normally Godot's user folder
## (%APPDATA%/Godot/app_userdata/Baustellen Manager). Portable mode: a file "portable.txt" next to
## the exe; an optional line "data=<path>" (relative to the exe) points to a shared folder, e.g.
## "data=../../userdata" so that every build in build/* uses the same saves, maps and issues.
var data_root := "user://"
var SAVE_DIR := "user://saves"
var MAPS_DIR := "user://maps"
## Contents of res://build_info.json (written by tools/build.sh): version, commit, branch, date.
var build_info := {"version": "dev", "commit": "", "branch": "", "date": ""}
var data_pack_loaded := false
var logger: GameLogger           # engine log copy in <data>/logs/spiel.log

var company := {"name": "", "money": 0.0, "founded_day": 1, "reputation": 50.0, "jobs_done": 0}
var map_meta: Dictionary = {}   # id, name, center_lat, center_lon, size_m, hq{lat,lon,x,z}
var world: Node = null          # World node while playing
var selected: Object = null
var ledger: Array = []          # recent transactions {day, time, amount, reason}
var dev_fixture := ""           # offline fixture name (testing)
var pending_load: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var exe_dir := OS.get_executable_path().get_base_dir()
	if not OS.has_feature("editor"):
		var portable := exe_dir.path_join("portable.txt")
		if FileAccess.file_exists(portable):
			var rel := "userdata"
			for line in FileAccess.get_file_as_string(portable).split("\n"):
				line = line.strip_edges()
				if line.begins_with("data="):
					rel = line.substr(5).strip_edges()
			data_root = rel if rel.is_absolute_path() else exe_dir.path_join(rel).simplify_path()
			DirAccess.make_dir_recursive_absolute(data_root)
	SAVE_DIR = data_path("saves")
	MAPS_DIR = data_path("maps")
	# build info first: the log header names the version
	if FileAccess.file_exists("res://build_info.json"):
		var bi = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
		if bi is Dictionary:
			build_info.merge(bi, true)
	logger = GameLogger.new()
	logger.open(data_path("logs"))
	OS.add_logger(logger)
	_load_data_pack(exe_dir)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fixture="):
			dev_fixture = a.substr(10)


## Models, barrier set and demo map ship in a separate pack (BaustellenManager-Daten.pck) that
## rarely changes; code builds stay small. Not needed when running from the project folder.
func _load_data_pack(exe_dir: String) -> void:
	var path := exe_dir.path_join("BaustellenManager-Daten.pck")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--data-pack="):
			path = a.substr(12)
	if ResourceLoader.exists("res://assets/consim/excavator_a918/excavator_a918.glb"):
		return   # already there (project folder or a full pack)
	if FileAccess.file_exists(path):
		data_pack_loaded = ProjectSettings.load_resource_pack(path, false)
		if not data_pack_loaded:
			push_error("Daten-Pack konnte nicht geladen werden: " + path)
	else:
		push_error("Daten-Pack fehlt: " + path)


func version_text() -> String:
	var v: String = build_info.version
	if build_info.branch != "" and build_info.branch != "main":
		v += " (" + build_info.branch + ")"
	return v


func data_path(sub: String) -> String:
	return data_root.path_join(sub)


func map_dir() -> String:
	return MAPS_DIR.path_join(map_meta.get("id", "none"))


func money() -> float:
	return company.money


func add_money(amount: float, reason: String) -> void:
	company.money += amount
	ledger.push_front({"day": Clock.day, "time": Clock.time_string(), "amount": amount, "reason": reason})
	if ledger.size() > 200:
		ledger.resize(200)
	Events.money_changed.emit(company.money, amount, reason)


## Spends money if affordable (or if force). Returns false when the company can't pay.
func spend(amount: float, reason: String, force := false) -> bool:
	if amount <= 0.0:
		return true
	if not force and company.money < amount:
		Events.warn("Nicht genug Geld: %s benötigt %s" % [reason, Balance.money(amount)])
		return false
	add_money(-amount, reason)
	return true


func select(obj: Object) -> void:
	if selected == obj:
		return
	if selected and is_instance_valid(selected) and selected.has_method("set_selected"):
		selected.set_selected(false)
	selected = obj
	if selected and selected.has_method("set_selected"):
		selected.set_selected(true)
	Events.selection_changed.emit(selected)


func new_company(cname: String, meta: Dictionary) -> void:
	company = {"name": cname, "money": Balance.START_MONEY, "founded_day": 1, "reputation": 50.0, "jobs_done": 0}
	map_meta = meta
	ledger.clear()
	selected = null


# --- save / load ----------------------------------------------------------------------------

func save_game(slot := "spielstand") -> bool:
	if world == null:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": 1, "company": company, "map": map_meta, "ledger": ledger.slice(0, 60),
		"clock": {"day": Clock.day, "minutes": Clock.minutes, "doy": Clock.day_of_year},
		"world": world.save_state(),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open_compressed(SAVE_DIR.path_join(slot + ".sav"), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		Events.error("Speichern fehlgeschlagen")
		return false
	f.store_var(data, false)
	f.close()
	Events.ok("Spiel gespeichert")
	return true


func has_save(slot := "spielstand") -> bool:
	return FileAccess.file_exists(SAVE_DIR.path_join(slot + ".sav"))


## Full state as a Dictionary (also used for issue reports).
func save_data() -> Dictionary:
	return {
		"version": 1, "company": company, "map": map_meta, "ledger": ledger.slice(0, 60),
		"clock": {"day": Clock.day, "minutes": Clock.minutes, "doy": Clock.day_of_year},
		"world": world.save_state() if world else {},
		"saved_at": Time.get_datetime_string_from_system(), "build": build_info,
	}


func write_save_file(path: String) -> bool:
	if world == null:
		return false
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(save_data(), false)
	f.close()
	return true


func read_save_file(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var(false)
	f.close()
	return d if d is Dictionary else {}


func read_save(slot := "spielstand") -> Dictionary:
	var f := FileAccess.open_compressed(SAVE_DIR.path_join(slot + ".sav"), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var(false)
	f.close()
	return d if d is Dictionary else {}


func apply_save_header(d: Dictionary) -> void:
	company = d.company
	map_meta = d.map
	ledger = d.get("ledger", [])
	Clock.day = d.clock.day
	Clock.minutes = d.clock.minutes
	Clock.day_of_year = d.clock.get("doy", 105)
	pending_load = d.get("world", {})
	if String(map_meta.get("id", "")).begins_with("dev_"):
		dev_fixture = String(map_meta.id).substr(4)
