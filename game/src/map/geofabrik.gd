class_name GeofabrikSource
extends Node
## Gets the map data as a ready-made OpenStreetMap extract from Geofabrik (download.geofabrik.de):
## picks the smallest extract that contains the whole map (e.g. "Hamburg", 51 MB), downloads it
## once (a normal file download, no query servers) and keeps it for other maps in the same area.
## If no extract fits or it is too big to read in reasonable time, result is "skip" and the
## caller uses Overpass instead.

signal log_line(text: String, level: int)

enum { L_INFO, L_OK, L_WARN, L_ERR }

const UA := "BaustellenManager/0.2 (private single-player game)"
const HOST := "download.geofabrik.de"
const INDEX_URL := "https://download.geofabrik.de/index-v1.json"
# testing: --geofabrik-index=<url of an index-v1.json>
var CACHE_DIR: String = Game.data_path("extracts")
const MAX_MB := 160.0              # bigger extracts take too long to read → Overpass
const MAX_AGE_DAYS := 30
const MARGIN := 1000.0             # the extract must cover the map plus this margin

var running := false
var result := ""                   # "ok", "skip", "failed", "cancelled"
var reason := ""
var region_id := ""
var region_name := ""
var pbf_path := ""
var phase := ""                    # text for the loading screen
var total := -1
var got := 0
var bps := 0.0
var fails := 0
var _req: HTTPRequest
var _resolved_url := ""
var _cancel := false
var _last_t := 0
var _last_got := 0


func cancel() -> void:
	_cancel = true
	if _req and is_instance_valid(_req):
		_req.cancel_request()
		_req.queue_free()
		_req = null


## Coroutine: await run(meta). Afterwards check `result`.
func run(meta: Dictionary) -> void:
	running = true
	result = ""
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	# 1) index of all extracts (with their outlines), kept for a month
	phase = "Verzeichnis der Geofabrik-Auszüge laden"
	var index_path := CACHE_DIR.path_join("index-v1.json")
	if not _fresh(index_path):
		_log("Lade das Verzeichnis der Geofabrik-Auszüge …")
		var r := await _download(_index_url(), index_path, "Verzeichnis")
		if _cancel:
			_end("cancelled", "")
			return
		if r != "":
			_end("skip", "Verzeichnis nicht ladbar: " + r)
			return
	# 2) smallest extract that covers the map
	phase = "Passenden Auszug suchen"
	var corners := _corners(meta)
	var th := Thread.new()
	th.start(func(): return GeofabrikSource._pick(index_path, corners))
	while th.is_alive():
		await get_tree().process_frame
	var pick: Dictionary = th.wait_to_finish()
	if _cancel:
		_end("cancelled", "")
		return
	if pick.has("error"):
		DirAccess.remove_absolute(index_path)
		_end("skip", pick.error)
		return
	if pick.is_empty():
		_end("skip", "kein einzelner Auszug deckt die Karte ab")
		return
	region_id = pick.id
	region_name = pick.name
	var url: String = pick.url
	_log("Passender Auszug: „%s“ (%s)" % [region_name, region_id])
	# 3) size check
	phase = "Größe von „%s“ prüfen" % region_name
	var size := await _head_size(url)
	if _cancel:
		_end("cancelled", "")
		return
	if size > 0:
		_log("Auszug „%s“: %s" % [region_name, _mb(size)])
		if size > MAX_MB * 1048576.0:
			_end("skip", "Auszug „%s“ ist mit %s zu groß zum Einlesen" % [region_name, _mb(size)])
			return
	# 4) cached copy?
	pbf_path = CACHE_DIR.path_join(region_id.replace("/", "_") + ".osm.pbf")
	if _fresh(pbf_path) and (size <= 0 or _file_size(pbf_path) == size):
		var age := (Time.get_unix_time_from_system() - FileAccess.get_modified_time(pbf_path)) / 86400.0
		_log("Auszug „%s“ ist schon da (%d Tage alt) – kein Download nötig." % [region_name, int(age)], L_OK)
		_end("ok", "")
		return
	# 5) download + checksum
	for attempt in 2:
		phase = "„%s“ herunterladen" % region_name
		total = size
		var err := await _download(_resolved_url if _resolved_url != "" else url, pbf_path, "Auszug „%s“" % region_name)
		if _cancel:
			_end("cancelled", "")
			return
		if err != "":
			fails += 1
			if attempt == 0:
				_log("Download fehlgeschlagen (%s) – zweiter Versuch." % err, L_WARN)
				await get_tree().create_timer(3.0).timeout
				continue
			_end("skip", "Download fehlgeschlagen: " + err)
			return
		phase = "Prüfsumme kontrollieren"
		var ok := await _check_md5(url + ".md5", pbf_path)
		if ok:
			_end("ok", "")
			return
		fails += 1
		DirAccess.remove_absolute(pbf_path)
		_log("Prüfsumme stimmt nicht – Datei wird neu geladen.", L_WARN)
	_end("skip", "Datei kam zweimal beschädigt an")
	return


