shader_type spatial;
// Bontago-adt.2 (graphics roadmap "Textures/materials (disc/emissive)"):
// additive overlay drawn as the `next_pass` of game/DiscBody.gd's band
// StandardMaterial3D. It gives the plain graphite side wall its "banded body"
// read from mockup 08 without replacing that material: a thin dim gold inlay
// line just under the glowing chamfer, a second faint line near the bottom
// edge, and a cool lavender fresnel sheen so the side reflects the sky as a
// polished graphite wall rather than borrowing the sunset's orange. Additive
// and unshaded, so it cannot brighten past its own (tunable) energy; the
// bottom cap is masked out by its downward normal.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec3 inlay_color : source_color = vec3(1.0, 0.7, 0.3);
uniform float inlay_energy : hint_range(0.0, 4.0) = 0.9;
uniform float inlay_position : hint_range(0.0, 1.0) = 0.12;
uniform float inlay_width : hint_range(0.001, 0.3) = 0.03;
uniform float lower_line_position : hint_range(0.0, 1.0) = 0.88;
uniform float lower_line_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec3 sheen_color : source_color = vec3(0.5, 0.45, 0.75);
uniform float sheen_strength : hint_range(0.0, 2.0) = 0.45;
uniform float sheen_power : hint_range(0.5, 10.0) = 2.5;

varying float v_side;

void vertex() {
	// 1 on the vertical wall, 0 on the flat bottom cap.
	v_side = 1.0 - smoothstep(0.5, 0.9, abs((MODEL_MATRIX * vec4(NORMAL, 0.0)).y));
}

void fragment() {
	float line_aa = max(fwidth(UV.y), 0.0005);
	float inlay = 1.0 - smoothstep(inlay_width * 0.5, inlay_width * 0.5 + line_aa * 1.5, abs(UV.y - inlay_position));
	float lower = 1.0 - smoothstep(inlay_width * 0.3, inlay_width * 0.3 + line_aa * 1.5, abs(UV.y - lower_line_position));
	float fres = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), sheen_power);
	vec3 col = inlay_color * inlay_energy * inlay
		+ sheen_color * lower_line_strength * lower
		+ sheen_color * sheen_strength * fres;
	ALBEDO = col * v_side;
}
