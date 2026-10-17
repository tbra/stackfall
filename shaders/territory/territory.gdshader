shader_type spatial;
// DECISION: the disc is opaque (fragment() never writes ALPHA), so the material is
// compile-time opaque rather than alpha 1.0 in the transparent queue; a shader that never
// writes ALPHA depth-tests and depth-writes normally, so blocks and the ghost footprint
// quad test correctly against it. The disc shows ProceduralSky reflections (Main.tscn's
// WorldEnvironment) via SPECULAR/METALLIC below.
// DECISION (shaders/territory/territory.gdshader): specular_disabled. The "main light
// source glaringly visible in the disc reflection" was never in the mirror
// texture -- it is the DirectionalLight3D's own GGX specular lobe on this
// surface (the bisect run shows it unchanged with the planar mirror, SSR, the
// ReflectionProbe or shadows switched off, and gone only with the light's
// specular at 0). At a polished roughness that lobe peaks hundreds of times
// brighter than the sun's diffuse light, so any clamp on a sampled texture
// cannot reach it. Direct-light specular is turned off on the disc only (the
// light still shades blocks normally); the disc's reflection is the planar
// mirror (EMISSION below) plus the ambient/probe/SSR reflection, which never
// shows a hot spot for a sun the skybox does not paint.
// DECISION: fog_disabled. The sunset depth/volumetric fog (warm
// albedo) was what turned the cool graphite disc top brown (verified: fog off
// gives a neutral near-black surface); the disc keeps its own cool sky sheen
// for atmosphere instead.
render_mode cull_disabled, specular_disabled, fog_disabled;

// Territory on the disk (spec 1.10, 2.5).
//
// **Two rendering paths.** The analytic path draws the border as the true union of the
// disk-local circles TerritorySolver/TerritoryGroups actually kept, a curve by
// construction (smoothstepping a bilinearly-upscaled 1 m cell raster can only look like a
// blurred grid; game/field/TerritoryOverlay.gd's class doc explains why territory_res
// cannot fix this). The raster path is kept as the fallback for the one case the
// analytic path cannot bound the cost of: circle_count exceeding
// TerritoryVisuals.max_shader_circles (game/field/TerritoryOverlay.gd sets
// `circles_valid` to false whenever that happens, or before any circles have
// ever been uploaded).
//
// game/field/TerritoryOverlay.gd uploads, per raster tick:
//
//   territory_tex the slot grid (R = team_id + 1, 0 = unowned)
//                          upscaled bilinearly to MapDef.territory_res and
//                          sampled with filter_linear. Only read by the
//                          raster (fallback) path.
//   territory_cells the same slot grid at cell resolution, unblended.
//                          Only read by the raster (fallback) path.
//   territory_state STATE_CONTESTED (1) | STATE_HOLE (2) |
//   territory_state_soft STATE_GOAL_ZONE (4) per cell, at cell resolution,
//                          bound twice. STATE_HOLE is read by *both* paths —
//                          holes are TerritoryRaster's authority for
//                          physical floor (spec 2.5: "Discard floor pixels
//                          only for actual physical holes"), never an
//                          analytic quantity, so the unfiltered sampler's
//                          discard test below is common code. The rest of
//                          this texture (CONTESTED / GOAL_ZONE, and the
//                          filtered hole-rim glow) is only read by the
//                          raster (fallback) path; the analytic path derives
//                          contested/goal-zone visuals straight from the
//                          circle/goal lists instead.
//   circle_tex one texel per home-anchored circle: R/G = disk-local x/z, B = radius, A =
//                          team id. filter_nearest, read with texelFetch()
//                          so a filtered sample never blends two circles'
//                          rows together.
//   goal_tex one texel per goal no-build disc: R/G = x/z,
//                          B = radius. Read the same way, independent of
//                          circles_valid — the goal list is always small
//                          (spec 1.5 allows 1-5) and never itself overflows.
//
// Disk-local (x, z) maps to UV with uv_scale / uv_offset, which carry
// CellGrid's convention: cell (0, 0) is the -x/-z corner of the square that
// covers the disk. The analytic path reads v_local.xz directly and needs no
// UV at all; uv is still computed for the raster path and the shimmer's
// travelling-band pattern.

#include "res://shaders/territory/territory_circle_field.gdshaderinc"
// TerritoryRaster's per-cell state bits.
const int STATE_CONTESTED = 1;
const int STATE_HOLE = 2;
const int STATE_GOAL_ZONE = 4;
// Goal discs the analytic path loops; mirrors game/field/TerritoryOverlay.gd's
// GOAL_TEXELS_MAX. Spec 1.5 allows only 1-5 goal flags, so this is a wire/
// shader safety cap, not a rule.
const int GOAL_MAX = 8;

// weather fog for a fog_disabled surface. Nothing closer than
// wfog_begin metres (view space), wfog_strength at wfog_end; 0 strength = off.
uniform float wfog_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wfog_begin = 30.0;
uniform float wfog_end = 110.0;

// rain wet look. Albedo is multiplied by (1 - wet_darken); 0 = off.
uniform float wet_darken : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wfog_color : source_color = vec4(0.72, 0.8, 0.88, 1.0);
// cloud shadows (game/sky/CloudShadows.gd). The disc is EMISSION-dominated (planar
// mirror), which a Decal cannot darken, so the same two cross-fading shadow layers are sampled
// here. cshadow_*_m maps world position to the layer's unit box (-0.5..0.5 per axis, the Decal's
// own mapping); cshadow_*_alpha is the layer's strength (0 = off); cshadow_color is the tint.
uniform sampler2D cshadow_tex_a : filter_linear, repeat_disable;
uniform sampler2D cshadow_tex_b : filter_linear, repeat_disable;
uniform mat4 cshadow_a_m = mat4(1.0);
uniform mat4 cshadow_b_m = mat4(1.0);
uniform float cshadow_a_alpha = 0.0;
uniform float cshadow_b_alpha = 0.0;
uniform vec3 cshadow_color : source_color = vec3(0.02, 0.025, 0.07);

