shader_type sky;
#include "res://shaders/include/cloud_common.gdshaderinc"

// Bontago-adt.1: procedural night sky for config/sky_themes/night.tres --
// deep blue gradient, twinkling stars, a shaded moon with glow, and a
// slowly drifting cel-banded moonlit cloud layer above the horizon. Below
// the horizon the far cloud sea is the sunset panorama's painted cumulus,
// gradient-mapped onto a moonlit ramp (cloud_common moonlit_grade: forms kept,
// warm hue and sun glow gone) and rotated (sky_yaw_offset_deg) so its bright
// horizon sheen sits under the moon; it drifts with the same two-phase flow
// as the sunset sea. Stars, twinkle, clouds and flow are skipped in the
// radiance (reflection) pass, which keeps gradient, moon glow and one static
// sea sample: cheap and free of flicker in the disc's reflections.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform vec3 zenith_color : source_color = vec3(0.008, 0.018, 0.06);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.11, 0.24);
uniform vec3 below_color : source_color = vec3(0.02, 0.035, 0.09);
uniform float horizon_falloff = 0.55;
// Cool fill light added only to the radiance (ambient/reflection) pass so
// blocks and disc keep their colour at night.
uniform vec3 ambient_fill_color : source_color = vec3(0.10, 0.15, 0.32);

// Direction toward the moon (unit vector); keep aligned with the theme's
// directional light so shadows and the moon agree.
uniform vec3 moon_direction = vec3(0.35, 0.36, 0.86);
uniform vec3 moon_color : source_color = vec3(0.86, 0.92, 1.0);
uniform vec3 moon_dark_color : source_color = vec3(0.34, 0.4, 0.55);
uniform vec3 moon_glow_color : source_color = vec3(0.35, 0.5, 0.85);
uniform float moon_angular_radius_deg = 3.2;
uniform float moon_glow_deg = 22.0;
uniform float moon_glow_intensity = 0.55;
uniform float moon_intensity = 2.0;
// Terminator direction in the moon's own disc plane (x right, y up); the
// phase is how much of the disc is lit (1 full, 0 dark).
uniform vec2 moon_phase_direction = vec2(-0.55, 0.35);
uniform float moon_phase = 0.86;
uniform float moon_maria_strength = 0.45;

// Far cloud sea (below the horizon): the painted panorama, graded to moonlight.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float exposure = 0.8;
uniform float seam_blend_width = 0.025;
uniform float sky_yaw_offset_deg = 0.0;
uniform float sky_pitch_offset_deg = 0.0;
uniform float grade_amount = 1.0;
uniform vec3 grade_dark : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 grade_mid : source_color = vec3(0.12, 0.17, 0.33);
uniform vec3 grade_light : source_color = vec3(0.55, 0.64, 0.82);
uniform float grade_gamma = 1.2;
// eyedir.y band over which the sky gradient hands over to the sea.
uniform float sea_blend_top = 0.02;
uniform float sea_blend_bottom = -0.03;
uniform vec2 sea_flow = vec2(-1.0, 0.0);
uniform float sea_flow_span = 0.006;
uniform float sea_flow_period = 16.0;
uniform float sea_flow_jitter_scale = 1.5;
// Bontago-59o.16 (procedural sky P4): procedural cloud sea instead of the
// painted panorama when procedural_sea_mix > 0 (game/Skybox.gd writes it from
// the theme toggle). Same palette-driven function as the sunset sea, with the
// night cloud colours, then moonlit-graded like the panorama sea. proc_sea_*
// colours/fade come from the theme; the rest is set on this material.
uniform float procedural_sea_mix = 0.0;
uniform vec4 proc_sea_color_near : source_color = vec4(0.06, 0.1, 0.22, 1.0);
uniform vec4 proc_sea_color_far : source_color = vec4(0.03, 0.05, 0.12, 1.0);
uniform float proc_sea_horizon_fade = 0.12;
uniform vec4 proc_sea_params = vec4(0.5, 0.9, 0.004, 4.0);
uniform vec2 proc_sea_heights = vec2(1.0, 0.6);
uniform vec2 proc_sea_wind = vec2(1.0, 0.35);
uniform float proc_sea_coverage = 0.5;
uniform float proc_sea_softness = 0.06;
uniform float proc_sea_band_edge = 0.08;

uniform float star_cells_fine = 105.0;
uniform float star_cells_coarse = 46.0;
uniform float star_size = 0.3;
uniform float star_brightness = 4.0;
uniform float star_density = 0.8;
uniform float twinkle_speed = 2.2;
uniform float twinkle_amount = 0.55;
uniform vec3 star_tint_cool : source_color = vec3(0.7, 0.82, 1.0);
uniform vec3 star_tint_warm : source_color = vec3(1.0, 0.9, 0.75);
uniform float star_horizon_fade = 0.22;

