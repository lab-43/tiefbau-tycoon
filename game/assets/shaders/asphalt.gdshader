shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.235, 0.238, 0.245);
uniform float patchiness = 0.5;
uniform bool on_deck = false;   // bridge deck layers (#8)
uniform float deck_off = 0.05;   // height of the layer above the deck
varying vec3 wpos;
varying float t_off;   // height above the ground (#8)
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; t_off = wpos.y - terrain_h(wpos.xz); }
void fragment() {
	DEPTH = on_deck ? terrain_depth_deck(INV_VIEW_MATRIX[3].xyz, wpos, deck_off, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.z)
		: terrain_depth(INV_VIEW_MATRIX[3].xyz, wpos, t_off, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.z);
	if (in_pit(wpos.xz)) { discard; }
	float large = fbm(wpos.xz * 0.035);
	float mid = vnoise(wpos.xz * 0.45);
	float grain = hash12(floor(wpos.xz * 22.0));
	float shade = 0.86 + 0.22 * large * patchiness + 0.06 * mid + 0.05 * (grain - 0.5);
	// repaired patches
	float p = step(0.78, vnoise(wpos.xz * 0.11 + 17.0));
	vec3 col = base_color * shade;
	col = mix(col, col * 0.82, p * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.88 - 0.1 * p;
	SPECULAR = 0.35;
}