float cshadow_layer(sampler2D tex, mat4 to_unit, float alpha, vec3 world) {
	if (alpha <= 0.0) {
		return 0.0;
	}
	vec3 local = (to_unit * vec4(world, 1.0)).xyz;
	if (abs(local.x) > 0.5 || abs(local.y) > 0.5 || abs(local.z) > 0.5) {
		return 0.0;
	}
	return texture(tex, local.xz + 0.5).a * alpha;
}
uniform sampler2D territory_tex : filter_linear, repeat_disable;
uniform sampler2D territory_cells : filter_nearest, repeat_disable;
uniform sampler2D territory_state : filter_nearest, repeat_disable;
uniform sampler2D territory_state_soft : filter_linear, repeat_disable;
// Per-slot colors from MatchConfig.player_colors, already converted to linear
// by TerritoryOverlay; indexed by the slot byte - 1 (raster path) or the
// circle's own team id (analytic path).
uniform vec4 slot_colors[SLOT_COLOR_MAX];

uniform vec4 base_color : source_color = vec4(0.68, 0.70, 0.74, 1.0);
// Defaults match TerritoryVisuals.gd's disk_metallic/disk_roughness
// (a glossy dielectric under the planar mirror); only used if TerritoryOverlay never pushes the real
// resource values (it always does in practice -- see refresh_visual_uniforms()).
uniform float base_metallic : hint_range(0.0, 1.0) = 0.1;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.3;

// -- Sun-facing sheen / diffuse cooling --------------------
// Main.tscn's DirectionalLight3D is warm and tuned for the blocks, so Godot's default
// diffuse response (ALBEDO * warm LIGHT_COLOR) would push disk_base_color's cool grey
// toward brown wherever the top faces the sun. light() below (defining it replaces only the
// DIRECT DirectionalLight3D diffuse/specular pass; ambient/IBL/the planar mirror are computed
// elsewhere) desaturates that light's colour toward its own luminance and caps its energy, so
// ambient/mirror/the explicit sheen below stay the dominant read instead of a warm-lit matte
// surface.
//
// DECISION: disk_sheen_* is a VIEW-DEPENDENT specular-style term, not a position mask: a
// position-based gradient painted the same half gold from every angle. reflect() the
// camera's view ray off the disc's flat NORMAL and compare with the sun direction (mirror
// optics: would a perfect mirror here show the sun to this camera). Per-pixel VIEW varies
// across the surface, giving a broad gradient rather than one hot spot, and the term falls
// to ~0 when the sun is behind the camera. disk_sheen_exponent is deliberately LOW (a broad
// lobe): a real GGX hot spot was rejected for the DIRECT light (see the render_mode
// DECISION above), so this is a hand-tuned, non-physical falloff.
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
uniform vec3 disk_sheen_color : source_color = vec3(1.0, 0.78, 0.4);
uniform float disk_sheen_strength : hint_range(0.0, 2.0) = 0.6;
uniform float disk_sheen_exponent : hint_range(0.5, 16.0) = 2.5;
uniform float disk_diffuse_response : hint_range(0.0, 1.0) = 0.45;
uniform float disk_diffuse_desaturate : hint_range(0.0, 1.0) = 0.85;

// DECISION: the disk is unconditionally opaque (fragment() never writes ALPHA), so there are no disk-opacity uniforms.

uniform float uv_scale = 0.011111;
uniform float uv_offset = 0.5;

// -- Raster (fallback) path uniforms -----------------------------------------
uniform float edge_softness : hint_range(0.001, 1.0) = 0.25;
uniform float tint_alpha : hint_range(0.0, 1.0) = 0.55;

uniform float outline_width : hint_range(0.001, 1.0) = 0.16;
uniform float outline_speed = 1.6;
uniform float outline_strength = 1.4;
uniform float outline_pulse_depth : hint_range(0.0, 1.0) = 0.45;

uniform vec4 contested_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float contested_shimmer_rate = 5.0;
uniform float contested_shimmer_scale = 24.0;
uniform float contested_shimmer_strength = 0.5;

uniform vec4 hole_rim_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float hole_rim_width : hint_range(0.001, 1.0) = 0.35;
uniform float hole_rim_glow = 2.5;

// animated void drawn on hole cells (config/
// HoleVisualTuning.gd feeds every value; game/field/TerritoryOverlay.gd uploads).
uniform vec4 void_deep_color : source_color = vec4(0.01, 0.005, 0.03, 1.0);
uniform vec4 void_mid_color : source_color = vec4(0.12, 0.04, 0.3, 1.0);
uniform vec4 void_rim_color : source_color = vec4(0.65, 0.35, 1.0, 1.0);
uniform float void_rim_width_cells : hint_range(0.01, 0.5) = 0.18;
uniform float void_rim_glow = 1.8;
uniform float void_swirl_scale = 0.8;
uniform float void_swirl_speed = 0.35;
uniform float void_swirl_twist = 1.4;
uniform int void_band_count = 3;
uniform float void_band_softness : hint_range(0.0, 0.5) = 0.08;
uniform float void_mid_amount : hint_range(0.0, 1.0) = 0.6;
// 1 = swirl animates and bands from noise; 0 = flat deep colour + rim (Low).
uniform float void_animated : hint_range(0.0, 1.0) = 1.0;
// One grid cell in territory UV units (1 / cells per side).
uniform float hole_cell_uv = 0.05;
// the hole raster (R = 1 on hole cells, G = 1 on contested cells) at cell resolution,
// sampled with a linear filter so the void follows a smooth field, not cell
// squares. Bound by game/field/TerritoryOverlay.gd's push_cells().
uniform sampler2D territory_hole : filter_linear, repeat_disable;
// False only while the uploaded territory_hole has no hole cell (game/field/TerritoryOverlay.gd
// push_cells()); fragment() then skips the void field entirely. True by default so an
// overlay that never uploaded keeps the always-evaluate behaviour.
uniform bool void_present = true;
// Smoothed hole mask level a pixel needs inside the overlap region (every
// pixel of an activated cell clears it; reaches at most ~0.3 cell past one).
uniform float void_overlap_mask_min = 0.2;
// Mask level for a hole outside any overlap (Jumping Bean, or a permanent
// hole whose contest ended): the bilinear 0.5 iso-line, a rounded blob.
uniform float void_blob_mask_min = 0.5;

