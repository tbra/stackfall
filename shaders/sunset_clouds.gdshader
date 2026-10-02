shader_type sky;
#include "res://shaders/include/cloud_common.gdshaderinc"

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float seam_blend_width = 0.025;
uniform float pole_blend_width = 0.06;
uniform float exposure = 0.8;
// DECISION (shaders/sunset_clouds.gdshader, Bontago-1pi.1 v2, orchestrator
// review of the v1 candidate): rotates the PANORAMA TEXTURE's own sampling
// UV, not the world-space `sun_direction` below -- v1 fixed the two-sun bug
// by pointing sun_direction (and DirectionalLight3D) at the panorama's own
// painted-sun world direction, but that also spun the default CameraRig view
// away from the sun and dropped the light to a near-horizon grazing angle
// that blew out the goal-zone floor to flat yellow. Rotating the texture
// instead keeps sun_direction/the light exactly as originally tuned and
// moves the painted disc to meet them.
//
// Godot maps EYEDIR to U = atan(x, -z)/TAU (wrapped), V = acos(y)/PI.
// The painted disc centre is (1276, 424) in the 1774x887 panorama; its lower
// edge is hidden by clouds, so use the full circle centre, not the visible
// pixels' centroid. The original flare direction maps to U = 0.208007,
// V = 0.478016. sunset.tres therefore shifts U by 184.058612 degrees, and
// leaves V unchanged: 424/887 already matches the flare's elevation.
// Pitch is a latitude sampling offset, not a rigid spherical rotation;
// clamp at the poles. Zero defaults let other panoramas opt into alignment.
// This same sky() runs for background and radiance, so sky reflections and
// ambient light rotate consistently; DiscMirror shares the Environment sky.
uniform float sky_yaw_offset_deg = 0.0;
uniform float sky_pitch_offset_deg = 0.0;

// Bontago-mp0.3.4 (Graphics pass 2, owner feedback "lens flare from the sun"
// + fix round "move god rays into the sky"): a warm sun glow/halo and
// crepuscular god-ray beams, drawn as part of the sky pass itself -- this
// runs behind every opaque object (the disc, blocks, beacons) for free (a
// sky shader is always the backmost thing drawn) and is naturally picked up
// by ReflectionProbe/SSR the same way the painted panorama already is,
// unlike a screen-space overlay which would have to be manually depth-
// tested against scene geometry. vfx/SunFlare.gd's screen-space CanvasLayer
// keeps only the true lens-artifact elements (a tight starburst sparkle
// directly on the sun disc, and the ghost discs along the sun->center
// axis) -- see that file's own class doc.
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
// Bontago-mp0.13: the cycle uses this same sky pass and uniforms; its
// procedural branch hides the panorama's painted sun before the sun moves.
uniform float cycle_night_mix = 0.0;
uniform vec3 cycle_night_zenith : source_color = vec3(0.008, 0.018, 0.06);
uniform vec3 cycle_night_horizon : source_color = vec3(0.07, 0.11, 0.24);
uniform vec3 cycle_night_below : source_color = vec3(0.02, 0.035, 0.09);
uniform float cycle_star_brightness = 2.0;
uniform float cycle_star_cells = 105.0;
uniform float cycle_star_threshold = 0.92;
uniform float cycle_star_radius = 0.12;
uniform float cycle_star_horizon_fade = 0.22;

