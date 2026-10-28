class_name MapDownloader
extends Node
## Downloads the OpenStreetMap data of a map in small pieces from several Overpass servers at
## the same time. A failed piece is retried on another server. A piece that is too big for the
## server (time or memory limit) is split into four. Everything is logged for the loading screen.
##
## Pieces:
##   t_*   1 km tiles (roads, buildings, areas, trees …), split down to 250 m
##   ri_*  ids of multipolygon relations per 2 km region (tiny answers)
##   rel_* the multipolygon relations themselves, fetched by id in batches (each one only once)
##   bus_* bus routes (members only, no geometry)

signal log_line(text: String, level: int)
signal done(ok: bool)

enum { L_INFO, L_OK, L_WARN, L_ERR }

const UA := "BaustellenManager/0.2 (private single-player game)"
const TILE := 1000.0
const MIN_TILE := 250.0
const REL_REGION := 2000.0
const MIN_REL_REGION := 500.0
const MIN_BUS_REGION := 1000.0
const REL_BATCH := 40
const MAX_ATTEMPTS := 8
const MANIFEST := "complete.json"
const ENDPOINTS := [
	{"host": "overpass-api.de", "url": "https://overpass-api.de/api/interpreter", "slots": 1},
	{"host": "overpass.private.coffee", "url": "https://overpass.private.coffee/api/interpreter", "slots": 2},
]
# progress weights
const W_TILES := 0.85
const W_RELIDX := 0.03
const W_REL := 0.09
const W_BUS := 0.03

var meta: Dictionary
var dir: String
var jobs: Array = []
var eps: Array = []
var running := false
var result := ""            # "", "ok", "failed", "cancelled"
var bytes_total := 0
var started_ms := 0
var _rel_batches_made := false
var _half := 0.0
var _last_ok_ms := 0
var diagnosis := ""          # short hint for the player when the download failed


# ------------------------------------------------------------------------------------------
# Public
# ------------------------------------------------------------------------------------------

static func is_complete(osm_dir: String) -> bool:
	return FileAccess.file_exists(osm_dir.path_join(MANIFEST))


static func read_manifest(osm_dir: String) -> Dictionary:
	var p := osm_dir.path_join(MANIFEST)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {"broken": true}


static func write_manifest(osm_dir: String, info: Dictionary) -> void:
	var f := FileAccess.open(osm_dir.path_join(MANIFEST), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(info, "\t"))


func start(m: Dictionary, osm_dir: String) -> void:
	meta = m
	dir = osm_dir
	_half = float(meta.size_m) * 0.5
	started_ms = Time.get_ticks_msec()
	_last_ok_ms = started_ms
	diagnosis = ""
	bytes_total = 0
	result = ""
	eps.clear()
	var defs: Array = ENDPOINTS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--overpass="):
			# testing / own server: --overpass=url1,url2
			defs = []
			for u in a.substr(11).split(","):
				defs.append({"host": u.replace("https://", "").replace("http://", "").replace("/api/interpreter", ""), "url": u, "slots": 1})
	for e in defs:
		eps.append({"host": e.host, "url": e.url, "slots": e.slots, "busy": 0, "cooldown_until": 0, "streak": 0,
			"ok": 0, "fail": 0, "bytes": 0, "last_error": "", "probe": "prüfe …"})
	jobs.clear()
	_rel_batches_made = false
	_plan_jobs()
	var todo := jobs.filter(func(j): return j.state == "pending").size()
	var have := jobs.size() - todo
	_log("Download geplant: %d Teile (%d schon vorhanden), %d Server parallel." % [jobs.size(), have, eps.size()])
	_maybe_make_rel_batches()
	running = true
	_probe_servers()


func cancel() -> void:
	if not running:
		return
	for j in jobs:
		if j.state == "active" and j.req:
			var req: HTTPRequest = j.req
			req.cancel_request()
			req.queue_free()
			j.req = null
			j.state = "pending"
	running = false
	result = "cancelled"
	_log("Download abgebrochen.", L_WARN)


func progress() -> float:
	var p := 0.0
	for j in jobs:
		if j.state == "done":
			p += j.weight
		elif j.state == "active" and j.get("body", -1) > 0:
			p += j.weight * clampf(float(j.get("got", 0)) / float(j.body), 0.0, 0.95)
	if _rel_batches_made and jobs.filter(func(j): return j.kind == "rel").is_empty():
		p += W_REL
	return clampf(p, 0.0, 1.0)


