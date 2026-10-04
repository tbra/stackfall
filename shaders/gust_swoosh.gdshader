shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-59o.6: cartoon wind swooshes. Bontago-mp0.81 swapped the two wind looks: this
// curled SWOOSH look is now the ambient Storm wind's (vfx/weather/StormPresentation.gd
// scatters the strokes through its weather box: `center`/`radius`/spread_* describe that
// volume); a Breeze gust now draws the soft wisp look (wind_streak.gdshader).
// Each instance is a tapered ribbon (mesh built in GDScript: VERTEX = centerline point
// in stroke space, NORMAL.xy = ribbon normal, UV = (arc fraction t, side -1..1)).
// A stroke draws on from its tail to its curled head, holds, then erases from the tail,
// and respawns at a new hashed spot every cycle. All motion is here, so a gust costs
// no per-frame CPU per stroke.
//
// Per-instance data: INSTANCE_CUSTOM.x = cluster seed, .y = cycle phase,
// .z = parallel index within the cluster (-1, 0, 1 ...), .w = per-stroke variation.
// .x doubles as the stratified rank 0..1 that `density` thins by (clusters fade together).

uniform vec3 center = vec3(0.0);
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);
uniform float radius = 4.0;
uniform float length_m = 3.0;
uniform float width_m = 0.22;
uniform float speed = 3.0;
uniform float travel = 0.0;
uniform float life : hint_range(0.0, 1.0) = 1.0;
// Fraction of the stroke set drawn (clusters thin by seed), plus fades by camera distance:
// strokes closer than near_fade_m.x vanish and are whole by .y (a near stroke would span the
// screen); beyond fade_far_m / 2 they fade out. Zero = off.
uniform float density : hint_range(0.0, 1.0) = 1.0;
uniform vec2 near_fade_m = vec2(0.0);
uniform float fade_far_m = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float spacing_m = 0.35;
uniform float cycle_s = 1.8;
uniform float draw_frac = 0.4;
uniform float erase_frac = 0.35;
uniform float tip_taper = 0.12;
// Bontago-mp0.131: feather (arc fraction) of the draw-on head and draw-off tail edge.
uniform float reveal_softness = 0.25;
uniform float peak_bias = 0.8;
uniform float spread_along = 0.8;
uniform float spread_side = 0.7;
uniform float spread_up = 0.6;
uniform float min_foreshorten = 0.25;
uniform float length_variation = 0.4;
uniform float parallel_shrink = 0.2;
uniform float parallel_lag = 0.15;
uniform float anchor_frac = 0.4;
uniform float height_bias = 1.8;
uniform float height_length_gain = 0.8;

const float PI_C = 3.14159265;

varying float side_v;
varying float shown;
varying float along_v;
varying vec2 window_v;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float cycle = travel / cycle_s + INSTANCE_CUSTOM.y;
	float idx = floor(cycle);
	float c = cycle - idx;
	float key = seed * 91.7 + idx * 13.3;
	vec3 side = normalize(cross(wind_dir, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, wind_dir);
	float along = (hash(key + 1.0) * 2.0 - 1.0) * radius * spread_along + c * cycle_s * speed;
	// Bontago-mp0.28 round 2: height_bias > 1 pushes strokes toward the top of the
	// gust volume (matching the height-weighted force); higher strokes run longer.
	float high = pow(hash(key + 3.0), 1.0 / max(height_bias, 0.1));
	vec3 p = center + wind_dir * along
		+ side * ((hash(key + 2.0) * 2.0 - 1.0) * radius * spread_side)
		+ up * ((high * 2.0 - 1.0) * radius * spread_up);
	vec4 view_pos = VIEW_MATRIX * vec4(p, 1.0);
	// Bontago-mp0.28: the screen direction of the world heading (wind_dir) must follow the
	// perspective projection (strokes converge on the heading's vanishing
	// point), not the camera-plane projection of the direction vector, or
	// off-centre strokes visibly disagree with the way the wind moves.
	vec3 dir_view = (VIEW_MATRIX * vec4(wind_dir, 0.0)).xyz;
	vec3 end_view = (VIEW_MATRIX * vec4(p + wind_dir * length_m, 1.0)).xyz;
	vec2 d2 = dir_view.xy;
	float d2_len = length(d2);
	if (view_pos.z < -0.5 && end_view.z < -0.5) {
		vec2 projected = end_view.xy / -end_view.z - view_pos.xy / -view_pos.z;
		d2 = projected * -view_pos.z;
		float projected_len = length(d2);
		d2_len = min(projected_len / max(length_m, 0.001), 1.0);
		d2 = projected_len > 0.0001 ? d2 / projected_len * d2_len : d2;
	}
	d2 = d2_len > 0.0001 ? d2 / d2_len : vec2(1.0, 0.0);
	vec2 perp = vec2(-d2.y, d2.x);
	float foreshorten = max(d2_len, min_foreshorten);
	float flip = hash(key + 4.0) < 0.5 ? 1.0 : -1.0;
	float len = length_m * (1.0 - 0.5 * length_variation + length_variation * INSTANCE_CUSTOM.w) * (1.0 - parallel_shrink * abs(INSTANCE_CUSTOM.z)) * (1.0 + height_length_gain * (high - 0.5));

	float t = UV.x;
	float head = smoothstep(0.0, 1.0, clamp(c / draw_frac, 0.0, 1.0));
	float tail_c = (c - (1.0 - erase_frac)) / erase_frac;
	float tail = smoothstep(0.0, 1.0, clamp(tail_c, 0.0, 1.0));
	float f = max(tip_taper, 0.001);
	float ends = clamp((t - tail) / f, 0.0, 1.0) * clamp((head - t) / f, 0.0, 1.0);
	float profile = sin(PI_C * pow(t, peak_bias));
	float half_w = 0.5 * width_m * profile * ends;

	vec2 local = vec2(VERTEX.x - anchor_frac, VERTEX.y * flip);
	vec2 n2 = vec2(NORMAL.x, NORMAL.y * flip);
	vec2 centre2 = vec2(local.x * len * foreshorten, local.y * len)
		+ vec2(INSTANCE_CUSTOM.z * parallel_lag * len * foreshorten, INSTANCE_CUSTOM.z * spacing_m);
	vec2 off = centre2 + n2 * half_w * UV.y;
	VERTEX = view_pos.xyz + vec3(d2 * off.x + perp * off.y, 0.0);
	side_v = UV.y;
	along_v = t;
	// Reveal window (mirrored by StormPresentation.reveal_window): tail edge, head edge in arc fraction.
	window_v = vec2(tail * (1.0 + reveal_softness) - reveal_softness, head * (1.0 + reveal_softness));
	float dist = length(view_pos.xyz);
	float near_w = near_fade_m.y > near_fade_m.x ? smoothstep(near_fade_m.x, near_fade_m.y, dist) : 1.0;
	float far_w = fade_far_m > 0.0 ? 1.0 - smoothstep(fade_far_m * 0.5, fade_far_m, dist) : 1.0;
	float thin = density >= 1.0 ? 1.0 : 1.0 - smoothstep(density - 0.06, density, seed);
	shown = life * near_w * far_w * thin;
}

void fragment() {
	float edge = clamp((1.0 - abs(side_v)) / max(fwidth(side_v), 0.0001), 0.0, 1.0);
	ALBEDO = tint.rgb;
	float soft = max(reveal_softness, 0.001);
	float reveal = smoothstep(window_v.x, window_v.x + soft, along_v) * (1.0 - smoothstep(window_v.y - soft, window_v.y, along_v));
	ALPHA = edge * reveal * tint.a * shown;
}
