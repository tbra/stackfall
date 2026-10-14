shader_type spatial;
render_mode cull_back;
// Bontago-9cv: cel shading for the gift models (config/gifts/GiftModelTable.gd swaps each
// imported model material for one of these at build time). Same light model as
// the blocks (shaders/blocks/block_cell_grid.gdshader light()): N.L quantized into
// toon_band_count bands that blend shadow -> lit -> highlight multipliers, a crisp
// specular band and a warm rim, so a gift sits in the same world as the pile.
// The gift ink outline (shaders/gifts/gift_outline.gdshader) is this material's next_pass.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;
uniform bool use_vertex_color = false;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

uniform int toon_band_count = 3;
uniform float band_softness : hint_range(0.0, 0.2) = 0.02;
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.9, 0.72, 1.0);
uniform float highlight_brightness : hint_range(0.5, 2.0) = 1.15;
uniform vec4 lit_tint : source_color = vec4(1.0, 0.97, 0.94, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.66, 0.9, 1.0);
uniform float shadow_brightness : hint_range(0.0, 1.5) = 0.62;
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.12;
uniform float ambient_scale : hint_range(0.0, 1.0) = 0.5;

uniform vec4 specular_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float specular_sharpness = 48.0;
uniform float specular_softness : hint_range(0.001, 0.3) = 0.04;
uniform float specular_strength : hint_range(0.0, 2.0) = 0.35;

uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.62, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec3 base = albedo_color.rgb;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV).rgb;
	}
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	float grey = dot(base, vec3(0.299, 0.587, 0.114));
	ALBEDO = clamp(mix(vec3(grey), base, albedo_saturation), 0.0, 1.0);
	AO = ambient_scale;
	EMISSION = emission_color.rgb * emission_energy;
	// Warm rim on the silhouette, like the blocks' rim light.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION += rim_color.rgb * rim * rim_strength * ALBEDO;
}

void light() {
	float band_count = max(float(toon_band_count), 1.0);
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float scaled = ndotl * band_count;
	float band_index = floor(scaled);
	band_index += smoothstep(1.0 - band_softness * band_count, 1.0, scaled - band_index);
	float band_norm = band_count > 1.0 ? clamp(band_index / (band_count - 1.0), 0.0, 1.0) : 1.0;
	vec3 shadow_mul = shadow_tint.rgb * shadow_brightness;
	vec3 lit_mul = lit_tint.rgb;
	vec3 highlight_mul = highlight_tint.rgb * highlight_brightness;
	vec3 band_mul = band_norm < 0.5
		? mix(shadow_mul, lit_mul, band_norm * 2.0)
		: mix(lit_mul, highlight_mul, (band_norm - 0.5) * 2.0);
	DIFFUSE_LIGHT += mix(shadow_mul, band_mul, ATTENUATION) * LIGHT_COLOR / PI;
	vec3 half_vec = normalize(LIGHT + VIEW);
	float spec_term = pow(max(dot(NORMAL, half_vec), 0.0), specular_sharpness);
	float spec_mask = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, spec_term);
	SPECULAR_LIGHT += spec_mask * specular_strength * specular_color.rgb * LIGHT_COLOR.rgb * ATTENUATION / PI;
}
