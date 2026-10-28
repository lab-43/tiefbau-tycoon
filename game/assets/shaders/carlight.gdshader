shader_type spatial;
render_mode cull_disabled;
global uniform float night;
uniform vec3 color : source_color = vec3(1.0, 0.1, 0.05);
uniform float base = 0.25;
uniform float night_gain = 0.0;
instance uniform float on = 0.0;
void fragment() {
	float k = clamp(base + on * 0.75 + night * night_gain, 0.0, 1.0);
	ALBEDO = color * (0.35 + 0.65 * k);
	EMISSION = color * (on * 2.5 + night * night_gain * 3.0);
}