float cycle_star_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
uniform vec4 sun_core_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform vec4 sun_halo_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform vec4 sun_ray_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float sun_core_angular_radius_deg = 1.6;
uniform float sun_halo_angular_radius_deg = 9.0;
uniform float sun_halo_softness_deg = 10.0;
// DECISION (shaders/sunset_clouds.gdshader, Bontago-1pi.1, owner playtest:
// "there are 2 suns, one built in to the skybox and another with the lens
// flares" + follow-up "the sun isn't fixed either... the suns are basically
// 180 degrees apart"): assets/sky/sunset-clouds-v1.png already has a painted
// sun disc baked into the panorama, and sky_yaw_offset_deg/
// sky_pitch_offset_deg above now rotate that panorama so the painted disc
// lands exactly at sun_direction (see those uniforms' own DECISION), so this
// shader's own additive core+halo circle would be a second, separately-drawn
// disc sitting on top of the painted one -- not a second sun in a different
// place, but visibly a second bright circle. Zeroing these two defaults
// (rather than deleting the code, or the simpler-still "just leave the halo"
// half-measure) is the simplest change that leaves exactly one visible sun --
// the painted panorama disc, reinforced only by vfx/SunFlare.gd's
// screen-space sparkle (coincident with sun_direction, same as this disc) --
// while a future theme that wants its own procedural disc (a
// painted-texture-free sky, or a different sun position) can still opt back
// in by overriding these two on its own ShaderMaterial, without touching
// this shader file again. ray_* below is untouched: the god-ray beams read
// as atmosphere fanning from the (still painted) sun, not a second disc
// shape, and moving them into this sky pass was itself an earlier owner fix
// round (see this file's class doc) this package does not re-litigate.
uniform float sun_core_intensity = 0.0;
uniform float sun_halo_intensity = 0.0;
// Long, soft god-ray beams fanning out from the sun. Two overlaid ray
// layers (many thin + a few wide) rather than one uniform comb, matching
// "varying widths, many thin + a few wide beams" from the mockup review.
uniform float ray_count = 14.0;
uniform float ray_sharpness = 5.0;
uniform float ray_wide_count = 4.0;
uniform float ray_wide_sharpness = 2.0;
uniform float ray_length_deg = 55.0;
uniform float ray_intensity = 0.35;
// Slow, subtle brightness wobble on the ray layer only -- "slow subtle
// shimmer" from the mockup review; low amplitude so it reads as
// atmospheric drift, not a flicker.
uniform float ray_shimmer_speed = 0.15;
uniform float ray_shimmer_amount = 0.08;
// Bontago-mp0.34: share of the sun glow and god rays that survives weather and
// night (game/Skybox.gd via CloudLighting.sun_effect_scale); 1 = clear daylight.
uniform float sun_effect_scale : hint_range(0.0, 1.0) = 1.0;


// Bontago-adt.1 (graphics pass, animated sky): the painted panorama is kept
// (it carries the mockup-08 look) but now lives.
//  1. SEAM FIX. The old thin dashed vertical line in the upper sky was a
//     mip-selection artifact: fract() on the wrapped U coordinate makes the
//     screen-space UV derivative spike to ~1 on the pixels straddling the
//     wrap, so texture() picked the smallest mip level there and drew a one-
//     pixel line of averaged colour. textureGrad() with derivatives taken from
//     whichever of two half-shifted wraps is continuous removes it.
//  2. DRIFT. Panorama sampling is sheared by latitude with a slow sine, plus a
//     noise-driven UV warp, both faded to zero around the painted sun so it
//     stays glued to sun_direction. Clouds at different heights slide past one
//     another and billow instead of the picture being a static plate.
//  3. CEL CLOUD LAYER. A procedural, cel-banded cloud layer (shared noise
//     texture) scrolls with the wind above the horizon and blends over the
//     panorama, so there is steady visible motion and the mockup's banded
//     cel shading. It fades out near the sun disc and at the horizon.
//  4. FAR CLOUD SEA (Bontago-adt.1 round 3). Below the horizon the painted
//     cumulus is the distant cloud sea: it gets a two-phase flow drift
//     (sea_flow_*) instead of the noise warp, so it slides slowly around the
//     disc without marbling. The near/mid sea is real 3D puffs
//     (vfx/CloudSea.gd, shaders/cloud_puffs.gdshader) that fade into this
//     panorama by sampling it along their own view ray.
// All animated terms are skipped in the radiance (reflection) pass, which
// therefore stays as cheap and stable as before.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float sway_amount = 0.006;
uniform float sway_speed = 0.05;
uniform float sway_latitude_frequency = 3.0;
uniform float warp_amount = 0.006;
uniform float warp_speed = 0.006;
uniform float warp_scale = 2.5;
// Angular radius (degrees) around sun_direction inside which the panorama is
// left un-animated; motion fades in over sun_motion_fade_deg beyond it.
uniform float sun_motion_protect_deg = 6.0;
uniform float sun_motion_fade_deg = 26.0;

