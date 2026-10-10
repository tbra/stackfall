shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Honey look C (Bontago-lv2): glossy amber glue beads along the block cell edges (generated
// flattened spheres, one draw per block). Opaque, so the block colour stays fully readable.
#include "res://shaders/include/honey_shading.gdshaderinc"

uniform float alpha = 1.0;

void fragment() {
	vec3 albedo;
	vec3 emission;
	honey_surface(dot(normalize(NORMAL), normalize(VIEW)), albedo, emission);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 0.1;
	SPECULAR = 0.0;
	ALPHA = alpha;
}
