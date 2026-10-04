shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.66, 0.79, 0.98, 0.42);
uniform float curtain_height = 30.0;
uniform float fall_speed = 4.2;

void vertex() {
	float offset_y = mod(INSTANCE_CUSTOM.r * curtain_height + TIME * fall_speed, curtain_height) - curtain_height * 0.5;
	VERTEX.y += offset_y;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float taper = smoothstep(0.0, 0.18, across);
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.86, 1.0, UV.y));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * taper * ends;
}
