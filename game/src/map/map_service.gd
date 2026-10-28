class_name MapService
extends Node
## Gets the map ready: downloads the OSM data (MapDownloader), bakes the city in a worker thread,
## builds the scene and caches the result. Every step is logged (screen, console and a log file)
## and the loading screen polls snapshot() for live progress.

signal progress(step: String, frac: float)
signal finished(ok: bool, message: String)

enum { L_INFO, L_OK, L_WARN, L_ERR }

const LOG_KEEP := 400

var meta: Dictionary
var city_root: Node3D
var net: RoadNet
var bake_result: Dictionary
var cancelled := false
var log_lines: Array = []        # [seconds, level, text]
var log_serial := 0              # number of lines ever added (the screen appends what is new)
var log_path := ""
var stages: Array = []           # [{id, title, state ("wait"|"run"|"done"|"skip"|"fail"), t0, t1}]
var step_text := "Vorbereiten …"
var frac := 0.0
var stage_frac := 0.0
var downloader: MapDownloader
var geofabrik: GeofabrikSource
var pbf_path := ""               # Geofabrik extract to read instead of Overpass pieces
var _shares := {"download": 0.45, "bake": 0.35, "scene": 0.12, "save": 0.08, "cache": 0.6}

var _thread: Thread
var _builder: MapBuilder
var _t_start := 0
var _log_file: FileAccess


# ------------------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------------------

func prepare(m: Dictionary) -> void:
	meta = m
	_t_start = Time.get_ticks_msec()
	var dir: String = Game.MAPS_DIR.path_join(meta.id)
	var osm_dir := dir.path_join("osm2")
	DirAccess.make_dir_recursive_absolute(osm_dir)
	_open_log(dir)
	_save_meta(dir)
	_log("Karte „%s“: %.0f × %.0f km um %.5f, %.5f" % [meta.get("name", "?"), meta.size_m / 1000.0, meta.size_m / 1000.0,
		meta.center_lat, meta.center_lon])
	_log("Godot %s · %s · Daten: %s" % [Engine.get_version_info().string, OS.get_name(), ProjectSettings.globalize_path(dir)])
	var cache := dir.path_join("baked_v%d.bin" % MapBuilder.BAKE_VERSION)
	if FileAccess.file_exists(cache):
		_set_stages([["cache", "Gespeicherte Karte lesen"], ["scene", "3D-Szene aufbauen"]])
		_begin("cache", "Gespeicherte Karte lesen …")
		var ok := await _load_cache(cache)
		if cancelled:
			_stop()
			return
		if ok:
			_end("cache")
			_begin("scene", "3D-Szene aufbauen …")
			await _build_scene(bake_result)
			_end("scene")
			_log("Karte bereit nach %s." % MapDownloader._secs(_elapsed()), L_OK)
			_close_log()
			finished.emit(true, "")
			return
		_log("Gespeicherte Karte ist unlesbar – sie wird neu aufbereitet.", L_WARN)
		DirAccess.remove_absolute(cache)
	_set_stages([["download", "Kartendaten herunterladen (OpenStreetMap)"], ["bake", "Karte aufbereiten"],
		["scene", "3D-Szene aufbauen"], ["save", "Karte speichern"]])
	if Game.dev_fixture != "":
		_copy_fixture(osm_dir)
	var mf := MapDownloader.read_manifest(osm_dir)
	if mf.has("pbf") and FileAccess.file_exists(mf.pbf):
		pbf_path = mf.pbf
		_use_pbf_shares()
		_log("Kartendaten liegen schon vor (Geofabrik-Auszug %s) – kein Download nötig." % String(mf.get("region", "")), L_OK)
		_skip("download")
	elif not mf.is_empty() and not mf.has("pbf"):
		_log("Kartendaten liegen schon vollständig vor – kein Download nötig.", L_OK)
		_skip("download")
	else:
		_begin("download", "Kartendaten herunterladen …")
		var ok_dl := await _download_any(osm_dir)
		if cancelled:
			_stop()
			return
		if not ok_dl:
			_fail_stage("download")
			var msg := ("Einige Kartenteile konnten nicht geladen werden. Was schon da ist, bleibt gespeichert – " +
				"„Erneut versuchen“ lädt nur den Rest. Details stehen im Protokoll.")
			if downloader and downloader.diagnosis != "":
				msg = downloader.diagnosis + "\n\n" + msg
			_log(msg, L_ERR)
			_close_log()
			finished.emit(false, msg)
			return
		_end("download")
	_begin("bake", "Karte aufbereiten …")
	var ok_b: bool = await _bake(osm_dir, cache)
	if not ok_b:
		_stop()
		return
	_log("Karte bereit nach %s." % MapDownloader._secs(_elapsed()), L_OK)
	_close_log()
	finished.emit(true, "")