func _index_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--geofabrik-index="):
			return a.substr(18)
	return INDEX_URL


func _end(res: String, why: String) -> void:
	result = res
	reason = why
	running = false
	phase = ""
	if res == "skip":
		_log("Geofabrik nicht nutzbar: %s → Overpass wird verwendet." % why, L_WARN)


## Data for the loading screen (same fields as MapDownloader.snapshot()).
func snapshot() -> Dictionary:
	var text := phase
	var st := "busy" if running else "idle"
	if phase.ends_with("herunterladen") and total > 0:
		text = "%s · %s von %s (%s/s)" % [phase, _mb(got), _mb(total), _mb(int(bps))]
	elif phase.ends_with("herunterladen"):
		text = "%s · %s (%s/s)" % [phase, _mb(got), _mb(int(bps))]
	var frac := 0.0
	if result == "ok":
		frac = 1.0
	elif total > 0:
		frac = clampf(float(got) / total, 0.0, 1.0)
	return {"mode": "geofabrik", "tiles": [], "fill": frac, "region": region_name, "phase": phase,
		"got": got, "total": total, "bps": bps, "progress": frac,
		"eps": [{"host": HOST, "state": st, "text": text if text != "" else "fertig", "ok": 1 if result == "ok" else 0,
			"fail": fails, "bytes": got, "probe": ""}],
		"tiles_done": 0, "tiles_total": 0, "jobs_done": 0, "jobs_total": 0, "jobs_active": 1 if running else 0,
		"jobs_failed": 0, "bytes": got}


# ------------------------------------------------------------------------------------------
# Picking the extract (worker thread)
# ------------------------------------------------------------------------------------------

static func _pick(index_path: String, corners: PackedVector2Array) -> Dictionary:
	var txt := FileAccess.get_file_as_string(index_path)
	var doc = JSON.parse_string(txt)
	txt = ""
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("features"):
		return {"error": "Verzeichnis unlesbar"}
	var best := {}
	var best_area := INF
	for ft in doc.features:
		var props: Dictionary = ft.get("properties", {})
		var urls: Dictionary = props.get("urls", {})
		if not urls.has("pbf"):
			continue
		var geom = ft.get("geometry")
		if typeof(geom) != TYPE_DICTIONARY:
			continue
		var polys: Array = []
		match geom.get("type", ""):
			"Polygon":
				polys = [geom.coordinates]
			"MultiPolygon":
				polys = geom.coordinates
			_:
				continue
		var rings: Array = []
		var area := 0.0
		for poly in polys:
			if poly.is_empty():
				continue
			var outer: Array = poly[0]
			var ring := PackedVector2Array()
			ring.resize(outer.size())
			var i := 0
			for c in outer:
				ring[i] = Vector2(c[0], c[1])   # lon, lat
				i += 1
			rings.append(ring)
			area += absf(_ring_area(ring))
		if area >= best_area:
			continue
		var all_in := true
		for p in corners:
			var inside := false
			for ring in rings:
				if Geometry2D.is_point_in_polygon(p, ring):
					inside = true
					break
			if not inside:
				all_in = false
				break
		if all_in:
			best_area = area
			best = {"id": props.get("id", ""), "name": props.get("name", props.get("id", "")), "url": urls.pbf}
	return best


static func _ring_area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in r.size():
		var p := r[i]
		var q := r[(i + 1) % r.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _corners(meta: Dictionary) -> PackedVector2Array:
	Geo.setup(meta.center_lat, meta.center_lon)
	var h: float = float(meta.size_m) * 0.5 + MARGIN
	var out := PackedVector2Array()
	for c in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]:
		var ll := Geo.to_latlon(c)
		out.append(Vector2(ll.y, ll.x))   # lon, lat
	return out


# ------------------------------------------------------------------------------------------
# HTTP
# ------------------------------------------------------------------------------------------

