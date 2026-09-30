shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-470.2: one Breeze gust's swirl of streaks (vfx/weather/GustPresentation.gd).
// Every streak advances along `heading` through a sphere of `radius` around
// `center` on its own helix; `life` (0..1..0 over the gust) fades the whole
// swirl in and out. All motion is here, so a gust costs no per-frame CPU per streak.
//
// Per-instance data: INSTANCE_CUSTOM.x = start along the axis, .y = helix phase,
// .z = helix radius fraction, .w = pace/seed.

uniform vec3 center = vec3(0.0);
uniform vec3 heading = vec3(1.0, 0.0, 0.0);
uniform float radius = 4.0;
uniform float length_m = 2.2;
uniform float width_m = 0.09;
uniform float speed = 7.0;
uniform float travel = 0.0;
uniform float life : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

varying float shown;

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	vec3 side = normalize(cross(heading, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, heading);
	float span = radius * 2.0;
	float pace = 0.7 + 0.6 * seed;
	float along = mod(INSTANCE_CUSTOM.x * span + travel * speed * pace, span) - radius;
	float angle = INSTANCE_CUSTOM.y * 6.2831853 + travel * 2.2 * (0.5 + seed);
	float helix = radius * 0.7 * sqrt(INSTANCE_CUSTOM.z);
	vec3 p = center + heading * along + (side * cos(angle) + up * sin(angle)) * helix;
	vec4 view_pos = VIEW_MATRIX * vec4(p, 1.0);
	vec3 dir_view = (VIEW_MATRIX * vec4(heading, 0.0)).xyz;
	vec2 d2 = dir_view.xy;
	float d2_len = length(d2);
	d2 = d2_len > 0.0001 ? d2 / d2_len : vec2(1.0, 0.0);
	vec2 perp = vec2(-d2.y, d2.x);
	float foreshorten = max(d2_len, 0.25);
	vec2 corner = vec2(VERTEX.x * length_m * foreshorten, VERTEX.y * width_m);
	VERTEX = view_pos.xyz + vec3(d2 * corner.x + perp * corner.y, 0.0);
	// Fade out toward the ends of the axis so streaks do not pop at the wrap.
	shown = life * (1.0 - smoothstep(radius * 0.6, radius, abs(along)));
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	float taper = 1.0 - abs(c.x) * 2.0;
	float line = step(abs(c.y), 0.5 * taper * taper) * smoothstep(0.0, 0.25, taper);
	ALBEDO = tint.rgb;
	ALPHA = line * tint.a * shown;
}
