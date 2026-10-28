class_name TerrainSource
extends Node
## Downloads the ground heights of a map once (#8): Terrarium tiles (height = R*256 + G + B/256 - 32768 m)
## from Mapterhorn (tiles.mapterhorn.com), which bundles the official 1 m terrain models (DGM1) of all German
## states and Copernicus GLO-30 elsewhere. Fallback: the AWS Terrain Tiles (Mapzen, SRTM-based, coarser).
## The tiles stay in <map>/terrain/ with a manifest; TerrainBake reads them in the bake thread.
## Testing: --terrain-url=<template with {z} {x} {y}> (e.g. a local http.server), --no-terrain.

signal log_line(text: String, level: int)

enum { L_INFO, L_OK, L_WARN, L_ERR }

const UA := "BaustellenManager/0.2 (private single-player game)"
const MAX_TILES := 64
const PARALLEL := 4
const SOURCES := [
	{"id": "mapterhorn", "name": "Mapterhorn", "host": "tiles.mapterhorn.com", "ext": "webp",
		"url": "https://tiles.mapterhorn.com/{z}/{x}/{y}.webp",
		"attribution": "Höhen: Mapterhorn (mapterhorn.com) mit den DGM1 der Länder, u. a. © Freie und Hansestadt Hamburg, LGV (dl-de/by-2.0); außerhalb: Copernicus GLO-30 © DLR e.V./Airbus, EU"},
	{"id": "aws", "name": "AWS Terrain Tiles", "host": "s3.amazonaws.com", "ext": "png",
		"url": "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png",
		"attribution": "Höhen: Terrain Tiles (Mapzen/AWS Open Data) aus SRTM, GMTED und ETOPO1"},
]

var running := false
var result := ""          # "ok", "none" (no heights: flat map), "cancelled"
var done := 0
var total := 0
var got_bytes := 0
var _cancel := false
var _reqs: Array = []


func cancel() -> void:
	_cancel = true
	for r in _reqs:
		if is_instance_valid(r):
			r.cancel_request()
			r.queue_free()
	_reqs.clear()


## Web Mercator tile range covering the map plus TerrainBake.MARGIN. Returns {zoom, x0, x1, y0, y1}.
static func tile_range(meta: Dictionary) -> Dictionary:
	Geo.setup(meta.center_lat, meta.center_lon)
	var half: float = float(meta.size_m) * 0.5 + TerrainBake.MARGIN + 100.0
	var nw := Geo.to_latlon(Vector2(-half, -half))
	var se := Geo.to_latlon(Vector2(half, half))
	for z in [13, 12, 11, 10]:
		var a := _tile_xy(nw.x, nw.y, z)
		var c := _tile_xy(se.x, se.y, z)
		var r := {"zoom": z, "x0": int(a.x), "x1": int(c.x), "y0": int(a.y), "y1": int(c.y)}
		if (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1) <= MAX_TILES:
			return r
	return {}


static func _tile_xy(lat: float, lon: float, z: int) -> Vector2:
	var n := pow(2.0, z)
	var s := sin(deg_to_rad(lat))
	return Vector2((lon + 180.0) / 360.0 * n, (0.5 - log((1.0 + s) / (1.0 - s)) / (4.0 * PI)) * n)


static func tile_name(mf: Dictionary, x: int, y: int) -> String:
	return "%s_%d_%d_%d.%s" % [mf.get("source", "t"), int(mf.zoom), x, y, mf.get("ext", "webp")]


