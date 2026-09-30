shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-adt.1: distant bird flocks, animated entirely here so they move in
// the game, the editor and the static baked demo (vfx/DistantBirds.gd builds
// the MultiMesh; there is no per-frame script).
//
// Per-instance data:
//   MODEL_MATRIX origin      = orbit centre (flock position, metres)
//   MODEL_MATRIX basis scale = bird size (uniform)
//   INSTANCE_CUSTOM.x        = orbit radius (m)
//   INSTANCE_CUSTOM.y        = flock orbit phase (rad), shared by a flock
//   INSTANCE_CUSTOM.z        = angular speed (rad/s), sign = direction
//   INSTANCE_CUSTOM.w        = per-bird random seed 0..1
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
uniform vec3 bird_color : source_color = vec3(0.16, 0.1, 0.2);
uniform vec3 haze_color : source_color = vec3(0.85, 0.5, 0.42);
uniform float haze_start_m = 250.0;
uniform float haze_end_m = 700.0;
uniform float flap_speed = 7.0;
uniform float flap_amount = 0.55;
uniform float bank_amount = 0.35;
uniform float formation_spread = 0.22;
uniform float radius_spread = 0.12;
uniform float height_spread_m = 9.0;
uniform float bob_amount_m = 3.0;

varying float haze;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.w;
	float dir_sign = INSTANCE_CUSTOM.z >= 0.0 ? 1.0 : -1.0;
	float angle = INSTANCE_CUSTOM.y + TIME * INSTANCE_CUSTOM.z + (hash11(seed) - 0.5) * formation_spread;
	float radius = INSTANCE_CUSTOM.x * (1.0 + (hash11(seed + 3.0) - 0.5) * radius_spread);
	vec2 radial = vec2(cos(angle), sin(angle));
	vec3 orbit = vec3(radial.x * radius,
		(hash11(seed + 7.0) - 0.5) * height_spread_m + sin(angle * 1.7 + seed * 20.0) * bob_amount_m,
		radial.y * radius);

	vec3 forward = normalize(vec3(-radial.y * dir_sign, 0.0, radial.x * dir_sign));
	vec3 inward = -vec3(radial.x, 0.0, radial.y);
	vec3 up = normalize(vec3(0.0, 1.0, 0.0) + inward * bank_amount);
	vec3 side = normalize(cross(forward, up));
	up = cross(side, forward);

	float size = length(MODEL_MATRIX[0].xyz);
	float flap_phase = TIME * flap_speed * (0.85 + hash11(seed + 11.0) * 0.3) + seed * 40.0;
	vec3 local = VERTEX;
	local.y += sin(flap_phase) * UV.x * flap_amount;
	local.x -= abs(sin(flap_phase)) * UV.x * flap_amount * 0.3;

	vec3 world = MODEL_MATRIX[3].xyz + orbit + (forward * local.x + up * local.y + side * local.z) * size;
	haze = smoothstep(haze_start_m, haze_end_m, length(world.xz));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	wfog_dist = length(VERTEX);
	NORMAL = (VIEW_MATRIX * vec4(up, 0.0)).xyz;
}

void fragment() {
	ALBEDO = mix(bird_color, haze_color, haze * 0.7);
	ALBEDO = mix(ALBEDO, wfog_color.rgb, clamp((wfog_dist - wfog_begin) / max(wfog_end - wfog_begin, 0.001), 0.0, 1.0) * wfog_strength);
}
