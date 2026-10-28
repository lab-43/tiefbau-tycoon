shader_type spatial;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.79, 0.78, 0.75);
uniform vec3 alt_color : source_color = vec3(0.74, 0.73, 0.69);
uniform float scale = 0.02;
uniform float detail = 0.6;
varying vec3 wpos;
varying float t_off;   // height above the ground (#8)
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; t_off = wpos.y - terrain_h(wpos.xz); }
void fragment() {
	DEPTH = terrain_depth(INV_VIEW_MATRIX[3].xyz, wpos, t_off, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.z);
	if (in_pit(wpos.xz)) { discard; }
	float n = fbm(wpos.xz * scale);
	float d = vnoise(wpos.xz * 1.3);
	ALBEDO = mix(base_color, alt_color, n) * (1.0 - detail * 0.08 + detail * 0.08 * d);
	ROUGHNESS = 0.95;
}