func leaf_tiles() -> Array:
	return jobs.filter(func(j): return j.kind == "tile" and j.state != "split")


## Data for the loading screen (polled a few times per second).
func snapshot() -> Dictionary:
	var now := Time.get_ticks_msec()
	var tiles := []
	var t_done := 0
	var t_total := 0
	var in_flight := 0
	for j in jobs:
		if j.state == "active":
			in_flight += int(j.get("got", 0))
		if j.kind != "tile" or j.state == "split":
			continue
		t_total += 1
		if j.state == "done":
			t_done += 1
		tiles.append({"rect": j.rect, "state": j.state, "retry": j.attempts > 0 and j.state == "pending"})
	var ep_rows := []
	for ep in eps:
		var parts := []
		for j in jobs:
			if j.state == "active" and j.ep == ep:
				var secs := (now - int(j.t0)) / 1000.0
				match j.phase:
					"Lädt":
						parts.append("%s lädt %s (%s/s)" % [j.label, _fmt_bytes(int(j.get("got", 0))), _fmt_bytes(int(j.get("bps", 0.0)))])
					_:
						parts.append("%s: %s %.0f s" % [j.label, j.phase, secs])
		var state := "busy"
		var text := ""
		if not parts.is_empty():
			text = ", ".join(parts)
		elif ep.get("down", false):
			state = "pause"
			text = "nicht erreichbar – neue Prüfung alle 60 s"
		elif now < int(ep.cooldown_until):
			state = "pause"
			text = "Pause %d s – %s" % [ceili((int(ep.cooldown_until) - now) / 1000.0), ep.last_error]
		else:
			state = "idle"
			text = "bereit" if running else "fertig"
		ep_rows.append({"host": ep.host, "state": state, "text": text, "ok": ep.ok, "fail": ep.fail,
			"bytes": ep.bytes, "probe": ep.probe})
	var pend := 0
	var act := 0
	var failed := 0
	var done_n := 0
	for j in jobs:
		match j.state:
			"pending":
				pend += 1
			"active":
				act += 1
			"failed":
				failed += 1
			"done":
				done_n += 1
	return {"tiles": tiles, "tiles_done": t_done, "tiles_total": t_total, "eps": ep_rows,
		"bytes": bytes_total + in_flight, "jobs_done": done_n, "jobs_pending": pend, "jobs_active": act,
		"jobs_failed": failed, "jobs_total": jobs.filter(func(j): return j.state != "split").size(),
		"progress": progress(), "half": _half}


# ------------------------------------------------------------------------------------------
# Planning
# ------------------------------------------------------------------------------------------

func _plan_jobs() -> void:
	var size: float = meta.size_m
	var n := int(ceil(size / TILE - 0.001))
	var total_area := size * size
	var tiles := []
	for i in n:
		for k in n:
			var r := Rect2(-_half + i * TILE, -_half + k * TILE, minf(TILE, size - i * TILE), minf(TILE, size - k * TILE))
			tiles.append({"rect": r, "label": "%s%d" % [char(65 + i), k + 1]})
	# load from the centre outwards: the yard area is ready first if anything goes wrong later
	tiles.sort_custom(func(a, b): return a.rect.get_center().length() < b.rect.get_center().length())
	var nr := int(ceil(size / REL_REGION - 0.001))
	for i in nr:
		for k in nr:
			var r := Rect2(-_half + i * REL_REGION, -_half + k * REL_REGION, minf(REL_REGION, size - i * REL_REGION), minf(REL_REGION, size - k * REL_REGION))
			_plan_rect("relidx", r, "Relationen %d" % (i * nr + k + 1), W_RELIDX * r.get_area() / total_area, MIN_REL_REGION)
	_plan_rect("bus", Rect2(-_half, -_half, size, size), "Buslinien", W_BUS, MIN_BUS_REGION)
	for t in tiles:
		_plan_rect("tile", t.rect, "Kachel " + t.label, W_TILES * t.rect.get_area() / total_area, MIN_TILE)


func _prefix(kind: String) -> String:
	match kind:
		"tile":
			return "t"
		"relidx":
			return "ri"
		"bus":
			return "bus"
	return "x"


func _rect_file(kind: String, r: Rect2) -> String:
	return "%s_%d_%d_%d.json" % [_prefix(kind), int(round(r.position.x)), int(round(r.position.y)), int(round(r.size.x))]