// -- Analytic circle path uniforms ---------------------------
// False when circle_count is 0 (no solve yet, or a match just ended) or
// exceeds max_shader_circles (spec 2.5, "Bounded cost"): the raster path
// below is drawn instead for that frame.
uniform bool circles_valid = false;
// MatchConfig.HoleMode.OFF: colour by a single-slot argmax over the circle
// list (spec 2.5's v2 alternative) instead of a per-team union + contested
// test.
uniform bool argmax_mode = false;
uniform sampler2D goal_tex : filter_nearest, repeat_disable;
uniform int goal_count = 0;
// A coarse spatial bin over the circle list, built on the CPU by
// game/field/TerritoryOverlay.gd's _pack_circle_bins(). Without it every disk pixel
// fetched every circle (O(pixels x circles), measured ~95-120 ms/frame at
// 60-160 live blocks against ~15-30 ms with the circle loop skipped). Texel k
// < bin_grid^2 holds (start, count) for bin k; the texels from `start`
// onward hold ascending circle indices (the same team-sorted order as
// circle_tex, so the saturation early-out below sees the same sequence). A
// circle is binned wherever its value (radius - distance) can reach
// -circle_bin margin, a band wider than every visual effect below reads, so
// the skipped circles never change a drawn pixel. Points outside the grid,
// or circle_bins_valid == false, loop the whole list exactly as before.
uniform float rim_width : hint_range(0.001, 2.0) = 0.35;
// The ownership tint's smoothstep feathers over edge_softness_m, separate from
// rim_soft_width (the glow band's coverage gate above), so the border reads crisp while
// the rim glow (rim_width/rim_strength/rim_pulse_depth/rim_speed below) stays soft.
// See circle_path()'s DECISION comment.
uniform float edge_softness_m : hint_range(0.0, 2.0) = 0.03;
uniform float rim_strength = 1.4;
uniform float rim_pulse_depth : hint_range(0.0, 1.0) = 0.45;
uniform float rim_speed = 1.6;

// -- Top-surface brushed/plank grain ---------------------------------------
// Cheap hash-based value noise in disk-local meters (v_local.xz): no texture sampling or
// extra render pass. Perturbs NORMAL/ROUGHNESS only, computed in fragment() BEFORE both the
// mirror block's fresnel term and the disk_sheen block, so the sun sheen and the
// mirror/ambient/SSR/probe specular all read the perturbed values while ALBEDO/EMISSION
// (territory tint/border/shimmer/hole-rim colors, finalized by raster_path()/circle_path()
// before this block) are never touched, so fills and borders cannot distort. See
// fragment()'s call site for the NORMAL-basis DECISION.
uniform float top_grain_strength : hint_range(0.0, 0.5) = 0.05;
uniform float top_grain_scale : hint_range(0.01, 5.0) = 0.35;
uniform float top_grain_fine_scale : hint_range(1.0, 30.0) = 6.0;
uniform float top_grain_roughness_strength : hint_range(0.0, 1.0) = 0.12;

// -- polished graphite look (roadmap "Textures/materials") ------
// The flat brown read came from the warm sky ambient + reflection probe/SSR
// lighting a dielectric surface at full default strength. disk_ambient_scale
// scales the ambient diffuse term (AO built-in) and disk_specular the
// dielectric F0 (SPECULAR built-in, 0.5 = engine default), so the surface
// stays a dark graphite instead of borrowing the sunset; the sky still shows
// up as a strong fresnel sheen at grazing angles and through the mirror.
// Flat cool graphite fill added as light-independent emission so the disc
// keeps its cool hue whatever colour the sky ambient is (warm sunset ambient
// on a cool albedo is what turned the disc brown).
uniform vec3 disk_fill_color : source_color = vec3(0.045, 0.05, 0.065);
uniform float disk_ambient_scale : hint_range(0.0, 1.0) = 0.35;
uniform float disk_specular : hint_range(0.0, 1.0) = 0.5;
// Procedural machined-panel texture (albedo only, tint/contours untouched):
// square panels of panel_size_m with constant-pixel-width seams and a subtle
// per-panel brightness variation. Seams fade out where panels shrink below
// ~panel_fade_px on screen so distant views never moire.
// Cool sky-coloured fresnel sheen: the graphite picks up a lavender sky
// reflection toward grazing angles (far side of the disc), as in mockup 08.
uniform vec3 disk_sky_sheen_color : source_color = vec3(0.45, 0.42, 0.62);
uniform float disk_sky_sheen_strength : hint_range(0.0, 2.0) = 0.35;
uniform float disk_sky_sheen_power : hint_range(0.5, 10.0) = 3.0;
uniform float panel_size_m = 6.0;
uniform float panel_seam_width_px = 1.0;
uniform float panel_seam_strength : hint_range(0.0, 1.0) = 0.5;
uniform float panel_variation : hint_range(0.0, 0.5) = 0.12;
uniform float panel_fade_px = 12.0;
// Flat, light-independent emissive fill of the territory tint so it reads at
// the same strength in day and night themes.
uniform float tint_fill_emission : hint_range(0.0, 1.0) = 0.12;

#include "res://shaders/include/disc_plating.gdshaderinc"

varying vec3 v_local;

// -- Weather snow --------------------------------------------
// Visual-only snow layer, driven by game/weather/SnowDiscCover.gd through this
// material. snow_strength 0 (the default) leaves the disc exactly as it was.
// Coverage is a soft low-frequency field (domain-warped gradient noise, wide
// smoothstep edges) biased up along plate seams, near the rim and around
// block bases (snow_drift_tex), so drifts gather there first; light snow is
// a faint frosting (snow_strength well below 1), heavy snow soft drifts with
// dark bare disc between them.
uniform float snow_strength = 0.0;
// snow_threshold is the even base depth (0..1) of the cover at the current level;
// snow_variation scales the gentle noise around it.
uniform float snow_threshold = 0.5;
uniform float snow_variation = 0.3;
uniform float snow_scale = 0.12;
// Wind: unit direction on the disc and how many times longer drifts run along
// it than across, so coverage forms streaks and tails rather than round blobs.
uniform vec2 snow_wind_dir = vec2(1.0, 0.0);
uniform float snow_wind_stretch = 4.0;
uniform vec2 snow_offset = vec2(0.0);
uniform float snow_seam_bias = 0.12;
uniform float snow_seam_width = 0.08;
uniform float snow_rim_start = 0.8;
uniform float snow_rim_bias = 0.15;
uniform sampler2D snow_drift_tex : filter_linear, repeat_disable;
uniform float snow_drift_span = 1.0;
uniform float snow_base_bias = 0.25;
uniform float snow_field_radius = 45.0;
uniform vec4 snow_color : source_color = vec4(0.84, 0.86, 0.93, 1.0);
uniform vec4 snow_shade_tint : source_color = vec4(0.55, 0.58, 0.82, 1.0);
uniform float snow_shadow_band = 0.2;
uniform float snow_band_softness = 0.1;
uniform float snow_light_gain = 0.42;
uniform float snow_ambient_factor = 0.6;
// Cel tones inside a drift: depth below snow_tone_mid is the cool shadow
// tone, above snow_tone_lit the lit off-white, between them pale lavender;
// each step is snow_tone_width wide. Only the outermost snow_edge_soft of
// depth fades softly into the bare disc.
uniform vec4 snow_tone_mid : source_color = vec4(0.74, 0.76, 0.9, 1.0);
uniform vec4 snow_tone_shade : source_color = vec4(0.6, 0.63, 0.82, 1.0);
uniform float snow_tone_mid_at = 0.35;
uniform float snow_tone_lit_at = 0.7;
uniform float snow_tone_width = 0.03;
uniform float snow_edge_soft = 0.3;
varying float v_snow;

