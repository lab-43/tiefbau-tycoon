shader_type spatial;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.42, 0.53, 0.33);
uniform vec3 alt_color : source_color = vec3(0.50, 0.58, 0.36);
varying vec3 wpos;
varying float t_off;   // height above the ground (#8)
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; t_off = wpos.y - terrain_h(wpos.xz); }
void fragment() {
	DEPTH = terrain_depth(INV_VIEW_MATRIX[3].xyz, wpos, t_off, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.z);
	if (in_pit(wpos.xz)) { discard; }
	float n = fbm(wpos.xz * 0.05);
	float d = vnoise(wpos.xz * 2.1);
	ALBEDO = mix(base_color, alt_color, n) * (0.93 + 0.1 * d);
	ROUGHNESS = 0.97;
}