func _valid_file(f: String) -> bool:
	var p := dir.path_join(f)
	if not FileAccess.file_exists(p):
		return false
	var fa := FileAccess.open(p, FileAccess.READ)
	return fa != null and fa.get_length() > 40


func _quads(r: Rect2) -> Array:
	var h := r.size * 0.5
	return [Rect2(r.position, h), Rect2(r.position + Vector2(h.x, 0), h),
		Rect2(r.position + Vector2(0, h.y), h), Rect2(r.position + h, h)]


func _exists_below(kind: String, r: Rect2, min_size: float) -> bool:
	if r.size.x * 0.5 < min_size - 0.1:
		return false
	for q in _quads(r):
		if _valid_file(_rect_file(kind, q)) or _exists_below(kind, q, min_size):
			return true
	return false


## Adds a job for a rectangle; resumes earlier downloads (also ones that were already split).
func _plan_rect(kind: String, r: Rect2, label: String, weight: float, min_size: float) -> void:
	var f := _rect_file(kind, r)
	if _valid_file(f):
		var j := _new_job(kind, f, label, weight)
		j.rect = r
		j.state = "done"
		j.bytes = FileAccess.open(dir.path_join(f), FileAccess.READ).get_length()
		bytes_total += j.bytes
		jobs.append(j)
		return
	if _exists_below(kind, r, min_size):
		var qs := _quads(r)
		for qi in 4:
			_plan_rect(kind, qs[qi], "%s.%d" % [label, qi + 1], weight * 0.25, min_size)
		return
	var j2 := _new_job(kind, f, label, weight)
	j2.rect = r
	jobs.append(j2)


func _new_job(kind: String, file: String, label: String, weight: float) -> Dictionary:
	return {"kind": kind, "file": file, "label": label, "weight": weight, "state": "pending", "rect": Rect2(),
		"ids": PackedInt64Array(), "attempts": 0, "hard": 0, "not_before": 0, "last_host": "", "last_error": "",
		"bytes": 0, "ep": null, "req": null, "t0": 0, "phase": "", "got": 0, "body": -1, "bps": 0.0,
		"last_got": 0, "last_t": 0, "stall_t": 0}


## After all relation-id pieces are there: fetch the relations themselves in batches.
func _maybe_make_rel_batches() -> void:
	if _rel_batches_made:
		return
	for j in jobs:
		if j.kind == "relidx" and j.state != "done" and j.state != "split":
			return
	var ids := {}
	for j in jobs:
		if j.kind != "relidx" or j.state != "done":
			continue
		var doc = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(j.file)))
		if typeof(doc) == TYPE_DICTIONARY and doc.has("elements"):
			for el in doc.elements:
				if el.get("type", "") == "relation":
					ids[int(el.id)] = true
	var sorted: Array = ids.keys()
	sorted.sort()
	var nb := int(ceil(sorted.size() / float(REL_BATCH)))
	for b in nb:
		var part := PackedInt64Array(sorted.slice(b * REL_BATCH, (b + 1) * REL_BATCH))
		var j := _new_job("rel", "rel_%03d_%d.json" % [b, part[0]], "Flächen %d/%d" % [b + 1, nb], W_REL / maxf(1.0, nb))
		j.ids = part
		_add_rel_job(j)
	_rel_batches_made = true
	if nb > 0:
		_log("%d Flächen-/Gebäude-Relationen gefunden, sie werden in %d Paketen geladen." % [sorted.size(), nb])


## Adds a relation batch; picks up files from earlier runs, also halves of a batch that was split.
func _add_rel_job(j: Dictionary) -> void:
	jobs.append(j)
	if _valid_file(j.file):
		j.state = "done"
		j.bytes = FileAccess.open(dir.path_join(j.file), FileAccess.READ).get_length()
		bytes_total += j.bytes
		return
	if _rel_split_exists(j):
		j.state = "split"
		for h in _rel_halves(j):
			_add_rel_job(h)


func _rel_split_exists(j: Dictionary) -> bool:
	for h in _rel_halves(j):
		if _valid_file(h.file) or _rel_split_exists(h):
			return true
	return false