func cancel() -> void:
	cancelled = true
	if downloader:
		downloader.cancel()
	if geofabrik:
		geofabrik.cancel()
	_log("Abgebrochen.", L_WARN)


func _stop() -> void:
	_close_log()
	finished.emit(false, "")


# ------------------------------------------------------------------------------------------
# Download
# ------------------------------------------------------------------------------------------

## First choice: one ready-made extract from Geofabrik (a plain file download, reliable and fast).
## If none fits or it fails: the map pieces from the Overpass servers.
func _download_any(osm_dir: String) -> bool:
	var force_overpass := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--overpass=") or a == "--no-geofabrik":
			force_overpass = true
	if not force_overpass:
		geofabrik = GeofabrikSource.new()
		geofabrik.name = "Geofabrik"
		add_child(geofabrik)
		geofabrik.log_line.connect(_log)
		_log("Quelle 1: fertiger OpenStreetMap-Auszug von Geofabrik (download.geofabrik.de).")
		geofabrik.run(meta)
		while geofabrik.running and not cancelled:
			var snap := geofabrik.snapshot()
			stage_frac = snap.progress
			if String(snap.phase).ends_with("herunterladen"):
				step_text = "Kartendaten herunterladen: Geofabrik-Auszug „%s“" % snap.region
				if snap.total > 0:
					step_text += " · %s von %s" % [MapDownloader._fmt_bytes(snap.got), MapDownloader._fmt_bytes(snap.total)]
			else:
				step_text = "Kartendaten: " + (snap.phase if snap.phase != "" else "Geofabrik")
			_update_frac()
			await get_tree().process_frame
		if cancelled:
			return false
		if geofabrik.result == "ok":
			pbf_path = geofabrik.pbf_path
			_use_pbf_shares()
			MapDownloader.write_manifest(osm_dir, {"source": "geofabrik", "pbf": pbf_path, "region": geofabrik.region_name,
				"time": Time.get_datetime_string_from_system()})
			return true
		_log("Quelle 2: Kartenteile von den Overpass-Servern.")
	return await _download(osm_dir)


func _use_pbf_shares() -> void:
	# reading the extract happens during "Karte aufbereiten" and takes longer than the download
	_shares = {"download": 0.2, "bake": 0.6, "scene": 0.12, "save": 0.08, "cache": 0.6}
	_update_frac()

func _download(osm_dir: String) -> bool:
	downloader = MapDownloader.new()
	downloader.name = "Downloader"
	add_child(downloader)
	downloader.log_line.connect(_log)
	downloader.start(meta, osm_dir)
	while downloader.running and not cancelled:
		var snap := downloader.snapshot()
		stage_frac = snap.progress
		step_text = "Kartendaten herunterladen: %d von %d Kacheln · %s" % [snap.tiles_done, snap.tiles_total, MapDownloader._fmt_bytes(snap.bytes)]
		_update_frac()
		await get_tree().process_frame
	return downloader.result == "ok"


func _copy_fixture(osm_dir: String) -> void:
	if MapDownloader.is_complete(osm_dir):
		return
	var src := "res://test_fixtures/%s/osm" % Game.dev_fixture
	var n := 0
	for f in DirAccess.get_files_at(src):
		if f.ends_with(".json") and not FileAccess.file_exists(osm_dir.path_join(f)):
			var data := FileAccess.get_file_as_bytes(src.path_join(f))
			var w := FileAccess.open(osm_dir.path_join(f), FileAccess.WRITE)
			w.store_buffer(data)
			n += 1
	MapDownloader.write_manifest(osm_dir, {"fixture": Game.dev_fixture})
	_log("Offline-Demokarte „%s“ verwendet (%d Dateien)." % [Game.dev_fixture, n], L_OK)


# ------------------------------------------------------------------------------------------
# Bake (worker thread), scene, cache
# ------------------------------------------------------------------------------------------

