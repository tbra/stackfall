shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, world_vertex_coords;

// Bontago-mp0.19: overhead cel-style cloud ceiling (vfx/weather/CloudCeiling.gd).
// One horizontal plane per layer. Clouds sample the project's seamless cloud
// noise texture (config/sky_themes/cloud_noise.tres) in world XZ: a broad
// coverage field plus round "cumulus heightfield" lobes (cloud_common.gdshaderinc),
// banded into shadow/mid/lit cel colours like shaders/cloud_puffs. Seen from
// below, thick cloud is dark. (The first candidate used a sin-hash value noise:
// its low-frequency lattice produced straight sheared facets.)

#include "res://shaders/include/cloud_common.gdshaderinc"

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float amount = 0.0;
uniform float coverage = 0.6;
uniform float edge_softness = 0.06;
// Cycles of the noise texture per metre.
uniform float noise_scale = 0.0025;
uniform vec2 drift = vec2(0.0);
// 1-2: broad field only (Low); 3+: adds the round cumulus lobes.
uniform int octaves = 4;
uniform float layer_seed = 0.0;
uniform vec3 shadow_color : source_color = vec3(0.17, 0.2, 0.25);
uniform vec3 mid_color : source_color = vec3(0.34, 0.39, 0.45);
uniform vec3 lit_color : source_color = vec3(0.55, 0.6, 0.66);
uniform float darkness = 0.15;
uniform float mid_threshold = 0.45;
uniform float shadow_threshold = 0.72;
uniform float fade_far_start = 350.0;
uniform float fade_far_end = 650.0;
// Fade of rays near the horizon (view elevation, sine) so the far edge never shows.
uniform float horizon_fade = 0.25;
uniform float lobe_mix = 0.45;
uniform float lobe_scale = 1.7;
uniform float band_softness = 0.03;
uniform float full_opacity_amount = 0.25;
uniform float layer_alpha = 1.0;

varying vec3 world_pos;

// Fixed decorrelation offsets between layers / noise fields (pure maths).
const vec2 LOBE_OFFSET = vec2(0.23, 0.61);
const vec2 LAYER_SEED_STEP = vec2(0.37, 0.71);

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2 uv = (world_pos.xz + drift) * noise_scale + layer_seed * LAYER_SEED_STEP;
	float broad = cloud_fbm(cloud_noise, uv);
	float thickness = broad;
	if (octaves >= 3) {
		thickness = mix(broad, cumulus_height(cloud_noise, uv * lobe_scale + LOBE_OFFSET), lobe_mix);
	}
	float cut = 1.0 - coverage * amount;
	float mask = smoothstep(cut, cut + max(edge_softness, 0.001), thickness);
	float body = clamp((thickness - cut) / max(1.0 - cut, 0.001), 0.0, 1.0);
	// Cel bands on how deep into the cloud this pixel is; soft step edges.
	vec3 col = lit_color;
	col = mix(col, mid_color, smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, body));
	col = mix(col, shadow_color, smoothstep(shadow_threshold - band_softness, shadow_threshold + band_softness, body));
	col *= 1.0 - darkness;
	vec3 view = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(view.xz);
	float far_fade = 1.0 - smoothstep(fade_far_start, fade_far_end, dist);
	float elevation = abs(view.y) / max(length(view), 0.001);
	float sky_fade = smoothstep(0.0, max(horizon_fade, 0.001), elevation);
	ALBEDO = col;
	ALPHA = mask * far_fade * sky_fade * layer_alpha * clamp(amount / max(full_opacity_amount, 0.001), 0.0, 1.0);
}