func _rel_halves(j: Dictionary) -> Array:
	var ids: PackedInt64Array = j.ids
	if ids.size() < 2:
		return []
	var m := ids.size() / 2
	var out := []
	for k in 2:
		var part := ids.slice(0, m) if k == 0 else ids.slice(m)
		var h := _new_job("rel", "rel_s%d_%d.json" % [part.size(), part[0]], "%s.%d" % [j.label, k + 1], j.weight * 0.5)
		h.ids = part
		out.append(h)
	return out


# ------------------------------------------------------------------------------------------
# Queries
# ------------------------------------------------------------------------------------------

func _bbox(r: Rect2) -> String:
	Geo.setup(meta.center_lat, meta.center_lon)
	var sw := Geo.to_latlon(Vector2(r.position.x, r.end.y))
	var ne := Geo.to_latlon(Vector2(r.end.x, r.position.y))
	return "%.6f,%.6f,%.6f,%.6f" % [sw.x, sw.y, ne.x, ne.y]


func _query(j: Dictionary) -> String:
	match j.kind:
		"tile":
			# smaller pieces ask for less server time: overloaded servers admit them more easily
			var to := 90 if j.rect.size.x > 600.0 else 60
			return ("[out:json][timeout:%d][bbox:%s];(" % [to, _bbox(j.rect)] +
				"way[\"highway\"];way[\"building\"];way[\"landuse\"];" +
				"way[\"leisure\"~\"^(park|garden|playground|pitch|sports_centre|golf_course)$\"];" +
				"way[\"natural\"~\"^(water|wood|scrub|grassland|heath|sand|beach|wetland)$\"];" +
				"way[\"waterway\"~\"^(riverbank|dock|canal|river)$\"];way[\"water\"];" +
				"way[\"amenity\"=\"parking\"];way[\"railway\"~\"^(rail|light_rail|subway|tram)$\"];" +
				"way[\"area:highway\"];" +
				"node[\"highway\"~\"^(traffic_signals|stop|give_way|crossing|bus_stop|street_lamp)$\"];" +
				"node[\"natural\"=\"tree\"];);out body geom qt;")
		"relidx":
			return ("[out:json][timeout:90][bbox:%s];(" % _bbox(j.rect) +
				"relation[\"type\"=\"multipolygon\"][\"building\"];" +
				"relation[\"type\"=\"multipolygon\"][\"landuse\"];" +
				"relation[\"type\"=\"multipolygon\"][\"leisure\"~\"^(park|garden)$\"];" +
				"relation[\"type\"=\"multipolygon\"][\"natural\"~\"^(water|wood|scrub|grassland|wetland)$\"];" +
				"relation[\"type\"=\"multipolygon\"][\"waterway\"=\"riverbank\"];" +
				"relation[\"type\"=\"multipolygon\"][\"water\"];);out ids;")
		"rel":
			var ids: PackedInt64Array = j.ids
			var s := []
			for id in ids:
				s.append(str(id))
			return "[out:json][timeout:120];relation(id:%s);out body geom;" % ",".join(s)
		"bus":
			return "[out:json][timeout:90][bbox:%s];relation[\"type\"=\"route\"][\"route\"=\"bus\"];out body;" % _bbox(j.rect)
	return ""


# ------------------------------------------------------------------------------------------
# Scheduler
# ------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_msec()
	for j in jobs:
		if j.state == "active":
			_poll(j, now)
	# nothing works at all for a while (no internet, firewall, all servers down): stop and say so
	if now - _last_ok_ms > 150000 and eps.all(func(e): return int(e.streak) >= 3 or e.get("down", false)):
		for j in jobs:
			if j.state == "active":
				_abort(j)
			if j.state == "pending" or j.state == "active":
				j.state = "failed"
		_log("Seit %d s kam von keinem Server eine Antwort – Download wird angehalten." % ((now - _last_ok_ms) / 1000), L_ERR)
		_finish()
		return
	for ep in eps:
		if ep.get("down", false):
			if not ep.get("probing", false) and now >= int(ep.get("next_probe", 0)):
				_probe(ep)
			continue
		while ep.busy < ep.slots and now >= int(ep.cooldown_until):
			var j := _next_job(ep, now)
			if j.is_empty():
				break
			_start_job(j, ep, now)
	var busy := false
	for j in jobs:
		if j.state == "pending" or j.state == "active":
			busy = true
			break
	if busy:
		return
	if not _rel_batches_made and not jobs.any(func(j): return j.kind == "relidx" and j.state == "failed"):
		_maybe_make_rel_batches()
		if jobs.any(func(j): return j.state == "pending"):
			return
	_finish()