## Returns false if the player cancelled meanwhile.
func _bake(osm_dir: String, cache: String) -> bool:
	_builder = MapBuilder.new()
	_thread = Thread.new()
	var m := meta.duplicate(true)
	var pbf := pbf_path
	if pbf != "":
		_log("Lese den Auszug %s …" % ProjectSettings.globalize_path(pbf))
	_thread.start(func(): return _builder.bake(m, osm_dir, pbf))
	var last_step := ""
	var t_step := Time.get_ticks_msec()
	while _thread.is_alive():
		var st := _builder.get_status()
		for n in _builder.take_notes():
			_log(n)
		var s: String = st[0]
		var base := s.get_slice(" (", 0).get_slice(":", 0)
		if base != last_step:
			last_step = base
			t_step = Time.get_ticks_msec()
		var secs := (Time.get_ticks_msec() - t_step) / 1000.0
		step_text = s + ("  · %d s" % int(secs) if secs >= 2.0 else "")
		stage_frac = float(st[1])
		_update_frac()
		await get_tree().create_timer(0.1).timeout
	bake_result = _thread.wait_to_finish()
	for n in _builder.take_notes():
		_log(n)
	if cancelled:
		return false
	net = bake_result.net
	_end("bake")
	_begin("scene", "3D-Szene aufbauen …")
	await _build_scene(bake_result)
	_end("scene")
	if cancelled:
		return false
	_begin("save", "Karte für den nächsten Start speichern …")
	await _save_cache(cache, bake_result)
	_end("save")
	return true


func _build_scene(res: Dictionary) -> void:
	city_root = MapBuilder.create_city_root(res)
	var total: int = maxi(1, res.roads.size() + res.city.size())
	var count := 0
	for group in ["roads", "city"]:
		for ck in res[group]:
			MapBuilder.add_chunk_layers(city_root, ck, res[group][ck])
			count += 1
			if count % 8 == 0:
				stage_frac = float(count) / total
				step_text = "3D-Szene aufbauen: %d von %d Kartenkacheln" % [count, total]
				_update_frac()
				await get_tree().process_frame
	for ck in res.trees:
		MapBuilder.add_instances(city_root, ck, "trees", res.trees[ck])
	for ck in res.lamps:
		MapBuilder.add_instances(city_root, ck, "lamps", res.lamps[ck])
	_log("3D-Szene: %d Kartenkacheln, %d Baumgruppen" % [total, res.trees.size()])


static func _layers_to_data(chunks: Dictionary) -> Dictionary:
	var out := {}
	for ck in chunks:
		var layers := {}
		for ln in chunks[ck]:
			var l: MeshLayer = chunks[ck][ln]
			layers[ln] = [l.verts, l.normals, l.uvs if l.use_uvs else PackedVector2Array(), l.colors if l.use_colors else PackedColorArray(), l.indices]
		out[ck] = layers
	return out


static func _data_to_layers(d: Dictionary) -> Dictionary:
	var out := {}
	for ck in d:
		var layers := {}
		for ln in d[ck]:
			var a: Array = d[ck][ln]
			var l := MeshLayer.new()
			l.verts = a[0]
			l.normals = a[1]
			l.uvs = a[2]
			l.use_uvs = a[2].size() > 0
			l.colors = a[3]
			l.use_colors = a[3].size() > 0
			l.indices = a[4]
			layers[ln] = l
		out[ck] = layers
	return out


func _save_cache(path: String, res: Dictionary) -> void:
	var d := {
		"roads": _layers_to_data(res.roads), "city": _layers_to_data(res.city), "trees": res.trees, "lamps": res.lamps,
		"bounds": res.bounds, "hq": res.hq, "stats": res.stats, "bus_stops": res.bus_stops, "net": res.net.serialize(),
	}
	var th := Thread.new()
	th.start(func():
		var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if f == null:
			return false
		f.store_var(d, false)
		f.close()
		return true)
	var t0 := Time.get_ticks_msec()
	while th.is_alive():
		step_text = "Karte speichern … %d s" % int((Time.get_ticks_msec() - t0) / 1000.0)
		stage_frac = 0.5
		_update_frac()
		await get_tree().process_frame
	var ok: bool = th.wait_to_finish()
	if ok:
		var fa := FileAccess.open(path, FileAccess.READ)
		_log("Karte gespeichert (%s) – der nächste Start geht schnell." % MapDownloader._fmt_bytes(fa.get_length() if fa else 0), L_OK)
	else:
		_log("Karte konnte nicht gespeichert werden (%s)." % path, L_WARN)


