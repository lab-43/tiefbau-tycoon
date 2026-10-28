// Shared code of carlamp.gdshader (single-sided lamp glass) and carlamp_2s.gdshader (double-sided).
// Lamp glass of traffic car models (#2). Looks like the model's own StandardMaterial3D (albedo,
// normal, roughness/metallic/AO textures copied over by TrafficModels) and adds the light: daytime
// running / low beam and tail lights from the global night level, brake and indicators from the
// per-car instance uniform `lamp`. One material per model and lamp function, shared by all cars.
global uniform float night;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform float roughness = 1.0;
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metal_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool use_ao = false;
uniform float specular = 0.5;

// 0 head, 1 tail, 2 brake, 3 indicator left, 4 indicator right, 5 reverse
uniform int fn = 0;
// head glass with vertices behind this mesh-local z also carries the rear position lamps (tail)
uniform float rear_z = 1e9;
// tail glass also shows the brake light (model without own brake glass)
uniform bool tail_brakes = false;
// x brake, y indicator left, z indicator right (0..1), w unused
instance uniform vec4 lamp = vec4(0.0);

varying flat float v_rear;

void vertex() {
	// some models carry the rear position lamps in their "head" glass: those act as tail lights
	v_rear = VERTEX.z > rear_z ? 1.0 : 0.0;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo;
	ALBEDO = a.rgb;
	ROUGHNESS = dot(texture(rough_tex, UV), rough_channel) * roughness;
	METALLIC = dot(texture(metal_tex, UV), metal_channel) * metallic;
	SPECULAR = specular;
	if (use_ao) {
		AO = dot(texture(ao_tex, UV), ao_channel);
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	int f = fn;
	if (f == 0 && v_rear > 0.5) {
		f = 1;
	}
	vec3 col = vec3(1.0, 0.95, 0.85);
	float k = 0.0;
	if (f == 0) {
		k = 0.35 + night * 1.85;                          // daytime running light -> low beam
	} else if (f == 1) {
		// coloured lamps stay at emission <= ~2: above that AgX tonemapping turns them white
		// (lesson leuchten-nicht-ueberstrahlen)
		col = vec3(1.0, 0.02, 0.01);
		k = 0.3 + night * 0.6 + (tail_brakes ? lamp.x * 1.3 : 0.0);
	} else if (f == 2) {
		col = vec3(1.0, 0.02, 0.01);
		k = lamp.x * 2.0;
	} else if (f == 3) {
		col = vec3(1.0, 0.3, 0.0);
		k = lamp.y * 2.0;
	} else if (f == 4) {
		col = vec3(1.0, 0.3, 0.0);
		k = lamp.z * 2.0;
	} else {
		col = vec3(1.0);
	}
	EMISSION = col * k;
}
