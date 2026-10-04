shader_type spatial;
// Bontago-mp0.123 fix: the horizon-island cel look (asset COLOR_0 facets, three
// directional-light bands) with scene fog disabled. Instead of the depth fog
// washing every island to flat lavender, HorizonIslands.gd feeds the live sky
// fog/horizon colour into haze_color each half second, so the islands pick up
// the time-of-day light and still sit in the same haze as the cloud band.
render_mode diffuse_lambert, specular_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 haze_color : source_color = vec4(0.8, 0.7, 0.7, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.3;
uniform float color_gain = 1.0;
void fragment() {
	vec3 base = COLOR.rgb * tint.rgb * color_gain;
	ALBEDO = mix(base, haze_color.rgb, haze_amount);
	ROUGHNESS = 1.0;
}
void light() {
	float facing = dot(NORMAL, LIGHT);
	float band = 0.36 + 0.28 * step(0.12, facing) + 0.36 * step(0.60, facing);
	// Godot pre-multiplies LIGHT_COLOR by PI for diffuse; a custom light() must divide it back out or everything blows out to white.
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band / PI;
}
