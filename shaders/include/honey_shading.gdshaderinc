// Shared cel-glossy honey shading for the blob looks (Bontago-lv2): banded diffuse,
// a hard specular highlight, deep-amber toward grazing angles and a rim glow standing in
// for light passing through the blob. Included by honey_jelly/honey_beads.
uniform vec4 honey_color : source_color = vec4(1.0, 0.7, 0.04, 1.0);
uniform vec3 deep_amber : source_color = vec3(0.85, 0.42, 0.0);
uniform float rim_power = 3.5;
uniform float rim_strength = 0.5;
uniform float glow_floor = 0.12;
uniform int band_count = 3;
uniform float gloss_threshold = 0.96;
uniform float gloss_strength = 1.0;
uniform vec3 gloss_color : source_color = vec3(1.0, 0.96, 0.75);

// Albedo and emission from the view-facing term (0 = grazing, 1 = facing the camera).
void honey_surface(float facing, out vec3 albedo, out vec3 emission) {
	float edge = pow(1.0 - clamp(facing, 0.0, 1.0), rim_power);
	albedo = mix(honey_color.rgb, deep_amber, clamp(0.35 * (1.0 - edge) + edge * 0.5, 0.0, 1.0));
	emission = honey_color.rgb * (glow_floor + edge * rim_strength);
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float bands = max(float(band_count), 1.0);
	float banded = ceil(nl * bands) / bands;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * banded / PI;
	float nh = clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0);
	SPECULAR_LIGHT += gloss_color * LIGHT_COLOR * ATTENUATION * gloss_strength * step(gloss_threshold, nh) * step(0.001, nl) / PI;
}
