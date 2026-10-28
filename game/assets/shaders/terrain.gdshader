shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/common.gdshaderinc"
// Excavation heightfield. Colour from depth bands (road build-up) and vertex flags:
// COLOR.r = refilled material, COLOR.g = compacted, COLOR.b = fresh asphalt surface
uniform float y_road = 0.05;
uniform float sand_top = -1.2;
varying vec3 wpos;
varying vec4 vcol;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
}
vec3 asphalt_old(vec2 p) {
	float large = fbm(p * 0.035);
	float mid = vnoise(p * 0.45);
	float grain = hash12(floor(p * 22.0));
	float shade = 0.86 + 0.11 * large + 0.06 * mid + 0.05 * (grain - 0.5);
	float patchy = step(0.78, vnoise(p * 0.11 + 17.0));
	vec3 col = vec3(0.235, 0.238, 0.245) * shade;
	return mix(col, col * 0.82, patchy * 0.6);
}
void fragment() {
	float h = wpos.y - y_road - terrain_h(wpos.xz);   // depth below the road surface (#8: ground heights)
	vec2 p = wpos.xz;
	float g = hash12(floor(p * 30.0 + wpos.y * 13.0));
	float n = vnoise(p * 3.0 + wpos.y * 2.0);
	vec3 soil = vec3(0.40, 0.31, 0.22) * (0.85 + 0.25 * n + 0.12 * (g - 0.5));
	soil *= mix(1.0, 0.72, clamp(-h / 2.2, 0.0, 1.0));
	vec3 base = vec3(0.50, 0.48, 0.45) * (0.85 + 0.3 * (g - 0.5) + 0.1 * n);
	vec3 col;
	float rough = 0.95;
	if (vcol.r < 0.5) {
		col = soil;
		col = mix(col, base, smoothstep(-0.47, -0.44, h));
		col = mix(col, asphalt_old(p) * 0.92, smoothstep(-0.125, -0.11, h));
		if (h > -0.11) { col = asphalt_old(p); rough = 0.88; }
	} else {
		vec3 sand = vec3(0.80, 0.68, 0.45) * (0.88 + 0.18 * n + 0.1 * (g - 0.5));
		vec3 gravel = vec3(0.56, 0.54, 0.51) * (0.8 + 0.4 * (g - 0.5) + 0.1 * n);
		col = mix(sand, gravel, smoothstep(sand_top - 0.01, sand_top + 0.01, h));
		vec3 fresh = vec3(0.115, 0.115, 0.125) * (0.92 + 0.12 * vnoise(p * 1.7) + 0.05 * (g - 0.5));
		col = mix(col, fresh, vcol.b);
		if (vcol.b > 0.5) { rough = 0.82 - 0.12 * vcol.g; }
		col *= mix(1.0, 0.93, vcol.g);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
