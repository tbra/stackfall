shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-470.5: distant bird flocks that cross the sky. vfx/DistantBirds.gd
// schedules flights and advances `flight_clock`; everything else (the path,
// glide/flap bursts, bank, sway, formation breathing) is computed here.
//
// Per-instance data (see DistantBirds.gd):
//   MODEL_MATRIX[3]          = path start (world, m)
//   MODEL_MATRIX[0]          = flock velocity (m/s)
//   MODEL_MATRIX[1]          = formation offset (right, up, back) in m
//   MODEL_MATRIX[2]          = (duration s, sway amplitude m, flock phase rad)
//   INSTANCE_CUSTOM          = (start clock, bird seed 0..1, size m, flap-rate mult)
// A bird outside [start, start + duration] collapses to a point (not drawn).
// The mesh is a flat V in the XZ plane, nose toward +X; UV.x is 0 at the body
// and 1 at the wing tips, so the tips flap and the body stays put.

// Bontago-470.3: weather fog for a fog_disabled shader (see
// vfx/weather/WeatherFogShader.gd). Nothing closer than wfog_begin metres from
// the camera, wfog_strength at wfog_end; 0 strength = off.
uniform float wfog_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wfog_begin = 25.0;
uniform float wfog_end = 110.0;
uniform vec4 wfog_color : source_color = vec4(0.72, 0.8, 0.88, 1.0);
varying float wfog_dist;
uniform float flight_clock = 0.0;
uniform vec3 bird_color : source_color = vec3(0.16, 0.1, 0.2);
uniform vec3 haze_color : source_color = vec3(0.85, 0.5, 0.42);
uniform float haze_start_m = 250.0;
uniform float haze_end_m = 700.0;
// Wing beats (rad/s) while flapping, and how far the tips swing.
uniform float flap_speed = 11.0;
uniform float flap_amount = 0.75;
// Resting wing dihedral (tips up) while gliding, and the glide flutter.
uniform float glide_dihedral = 0.3;
uniform float glide_flutter = 0.05;
// Flap bursts: period of the glide/flap cycle (rad/s), the share of the cycle
// spent flapping (0..1) and how far birds of one flock drift out of step (rad).
uniform float burst_rate = 0.42;
uniform float burst_share = 0.4;
uniform float burst_stagger = 0.9;
// Rise/fall (m) tied to the cycle: climb while flapping, sink while gliding.
uniform float burst_height_m = 5.0;
// Lateral weave (rad/s), bank gain and per-bird wobble (rad).
uniform float sway_rate = 0.11;
uniform float bank_amount = 0.5;
uniform float bank_wobble = 0.08;
// Formation breathing: metres and rate (rad/s).
uniform float breathe_m = 2.5;
uniform float breathe_rate = 0.23;
// Seconds over which a flight fades in and out (size scale).
uniform float fade_s = 4.0;

varying float haze;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	float duration = MODEL_MATRIX[2].x;
	float t = flight_clock - INSTANCE_CUSTOM.x;
	bool alive = t >= 0.0 && t <= duration;
	t = clamp(t, 0.0, duration);
	float seed = INSTANCE_CUSTOM.y;
	float size = INSTANCE_CUSTOM.z * smoothstep(0.0, fade_s, t) * smoothstep(0.0, fade_s, duration - t);
	float sway_amp = MODEL_MATRIX[2].y;
	float flock_phase = MODEL_MATRIX[2].z;
	vec3 velocity = MODEL_MATRIX[0].xyz;

	// Glide/flap cycle: staggered per bird so the flock ripples, not pulses.
	float burst_phase = t * burst_rate + flock_phase + (hash11(seed + 5.0) - 0.5) * burst_stagger;
	float burst_wave = sin(burst_phase);
	float flapping = smoothstep(1.0 - 2.0 * burst_share, 1.0 - 2.0 * burst_share + 0.35, burst_wave);
	float height = burst_height_m * sin(burst_phase - 1.0);
	float height_rate = burst_height_m * burst_rate * cos(burst_phase - 1.0);

	// Flock-wide lateral weave, and the frame it happens in.
	vec3 flat_dir = normalize(vec3(velocity.x, 0.0, velocity.z));
	vec3 right0 = normalize(cross(flat_dir, vec3(0.0, 1.0, 0.0)));
	float sway_phase = t * sway_rate + flock_phase * 1.7;
	float sway = sway_amp * sin(sway_phase);
	float sway_rate_mps = sway_amp * sway_rate * cos(sway_phase);

	vec3 v_total = velocity + right0 * sway_rate_mps + vec3(0.0, height_rate, 0.0);
	vec3 forward = normalize(v_total);
	vec3 side = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, forward);

	// Bank into the weave (lateral acceleration), plus a small per-bird wobble.
	float lateral_accel = -sway_amp * sway_rate * sway_rate * sin(sway_phase);
	float bank = clamp(lateral_accel * bank_amount * 60.0, -0.6, 0.6) + sin(t * 0.7 + seed * 40.0) * bank_wobble;
	up = normalize(up * cos(bank) + side * sin(bank));
	side = normalize(cross(forward, up));

	// Formation offset (with slow breathing) in the flock's flat frame.
	vec3 offset = MODEL_MATRIX[1].xyz;
	float breathe = sin(t * breathe_rate + seed * 30.0) * breathe_m;
	vec3 formation = right0 * offset.x + vec3(0.0, offset.y + sin(t * 0.31 + seed * 17.0) * breathe_m * 0.4, 0.0)
		- flat_dir * (offset.z + breathe);

	float flap_rate = flap_speed * INSTANCE_CUSTOM.w;
	float flap_wave = sin(t * flap_rate + seed * 40.0);
	vec3 local = VERTEX;
	float tip = UV.x;
	local.y += tip * (glide_dihedral * (1.0 - flapping * 0.6)
		+ flap_wave * flap_amount * flapping
		+ sin(t * 1.9 + seed * 25.0) * glide_flutter * (1.0 - flapping));
	local.x -= abs(flap_wave) * tip * flap_amount * 0.3 * flapping;
	local.z *= 1.0 - 0.15 * flapping * abs(flap_wave) * tip;

	vec3 world = MODEL_MATRIX[3].xyz + velocity * t + right0 * sway + vec3(0.0, height, 0.0) + formation
		+ (forward * local.x + up * local.y + side * local.z) * size;
	haze = smoothstep(haze_start_m, haze_end_m, length(world.xz));
	if (!alive) {
		// Parked or finished: collapse every vertex to one far point (never drawn).
		world = vec3(0.0, -100000.0, 0.0);
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	wfog_dist = length(VERTEX);
	NORMAL = (VIEW_MATRIX * vec4(up, 0.0)).xyz;
}

void fragment() {
	ALBEDO = mix(bird_color, haze_color, haze * 0.7);
	ALBEDO = mix(ALBEDO, wfog_color.rgb, clamp((wfog_dist - wfog_begin) / max(wfog_end - wfog_begin, 0.001), 0.0, 1.0) * wfog_strength);
}
