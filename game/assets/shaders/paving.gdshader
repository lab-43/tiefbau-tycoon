shader_type spatial;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.70, 0.695, 0.68);
uniform float tile = 0.32;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (in_pit(wpos.xz)) { discard; }
	vec2 g = wpos.xz / tile;
	vec2 f = abs(fract(g) - 0.5);
	float joint = smoothstep(0.47, 0.5, max(f.x, f.y));
	float v = hash12(floor(g)) * 0.06 + fbm(wpos.xz * 0.2) * 0.08;
	ALBEDO = base_color * (0.95 + v) * (1.0 - joint * 0.18);
	ROUGHNESS = 0.92;
}