uniform float cloud_layer_opacity = 0.9;
uniform float cloud_layer_scale = 1.1;
uniform float cloud_horizon_lift = 0.5;
uniform float cloud_fade_start = 0.2;
uniform float cloud_fade_height = 0.55;
uniform vec2 cloud_wind = vec2(1.0, 0.3);
uniform float cloud_wind_speed = 0.0035;
uniform float cloud_coverage = 0.7;
uniform float cloud_edge_softness = 0.03;
uniform float cloud_warp_amount = 0.12;
uniform float cloud_bands = 4.0;
uniform float cloud_cel_edge = 0.08;
uniform float cloud_light_probe = 0.05;
uniform float cloud_light_contrast = 6.0;
uniform float cloud_rim_width = 0.15;
uniform float cloud_moon_clear_deg = 6.0;
uniform vec3 cloud_shadow_color : source_color = vec3(0.015, 0.025, 0.07);
uniform vec3 cloud_mid_color : source_color = vec3(0.05, 0.08, 0.2);
uniform vec3 cloud_lit_color : source_color = vec3(0.35, 0.47, 0.72);
uniform vec3 cloud_rim_color : source_color = vec3(0.68, 0.8, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	return vec3(hash13(p), hash13(p + 17.1), hash13(p + 41.7));
}

// One layer of point stars: a jittered point per 3D grid cell, most cells
// empty, brightness heavily skewed toward dim.
vec3 star_layer(vec3 dir, float cells, float size_scale) {
	vec3 p = dir * cells;
	vec3 cell = floor(p);
	vec3 local = fract(p);
	vec3 h = hash33(cell);
	float present = step(1.0 - star_density * 0.35, h.x);
	vec3 pos = 0.2 + 0.6 * hash33(cell + 7.3);
	float dist = length(local - pos);
	float radius = star_size * size_scale * (0.4 + h.y * 0.6);
	float core = 1.0 - smoothstep(0.0, radius, dist);
	float brightness = pow(h.z, 3.0) * star_brightness;
	float twinkle = 1.0 - twinkle_amount * (0.5 + 0.5 * sin(TIME * twinkle_speed * (0.6 + h.y) + h.x * 200.0));
	vec3 tint = mix(star_tint_cool, star_tint_warm, h.y);
	return tint * core * core * brightness * twinkle * present;
}

