shader_type sky;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float seam_blend_width = 0.025;
uniform float pole_blend_width = 0.06;
uniform float exposure = 0.8;

void sky() {
	vec2 uv = SKY_COORDS;
	vec3 color = texture(panorama, uv).rgb;
	// Symmetric edge blend makes imperfect authored panorama boundaries continuous.
	float seam = 1.0 - smoothstep(0.0, seam_blend_width, min(uv.x, 1.0 - uv.x));
	color = mix(color, texture(panorama, vec2(1.0 - uv.x, uv.y)).rgb, seam * 0.5);
	// Longitude converges to one color at each pole, avoiding a pinwheel seam.
	float pole = 1.0 - smoothstep(0.0, pole_blend_width, min(uv.y, 1.0 - uv.y));
	vec3 pole_color = texture(panorama, vec2(0.5, uv.y < 0.5 ? 0.0 : 1.0)).rgb;
	COLOR = mix(color, pole_color, pole) * exposure;
}
