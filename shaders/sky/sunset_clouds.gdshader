shader_type sky;
#include "res://shaders/include/cloud_common.gdshaderinc"

// G1: the sky must NOT read the built-in TIME. Any TIME use makes
// the engine re-render the whole radiance octmap + filter every frame (sky.cpp:1033,
// uses_time), and so does every material uniform write (sky.cpp:1044). `sky_time` is a
// GLOBAL uniform (project.godot [shader_globals]): game/sky/Skybox.gd writes it each frame
// into the shared global buffer, which neither flag sees, so the visible background
// animates smoothly while the radiance only re-renders at SkyRadianceConfig.radiance_hz
// (the cycle's palette/sun writes).
global uniform float sky_time;
// per-frame disc directions (game/sky/Skybox.gd); a global write does not dirty
// the material, so the discs move smoothly while the material (light, palette) steps.
global uniform vec3 sky_sun_dir;
global uniform vec3 sky_moon_dir;
uniform float use_global_dirs = 0.0;


uniform float exposure = 0.8;

// A warm sun glow/halo and crepuscular god-ray beams, drawn as part of the sky
// pass itself: this runs behind every opaque object (the disc, blocks, beacons)
// for free and is picked up by ReflectionProbe/SSR, unlike a screen-space
// overlay that would have to be depth-tested against scene geometry.
// game/sky/SunFlare.gd's screen-space CanvasLayer keeps only the lens-artifact
// elements (a tight starburst sparkle on the sun disc and the ghost discs along
// the sun->center axis).
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
// The cycle uses this same sky pass and uniforms.
uniform float cycle_night_mix = 0.0;
uniform vec3 cycle_night_zenith : source_color = vec3(0.008, 0.018, 0.06);
uniform vec3 cycle_night_horizon : source_color = vec3(0.07, 0.11, 0.24);
uniform vec3 cycle_night_below : source_color = vec3(0.02, 0.035, 0.09);
uniform float cycle_star_brightness = 2.0;
uniform float cycle_star_cells = 105.0;
uniform float cycle_star_threshold = 0.92;
uniform float cycle_star_radius = 0.12;
uniform float cycle_star_horizon_fade = 0.22;
// Moon disc + halo textures (assets/textures/sky/moon), drawn at
// night opposite the sun. moon_visibility is 0..1 (time of day x weather keep, set by
// game/sky/Skybox.gd); the angular sizes and strengths come from SkyCycleDef.cycle_moon_*.
uniform sampler2D moon_disc_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D moon_halo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 moon_direction = vec3(-0.963087, -0.069011, 0.260192);
uniform float moon_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float moon_angular_radius_deg = 3.2;
uniform float moon_halo_radius_deg = 14.0;
uniform float moon_halo_strength = 0.6;
uniform float moon_brightness = 1.0;
// Visible disc / halo radius as a fraction of the half texture quad (400/512 and 480/512).
uniform float moon_disc_fill = 0.78125;
uniform float moon_halo_fill = 0.9375;
// aurora borealis curtains (cloud_common aurora_borealis) behind the moon
// at night. aurora_visibility is 0..1 (night x weather keep x graphics preset, set by
// game/sky/Skybox.gd, so it is exactly 0 by day, in a storm and on Low); the rest come from
// SkyCycleDef.aurora_*.
uniform float aurora_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float aurora_intensity = 0.45;
uniform vec3 aurora_color_low : source_color = vec3(0.12, 1.0, 0.42);
uniform vec3 aurora_color_mid : source_color = vec3(0.08, 0.75, 0.8);
uniform vec3 aurora_color_top : source_color = vec3(0.55, 0.3, 0.95);
uniform float aurora_speed = 1.0;
uniform float aurora_base_height = 0.1;
uniform float aurora_curtain_height = 0.4;

// Samples a moon texture laid on the tangent plane at `plane` (tan-space coords).
vec4 moon_layer(sampler2D tex, vec2 plane, float visible_angle_deg, float fill) {
	float half_quad = tan(radians(visible_angle_deg)) / fill;
	vec2 uv = vec2(plane.x, -plane.y) / (2.0 * half_quad) + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return textureLod(tex, uv, 0.0);
}

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
// The sky shows a single sun (SunFlare adds only a screen-space sparkle at sun_direction), so
// there is no additive procedural core/halo term; the ray_* god-ray beams below stay on.
// Long, soft god-ray beams fanning out from the sun. Two overlaid ray
// layers (many thin + a few wide) rather than one uniform comb.
uniform float ray_count = 14.0;
uniform float ray_sharpness = 5.0;
uniform float ray_wide_count = 4.0;
uniform float ray_wide_sharpness = 2.0;
uniform float ray_length_deg = 55.0;
uniform float ray_intensity = 0.35;
// Slow, subtle brightness wobble on the ray layer only; low amplitude so it
// reads as atmospheric drift, not a flicker.
uniform float ray_shimmer_speed = 0.15;
uniform float ray_shimmer_amount = 0.08;
// share of the sun glow and god rays that survives weather and
// night (game/sky/Skybox.gd via CloudLighting.sun_effect_scale); 1 = clear daylight.
// EVERY additive sun term below (god rays) multiplies it, and
// it is exactly 0 at full storm where the procedural sun glow is also 0, so the rays can
// never outlive a hidden sun. A new sun term must multiply it too.
uniform float sun_effect_scale : hint_range(0.0, 1.0) = 1.0;


