shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-22y.4: wind streaks and drifting motes (vfx/weather/WindPresentation.gd
// builds one MultiMesh per kind). The script feeds `travel` (metres advanced
// along the wind, integrated from the gusting speed) and `wind_dir`; all
// per-instance scatter and wrapping happens here, so there is no per-frame
// per-instance CPU cost.
//
// Per-instance data:
//   INSTANCE_CUSTOM.xyz = scatter in 0..1 across the box (x, height, z)
//   INSTANCE_CUSTOM.w   = rank 0..1; shown while rank < density

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);
uniform float travel = 0.0;
uniform float density : hint_range(0.0, 1.0) = 1.0;
uniform vec3 box_half = vec3(55.0, 20.0, 55.0);
uniform float box_base_y = -6.0;
uniform float length_m = 5.0;
uniform float width_m = 0.09;
// 0 = streak (tapered line), 1 = mote (soft tumbling dot).
uniform float mote_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 band_tint : source_color = vec4(1.0);
uniform float band_width : hint_range(0.0, 1.0) = 0.28;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.14;
uniform float fade_far_m = 120.0;
uniform float bob_m = 0.4;
// Motes fade out this close to the camera (start, fully visible).
uniform vec2 near_fade_m = vec2(8.0, 26.0);

varying float shown;
varying float shape_mix;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	vec3 size = box_half * 2.0;
	vec3 home = vec3(INSTANCE_CUSTOM.x, 0.0, INSTANCE_CUSTOM.z) * size;
	// Advance along the wind (each instance a slightly different pace), wrap in the XZ box.
	vec3 along = wind_dir * travel * (0.7 + 0.6 * hash11(seed * 13.0));
	vec3 p = home + along;
	p.x = mod(p.x, size.x) - box_half.x;
	p.z = mod(p.z, size.z) - box_half.z;
	p.y = box_base_y + INSTANCE_CUSTOM.y * (box_half.y * 2.0)
		+ bob_m * sin(travel * 0.15 + seed * 40.0);
	vec4 view_pos = VIEW_MATRIX * vec4(p, 1.0);
	// Bontago-mp0.28: the screen direction of the world heading must follow the
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
	// Foreshorten a streak that points at the camera; motes keep a fixed size.
	float foreshorten = mix(max(d2_len, 0.25), 1.0, mote_mix);
	// A mote tumbles: rotate its screen axes.
	float spin = travel * 0.4 + seed * 30.0;
	vec2 ax = mix(d2, vec2(cos(spin), sin(spin)), mote_mix);
	vec2 ay = mix(perp, vec2(-ax.y, ax.x), mote_mix);
	vec2 corner = vec2(VERTEX.x * length_m * foreshorten, VERTEX.y * width_m);
	VERTEX = view_pos.xyz + vec3(ax * corner.x + ay * corner.y, 0.0);
	float dist = length(view_pos.xyz);
	shown = (1.0 - smoothstep(density - 0.06, density, seed))
		* (1.0 - smoothstep(fade_far_m * 0.5, fade_far_m, dist))
		* mix(smoothstep(0.12, 0.45, d2_len), 1.0, mote_mix)
		* mix(1.0, smoothstep(near_fade_m.x, near_fade_m.y, dist), mote_mix);
	shape_mix = mote_mix;
}

void fragment() {
	// DECISION: two flat colour bands and only an alpha feather keep the
	// storm's longer, straighter strips cel shaded instead of blurred.
	vec2 c = UV - vec2(0.5);
	float taper = 1.0 - abs(c.x) * 2.0;
	float half_width = 0.5 * taper * taper;
	float line = 1.0 - smoothstep(max(0.0, half_width - edge_softness), half_width, abs(c.y));
	line *= smoothstep(0.0, 0.25, taper);
	float band = step(abs(c.y), half_width * band_width);
	float r = clamp(length(c) * 2.0, 0.0, 1.0);
	float dot_alpha = smoothstep(0.0, 0.6, 1.0 - r);
	vec3 core = mix(tint.rgb, vec3(1.0, 0.8, 0.4), 0.35 * (1.0 - r) * shape_mix);
	float a = mix(line, dot_alpha, shape_mix);
	ALBEDO = mix(mix(tint.rgb, band_tint.rgb, band), core, shape_mix);
	ALPHA = a * tint.a * shown;
}
