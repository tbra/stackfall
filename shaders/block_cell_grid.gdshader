shader_type spatial;
// Bontago-xtq.27 (M7 P2, docs/M7_PLAN.md P2; spec 2.10 as amended, owner
// decision 2026-09-26 Bontago-5h7 Q1/Q2): the block mesh stays one merged
// solid shape (Bontago-xtq.3) -- this shader is what actually draws the
// per-cell grid lines and the toon shading bands on its faces, it never
// changes geometry/collision/connectivity.
//
// Bontago-mp0.3.1 (owner feedback on docs/art_mockups/08-cel-shaded-home-
// beacons.png: "Blocks only have the black borders, the mockup shows much
// more detailed cel-shading with highlights and shadows affected by the
// light source"), fix round (owner review of blocks-r1):
//   - shadow/lit/highlight are three explicit tinted "keyframe" colours
//     interpolated by the toon-banded N.L, not one hue scaled by a single
//     brightness scalar -- see light()'s own comment for why.
//   - the bright bevel band now measures distance from the *same* true UV
//     cell edge the dark seam does (dist_to_edge = 0), so it hugs the edge
//     and fades inward instead of drawing an inset "picture frame" square.
//   - the specular highlight is tuned small/hard/tinted so it never washes
//     out a whole face past the HDR glow threshold (Main.tscn's 1.1).
//   - a subtle warm Fresnel rim light on edges facing the sun.
// Every number above lives on config/BlockVisualTuning.gd, wired in by
// game/BlockFactory.gd's `_material_for_color()`.
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
render_mode cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int toon_band_count = 3;
uniform float grid_line_width_px = 0.9;
uniform vec4 grid_line_color : source_color = vec4(0.12, 0.1, 0.1, 1.0);
uniform vec4 grid_line_glow_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform float grid_line_glow_strength = 2.2;
uniform float grid_line_seam_mix : hint_range(0.0, 1.0) = 0.4;

uniform vec4 highlight_tint : source_color = vec4(1.0, 0.85, 0.65, 1.0);
uniform float highlight_tint_mix : hint_range(0.0, 1.0) = 0.35;
uniform float highlight_brightness : hint_range(0.5, 1.5) = 1.0;
uniform vec4 lit_tint : source_color = vec4(1.0, 0.15, 0.0, 1.0);
uniform float lit_tint_mix : hint_range(0.0, 1.0) = 0.15;
uniform vec4 shadow_tint : source_color = vec4(0.85, 0.85, 0.95, 1.0);
uniform float shadow_tint_mix : hint_range(0.0, 1.0) = 0.6;
uniform float shadow_brightness : hint_range(0.0, 1.5) = 0.72;

uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular_sharpness = 96.0;
uniform float specular_softness : hint_range(0.001, 0.3) = 0.03;
uniform float specular_strength : hint_range(0.0, 2.0) = 0.16;
uniform float specular_albedo_tint : hint_range(0.0, 1.0) = 0.4;

uniform float bevel_highlight_width_px = 1.4;
uniform vec4 bevel_highlight_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float bevel_highlight_strength : hint_range(0.0, 2.0) = 0.22;

