shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Bontago-mp0.3.4 fix round (owner: dust rendered as "huge flat hard-edged
// blown-out yellow rectangles smeared across the disc" -- the previous
// candidate was a plain unshaded BoxMesh cube, many of which overlapped
// into one solid blob at close range). A soft, round, billboarded quad
// instead: a procedural radial alpha falloff (no texture asset needed,
// "procedural in shader is fine" per the owner's own fix-round note),
// never writing to EMISSION at all so it can never trigger Main.tscn's
// Environment.glow_hdr_threshold bloom -- "no bloom" per the same note.
//
// DECISION: `render_mode billboard` is a StandardMaterial3D-only concept
// (BaseMaterial3D.billboard_mode) -- Godot's spatial shading language has no
// such render_mode keyword (confirmed by a compile error, "Invalid render
// mode: 'billboard'", while adding this file's own tests/unit/
// test_block_effects.gd coverage). The standard vertex()-level billboard
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
	// COLOR.a carries this particle's own remaining-lifetime fade
	// (ParticleProcessMaterial.color_ramp, set in
	// BlockEffectsManager._build_dust_process_material()).
	ALPHA = soft * max_alpha * COLOR.a;
}
