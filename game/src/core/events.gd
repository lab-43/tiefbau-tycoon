extends Node
## Global signal bus. Keeps systems loosely coupled (UI listens, simulation emits).

signal notify(text: String, kind: String)            # kind: info | ok | warn | error
signal money_changed(balance: float, delta: float, reason: String)
signal time_tick(day: int, minutes: float)           # emitted about once per game minute
signal speed_changed(index: int)
signal selection_changed(obj: Object)
signal hover_changed(obj: Object)
signal job_offers_changed()
signal job_changed(job: Object)
signal site_changed(site: Object)
signal vehicle_changed(vehicle: Object)
signal vehicle_added(vehicle: Object)
signal world_ready()
signal request_focus(pos: Vector3, distance: float)
signal tool_changed(tool_name: String)
signal context_command(world_pos: Vector3, target: Object)
signal open_issues()                                 # show the "Meldungen" window
signal report_issue()                                # open the F8 report dialog


## Last notifications [time, kind, text] (attached to issue reports).
var history: Array = []


func _ready() -> void:
	notify.connect(func(text: String, kind: String):
		history.append([Time.get_time_string_from_system(), kind, text])
		if history.size() > 300:
			history.pop_front())


func info(text: String) -> void:
	notify.emit(text, "info")


func ok(text: String) -> void:
	notify.emit(text, "ok")


func warn(text: String) -> void:
	notify.emit(text, "warn")


func error(text: String) -> void:
	notify.emit(text, "error")
