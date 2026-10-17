shader_type spatial;
render_mode cull_disabled;

// The disc's glowing CHAMFER face (config/territory/DiscBodyVisuals.gd chamfer_* fields,
// game/field/ArenaMesh.gd). A sloped ring frustum whose TOP edge is exactly flush (same
// radius AND same y) with game/field/TerritoryOverlay.gd's CylinderMesh top-face outer
// edge -- the true playing-surface boundary -- and whose BOTTOM edge meets
// game/field/ArenaMesh.gd's vertical band flush at the band's outer radius. Sharing that
// top edge is safe: the two faces diverge in radius immediately (a sloped face vs. a
// constant-radius vertical wall), so they touch only along a zero-width edge, not over a
// coincident area, and there is no "dashes at distance" z-fight.
//
// min_screen_width_factor is a secondary safety net: it pushes the chamfer's BOTTOM edge
// (never the shared top edge) down a little further per meter of camera distance, so its
// screen-space coverage never drops below roughly a pixel at long range on any map radius.
//
// surface_noise is a procedurally generated (FastNoiseLite-backed NoiseTexture2D)
// tangent-space normal map, built by game/field/ArenaMesh.gd and shared with the band's
// StandardMaterial3D so both disc surfaces carry the same fine-grained sun sheen.
// surface_anisotropy feeds the built-in ANISOTROPY output using this mesh's generated
// TANGENT data (SurfaceTool.generate_tangents(), U running around the circumference),
// giving a brushed-metal specular streak in the same direction as the band's highlight.
//
// The line reads as a thin edge-lit lip rather than a filled bar because EMISSION fades
// from full strength at the top edge to zero at the (possibly extended) bottom edge.
// ArenaMesh's band mesh builder paints COLOR.r = 0.0 on every top-edge vertex and 1.0 on
// every bottom-edge vertex (its `with_gradient` parameter), so this shader knows per
// vertex which edge it is without a second uniform.

uniform vec3 rim_color : source_color = vec3(1.0, 0.78, 0.35);
uniform float rim_emission_energy = 2.6;
// Matches DiscBodyVisuals.band_color so an extended, non-emissive lower
// portion of this mesh reads as a continuation of the metal band underneath
// it rather than a visibly separate flat-shaded strip.
uniform vec3 band_color : source_color = vec3(0.035, 0.035, 0.04);
// World meters of extra downward push per world meter of camera distance. 0 disables
// the widening entirely (the mesh renders exactly as authored).
uniform float min_screen_width_factor = 0.004;
uniform sampler2D surface_noise : hint_normal;
uniform float surface_noise_strength = 0.35;
uniform float surface_anisotropy = 0.6;

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
	NORMAL_MAP = texture(surface_noise, UV).rgb;
	NORMAL_MAP_DEPTH = surface_noise_strength;
	ANISOTROPY = surface_anisotropy;
}
