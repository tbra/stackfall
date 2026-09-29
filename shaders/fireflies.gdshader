shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-adt.3: night-theme fireflies (vfx/Fireflies.gd builds one MultiMesh of
// billboard quads; every bit of motion and blinking is computed here from TIME,
// so there is no per-frame script and no CPU cost).
//
// Per-instance data:
//   MODEL_MATRIX origin.x = 0 for rim/cloud-sea motes, 1 for sparse motes above
//                           the disc's outer band
//   INSTANCE_CUSTOM.x = azimuth around the disc (rad)
//   INSTANCE_CUSTOM.y = radial fraction 0..1 within the band
//   INSTANCE_CUSTOM.z = height fraction 0..1 within the band
//   INSTANCE_CUSTOM.w = per-mote random seed 0..1

uniform float disc_radius = 30.0;
uniform vec2 rim_offset = vec2(-1.0, 26.0);
uniform vec2 rim_height = vec2(-22.0, 4.0);
uniform float above_inset = 8.0;
uniform vec2 above_height = vec2(2.0, 9.0);
uniform float drift_radius = 2.2;
uniform float drift_speed = 0.35;
uniform float blink_hz = 0.35;
uniform float size_m = 0.16;
uniform vec3 glow_color : source_color = vec3(0.72, 1.0, 0.28);
uniform float energy = 3.0;
uniform float fade_far_m = 140.0;
uniform float min_glow = 0.18;

varying float pulse;
varying float fade;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	float above = MODEL_MATRIX[3].x;
	float radius = mix(disc_radius + mix(rim_offset.x, rim_offset.y, INSTANCE_CUSTOM.y),
		disc_radius - INSTANCE_CUSTOM.y * above_inset, above);
	float height = mix(mix(rim_height.x, rim_height.y, INSTANCE_CUSTOM.z),
		mix(above_height.x, above_height.y, INSTANCE_CUSTOM.z), above);
	vec3 home = vec3(cos(INSTANCE_CUSTOM.x) * radius, height, sin(INSTANCE_CUSTOM.x) * radius);
	float t = TIME * drift_speed + seed * 100.0;
	vec3 drift = vec3(sin(t * 1.0 + seed * 17.0) + 0.5 * sin(t * 2.3 + seed * 5.0),
		0.6 * sin(t * 0.83 + seed * 31.0),
		cos(t * 1.1 + seed * 11.0) + 0.5 * cos(t * 1.9 + seed * 7.0)) * drift_radius * 0.66;
	vec4 view_pos = VIEW_MATRIX * vec4(home + drift, 1.0);
	float blink_phase = TIME * TAU * blink_hz * (0.6 + hash11(seed + 2.0) * 0.8) + seed * 40.0;
	pulse = mix(min_glow, 1.0, smoothstep(0.35, 0.95, 0.5 + 0.5 * sin(blink_phase)));
	float dist = length(view_pos.xyz);
	fade = 1.0 - smoothstep(fade_far_m * 0.55, fade_far_m, dist);
	float scale = size_m * (0.6 + 0.4 * pulse);
	VERTEX = view_pos.xyz + vec3(VERTEX.xy * scale, 0.0);
}

void fragment() {
	float d = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float falloff = pow(1.0 - d, 2.0) + 0.6 * pow(1.0 - d, 6.0);
	ALBEDO = glow_color * energy * pulse * fade;
	ALPHA = clamp(falloff, 0.0, 1.0);
}
