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

// --- ground heights (#8): Terrain.activate() hands the smoothed height grid to the GPU ---
// Flat map layers (ground, areas, roads, paths, markings) compute the exact ground surface per pixel, so the
// layers keep their order (a few cm apart) on any slope, independent of how coarse their meshes are.
global uniform sampler2D terrain_tex;
global uniform vec4 terrain_rect;   // grid origin x, origin z, 1 / cell size, enabled (0/1)
global uniform vec4 terrain_size;   // nodes x, nodes z, cell size, 0
// height, dh/dx, dh/dz of the bilinear surface (same formula as Terrain.sample on the CPU)
vec3 terrain_hg(vec2 p) {
	if (terrain_rect.w < 0.5) return vec3(0.0);
	vec2 mx = terrain_size.xy - 1.0;
	vec2 g = clamp((p - terrain_rect.xy) * terrain_rect.z, vec2(0.0), mx);
	vec2 i0 = min(floor(g), mx - 1.0);
	vec2 f = g - i0;
	ivec2 i = ivec2(i0);
	float a = texelFetch(terrain_tex, i, 0).r;
	float b = texelFetch(terrain_tex, i + ivec2(1, 0), 0).r;
	float c = texelFetch(terrain_tex, i + ivec2(0, 1), 0).r;
	float d = texelFetch(terrain_tex, i + ivec2(1, 1), 0).r;
	return vec3(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(b - a, d - c, f.y) * terrain_rect.z, mix(c - a, d - b, f.x) * terrain_rect.z);
}
float terrain_h(vec2 p) { return terrain_hg(p).x; }
// View ray through this fragment as o + d * t, t = 1 at the rasterised point wp. Perspective: from the camera,
// t is relative to the distance. Orthographic (the closure designer's top view, #9): along the view direction,
// t in metres. `span` is how far t may go towards the camera.
void terrain_ray(vec3 cam, vec3 wp, mat4 view, mat4 proj, out vec3 o, out vec3 d, out float span) {
	if (proj[3][3] > 0.5) {
		d = -vec3(view[0][2], view[1][2], view[2][2]);
		o = wp - d;
		span = 20.0;
	} else {
		o = cam;
		d = wp - cam;
		span = 0.5;
	}
}
// Depth of the surface `off` metres above the ground where the view ray through this fragment meets it
// (Newton steps from the rasterised point). Layers more than 0.6 m above the ground (bridge decks) keep
// their own depth.
float terrain_depth(vec3 cam, vec3 wp, float off, mat4 view, mat4 proj, float fz) {
	if (terrain_rect.w < 0.5 || abs(off) > 0.6) return fz;
	vec3 o; vec3 d; float span;
	terrain_ray(cam, wp, view, proj, o, d, span);
	float lim = span * 0.2;   // 10 % of the distance, or 4 m along an orthographic ray
	float t = 1.0;
	for (int k = 0; k < 3; k++) {
		vec3 p = o + d * t;
		vec3 hg = terrain_hg(p.xz);
		float df = d.y - hg.y * d.x - hg.z * d.z;
		if (abs(df) < 1e-6) break;
		t = clamp(t - (p.y - hg.x - off) / df, 1.0 - lim, 1.0 + lim);
	}
	vec4 c = proj * view * vec4(o + d * t, 1.0);
	return c.z / c.w;
}
// Bridge decks (#8, layers *_deck): a deck does not follow the ground. Where its triangles lie above the ground
// they keep their own depth; where a triangle dips below the ground (near the abutments, between two vertices)
// the surface is lifted to off above the ground - never pushed down into a bank that drops away under it.
float terrain_depth_deck(vec3 cam, vec3 wp, float off, mat4 view, mat4 proj, float fz) {
	if (terrain_rect.w < 0.5) return fz;
	if (terrain_h(wp.xz) + off <= wp.y) return fz;
	vec3 o; vec3 d; float span;
	terrain_ray(cam, wp, view, proj, o, d, span);
	float t = 1.0;
	for (int k = 0; k < 4; k++) {
		vec3 p = o + d * t;
		vec3 hg = terrain_hg(p.xz);
		float df = d.y - hg.y * d.x - hg.z * d.z;
		if (abs(df) < 1e-6) break;
		t = clamp(t - (p.y - hg.x - off) / df, 1.0 - span, 1.0);
	}
	vec4 c = proj * view * vec4(o + d * t, 1.0);
	return c.z / c.w;
}
// Water areas lie flat; their bank lies inside them (TerrainBake keeps the land height up to the shore).
// Where the ground rises above the water plane, the water is drawn on the ground (0.031 up, like the flat
// layer order), so the shore is exactly the outline of the water area instead of a 5 m grid contour.
float water_depth(vec3 cam, vec3 wp, mat4 view, mat4 proj, float fz) {
	if (terrain_rect.w < 0.5) return fz;
	float gap = terrain_h(wp.xz) + 0.031 - wp.y;
	if (gap <= 0.0) return fz;
	// The ray meets the bank before the water plane: walk back towards the camera until it is above the bank
	// surface, then bisect. (Newton steps did not converge on steep banks seen at an angle: jagged shores.)
	vec3 o; vec3 d; float span;
	terrain_ray(cam, wp, view, proj, o, d, span);
	float t_min = 1.0 - span;
	float up = max(-d.y, 1e-4);   // height gained per unit of t when going back towards the camera
	float t_in = 1.0;             // below the bank surface
	float t_out = 1.0;
	for (int k = 0; k < 8; k++) {
		t_out = max(t_min, t_in - (gap + 0.02) / up);
		vec3 p = o + d * t_out;
		gap = terrain_h(p.xz) + 0.031 - p.y;
		if (gap <= 0.0 || t_out <= t_min) break;
		t_in = t_out;
	}
	for (int k = 0; k < 16; k++) {   // to well below the 2 cm between water and road surfaces
		float tm = 0.5 * (t_in + t_out);
		vec3 p = o + d * tm;
		if (terrain_h(p.xz) + 0.031 > p.y) t_in = tm; else t_out = tm;
	}
	vec4 c = proj * view * vec4(o + d * t_out, 1.0);
	return c.z / c.w;
}
