class_name IssueStore
extends RefCounted
## "Meldungen": bugs, wishes and improvements reported from inside the game, stored as folders so
## that agent sessions can work on them (see tools/agent/issues.py and .claude/skills/issue-ablauf).
##
## <data>/issues/<nnnn>-<slug>/
##   issue.json        written once when reporting: text, type, area, priority, pins, camera,
##                     selection, game/map/build/system context, list of attachments
##   beschreibung.md   the text as typed (plus title)
##   bild_N.png        screenshots; bild_N_markiert.png has the pins drawn in
##   spielstand.sav    complete game state at report time (load with --e2e=repro)
##   zustand.txt/.json readable dump of sites, vehicles, traffic, selection
##   logs/             engine log tail, in-game notifications, map loading log
##   verlauf.jsonl     append-only thread of user and agents: comment, question, answer, status, fix
##   claims/<n>/       agent claims (written by tools/agent/issues.py, never by the game)
## The current status is the "status" field of the last thread entry that has one.

const STATUS_TEXT := {
	"offen": "offen", "in_arbeit": "in Arbeit", "rueckfrage": "Rückfrage", "bitte_pruefen": "bitte prüfen",
	"erledigt": "erledigt", "abgelehnt": "abgelehnt",
}
const TYPES := {"fehler": "Fehler", "wunsch": "Wunsch", "verbesserung": "Verbesserung"}
## Display names incl. types only agents create ("aufgabe" = task from a chat with Claude).
const TYPE_TEXT := {"fehler": "Fehler", "wunsch": "Wunsch", "verbesserung": "Verbesserung", "aufgabe": "Aufgabe"}
const AREAS := {
	"auto": "automatisch", "verkehr": "Verkehr", "baustelle": "Baustelle", "fahrzeuge": "Fahrzeuge",
	"karte": "Karte & Laden", "oberflaeche": "Oberfläche", "grafik": "Grafik", "leistung": "Leistung",
	"wirtschaft": "Wirtschaft", "sonstiges": "Sonstiges",
}
const PRIOS := {"niedrig": "niedrig", "normal": "normal", "hoch": "hoch", "blockiert": "blockiert mich"}
## Statuses in which the player is asked to do something.
const NEEDS_USER := ["rueckfrage", "bitte_pruefen"]


static func root() -> String:
	return Game.data_path("issues")


static func list_all() -> Array:
	var out: Array = []
	var r := root()
	if not DirAccess.dir_exists_absolute(r):
		return out
	for d in DirAccess.get_directories_at(r):
		var info := summary(r.path_join(d))
		if not info.is_empty():
			out.append(info)
	out.sort_custom(func(a, b): return a.id > b.id)
	return out


## Small dictionary for lists: id, folder, title, type, area, priority, status, updated, claimed_by.
static func summary(folder: String) -> Dictionary:
	var meta := _read_json(folder.path_join("issue.json"))
	if meta.is_empty():
		return {}
	var th := thread(folder)
	var st := "offen"
	var updated: String = meta.get("created", "")
	for e in th:
		if e.has("status"):
			st = e.status
		updated = e.get("t", updated)
	return {"id": int(meta.get("id", 0)), "folder": folder, "title": meta.get("title", ""), "type": meta.get("type", "fehler"),
		"area": meta.get("area", "sonstiges"), "priority": meta.get("priority", "normal"), "status": st,
		"updated": updated, "entries": th.size(), "claimed_by": active_claim(folder)}


static func load_issue(folder: String) -> Dictionary:
	var meta := _read_json(folder.path_join("issue.json"))
	meta["folder"] = folder
	meta["thread"] = thread(folder)
	meta["status"] = "offen"
	for e in meta.thread:
		if e.has("status"):
			meta.status = e.status
	return meta


static func thread(folder: String) -> Array:
	var out: Array = []
	var p := folder.path_join("verlauf.jsonl")
	if not FileAccess.file_exists(p):
		return out
	for line in FileAccess.get_file_as_string(p).split("\n"):
		line = line.strip_edges()
		if line == "":
			continue
		var e = JSON.parse_string(line)
		if e is Dictionary:
			out.append(e)
	return out


## Appends one entry (adds time, author and a unique "eid"). Append-only, so the game and agents never
## overwrite each other's lines. Godot has no O_APPEND: between seek_end() and the write an agent could
## append at the same moment, so the line is verified and written again if it got lost.
static func append(folder: String, entry: Dictionary) -> void:
	entry["t"] = Time.get_datetime_string_from_system(false, true)
	entry["eid"] = "%08x" % (randi() & 0x7fffffff)
	if not entry.has("by"):
		entry["by"] = "Spieler"
	var p := folder.path_join("verlauf.jsonl")
	var line := JSON.stringify(entry)
	for attempt in 4:
		var f := FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			push_error("Meldung: Verlauf nicht schreibbar: " + p)
			return
		f.seek_end()
		f.store_line(line)
		f.close()
		for e in thread(folder).slice(-50):
			if String(e.get("eid", "")) == entry.eid:
				return
	push_error("Meldung: Eintrag im Verlauf nicht wiedergefunden: " + p)


