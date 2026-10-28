class_name DayNight
extends Node
## Drives sun, moon, sky, ambient light, fog and night lighting from the game clock and map latitude.

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var night := 0.0          # 0 = day, 1 = full night
var latitude := 53.55
var override_hour := -1.0  # debug: light as at this hour (>= 0), the clock keeps running
var _acc := 10.0


func setup(world_env: WorldEnvironment, sun_light: DirectionalLight3D, moon_light: DirectionalLight3D) -> void:
	env = world_env.environment
	sun = sun_light
	moon = moon_light
	sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	update_now()


static func make_environment() -> Environment:
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_curve = 0.12
	psm.ground_curve = 0.05
	psm.sun_angle_max = 20.0
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(0.80, 0.82, 0.86)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 2.4
	e.ssao_intensity = 2.2
	e.ssao_power = 1.6
	e.ssao_detail = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.2
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_density = 0.00002
	e.fog_aerial_perspective = 0.4
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.0
	return e


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.1:
		return
	_acc = 0.0
	update_now()


func update_now() -> void:
	if env == null:
		return
	var sp := Clock.sun_position(latitude) if override_hour < 0.0 else Clock.sun_position_at(latitude, override_hour)
	var el := sp.x
	var az := sp.y
	# sun direction: light travels from the sun towards the ground
	var dir_to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	var day := clampf((rad_to_deg(el) + 4.0) / 14.0, 0.0, 1.0)          # 0 below -4 deg, 1 above 10 deg
	var golden := clampf(1.0 - absf(rad_to_deg(el) - 4.0) / 12.0, 0.0, 1.0) * day
	night = 1.0 - clampf((rad_to_deg(el) + 7.0) / 9.0, 0.0, 1.0)         # 1 below -7 deg
	if el > -0.05:
		sun.visible = true
		sun.look_at_from_position(Vector3.ZERO, -dir_to_sun, Vector3.UP if absf(dir_to_sun.y) < 0.99 else Vector3.FORWARD)
	else:
		sun.visible = false
	sun.light_energy = 1.45 * day
	sun.light_color = Color(1.0, 0.93, 0.84).lerp(Color(1.0, 0.62, 0.36), golden * 0.8)
	sun.shadow_enabled = day > 0.05
	# moon roughly opposite to the sun, dim and cool
	moon.visible = night > 0.05
	moon.light_energy = 0.22 * night
	moon.light_color = Color(0.62, 0.72, 1.0)
	var moon_dir := Vector3(-dir_to_sun.x, maxf(0.35, -dir_to_sun.y), -dir_to_sun.z).normalized()
	moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)
	# sky colours
	var top_day := Color(0.36, 0.56, 0.84)
	var hor_day := Color(0.76, 0.83, 0.90)
	var top_night := Color(0.012, 0.018, 0.04)
	var hor_night := Color(0.04, 0.05, 0.09)
	var hor_sunset := Color(0.95, 0.62, 0.42)
	var top := top_night.lerp(top_day, day)
	var hor := hor_night.lerp(hor_day, day).lerp(hor_sunset, golden * 0.55)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.4)
	sky_mat.sky_energy_multiplier = lerpf(0.35, 1.0, day)
	env.ambient_light_energy = lerpf(0.5, 1.15, day)
	env.ambient_light_sky_contribution = lerpf(0.9, 0.55, day)
	env.ambient_light_color = Color(0.32, 0.36, 0.48).lerp(Color(0.84, 0.85, 0.88), day)
	env.fog_light_color = hor
	env.tonemap_exposure = lerpf(1.25, 1.0, day)
	Mats.set_night(night)
