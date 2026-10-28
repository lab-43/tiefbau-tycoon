shader_type spatial;
render_mode cull_disabled;
global uniform float night;
uniform vec3 color : source_color = vec3(1.0, 0.62, 0.05);
instance uniform float phase = 0.0;
instance uniform float on = 1.0;
void fragment() {
	// yellow warning light (Warnleuchte): short flash every 1.1 s, sequential phase for running lights
	float t = fract(TIME * 0.9 - phase);
	float flash = smoothstep(0.0, 0.03, t) * (1.0 - smoothstep(0.16, 0.24, t));
	float k = on * flash;
	ALBEDO = color * (0.45 + 0.5 * k);
	EMISSION = color * k * (1.5 + night * 5.0);
	ROUGHNESS = 0.3;
}