func _next_job(ep: Dictionary, now: int) -> Dictionary:
	var fallback := {}
	for j in jobs:
		if j.state != "pending" or int(j.not_before) > now:
			continue
		if j.last_host != ep.host:
			return j
		if fallback.is_empty():
			fallback = j
	if fallback.is_empty():
		return {}
	# only take a job back to the server where it just failed if no other server can take it soon
	for other in eps:
		if other != ep and not other.get("down", false) and other.busy < other.slots and now >= int(other.cooldown_until) - 3000:
			return {}
	return fallback


func _start_job(j: Dictionary, ep: Dictionary, now: int) -> void:
	var req := HTTPRequest.new()
	req.timeout = 200.0
	# not threaded: cancelling a threaded request blocks the main thread (blocking sockets) until
	# the server answers – that froze the game for minutes when a server did not respond
	req.use_threads = false
	req.download_chunk_size = 1 << 18
	req.accept_gzip = true
	req.download_file = dir.path_join(j.file + ".part")
	add_child(req)
	var headers := PackedStringArray(["User-Agent: " + UA, "Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json"])
	j.attempts += 1
	var err := req.request(ep.url, headers, HTTPClient.METHOD_POST, "data=" + _query(j).uri_encode())
	if err != OK:
		req.queue_free()
		_fail(j, ep, "Anfrage konnte nicht gestartet werden (Godot-Fehler %d)" % err, "net", now, false)
		return
	req.request_completed.connect(_on_completed.bind(j, ep, req))
	j.state = "active"
	j.ep = ep
	j.req = req
	j.t0 = now
	j.phase = "Verbinde"
	j.got = 0
	j.body = -1
	j.bps = 0.0
	j.last_got = 0
	j.last_t = now
	j.stall_t = now
	ep.busy += 1
	_log("%s → %s%s" % [j.label, ep.host, (" (Versuch %d)" % j.attempts) if j.attempts > 1 else ""])


func _poll(j: Dictionary, now: int) -> void:
	var req: HTTPRequest = j.req
	if req == null:
		return
	match req.get_http_client_status():
		HTTPClient.STATUS_RESOLVING:
			j.phase = "DNS-Abfrage"
		HTTPClient.STATUS_CONNECTING:
			j.phase = "verbinde"
		HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_REQUESTING:
			j.phase = "Server rechnet"
		HTTPClient.STATUS_BODY:
			j.phase = "Lädt"
	var got := req.get_downloaded_bytes()
	j.body = req.get_body_size()
	if got != int(j.got):
		j.got = got
		j.stall_t = now
	var dt := (now - int(j.last_t)) / 1000.0
	if dt >= 0.5:
		var inst := (got - int(j.last_got)) / dt
		j.bps = lerpf(float(j.bps), inst, 0.5)
		j.last_got = got
		j.last_t = now
	# watchdogs
	var ep: Dictionary = j.ep
	if (j.phase == "DNS-Abfrage" or j.phase == "verbinde") and now - int(j.t0) > 20000:
		_abort(j)
		_fail(j, ep, "keine Verbindung nach 20 s", "net", now)
	elif j.phase == "Lädt" and now - int(j.stall_t) > 45000:
		_abort(j)
		_fail(j, ep, "Download hängt seit 45 s", "stall", now)
	elif j.phase != "Lädt" and now - int(j.t0) > 180000:
		_abort(j)
		_fail(j, ep, "Server antwortet nicht (180 s)", "timeout", now)


func _abort(j: Dictionary) -> void:
	var req: HTTPRequest = j.req
	if req:
		if req.request_completed.is_connected(_on_completed):
			req.request_completed.disconnect(_on_completed)
		req.cancel_request()
		req.queue_free()
	j.req = null
	var ep: Dictionary = j.ep
	ep.busy = maxi(0, ep.busy - 1)
	DirAccess.remove_absolute(dir.path_join(j.file + ".part"))