// Integer lattice hash: exact on every GPU. (A float fract() hash lost
// precision at larger lattice coordinates and gave seams in the snow.)
float snow_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h) * (1.0 / 4294967295.0);
}

float snow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a0 = snow_hash(i) * 6.2831853;
	float a1 = snow_hash(i + vec2(1.0, 0.0)) * 6.2831853;
	float a2 = snow_hash(i + vec2(0.0, 1.0)) * 6.2831853;
	float a3 = snow_hash(i + vec2(1.0, 1.0)) * 6.2831853;
	float g0 = dot(vec2(cos(a0), sin(a0)), f);
	float g1 = dot(vec2(cos(a1), sin(a1)), f - vec2(1.0, 0.0));
	float g2 = dot(vec2(cos(a2), sin(a2)), f - vec2(0.0, 1.0));
	float g3 = dot(vec2(cos(a3), sin(a3)), f - vec2(1.0, 1.0));
	return mix(mix(g0, g1, u.x), mix(g2, g3, u.x), u.y) * 0.7 + 0.5;
}

// Raw snow depth 0..1 at disc-local `point` (before snow_strength).
float snow_coverage(vec2 point) {
	// partial, wind-stretched coverage. The base amount rises
	// with the snow level (gradual build-up); streak noise stretched along the
	// wind leaves thinner patches, and the biases deepen it at seams, the rim
	// and block bases. snow_strength is capped on the CPU so territory shows.
	vec2 p = point * snow_scale + snow_offset;
	vec2 wind_p = vec2(dot(p, snow_wind_dir) / max(snow_wind_stretch, 1.0),
		dot(p, vec2(-snow_wind_dir.y, snow_wind_dir.x)));
	float streaks = snow_noise(wind_p) * 0.65 + snow_noise(wind_p * vec2(1.7, 3.1) + 9.7) * 0.35;
	float depth = snow_threshold + snow_variation * (streaks - 0.5);
	vec2 panel = fract(point / max(panel_size_m, 0.01));
	vec2 seam_d = min(panel, vec2(1.0) - panel);
	depth += snow_seam_bias * (1.0 - smoothstep(0.0, snow_seam_width, min(seam_d.x, seam_d.y)));
	depth += snow_rim_bias * smoothstep(snow_rim_start, 1.0, length(point) / max(snow_field_radius, 0.001));
	depth += snow_base_bias * texture(snow_drift_tex, point / max(snow_drift_span, 0.001) + 0.5).r;
	return clamp(depth, 0.0, 1.0);
}

void vertex() {
	v_local = VERTEX;
}

// Only replaces the DIRECT DirectionalLight3D contribution -- ambient/IBL and the planar
// mirror EMISSION added in fragment() are untouched by defining this. Desaturating
// LIGHT_COLOR toward its own luminance keeps the diffuse term's brightness/shading
// (ATTENUATION, N.L via Godot's own light() call site) while dropping most of the sun's
// warm hue, so the surface's own cool ALBEDO reads through instead of being tinted brown;
// disk_diffuse_response then caps the whole term's energy so the disc doesn't become an
// evenly-lit flat grey either.
void light() {
	float luma = dot(LIGHT_COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cool_light = mix(LIGHT_COLOR.rgb, vec3(luma), disk_diffuse_desaturate);
	vec3 disc_light = ALBEDO * cool_light * ATTENUATION * disk_diffuse_response;
	if (v_snow > 0.0) {
		// snow is cel-lit in three flat bands (cool lavender
		// shadow, mid, lit) instead of the metal's damped response.
		// Lit / shadowed only (the tone bands come from snow depth); NORMAL
		// was flattened for snow in fragment(), so plate seams and grain do
		// not draw lines through it. The band follows the shadow
		// (ATTENUATION), not the low sunset N.L, so cascade transitions do not
		// draw arcs across the snow.
		float facing = step(0.0, dot(NORMAL, LIGHT));
		float lit = facing * smoothstep(snow_shadow_band - snow_band_softness, snow_shadow_band + snow_band_softness, ATTENUATION);
		vec3 band = mix(snow_shade_tint.rgb, vec3(1.0), lit);
		disc_light = mix(disc_light, ALBEDO * band * cool_light * snow_light_gain, v_snow);
	}
	DIFFUSE_LIGHT += disc_light;
}

// The raster (fallback) path.
// Kept whole rather than folded into the analytic path below, because spec
// 3.3's "Bounded cost" asks for a real fallback when the circle list
// overflows, not a best-effort partial draw with some circles silently
// missing.
// moving diagonal stripes for contested/goal areas, faded
// to their mean wherever a stripe gets narrower than ~2 px on screen. At
// gameplay distance the raw 24-stripes-per-metre pattern aliased into a
// zebra moire around the goal flag.
float aa_stripes(float phase) {
	float stripes = 0.5 + 0.5 * sin(phase * TAU);
	return mix(stripes, 0.5, smoothstep(0.25, 0.5, fwidth(phase)));
}

// -- Part 2: cheap hash-based value noise for the top-surface
// brushed/plank grain (see top_grain_* uniforms' own header comment). No
// texture sampling: a single sin()/fract() hash plus a smoothstep-
// interpolated lerp between two integer cells, same "cheap hash noise"
// family a baked texture would use, evaluated directly in this shader.

// Grain "height" at disk-local point `p` -- a coarse, low-frequency "plank"
// band (top_grain_scale) plus a finer, higher-frequency "brushed" ripple
// within it (top_grain_scale * top_grain_fine_scale), both driven by p.x
// only (so the streaks read as long, roughly-parallel lines running along
// local Z, the "brushed metal"/plank look) with a slow, low-frequency
// waviness phase-shifted by p.y so the lines are not perfectly straight
// across the whole disc.
float grain_height(vec2 p) {
	float waviness = value_noise_1d(p.y * 0.04) * 2.0;
	float coarse = value_noise_1d(p.x * top_grain_scale + waviness) - 0.5;
	float fine = value_noise_1d(p.x * top_grain_scale * top_grain_fine_scale + waviness) - 0.5;
	return coarse * 0.7 + fine * 0.3;
}


void raster_path(vec2 uv, vec3 base, out vec3 albedo, out vec3 emission) {
	float owner_near = round(texture(territory_cells, uv).r * 255.0);
	float owner_soft = texture(territory_tex, uv).r * 255.0;
	float state_near = round(texture(territory_state, uv).r * 255.0);
	float state_soft = texture(territory_state_soft, uv).r * 255.0;

	int owner_id = int(owner_near) - 1;
	bool owned = owner_id >= 0;

	float presence = clamp(owner_soft / max(owner_near, 1.0), 0.0, 1.0);
	float coverage = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, presence);
	float tint = owned ? coverage : 0.0;

	vec3 team_color = slot_colors[clamp(owner_id, 0, SLOT_COLOR_MAX - 1)].rgb;
	albedo = mix(base, team_color, tint * tint_alpha);
	emission = team_color * tint * tint_fill_emission;

	float band = 1.0 - smoothstep(0.0, outline_width, abs(presence - 0.5));
	float pulse = mix(
		1.0 - outline_pulse_depth,
		1.0,
		0.5 + 0.5 * sin(TIME * outline_speed * TAU)
	);
	emission += team_color * band * outline_strength * pulse * (owned ? 1.0 : 0.0);

	int state_bits = int(state_near);
	float shimmer_active = ((state_bits & (STATE_CONTESTED | STATE_GOAL_ZONE)) != 0) ? 1.0 : 0.0;
	float shimmer = aa_stripes(
		(uv.x + uv.y) * contested_shimmer_scale - TIME * contested_shimmer_rate
	);
	emission += contested_color.rgb * shimmer_active * shimmer * contested_shimmer_strength;

	float rim = smoothstep(
		float(STATE_HOLE) - hole_rim_width * 2.0, float(STATE_HOLE), state_soft
	);
	emission += hole_rim_color.rgb * rim * hole_rim_glow;
}

