shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Bontago-8or.26: flat-shaded cel vortex drawn on a horizontal disc whose edge is the
// black hole's pull radius (game/specials/BlackHoleVisual.gd). Dark core, swirling
// two-tone accretion arms, and thin streaks sliding inward. `grow` (0..1) scales the
// whole pattern so it grows in on spawn and collapses at the end of the lifetime.

uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform float time_s = 0.0;
uniform float core_fraction = 0.16;
uniform float ring_inner = 0.16;
uniform float ring_outer = 0.7;
uniform float arm_count = 4.0;
uniform float arm_twist = 5.0;
uniform float spin_speed = 1.6;
uniform float streaks_on = 1.0;
uniform float streak_count = 14.0;
uniform float streak_density = 7.0;
uniform float streak_speed = 0.8;
uniform float streak_width = 0.12;
uniform float streak_alpha = 0.5;
uniform float dash_threshold = 0.35;
uniform float streak_fade_start = 0.8;
uniform float cel_steps = 3.0;
uniform vec4 core_color : source_color = vec4(0.02, 0.0, 0.05, 1.0);
uniform vec4 ring_color_a : source_color = vec4(0.62, 0.25, 0.95, 1.0);
uniform vec4 ring_color_b : source_color = vec4(0.95, 0.55, 0.25, 1.0);
uniform vec4 streak_color : source_color = vec4(0.75, 0.6, 1.0, 1.0);

const float TAU_C = 6.2831853;

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / max(grow, 0.001);
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(p.y, p.x);
	vec3 col = core_color.rgb;
	float alpha = 1.0;
	if (r > core_fraction) {
		float curl = ang - spin_speed * time_s + arm_twist * smoothstep(ring_inner, ring_outer, r);
		float arm = step(0.0, cos(curl * arm_count));
		float band_in = step(ring_inner, r);
		float band_out = 1.0 - step(ring_outer, r);
		float ring = band_in * band_out;
		// Cel-stepped fade toward the ring's outer edge.
		float fade = 1.0 - smoothstep(ring_inner, ring_outer, r);
		float stepped = ceil(fade * cel_steps) / cel_steps;
		vec3 ring_col = mix(ring_color_b.rgb, ring_color_a.rgb, arm);
		// Inward-sliding streaks across the outer disc.
		if (streaks_on > 0.5) {
			float lane = fract(ang / TAU_C * streak_count);
			float lane_mask = 1.0 - step(streak_width, abs(lane - 0.5));
			float dash = 1.0 - step(dash_threshold, fract(r * streak_density + time_s * streak_speed));
			float streak = lane_mask * dash * streaks_on * (1.0 - ring) * (1.0 - smoothstep(streak_fade_start, 1.0, r));
			col = mix(ring_col, streak_color.rgb, streak * (1.0 - ring));
			alpha = max(ring * stepped, streak * streak_alpha);
		} else {
			col = ring_col;
			alpha = ring * stepped;
		}
	}
	ALBEDO = col;
	ALPHA = alpha;
}