func _on_completed(res: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, j: Dictionary, ep: Dictionary, req: HTTPRequest) -> void:
	if j.req != req:
		return
	var now := Time.get_ticks_msec()
	var secs := (now - int(j.t0)) / 1000.0
	j.req = null
	req.queue_free()
	ep.busy = maxi(0, ep.busy - 1)
	if not running:
		return
	var part := dir.path_join(j.file + ".part")
	if res != HTTPRequest.RESULT_SUCCESS:
		DirAccess.remove_absolute(part)
		_fail(j, ep, _result_text(res), "timeout" if res == HTTPRequest.RESULT_TIMEOUT else "net", now)
		return
	if code != 200:
		var txt := _error_snippet(part)
		DirAccess.remove_absolute(part)
		var cls := "busy"
		var msg := "HTTP %d" % code
		match code:
			429:
				cls = "rate"
				msg = "HTTP 429: zu viele Anfragen"
			406:
				cls = "rate"
				msg = "HTTP 406: Anfrage abgelehnt"
			504:
				msg = "HTTP 504: Server überlastet"
			503:
				msg = "HTTP 503: Server nicht verfügbar"
			400:
				cls = "bad"
				msg = "HTTP 400: Server lehnt die Abfrage ab"
		if txt != "":
			msg += " – " + txt
		if txt.contains("timed out") or txt.contains("out of memory") or txt.contains("run out of memory"):
			cls = "too_big"
		_fail(j, ep, msg, cls, now)
		return
	var check := _check_json(part)
	if check.cls != "":
		DirAccess.remove_absolute(part)
		_fail(j, ep, check.msg, check.cls, now)
		return
	var size := FileAccess.open(part, FileAccess.READ).get_length()
	DirAccess.remove_absolute(dir.path_join(j.file))
	DirAccess.rename_absolute(part, dir.path_join(j.file))
	j.state = "done"
	j.bytes = size
	bytes_total += size
	ep.ok += 1
	ep.bytes += size
	ep.streak = 0
	ep.down = false
	_last_ok_ms = now
	_log("%s ✓ %s · %s in %s" % [j.label, ep.host, _fmt_bytes(size), _secs(secs)], L_OK)
	if j.kind == "relidx":
		_maybe_make_rel_batches()


## Validates a downloaded Overpass answer: JSON, complete, no runtime error.
func _check_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"cls": "net", "msg": "Antwort konnte nicht gespeichert werden"}
	var flen := f.get_length()
	var head := f.get_buffer(mini(256, flen)).get_string_from_utf8().strip_edges()
	f.seek(maxi(0, flen - 1500))
	var tail := f.get_buffer(1500).get_string_from_utf8()
	f.close()
	if not head.begins_with("{"):
		var snippet := _strip_html(head)
		return {"cls": "busy", "msg": "keine JSON-Antwort: " + _one_line(snippet).left(140)}
	var ri := tail.find("\n  \"remark\"")
	if ri >= 0:
		var remark := _json_string_after(tail, ri + 1)
		var cls := "busy"
		if remark.contains("timed out") or remark.contains("memory"):
			cls = "too_big"
		return {"cls": cls, "msg": "Server-Abbruch: " + remark.left(160)}
	if not tail.strip_edges().ends_with("}"):
		return {"cls": "stall", "msg": "Antwort unvollständig (%s)" % _fmt_bytes(flen)}
	return {"cls": "", "msg": ""}


func _fail(j: Dictionary, ep: Dictionary, msg: String, cls: String, now: int, count_attempt := true) -> void:
	if not count_attempt or cls == "rate":
		# a refusal because of too many requests is not the piece's fault
		j.attempts = maxi(0, j.attempts - 1)
	j.state = "pending"
	j.req = null
	j.last_error = msg
	j.last_host = ep.host
	ep.fail += 1
	ep.last_error = msg.left(60)
	var pause := 0.0
	match cls:
		"net":
			ep.streak += 1
			pause = minf(120.0, 15.0 * ep.streak)
		"rate":
			ep.streak += 1
			pause = minf(180.0, 30.0 * ep.streak)
		"busy":
			# overloaded server: back off exponentially (15, 30, 60, 120 s), the piece itself is fine
			ep.streak += 1
			pause = minf(120.0, 15.0 * pow(2.0, ep.streak - 1))
		"timeout":
			ep.streak += 1
			pause = minf(60.0, 10.0 * ep.streak)
			j.hard += 1
		"too_big":
			j.hard += 2
		"stall":
			pause = 5.0
		"bad":
			j.hard += 1
	if pause > 0.0:
		ep.cooldown_until = now + int(pause * 1000.0)
	var lvl := L_WARN
	var what := msg
	if pause > 0.0:
		what += " – Server-Pause %d s" % int(pause)
	# too heavy for the server: split into smaller pieces
	if j.hard >= 2 and _split(j):
		_log("%s ✗ %s: %s → wird in kleinere Teile geteilt" % [j.label, ep.host, what], lvl)
		return
	if j.attempts >= MAX_ATTEMPTS:
		j.state = "failed"
		_log("%s ✗ nach %d Versuchen aufgegeben: %s" % [j.label, j.attempts, msg], L_ERR)
		return
	j.not_before = now + 1500 * j.attempts
	_log("%s ✗ %s: %s → neuer Versuch auf anderem Server" % [j.label, ep.host, what], lvl)


