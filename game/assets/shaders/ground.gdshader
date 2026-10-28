shader_type spatial;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.79, 0.78, 0.75);
uniform vec3 alt_color : source_color = vec3(0.74, 0.73, 0.69);
uniform float scale = 0.02;
uniform float detail = 0.6;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (in_pit(wpos.xz)) { discard; }
	float n = fbm(wpos.xz * scale);
	float d = vnoise(wpos.xz * 1.3);
	ALBEDO = mix(base_color, alt_color, n) * (1.0 - detail * 0.08 + detail * 0.08 * d);
	ROUGHNESS = 0.95;
}
