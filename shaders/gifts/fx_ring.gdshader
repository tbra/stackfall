shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
// a flat expanding ring (the cartoon blast's shock ring, the Freeze
// frost ring and the Jumping Bean hop ring),
// drawn on a 2x2 plane whose UV edge is radius 1. The caller scales the node to
// the current radius and sets `width_frac` (band width / radius) and `alpha_scale`.
// `fill` adds a faint disc inside the band (0 = band only).

uniform vec4 ring_color : source_color = vec4(1.0, 0.92, 0.65, 1.0);
uniform float width_frac = 0.1;
uniform float alpha_scale = 1.0;
uniform float fill = 0.0;
uniform float glow = 1.5;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float aa = fwidth(r);
	float outer = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float band = smoothstep(1.0 - width_frac - aa, 1.0 - width_frac, r) * outer;
	float strength = max(band, fill * outer);
	ALBEDO = ring_color.rgb * glow;
	ALPHA = strength * alpha_scale;
}
