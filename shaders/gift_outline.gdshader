shader_type spatial;
render_mode cull_front, unshaded;

// Thin ink rim for gift primitives; shared by every palette material.
void vertex() {
	vec3 n = normalize((MODELVIEW_NORMAL_MATRIX * NORMAL));
	vec2 direction = normalize((PROJECTION_MATRIX * vec4(n, 0.0)).xy + vec2(0.00001));
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy += direction * 1.4 * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = vec3(0.055, 0.065, 0.095);
}