## A server did not answer the status check: take its pieces that are still connecting away.
func _server_down(ep: Dictionary, why: String, pause: float) -> void:
	var now := Time.get_ticks_msec()
	ep.cooldown_until = maxi(int(ep.cooldown_until), now + int(pause * 1000.0))
	ep.last_error = why
	for j in jobs:
		if j.state == "active" and j.ep == ep and j.phase != "Lädt":
			_abort(j)
			j.state = "pending"
			j.last_host = ep.host
			j.attempts = maxi(0, j.attempts - 1)
			_log("%s wird an einen anderen Server gegeben." % j.label)


## A hint for the player from the errors that happened.
func _diagnose(failed: Array) -> String:
	var tls := 0
	var net := 0
	var busy := 0
	for j in failed:
		var e: String = j.last_error
		if e.contains("TLS"):
			tls += 1
		elif e.contains("Verbindung") or e.contains("DNS") or e.contains("keine Antwort"):
			net += 1
		elif e.contains("429") or e.contains("504") or e.contains("503") or e.contains("Server"):
			busy += 1
	if tls >= maxi(net, busy) and tls > 0:
		return ("Die sichere Verbindung (HTTPS) zu den Kartenservern scheitert. Häufige Ursache: ein Virenscanner " +
			"oder eine Firewall prüft HTTPS-Verbindungen – dann eine Ausnahme für BaustellenManager.exe anlegen.")
	if net >= busy and net > 0:
		return "Die Kartenserver sind nicht erreichbar. Bitte Internetverbindung und Firewall prüfen."
	if busy > 0:
		return "Die öffentlichen Kartenserver sind gerade überlastet. In ein paar Minuten erneut versuchen – fertige Teile bleiben gespeichert."
	return ""


func _split(j: Dictionary) -> bool:
	var children := []
	match j.kind:
		"tile", "relidx", "bus":
			var min_size := MIN_TILE if j.kind == "tile" else (MIN_REL_REGION if j.kind == "relidx" else MIN_BUS_REGION)
			if j.rect.size.x * 0.5 < min_size - 0.1:
				return false
			var qs := _quads(j.rect)
			for qi in 4:
				var c := _new_job(j.kind, _rect_file(j.kind, qs[qi]), "%s.%d" % [j.label, qi + 1], j.weight * 0.25)
				c.rect = qs[qi]
				children.append(c)
		"rel":
			children = _rel_halves(j)
			if children.is_empty():
				return false
	j.state = "split"
	var at := jobs.find(j)
	for k in children.size():
		var c: Dictionary = children[k]
		if _valid_file(c.file):
			c.state = "done"
			c.bytes = FileAccess.open(dir.path_join(c.file), FileAccess.READ).get_length()
			bytes_total += c.bytes
		jobs.insert(at + 1 + k, c)
	return true


func _finish() -> void:
	running = false
	var failed := jobs.filter(func(j): return j.state == "failed")
	var secs := (Time.get_ticks_msec() - started_ms) / 1000.0
	if failed.is_empty():
		result = "ok"
		var files := []
		for j in jobs:
			if j.state == "done":
				files.append(j.file)
		write_manifest(dir, {"files": files, "bytes": bytes_total, "seconds": secs,
			"time": Time.get_datetime_string_from_system()})
		_log("Download fertig: %d Teile, %s in %d s." % [files.size(), _fmt_bytes(bytes_total), int(secs)], L_OK)
		done.emit(true)
	else:
		result = "failed"
		diagnosis = _diagnose(failed)
		var names := []
		for j in failed:
			if j.last_error != "":
				names.append("%s (%s)" % [j.label, j.last_error.left(50)])
		_log("Download unvollständig: %d Teile fehlen: %s" % [failed.size(), "; ".join(names.slice(0, 6))], L_ERR)
		done.emit(false)


# ------------------------------------------------------------------------------------------
# Server check (only for the log: shows right away whether a server is reachable)
# ------------------------------------------------------------------------------------------

