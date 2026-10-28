shader_type spatial;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.42, 0.53, 0.33);
uniform vec3 alt_color : source_color = vec3(0.50, 0.58, 0.36);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (in_pit(wpos.xz)) { discard; }
	float n = fbm(wpos.xz * 0.05);
	float d = vnoise(wpos.xz * 2.1);
	ALBEDO = mix(base_color, alt_color, n) * (0.93 + 0.1 * d);
	ROUGHNESS = 0.97;
}