// The cycle runs the procedural branch below. The shared
// noise texture drives the procedural cloud layers. All animated terms are skipped
// in the radiance (reflection) pass.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float cloud_cel_edge = 0.08;
uniform vec3 cloud_shadow_color : source_color = vec3(0.34, 0.27, 0.47);
uniform vec3 cloud_mid_color : source_color = vec3(0.86, 0.55, 0.52);
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.82, 0.52);
uniform vec3 cloud_rim_color : source_color = vec3(1.0, 0.9, 0.66);

uniform float procedural_sea_mix = 1.0;
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
// Shader-only look tuning (set per sky on the material).
uniform float proc_gradient_bands = 8.0;
uniform float proc_gradient_band_edge = 0.12;
uniform float proc_sun_edge_deg = 0.25;
uniform float proc_sun_halo_bands = 4.0;
uniform float proc_sun_halo_strength = 0.6;
uniform float proc_horizon_glow_strength = 0.45;
uniform float proc_horizon_glow_sun_bias = 3.0;
// Shader-only look tuning: far cloud sea (below horizon). sea_params: x far-stratum scale, y near-stratum scale,
// z drift speed, w cel bands. sea_heights: x far, y near stratum plane height.
uniform vec4 proc_sea_params = vec4(0.5, 0.9, 0.004, 4.0);
uniform vec2 proc_sea_heights = vec2(1.0, 0.6);
uniform vec2 proc_sea_wind = vec2(1.0, 0.35);
uniform float proc_sea_coverage = 0.5;
uniform float proc_sea_softness = 0.06;
uniform float proc_sea_band_edge = 0.08;

void sky() {
	vec3 eyedir = normalize(EYEDIR);
	vec3 sun_dir = normalize(use_global_dirs > 0.5 ? sky_sun_dir : sun_direction);
	float cos_angle = dot(eyedir, sun_dir);
	float angle_deg = degrees(acos(clamp(cos_angle, -1.0, 1.0)));

	// DECISION: COLOR starts black; the procedural gradient below fills it
	// whenever procedural_sea_mix > 0 (default 1, every cycle sets 1).
	COLOR = vec3(0.0);

	// Procedural gradient sky, blended by procedural_sea_mix.
	// The radiance pass takes no noise taps here, so it is cheap and stable.
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
				pcol = procedural_sea_color(noise_tex, eyedir, sun_dir, sky_time, proc_sea_params, proc_sea_heights,
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
	// Aurora over the night sky, behind the moon below and (like the stars) background pass only.
	if (aurora_visibility > 0.0 && aurora_intensity > 0.0 && !AT_CUBEMAP_PASS && eyedir.y > 0.0) {
		COLOR += aurora_borealis(noise_tex, eyedir, sky_time, aurora_base_height, aurora_curtain_height, aurora_speed,
			aurora_color_low, aurora_color_mid, aurora_color_top) * aurora_intensity * aurora_visibility * exposure;
	}
	if (moon_visibility > 0.0 && !AT_CUBEMAP_PASS) {
		vec3 moon_dir = normalize(use_global_dirs > 0.5 ? sky_moon_dir : moon_direction);
		float moon_cos = dot(eyedir, moon_dir);
		if (moon_cos > 0.05) {
			vec3 moon_ref = abs(moon_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 moon_right = normalize(cross(moon_ref, moon_dir));
			vec3 moon_up = cross(moon_dir, moon_right);
			vec2 plane = vec2(dot(eyedir, moon_right), dot(eyedir, moon_up)) / moon_cos;
			vec4 halo_px = moon_layer(moon_halo_tex, plane, moon_halo_radius_deg, moon_halo_fill);
			COLOR += halo_px.rgb * halo_px.a * moon_halo_strength * moon_visibility * exposure;
			vec4 disc_px = moon_layer(moon_disc_tex, plane, moon_angular_radius_deg, moon_disc_fill);
			COLOR = mix(COLOR, disc_px.rgb * moon_brightness * exposure, disc_px.a * moon_visibility);
		}
	}


	// God rays: an angular position around the sun axis (tangent/bitangent
	// basis), two overlaid ray-comb frequencies, faded out by angular
	// distance from the sun so they never reach all the way across the sky.
	vec3 arbitrary = abs(sun_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(arbitrary, sun_dir));
	vec3 bitangent = cross(sun_dir, tangent);
	vec3 offset = eyedir - sun_dir * cos_angle;
	float ray_angle = atan(dot(offset, bitangent), dot(offset, tangent));
	float ray_fade = 1.0 - smoothstep(0.0, ray_length_deg, angle_deg);
	if (ray_fade > 0.0 && sun_effect_scale > 0.0) {
		float shimmer = 1.0 + sin(sky_time * ray_shimmer_speed + ray_angle * 3.0) * ray_shimmer_amount;
		float rays_thin = pow(abs(cos(ray_angle * ray_count * 0.5)), ray_sharpness);
		float rays_wide = pow(abs(cos(ray_angle * ray_wide_count * 0.5)), ray_wide_sharpness);
		float rays = (rays_thin * 0.65 + rays_wide * 0.35) * ray_fade * ray_intensity * shimmer * (1.0 - cycle_night_mix) * sun_effect_scale;
		COLOR += sun_ray_color.rgb * rays;
	}
}
