class_name Job
extends RefCounted
## A contract: replace a damaged pipe section under a lane. Offer → active (site) → done.

var id := 0
var kind := "pipe"
var client := ""
var street := ""
var district := ""
var key := -1
var s0 := 0.0
var length := 4.0
var width := 1.3
var depth := 1.8
var pipe_d := 0.3
var pipe_name := "Trinkwasserleitung DN 300"
var pay := 0.0
var offered_at := 0.0           # total game minutes
var expires_at := 0.0
var duration_days := 3
var deadline_day := 0
var accepted_day := 0
var state := "offer"            # offer | active | done | declined | expired
var scouted := false
var costs := 0.0
var center := Vector2.ZERO
var distance_m := 0.0
var result := {}


func short_title() -> String:
	return "Auftrag %d" % id


func title() -> String:
	return "%s erneuern" % pipe_name


func location() -> String:
	return street if street != "" else "Unbenannte Straße"


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "client": client, "street": street, "district": district, "key": key, "s0": s0,
		"length": length, "width": width, "depth": depth, "pipe_d": pipe_d, "pipe_name": pipe_name, "pay": pay,
		"offered_at": offered_at, "expires_at": expires_at, "duration_days": duration_days, "deadline_day": deadline_day,
		"accepted_day": accepted_day, "state": state, "scouted": scouted, "costs": costs, "center": center,
		"distance_m": distance_m, "result": result}


static func from_dict(d: Dictionary) -> Job:
	var j := Job.new()
	for k in d:
		if k in j:
			j.set(k, d[k])
	return j
