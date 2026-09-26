shader_type spatial;
// Bontago-xtq.40 (owner playtest, "ghost block renders without any lines"):
// game/GhostPreview.gd's held-block body used a plain StandardMaterial3D with
// no cell-grid lines at all -- shaders/block_cell_grid.gdshader (the real
// placed-block shader) was never assigned to it, and GhostPreview's own
// _apply_material_to_visual() immediately overwrote build_visual_only()'s
// meshes with that plain material anyway. This is a dedicated variant of that
// shader for the ghost's own translucent body, not a shared/edited copy of
// block_cell_grid.gdshader itself:
//   - the ghost needs ALPHA (translucency, validity-tint alpha) and a
//     triplanar hatch overlay (HOLE/GOAL_ZONE state) neither of which the
//     real, always-opaque block shader supports or should gain -- adding
//     either there would change every placed block's own render_mode/opaque
//     depth-draw behaviour, which this package must not touch (see
//     game/BlockFactory.gd's own shader, untouched).
//   - deliberately has NO `contributing` instance uniform at all (contrast
//     block_cell_grid.gdshader's own one) -- the settled/sleeping "resting =
//     contributing to territory influence" glow (Bontago-xtq.27) is reserved
//     for real placed blocks; leaving the uniform out entirely, rather than
//     just never setting it true, means the ghost structurally cannot ever
//     receive that glow, not just that nothing currently requests it.
//   - no toon-banded light() override: the ghost's own default PBR-ish
//     shading is unchanged from the StandardMaterial3D this replaces
//     (SHADING_MODE_PER_PIXEL, no explicit ROUGHNESS/METALLIC/SPECULAR --
//     Godot's built-in spatial shader defaults for those already match
//     StandardMaterial3D's own defaults when a shader never writes them).
//
// Cell-grid lines: identical UV-edge-distance trick to block_cell_grid.
// gdshader -- see that file's own header for why BlockMeshBuilder's merged,
// 0..1-per-cell-face UVs make this exact, with no extra per-cell bookkeeping.
// grid_line_color/grid_line_width_px are read straight from the same
// BlockVisualTuning resource game/BlockFactory.gd's real blocks use
// (game/GhostPreview.gd's own VISUAL_TUNING const), so a real block and its
// own ghost preview always draw identical grid lines.
//
// DECISION (shaders/ghost_cell_grid.gdshader, Bontago-xtq.40): translucency
// comes from writing ALPHA alone, with no explicit `render_mode blend_mix`
// keyword -- relying on the same Godot behaviour shaders/territory.gdshader's
// own header already documents for this project ("a shader that never writes
// ALPHA is opaque by default and always depth-tests and depth-writes
// normally"; the converse holds too: writing ALPHA switches the material
// into the blended/transparent draw path). Confirmed visually via
// tools/screenshot_xtq40_ghost.gd.
//
// DECISION (shaders/ghost_cell_grid.gdshader, Bontago-xtq.40): the hatch
// overlay (HOLE/GOAL_ZONE state, spec 2.5 "hatched pattern when over a
// hole") is hand-rolled triplanar box-mapping (world position/normal, three
// axis-projected samples blended by |normal|, normalized to sum 1) rather
// than StandardMaterial3D.uv1_triplanar, which has no ShaderMaterial
// equivalent -- the ghost's single merged shape mesh has 0..1 UVs per cell
// face (needed for the grid lines above), not a whole-shape 0..1 range, so a
// plain UV-mapped hatch would repeat once per cell instead of tiling evenly
// across the whole silhouette the way the original StandardMaterial3D
// (uv1_triplanar + uv1_scale) did. This blend skips uv1_triplanar_sharpness'
// own exponent (a plain linear normalize instead) -- close enough for a
// translucent overlay pattern, not a lit surface material, and avoids a
// magic-number sharpness constant this package has no owner feedback to tune
// against.
render_mode cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float grid_line_width_px = 1.5;
uniform vec4 grid_line_color : source_color = vec4(0.12, 0.1, 0.1, 1.0);

// HOLE/GOAL_ZONE-only hatch overlay -- see game/GhostPreview.gd's
// _apply_validity_material(), which is the only place any of these three
// change together (use_hatch toggled with hatch_scale, hatch_texture bound
// once in _ready()).
uniform bool use_hatch = false;
uniform sampler2D hatch_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float hatch_scale = 6.0;

varying vec2 v_uv;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_uv = UV;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float sample_hatch_triplanar_alpha(vec3 world_pos, vec3 world_normal, float scale) {
	vec3 blend_weight = abs(world_normal);
	blend_weight /= max(blend_weight.x + blend_weight.y + blend_weight.z, 0.0001);
	float x_alpha = texture(hatch_texture, world_pos.zy * scale).a;
	float y_alpha = texture(hatch_texture, world_pos.xz * scale).a;
	float z_alpha = texture(hatch_texture, world_pos.xy * scale).a;
	return x_alpha * blend_weight.x + y_alpha * blend_weight.y + z_alpha * blend_weight.z;
}

void fragment() {
	// Same UV-edge-distance grid-line trick as shaders/block_cell_grid.
	// gdshader's own fragment() -- see that file's header for why
	// BlockMeshBuilder's per-cell 0..1 UVs make this land exactly on cell
	// boundaries and the shape's own silhouette.
	vec2 to_edge = min(v_uv, vec2(1.0) - v_uv);
	float dist_to_edge = min(to_edge.x, to_edge.y);
	float px_width = max(fwidth(dist_to_edge), 0.0001) * grid_line_width_px;
	float line_amount = 1.0 - smoothstep(0.0, px_width, dist_to_edge);

	float hatch_alpha = 1.0;
	if (use_hatch) {
		hatch_alpha = sample_hatch_triplanar_alpha(v_world_pos, v_world_normal, hatch_scale);
	}

	ALBEDO = mix(albedo_color.rgb, grid_line_color.rgb, line_amount);
	ALPHA = albedo_color.a * hatch_alpha;
}
