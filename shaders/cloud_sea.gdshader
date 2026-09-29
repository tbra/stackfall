shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/include/cloud_common.gdshaderinc"

// One layer of the stylized cumulus sea below the floating disc
// (vfx/CloudSea.gd stacks copies at different heights). Fragment-only and
// driven by TIME, so it drifts and billows in the game, the editor and the
// baked demo with no script. A billow-noise cumulus heightfield is
// lit like a real surface: normals from the height gradient, banded N.L against
// the light, crevice darkening from height, and a rim on sun-facing cloud edges.
// Upper layers are patchy (holes show the layer below); the deepest is solid.
// Distance fade blends colour to the horizon tint and alpha to 0, handing over
// to the sky panorama with no seam.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

// Direction toward the light (sun / moon).
uniform vec3 light_direction = vec3(0.963087, 0.069011, -0.260192);
// Shading light is lifted to at least this elevation so cloud tops are lit
// even for a sun on the horizon.
uniform float min_light_elevation = 0.45;
uniform vec3 shadow_color : source_color = vec3(0.32, 0.25, 0.44);
uniform vec3 mid_color : source_color = vec3(0.82, 0.5, 0.5);
uniform vec3 lit_color : source_color = vec3(1.0, 0.8, 0.5);
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.6);
uniform vec3 horizon_color : source_color = vec3(0.98, 0.64, 0.4);

// World metres per worley tile on the top layer.
uniform float cloud_scale = 700.0;
uniform vec2 wind = vec2(0.6, 0.25);
uniform float wind_speed = 0.004;
uniform float layer_scale_step = 0.3;
uniform float layer_speed_step = 0.25;
uniform float layer_index = 0.0;
uniform float layer_count = 3.0;

// Height above which cloud exists; each deeper layer lowers it (last = 0 = solid).
uniform float coverage = 0.5;
uniform float coverage_layer_step = 0.25;
uniform float edge_softness = 0.05;
uniform float warp_amount = 0.05;
uniform float billow_amount = 0.04;
uniform float billow_speed = 0.25;
uniform float layer_opacity = 1.0;

uniform float cel_bands = 4.0;
uniform float cel_edge = 0.07;
uniform float bump_strength = 0.1;
uniform float gradient_step = 0.012;
uniform float ambient_shade = 0.08;
uniform float crevice_floor = 0.45;
uniform float rim_width = 0.09;

uniform float fade_start_m = 380.0;
uniform float fade_end_m = 950.0;
uniform float horizon_tint = 0.75;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float field(vec2 q, float t) {
	return cumulus_height(noise_tex, q) + sin(t + q.x * 7.0 + q.y * 5.0) * billow_amount;
}

void fragment() {
	float dist = length(world_pos.xz);
	float fade = 1.0 - smoothstep(fade_start_m, fade_end_m, dist);
	if (fade <= 0.0) {
		discard;
	}
	float scale = cloud_scale * (1.0 + layer_scale_step * layer_index);
	float speed = wind_speed * (1.0 + layer_speed_step * (layer_index - 1.0));
	vec2 p = world_pos.xz / scale + vec2(0.173, 0.331) * layer_index;
	vec2 drift = wind * speed * TIME;
	vec2 warp = (vec2(
		texture(noise_tex, p * 0.6 + drift * 0.5 + vec2(0.3, 0.7)).r,
		texture(noise_tex, p * 0.6 - drift * 0.4 + vec2(0.9, 0.2)).r) - 0.5) * warp_amount;
	vec2 q = p + drift + warp;
	float t = TIME * billow_speed + layer_index * 2.0;

	float h = field(q, t);
	float hx = field(q + vec2(gradient_step, 0.0), t);
	float hz = field(q + vec2(0.0, gradient_step), t);

	float cut = max(coverage - coverage_layer_step * layer_index, 0.0);
	float body = layer_index >= layer_count - 1.0 ? 1.0 : smoothstep(cut, cut + edge_softness, h);
	if (body <= 0.002) {
		discard;
	}
	float height_rel = clamp((h - cut) / max(1.0 - cut, 0.001), 0.0, 1.0);

	// Slope along the light: >0 where the surface falls away toward the light
	// (it faces the sun). Small, so it only skews the height-based banding.
	vec2 grad = vec2(hx - h, hz - h) / gradient_step;
	vec2 light_xz = normalize(light_direction.xz + vec2(0.0001));
	float facing = clamp(-dot(grad, light_xz) * bump_strength, -0.5, 0.5);
	float crevice = mix(crevice_floor, 1.0, smoothstep(0.0, 0.55, height_rel));
	float shade = clamp((ambient_shade + height_rel * 0.55 + facing) * crevice + 0.02, 0.0, 1.0);
	float q_shade = cel_quantize(shade, cel_bands, cel_edge);
	vec3 col = cel_ramp(shadow_color, mid_color, lit_color, q_shade);
	float sun_facing = smoothstep(0.0, 0.25, facing);
	float rim = (1.0 - smoothstep(0.0, rim_width, h - cut)) * sun_facing;
	col = mix(col, rim_color, clamp(rim, 0.0, 1.0));
	col = mix(col, horizon_color, smoothstep(fade_start_m * 0.3, fade_end_m, dist) * horizon_tint);

	ALBEDO = col;
	ALPHA = body * fade * layer_opacity;
}
