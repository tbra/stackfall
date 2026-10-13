shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// Falling-block trail ribbon. BlockEffectsManager owns the geometry: one unit
// quad from the head (UV.y = 0, at the block's visual centre) to the tail
// (UV.y = 1), turned about the travel axis to face the camera and scaled to
// the block's width and its fall speed every physics step.
// Bontago-a3z: a soft glow across the ribbon's width with a brighter core and
// `line_count` thin speed lines, so one ribbon reads as the mockup's streaked
// falling piece instead of three hair-thin strips.

uniform vec4 trail_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.2;
uniform float max_alpha = 0.9;
uniform float line_count = 3.0;
// Width of one speed line as a fraction of its lane.
uniform float line_width = 0.18;
// Fraction of the length over which the head fades in (hides the hard edge).
uniform float head_fade = 0.06;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float glow = 1.0 - smoothstep(0.55, 1.0, across);
	float core = 1.0 - smoothstep(0.0, 0.45, across);
	float lines = 0.0;
	if (line_count > 0.5) {
		float lane = fract(UV.x * line_count) * 2.0 - 1.0;
		lines = 1.0 - smoothstep(line_width * 0.5, line_width, abs(lane));
		// Lines run shorter than the glow, staggered by lane, like speed streaks.
		float lane_index = floor(UV.x * line_count);
		float reach = 0.55 + 0.35 * fract(sin(lane_index * 12.9898) * 43758.5453);
		lines *= 1.0 - smoothstep(reach * 0.6, reach, UV.y);
	}
	float along = (1.0 - smoothstep(0.2, 1.0, UV.y)) * smoothstep(0.0, head_fade, UV.y);
	float strength = clamp(0.8 * glow + 0.2 * core + 0.5 * lines, 0.0, 1.0) * along;
	vec3 colour = mix(trail_color.rgb, vec3(1.0), 0.1 * core + 0.45 * lines);
	ALBEDO = colour;
	EMISSION = colour * emission_energy * strength;
	ALPHA = strength * max_alpha;
}
