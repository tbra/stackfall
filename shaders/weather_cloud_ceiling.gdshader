// Bontago-mp0.19 / mp0.29: overhead cel-style cloud ceiling (vfx/weather/CloudCeiling.gd).
// One horizontal plane per layer: the underside of the same clouds as the sea
// and puffs. The body is cloud_cel_layer (cloud_common.gdshaderinc), the very
// code the sea stratum uses: the project's seamless cloud noise in world XZ, a
// one-tap sun probe, cel banding and a rim. Only the thickness term is flipped
// (seen from below the thick middle is the shadowed part). No billow creases:
// they read as marbled veins, not rounded cloud lobes.

#include "res://shaders/include/cloud_common.gdshaderinc"

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float amount = 0.0;
uniform float coverage = 0.6;
uniform float edge_softness = 0.06;
// Cycles of the noise texture per metre.
uniform float noise_scale = 0.005;
uniform vec2 drift = vec2(0.0);
uniform float layer_seed = 0.0;
uniform vec3 shadow_color : source_color = vec3(0.17, 0.2, 0.25);
uniform vec3 mid_color : source_color = vec3(0.34, 0.39, 0.45);
uniform vec3 lit_color : source_color = vec3(0.55, 0.6, 0.66);
uniform vec3 rim_color : source_color = vec3(0.75, 0.78, 0.84);
// Shared CloudLighting inputs: light direction/colour, cycle night mix, scaled
// sun-side lighting strength (scales the lobe light contrast), weather darkening.
uniform vec3 light_direction = vec3(0.963087, 0.069011, -0.260192);
uniform vec3 light_color : source_color = vec3(1.0);
uniform float night_mix = 0.0;
uniform float sun_side_strength = 0.2;
uniform float darkness = 0.15;
uniform float cel_bands = 4.0;
uniform float band_softness = 0.1;
uniform float light_contrast = 6.0;
uniform float sun_probe = 0.04;
uniform float fade_far_start = 350.0;
uniform float fade_far_end = 650.0;
// Elevation (sine) over which the layer fades out toward the horizon; fully
// gone below a third of it, so no flat band meets the sky there.
uniform float horizon_fade = 0.5;
uniform float full_opacity_amount = 0.25;
uniform float layer_alpha = 1.0;

varying vec3 world_pos;

const vec2 LAYER_SEED_STEP = vec2(0.37, 0.71);
const float HORIZON_GONE_SHARE = 0.33;
// sun_side_strength at which light_contrast applies unscaled (tuning default).
const float REFERENCE_SUN_SIDE = 0.22;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2 q = (world_pos.xz + drift) * noise_scale + layer_seed * LAYER_SEED_STEP;
	float cut = 1.0 - coverage * amount;
	vec2 to_sun = normalize(light_direction.xz + vec2(0.0001));
	float contrast = light_contrast * sun_side_strength / REFERENCE_SUN_SIDE;
	vec4 cloud = cloud_cel_layer(cloud_noise, q, to_sun, cut, max(edge_softness, 0.001), cel_bands, band_softness,
		sun_probe, contrast, shadow_color, mid_color, lit_color, rim_color * light_color, false, true);
	vec3 view = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(view.xz);
	float far_fade = 1.0 - smoothstep(fade_far_start, fade_far_end, dist);
	float elevation = abs(view.y) / max(length(view), 0.001);
	float sky_fade = smoothstep(horizon_fade * HORIZON_GONE_SHARE, max(horizon_fade, 0.001), elevation);
	ALBEDO = cloud.rgb * (1.0 - darkness);
	ALPHA = cloud.a * far_fade * sky_fade * layer_alpha * clamp(amount / max(full_opacity_amount, 0.001), 0.0, 1.0);
}