// DECISION (shaders/territory/territory.gdshader): bake the circle loop.
// Measured with 300 asleep blocks: uploading only the 2
// home circles cut GPU 16.4 -> 7.6 ms, so the per-pixel circle loop (even
// binned) dominated and scales with pixels (3440x1440 is 2.4x 1080p). The
// loop's three outputs (best value, second-best team value, slot) are a pure
// function of the circle set, which changes at most ~5 Hz. game/
// TerritoryOverlay.gd therefore renders them into a texture with
// territory_circle_bake.gdshader only when the set changes, and this shader
// does two texture reads per pixel. Edge quality: the baked values are the
// continuous signed field (radius - distance, smooth-maxed), so the linear
// filter gives a smooth sub-texel boundary; only the discrete slot is nearest.
// Works identically on host and clients: both feed set_circles(). Pulse,
// shimmer, rim band, goals and the hole discard stay per-pixel and live.
// bake_valid is false (direct loop) until the first bake has rendered and
// whenever no renderer exists.
uniform bool bake_valid = false;
uniform vec2 bake_half_extent = vec2(45.0, 45.0);
uniform sampler2D circle_bake_linear : filter_linear, repeat_disable;
uniform sampler2D circle_bake_near : filter_nearest, repeat_disable;

// The analytic path. `point` is disk-local (x, z).
//
// DECISION (shaders/territory/territory.gdshader): cheap early-out, not a free one.
// Circles are uploaded sorted by team, largest radius first within a team
// (autoload/Match.gd's _update_circle_render()), and once a team's running
// coverage value has cleared metaball_blend + rim_soft_width — comfortably
// past the point where one more circle of the same team could still change
// what gets drawn — every further circle of that team is skipped. This only
// ever saves the arithmetic, not the texel fetch: a data-dependent loop
// bound would need contiguous per-team ranges tracked on the CPU side (an
// index per team, not just a sort) for no measured win at 400 texels, so it
// was not built. Revisit with real profiling numbers if max_shader_circles
// is ever raised well past 400.
// void_g: min(best, second-best team value) in metres, > 0
// where two teams' influence circles overlap (the smooth contested field).
void circle_path(vec2 point, vec3 base, out vec3 albedo, out vec3 emission, out float void_g) {
	float best_overall = -1000000.0;
	float second_best = -1000000.0;
	int owner_team = -1;
	if (bake_valid) {
		// the baked field (see the DECISION above); the
		// linear sampler reconstructs the continuous values, the nearest one the
		// discrete slot.
		vec2 bake_uv = point / (2.0 * bake_half_extent) + vec2(0.5);
		vec2 fields = texture(circle_bake_linear, bake_uv).rg;
		best_overall = (fields.r - 0.5) * 2.0 * BAKE_VALUE_CLAMP_M;
		second_best = (fields.g - 0.5) * 2.0 * BAKE_VALUE_CLAMP_M;
		owner_team = int(round(texture(circle_bake_near, bake_uv).b * OWNER_ENCODE_DIV)) - 1;
	} else {
		circle_field(point, best_overall, second_best, owner_team);
	}
	bool two_teams_inside = best_overall >= 0.0 && second_best >= 0.0;
	void_g = argmax_mode ? -1000000.0 : min(best_overall, second_best);

	// Default (overlap) mode: two or more teams' circles covering the same
	// point is a contest (spec 1.5), drawn with no team tint at all, same as
	// the raster path's CONTESTED cells. argmax_mode (v2, hole_mode == OFF)
	// has no contested concept — TerritoryRaster._argmax() always picks
	// exactly one owner — so it never sets this.
	bool contested = !argmax_mode && two_teams_inside;

	albedo = base;
	emission = vec3(0.0);

	// DECISION: the tint's coverage smoothstep feathers over edge_softness_m (a few cm), not
	// rim_soft_width (0.25 m, the glow band's own property below), so the ownership boundary
	// reads crisp rather than blurred. The `>= -edge_softness_m` gate matches, so tint starts
	// exactly where the smoothstep does rather than up to 0.25 m early.
	// max(..., 0.0001): smoothstep(a, a, x) with a == 0 divides by zero
	// (NaN) in GLSL, and 0.0 is a legal (deliberately "as crisp as
	// possible") edge_softness_m value on the hint_range above.
	float edge_half_width = max(edge_softness_m, 0.0001);
	if (owner_team >= 0 && !contested && best_overall >= -edge_half_width) {
		float coverage = smoothstep(-edge_half_width, edge_half_width, best_overall);
		vec3 team_color = slot_colors[owner_team].rgb;
		albedo = mix(base, team_color, coverage * tint_alpha);
		emission += team_color * coverage * tint_fill_emission;

		float band = 1.0 - smoothstep(0.0, rim_width, abs(best_overall));
		float pulse = mix(
			1.0 - rim_pulse_depth, 1.0, 0.5 + 0.5 * sin(TIME * rim_speed * TAU)
		);
		emission += team_color * band * rim_strength * pulse;
	}

	if (contested) {
		float shimmer = aa_stripes(
			(point.x + point.y) * contested_shimmer_scale
			- TIME * contested_shimmer_rate
		);
		emission += contested_color.rgb * shimmer * contested_shimmer_strength;
	}

	// Goal no-build discs, drawn analytically regardless of team ownership —
	// a goal zone blocks placement, not influence (spec 1.5) — and
	// independent of circles_valid: the goal list is capped at GOAL_MAX and
	// never itself the reason a frame would overflow.
	bool in_goal_zone = false;
	int goal_n = min(goal_count, GOAL_MAX);
	for (int g = 0; g < goal_n; g++) {
		vec4 gc = texelFetch(goal_tex, ivec2(g, 0), 0);
		if (distance(point, gc.xy) <= gc.b) {
			in_goal_zone = true;
			break;
		}
	}
	if (in_goal_zone) {
		float shimmer = aa_stripes(
			(point.x + point.y) * contested_shimmer_scale
			- TIME * contested_shimmer_rate
		);
		emission += contested_color.rgb * shimmer * contested_shimmer_strength;
	}
}


