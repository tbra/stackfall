shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
// Bontago-mp0.120: cel dust-puff flipbook (assets/vfx/impact_puff_v1, 4x4 atlas
// of 256px cells, 16 frames). Billboarded on the camera; the contact pivot
// (UV y = pivot_uv_y) sits on the node origin so the dust rises from the
// impact point. No mipmaps/filter bleed: linear filtering, no mip sampling.

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float frame = 0.0;
uniform float quad_size = 1.0;
uniform float pivot_uv_y = 0.609375;
uniform float alpha_scale = 1.0;
uniform float grid = 4.0;

void vertex() {
	vec2 local = VERTEX.xy;
	local.y += pivot_uv_y - 0.5;
	local *= quad_size;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	VERTEX = vec3(local, 0.0);
}

void fragment() {
	float f = floor(frame + 0.5);
	vec2 cell = vec2(mod(f, grid), floor(f / grid));
	vec4 texel = texture(atlas, (UV + cell) / grid);
	ALBEDO = texel.rgb * tint.rgb;
	ALPHA = texel.a * tint.a * alpha_scale;
}
