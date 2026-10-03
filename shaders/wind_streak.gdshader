shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-22y.4: soft wind wisps and drifting motes. Bontago-mp0.81 swapped the
// two wind looks: this WISP look (bowed, feathered, banded ribbons) is now a Breeze
// GUST's look (vfx/weather/GustPresentation.gd, scattered in a heading-aligned box
// around the gust via box_center/box_align); the ambient Storm wind uses the curled
// swoosh look (gust_swoosh.gdshader) and only draws its motes with this shader
// (vfx/weather/StormPresentation.gd). The script feeds `travel` (metres advanced
// along the wind) and `wind_dir`; all per-instance scatter and wrapping happens
// here, so there is no per-frame per-instance CPU cost.
//
// Per-instance data:
//   INSTANCE_CUSTOM.xyz = scatter in 0..1 across the box (x, height, z)
//   INSTANCE_CUSTOM.w   = rank 0..1; shown while rank < density
//
// Bontago-mp0.35: storm streaks are wisps, not lines. Each is a curved tapered
// ribbon (mesh built in StormPresentation) that, like a gust stroke, draws on
// from its tail, holds, then erases, and respawns at a new hashed spot each
// cycle. Length, opacity and bow vary per streak, and streaks within
// near_fade_m of the camera fade out entirely (a close streak would span the
// whole screen). StormPresentation mirrors the hash and fade on the CPU for tests.

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);
uniform float travel = 0.0;
uniform float density : hint_range(0.0, 1.0) = 1.0;
uniform vec3 box_half = vec3(55.0, 20.0, 55.0);
uniform float box_base_y = -6.0;
// Wisps: the box is centred here (a gust's centre) and, when box_align is on, its
// x axis follows wind_dir and z the sideways axis (box_half = along, up, side).
uniform vec3 box_center = vec3(0.0);
uniform bool box_align = false;
// Wisps: height_bias > 1 pushes spawns toward the top of the box; strokes there
// run height_length_gain longer (0 = none). life fades the whole set (a gust's envelope).
uniform float height_bias = 1.0;
uniform float height_length_gain = 0.0;
uniform float life : hint_range(0.0, 1.0) = 1.0;
// Streak: longest length; length_min_m the shortest. Mote: both are its size.
uniform float length_m = 12.0;
uniform float length_min_m = 4.0;
uniform float width_m = 0.2;
// 0 = streak (curved tapered ribbon), 1 = mote (soft tumbling dot).
uniform float mote_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 band_tint : source_color = vec4(1.0);
uniform float band_width : hint_range(0.0, 1.0) = 0.28;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.14;
uniform float fade_far_m = 120.0;
uniform float bob_m = 0.4;
// Motes fade out this close to the camera (start, fully visible).
uniform vec2 near_fade_m = vec2(8.0, 26.0);
// Streaks: metres drifted over one life, draw-on / erase fractions of the life,
// end taper, bow and wobble amplitude (m), opacity floor.
uniform float life_m = 70.0;
uniform float draw_frac = 0.3;
uniform float erase_frac = 0.35;
uniform float tip_taper = 0.3;
uniform float bow_m = 0.6;
uniform float wobble_m = 0.25;
uniform float opacity_min = 0.35;

const float PI_C = 3.14159265;