// Far cloud sea (the panorama's lower hemisphere): two-phase flow drift so
// the painted cumulus below the horizon slides slowly around the disc with no
// accumulating smear (cloud_common flow_phases). Span is the UV distance one
// phase travels; the jitter noise staggers the cross-fade across the sea.
// sea_flow_fade_start/_end are eyedir.y values: flow is full below _end and
// zero above _start (the horizon band and sky keep only the sway above).
uniform vec2 sea_flow = vec2(-1.0, 0.0);
uniform float sea_flow_span = 0.006;
uniform float sea_flow_period = 16.0;
uniform float sea_flow_jitter_scale = 1.5;
uniform float sea_flow_fade_start = 0.0;
uniform float sea_flow_fade_end = -0.06;

uniform float cloud_layer_opacity = 0.8;
uniform float cloud_layer_scale = 1.1;
uniform float cloud_horizon_lift = 0.5;
uniform float cloud_fade_start = 0.25;
uniform float cloud_fade_height = 0.6;
uniform vec2 cloud_wind = vec2(1.0, 0.35);
uniform float cloud_wind_speed = 0.004;
uniform float cloud_coverage = 0.68;
uniform float cloud_edge_softness = 0.03;
uniform float cloud_warp_amount = 0.12;
uniform float cloud_bands = 4.0;
uniform float cloud_cel_edge = 0.08;
uniform float cloud_light_probe = 0.05;
uniform float cloud_light_contrast = 6.0;
uniform float cloud_rim_width = 0.15;
uniform float cloud_sun_clear_deg = 12.0;
uniform vec3 cloud_shadow_color : source_color = vec3(0.34, 0.27, 0.47);
uniform vec3 cloud_mid_color : source_color = vec3(0.86, 0.55, 0.52);
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.82, 0.52);
uniform vec3 cloud_rim_color : source_color = vec3(1.0, 0.9, 0.66);

