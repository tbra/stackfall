shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
// Bontago-a3z: the cartoon blast's spiky star flash, billboarded on the camera
// (same billboard as shaders/impact_puff.gdshader). CartoonBlast drives `size`
// and `alpha_scale` over the flash's short life.

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 0.82, 1.0);
uniform float points = 8.0;
uniform float size = 1.0;
uniform float alpha_scale = 1.0;
// Radius of the star's valleys (1.0 = its spike tips).
uniform float inner = 0.42;
uniform float spike_sharpness = 6.0;
uniform float glow = 2.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	VERTEX = vec3(VERTEX.xy * size, 0.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spike = pow(abs(cos(a * points * 0.5)), spike_sharpness);
	float edge = mix(inner, 1.0, spike);
	float aa = fwidth(r);
	float inside = 1.0 - smoothstep(edge - aa, edge + aa, r);
	float core = 1.0 - smoothstep(0.0, inner, r);
	ALBEDO = mix(flash_color.rgb, vec3(1.0), core) * glow;
	ALPHA = inside * alpha_scale;
}
