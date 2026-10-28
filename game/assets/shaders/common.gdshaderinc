float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}

// --- construction pits: road surfaces discard fragments inside up to 4 oriented rectangles ---
// pit_aN = (center.x, center.z, dir.x, dir.z), pit_bN = (half_length, half_width, active, 0)
global uniform vec4 pit_a0;
global uniform vec4 pit_b0;
global uniform vec4 pit_a1;
global uniform vec4 pit_b1;
global uniform vec4 pit_a2;
global uniform vec4 pit_b2;
global uniform vec4 pit_a3;
global uniform vec4 pit_b3;
bool pit_test(vec2 p, vec4 a, vec4 b) {
	if (b.z < 0.5) return false;
	vec2 d = p - a.xy;
	float u = dot(d, a.zw);
	float v = dot(d, vec2(-a.w, a.z));
	return abs(u) < b.x && abs(v) < b.y;
}
bool in_pit(vec2 p) {
	return pit_test(p, pit_a0, pit_b0) || pit_test(p, pit_a1, pit_b1) || pit_test(p, pit_a2, pit_b2) || pit_test(p, pit_a3, pit_b3);
}