// Bontago-59o.16 (procedural sky P1): declarations only; the branch that
// reads them lands in P2-P4. procedural_sea_mix 0 = painted panorama.
uniform float procedural_sea_mix = 0.0;
uniform vec4 proc_zenith_color : source_color = vec4(0.161, 0.2, 0.333, 1.0);
uniform vec4 proc_mid_color : source_color = vec4(0.55, 0.36, 0.5, 1.0);
uniform vec4 proc_horizon_color : source_color = vec4(0.98, 0.64, 0.38, 1.0);
uniform float proc_gradient_mid_height = 0.35;
uniform float proc_gradient_power = 1.5;
uniform vec4 proc_horizon_glow_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform float proc_horizon_glow_width = 0.18;
uniform float proc_sun_glow_strength = 1.0;
uniform vec4 proc_sea_color_near : source_color = vec4(0.85, 0.5, 0.42, 1.0);
uniform vec4 proc_sea_color_far : source_color = vec4(0.34, 0.27, 0.47, 1.0);
uniform float proc_sea_horizon_fade = 0.12;
uniform float proc_strata_scale = 1.0;
// P2 shader-only look tuning (set per theme on the material).
uniform float proc_gradient_bands = 8.0;
uniform float proc_gradient_band_edge = 0.12;
uniform float proc_sun_edge_deg = 0.25;
uniform float proc_sun_halo_bands = 4.0;
uniform float proc_sun_halo_strength = 0.6;
uniform float proc_horizon_glow_strength = 0.45;
uniform float proc_horizon_glow_sun_bias = 3.0;
// P3 shader-only look tuning: far cloud sea (below horizon) and the second
// upper-strata layer. sea_params: x far-stratum scale, y near-stratum scale,
// z drift speed, w cel bands. sea_heights: x far, y near stratum plane height.
uniform vec4 proc_sea_params = vec4(0.5, 0.9, 0.004, 4.0);
uniform vec2 proc_sea_heights = vec2(1.0, 0.6);
uniform vec2 proc_sea_wind = vec2(1.0, 0.35);
uniform float proc_sea_coverage = 0.5;
uniform float proc_sea_softness = 0.06;
uniform float proc_sea_band_edge = 0.08;
uniform float proc_strata_opacity = 0.8;
uniform float proc_strata2_opacity = 0.55;
uniform float proc_strata2_scale = 0.7;
uniform vec2 proc_strata2_stretch = vec2(2.2, 1.0);
uniform vec2 proc_strata2_wind = vec2(-0.6, 0.2);
uniform float proc_strata2_lift = 0.9;
uniform float proc_strata2_coverage = 0.6;
uniform float proc_strata2_bands = 3.0;
uniform float proc_strata2_fade_start = 0.08;
uniform float proc_strata2_fade_height = 0.4;
// Pass 2 (Bontago-59o.19) upper-cloud shape: x warp, y bank-mask weight, z sun probe, w light contrast.
uniform vec4 proc_upper_shape = vec4(0.15, 0.3, 0.04, 6.0);
uniform float proc_upper_rot2 = 0.6;
// Bontago-59o.20: authored cloud-card layers replace the noise overhead layers
// when proc_cards_mix > 0. proc_cards_layout*: x plane scale, y horizon lift,
// z density, w card half-size in cells. proc_cards_light: x openness floor,
// y skylight up-bias, z rim power, w rim strength. proc_cards_wind: layer 1 xy, layer 2 zw.
uniform sampler2D cloud_cards : filter_linear_mipmap, repeat_disable;
// Bontago-t8x.2: master switch for both procedural overhead layers (cards and noise strata).
uniform float proc_overhead_mix = 1.0;
uniform float proc_cards_mix = 0.0;
uniform float proc_cards_opacity = 0.95;
uniform vec4 proc_cards_layout = vec4(1.5, 0.35, 0.85, 0.9);
uniform vec4 proc_cards_layout2 = vec4(2.6, 0.6, 0.7, 0.8);
uniform vec4 proc_cards_light = vec4(0.3, 0.35, 2.0, 2.5);
uniform vec4 proc_cards_wind = vec4(0.004, 0.0015, -0.003, 0.001);
uniform float proc_cards_bands = 4.0;
uniform float proc_cards_contrast = 1.8;
uniform float proc_cards_fade_start = 0.03;
uniform float proc_cards_fade_height = 0.25;
// Plane-coordinate multipliers for the two upper layers (higher = smaller cumulus).
uniform float proc_upper_coverage_shift = 0.1;
uniform vec2 proc_upper_scale = vec2(3.6, 2.6);

// Panorama colour with the symmetric seam blend (imperfect authored
// panorama edges made continuous).
vec3 sample_panorama(vec2 uv, vec2 ddx_uv, vec2 ddy_uv) {
	vec3 color = textureGrad(panorama, uv, ddx_uv, ddy_uv).rgb;
	float seam = 1.0 - smoothstep(0.0, seam_blend_width, min(uv.x, 1.0 - uv.x));
	vec2 mirrored_ddx = vec2(-ddx_uv.x, ddx_uv.y);
	vec2 mirrored_ddy = vec2(-ddy_uv.x, ddy_uv.y);
	return mix(color, textureGrad(panorama, vec2(1.0 - uv.x, uv.y), mirrored_ddx, mirrored_ddy).rgb, seam * 0.5);
}