uniform vec4 rim_color : source_color = vec4(1.0, 0.75, 0.5, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.15;

instance uniform bool contributing = false;

varying vec2 v_uv;
varying float v_bevel_amount;

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
	float uv_per_px = max(fwidth(dist_to_edge), 0.0001);
	float px_width = uv_per_px * grid_line_width_px;
	float seam_amount = 1.0 - smoothstep(0.0, px_width, dist_to_edge);

	// Bontago-mp0.3.1 fix round: measured from the *same* true edge
	// (dist_to_edge = 0) as the seam above, not offset past it -- this is
	// what makes the bright band hug the actual cell edge instead of
	// drawing an inset "picture frame" square further in.
	float bevel_width = uv_per_px * bevel_highlight_width_px;
	float bevel_amount = 1.0 - smoothstep(0.0, bevel_width, dist_to_edge);

	vec3 seam_target = contributing ? grid_line_glow_color.rgb : grid_line_color.rgb;
	// Owner feedback (Bontago-mp0.3.1): a darker *shade of the block's own
	// colour*, not a flat-replace black line -- grid_line_seam_mix < 1.0 keeps
	// some of albedo_color in the seam instead of fully overwriting it.
	vec3 seam_color = mix(albedo_color.rgb, seam_target, grid_line_seam_mix);
	float glow = contributing ? grid_line_glow_strength : 0.0;

	ALBEDO = mix(albedo_color.rgb, seam_color, seam_amount);
	EMISSION = seam_target * seam_amount * glow;

	v_bevel_amount = clamp(bevel_amount, 0.0, 1.0);
}

void light() {
	float band_count = max(float(toon_band_count), 1.0);
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band_index = floor(ndotl * band_count);
	float band_norm = band_count > 1.0 ? band_index / (band_count - 1.0) : band_index;
	band_norm = clamp(band_norm, 0.0, 1.0);

	// Bontago-mp0.3.1 fix round (owner review: "make the bands produce ~3
	// distinct values per colour", "top faces noticeably lighter/warmer...
	// lit side mid saturated... away side darker and slightly cool"): three
	// explicit tinted keyframe colours built from this fragment's own ALBEDO
	// (already carries the cell-seam darkening from fragment() above),
	// interpolated by the toon band instead of one hue scaled by a single
	// shadow_floor/highlight_boost brightness scalar.
	vec3 shadow_color = mix(ALBEDO, ALBEDO * shadow_tint.rgb, shadow_tint_mix) * shadow_brightness;
	vec3 lit_color = mix(ALBEDO, lit_tint.rgb, lit_tint_mix);
	vec3 highlight_color = mix(ALBEDO, highlight_tint.rgb, highlight_tint_mix) * highlight_brightness;

	vec3 band_color;
	if (band_norm < 0.5) {
		band_color = mix(shadow_color, lit_color, band_norm * 2.0);
	} else {
		band_color = mix(lit_color, highlight_color, (band_norm - 0.5) * 2.0);
	}
	DIFFUSE_LIGHT += band_color * LIGHT_COLOR * ATTENUATION;

	// Hard-edged, tinted specular "plastic" highlight -- a Blinn-Phong term
	// quantized to a crisp, small, dim dot (not GGX's soft PBR falloff), and
	// blended toward the lit albedo instead of pure white so it never reads
	// as a blown-out patch (owner review: "clamp the specular... never
	// whites out a whole face").
	vec3 half_vec = normalize(LIGHT + VIEW);
	float spec_term = pow(max(dot(NORMAL, half_vec), 0.0), specular_sharpness);
	float spec_mask = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, spec_term);
	vec3 tinted_specular = mix(specular_color.rgb, band_color, specular_albedo_tint);
	SPECULAR_LIGHT += spec_mask * specular_strength * tinted_specular * LIGHT_COLOR.rgb * ATTENUATION;

	// Bright bevel hugging the true cell edge, fading inward, restricted to
	// faces angled toward the light so the shape reads as a gently bevelled
	// cube rather than a second grid line running everywhere.
	float bevel_mask = v_bevel_amount * smoothstep(0.05, 0.35, ndotl);
	DIFFUSE_LIGHT += bevel_mask * bevel_highlight_strength * bevel_highlight_color.rgb * LIGHT_COLOR.rgb * ATTENUATION;

	// Subtle warm rim light on silhouette edges facing the sun.
	float fresnel = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float rim_mask = fresnel * smoothstep(0.0, 0.3, ndotl);
	DIFFUSE_LIGHT += rim_mask * rim_strength * rim_color.rgb * LIGHT_COLOR.rgb * ATTENUATION;
}
