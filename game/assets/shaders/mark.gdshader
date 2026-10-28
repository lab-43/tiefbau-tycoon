shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/common.gdshaderinc"
uniform vec3 color : source_color = vec3(0.93, 0.93, 0.91);
uniform float roughness = 0.55;
uniform bool on_deck = false;   // bridge deck layers (#8)
uniform float deck_off = 0.05;   // height of the layer above the deck
varying vec3 wpos;
varying float t_off;   // height above the ground (#8)
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; t_off = wpos.y - terrain_h(wpos.xz); }
void fragment() {
	DEPTH = on_deck ? terrain_depth_deck(INV_VIEW_MATRIX[3].xyz, wpos, deck_off, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.z)
		: terrain_depth(INV_VIEW_MATRIX[3].xyz, wpos, t_off, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.z);
	if (in_pit(wpos.xz)) { discard; }
	float grain = hash12(floor(wpos.xz * 30.0));
	ALBEDO = color * (0.94 + 0.06 * grain);
	ROUGHNESS = roughness;
}
