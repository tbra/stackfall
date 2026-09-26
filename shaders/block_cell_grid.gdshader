shader_type spatial;
// Bontago-xtq.27 (M7 P2, docs/M7_PLAN.md P2; spec 2.10 as amended, owner
// decision 2026-09-26 Bontago-5h7 Q1/Q2): the block mesh stays one merged
// solid shape (Bontago-xtq.3) -- this shader is what actually draws the
// per-cell grid lines and the toon shading bands on its faces, it never
// changes geometry/collision/connectivity.
//
// Cell-grid lines: core/blocks/BlockMeshBuilder.gd already emits 0..1 UVs
// per visible *cell* face (only exposed faces get a quad at all, so each
// quad's UV already spans exactly one cell's face -- see that file's
// _append_face()). Drawing a thin line wherever a UV coordinate is near 0 or
// 1 therefore lands exactly on every cell boundary and on the shape's own
// silhouette, with no extra per-cell bookkeeping needed here.
//
// Toon bands: light() below quantizes the N.L diffuse term into
// toon_band_count discrete steps instead of Godot's normal smooth ramp.
//
// Glow: `contributing` is a per-instance shader parameter (not a plain
// uniform -- every block shares this one ShaderMaterial instance, cached by
// owner color in game/BlockFactory.gd's `_material_for_color()`), set via
// GeometryInstance3D.set_instance_shader_parameter(&"contributing", bool) --
// see BlockFactory.build()'s `sleeping_state_changed` wiring for who flips it
// and why "resting" stands in for "contributing to territory influence"
// this milestone.
render_mode cull_back, specular_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int toon_band_count = 3;
uniform float grid_line_width_px = 1.5;
uniform vec4 grid_line_color : source_color = vec4(0.12, 0.1, 0.1, 1.0);
uniform vec4 grid_line_glow_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform float grid_line_glow_strength = 2.2;

instance uniform bool contributing = false;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Distance, in UV space, from this fragment to the nearest of the quad's
	// four edges (each visible face's own cell boundary/silhouette).
	vec2 to_edge = min(v_uv, vec2(1.0) - v_uv);
	float dist_to_edge = min(to_edge.x, to_edge.y);

	// hint_range keeps grid_line_width_px a "pixels" knob rather than a raw
	// UV fraction: fwidth(dist_to_edge) is how much dist_to_edge changes per
	// screen pixel here, so multiplying by the pixel count gives a line that
	// reads the same width on screen regardless of the block's distance from
	// the camera or its cell size.
	float px_width = max(fwidth(dist_to_edge), 0.0001) * grid_line_width_px;
	float line_amount = 1.0 - smoothstep(0.0, px_width, dist_to_edge);

	vec3 line_color = contributing ? grid_line_glow_color.rgb : grid_line_color.rgb;
	float glow = contributing ? grid_line_glow_strength : 0.0;

	ALBEDO = mix(albedo_color.rgb, line_color, line_amount);
	EMISSION = line_color * line_amount * glow;
}

void light() {
	float band_count = max(float(toon_band_count), 1.0);
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float banded = floor(ndotl * band_count) / band_count;
	DIFFUSE_LIGHT += banded * ALBEDO * LIGHT_COLOR * ATTENUATION;
}
