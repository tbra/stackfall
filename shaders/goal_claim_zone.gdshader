shader_type spatial;
// Bontago-mp0.147: the goal beacon's claim zone, one flat disc mesh drawn in one
// pass. Cel-shaded to match the Sunset Signal look: a faint stepped fill that
// brightens in hard bands toward the edge, slow rings drifting inward, and a crisp
// rim made of a solid outer line plus a dashed inner line (so the edge still reads
// when colour is the only difference). Unshaded, no screen reads, no depth write.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 zone_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// Radius of the rim's centre line in metres (the host's claim radius).
uniform float zone_radius = 6.0;
uniform float rim_width = 0.5;
uniform float rim_alpha = 0.8;
uniform float fill_alpha = 0.14;
uniform float cel_steps = 4.0;
uniform float ring_count = 3.0;
uniform float ring_speed = 0.12;
uniform float ring_width = 0.12;
uniform float dash_count = 64.0;
// 0..1 progress of a capture in this zone: brightens the fill and rings.
uniform float capture = 0.0;
uniform float capture_boost = 1.5;
uniform float rim_edge_lighten = 0.45;

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

void fragment() {
	float d = length(local_xz);
	float aa = max(fwidth(d), 0.001);
	float half_w = rim_width * 0.5;
	float from_rim = abs(d - zone_radius);
	float rim_mask = 1.0 - smoothstep(half_w - aa, half_w, from_rim);

	// Outer half of the rim is a solid line; the inner half is dashed.
	float outward = d - zone_radius;
	float dash_phase = fract(atan(local_xz.x, local_xz.y) / 6.28318 * round(dash_count));
	float dash = step(0.5, dash_phase);
	float solid_part = smoothstep(half_w * 0.15 - aa, half_w * 0.15 + aa, outward);
	float rim = rim_mask * mix(dash, 1.0, solid_part);

	// Cel-stepped fill inside the rim: bands brighten toward the edge.
	float t = clamp(d / max(zone_radius, 0.001), 0.0, 1.0);
	float steps = max(cel_steps, 1.0);
	float banded = floor(t * steps) / steps;
	float inside = 1.0 - smoothstep(zone_radius - half_w - aa, zone_radius - half_w, d);
	float boost = 1.0 + capture * capture_boost;
	float fill = fill_alpha * (0.4 + 0.6 * banded) * boost;

	// Rings drift inward (phase grows with time, pattern moves toward the centre).
	float ring_phase = fract(t * ring_count + TIME * ring_speed);
	float ring = step(1.0 - ring_width, ring_phase) * smoothstep(0.1, 0.4, t);
	float ring_a = ring * fill_alpha * 2.5 * boost;

	float inner_a = clamp(fill + ring_a, 0.0, 1.0) * inside;
	vec3 base = zone_color.rgb;
	vec3 light = mix(base, vec3(1.0), rim_edge_lighten);
	float rim_a = rim * rim_alpha;
	float a = max(inner_a, rim_a);
	ALBEDO = mix(base, light, step(inner_a, rim_a));
	ALPHA = a;
}
