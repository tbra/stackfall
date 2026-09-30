shader_type spatial;
// Bontago-22y.6: one falling snowflake. Camera-facing particle quad drawn as
// a soft round dot (never a visible square), unshaded, no depth write.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 flake_color : source_color = vec4(0.96, 0.98, 1.0, 0.9);
uniform float core = 0.35;

void vertex() {
	// Billboard, keeping the particle's own scale.
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(vec4(scale, 0.0, 0.0, 0.0), vec4(0.0, scale, 0.0, 0.0), vec4(0.0, 0.0, scale, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float alpha = 1.0 - smoothstep(core, 1.0, d);
	if (alpha <= 0.0) {
		discard;
	}
	ALBEDO = flake_color.rgb;
	ALPHA = flake_color.a * alpha;
}