void sky() {
	vec3 eyedir = normalize(EYEDIR);
	vec3 moon_dir = normalize(moon_direction);

	// Gradient: zenith -> horizon -> below.
	float up = clamp(eyedir.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, horizon_falloff));
	col = mix(col, below_color, smoothstep(0.0, -0.35, eyedir.y));

	float cos_moon = dot(eyedir, moon_dir);
	float moon_deg = degrees(acos(clamp(cos_moon, -1.0, 1.0)));

	// Moon glow: soft halo (works in the radiance pass too).
	float glow = exp(-pow(moon_deg / moon_glow_deg, 1.4) * 2.2);
	col += moon_glow_color * glow * moon_glow_intensity;

	if (!AT_CUBEMAP_PASS) {
		// Stars, faded near the horizon and washed out by the moon's glow.
		float star_mask = smoothstep(0.0, star_horizon_fade, eyedir.y) * (1.0 - glow * 0.85);
		if (star_mask > 0.0) {
			vec3 stars = star_layer(eyedir, star_cells_fine, 1.0);
			stars += star_layer(eyedir + vec3(3.7, 1.3, 9.1), star_cells_coarse, 1.5);
			col += stars * star_mask;
		}

		// Moon disc with a phase terminator and dark maria.
		if (moon_deg < moon_angular_radius_deg * 1.15) {
			vec3 arbitrary = abs(moon_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 right = normalize(cross(arbitrary, moon_dir));
			vec3 upv = cross(moon_dir, right);
			float radius_rad = radians(moon_angular_radius_deg);
			vec2 disc = vec2(dot(eyedir, right), dot(eyedir, upv)) / sin(radius_rad);
			float r2 = dot(disc, disc);
			float edge = 1.0 - smoothstep(0.96, 1.0, sqrt(r2));
			if (edge > 0.0) {
				vec3 n = vec3(disc, sqrt(max(1.0 - r2, 0.0)));
				vec3 phase_light = normalize(vec3(moon_phase_direction * (1.0 - moon_phase), 1.0));
				float lit = smoothstep(0.0, 0.25, dot(n, phase_light));
				float maria = texture(noise_tex, disc * 0.18 + 0.5).r;
				float maria_mask = smoothstep(0.45, 0.6, maria) * moon_maria_strength;
				vec3 surface = mix(moon_color, moon_dark_color, maria_mask);
				vec3 moon_col = mix(moon_dark_color * 0.12, surface, lit);
				col = mix(col, moon_col * moon_intensity, edge);
			}
		}

		// Moonlit cel-banded clouds.
		if (eyedir.y > 0.0) {
			vec2 cp = eyedir.xz / (eyedir.y + cloud_horizon_lift) * cloud_layer_scale;
			vec2 drift = cloud_wind * cloud_wind_speed * TIME;
			vec2 cwarp = (vec2(
				texture(noise_tex, cp * 0.5 + drift * 0.6 + vec2(0.3, 0.7)).r,
				texture(noise_tex, cp * 0.5 - drift * 0.4 + vec2(0.9, 0.2)).r) - 0.5) * cloud_warp_amount;
			vec2 cq = cp + drift + cwarp;
			float d = cloud_fbm(noise_tex, cq);
			vec2 to_moon = normalize(moon_dir.xz + vec2(0.0001));
			float d_moon = cloud_fbm(noise_tex, cq + to_moon * cloud_light_probe);
			float body = smoothstep(cloud_coverage, cloud_coverage + cloud_edge_softness, d);
			float height01 = clamp((d - cloud_coverage) / max(1.0 - cloud_coverage, 0.001), 0.0, 1.0);
			float facing = clamp(0.5 + (d - d_moon) * cloud_light_contrast, 0.0, 1.0);
			float moon_side = clamp(cos_moon * 0.5 + 0.5, 0.0, 1.0);
			float shade = clamp(height01 * 0.45 + facing * 0.4 + moon_side * 0.3, 0.0, 1.0);
			float qs = cel_quantize(shade, cloud_bands, cloud_cel_edge);
			vec3 ccol = cel_ramp(cloud_shadow_color, cloud_mid_color, cloud_lit_color, qs);
			float rim = (1.0 - smoothstep(0.0, cloud_rim_width, height01)) * smoothstep(0.55, 0.85, facing);
			ccol = mix(ccol, cloud_rim_color, rim * 0.8);
			float alpha = body * cloud_layer_opacity
				* smoothstep(cloud_fade_start, cloud_fade_height, eyedir.y)
				* smoothstep(moon_angular_radius_deg, moon_angular_radius_deg + cloud_moon_clear_deg, moon_deg);
			col = mix(col, ccol, alpha);
		}
	}
	// Far cloud sea below the horizon.
	float sea = smoothstep(sea_blend_top, sea_blend_bottom, eyedir.y);
	if (sea > 0.0) {
		vec2 puv = sky_panorama_uv(eyedir, sky_yaw_offset_deg, sky_pitch_offset_deg);
		vec3 sea_col;
		if (procedural_sea_mix > 0.0) {
			// Flat palette in the radiance pass (no noise taps there).
			vec3 flat_sea = mix(proc_sea_color_near.rgb, proc_sea_color_far.rgb, smoothstep(0.0, 1.0, -eyedir.y));
			sea_col = flat_sea;
			if (!AT_CUBEMAP_PASS) {
				sea_col = procedural_sea_color(noise_tex, eyedir, normalize(moon_direction), TIME, proc_sea_params,
					proc_sea_heights, proc_sea_wind, proc_sea_coverage, proc_sea_softness, proc_sea_band_edge,
					proc_sea_horizon_fade, proc_sea_color_near.rgb, proc_sea_color_far.rgb, cloud_shadow_color,
					cloud_mid_color, cloud_lit_color, cloud_rim_color, col / max(exposure, 0.001));
			}
			sea_col = mix(panorama_lod(panorama, puv, seam_blend_width), sea_col, clamp(procedural_sea_mix, 0.0, 1.0));
		} else if (AT_CUBEMAP_PASS) {
			sea_col = panorama_lod(panorama, puv, seam_blend_width);
		} else {
			vec2 np = eyedir.xz / (abs(eyedir.y) + 0.35);
			vec3 flow = flow_phases(TIME, sea_flow_period, texture(noise_tex, np * sea_flow_jitter_scale * 0.1).r);
			vec2 uv_a = puv + sea_flow * sea_flow_span * flow.x;
			vec2 uv_b = puv + sea_flow * sea_flow_span * flow.y;
			vec3 col_a = panorama_lod(panorama, vec2(fract(uv_a.x), clamp(uv_a.y, 0.0, 1.0)), seam_blend_width);
			vec3 col_b = panorama_lod(panorama, vec2(fract(uv_b.x), clamp(uv_b.y, 0.0, 1.0)), seam_blend_width);
			sea_col = mix(col_a, col_b, flow.z);
		}
		sea_col = moonlit_grade(sea_col * exposure, grade_amount, grade_dark, grade_mid, grade_light, grade_gamma);
		col = mix(col, sea_col, sea);
	}
	if (AT_CUBEMAP_PASS) {
		col += ambient_fill_color;
	}
	COLOR = col;
}
