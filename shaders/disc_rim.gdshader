shader_type spatial;
render_mode cull_disabled;

// Bontago-mp0.3.8 problem 2 (owner: "the thin glowing gold lip on the top
// rim breaks into dashes at distance"). The ACTUAL cause (diagnosed with
// feedback/overhaul/disc2-diag1..5, an extreme-value bisection): the rim's
// top edge sits at almost exactly the same radius AND y as game/
// TerritoryOverlay.gd's own CylinderMesh top-face edge -- close enough
// up-close, but the two near-coincident edges z-fight per-pixel/per-triangle
// at the long camera distances of an overview shot, which no amount of
// EXTRA MESH HEIGHT can fix (a depth-buffer precision problem, not a
// coverage problem) -- confirmed by a diagnostic capture where 6x the rim's
// normal height changed nothing on the far/away side of the ring. The real
// fix is config/DiscBodyVisuals.gd's own rim_radius_scale, raised from a
// "hair's-width" 1.006 to a genuinely separated 1.02 (its own DECISION has
// the full derivation).
//
// This shader's own min_screen_width_factor mechanism below is a SECONDARY
// safety net, not that fix: it grows the ring's BOTTOM edge only (never the
// top edge, which must stay flush with game/DiscBody.gd's own top_y = 0.0,
// the true playing surface) by an amount proportional to distance-to-camera,
// so a genuinely sub-pixel-thin rim's rasterized screen coverage never
// shrinks below roughly a pixel no matter how far away the camera or how
// small a MapDef.field_radius is (the actual z-fighting fix above is a fixed
// world-meter offset, so it is not automatically distance/radius-aware the
// way this is). Up close, distance is small, so the extra push is
// negligible and the mesh stays exactly as authored (thin). game/DiscBody.
// gd's own _build_band_mesh() paints COLOR.r = 0.0 on every top-edge vertex
// and 1.0 on every bottom-edge vertex (see its own `with_gradient`
// parameter) so this shader knows, per vertex, which edge it is without a
// second uniform.
//
// The visible line still reads as a thin edge-lit lip rather than a filled
// bar because EMISSION fades from full strength at the top edge to zero at
// the (possibly extended) bottom edge -- see fragment() below.

uniform vec3 rim_color : source_color = vec3(1.0, 0.78, 0.35);
uniform float rim_emission_energy = 2.6;
// Matches DiscBodyVisuals.band_color so an extended, non-emissive lower
// portion of this mesh reads as a continuation of the metal band underneath
// it rather than a visibly separate flat-shaded strip.
uniform vec3 band_color : source_color = vec3(0.035, 0.035, 0.04);
// World meters of extra downward push per world meter of camera distance --
// see this file's own header comment. 0 disables the widening entirely
// (the mesh renders exactly as authored, reproducing the dashing bug).
uniform float min_screen_width_factor = 0.004;

varying float v_gradient;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	float extra_drop = dist * min_screen_width_factor;
	// COLOR.r is 0.0 on the top-edge vertices (never moved -- must stay
	// flush with the true playing surface) and 1.0 on the bottom-edge
	// vertices (pushed further down as distance grows).
	VERTEX.y -= COLOR.r * extra_drop;
	v_gradient = COLOR.r;
}

void fragment() {
	float fade = 1.0 - smoothstep(0.0, 1.0, v_gradient);
	ALBEDO = mix(band_color, rim_color, fade);
	EMISSION = rim_color * rim_emission_energy * fade;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}
