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
//
// Bontago-adt.2 (graphics roadmap "Improved cel-shader/toon-shader", mockup 08):
// look rework.
//   - The toon ramp used to bake ALBEDO into its band colours, but Godot
//     multiplies DIFFUSE_LIGHT by ALBEDO once more after light(), so colours
//     were squared (muddy, over-dark saturation). The bands are now pure
//     per-channel multipliers (cool shadow / neutral lit / warm highlight) and
//     the engine applies ALBEDO exactly once. `light_gain` rescales the
//     result; LIGHT_COLOR already carries the PI factor, hence the /PI.
//   - Bevel highlight and rim are added through SPECULAR_LIGHT so they stay
//     light-coloured instead of being tinted by ALBEDO a second time.
//   - The bevel is a narrow band just inside the dark seam (peaking at the
//     seam edge and fading inward), giving each cell a bevelled-cube read.
//   - A cool "sky bounce" rim reads on faces turned away from the sun.
//   - At long range (cells only a few pixels wide) the grid line and bevel
//     fade to a fraction of their strength so distant towers stay clean
//     instead of collapsing to a dark mesh; everything is screen-space.
render_mode cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int toon_band_count = 3;
uniform float grid_line_width_px = 0.9;
uniform vec4 grid_line_color : source_color = vec4(0.12, 0.1, 0.1, 1.0);
uniform vec4 grid_line_glow_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform float grid_line_glow_strength = 0.0;
uniform float grid_line_seam_mix : hint_range(0.0, 1.0) = 0.75;
// Distance stability: below grid_line_far_cell_px on-screen pixels per cell
// the grid line/bevel are scaled toward grid_line_far_strength; at or above
// grid_line_full_cell_px they are full strength.
uniform float grid_line_far_cell_px = 5.0;
uniform float grid_line_full_cell_px = 22.0;
uniform float grid_line_far_strength : hint_range(0.0, 1.0) = 0.45;

uniform vec4 highlight_tint : source_color = vec4(1.0, 0.9, 0.72, 1.0);
uniform float highlight_tint_mix : hint_range(0.0, 1.0) = 1.0;
uniform float highlight_brightness : hint_range(0.5, 2.0) = 1.15;
uniform vec4 lit_tint : source_color = vec4(1.0, 0.97, 0.94, 1.0);
uniform float lit_tint_mix : hint_range(0.0, 1.0) = 1.0;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.66, 0.9, 1.0);
uniform float shadow_tint_mix : hint_range(0.0, 1.0) = 1.0;
uniform float shadow_brightness : hint_range(0.0, 1.5) = 0.62;
// Saturation multiplier on the block colour before shading (1 = as authored);
// keeps player colours vivid after the warm sun colour and cool shadow tint.
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.15;
// Bottom-of-cell contact shading on side faces (strength = darkening at the
// bottom edge, height = fraction of the cell it fades over).
uniform float cell_ao_strength : hint_range(0.0, 1.0) = 0.3;
uniform float cell_ao_height : hint_range(0.05, 1.0) = 0.7;
// Scale of the sky ambient light on blocks (AO built-in). The sunset ambient
// is orange, which tinted blue blocks teal on their shadow faces; the toon
// shadow band (cool shadow_tint) supplies the fill instead.
uniform float ambient_scale : hint_range(0.0, 1.0) = 0.5;
uniform float light_gain : hint_range(0.0, 4.0) = 1.0;
uniform float band_softness : hint_range(0.0, 0.2) = 0.02;

uniform vec4 specular_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float specular_sharpness = 64.0;
uniform float specular_softness : hint_range(0.001, 0.3) = 0.04;
uniform float specular_strength : hint_range(0.0, 2.0) = 0.32;
uniform float specular_albedo_tint : hint_range(0.0, 1.0) = 0.25;

