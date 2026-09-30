shader_type spatial;
// Bontago-sen.6: additive fresnel rim used as the next_pass of a held gift's
// tint overlay (game/GhostPreview.gd), so gift models glow like the plain block
// ghost does (shaders/ghost_cell_grid.gdshader computes the same rim inline).
// Purely visual: unshaded, additive, no depth write, no shadows.
render_mode blend_add, unshaded, depth_draw_never, cull_back;

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow_strength = 0.0;
uniform float glow_rim_power = 2.5;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), max(glow_rim_power, 0.01));
	ALBEDO = glow_color.rgb * glow_strength * rim;
}
