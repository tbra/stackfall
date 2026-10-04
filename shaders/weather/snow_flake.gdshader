shader_type spatial;
// Bontago-22y.6: one falling snowflake. Camera-facing particle quad drawn as
// a soft round dot (never a visible square), unshaded, no depth write.
// Bontago-mp0.97 (playtest: too subtle): the on-screen size is clamped between
// min_angle and max_angle (radians), so a far flake never shrinks to a
// sub-pixel speck and a near one never becomes a blob, and a cool outline
// (edge_color from edge_start across the flake) keeps the white core readable
// against the bright sky.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 flake_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.5, 0.64, 0.9, 1.0);
uniform float edge_start = 0.4;
uniform float core = 0.65;
uniform float edge_blend = 0.25;
// The quad's world size (metres), to turn the clamped size back into a scale.
uniform float flake_size = 0.18;
uniform float min_angle = 0.006;
uniform float max_angle = 0.03;
// Bontago-mp0.121: optional cel snowflake atlas (columns x rows, row-major,
// top-left origin). Each particle slot keeps one random cell. Full-colour art
// already has its own shading and outline, so the dot mask and edge tint are
// skipped. No mipmaps (cells would bleed into each other).
uniform bool use_atlas = false;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec2 atlas_grid = vec2(4.0, 4.0);
varying flat float cell;

void vertex() {
	// Stable per-slot hash picks the atlas cell.
	cell = floor(fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453) * atlas_grid.x * atlas_grid.y);
	// Billboard, keeping the particle's own scale but clamping the apparent size.
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float depth = max(-(VIEW_MATRIX * MODEL_MATRIX[3]).z, 0.0);
	float world_size = clamp(flake_size * length(MODEL_MATRIX[0].xyz), depth * min_angle, depth * max_angle);
	float scale = world_size / max(flake_size, 0.0001);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(vec4(scale, 0.0, 0.0, 0.0), vec4(0.0, scale, 0.0, 0.0), vec4(0.0, 0.0, scale, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	if (use_atlas) {
		float col = mod(cell, atlas_grid.x);
		float row = floor(cell / atlas_grid.x);
		vec4 tex = texture(atlas, (UV + vec2(col, row)) / atlas_grid);
		if (tex.a <= 0.01) {
			discard;
		}
		ALBEDO = tex.rgb * flake_color.rgb;
		ALPHA = tex.a * flake_color.a;
	} else {
		float d = length(UV * 2.0 - 1.0);
		float alpha = 1.0 - smoothstep(core, 1.0, d);
		if (alpha <= 0.0) {
			discard;
		}
		ALBEDO = mix(flake_color.rgb, edge_color.rgb, smoothstep(edge_start, edge_start + edge_blend, d) * edge_color.a);
		ALPHA = flake_color.a * alpha;
	}
}
