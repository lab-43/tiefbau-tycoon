shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.42, 0.33, 0.24);
uniform float grain = 0.15;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float g = hash12(floor(wpos.xz * 18.0 + wpos.y * 7.0));
	float m = vnoise(wpos.xz * 2.3 + wpos.y);
	vec3 col = base_color * (0.82 + 0.25 * m + grain * (g - 0.5));
	ALBEDO = col;
	ROUGHNESS = 0.97;
}
