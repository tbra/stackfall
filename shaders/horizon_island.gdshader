shader_type spatial;
// Bontago-mp0.123: horizon-island cel look, self-lit. Root cause of the flat
// read: with the scene's sky ambient (AMBIENT_SOURCE_SKY) every facet received
// the same bright ambient, so the asset's narrow COLOR_0 range and its light
// bands washed out to one tone. This shader is unshaded: HorizonIslands.gd
// feeds the live sun direction/colour and sky fog colour, faces are split into
// a bright cap (world normal up) and a darker rock body, and three hard bands
// against the sun keep facets distinct at 1 km.
render_mode unshaded, fog_disabled, specular_disabled, cull_back;
uniform vec4 haze_color : source_color = vec4(0.8, 0.7, 0.7, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.3;
uniform float color_gain = 1.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0);
uniform vec4 cap_tint : source_color = vec4(1.0);
uniform vec4 rock_tint : source_color = vec4(1.0);
uniform float cap_normal_min_y = 0.55;
uniform float shadow_level = 0.35;
uniform float mid_level = 0.65;
varying vec3 world_normal;
void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec3 n = normalize(world_normal);
	vec3 tint = n.y >= cap_normal_min_y ? cap_tint.rgb : rock_tint.rgb;
	float facing = dot(n, normalize(sun_direction));
	float band = shadow_level + (mid_level - shadow_level) * step(0.12, facing) + (1.0 - mid_level) * step(0.6, facing);
	vec3 lit = COLOR.rgb * tint * color_gain * band * sun_color.rgb;
	ALBEDO = mix(lit, haze_color.rgb, haze_amount);
}
