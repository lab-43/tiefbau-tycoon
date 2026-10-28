class_name Mats
extends RefCounted
## Shared materials for the generated city. Created once, reused by all chunks and saved scenes.

static var _cache := {}


static func _shader(path: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _std(col: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


const DECK_OFF := {"asphalt": RoadMesher.Y_ROAD, "sidewalk": RoadMesher.Y_SW, "mark": RoadMesher.Y_MARK}


static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	if name.ends_with("_deck"):
		# same look on a bridge deck, but the depth is only ever lifted onto the ground (#8)
		var dm := get_mat(name.trim_suffix("_deck")).duplicate() as ShaderMaterial
		dm.set_shader_parameter("on_deck", true)
		dm.set_shader_parameter("deck_off", DECK_OFF.get(name.trim_suffix("_deck"), 0.05))
		_cache[name] = dm
		return dm
	var m: Material
	match name:
		"asphalt":
			m = _shader("res://assets/shaders/asphalt.gdshader")
		"asphalt_new":
			m = _shader("res://assets/shaders/asphalt.gdshader", {"base_color": Color(0.13, 0.13, 0.14), "patchiness": 0.1})
		"sidewalk":
			m = _shader("res://assets/shaders/paving.gdshader")
		"path":
			m = _shader("res://assets/shaders/paving.gdshader", {"base_color": Color(0.74, 0.72, 0.68), "tile": 0.25})
		"cycleway":
			m = _shader("res://assets/shaders/asphalt.gdshader", {"base_color": Color(0.46, 0.30, 0.27), "patchiness": 0.3})
		"track":
			m = _shader("res://assets/shaders/ground.gdshader", {"base_color": Color(0.63, 0.58, 0.50), "alt_color": Color(0.58, 0.54, 0.47)})
		"curb":
			m = _std(Color(0.78, 0.775, 0.76), 0.85)
		"bridge":
			m = _std(Color(0.70, 0.69, 0.67), 0.85)
		"mark":
			m = _shader("res://assets/shaders/mark.gdshader")
		"mark_yellow":
			m = _shader("res://assets/shaders/mark.gdshader", {"color": Color(0.96, 0.74, 0.05), "roughness": 0.5})
		"building":
			m = _shader("res://assets/shaders/building.gdshader")
		"ground":
			m = _shader("res://assets/shaders/ground.gdshader")
		"water":
			m = _shader("res://assets/shaders/water.gdshader")
		"area_grass":
			m = _shader("res://assets/shaders/grass.gdshader")
		"area_park":
			m = _shader("res://assets/shaders/grass.gdshader", {"base_color": Color(0.40, 0.52, 0.31), "alt_color": Color(0.47, 0.57, 0.34)})
		"area_cemetery":
			m = _shader("res://assets/shaders/grass.gdshader", {"base_color": Color(0.38, 0.48, 0.32), "alt_color": Color(0.43, 0.51, 0.35)})
		"area_forest":
			m = _shader("res://assets/shaders/grass.gdshader", {"base_color": Color(0.27, 0.36, 0.22), "alt_color": Color(0.33, 0.40, 0.25)})
		"area_pitch":
			m = _shader("res://assets/shaders/grass.gdshader", {"base_color": Color(0.36, 0.55, 0.30), "alt_color": Color(0.38, 0.57, 0.31)})
		"area_farmland":
			m = _shader("res://assets/shaders/ground.gdshader", {"base_color": Color(0.66, 0.64, 0.47), "alt_color": Color(0.60, 0.60, 0.42), "scale": 0.01})
		"area_industrial", "area_commercial":
			m = _shader("res://assets/shaders/ground.gdshader", {"base_color": Color(0.70, 0.70, 0.69), "alt_color": Color(0.66, 0.66, 0.65)})
		"area_residential":
			m = _shader("res://assets/shaders/ground.gdshader", {"base_color": Color(0.78, 0.77, 0.74), "alt_color": Color(0.75, 0.74, 0.71)})
		"area_paved":
			m = _shader("res://assets/shaders/asphalt.gdshader", {"base_color": Color(0.36, 0.36, 0.37), "patchiness": 0.3})
		"area_sand":
			m = _shader("res://assets/shaders/ground.gdshader", {"base_color": Color(0.86, 0.80, 0.64), "alt_color": Color(0.82, 0.76, 0.60)})
		"ballast":
			m = _shader("res://assets/shaders/ground.gdshader", {"base_color": Color(0.50, 0.47, 0.44), "alt_color": Color(0.45, 0.43, 0.40), "scale": 0.3, "detail": 1.5})
		"rail":
			m = _std(Color(0.35, 0.33, 0.31), 0.4, 0.7)
		"trunk":
			m = _std(Color(0.30, 0.24, 0.19), 0.95)
		"foliage":
			var f := _std(Color(0.36, 0.48, 0.27), 0.95)
			f.vertex_color_use_as_albedo = false
			m = f
		"portal":
			m = _std(Color(0.66, 0.65, 0.62), 0.9)
		"portal_green":
			m = _std(Color(0.40, 0.51, 0.31), 0.97)
		"portal_dark":
			var pd := _std(Color(0.025, 0.025, 0.03), 1.0)
			pd.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m = pd
		"under_road":
			m = _overlay(UndergroundView.ROAD, 12)
		"under_rail":
			m = _overlay(UndergroundView.RAIL, 11)
		"under_subway":
			m = _overlay(UndergroundView.SUBWAY, 10)
		"lamp_pole":
			m = _std(Color(0.32, 0.33, 0.34), 0.5, 0.6)
		"lamp_head":
			var lh := _std(Color(0.9, 0.9, 0.85), 0.4)
			lh.emission_enabled = true
			lh.emission = Color(1.0, 0.82, 0.55)
			lh.emission_energy_multiplier = 0.0
			m = lh
		_:
			m = _std(Color(1, 0, 1))
	_cache[name] = m
	return m


## Underground view (#31): flat colour drawn over everything (no depth test), above the dimmed city.
static func _overlay(col: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = priority
	return m


## Night factor 0..1 sets emissive street lamps (shared material).
static func set_night(f: float) -> void:
	var lh: StandardMaterial3D = get_mat("lamp_head")
	lh.emission_energy_multiplier = f * 6.0
