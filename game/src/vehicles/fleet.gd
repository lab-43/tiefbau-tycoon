class_name Fleet
extends Node3D
## Owns all company vehicles: spawning, naming, number plates, purchase, save/load.

const NAMES := {"van_crew": "Kolonnenbus", "truck_flatbed": "Pritsche", "truck_tipper": "Kipper",
	"tractor_lowbed": "Tieflader", "excavator_a918": "Mobilbagger", "cold_planer": "Kaltfräse", "roller_bw141": "Walze"}

var world: World
var vehicles: Array = []
var _plate_no := 100


func setup(w: World) -> void:
	world = w


func spawn_start_fleet() -> void:
	for id in Balance.START_FLEET:
		var v := add_vehicle(id)
		var si := world.hq.free_slot(v.kind_slot())
		if si >= 0:
			world.hq.slots[si].used_by = v
			v.slot = si
			v.place(world.hq.slots[si].pos, world.hq.slots[si].yaw)
		else:
			v.place(world.hq.gate_world() + Vector3(0, 0, 0), 0.0)
		v.status_text = "In der Zentrale"
		if id == "van_crew":
			v.crew_aboard = 3
			v.cargo.barriers = 1


func _next_name(id: String) -> String:
	var base: String = NAMES.get(id, Balance.vehicle(id).get("name", id))
	var n := 1
	for v in vehicles:
		if v.def_id == id:
			n += 1
	return "%s %d" % [base, n]


func add_vehicle(id: String, name := "", plate := "") -> Vehicle:
	var v := Vehicle.new()
	v.name = "V_%s_%d" % [id, vehicles.size()]
	add_child(v)
	if name == "":
		name = _next_name(id)
	if plate == "":
		_plate_no += 1
		plate = "HH-BM %d" % _plate_no
	v.setup(world, id, name, plate)
	vehicles.append(v)
	Events.vehicle_added.emit(v)
	return v


func buy(id: String) -> Vehicle:
	var d := Balance.vehicle(id)
	if d.is_empty():
		return null
	var si := world.hq.free_slot("lowbed" if id == "tractor_lowbed" else ("truck" if d.get("length", 5.0) > 7.5 else "small"))
	if si < 0:
		Events.warn("Kein freier Stellplatz in der Zentrale")
		return null
	if not Game.spend(d.price, "Kauf %s" % d.name):
		return null
	var v := add_vehicle(id)
	world.hq.slots[si].used_by = v
	v.slot = si
	v.place(world.hq.slots[si].pos, world.hq.slots[si].yaw)
	v.status_text = "In der Zentrale"
	Events.ok("%s gekauft" % v.vname)
	return v


func by_plate(p: String) -> Vehicle:
	for v in vehicles:
		if v.plate == p:
			return v
	return null


func of_type(ability: String) -> Array:
	return vehicles.filter(func(v): return v.has_ability(ability))


func save_state() -> Dictionary:
	var arr := []
	for v in vehicles:
		arr.append(v.save_state())
	return {"vehicles": arr, "plate_no": _plate_no}


func load_state(d: Dictionary) -> void:
	_plate_no = d.get("plate_no", 100)
	for vd in d.get("vehicles", []):
		var v := add_vehicle(vd.def, vd.name, vd.plate)
		v.load_state(vd)
		v.status_text = "Abgestellt"
	# machines that were on a lowbed
	for vd in d.get("vehicles", []):
		if vd.get("carried_by", "") != "":
			var m := by_plate(vd.plate)
			var lb := by_plate(vd.carried_by)
			if m and lb:
				lb.cargo.machine = m
				m.carried_by = lb
				m.state = "on_trailer"
				m.status_text = "Auf %s" % lb.vname
