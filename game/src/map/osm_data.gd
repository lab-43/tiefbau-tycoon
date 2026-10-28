class_name OsmData
extends RefCounted
## Parsed, projected and classified OpenStreetMap data for one map (all in local meters).

const DRIVABLE := {
	"motorway": 1, "trunk": 1, "primary": 1, "secondary": 1, "tertiary": 1, "unclassified": 1,
	"residential": 1, "living_street": 1, "service": 1, "road": 1, "busway": 1,
	"motorway_link": 1, "trunk_link": 1, "primary_link": 1, "secondary_link": 1, "tertiary_link": 1,
}
const PATHS := {"footway": 1, "path": 1, "cycleway": 1, "pedestrian": 1, "steps": 1, "bridleway": 1, "track": 1}

var bounds := Rect2()                 # map rectangle in local coordinates
var roads: Array = []                 # {id, ids: PackedInt64Array, pts: PackedVector2Array, tags}
var paths: Array = []                 # {id, pts, tags}
var rails: Array = []                 # {id, pts, tags}
var buildings: Array = []             # {id, outer: PackedVector2Array, holes: Array, tags}
var areas: Array = []                 # {id, kind, outer, holes, tags}
var signals: Dictionary = {}          # osm node id -> Vector2
var crossings: Dictionary = {}        # osm node id -> {pos, kind}
var give_way: Dictionary = {}         # osm node id -> Vector2 (give_way / stop)
var stops: Dictionary = {}            # osm node id -> true (stop sign: Haltlinie instead of Wartelinie)
var bus_stops: Array = []             # Vector2
var lamps: Array = []                 # Vector2
var trees: Array = []                 # Vector2
var bus_way_ids: Dictionary = {}      # way id -> true
var stats: Dictionary = {}


static func area_kind(tags: Dictionary) -> String:
	var lu: String = tags.get("landuse", "")
	var le: String = tags.get("leisure", "")
	var na: String = tags.get("natural", "")
	var wa: String = tags.get("waterway", "")
	if na == "water" or wa in ["riverbank", "dock", "canal"] or tags.has("water"):
		return "water"
	if na in ["wood"] or lu == "forest":
		return "forest"
	if le in ["park", "garden", "golf_course"] or lu in ["recreation_ground", "village_green"]:
		return "park"
	if le in ["pitch", "sports_centre", "playground"]:
		return "pitch"
	if lu in ["grass", "meadow", "greenfield", "allotments", "flowerbed"] or na in ["grassland", "heath", "scrub", "wetland"]:
		return "grass"
	if lu in ["cemetery"]:
		return "cemetery"
	if lu in ["farmland", "farmyard", "orchard", "vineyard", "plant_nursery"]:
		return "farmland"
	if lu in ["industrial", "railway", "port", "depot", "construction", "brownfield", "landfill", "quarry"]:
		return "industrial"
	if lu in ["commercial", "retail"]:
		return "commercial"
	if tags.get("amenity", "") == "parking" or tags.has("area:highway"):
		return "paved"
	if na in ["sand", "beach"]:
		return "sand"
	if lu in ["residential"]:
		return "residential"
	return ""