## Manifest of complete tiles in dir, or {} if they are not all there.
static func read_manifest(dir: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(dir.path_join("terrain.json"))
	if txt == "":
		return {}
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY or not d.has("zoom"):
		return {}
	for y in range(int(d.y0), int(d.y1) + 1):
		for x in range(int(d.x0), int(d.x1) + 1):
			if not FileAccess.file_exists(dir.path_join(tile_name(d, x, y))):
				return {}
	return d


static func disabled() -> bool:
	return "--no-terrain" in OS.get_cmdline_user_args()


static func _url_override() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--terrain-url="):
			return a.substr(14)
	return ""


## Coroutine: await run(meta, dir). Afterwards check `result`.
func run(meta: Dictionary, dir: String) -> void:
	running = true
	result = ""
	DirAccess.make_dir_recursive_absolute(dir)
	var rng := tile_range(meta)
	if rng.is_empty():
		_log("Geländehöhen: Karte zu groß für die Höhenkacheln – sie bleibt flach.", L_WARN)
		_finish("none")
		return
	var sources: Array = SOURCES.duplicate(true)
	var ov := _url_override()
	if ov != "":
		var ext := ov.get_extension().get_slice("?", 0)
		sources = [{"id": "test", "name": "Test-Server", "host": ov.get_slice("/", 2), "ext": ext if ext != "" else "webp",
			"url": ov, "attribution": "Testdaten"}]
	for src in sources:
		var mf := {"source": src.id, "name": src.name, "attribution": src.attribution, "ext": src.ext,
			"zoom": rng.zoom, "x0": rng.x0, "x1": rng.x1, "y0": rng.y0, "y1": rng.y1,
			"time": Time.get_datetime_string_from_system()}
		total = (rng.x1 - rng.x0 + 1) * (rng.y1 - rng.y0 + 1)
		_log("Geländehöhen von %s (%s): %d Kacheln, Zoomstufe %d" % [src.name, src.host, total, rng.zoom])
		var ok := await _fetch_all(src, mf, dir)
		if _cancel:
			_finish("cancelled")
			return
		if ok:
			var f := FileAccess.open(dir.path_join("terrain.json"), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(mf, "\t"))
				f.close()
			_log("Geländehöhen geladen: %d Kacheln, %s." % [total, MapDownloader._fmt_bytes(got_bytes)], L_OK)
			_finish("ok")
			return
		_log("%s nicht erreichbar oder unvollständig." % src.name, L_WARN)
	_log("Keine Geländehöhen verfügbar – die Karte bleibt flach.", L_WARN)
	_finish("none")


func _finish(r: String) -> void:
	result = r
	running = false


func _fetch_all(src: Dictionary, mf: Dictionary, dir: String) -> bool:
	var todo: Array = []
	for y in range(int(mf.y0), int(mf.y1) + 1):
		for x in range(int(mf.x0), int(mf.x1) + 1):
			todo.append(Vector2i(x, y))
	done = 0
	got_bytes = 0
	var failed := [0]
	var active := [0]
	while (not todo.is_empty() or active[0] > 0) and not _cancel:
		while active[0] < PARALLEL and not todo.is_empty() and failed[0] == 0:
			var t: Vector2i = todo.pop_front()
			var path := dir.path_join(tile_name(mf, t.x, t.y))
			if FileAccess.file_exists(path):
				done += 1
				continue
			var url := String(src.url).replace("{z}", str(mf.zoom)).replace("{x}", str(t.x)).replace("{y}", str(t.y))
			active[0] += 1
			_get_tile(url, path, func(ok: bool):
				active[0] -= 1
				if ok:
					done += 1
				else:
					failed[0] += 1)
		if failed[0] > 0 and active[0] == 0:
			return false
		await get_tree().process_frame
	return failed[0] == 0 and not _cancel


## One tile with up to three attempts; follows redirects. cb(ok) when finished.
func _get_tile(url: String, path: String, cb: Callable) -> void:
	for attempt in 3:
		var hop_url := url
		for hop in 5:
			var req := HTTPRequest.new()
			req.use_threads = false
			req.timeout = 30.0
			add_child(req)
			_reqs.append(req)
			var err := req.request(hop_url, PackedStringArray(["User-Agent: " + UA]))
			if err != OK:
				_reqs.erase(req)
				req.queue_free()
				break
			var res: Array = await req.request_completed
			_reqs.erase(req)
			if is_instance_valid(req):
				req.queue_free()
			if _cancel:
				cb.call(false)
				return
			if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] in GeofabrikSource.REDIRECTS:
				var loc := GeofabrikSource._location(res[2], hop_url)
				if loc == "":
					break
				hop_url = loc
				continue
			if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200 and _is_image(res[3]):
				var body: PackedByteArray = res[3]
				var f := FileAccess.open(path + ".part", FileAccess.WRITE)
				if f:
					f.store_buffer(body)
					f.close()
					DirAccess.remove_absolute(path)
					DirAccess.rename_absolute(path + ".part", path)
					got_bytes += body.size()
					cb.call(true)
					return
			if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 404:
				cb.call(false)
				return
			break
		if attempt < 2:
			await get_tree().create_timer(1.5 * (attempt + 1)).timeout
			if _cancel:
				break
	cb.call(false)


## A PNG or WebP file (an error page from a proxy or captive portal is not saved as a tile).
static func _is_image(b: PackedByteArray) -> bool:
	if b.size() < 64:
		return false
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		return true
	return b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP"


func _log(text: String, level := L_INFO) -> void:
	log_line.emit(text, level)