func _load_cache(path: String) -> bool:
	var m := meta.duplicate()
	var th := Thread.new()
	th.start(func():
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f == null:
			return {}
		var d = f.get_var(false)
		f.close()
		if not (d is Dictionary) or not d.has("net"):
			return {}
		Geo.setup(m.center_lat, m.center_lon)
		var rn := RoadNet.new()
		rn.deserialize(d.net)
		return {"net": rn, "roads": _data_to_layers(d.roads), "city": _data_to_layers(d.city), "trees": d.trees,
			"lamps": d.lamps, "bounds": d.bounds, "hq": d.hq, "stats": d.stats, "bus_stops": d.get("bus_stops", [])})
	var t0 := Time.get_ticks_msec()
	while th.is_alive():
		step_text = "Gespeicherte Karte lesen … %d s" % int((Time.get_ticks_msec() - t0) / 1000.0)
		stage_frac = 0.5
		_update_frac()
		await get_tree().process_frame
	var res: Dictionary = th.wait_to_finish()
	if res.is_empty():
		return false
	Geo.setup(meta.center_lat, meta.center_lon)
	net = res.net
	bake_result = res
	_log("Gespeicherte Karte gelesen in %s." % MapDownloader._secs((Time.get_ticks_msec() - t0) / 1000.0), L_OK)
	return true


# ------------------------------------------------------------------------------------------
# Stages, progress, log
# ------------------------------------------------------------------------------------------

## Polled by the loading screen.
func snapshot() -> Dictionary:
	return {"stages": stages, "step": step_text, "frac": frac, "elapsed": _elapsed(),
		"dl": _dl_snapshot(),
		"log_serial": log_serial}


func _dl_snapshot() -> Dictionary:
	if not (_stage_state("download") in ["run", "fail"]):
		return {}
	if downloader and is_instance_valid(downloader):
		return downloader.snapshot()
	if geofabrik and is_instance_valid(geofabrik):
		return geofabrik.snapshot()
	return {}


func _set_stages(list: Array) -> void:
	stages.clear()
	for s in list:
		stages.append({"id": s[0], "title": s[1], "state": "wait", "t0": 0.0, "t1": 0.0})


func _stage(id: String) -> Dictionary:
	for s in stages:
		if s.id == id:
			return s
	return {}


func _stage_state(id: String) -> String:
	var s := _stage(id)
	return s.get("state", "")


func _begin(id: String, text: String) -> void:
	var s := _stage(id)
	s.state = "run"
	s.t0 = _elapsed()
	step_text = text
	stage_frac = 0.0
	_update_frac()
	_log("▶ " + s.title)


func _end(id: String) -> void:
	var s := _stage(id)
	s.state = "done"
	s.t1 = _elapsed()
	stage_frac = 1.0
	_update_frac()
	_log("✓ %s (%s)" % [s.title, MapDownloader._secs(s.t1 - s.t0)], L_OK)


func _skip(id: String) -> void:
	var s := _stage(id)
	s.state = "skip"


func _fail_stage(id: String) -> void:
	var s := _stage(id)
	s.state = "fail"
	s.t1 = _elapsed()


## Overall progress: each stage gets a share of the bar.
func _update_frac() -> void:
	var shares := _shares
	var total := 0.0
	var got := 0.0
	for s in stages:
		var w: float = shares.get(s.id, 0.1)
		if s.id == "scene" and stages.size() == 2:
			w = 0.4
		total += w
		match s.state:
			"done", "skip":
				got += w
			"run":
				got += w * clampf(stage_frac, 0.0, 1.0)
	frac = got / maxf(total, 0.001)
	progress.emit(step_text, frac)


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t_start) / 1000.0


func _log(text: String, level := L_INFO) -> void:
	var t := _elapsed()
	log_lines.append([t, level, text])
	log_serial += 1
	if log_lines.size() > LOG_KEEP:
		log_lines.pop_front()
	var tag: String = ["   ", "OK ", "!! ", "XX "][clampi(level, 0, 3)]
	var line := "[%02d:%02d] %s%s" % [int(t) / 60, int(t) % 60, tag, text]
	print(line)
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()


func full_log_text() -> String:
	var out := PackedStringArray()
	for l in log_lines:
		out.append("[%02d:%02d] %s" % [int(l[0]) / 60, int(l[0]) % 60, l[2]])
	return "\n".join(out)


func _open_log(dir: String) -> void:
	var p := dir.path_join("laden.log")
	# keep earlier attempts in the file (useful when sending it for debugging), but not forever
	var old := FileAccess.open(p, FileAccess.READ)
	var append := old != null and old.get_length() < 2 * 1024 * 1024
	old = null
	_log_file = FileAccess.open(p, FileAccess.READ_WRITE if append else FileAccess.WRITE)
	if _log_file and append:
		_log_file.seek_end()
		_log_file.store_line("")
	log_path = ProjectSettings.globalize_path(p)
	if _log_file:
		_log_file.store_line("Baustellen Manager – Ladeprotokoll vom %s" % Time.get_datetime_string_from_system())


func _close_log() -> void:
	if _log_file:
		_log_file.flush()
		_log_file = null


func _save_meta(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("map.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "\t"))


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
