shader_type spatial;
// Bontago-mp0.3.1 (Graphics pass 2, owner feedback on docs/art_mockups/
// 08-cel-shaded-home-beacons.png: "Same for the beacons" -- the beacons need
// the same cel-shading detail as blocks): the crystal is a faceted bipyramid
// with its own per-facet flat normals (HomeFlag._build_crystal_mesh()/
// _add_facet()) -- this shader adds toon-banded diffuse with a never-near-
// black shadow floor/cool tint, a hard-edged specular facet highlight, and
// the crystal's own emissive glow (BeaconVisualTuning.crystal_emission,
// pulsed live by HomeFlag._apply_pulse()), matching
// shaders/block_cell_grid.gdshader's technique for visual consistency across
// blocks and beacons.
//
// Unlike BlockFactory's block material, every HomeFlag/GoalFlag builds its
// own dedicated ShaderMaterial instance in HomeFlag._build() (never shared or
// colour-keyed across flags), so every uniform below is a plain uniform set
// directly from BeaconVisualTuning/the flag's own colour in
// HomeFlag._apply_color() -- no per-instance shader parameters needed here.
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.1;

uniform int toon_band_count = 3;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.45;
uniform vec4 shadow_tint : source_color = vec4(0.72, 0.78, 0.97, 1.0);
uniform float highlight_boost : hint_range(1.0, 2.0) = 1.2;

uniform float specular_strength : hint_range(0.0, 2.0) = 0.8;
uniform float specular_sharpness = 32.0;
uniform float specular_softness : hint_range(0.001, 0.3) = 0.08;

void fragment() {
	ALBEDO = albedo_color.rgb;
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float band_count = max(float(toon_band_count), 1.0);
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band_index = floor(ndotl * band_count);
	float band_norm = band_count > 1.0 ? band_index / (band_count - 1.0) : band_index;
	band_norm = clamp(band_norm, 0.0, 1.0);

	float shade = mix(shadow_floor, highlight_boost, band_norm);
	vec3 lit_albedo = mix(ALBEDO * shadow_tint.rgb, ALBEDO, band_norm);
	DIFFUSE_LIGHT += shade * lit_albedo * LIGHT_COLOR * ATTENUATION;

	vec3 half_vec = normalize(LIGHT + VIEW);
	float spec_term = pow(max(dot(NORMAL, half_vec), 0.0), specular_sharpness);
	float spec_mask = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, spec_term);
	SPECULAR_LIGHT += spec_mask * specular_strength * LIGHT_COLOR.rgb * ATTENUATION;
}
