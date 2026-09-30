shader_type spatial;
// Bontago-22y.6: a colliding snow drift on the disc. Lit exactly like the
// disc's own snow layer (shaders/territory.gdshader: desaturated sun, lit or
// cool shadow tone, same gain and reduced sky ambient), so it reads as part
// of the same snow, and it fades in over its lowest `rim_fade_height` (in
// the mesh's own, field-local height) so no oval outline shows where it
// meets the disc. Only the rim fades; what can bear weight is opaque, so
// what you see is still what you land on.
render_mode specular_disabled, depth_draw_always;

uniform vec4 snow_color : source_color = vec4(0.8, 0.82, 0.9, 1.0);
uniform vec4 shade_color : source_color = vec4(0.55, 0.58, 0.82, 1.0);
uniform float light_gain = 0.42;
uniform float diffuse_desaturate = 0.85;
uniform float ambient_ao = 0.36;
uniform float shadow_band = 0.2;
uniform float band_softness = 0.1;
uniform float rim_fade_height = 0.08;
uniform float rim_fade_base = 0.002;

varying float v_height;

void vertex() {
	v_height = VERTEX.y;
}

void fragment() {
	ALBEDO = snow_color.rgb;
	ROUGHNESS = 1.0;
	AO = ambient_ao;
	AO_LIGHT_AFFECT = 0.0;
	ALPHA = smoothstep(rim_fade_base, rim_fade_base + max(rim_fade_height, 0.0001), v_height);
}

void light() {
	float luma = dot(LIGHT_COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cool_light = mix(LIGHT_COLOR.rgb, vec3(luma), diffuse_desaturate);
	float facing = step(0.0, dot(NORMAL, LIGHT));
	float lit = facing * smoothstep(shadow_band - band_softness, shadow_band + band_softness, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * mix(shade_color.rgb, vec3(1.0), lit) * cool_light * light_gain;
}