float void_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float void_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(void_hash(i), void_hash(i + vec2(1.0, 0.0)), f.x),
		mix(void_hash(i + vec2(0.0, 1.0)), void_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The void's signed distance (metres, > 0 inside) is the smooth overlap field
// of opposing teams' circles (void_g, the same union boundary the territory
// tints use), cut to the hole cells the raster has actually activated
// (hole_delay, TEMPORARY/PERMANENT/OFF, closing holes all live in that mask),
// so no cell square shows: the edge is the circle boundary wherever it is
// inside an activated cell.
// DECISION: a pixel of a non-hole cell within ~0.3 cell of a hole
// cell may show void where the circles overlap (the smoothed mask threshold),
// and a hole outside any overlap (Jumping Bean, or a permanent hole whose
// contest ended) draws as the rounded bilinear blob of the mask; both stay
// under one cell from the cells the dissolve rule uses.
float void_signed_distance(vec2 uv, float void_g, out float cell_m) {
	cell_m = hole_cell_uv / max(uv_scale, 0.000001);
	vec2 masks = texture(territory_hole, uv).rg;
	float overlap_d = min(void_g, (masks.r - void_overlap_mask_min) * cell_m);
	// The blob only where no contested cell is near: inside a contest the
	// circle boundary alone shapes the edge.
	float blob_d = masks.g < 0.05 ? (masks.r - void_blob_mask_min) * cell_m : -1000000.0;
	return max(overlap_d, blob_d);
}

// The hole pixel's colour: a dark, gently swirling, cel-banded void
// (domain-warped value noise, twisted by depth inside the boundary) with a lit
// rim along the smooth boundary. `depth` is the signed distance in metres.
void hole_void(float depth, float cell_m, vec2 world_xz, out vec3 albedo, out vec3 emission) {
	float rim = 1.0 - smoothstep(0.0, void_rim_width_cells * cell_m, depth);

	float depth_t = 0.0;
	if (void_animated > 0.5) {
		vec2 p = world_xz * void_swirl_scale;
		float t = TIME * void_swirl_speed;
		float ang = void_swirl_twist * (1.0 - clamp(depth / (cell_m * 1.5), 0.0, 1.0)) + t;
		mat2 rot = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang)));
		vec2 q = rot * p;
		float warp = void_noise(q + vec2(t, -t));
		float n = void_noise(q * 1.7 + vec2(warp * 2.0, t));
		float bands = max(float(void_band_count), 1.0);
		float scaled = n * bands;
		float band = floor(scaled);
		band += smoothstep(1.0 - void_band_softness * bands, 1.0, scaled - band);
		depth_t = clamp(band / bands, 0.0, 1.0);
	}
	albedo = void_deep_color.rgb;
	emission = mix(void_deep_color.rgb, void_mid_color.rgb, depth_t * void_mid_amount);
	emission += void_rim_color.rgb * rim * void_rim_glow;
}

