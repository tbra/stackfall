shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

// Bontago-adt.3: cel shading for the cosmetic perching birds
// (vfx/PerchingBirds.gd). Same recipe as shaders/block_cell_grid.gdshader's
// toon bands: the N.L term is quantised into `band_count` steps and mapped to
// a cool-shadow .. warm-lit multiplier; the engine multiplies by ALBEDO once.
// The per-part colour is an instance uniform so every bird part shares one
// material.

instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int band_count = 3;
uniform vec3 shadow_tint : source_color = vec3(0.6, 0.62, 0.85);
uniform vec3 lit_tint : source_color = vec3(1.0, 0.96, 0.9);
uniform float shadow_brightness = 0.72;
uniform float light_gain = 1.0;

void fragment() {
	ALBEDO = tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float bands = float(max(band_count, 2));
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float step_value = min(floor(ndl * bands) / (bands - 1.0), 1.0);
	vec3 ramp = mix(shadow_tint * shadow_brightness, lit_tint, step_value);
	DIFFUSE_LIGHT += ramp * LIGHT_COLOR * light_gain / PI;
}