## Downloads url to path (via .part). Returns "" on success, else an error text.
## Follows redirects itself (Godot only follows 301/302; Geofabrik answers with 307).
## Non-threaded on purpose: cancelling a threaded HTTPRequest blocks the main thread until the
## server answers (blocking sockets), which froze the game for minutes.
func _download(url: String, path: String, what: String) -> String:
	for hop in 6:
		var req := HTTPRequest.new()
		req.use_threads = false
		req.download_chunk_size = 1 << 20
		req.timeout = 0.0
		req.max_redirects = 8
		req.download_file = path + ".part"
		add_child(req)
		_req = req
		got = 0
		bps = 0.0
		_last_t = Time.get_ticks_msec()
		_last_got = 0
		var t0 := _last_t
		var err := req.request(url, PackedStringArray(["User-Agent: " + UA]))
		if err != OK:
			req.queue_free()
			return "Anfrage nicht möglich (Godot-Fehler %d)" % err
		var done := [false, 0, 0, PackedStringArray()]
		req.request_completed.connect(func(res: int, code: int, h: PackedStringArray, _b: PackedByteArray):
			done[0] = true
			done[1] = res
			done[2] = code
			done[3] = h)
		var stall_t := t0
		var next_log := 0.25
		while not done[0]:
			await get_tree().process_frame
			if _cancel or not is_instance_valid(req):
				return "abgebrochen"
			var now := Time.get_ticks_msec()
			var g := req.get_downloaded_bytes()
			if req.get_body_size() > 0:
				total = req.get_body_size()
			if g != got:
				got = g
				stall_t = now
			if now - _last_t >= 500:
				bps = lerpf(bps, (got - _last_got) / ((now - _last_t) / 1000.0), 0.5)
				_last_t = now
				_last_got = got
			if total > 2_000_000 and float(got) / total >= next_log:
				_log("%s: %d %% (%s von %s, %s/s)" % [what, int(next_log * 100.0), _mb(got), _mb(total), _mb(int(bps))])
				next_log += 0.25
			if now - stall_t > 60000:
				req.cancel_request()
				req.queue_free()
				_req = null
				DirAccess.remove_absolute(path + ".part")
				return "seit 60 s kommen keine Daten"
		_req = null
		req.queue_free()
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		if done[1] != HTTPRequest.RESULT_SUCCESS:
			DirAccess.remove_absolute(path + ".part")
			return MapDownloader._result_text(done[1])
		if done[2] in REDIRECTS:
			DirAccess.remove_absolute(path + ".part")
			var loc := _location(done[3], url)
			if loc == "":
				return "HTTP %d ohne Ziel" % done[2]
			_log("Weiterleitung (HTTP %d) → %s" % [done[2], loc])
			url = loc
			continue
		if done[2] != 200:
			DirAccess.remove_absolute(path + ".part")
			return "HTTP %d" % done[2]
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(path + ".part", path)
		_log("%s geladen: %s in %s" % [what, _mb(_file_size(path)), MapDownloader._secs(secs)], L_OK)
		return ""
	return "zu viele Weiterleitungen"


## Small request (HEAD or GET of a short text) with redirect handling.
## Returns [result, code, headers, body, final_url].
func _fetch(url: String, method := HTTPClient.METHOD_GET) -> Array:
	for hop in 6:
		var req := HTTPRequest.new()
		req.use_threads = false
		req.timeout = 20.0
		add_child(req)
		_req = req
		var err := req.request(url, PackedStringArray(["User-Agent: " + UA]), method)
		if err != OK:
			req.queue_free()
			return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), url]
		var res: Array = await req.request_completed
		_req = null
		req.queue_free()
		if _cancel:
			return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray(), url]
		if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] in REDIRECTS:
			var loc := _location(res[2], url)
			if loc == "":
				return res + [url]
			url = loc
			continue
		return res + [url]
	return [HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, 0, PackedStringArray(), PackedByteArray(), url]


## Size of the file behind url (after redirects); also remembers the final address.
func _head_size(url: String) -> int:
	var res := await _fetch(url, HTTPClient.METHOD_HEAD)
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_log("Größe nicht ermittelbar (%s)" % (MapDownloader._result_text(res[0]) if res[0] != HTTPRequest.RESULT_SUCCESS else "HTTP %d" % res[1]), L_WARN)
		return -1
	_resolved_url = res[4]
	if res[4] != url:
		_log("Der Auszug liegt unter %s" % res[4])
	for h in res[2]:
		if h.to_lower().begins_with("content-length:"):
			return int(h.substr(15).strip_edges())
	return -1


func _check_md5(md5_url: String, path: String) -> bool:
	var res := await _fetch(md5_url)
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_log("Prüfsumme nicht abrufbar – Datei wird ungeprüft verwendet.", L_WARN)
		return true
	var expect := (res[3] as PackedByteArray).get_string_from_ascii().strip_edges().get_slice(" ", 0).to_lower()
	var th := Thread.new()
	th.start(func(): return FileAccess.get_md5(path))
	while th.is_alive():
		await get_tree().process_frame
	var have: String = th.wait_to_finish()
	if expect.length() == 32 and have.to_lower() != expect:
		return false
	_log("Prüfsumme in Ordnung.", L_OK)
	return true


const REDIRECTS := [301, 302, 303, 307, 308]


static func _location(headers: PackedStringArray, base: String) -> String:
	for h in headers:
		if h.to_lower().begins_with("location:"):
			var loc := h.substr(9).strip_edges()
			if loc.begins_with("//"):
				return base.get_slice("//", 0) + loc
			if loc.begins_with("/"):
				var host_end := base.find("/", base.find("://") + 3)
				return (base.substr(0, host_end) if host_end > 0 else base) + loc
			if not loc.contains("://"):
				return base.substr(0, base.rfind("/") + 1) + loc
			return loc
	return ""


# ------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------

func _fresh(path: String) -> bool:
	if not FileAccess.file_exists(path) or _file_size(path) < 100:
		return false
	return Time.get_unix_time_from_system() - FileAccess.get_modified_time(path) < MAX_AGE_DAYS * 86400.0


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


static func _mb(b: int) -> String:
	return MapDownloader._fmt_bytes(b)


func _log(text: String, level := L_INFO) -> void:
	log_line.emit(text, level)
