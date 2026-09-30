shader_type spatial;
// Bontago-22y.6: cel-styled snow cap. Two light bands (lit white, cool blue
// shade) plus a soft cool rim, so a cap reads as snow against the toon blocks.
// Geometry is the exact collider hull; the "soft rim" is lighting only.
render_mode specular_disabled;

uniform vec4 snow_color : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.72, 0.8, 0.95, 1.0);
uniform vec4 rim_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float rim_strength = 0.45;
uniform float band_softness = 0.08;
uniform float rim_power = 3.0;

void fragment() {
	ALBEDO = snow_color.rgb;
	ROUGHNESS = 1.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = rim_color.rgb * pow(1.0 - facing, rim_power) * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(0.0, band_softness, ndl) * ATTENUATION;
	vec3 tint = mix(shade_color.rgb, vec3(1.0), band);
	DIFFUSE_LIGHT += tint * max(band, 0.35) * LIGHT_COLOR / PI;
}