## Name of the session that currently works on the issue ("" if none). Same rules as
## tools/agent/issues.py: highest claims/<n>/, released by a "freigegeben" file, alive while
## owner.json heartbeat or the mtime of "herzschlag" is younger than 6 h.
static func active_claim(folder: String) -> String:
	var cdir := folder.path_join("claims")
	if not DirAccess.dir_exists_absolute(cdir):
		return ""
	var best := -1
	for d in DirAccess.get_directories_at(cdir):
		if d.is_valid_int():
			best = maxi(best, d.to_int())
	if best < 0:
		return ""
	var g := cdir.path_join(str(best))
	if FileAccess.file_exists(g.path_join("freigegeben")):
		return ""
	var owner := _read_json(g.path_join("owner.json"))
	var hb: float = float(owner.get("heartbeat_unix", 0))
	for f in ["owner.json", "herzschlag"]:
		if FileAccess.file_exists(g.path_join(f)):
			hb = maxf(hb, float(FileAccess.get_modified_time(g.path_join(f))))
	if owner.get("released", false) or Time.get_unix_time_from_system() - hb > 6 * 3600:
		return ""
	return String(owner.get("session", "?"))


## Next free issue id, reserved with mkdir <issues>/.ids/<n> (atomic, like tools/agent/issues.py),
## so a report from the game and an agent creating a task at the same moment never share an id.
static func next_id() -> int:
	var m := 0
	var r := root()
	var ids := r.path_join(".ids")
	DirAccess.make_dir_recursive_absolute(ids)
	for d in DirAccess.get_directories_at(r):
		var head := d.get_slice("-", 0)
		if head.is_valid_int():
			m = maxi(m, head.to_int())
	for d in DirAccess.get_directories_at(ids):
		if d.is_valid_int():
			m = maxi(m, d.to_int())
	var n := m + 1
	while DirAccess.make_dir_absolute(ids.path_join(str(n))) != OK:
		n += 1
		if n > m + 1000:  # folder not writable: fall back to the plain maximum
			return m + 1
	return n


static func slug(t: String) -> String:
	var s := t.to_lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
	var re := RegEx.new()
	re.compile("[^a-z0-9]+")
	s = re.sub(s, "-", true).strip_edges().trim_prefix("-").trim_suffix("-")
	return s.left(40).trim_suffix("-")


