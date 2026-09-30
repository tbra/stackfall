shader_type spatial;
// Bontago-470.7: the light pillar rising from a claimed goal beacon. Additive,
// unshaded, fading to nothing at the top, with bands scrolling upward so the
// claim reads through pattern and brightness, not hue alone. When contested,
// the bands alternate between color_a and color_b (a striped beam).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform float striped : hint_range(0.0, 1.0) = 0.0;
uniform float intensity = 0.7;
uniform float energy_scale = 1.0;
uniform float band_count = 10.0;
uniform float scroll = 0.0;
uniform float band_floor : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// UV.y runs 0 at the top to 1 at the bottom of a cylinder mesh.
	float h = 1.0 - UV.y;
	float phase = h * band_count - scroll;
	float band = 0.5 + 0.5 * sin(phase * 6.28318);
	float bright = mix(band_floor, 1.0, smoothstep(0.35, 0.65, band));
	float fade = pow(1.0 - h, 1.5);
	float rim = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 0.6);
	float pick = step(0.5, fract(phase * 0.5));
	vec3 col = mix(color_a.rgb, mix(color_a.rgb, color_b.rgb, pick), striped);
	ALBEDO = col * bright * fade * intensity * energy_scale * (0.35 + 0.65 * rim);
}
