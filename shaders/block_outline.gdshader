shader_type spatial;
// Bontago-xtq.27 (M7 P2, docs/M7_PLAN.md P2): inverted-hull outline pass for
// a block's merged mesh. game/BlockFactory.gd adds this as a *second*
// MeshInstance3D sharing the exact same ArrayMesh as the toon/cell-grid pass
// (shaders/block_cell_grid.gdshader) -- see BlockFactory.gd's own DECISION
// comment for why a second MeshInstance3D was chosen over a next_pass
// material on the primary one.
//
// Standard inverted-hull technique: cull the *front* faces (so only the
// enlarged back faces show, silhouetting the real mesh from behind it) and
// push every vertex out along its own normal by outline_width_m. Flat,
// unshaded color -- an outline reads as a hand-inked line, not a lit surface.
//
// Bontago-mp0.3.1 (owner feedback: "restrained... a dark tinted version of
// the block color rather than pure black"): `tint_color` is a per-instance
// shader parameter (game/BlockFactory.gd sets it from the block's own colour
// right after building "BlockOutline"), so the *material* itself stays the
// one shared ShaderMaterial instance BlockFactory.gd's own DECISION comment
// documents (never colour-keyed) while each block's outline still reads as
// its own darkened hue. outline_color is the fallback/floor colour mixed
// with that tint by outline_tint_amount.
render_mode cull_front, unshaded;

uniform float outline_width_m : hint_range(0.0, 0.1) = 0.009;
uniform vec4 outline_color : source_color = vec4(0.05, 0.04, 0.05, 1.0);
uniform float outline_tint_amount : hint_range(0.0, 1.0) = 0.65;
uniform float outline_tint_darken : hint_range(0.0, 1.0) = 0.35;

instance uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	VERTEX += NORMAL * outline_width_m;
}

void fragment() {
	vec3 darkened_tint = tint_color.rgb * outline_tint_darken;
	ALBEDO = mix(outline_color.rgb, darkened_tint, outline_tint_amount);
}
