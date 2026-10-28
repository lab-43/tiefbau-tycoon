extends Node
## All tunable numbers in one place: prices, wages, vehicle catalog, materials, job ranges.

const START_MONEY := 250000.0
const CURRENCY := "€"

# --- materials (price per tonne, density t/m3) -----------------------------------------------
const MATERIALS := {
	"soil":    {"name": "Aushub (Boden)",   "density": 1.8, "price_t": 0.0,  "dispose_t": 14.0, "color": Color(0.42, 0.33, 0.24)},
	"rubble":  {"name": "Bauschutt/Fräsgut", "density": 2.2, "price_t": 0.0, "dispose_t": 9.0,  "color": Color(0.28, 0.27, 0.26)},
	"sand":    {"name": "Füllsand",         "density": 1.6, "price_t": 19.0, "dispose_t": 0.0,  "color": Color(0.80, 0.68, 0.45)},
	"gravel":  {"name": "Schotter 0/32",    "density": 1.9, "price_t": 24.0, "dispose_t": 0.0,  "color": Color(0.55, 0.53, 0.50)},
	"asphalt": {"name": "Asphalt-Mischgut", "density": 2.4, "price_t": 98.0, "dispose_t": 0.0,  "color": Color(0.10, 0.10, 0.11)},
}
const PIPE_PRICE_PER_M := 48.0
const BARRIER_SET_PRICE := 2400.0

# --- people ---------------------------------------------------------------------------------
const WORKER_WAGE_H := 39.0
const NIGHT_SURCHARGE := 0.25
const DIESEL_EUR_L := 1.69

# --- vehicles -------------------------------------------------------------------------------
# model: id of an extracted asset in res://assets/consim/<model>/<model>.glb (fallback = procedural)
const VEHICLES := {
	"van_crew": {
		"name": "Kolonnenbus", "category": "transport", "model": "van_crew", "price": 42000.0,
		"max_kmh": 90.0, "accel": 2.4, "length": 5.4, "width": 2.0, "height": 2.4, "weight_t": 3.2,
		"seats": 3, "item_capacity": 24, "fuel_l_100km": 11.0, "op_l_h": 0.0,
		"color": Color(0.95, 0.95, 0.93), "abilities": ["crew", "items"],
	},
	"truck_flatbed": {
		"name": "Pritschen-LKW", "category": "transport", "model": "truck_flatbed", "price": 98000.0,
		"max_kmh": 80.0, "accel": 1.3, "length": 8.6, "width": 2.5, "height": 3.4, "weight_t": 14.0,
		"seats": 2, "item_capacity": 60, "pipe_capacity": 6, "fuel_l_100km": 28.0, "op_l_h": 4.0,
		"color": Color(0.95, 0.42, 0.08), "abilities": ["items", "pipes"],
	},
	"truck_tipper": {
		"name": "3-Achs-Kipper", "category": "transport", "model": "truck_tipper", "price": 124000.0,
		"max_kmh": 80.0, "accel": 1.2, "length": 8.4, "width": 2.5, "height": 3.3, "weight_t": 13.0,
		"seats": 1, "bulk_capacity_m3": 10.0, "fuel_l_100km": 32.0, "op_l_h": 5.0,
		"color": Color(0.95, 0.42, 0.08), "abilities": ["bulk"],
	},
	"tractor_lowbed": {
		"name": "Sattelzug mit Tieflader", "category": "transport", "model": "tractor_tgx", "trailer": "trailer_lowbed", "price": 168000.0,
		"max_kmh": 70.0, "accel": 0.9, "length": 7.0, "width": 2.55, "height": 3.8, "weight_t": 26.0,
		"seats": 1, "load_t": 32.0, "fuel_l_100km": 36.0, "op_l_h": 3.0,
		"color": Color(0.95, 0.42, 0.08), "abilities": ["lowbed"],
	},
	"excavator_a918": {
		"name": "Mobilbagger 18 t", "category": "machine", "model": "excavator_a918", "price": 189000.0,
		"max_kmh": 20.0, "accel": 0.8, "length": 6.2, "width": 2.55, "height": 3.2, "weight_t": 18.5,
		"seats": 1, "bucket_m3": 0.6, "reach_m": 8.2, "dig_depth_m": 4.5, "fuel_l_100km": 60.0, "op_l_h": 11.0,
		"color": Color(0.95, 0.78, 0.15), "abilities": ["dig", "lift"], "road_legal": true,
	},
	"cold_planer": {
		"name": "Kaltfräse 2 m", "category": "machine", "model": "cold_planer_bm2000", "price": 365000.0,
		"max_kmh": 6.0, "accel": 0.5, "length": 14.5, "width": 2.5, "height": 3.0, "weight_t": 26.0,
		"seats": 1, "mill_width": 2.0, "fuel_l_100km": 0.0, "op_l_h": 42.0,
		"color": Color(0.95, 0.8, 0.1), "abilities": ["mill"], "road_legal": false,
	},
	"roller_bw141": {
		"name": "Tandemwalze", "category": "machine", "model": "roller_bw141", "price": 58000.0,
		"max_kmh": 10.0, "accel": 0.6, "length": 3.3, "width": 1.6, "height": 2.8, "weight_t": 4.3,
		"seats": 1, "drum_width": 1.4, "fuel_l_100km": 0.0, "op_l_h": 5.5,
		"color": Color(0.95, 0.8, 0.1), "abilities": ["roll"], "road_legal": false,
	},
}

const START_FLEET := ["van_crew", "truck_flatbed", "truck_tipper", "tractor_lowbed", "excavator_a918"]

# --- jobs -------------------------------------------------------------------------------
const JOB_OFFER_INTERVAL_H := 5.0
const JOB_MAX_OFFERS := 3
const JOB_RADIUS_M := 2600.0
const JOB_PENALTY_PER_DAY := 0.03   # fraction of contract value


func vehicle(id: String) -> Dictionary:
	return VEHICLES.get(id, {})


func material_t(mat: String, m3: float) -> float:
	return m3 * float(MATERIALS[mat].density)


static func money(v: float) -> String:
	var neg := v < 0.0
	var s := str(int(round(absf(v))))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return ("−" if neg else "") + out + " €"
