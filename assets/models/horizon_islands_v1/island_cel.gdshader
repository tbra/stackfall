shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// Vertex-color facets remain distinct; the live environment supplies haze/ambient.
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
	ROUGHNESS = 1.0;
}
void light() {
	float facing = dot(NORMAL,LIGHT);
	float band = 0.36 + 0.28 * step(0.12,facing) + 0.36 * step(0.60,facing);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band;
}