func _probe_servers() -> void:
	for ep in eps:
		_probe(ep)


## Status check of one server. A server that does not answer is marked "down" and gets no pieces
## until a later check (every 60 s) succeeds.
func _probe(ep: Dictionary) -> void:
	ep.probing = true
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var url: String = ep.url.replace("/interpreter", "/status")
	var err := req.request(url, PackedStringArray(["User-Agent: " + UA]))
	if err != OK:
		req.queue_free()
		ep.probing = false
		return
	var t0 := Time.get_ticks_msec()
	req.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		ep.probing = false
		ep.next_probe = Time.get_ticks_msec() + 60000
		if not running:
			return
		var ms := Time.get_ticks_msec() - t0
		var was_down: bool = ep.get("down", false)
		if res != HTTPRequest.RESULT_SUCCESS:
			ep.probe = "nicht erreichbar"
			if not was_down:
				_log("Server %s nicht erreichbar: %s – er wird vorerst nicht benutzt." % [ep.host, _result_text(res)], L_WARN)
			ep.down = true
			_server_down(ep, "nicht erreichbar (%s)" % _result_text(res), 0.0)
			return
		if was_down:
			_log("Server %s ist wieder erreichbar." % ep.host, L_OK)
		ep.down = false
		if code != 200:
			ep.probe = "überlastet"
			_log("Server %s antwortet, ist aber überlastet (HTTP %d)." % [ep.host, code], L_WARN)
			return
		var txt := _strip_html(body.get_string_from_utf8())
		var slots := ""
		for line in txt.split("\n"):
			if "slots available" in line or "Slot available" in line or "Rate limit" in line:
				slots += line.strip_edges() + " "
		ep.probe = "erreichbar (%d ms)" % ms
		_log("Server %s erreichbar (%d ms, HTTP %d)%s" % [ep.host, ms, code, (": " + slots.strip_edges()) if slots != "" else ""]))


# ------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------

func _log(text: String, level := L_INFO) -> void:
	log_line.emit(text, level)


func _error_snippet(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_buffer(mini(4000, f.get_length())).get_string_from_utf8()
	f.close()
	txt = _one_line(_strip_html(txt))
	var i := txt.find("rror:")
	if i >= 0:
		txt = txt.substr(maxi(0, i - 1))
	return txt.left(160)


## Reads the JSON string value that starts after position `from` ("key": "value").
static func _json_string_after(s: String, from: int) -> String:
	var q := s.find("\"", s.find(":", from))
	if q < 0:
		return s.substr(from).strip_edges()
	var out := ""
	var i := q + 1
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			out += s[i + 1]
			i += 2
			continue
		if c == "\"":
			break
		out += c
		i += 1
	return out


static func _secs(t: float) -> String:
	return ("%.1f s" % t).replace(".", ",")


## Collapses whitespace and markdown so an error text fits one log line.
static func _one_line(s: String) -> String:
	var re := RegEx.new()
	re.compile("[#*`]+")
	s = re.sub(s, "", true)
	var ws := RegEx.new()
	ws.compile("\\s+")
	return ws.sub(s, " ", true).strip_edges()


static func _strip_html(s: String) -> String:
	var re := RegEx.new()
	re.compile("<[^>]*>")
	s = re.sub(s, " ", true)
	var ws := RegEx.new()
	ws.compile("[ \\t\\r]+")
	s = ws.sub(s, " ", true)
	return s.replace("&quot;", "\"").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").strip_edges()


static func _result_text(res: int) -> String:
	match res:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "keine Verbindung möglich"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Servername nicht auflösbar (DNS)"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Verbindung abgebrochen"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS-/Zertifikatsfehler"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "keine Antwort"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Antwort zu groß"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "Antwort nicht entpackbar"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Anfrage fehlgeschlagen"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Datei kann nicht angelegt werden"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Datei kann nicht geschrieben werden"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "zu viele Weiterleitungen"
		HTTPRequest.RESULT_TIMEOUT:
			return "Zeitüberschreitung"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "Antwort beschädigt"
	return "Fehler %d" % res


static func _fmt_bytes(b: int) -> String:
	if b < 1024:
		return "%d B" % b
	if b < 1024 * 1024:
		return "%.0f KB" % (b / 1024.0)
	return ("%.1f MB" % (b / 1048576.0)).replace(".", ",")