void fragment() {
	vec2 uv = v_local.xz * uv_scale + vec2(uv_offset);

	// Spec 2.5: "discards pixels where holes are". Read unfiltered, so the
	// gap is exactly the cell whose collision Field switched off. Holes stay
	// the raster's authority for physical floor in *both* paths — a hole is
	// never an analytic quantity (design note above).
	// The disc collision is solid under a hole, so the pixel is not discarded; it is drawn
	// as an animated void at the very end of fragment() (see hole_void()).
	float void_g = -1000000.0;

	vec3 albedo;
	vec3 emission;
	// Snow composites disc -> snow -> territory: the
	// snow replaces the base albedo the territory tint is mixed onto, and the
	// tint fill, contour, shimmer and hole rim (path emission) stay on top.
	vec3 snow_flat_normal = NORMAL;
	float snow = 0.0;
	vec3 path_base = base_color.rgb;
	// The whole snow block is skipped (uniform branch) when there is no snow;
	// mix(base, tone, 0.0) == base, so dry pixels are unchanged.
	if (snow_strength > 0.0) {
		float snow_depth = snow_coverage(v_local.xz);
		snow = snow_strength * smoothstep(0.0, max(snow_edge_soft, 0.001), snow_depth);
		vec3 snow_tone = mix(snow_tone_shade.rgb, snow_tone_mid.rgb,
			smoothstep(snow_tone_mid_at - snow_tone_width, snow_tone_mid_at + snow_tone_width, snow_depth));
		snow_tone = mix(snow_tone, snow_color.rgb,
			smoothstep(snow_tone_lit_at - snow_tone_width, snow_tone_lit_at + snow_tone_width, snow_depth));
		path_base = mix(base_color.rgb, snow_tone, snow);
	}
	v_snow = snow;
	if (circles_valid) {
		circle_path(v_local.xz, path_base, albedo, emission, void_g);
	} else {
		raster_path(uv, path_base, albedo, emission);
	}
	// Snowy pixels keep the path result: the metal texture, plating, seams,
	// mirror and sheen below belong to the bare disc, not to snow on it.
	vec3 path_albedo = albedo;
	vec3 path_emission = emission;

	// Top-surface brushed/plank grain -- see the
	// top_grain_* uniforms' own header comment. ALBEDO/EMISSION above are
	// already finalized (the territory tint/border/shimmer/hole-rim colors),
	// so this block only ever touches NORMAL/ROUGHNESS, run before the mirror
	// fresnel and disk_sheen blocks below so both read the grained NORMAL.
	//
	// DECISION (shaders/territory/territory.gdshader, part 2): builds its
	// own in-plane basis from MODEL_MATRIX/VIEW_MATRIX instead of the mesh's
	// own TANGENT/BINORMAL -- this disc's CylinderMesh top cap's own
	// generated UV/tangent direction is an implementation detail of Godot's
	// primitive builder (unspecified whether it runs radially or along an
	// axis), whereas the grain's own height field is deliberately sampled in
	// disk-local (v_local.xz) meters so its streak direction is stable and
	// predictable (parallel to local Z) regardless of that mesh detail. For
	// this flat, uniformly-scaled disc, the linear (rotation/uniform-scale,
	// no translation) part of VIEW_MATRIX * MODEL_MATRIX carries a local
	// direction into view space correctly enough for a subtle bump (the
	// final normalize() absorbs any residual scale) without needing a
	// dedicated inverse-transpose normal matrix, which Godot only exposes in
	// vertex(), not fragment().
	vec3 tex_mod = vec3(1.0);
	// procedural cel plating (see proc_plating()). The plate
	// NORMAL itself stays flat (the planar mirror and SSR stay undistorted);
	// only the banded sheen below reads the per-plate tilted normal.
	float proc_seam_occ = 0.0;
	float proc_highlight = 0.0;
	float proc_rough = -1.0;
	float proc_brush = 0.0;
	vec3 proc_plate_n = vec3(0.0, 1.0, 0.0);
	if (disc_procedural) {
		vec3 sun_local = transpose(mat3(MODEL_MATRIX)) * sun_direction;
		vec2 sun2 = length(sun_local.xz) > 0.0001 ? normalize(sun_local.xz) : vec2(1.0, 0.0);
		float proc_tone;
		// Camera height above the disc top (world y difference); the top face
		// is flat, so this is one value across the whole disc.
		float disc_world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float cam_height = max(CAMERA_POSITION_WORLD.y - disc_world_y, 0.0);
		proc_plating(v_local.xz, sun2, cam_height, proc_tone, proc_highlight, proc_seam_occ,
			proc_plate_n, proc_rough, proc_brush);
		tex_mod = proc_tone * disc_proc_base_tint;
		albedo *= tex_mod;
	}

	// Machined panel seams + per-panel brightness (albedo only). Skipped (uniform branch)
	// when both strengths are 0 -- the shipped look -- where every factor below is exactly 1.0.
	if (panel_variation != 0.0 || panel_seam_strength != 0.0) {
		vec2 panel_p = v_local.xz / max(panel_size_m, 0.01);
		vec2 panel_id = floor(panel_p);
		vec2 panel_f = fract(panel_p);
		float panel_rand = fract(sin(dot(panel_id, vec2(12.9898, 78.233))) * 43758.5453);
		albedo *= 1.0 + (panel_rand - 0.5) * 2.0 * panel_variation;
		vec2 seam_d = min(panel_f, vec2(1.0) - panel_f);
		float seam_dist = min(seam_d.x, seam_d.y);
		float panel_px = 1.0 / max(fwidth(seam_dist), 0.0001);
		float seam_fade = smoothstep(panel_fade_px * 0.5, panel_fade_px, panel_px);
		float seam_w = max(fwidth(seam_dist), 0.0001) * panel_seam_width_px;
		float seam_mask = (1.0 - smoothstep(0.0, seam_w, seam_dist)) * seam_fade;
		albedo *= 1.0 - seam_mask * panel_seam_strength;
	}

	float grain_h0 = 0.0;
	if (top_grain_strength > 0.0 || top_grain_roughness_strength > 0.0) {
		vec2 grain_point = v_local.xz;
		float grain_eps = 0.05;
		grain_h0 = grain_height(grain_point);
		float grain_dx = (grain_height(grain_point + vec2(grain_eps, 0.0)) - grain_h0) / grain_eps;
		float grain_dz = (grain_height(grain_point + vec2(0.0, grain_eps)) - grain_h0) / grain_eps;
		if (top_grain_strength > 0.0) {
			mat3 model_view_linear = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
			vec3 grain_x = model_view_linear * vec3(1.0, 0.0, 0.0);
			vec3 grain_z = model_view_linear * vec3(0.0, 0.0, 1.0);
			vec3 base_normal = normalize(NORMAL);
			NORMAL = normalize(
				base_normal
				- grain_x * grain_dx * top_grain_strength
				- grain_z * grain_dz * top_grain_strength
			);
		}
	}

	// The explicit warm-gold sheen: view-dependent mirror reflection, see the disk_sheen_*
	// DECISION above. NORMAL/VIEW are both view-space here (as in the mirror fresnel block);
	// sun_view_dir is the world-space sun_direction transformed into the same space. When the
	// reflected view ray lines up with the sun, this point mirrors the sun toward the camera;
	// the exponent is deliberately low (broad, soft).
	vec3 sheen_normal = normalize(NORMAL);
	vec3 sheen_view = normalize(VIEW);
	vec3 sun_view_dir = normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	vec3 reflected = reflect(-sheen_view, sheen_normal);
	float alignment = clamp(dot(normalize(reflected), sun_view_dir), 0.0, 1.0);
	float sheen = pow(alignment, disk_sheen_exponent);
	emission += disk_sheen_color * disk_sheen_strength * sheen;
	// The flat cool fill carries the texture too, so the pattern reads even
	// where the sky ambient is weak.
	emission += disk_fill_color * tex_mod;
	float sky_fresnel = pow(1.0 - clamp(dot(sheen_normal, sheen_view), 0.0, 1.0), disk_sky_sheen_power);
	emission += disk_sky_sheen_color * disk_sky_sheen_strength * sky_fresnel;
	if (disc_procedural) {
		// DECISION: keep the warm sun lobe continuous across
		// plates. Quantising a sun reflection using each plate's tilted normal
		// paints large tan stair steps at grazing angles. The cool sky lobe still
		// uses those normals and cel bands, preserving the machined facets.
		vec3 plate_view_n = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * proc_plate_n);
		float sun_lobe = pow(alignment, disc_proc_sheen_exponent);
		float sky_lobe = pow(1.0 - clamp(dot(plate_view_n, sheen_view), 0.0, 1.0), disc_proc_sky_sheen_power)
			* disc_proc_sky_sheen_weight;
		float bands = max(float(disc_proc_sheen_bands), 1.0);
		float q = clamp(sky_lobe, 0.0, 1.0) * bands;
		float band = floor(q);
		float band_aa = max(disc_proc_sheen_band_softness, fwidth(q));
		band += smoothstep(1.0 - band_aa, 1.0, q - band);
		float banded_sky = band / bands;
		float sun_weight = sun_lobe / max(sun_lobe + sky_fresnel, 0.0001);
		emission += disc_proc_sheen_strength * (
			mix(disk_sky_sheen_color * banded_sky * (1.0 + proc_brush),
				disc_proc_highlight_color * sun_lobe, sun_weight)
		);
		emission += disc_proc_highlight_color * proc_highlight;
	}

	if (snow > 0.0) {
		// snow <= snow_strength <= 1 - cover_territory_min, so the bare disc
		// (plates, rivets, territory tint) always keeps at least that share.
		albedo = mix(albedo, path_albedo, snow);
		emission = mix(emission, path_emission, snow);
	}
	ALBEDO = albedo;
	EMISSION = emission;
	// "the disc is a mirror-like surface
	// and not glass, so it should be reflective but not transparent": no
	// ALPHA write at all -- the whole disk (including the CylinderMesh's
	// vertical side wall, which shares this one ShaderMaterial) is
	// unconditionally opaque, so every ownership indicator (tint/rim/
	// shimmer/goal) reads at full strength through ALBEDO/EMISSION above with
	// no opacity trick needed.
	METALLIC = base_metallic;
	SPECULAR = disk_specular;
	AO = disk_ambient_scale;
	AO_LIGHT_AFFECT = 0.0;
	// Part 2: grain_h0 (the same coarse+fine grain height the
	// NORMAL perturbation above used, in [-0.5, 0.5]) also nudges ROUGHNESS a
	// little -- a purely additive, sign-symmetric variation so the grain
	// reads as fine streaks in the reflection's sharpness, not a visible
	// overall dulling of the whole disc (top_grain_roughness_strength = 0
	// leaves this identical to the old plain base_roughness assignment).
	ROUGHNESS = clamp(base_roughness + grain_h0 * top_grain_roughness_strength, 0.0, 1.0);
	if (disc_procedural) {
		ROUGHNESS = clamp(proc_rough, 0.0, 1.0);
	}
	if (snow > 0.0) {
		ROUGHNESS = mix(ROUGHNESS, 1.0, snow);
		METALLIC = mix(METALLIC, 0.0, snow);
		SPECULAR = mix(SPECULAR, 0.0, snow);
		AO = mix(AO, AO * snow_ambient_factor, snow);
		NORMAL = normalize(mix(NORMAL, snow_flat_normal, snow));
	}
	float void_cell_m = 0.0;
	float void_d = -1000000.0;
	float void_cover = 0.0;
	// fix2b: void_present (uniform) is false while the
	// uploaded hole mask has no hole cell; the mask then samples 0 everywhere,
	// void_d < 0 and void_cover == 0, so skipping the fetch changes no pixel.
	if (void_present) {
		void_d = void_signed_distance(uv, void_g, void_cell_m);
		// Anti-aliased edge: one pixel of the distance field's own gradient.
		void_cover = smoothstep(0.0, max(fwidth(void_d), 0.0001), void_d);
	}
	if (void_cover > 0.0) {
		// /44: the void replaces everything the bare disc
		// shows (plating, mirror, snow, tint): it must read as a gap.
		vec3 void_albedo;
		vec3 void_emission;
		hole_void(void_d, void_cell_m, v_local.xz, void_albedo, void_emission);
		ALBEDO = mix(ALBEDO, void_albedo, void_cover);
		EMISSION = mix(EMISSION, void_emission, void_cover);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		AO = 1.0;
		NORMAL = snow_flat_normal;
		v_snow = 0.0;
	}
	if (cshadow_a_alpha + cshadow_b_alpha > 0.0) {
		vec3 cs_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float cs = clamp(cshadow_layer(cshadow_tex_a, cshadow_a_m, cshadow_a_alpha, cs_world)
				+ cshadow_layer(cshadow_tex_b, cshadow_b_m, cshadow_b_alpha, cs_world), 0.0, 1.0);
		vec3 cs_tint = mix(vec3(1.0), cshadow_color, cs);
		ALBEDO *= cs_tint;
		EMISSION *= cs_tint;
		// Indirect light and reflections are not scaled by ALBEDO on this mirror-like disc, so
		// the shadow also removes ambient occlusion share and specular.
		AO *= 1.0 - cs;
		SPECULAR *= 1.0 - cs;
	}
	ALBEDO *= 1.0 - wet_darken;
	if (wfog_strength > 0.0) {
		float wfog = clamp((length(VERTEX) - wfog_begin) / max(wfog_end - wfog_begin, 0.001), 0.0, 1.0) * wfog_strength;
		ALBEDO = mix(ALBEDO, vec3(0.0), wfog);
		EMISSION = mix(EMISSION, wfog_color.rgb, wfog);
		METALLIC = mix(METALLIC, 0.0, wfog);
	}
}
