shader_type spatial;
render_mode cull_front, unshaded, skip_vertex_transform, shadows_disabled;

// Bontago-adt.3: inverted-hull outline pass (next_pass of perching_bird
// .gdshader) for the cel look. Expanded in view space with the correct normal
// matrix so non-uniformly scaled parts get an even line.

uniform vec4 outline_color : source_color = vec4(0.1, 0.06, 0.1, 1.0);
uniform float outline_width_m = 0.005;

void vertex() {
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * CUSTOM0.xyz);
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz + view_normal * outline_width_m;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