## Writes a new issue. report: {title, text, type, area, priority, pins, camera, selection, context};
## shots: [{image: Image, pins_screen: [[x, y, label], ...]}]. Returns the folder.
static func create(report: Dictionary, shots: Array, with_save: bool, with_logs: bool) -> String:
	var id := next_id()
	var folder := root().path_join("%04d-%s" % [id, slug(report.get("title", "meldung"))])
	DirAccess.make_dir_recursive_absolute(folder.path_join("logs"))
	var files: Array = []
	for i in shots.size():
		var img: Image = shots[i].image
		var name := "bild_%d.png" % (i + 1)
		img.save_png(folder.path_join(name))
		files.append(name)
		var pins: Array = shots[i].get("pins_screen", [])
		if not pins.is_empty():
			var marked := img.duplicate() as Image
			for pn in pins:
				_draw_pin(marked, Vector2(pn[0], pn[1]))
			var mname := "bild_%d_markiert.png" % (i + 1)
			marked.save_png(folder.path_join(mname))
			files.append(mname)
	if with_save and Game.world:
		if Game.write_save_file(folder.path_join("spielstand.sav")):
			files.append("spielstand.sav")
	var dump := state_dump()
	var tf := FileAccess.open(folder.path_join("zustand.txt"), FileAccess.WRITE)
	if tf:
		tf.store_string(dump.text)
	var jf := FileAccess.open(folder.path_join("zustand.json"), FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(dump.data, "\t"))
	files.append_array(["zustand.txt", "zustand.json"])
	if with_logs:
		files.append_array(_copy_logs(folder.path_join("logs")))
	var meta := report.duplicate(true)
	meta["id"] = id
	meta["created"] = Time.get_datetime_string_from_system(false, true)
	meta["build"] = Game.build_info
	meta["files"] = files
	meta["system"] = system_info()
	meta["map"] = Game.map_meta
	var f := FileAccess.open(folder.path_join("issue.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	var md := FileAccess.open(folder.path_join("beschreibung.md"), FileAccess.WRITE)
	md.store_string("# %s\n\n%s\n" % [report.get("title", ""), report.get("text", "")])
	md.close()
	append(folder, {"kind": "status", "status": "offen", "text": "Gemeldet"})
	return folder


static func _draw_pin(img: Image, p: Vector2) -> void:
	var c := Color(1.0, 0.42, 0.08)
	var w := img.get_width()
	var h := img.get_height()
	for r in [20, 19, 18, 17]:
		for a in 72:
			var q: Vector2 = p + Vector2(cos(a * TAU / 72.0), sin(a * TAU / 72.0)) * float(r)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				img.set_pixelv(Vector2i(q), c)
	for d in range(-7, 8):
		for k in [-1, 0, 1]:
			var a1 := Vector2i(int(p.x) + d, int(p.y) + k)
			var a2 := Vector2i(int(p.x) + k, int(p.y) + d)
			for q in [a1, a2]:
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
					img.set_pixelv(q, c)


# ------------------------------------------------------------------------------------------
# Context
# ------------------------------------------------------------------------------------------

static func system_info() -> Dictionary:
	return {
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"fps": Engine.get_frames_per_second(),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"godot": Engine.get_version_info().string,
	}


## Readable and structured snapshot of what is going on (for agents).
static func state_dump() -> Dictionary:
	var lines := PackedStringArray()
	var data := {"time": {"day": Clock.day, "clock": Clock.time_string(), "speed": Clock.speed_index},
		"money": Game.company.get("money", 0.0), "sites": [], "vehicles": [], "selected": ""}
	lines.append("Build %s · %s" % [Game.version_text(), Time.get_datetime_string_from_system()])
	lines.append("Firma %s · Tag %d %s · Geld %.0f €" % [Game.company.get("name", ""), Clock.day, Clock.time_string(), Game.company.get("money", 0.0)])
	var w = Game.world
	if w == null:
		lines.append("(keine Welt geladen)")
		return {"text": "\n".join(lines), "data": data}
	if Game.selected and is_instance_valid(Game.selected):
		data.selected = _obj_name(Game.selected)
		lines.append("Ausgewählt: " + data.selected)
	lines.append("Verkehr: %d Fahrzeuge" % w.traffic.traffic_count())
	lines.append("")
	for s in w.jobs.all_sites():
		var sd := {"id": s.sid, "title": s.job.short_title(), "location": s.job.location(), "step": s.step_id(),
			"phase": s.phase, "running": s.running, "sub": s.sub, "progress": s.progress, "status": s.status,
			"pile": [s.pile_mat, s.pile_m3], "vehicles": []}
		lines.append("BAUSTELLE %s (%s) – Schritt %s, läuft=%s, sub=%s, %.0f %%, „%s“" % [sd.title, sd.location, sd.step, s.running, s.sub, s.progress * 100.0, s.status])
		for v in s.vehicles:
			if is_instance_valid(v):
				sd.vehicles.append({"name": v.vname, "spot": s.spot_of.get(v, ""), "in_place": s.in_place.has(v)})
		data.sites.append(sd)
	lines.append("")
	for v in w.fleet.vehicles:
		var vd := {"name": v.vname, "type": v.def_id, "state": v.state, "status": v.status_text,
			"pos": [snappedf(v.position.x, 0.1), snappedf(v.position.z, 0.1)], "site": v.site.job.short_title() if v.site else "",
			"cargo": v.cargo_text()}
		var route := ""
		if v.agent:
			var pc: Dictionary = v.agent.route[v.agent.pi]
			vd["agent"] = {"piece": v.agent.pi, "pieces": v.agent.route.size(), "piece_type": pc.t, "s": v.agent.s,
				"s1": pc.s1, "v": v.agent.v, "reason": v.agent.reason, "wait_s": v.agent.wait_t}
			route = " · Route %d/%d Typ %d s=%.1f/%.1f v=%.1f warten=%.0f s Grund=%s" % [v.agent.pi, v.agent.route.size(), pc.t, v.agent.s, pc.s1, v.agent.v, v.agent.wait_t, v.agent.reason]
		data.vehicles.append(vd)
		lines.append("%-14s %-9s %-34s (%.0f, %.0f) %s%s" % [v.vname, v.state, v.status_text, v.position.x, v.position.z, v.cargo_text(), route])
	return {"text": "\n".join(lines), "data": data}


static func _obj_name(o: Object) -> String:
	if o is Vehicle:
		return "Fahrzeug %s (%s)" % [o.vname, o.def_id]
	if o is Site:
		return "Baustelle %s" % o.job.short_title()
	return str(o)


static func _copy_logs(dest: String) -> Array:
	var out: Array = []
	# engine log (print output, errors, script errors with backtraces)
	var lp: String = Game.logger.path if Game.logger else ""
	if lp != "" and FileAccess.file_exists(lp):
		var txt := FileAccess.get_file_as_string(lp)
		var lines := txt.split("\n")
		var f := FileAccess.open(dest.path_join("spiel.log"), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines.slice(maxi(0, lines.size() - 800))))
			out.append("logs/spiel.log")
	# in-game notifications
	var nf := FileAccess.open(dest.path_join("meldungen_im_spiel.txt"), FileAccess.WRITE)
	if nf:
		for e in Events.history:
			nf.store_line("%s [%s] %s" % e)
		out.append("logs/meldungen_im_spiel.txt")
	# map loading log
	if not Game.map_meta.is_empty():
		var ml := Game.map_dir().path_join("laden.log")
		if FileAccess.file_exists(ml):
			var data := FileAccess.get_file_as_bytes(ml)
			var mf := FileAccess.open(dest.path_join("laden.log"), FileAccess.WRITE)
			if mf:
				mf.store_buffer(data)
				out.append("logs/laden.log")
	return out


static func _read_json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}
