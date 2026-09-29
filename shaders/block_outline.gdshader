shader_type spatial;
// Bontago-xtq.27 (M7 P2, docs/M7_PLAN.md P2): inverted-hull outline pass for
// a block's merged mesh. game/BlockFactory.gd adds this as a *second*
// MeshInstance3D sharing the exact same ArrayMesh as the toon/cell-grid pass
// (shaders/block_cell_grid.gdshader).
//
// Standard inverted-hull technique: cull the *front* faces (so only the
// enlarged back faces show, silhouetting the real mesh from behind it) and
// push every vertex outward. Flat, unshaded colour -- a hand-inked line.
//
// Bontago-adt.2 (graphics roadmap "Improved cel-shader"): the push is now
// done in clip space so the outline is a constant number of *screen pixels*
// wide at any distance (the old 6 mm world-space push was sub-pixel far away
// and shimmered/muddied there). The width eases from outline_width_px close
// up to the thinner outline_far_width_px between outline_fade_start_m and
// outline_far_distance_m so a 300-block skyline does not turn into a dark mesh.
//
// Bontago-mp0.3.1: `tint_color` is a per-instance parameter (the block's own
// colour) so the material stays one shared instance; outline_color mixes with
// the darkened tint by outline_tint_amount.
render_mode cull_front, unshaded;

uniform float outline_width_px : hint_range(0.0, 8.0) = 1.6;
uniform float outline_far_width_px : hint_range(0.0, 8.0) = 0.9;
uniform float outline_fade_start_m : hint_range(0.0, 500.0) = 45.0;
uniform float outline_far_distance_m : hint_range(1.0, 1000.0) = 110.0;
uniform vec4 outline_color : source_color = vec4(0.05, 0.04, 0.05, 1.0);
uniform float outline_tint_amount : hint_range(0.0, 1.0) = 0.65;
uniform float outline_tint_darken : hint_range(0.0, 1.0) = 0.35;

instance uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_pos;
	vec3 view_normal = normalize((MODELVIEW_NORMAL_MATRIX * NORMAL));
	vec2 clip_dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	float dir_len = length(clip_dir);
	vec2 dir = dir_len > 0.0001 ? clip_dir / dir_len : vec2(0.0);

	float dist = length(view_pos.xyz);
	float far_t = smoothstep(outline_fade_start_m, outline_far_distance_m, dist);
	float width_px = mix(outline_width_px, outline_far_width_px, far_t);
	// NDC spans 2 units across the viewport; clip.w undoes the divide.
	vec2 ndc_offset = dir * width_px * 2.0 / VIEWPORT_SIZE;
	clip.xy += ndc_offset * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 darkened_tint = tint_color.rgb * outline_tint_darken;
	ALBEDO = mix(outline_color.rgb, darkened_tint, outline_tint_amount);
}
