shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// A soft, round, billboarded quad with a procedural radial alpha falloff
// (no texture asset). It never writes EMISSION, so it cannot trigger
// Main.tscn's Environment.glow_hdr_threshold bloom.
//
// DECISION: `render_mode billboard` is a StandardMaterial3D-only concept
// (BaseMaterial3D.billboard_mode) -- Godot's spatial shading language has no
// such render_mode keyword ("Invalid render mode: 'billboard'"). The vertex()-level billboard
// trick below (reconstructing MODELVIEW_MATRIX from VIEW_MATRIX/
// INV_VIEW_MATRIX, keeping only MODEL_MATRIX's own translation) is the
// custom-shader equivalent.
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

uniform vec4 dust_color : source_color = vec4(0.82, 0.78, 0.7, 1.0);
uniform float max_alpha = 0.42;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float d = length(centered) * 2.0; // 0 at center, 1 at the quad's edge.
	float soft = 1.0 - smoothstep(0.35, 1.0, d);
	ALBEDO = dust_color.rgb;
	// COLOR.a carries the particle's remaining-lifetime fade (color_ramp).
	ALPHA = soft * max_alpha * COLOR.a;
}
