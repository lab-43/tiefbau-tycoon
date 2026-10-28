shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 deep : source_color = vec3(0.16, 0.27, 0.30);
uniform vec3 shallow : source_color = vec3(0.30, 0.42, 0.43);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME * 0.05;
	vec2 uv = wpos.xz * 0.15;
	float n1 = vnoise(uv + vec2(t, t * 0.7));
	float n2 = vnoise(uv * 2.7 - vec2(t * 1.3, t * 0.4));
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.35 + (n2 - 0.5) * 0.2, 1.0, (n2 - 0.5) * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, 0.35 + 0.3 * fbm(wpos.xz * 0.01));
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6 + fres * 0.4;
}