void sky() {
	vec3 eyedir = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);
	float cos_angle = dot(eyedir, sun_dir);
	float angle_deg = degrees(acos(clamp(cos_angle, -1.0, 1.0)));

	vec2 uv = SKY_COORDS;
	// Rotate the panorama sampling coordinate itself -- see sky_yaw_offset_deg/
	// sky_pitch_offset_deg's own DECISION above. fract() wraps U around the
	// seam regardless of sign; V is clamped rather than wrapped since it must
	// never sample past a pole (unlike U, which repeats around the horizon).
	float u_raw = uv.x + sky_yaw_offset_deg / 360.0;
	uv.x = fract(u_raw);
	uv.y = clamp(uv.y + sky_pitch_offset_deg / 180.0, 0.0, 1.0);

	// Seam-safe derivatives: pick the continuous one of two half-shifted wraps.
	float u_alt = fract(u_raw + 0.5) - 0.5;
	vec2 grad_a = vec2(dFdx(uv.x), dFdy(uv.x));
	vec2 grad_b = vec2(dFdx(u_alt), dFdy(u_alt));
	bool a_ok = abs(grad_a.x) + abs(grad_a.y) <= abs(grad_b.x) + abs(grad_b.y);
	vec2 grad_u = a_ok ? grad_a : grad_b;
	vec2 ddx_uv = vec2(grad_u.x, dFdx(uv.y));
	vec2 ddy_uv = vec2(grad_u.y, dFdy(uv.y));

	// Animated distortion (background pass only), faded out around the sun.
	vec3 flow = vec3(0.0);
	float sea = 0.0;
	if (!AT_CUBEMAP_PASS) {
		float motion = smoothstep(sun_motion_protect_deg, sun_motion_protect_deg + sun_motion_fade_deg, angle_deg);
		vec2 np = eyedir.xz / (abs(eyedir.y) + 0.35) * warp_scale;
		vec2 wobble = vec2(
			texture(noise_tex, np + vec2(TIME * warp_speed, 0.0)).r,
			texture(noise_tex, np + vec2(0.0, -TIME * warp_speed) + vec2(0.5, 0.5)).r) - 0.5;
		float sway = sin(TIME * sway_speed + uv.y * sway_latitude_frequency * TAU + wobble.x * 4.0);
		vec2 shift = vec2(sway * sway_amount, 0.0) + wobble * warp_amount;
		// The far cloud sea below the horizon gets the flow drift instead of
		// the noise warp (warping the painted cumulus there marbles it).
		float sea_zone = smoothstep(sea_flow_fade_start, sea_flow_fade_end, eyedir.y);
		uv += shift * motion * (1.0 - sea_zone);
		uv.y = clamp(uv.y, 0.0, 1.0);
		sea = sea_zone * motion;
		if (sea > 0.0) {
			float jitter = texture(noise_tex, np * sea_flow_jitter_scale * 0.1).r;
			flow = flow_phases(TIME, sea_flow_period, jitter);
		}
	}

	vec3 color;
	if (sea <= 0.0) {
		color = sample_panorama(uv, ddx_uv, ddy_uv);
	} else {
		vec2 step_a = sea_flow * sea_flow_span * flow.x * sea;
		vec2 step_b = sea_flow * sea_flow_span * flow.y * sea;
		vec3 color_a = sample_panorama(vec2(fract(uv.x + step_a.x), clamp(uv.y + step_a.y, 0.0, 1.0)), ddx_uv, ddy_uv);
		vec3 color_b = sample_panorama(vec2(fract(uv.x + step_b.x), clamp(uv.y + step_b.y, 0.0, 1.0)), ddx_uv, ddy_uv);
		color = mix(color_a, color_b, flow.z);
	}
	// Longitude converges to one color at each pole, avoiding a pinwheel seam.
	float pole = 1.0 - smoothstep(0.0, pole_blend_width, min(uv.y, 1.0 - uv.y));
	vec3 pole_color = textureLod(panorama, vec2(0.5, uv.y < 0.5 ? 0.0 : 1.0), 0.0).rgb;
	COLOR = mix(color, pole_color, pole) * exposure;

	// Procedural gradient sky (Bontago-59o.16 P2): replaces the panorama,
	// including its painted sun (so there is no second disc), by
	// procedural_sea_mix. No noise taps, so it is valid in the radiance pass.
	if (procedural_sea_mix > 0.0) {
		vec3 pcol = sky_gradient(eyedir.y, proc_horizon_color.rgb, proc_mid_color.rgb, proc_zenith_color.rgb,
			proc_gradient_mid_height, proc_gradient_power, proc_gradient_bands, proc_gradient_band_edge);
		if (eyedir.y < 0.0) {
			float below = smoothstep(0.0, max(proc_sea_horizon_fade, 0.001), -eyedir.y);
			pcol = mix(pcol, proc_sea_color_near.rgb, below);
			pcol = mix(pcol, proc_sea_color_far.rgb, smoothstep(0.0, 1.0, -eyedir.y) * below);
			// Background pass only: the layered cel cloud sea (noise taps). The
			// radiance pass keeps the flat placeholder above.
			if (!AT_CUBEMAP_PASS) {
				pcol = procedural_sea_color(noise_tex, eyedir, sun_dir, TIME, proc_sea_params, proc_sea_heights,
					proc_sea_wind, proc_sea_coverage, proc_sea_softness, proc_sea_band_edge, proc_sea_horizon_fade,
					proc_sea_color_near.rgb, proc_sea_color_far.rgb, cloud_shadow_color, cloud_mid_color,
					cloud_lit_color, cloud_rim_color, pcol);
			}
		}
		float sun_side = pow(max(cos_angle, 0.0), max(proc_horizon_glow_sun_bias, 0.001));
		float glow = (1.0 - smoothstep(0.0, max(proc_horizon_glow_width, 0.001), abs(eyedir.y)))
			* mix(0.35, 1.0, sun_side) * proc_horizon_glow_strength;
		pcol = mix(pcol, proc_horizon_glow_color.rgb, clamp(glow, 0.0, 1.0));
		vec2 sd = sun_disc(cos_angle, sun_core_angular_radius_deg, proc_sun_edge_deg,
			sun_halo_angular_radius_deg + sun_halo_softness_deg, proc_sun_halo_bands, cloud_cel_edge);
		pcol += sun_halo_color.rgb * sd.y * proc_sun_halo_strength * proc_sun_glow_strength;
		pcol = mix(pcol, sun_core_color.rgb, sd.x * clamp(proc_sun_glow_strength, 0.0, 1.0));
		COLOR = mix(COLOR, pcol * exposure, clamp(procedural_sea_mix, 0.0, 1.0));
	}

	// Cel-banded procedural cloud layer over the panorama (background pass only).
	if (!AT_CUBEMAP_PASS && eyedir.y > 0.0 && procedural_sea_mix <= 0.0) {
		vec2 cp = eyedir.xz / (eyedir.y + cloud_horizon_lift) * cloud_layer_scale * mix(1.0, proc_strata_scale, clamp(procedural_sea_mix, 0.0, 1.0));
		vec2 drift = cloud_wind * cloud_wind_speed * TIME;
		vec2 cwarp = (vec2(
			texture(noise_tex, cp * 0.5 + drift * 0.6 + vec2(0.3, 0.7)).r,
			texture(noise_tex, cp * 0.5 - drift * 0.4 + vec2(0.9, 0.2)).r) - 0.5) * cloud_warp_amount;
		vec2 cq = cp + drift + cwarp;
		float d = cloud_fbm(noise_tex, cq);
		vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001));
		float d_sun = cloud_fbm(noise_tex, cq + to_sun * cloud_light_probe);
		float body = smoothstep(cloud_coverage, cloud_coverage + cloud_edge_softness, d);
		float height01 = clamp((d - cloud_coverage) / max(1.0 - cloud_coverage, 0.001), 0.0, 1.0);
		float facing = clamp(0.5 + (d - d_sun) * cloud_light_contrast, 0.0, 1.0);
		// Clouds nearer the sun are lit more from behind: warm them up.
		float sun_side = clamp(cos_angle * 0.5 + 0.5, 0.0, 1.0);
		float shade = clamp(height01 * 0.5 + facing * 0.4 + sun_side * 0.25, 0.0, 1.0);
		float qs = cel_quantize(shade, cloud_bands, cloud_cel_edge);
		vec3 ccol = cel_ramp(cloud_shadow_color, cloud_mid_color, cloud_lit_color, qs);
		float rim = (1.0 - smoothstep(0.0, cloud_rim_width, height01)) * smoothstep(0.55, 0.85, facing);
		ccol = mix(ccol, cloud_rim_color, rim * 0.8);
		float alpha = body * mix(cloud_layer_opacity, max(cloud_layer_opacity, proc_strata_opacity), clamp(procedural_sea_mix, 0.0, 1.0))
			* smoothstep(cloud_fade_start, cloud_fade_height, eyedir.y)
			* smoothstep(sun_core_angular_radius_deg, cloud_sun_clear_deg, angle_deg);
		COLOR = mix(COLOR, ccol, alpha);
	}

	// Procedural upper clouds (Bontago-59o.19): two isotropic broken-cumulus
	// layers on rotated high planes (see cloud_common procedural_upper_clouds),
	// background pass only.
	if (!AT_CUBEMAP_PASS && eyedir.y > 0.0 && procedural_sea_mix > 0.0 && proc_cards_mix > 0.0 && proc_overhead_mix > 0.0) {
		float cmix = clamp(procedural_sea_mix, 0.0, 1.0) * clamp(proc_cards_mix, 0.0, 1.0);
		float csun = smoothstep(sun_core_angular_radius_deg, cloud_sun_clear_deg * 0.5, angle_deg);
		float cfade = smoothstep(proc_cards_fade_start, proc_cards_fade_height, eyedir.y) * csun * proc_cards_opacity * cmix;
		vec4 k2 = sky_cloud_cards(cloud_cards, eyedir, sun_dir, TIME, proc_cards_layout2, 17.0, proc_cards_wind.zw,
			proc_cards_bands, cloud_cel_edge, proc_cards_light, proc_cards_contrast, cloud_shadow_color, cloud_mid_color, cloud_lit_color, cloud_rim_color);
		COLOR = mix(COLOR, k2.rgb * exposure, k2.a * cfade);
		vec4 k1 = sky_cloud_cards(cloud_cards, eyedir, sun_dir, TIME, proc_cards_layout, 0.0, proc_cards_wind.xy,
			proc_cards_bands, cloud_cel_edge, proc_cards_light, proc_cards_contrast, cloud_shadow_color, cloud_mid_color, cloud_lit_color, cloud_rim_color);
		COLOR = mix(COLOR, k1.rgb * exposure, k1.a * cfade);
	}
	if (!AT_CUBEMAP_PASS && eyedir.y > 0.0 && procedural_sea_mix > 0.0 && proc_cards_mix <= 0.0 && proc_overhead_mix > 0.0) {
		vec2 to_sun_xz = normalize(sun_dir.xz + vec2(0.0001));
		float sun_clear = smoothstep(sun_core_angular_radius_deg, cloud_sun_clear_deg, angle_deg);
		float mixv = clamp(procedural_sea_mix, 0.0, 1.0);
		vec4 u1 = procedural_upper_clouds(noise_tex, eyedir, to_sun_xz, TIME, cloud_layer_scale * proc_strata_scale * proc_upper_scale.x,
			cloud_horizon_lift, 0.0, cloud_wind, cloud_wind_speed, cloud_coverage - proc_upper_coverage_shift, cloud_edge_softness, cloud_bands,
			cloud_cel_edge, proc_upper_shape, cloud_shadow_color, cloud_mid_color, cloud_lit_color, cloud_rim_color);
		COLOR = mix(COLOR, u1.rgb * exposure, u1.a * proc_strata_opacity * mixv
			* smoothstep(cloud_fade_start, cloud_fade_height, eyedir.y) * sun_clear);
		vec4 u2 = procedural_upper_clouds(noise_tex, eyedir, to_sun_xz, TIME, proc_strata2_scale * proc_upper_scale.y, proc_strata2_lift,
			proc_upper_rot2, proc_strata2_wind, cloud_wind_speed * 1.8, proc_strata2_coverage - proc_upper_coverage_shift * 0.5, cloud_edge_softness,
			proc_strata2_bands, cloud_cel_edge, proc_upper_shape, cloud_shadow_color, cloud_mid_color, cloud_lit_color,
			cloud_rim_color);
		COLOR = mix(COLOR, u2.rgb * exposure, u2.a * proc_strata2_opacity * mixv
			* smoothstep(proc_strata2_fade_start, proc_strata2_fade_height, eyedir.y) * sun_clear);
	}
	if (cycle_night_mix > 0.0) {
		vec3 night = mix(cycle_night_horizon, cycle_night_zenith, pow(max(eyedir.y, 0.0), 0.55));
		night = mix(night, cycle_night_below, smoothstep(0.0, 0.35, -eyedir.y));
		if (!AT_CUBEMAP_PASS && eyedir.y > 0.0) {
			vec3 cell = floor(eyedir * cycle_star_cells);
			vec3 local = fract(eyedir * cycle_star_cells) - 0.5;
			float present = step(cycle_star_threshold, cycle_star_hash(cell));
			float point = 1.0 - smoothstep(cycle_star_radius * 0.17, cycle_star_radius, length(local));
			night += vec3(0.72, 0.82, 1.0) * present * point * cycle_star_brightness
				* smoothstep(0.0, cycle_star_horizon_fade, eyedir.y);
		}
		COLOR = mix(COLOR, night * exposure, clamp(cycle_night_mix, 0.0, 1.0));
	}

	// Bright core + soft halo, both angular falloffs around the sun direction.
	float core = 1.0 - smoothstep(0.0, sun_core_angular_radius_deg, angle_deg);
	float halo = 1.0 - smoothstep(sun_halo_angular_radius_deg - sun_halo_softness_deg, sun_halo_angular_radius_deg, angle_deg);
	halo = clamp(halo, 0.0, 1.0);
	COLOR += sun_core_color.rgb * core * sun_core_intensity * sun_effect_scale;
	COLOR += sun_halo_color.rgb * halo * sun_halo_intensity * sun_effect_scale;

	// God rays: an angular position around the sun axis (tangent/bitangent
	// basis), two overlaid ray-comb frequencies, faded out by angular
	// distance from the sun so they never reach all the way across the sky.
	vec3 arbitrary = abs(sun_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(arbitrary, sun_dir));
	vec3 bitangent = cross(sun_dir, tangent);
	vec3 offset = eyedir - sun_dir * cos_angle;
	float ray_angle = atan(dot(offset, bitangent), dot(offset, tangent));
	float ray_fade = 1.0 - smoothstep(0.0, ray_length_deg, angle_deg);
	if (ray_fade > 0.0) {
		float shimmer = 1.0 + sin(TIME * ray_shimmer_speed + ray_angle * 3.0) * ray_shimmer_amount;
		float rays_thin = pow(abs(cos(ray_angle * ray_count * 0.5)), ray_sharpness);
		float rays_wide = pow(abs(cos(ray_angle * ray_wide_count * 0.5)), ray_wide_sharpness);
		float rays = (rays_thin * 0.65 + rays_wide * 0.35) * ray_fade * ray_intensity * shimmer * (1.0 - cycle_night_mix) * sun_effect_scale;
		COLOR += sun_ray_color.rgb * rays;
	}
}
