shader_type spatial;
render_mode cull_back;
uniform float roughness_v = 0.85;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment() {
	vec3 c = COLOR.rgb;
	// subtle darkening towards the ground (contact feel) on walls
	float wall = 1.0 - abs(wnrm.y);
	c *= mix(1.0, 0.86 + 0.14 * clamp(wpos.y / 6.0, 0.0, 1.0), wall);
	ALBEDO = c;
	ROUGHNESS = roughness_v;
}