varying float shown;
varying float shape_mix;
varying float side_v;
varying float along_v;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	vec3 size = box_half * 2.0;
	vec3 p;
	float c = 0.5;
	float key = 0.0;
	float high = 0.5;
	if (mote_mix > 0.5) {
		vec3 home = vec3(INSTANCE_CUSTOM.x, 0.0, INSTANCE_CUSTOM.z) * size;
		vec3 along = wind_dir * travel * (0.7 + 0.6 * hash11(seed * 13.0));
		p = home + along;
		p.x = mod(p.x, size.x) - box_half.x;
		p.z = mod(p.z, size.z) - box_half.z;
		p.y = box_base_y + INSTANCE_CUSTOM.y * (box_half.y * 2.0)
			+ bob_m * sin(travel * 0.15 + seed * 40.0);
	} else {
		float cycle = travel / life_m * (0.8 + 0.4 * hash11(seed * 7.0)) + INSTANCE_CUSTOM.x;
		float idx = floor(cycle);
		c = cycle - idx;
		key = seed * 91.7 + idx * 13.3;
		high = pow(hash11(key + 3.0), 1.0 / max(height_bias, 0.1));
		vec3 home = vec3(hash11(key + 1.0) - 0.5, high, hash11(key + 2.0) - 0.5);
		vec3 local = vec3(home.x * size.x, box_base_y + home.y * size.y, home.z * size.z);
		if (box_align) {
			vec3 side_axis = normalize(cross(wind_dir, vec3(0.0, 1.0, 0.0)));
			local = vec3(0.0, local.y, 0.0) + wind_dir * local.x + side_axis * local.z;
		}
		p = box_center + local + wind_dir * (c - 0.5) * life_m;
	}
	float len = mix(length_min_m, length_m, hash11(key + 5.0));
	len *= 1.0 + height_length_gain * (high - 0.5);
	len = mix(len, length_m, mote_mix);
	vec4 view_pos = VIEW_MATRIX * vec4(p, 1.0);
	// Bontago-mp0.28: the screen direction of the world heading must follow the
	// perspective projection (strokes converge on the heading's vanishing
	// point), not the camera-plane projection of the direction vector, or
	// off-centre strokes visibly disagree with the way the wind moves.
	vec3 dir_view = (VIEW_MATRIX * vec4(wind_dir, 0.0)).xyz;
	vec3 end_view = (VIEW_MATRIX * vec4(p + wind_dir * len, 1.0)).xyz;
	vec2 d2 = dir_view.xy;
	float d2_len = length(d2);
	if (view_pos.z < -0.5 && end_view.z < -0.5) {
		vec2 projected = end_view.xy / -end_view.z - view_pos.xy / -view_pos.z;
		d2 = projected * -view_pos.z;
		float projected_len = length(d2);
		d2_len = min(projected_len / max(len, 0.001), 1.0);
		d2 = projected_len > 0.0001 ? d2 / projected_len * d2_len : d2;
	}
	d2 = d2_len > 0.0001 ? d2 / d2_len : vec2(1.0, 0.0);
	vec2 perp = vec2(-d2.y, d2.x);
	// Foreshorten a streak that points at the camera; motes keep a fixed size.
	float foreshorten = mix(max(d2_len, 0.25), 1.0, mote_mix);
	// A mote tumbles: rotate its screen axes.
	float spin = travel * 0.4 + seed * 30.0;
	vec2 ax = mix(d2, vec2(cos(spin), sin(spin)), mote_mix);
	vec2 ay = mix(perp, vec2(-ax.y, ax.x), mote_mix);

	float t = UV.x;
	// Draw on from the tail, hold, erase from the tail (the gust's approach).
	float head = smoothstep(0.0, 1.0, clamp(c / draw_frac, 0.0, 1.0));
	float tail = smoothstep(0.0, 1.0, clamp((c - (1.0 - erase_frac)) / erase_frac, 0.0, 1.0));
	float f = max(tip_taper, 0.001);
	float ends = clamp((t - tail) / f, 0.0, 1.0) * clamp((head - t) / f, 0.0, 1.0);
	float profile = sin(PI_C * t);
	float side = VERTEX.y * 2.0;
	float flip = hash11(key + 4.0) < 0.5 ? 1.0 : -1.0;
	float bend = flip * bow_m * sin(PI_C * t) * (0.5 + hash11(key + 6.0))
		+ wobble_m * sin(t * 9.0 + hash11(key + 7.0) * 6.28 + travel * 0.05) * profile;
	vec2 streak_off = vec2((t - 0.5) * len * foreshorten, bend + side * 0.5 * width_m * profile * ends);
	vec2 mote_off = vec2(VERTEX.x * length_m, VERTEX.y * width_m);
	vec2 off = mix(streak_off, mote_off, mote_mix);
	VERTEX = view_pos.xyz + vec3(ax * off.x + ay * off.y, 0.0);
	float dist = length(view_pos.xyz);
	float streak_alpha = mix(opacity_min, 1.0, hash11(key + 8.0))
		* smoothstep(near_fade_m.x, near_fade_m.y, dist);
	// density 1.0 shows everything (the soft edge only thins a partial density).
	shown = life * (density >= 1.0 ? 1.0 : 1.0 - smoothstep(density - 0.06, density, seed))
		* (1.0 - smoothstep(fade_far_m * 0.5, fade_far_m, dist))
		* mix(streak_alpha * smoothstep(0.12, 0.45, d2_len), smoothstep(near_fade_m.x, near_fade_m.y, dist), mote_mix);
	shape_mix = mote_mix;
	side_v = side;
	along_v = t;
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	// Streak: soft feathered edge across the ribbon, fading out toward both tips.
	float line = 1.0 - smoothstep(1.0 - max(edge_softness * 3.0, 0.05), 1.0, abs(side_v));
	line *= smoothstep(0.0, 0.3, along_v) * smoothstep(1.0, 0.7, along_v);
	float band = step(abs(side_v), band_width);
	float r = clamp(length(c) * 2.0, 0.0, 1.0);
	float dot_alpha = smoothstep(0.0, 0.6, 1.0 - r);
	vec3 core = mix(tint.rgb, vec3(1.0, 0.8, 0.4), 0.35 * (1.0 - r) * shape_mix);
	float a = mix(line, dot_alpha, shape_mix);
	ALBEDO = mix(mix(tint.rgb, band_tint.rgb, band), core, shape_mix);
	ALPHA = a * tint.a * shown;
}