uniform float bevel_highlight_width_px = 2.4;
uniform vec4 bevel_highlight_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float bevel_highlight_strength : hint_range(0.0, 2.0) = 0.42;
uniform float bevel_shadow_side_fraction : hint_range(0.0, 1.0) = 0.3;
// Fake chamfer: within bevel_width_fraction of a cell edge (never thinner than
// bevel_min_width_px) the shading normal tilts toward the edge by bevel_tilt,
// so the toon ramp lights sun-facing edges and shades the others.
uniform float bevel_width_fraction : hint_range(0.0, 0.3) = 0.07;
uniform float bevel_min_width_px = 1.5;
uniform float bevel_tilt : hint_range(0.0, 3.0) = 1.1;

uniform vec4 rim_color : source_color = vec4(1.0, 0.75, 0.5, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec4 rim_cool_color : source_color = vec4(0.55, 0.65, 1.0, 1.0);
uniform float rim_cool_strength : hint_range(0.0, 1.0) = 0.16;

instance uniform bool contributing = false;

varying vec2 v_uv;
varying float v_bevel_amount;
varying float v_seam;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Distance, in UV space, from this fragment to the nearest of the quad's
	// four edges (each visible face's own cell boundary/silhouette).
	vec2 to_edge = min(v_uv, vec2(1.0) - v_uv);
	float dist_to_edge = min(to_edge.x, to_edge.y);

	// fwidth(dist_to_edge) is UV change per screen pixel, so multiplying by a
	// pixel count gives lines of constant screen width at any distance.
	float uv_per_px = max(fwidth(dist_to_edge), 0.0001);
	float cell_px = 1.0 / uv_per_px;
	float detail = mix(
		grid_line_far_strength, 1.0,
		smoothstep(grid_line_far_cell_px, grid_line_full_cell_px, cell_px)
	);
	float px_width = uv_per_px * grid_line_width_px;
	float seam_amount = (1.0 - smoothstep(0.0, px_width, dist_to_edge)) * detail;

	// Bevel: a band peaking just inside the seam and fading inward.
	float band_start = px_width * 0.6;
	float band_end = px_width + uv_per_px * bevel_highlight_width_px;
	float bevel_amount = smoothstep(0.0, band_start, dist_to_edge)
		* (1.0 - smoothstep(band_start, band_end, dist_to_edge));

	// Fake chamfer normal (cotangent frame from screen derivatives, since the
	// merged mesh carries no tangents).
	vec3 n = normalize(NORMAL);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 duv1 = dFdx(v_uv);
	vec2 duv2 = dFdy(v_uv);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 tan_u = normalize(dp2perp * duv1.x + dp1perp * duv2.x + vec3(0.00001));
	vec3 tan_v = normalize(dp2perp * duv1.y + dp1perp * duv2.y + vec3(0.00001));
	float chamfer_w = min(max(bevel_width_fraction, uv_per_px * bevel_min_width_px), 0.45);
	float wx = 1.0 - smoothstep(chamfer_w * 0.85, chamfer_w, to_edge.x);
	float wy = 1.0 - smoothstep(chamfer_w * 0.85, chamfer_w, to_edge.y);
	float sx = v_uv.x < 0.5 ? -1.0 : 1.0;
	float sy = v_uv.y < 0.5 ? -1.0 : 1.0;
	vec3 tilt = tan_u * sx * wx + tan_v * sy * wy;
	NORMAL = normalize(n + tilt * bevel_tilt * detail);

	vec3 seam_target = contributing ? grid_line_glow_color.rgb : grid_line_color.rgb;
	vec3 seam_color = mix(albedo_color.rgb, seam_target, grid_line_seam_mix);
	float glow = contributing ? grid_line_glow_strength : 0.0;

	float base_luma = dot(albedo_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base_rgb = clamp(mix(vec3(base_luma), albedo_color.rgb, albedo_saturation), 0.0, 1.0);
	// Per-cell contact shading: the lower part of every side face darkens
	// (world-up measured through the same tangent frame as the chamfer), so
	// each cube reads as a solid with a grounded bottom instead of a flat tile.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float up_u = dot(tan_u, up_view);
	float up_v = dot(tan_v, up_view);
	float side_w = clamp(abs(up_u) + abs(up_v), 0.0, 1.0);
	float h_u = up_u > 0.0 ? v_uv.x : 1.0 - v_uv.x;
	float h_v = up_v > 0.0 ? v_uv.y : 1.0 - v_uv.y;
	float cell_h = (abs(up_u) * h_u + abs(up_v) * h_v) / max(abs(up_u) + abs(up_v), 0.0001);
	float cell_shade = mix(1.0 - cell_ao_strength, 1.0, smoothstep(0.0, cell_ao_height, cell_h));
	base_rgb *= mix(1.0, cell_shade, side_w * detail);
	ALBEDO = mix(base_rgb, seam_color, seam_amount);
	AO = ambient_scale;
	AO_LIGHT_AFFECT = 0.0;
	EMISSION = seam_target * seam_amount * glow;

	v_bevel_amount = clamp(bevel_amount * detail, 0.0, 1.0);
	v_seam = seam_amount;
}

void light() {
	float band_count = max(float(toon_band_count), 1.0);
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Anti-aliased band quantization (softness keeps thresholds crisp but
	// not stair-stepped where the normal is not constant).
	float scaled = ndotl * band_count;
	float band_index = floor(scaled);
	float frac_part = scaled - band_index;
	band_index += smoothstep(1.0 - band_softness * band_count, 1.0, frac_part);
	float band_norm = band_count > 1.0 ? clamp(band_index / (band_count - 1.0), 0.0, 1.0) : 1.0;

	// Per-channel multipliers, not colours: the engine multiplies
	// DIFFUSE_LIGHT by ALBEDO once after light().
	vec3 shadow_mul = mix(vec3(1.0), shadow_tint.rgb, shadow_tint_mix) * shadow_brightness;
	vec3 lit_mul = mix(vec3(1.0), lit_tint.rgb, lit_tint_mix);
	vec3 highlight_mul = mix(vec3(1.0), highlight_tint.rgb, highlight_tint_mix) * highlight_brightness;

	vec3 band_mul;
	if (band_norm < 0.5) {
		band_mul = mix(shadow_mul, lit_mul, band_norm * 2.0);
	} else {
		band_mul = mix(lit_mul, highlight_mul, (band_norm - 0.5) * 2.0);
	}
	// Where the sun is blocked by a shadow map (ATTENUATION 0) the face keeps
	// the cool shadow-band fill instead of dropping to the warm sky ambient,
	// so shadowed faces stay the block's own hue.
	vec3 effective_mul = mix(shadow_mul, band_mul, ATTENUATION);
	DIFFUSE_LIGHT += effective_mul * light_gain * LIGHT_COLOR / PI;

	// Crisp specular band.
	vec3 half_vec = normalize(LIGHT + VIEW);
	float spec_term = pow(max(dot(NORMAL, half_vec), 0.0), specular_sharpness);
	float spec_mask = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, spec_term);
	vec3 tinted_specular = mix(specular_color.rgb, ALBEDO * 1.5, specular_albedo_tint);
	SPECULAR_LIGHT += spec_mask * specular_strength * tinted_specular * LIGHT_COLOR.rgb * ATTENUATION / PI;

	// Edge bevel light: full on sun-facing faces, a fraction on the rest so
	// every cell edge still reads as bevelled.
	float facing = mix(bevel_shadow_side_fraction, 1.0, smoothstep(0.05, 0.6, ndotl));
	// The lip never paints over the dark seam groove (grid lines stay black).
	SPECULAR_LIGHT += (1.0 - v_seam) * v_bevel_amount * facing * bevel_highlight_strength
		* bevel_highlight_color.rgb * LIGHT_COLOR.rgb * ATTENUATION / PI;

	// Rim: warm on the sun side, cool "sky bounce" on the shadow side.
	float fresnel = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	SPECULAR_LIGHT += (1.0 - v_seam) * fresnel * smoothstep(0.0, 0.3, ndotl) * rim_strength
		* rim_color.rgb * LIGHT_COLOR.rgb * ATTENUATION / PI;
	SPECULAR_LIGHT += (1.0 - v_seam) * fresnel * (1.0 - smoothstep(0.0, 0.3, ndotl)) * rim_cool_strength
		* rim_cool_color.rgb * LIGHT_COLOR.rgb / PI;
}
