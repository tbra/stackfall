shader_type spatial;
// Bontago-xtq.4 (owner, 2026-09-22: "the map disc looks like glass: a bit
// transparent and reflective") introduced a translucent, blend_mix disk so
// ProceduralSky reflections (Main.tscn's WorldEnvironment) would show on it
// via SPECULAR/METALLIC below.
//
// DECISION (shaders/territory.gdshader, Bontago-xtq.11, owner 2026-09-23:
// "I think the disc is a mirror-like surface and not glass, so it should be
// reflective but not transparent"): retired that translucency entirely.
// fragment() below no longer writes ALPHA at all, so this material is
// compile-time opaque -- not just alpha == 1.0 while still queued as
// transparent. Removing "blend_mix"/"depth_draw_opaque" is safe because a
// shader that never writes ALPHA is opaque by default and always depth-tests
// and depth-writes normally; the old depth_draw_opaque comment's reasoning
// (blocks and the ghost footprint quad depth-testing correctly against the
// disk) no longer applies once the disk itself is not in the transparent
// queue.
// DECISION (shaders/territory.gdshader, Bontago-xtq.20, reproduced by
// tools/screenshot_feel8b_disc_glare.gd): specular_disabled. The "main light
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
// Bontago-adt.2 DECISION: fog_disabled. The sunset depth/volumetric fog (warm
// albedo) was what turned the cool graphite disc top brown (verified: fog off
// gives a neutral near-black surface); the disc keeps its own cool sky sheen
// for atmosphere instead.
render_mode cull_disabled, specular_disabled, fog_disabled;

// Territory on the disk (spec 2.10, 3.3, Bontago-cmc.5).
//
// **Two rendering paths.** Bontago-cmc.5 (owner requirement: "should look
// smooth... some kind of metaballs system") replaces the border itself —
// smoothstepping a bilinearly-upscaled 1 m cell raster can only ever look
// like a blurred grid, never a curve (game/TerritoryOverlay.gd's class doc
// explains why territory_res cannot fix this). The analytic path below draws
// the border as the true union of the disk-local circles
// TerritorySolver/TerritoryGroups actually kept, which is a curve by
// construction. The raster path is kept as the fallback for the one case the
// analytic path cannot bound the cost of: circle_count exceeding
// TerritoryVisuals.max_shader_circles (game/TerritoryOverlay.gd sets
// `circles_valid` to false whenever that happens, or before any circles have
// ever been uploaded).
//
// game/TerritoryOverlay.gd uploads, per raster tick:
//
//   territory_tex          the owner grid (R = team_id + 1, 0 = unowned)
//                          upscaled bilinearly to MapDef.territory_res and
//                          sampled with filter_linear. Only read by the
//                          raster (fallback) path.
//   territory_cells        the same owner grid at cell resolution, unblended.
//                          Only read by the raster (fallback) path.
//   territory_state        STATE_CONTESTED (1) | STATE_HOLE (2) |
//   territory_state_soft   STATE_GOAL_ZONE (4) per cell, at cell resolution,
//                          bound twice. STATE_HOLE is read by *both* paths —
//                          holes are TerritoryRaster's authority for
//                          physical floor (spec 3.3: "Discard floor pixels
//                          only for actual physical holes"), never an
//                          analytic quantity, so the unfiltered sampler's
//                          discard test below is common code. The rest of
//                          this texture (CONTESTED / GOAL_ZONE, and the
//                          filtered hole-rim glow) is only read by the
//                          raster (fallback) path; the analytic path derives
//                          contested/goal-zone visuals straight from the
//                          circle/goal lists instead.
//   circle_tex             one texel per home-anchored circle (Bontago-
//                          cmc.5): R/G = disk-local x/z, B = radius, A =
//                          team id. filter_nearest, read with texelFetch()
//                          so a filtered sample never blends two circles'
//                          rows together.
//   goal_tex               one texel per goal no-build disc: R/G = x/z,
//                          B = radius. Read the same way, independent of
//                          circles_valid — the goal list is always small
//                          (spec 2.2 allows 1-5) and never itself overflows.
//
// Disk-local (x, z) maps to UV with uv_scale / uv_offset, which carry
// CellGrid's convention: cell (0, 0) is the -x/-z corner of the square that
// covers the disk. The analytic path reads v_local.xz directly and needs no
// UV at all; uv is still computed for the raster path and the shimmer's
// travelling-band pattern.

#include "res://shaders/territory_circle_field.gdshaderinc"
// TerritoryRaster's per-cell state bits.
const int STATE_CONTESTED = 1;
const int STATE_HOLE = 2;
const int STATE_GOAL_ZONE = 4;
// Goal discs the analytic path loops; mirrors game/TerritoryOverlay.gd's
// GOAL_TEXELS_MAX. Spec 2.2 allows only 1-5 goal flags, so this is a wire/
// shader safety cap, not a rule.
const int GOAL_MAX = 8;

// Bontago-470.3: weather fog for a fog_disabled surface. Nothing closer than
// wfog_begin metres (view space), wfog_strength at wfog_end; 0 strength = off.
uniform float wfog_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wfog_begin = 30.0;
uniform float wfog_end = 110.0;
uniform vec4 wfog_color : source_color = vec4(0.72, 0.8, 0.88, 1.0);
uniform sampler2D territory_tex : filter_linear, repeat_disable;
uniform sampler2D territory_cells : filter_nearest, repeat_disable;
uniform sampler2D territory_state : filter_nearest, repeat_disable;
uniform sampler2D territory_state_soft : filter_linear, repeat_disable;
// Per-slot colors from MatchConfig.player_colors, already converted to linear
// by TerritoryOverlay; indexed by the owner byte - 1 (raster path) or the
// circle's own team id (analytic path).
uniform vec4 slot_colors[SLOT_COLOR_MAX];

uniform vec4 base_color : source_color = vec4(0.68, 0.70, 0.74, 1.0);
// Defaults match TerritoryVisuals.gd's disk_metallic/disk_roughness
// (Bontago-xtq.20: a glossy dielectric under the planar mirror); only used if TerritoryOverlay never pushes the real
// resource values (it always does in practice -- see refresh_visual_uniforms()).
uniform float base_metallic : hint_range(0.0, 1.0) = 0.1;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.3;

// -- Sun-facing sheen / diffuse cooling (Bontago-mp0.3.8) --------------------
// Owner report: "the disc top reads flat maroon-brown, mockup is dark cool
// graphite/black lacquer with a warm gold sheen gradient toward the sun".
// Main.tscn's DirectionalLight3D is warm (Bontago-mp0.3.6 look pass,
// light_color (1, 0.94, 0.85)) -- deliberately tuned for the blocks and out
// of scope here ("fix in the disc shading ... don't touch game/Main.tscn").
// Godot's default diffuse response multiplies ALBEDO by that warm
// LIGHT_COLOR every frame, which pushes disk_base_color's own cool grey
// (~#23262c) toward brown wherever the top faces the sun -- confirmed:
// disk_base_color is already the correct cool value; only the LIT result was
// wrong. light() below (Godot 4: defining it replaces only the DIRECT
// DirectionalLight3D diffuse/specular pass -- ambient/IBL/the planar mirror
// above are computed elsewhere, untouched) desaturates that light's colour
// toward its own luminance and caps its overall energy, so ambient/mirror/
// the explicit sheen below stay the dominant read instead of a warm-lit
// matte surface.
//
// DECISION (shaders/territory.gdshader, Bontago-mp0.3.8 review pass): the
// first version of disk_sheen_* was a purely POSITION-based gradient
// (disk-local direction from center, dotted with the sun's own horizontal
// direction) -- camera-independent, so it painted the exact same half of the
// disc gold from every angle, which read as a correct sunset gradient in the
// one --face-sun framing it was tuned against but as a flat gold wash (the
// default/player camera happens to look mostly at that same "sun half") or a
// hard diagonal terminator (the default overview framing, whose camera angle
// crosses the gradient boundary) in every other framing. Replaced with a
// genuine VIEW-DEPENDENT specular-style term: reflect() the camera's own
// view ray off the disc's flat NORMAL and compare the result with the sun's
// own direction -- standard mirror optics (this is exactly "would a perfect
// mirror at this point show the sun's reflection to this camera"), so the
// sheen is strong only when the camera is actually positioned to see the
// disc mirror the sun toward it (per-pixel VIEW varies across the surface
// even for one camera, which is what gives the mockup's own broad gradient
// rather than a single infinitesimal hot spot), and naturally falls to
// ~0 when the sun sits behind the camera. disk_sheen_exponent (replacing the
// old disk_sheen_softness) is deliberately LOW (a broad lobe, not a tight
// mirror-sharp highlight) -- a real GGX specular hot spot was already
// rejected on this surface for the DIRECT light (see the render_mode
// DECISION above); this is still a hand-tuned, non-physical falloff shape,
// just now genuinely reflection-driven rather than a fixed position mask.
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
uniform vec3 disk_sheen_color : source_color = vec3(1.0, 0.78, 0.4);
uniform float disk_sheen_strength : hint_range(0.0, 2.0) = 0.6;
uniform float disk_sheen_exponent : hint_range(0.5, 16.0) = 2.5;
uniform float disk_diffuse_response : hint_range(0.0, 1.0) = 0.45;
uniform float disk_diffuse_desaturate : hint_range(0.0, 1.0) = 0.85;

// DECISION (shaders/territory.gdshader, Bontago-xtq.11): the two disk-opacity
// uniforms that used to live here were removed -- fragment() no longer
// writes ALPHA, so the disk is unconditionally opaque now (see the
// render_mode comment above).

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

// -- Analytic circle path uniforms (Bontago-cmc.5) ---------------------------
// False when circle_count is 0 (no solve yet, or a match just ended) or
// exceeds max_shader_circles (spec 3.3, "Bounded cost"): the raster path
// below is drawn instead for that frame.
uniform bool circles_valid = false;
// MatchConfig.HoleMode.OFF: colour by a single-owner argmax over the circle
// list (spec 3.3's v2 alternative) instead of a per-team union + contested
// test.
uniform bool argmax_mode = false;
uniform sampler2D goal_tex : filter_nearest, repeat_disable;
uniform int goal_count = 0;
// Bontago-1pi.11 (owner playtest: "the game slows down a lot after a
// while"): a coarse spatial bin over the circle list, built on the CPU by
// game/TerritoryOverlay.gd's _pack_circle_bins(). Without it every disk pixel
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
// Bontago-xtq.14 (owner: "the edge of the area is a bit blurry, sharpen
// it"): the ownership TINT's own smoothstep used to share rim_soft_width
// with the glow band's coverage gate above -- crisp per docs/original_hover-
// preview.png ("hard-edged shadows/edges"), the rim glow (rim_width/
// rim_strength/rim_pulse_depth/rim_speed below, untouched) stays its own,
// deliberately soft effect. See circle_path()'s own DECISION comment.
uniform float edge_softness_m : hint_range(0.0, 2.0) = 0.03;
uniform float rim_strength = 1.4;
uniform float rim_pulse_depth : hint_range(0.0, 1.0) = 0.45;
uniform float rim_speed = 1.6;

// -- Planar mirror (Bontago-xtq.12 step 2) -----------------------------------
// game/DiscMirror.gd's SubViewport, holding a camera-mirrored-about-the-disk
// render of the scene at the same fov/near/far as the main camera. Sampled
// with SCREEN_UV (X flipped -- see below), the standard planar-reflection
// trick: a shared projection between the two cameras means a given screen
// pixel's mirrored-camera color is the correct reflection for that pixel's
// real-camera ray. Defaults (false / 0.0) match the ReflectionProbe/SSR-only
// look whenever no DiscMirror is wired (every existing
// tests/unit/test_territory_overlay.gd fixture, none of which call
// TerritoryOverlay.set_mirror_texture()).
// source_color (Bontago-xtq.20): the SubViewport holds the mirror camera's
// final, tonemapped sRGB-encoded frame; without the hint the shader read
// those encoded values as linear and the reflection came out washed-out and
// brighter than the scene it mirrors.
uniform sampler2D mirror_tex : source_color, filter_linear;
uniform bool mirror_enabled = false;
uniform float mirror_strength : hint_range(0.0, 1.0) = 0.0;
// Bontago-xtq.20: hue-preserving luminance cap on the sampled mirror color.
// The mirror viewport is LDR (tonemapped, <= 1.0 per channel), so this only
// engages below 1.0 -- it is a safety knob for a clipped white patch (e.g. the
// procedural fallback sky's own sun disc), not the glare fix (see the
// render_mode DECISION above: the glare was the light's specular lobe).
uniform float mirror_max_luminance : hint_range(0.1, 8.0) = 1.35;
// Bontago-mp0.3.2 (owner feedback: "the disc is just a thin mirror
// currently ... a much thicker metallic disc"): the mirror used to blend at
// a flat mirror_strength everywhere, which read as a bright, near-complete
// copy of the whole cloud sky straight down through the disc (the "brownish,
// almost see-through reflection" report) -- there was nothing left to read
// as a dark polished surface under it. fragment() below now scales the
// blended amount by a fresnel term built from the disc's own NORMAL/VIEW:
// mirror_center_fraction is how strong the reflection stays looking straight
// down (a subdued, mostly-albedo graphite/lacquer read), mirror_strength
// (unchanged) is the ceiling it opens up to at a grazing angle near the
// horizon -- exactly where the mockup's warm sunset sheen shows.
uniform float mirror_center_fraction : hint_range(0.0, 1.0) = 0.35;
uniform float mirror_fresnel_power : hint_range(0.1, 8.0) = 2.0;

// Bontago-mp0.3.2: disk_z_scale lets a non-round MapDef.MapShape.OVAL map
// warp this mesh's plain circle into the true ellipse shape_contains() tests
// membership against, entirely inside this shader -- see
// game/TerritoryOverlay.gd's own DECISION beside where it pushes this
// uniform for why VERTEX itself (not just the rendered position) has to be
// the one that is scaled: v_local is read by both the UV math above and the
// analytic circle_path() below, and CellGrid's own square raster/circle
// coordinates are already true disk-local meters (field_radius in x,
// field_radius * oval_aspect in z, not a unit circle later stretched by a
// node transform) -- so v_local has to carry that same already-elliptical
// meaning, not the cylinder's original uniform-radius local space.
uniform float disc_z_scale = 1.0;

// -- Top-surface brushed/plank grain (Bontago-pt.12 part 2, owner: "the dark
// graphite top shows fine plank/brush streaks ... where it interacts with
// the sun (top-right and bottom-centre)"). Cheap hash-based value noise in
// disk-local meters (v_local.xz below) -- no texture sampling, no extra
// render pass, just a handful of extra ALU ops already inside this one
// fragment() call. Perturbs NORMAL/ROUGHNESS only, computed in fragment()
// BEFORE both the mirror block's fresnel term and the disk_sheen block
// below, so the streaks show up exactly where the owner described (the
// explicit sun-sheen term and the mirror/ambient/SSR/probe specular all
// read the perturbed NORMAL/ROUGHNESS already) while staying invisible to
// ALBEDO/EMISSION -- the territory tint/border/shimmer/hole-rim colors
// computed by raster_path()/circle_path() above are already finalized
// before this block runs and are never touched by it, so fills and borders
// cannot distort. See fragment()'s own call site for the NORMAL-basis
// DECISION (why this does not need the mesh's own TANGENT/BINORMAL data).
uniform float top_grain_strength : hint_range(0.0, 0.5) = 0.05;
uniform float top_grain_scale : hint_range(0.01, 5.0) = 0.35;
uniform float top_grain_fine_scale : hint_range(1.0, 30.0) = 6.0;
uniform float top_grain_roughness_strength : hint_range(0.0, 1.0) = 0.12;

// -- Bontago-adt.2: polished graphite look (roadmap "Textures/materials") ------
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

// -- Bontago-adt.2: textured disc top (config/DiscSurfaceDef.gd) -------------
// World-space planar UVs on the disc top. Color is sRGB; normal/roughness/
// metalness are linear data. disc_textured false = the flat look above.
uniform bool disc_textured = false;
uniform sampler2D disc_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D disc_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D disc_roughness_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D disc_metalness_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform float disc_tile_size_m = 6.0;
uniform float disc_rotation_deg = 0.0;
uniform float disc_albedo_strength : hint_range(0.0, 1.0) = 0.5;
uniform float disc_albedo_gain = 1.0;
uniform float disc_albedo_contrast = 1.0;
uniform float disc_normal_strength : hint_range(0.0, 4.0) = 1.0;
uniform float disc_roughness_min : hint_range(0.0, 1.0) = 0.2;
uniform float disc_roughness_max : hint_range(0.0, 1.0) = 0.5;
uniform float disc_metalness_map_mix : hint_range(0.0, 1.0) = 0.0;
uniform float disc_metalness_scale = 1.0;
uniform float disc_detail_fade_px = 96.0;

// -- Bontago-adt.2: procedural cel plating (DiscSurfaceDef.Mode.PROCEDURAL) --
// Concentric rings of plates (plate count per ring grows with radius, random
// per-ring stagger and count jitter, so nothing tiles), crisp constant-pixel
// seams with a sun-facing lip, toon rivets, banded per-plate sheen. Detail
// fades with the camera's height above the disc (rivets first, then seams),
// uniformly across the whole disc, leaving a calm glossy disc from high up;
// a small per-pixel guard drops only sub-pixel detail at the grazing horizon. See proc_plating() below; the values are
// pushed from config/DiscSurfaceDef.gd by game/TerritoryOverlay.gd.
uniform bool disc_procedural = false;
uniform vec3 disc_proc_base_tint = vec3(0.14, 0.155, 0.25);
uniform float disc_proc_hub_radius_m = 3.5;
uniform float disc_proc_ring_width_m = 4.5;
uniform float disc_proc_plate_length_m = 5.0;
uniform float disc_proc_plate_count_jitter = 0.3;
uniform float disc_proc_split_chance = 0.3;
uniform float disc_proc_tone_variation = 0.12;
uniform float disc_proc_hatch_chance = 0.06;
uniform float disc_proc_hatch_inset_m = 0.7;
uniform float disc_proc_hatch_tone = 0.88;
uniform float disc_proc_seam_width_px = 1.3;
uniform float disc_proc_seam_darkness = 0.85;
uniform float disc_proc_lip_width_px = 1.2;
uniform float disc_proc_lip_strength = 0.35;
uniform float disc_proc_lip_highlight = 0.07;
uniform float disc_proc_seam_reflection_occlusion = 0.6;
uniform float disc_proc_rivet_radius_m = 0.085;
uniform float disc_proc_rivet_spacing_m = 0.32;
uniform float disc_proc_rivet_inset_m = 0.3;
uniform float disc_proc_rivet_row_spacing_m = 0.75;
// Pattern weights: none, corner pairs, 2x2 corner clusters, edge rows.
uniform vec4 disc_proc_rivet_weights = vec4(0.1, 0.35, 0.35, 0.2);
uniform float disc_proc_rivet_tone = 2.4;
uniform float disc_proc_rivet_highlight = 0.14;
uniform float disc_proc_rivet_shadow = 0.75;
uniform float disc_proc_rivet_shade = 0.35;
uniform float disc_proc_rivet_shadow_offset = 0.6;
uniform vec3 disc_proc_highlight_color : source_color = vec3(1.0, 0.84, 0.62);
uniform float disc_proc_plate_tilt = 0.08;
uniform float disc_proc_sheen_strength = 0.08;
uniform float disc_proc_sky_sheen_power = 4.0;
uniform float disc_proc_sky_sheen_weight = 0.8;
uniform float disc_proc_sheen_exponent = 4.0;
uniform int disc_proc_sheen_bands = 3;
uniform float disc_proc_sheen_band_softness = 0.15;
uniform float disc_proc_brush_strength = 0.35;
uniform float disc_proc_brush_scale_m = 0.05;
uniform float disc_proc_roughness = 0.22;
uniform float disc_proc_roughness_variation = 0.08;
// Bontago-adt.2 (owner follow-up): detail fades with the camera's HEIGHT
// above the disc top only, so the whole disc fades in and out together.
uniform float disc_proc_rivet_fade_height_start_m = 14.0;
uniform float disc_proc_rivet_fade_height_end_m = 22.0;
uniform float disc_proc_seam_fade_height_start_m = 24.0;
uniform float disc_proc_seam_fade_height_end_m = 40.0;
// Per-pixel anti-alias guard only (not a distance fade): detail smaller than
// this on screen is dropped so grazing horizon pixels never moire.
uniform float disc_proc_aa_rivet_min_px = 1.5;
uniform float disc_proc_aa_plate_min_px = 6.0;
uniform float disc_proc_brush_fade_px = 3.0;

varying vec3 v_local;

// -- Weather snow (Bontago-22y.6) --------------------------------------------
// Visual-only snow layer, driven by vfx/weather/SnowDiscCover.gd through this
// material. snow_strength 0 (the default) leaves the disc exactly as it was.
// Coverage is a soft low-frequency field (domain-warped gradient noise, wide
// smoothstep edges) biased up along plate seams, near the rim and around
// block bases (snow_drift_tex), so drifts gather there first; light snow is
// a faint frosting (snow_strength well below 1), heavy snow soft drifts with
// dark bare disc between them.
uniform float snow_strength = 0.0;
uniform float snow_threshold = 0.5;
uniform float snow_softness = 0.14;
uniform float snow_scale = 0.12;
uniform float snow_warp = 0.9;
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
	vec2 p = point * snow_scale + snow_offset;
	vec2 warp = vec2(snow_noise(p * 0.6 + 5.2), snow_noise(p * 0.6 + 1.3)) - 0.5;
	p += warp * snow_warp;
	float field = snow_noise(p) * 0.65 + snow_noise(p * 2.1 + 17.1) * 0.35;
	vec2 panel = fract(point / max(panel_size_m, 0.01));
	vec2 seam_d = min(panel, vec2(1.0) - panel);
	// Seams only gather snow next to a drift (not as a grid over bare disc).
	float near_drift = smoothstep(snow_threshold - 2.0 * snow_softness, snow_threshold, field);
	field += snow_seam_bias * near_drift * (1.0 - smoothstep(0.0, snow_seam_width, min(seam_d.x, seam_d.y)));
	field += snow_rim_bias * smoothstep(snow_rim_start, 1.0, length(point) / max(snow_field_radius, 0.001));
	field += snow_base_bias * texture(snow_drift_tex, point / max(snow_drift_span, 0.001) + 0.5).r;
	return smoothstep(snow_threshold - snow_softness, snow_threshold + snow_softness, field);
}

void vertex() {
	vec3 local = VERTEX;
	local.z *= disc_z_scale;
	VERTEX = local;
	v_local = local;
}

// Bontago-mp0.3.8 problem 1 (see the disk_diffuse_* uniforms' own DECISION
// above): only replaces the DIRECT DirectionalLight3D contribution --
// ambient/IBL and the planar mirror EMISSION added in fragment() below are
// untouched by defining this. Desaturating LIGHT_COLOR toward its own
// luminance keeps the diffuse term's brightness/shading (ATTENUATION,
// N.L via Godot's own light() call site) while dropping most of the sun's
// warm hue, so the surface's own cool ALBEDO reads through instead of being
// tinted brown; disk_diffuse_response then caps the whole term's energy so
// the disc doesn't just become an evenly-lit flat grey either.
void light() {
	float luma = dot(LIGHT_COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cool_light = mix(LIGHT_COLOR.rgb, vec3(luma), disk_diffuse_desaturate);
	vec3 disc_light = ALBEDO * cool_light * ATTENUATION * disk_diffuse_response;
	if (v_snow > 0.0) {
		// Bontago-22y.6: snow is cel-lit in three flat bands (cool lavender
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

// The raster (fallback) path: exactly Bontago-cmc.7's shader, unchanged.
// Kept whole rather than folded into the analytic path below, because spec
// 3.3's "Bounded cost" asks for a real fallback when the circle list
// overflows, not a best-effort partial draw with some circles silently
// missing.
// Bontago-mp0.3.6: moving diagonal stripes for contested/goal areas, faded
// to their mean wherever a stripe gets narrower than ~2 px on screen. At
// gameplay distance the raw 24-stripes-per-metre pattern aliased into a
// zebra moire around the goal flag.
float aa_stripes(float phase) {
	float stripes = 0.5 + 0.5 * sin(phase * TAU);
	return mix(stripes, 0.5, smoothstep(0.25, 0.5, fwidth(phase)));
}

// -- Bontago-pt.12 part 2: cheap hash-based value noise for the top-surface
// brushed/plank grain (see top_grain_* uniforms' own header comment). No
// texture sampling: a single sin()/fract() hash plus a smoothstep-
// interpolated lerp between two integer cells, same "cheap hash noise"
// family game/DiscBody.gd's own procedural texture used, just evaluated
// directly in this shader instead of baked into a texture.
float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}

float value_noise_1d(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = hash11(i);
	float b = hash11(i + 1.0);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

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

// -- Bontago-adt.2: procedural cel plating -----------------------------------
// Fixed toon shape constants (the look's geometry, not tunables): where the
// lit/shaded crescents start on a rivet dome (dot with the sun, -1..1), the
// catchlight's offset/radius as fractions of the rivet radius, and the
// facing range over which a seam lip turns from shaded to lit.
const float PROC_RIVET_CRESCENT = 0.45;
const float PROC_GLINT_OFFSET = 0.35;
const float PROC_GLINT_RADIUS = 0.22;
const float PROC_LIP_FACING_RAMP = 0.3;
// Sine-free hash (hash12 by Dave Hoskins) of a small integer plate id + salt;
// no precision loss for the id range used here.
float proc_hash(vec2 id, float salt) {
	vec3 p3 = fract(vec3(id.x, id.y, salt) * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// One toon rivet. `o` = offset of this pixel from the rivet centre (disc-local
// metres), `sun2` = horizontal direction toward the sun, `fw` = metres per
// pixel. Multiplies tone and adds to highlight.
void proc_rivet(vec2 o, vec2 sun2, float fw, float fade, inout float tone, inout float highlight) {
	float radius = max(disc_proc_rivet_radius_m, 0.001);
	float d = length(o);
	float body = 1.0 - smoothstep(radius - fw * 0.5, radius + fw * 0.5, d);
	vec2 shadow_o = o + sun2 * radius * disc_proc_rivet_shadow_offset;
	float cast_shadow = (1.0 - body)
		* (1.0 - smoothstep(radius - fw * 0.5, radius + fw * 0.5, length(shadow_o)));
	// Dome facing: -1 on the side away from the sun, +1 toward it. Crisp toon
	// thresholds, anti-aliased over about one pixel (fw / radius here).
	// Three toon tones on the head: a lit crescent toward the sun, a shaded
	// crescent away from it and the plain mid-tone cap between them, plus a
	// small catchlight dot on the lit side so the head reads as a dome.
	float facing = dot(o / radius, sun2);
	float aa = clamp(fw / radius, 0.02, 1.0);
	float lit = smoothstep(PROC_RIVET_CRESCENT - aa, PROC_RIVET_CRESCENT + aa, facing) * body;
	float shaded = smoothstep(PROC_RIVET_CRESCENT - aa, PROC_RIVET_CRESCENT + aa, -facing) * body;
	vec2 glint_o = o / radius - sun2 * PROC_GLINT_OFFSET;
	float glint = (1.0 - smoothstep(PROC_GLINT_RADIUS - aa, PROC_GLINT_RADIUS + aa, length(glint_o))) * body;
	// Thin dark toon outline around the head (the seam line width).
	float outline_w = 0.5 * disc_proc_seam_width_px * fw;
	float outline = 1.0 - smoothstep(outline_w - 0.5 * fw, outline_w + 0.5 * fw, abs(d - radius));
	tone *= mix(1.0, disc_proc_rivet_tone, body * fade);
	tone *= 1.0 - shaded * disc_proc_rivet_shade * fade;
	tone *= 1.0 - clamp(cast_shadow + outline, 0.0, 1.0) * disc_proc_rivet_shadow * fade;
	highlight += (lit + glint) * disc_proc_rivet_highlight * fade;
}

// Seam line + sun-facing lip for a groove `d` metres from this pixel;
// `into_plate` = unit direction from the groove toward the pixel. Width is
// constant in screen pixels (fwidth), like the block cell-grid seams.
void proc_groove(float d, vec2 into_plate, vec2 sun2, float fade, inout float tone, inout float highlight, inout float seam_occ) {
	float fw = max(fwidth(d), 0.00001);
	float half_w = 0.5 * disc_proc_seam_width_px * fw;
	float seam = 1.0 - smoothstep(half_w - 0.5 * fw, half_w + 0.5 * fw, d);
	float lip_end = half_w + disc_proc_lip_width_px * fw;
	float lip = smoothstep(half_w - 0.5 * fw, half_w + 0.5 * fw, d)
		* (1.0 - smoothstep(lip_end - 0.5 * fw, lip_end + 0.5 * fw, d));
	// The plate edge beside a groove faces back toward the groove: lit when
	// that points at the sun, in shade when it points away.
	float edge_facing = dot(-into_plate, sun2);
	float lip_lit = smoothstep(0.0, PROC_LIP_FACING_RAMP, edge_facing);
	float lip_shade = smoothstep(0.0, PROC_LIP_FACING_RAMP, -edge_facing);
	tone *= 1.0 - seam * disc_proc_seam_darkness * fade;
	tone *= 1.0 - lip * lip_shade * disc_proc_lip_strength * fade;
	highlight += lip * lip_lit * disc_proc_lip_highlight * fade;
	seam_occ = max(seam_occ, seam * fade);
}

// The plating at disc-local point p (x, z): an albedo/fill multiplier, an
// additive highlight amount, a seam mask for the reflection, the per-plate
// sheen normal (disc-local), roughness and the brushed-streak value.
void proc_plating(vec2 p, vec2 sun2, float cam_height, out float tone, out float highlight, out float seam_occ,
		out vec3 plate_n, out float rough, out float brush) {
	tone = 1.0;
	highlight = 0.0;
	seam_occ = 0.0;
	float m_per_px = max(max(length(dFdx(p)), length(dFdy(p))), 0.00001);
	// Height fade: one value for the whole disc (camera height above the top).
	float seam_height_fade = 1.0 - smoothstep(
		disc_proc_seam_fade_height_start_m, disc_proc_seam_fade_height_end_m, cam_height);
	float rivet_height_fade = 1.0 - smoothstep(
		disc_proc_rivet_fade_height_start_m, disc_proc_rivet_fade_height_end_m, cam_height);
	// Anti-alias guard: drops only genuinely sub-resolution detail (plates a
	// few pixels across, sub-pixel rivets), i.e. the grazing horizon band.
	float plate_px = disc_proc_plate_length_m / m_per_px;
	float rivet_px = 2.0 * disc_proc_rivet_radius_m / m_per_px;
	float seam_fade = seam_height_fade
		* smoothstep(0.5 * disc_proc_aa_plate_min_px, disc_proc_aa_plate_min_px, plate_px);
	float rivet_fade = rivet_height_fade * seam_fade
		* smoothstep(0.5 * disc_proc_aa_rivet_min_px, disc_proc_aa_rivet_min_px, rivet_px);

	float r = max(length(p), 0.0001);
	vec2 r_hat = p / r;
	vec2 t_hat = vec2(-r_hat.y, r_hat.x);
	float hub = max(disc_proc_hub_radius_m, 0.0);
	float ring_w = max(disc_proc_ring_width_m, 0.1);

	vec2 plate_id = vec2(-1.0, 0.0);
	float u_c = p.x;
	float v_c = p.y;
	float half_u = 0.0;
	float half_v = 0.0;
	bool is_hub = r < hub;
	// Groove distance/direction and the hatch field are computed without
	// divergent branches around the derivative calls (fwidth in proc_groove),
	// so screen-space widths stay valid across plate and hub boundaries.
	float d_seam = hub - r;
	vec2 into_seam = -r_hat;
	float hatch_sd = 1000.0;
	vec2 hatch_grad = r_hat;
	if (!is_hub) {
		float ring = floor((r - hub) / ring_w);
		float r_in = hub + ring * ring_w;
		float circumference = TAU * (r_in + 0.5 * ring_w);
		float jitter = (proc_hash(vec2(ring, 0.0), 1.0) - 0.5) * 2.0 * disc_proc_plate_count_jitter;
		float count = max(3.0, round(circumference / max(disc_proc_plate_length_m, 0.1) * (1.0 + jitter)));
		float stagger = proc_hash(vec2(ring, 0.0), 2.0);
		// Integer count: the atan() wrap at +-PI shifts s by exactly `count`,
		// so fract(s) and mod(floor(s), count) stay continuous across it.
		float s = atan(p.y, p.x) / TAU * count + stagger;
		float plate = mod(floor(s), count);
		half_u = PI * r / count;
		u_c = (fract(s) - 0.5) * 2.0 * half_u;
		half_v = 0.5 * ring_w;
		v_c = r - (r_in + half_v);
		plate_id = vec2(ring, plate);
		if (proc_hash(plate_id, 3.0) < disc_proc_split_chance) {
			// Split lengthwise into an inner and an outer strip.
			float outer = v_c > 0.0 ? 1.0 : 0.0;
			half_v *= 0.5;
			v_c -= (outer * 2.0 - 1.0) * half_v;
			plate_id.y += 1000.0 * (outer + 1.0);
		}
		float d_u = half_u - abs(u_c);
		float d_v = half_v - abs(v_c);
		d_seam = min(d_u, d_v);
		into_seam = d_u < d_v ? -sign(u_c) * t_hat : -sign(v_c) * r_hat;
		// Access hatch: an inset groove loop with a slightly different cover.
		float inset = disc_proc_hatch_inset_m;
		if (proc_hash(plate_id, 4.0) < disc_proc_hatch_chance
			&& half_u > 2.0 * inset && half_v > 1.5 * inset) {
			vec2 q = vec2(abs(u_c) - (half_u - inset), abs(v_c) - (half_v - inset));
			hatch_sd = max(q.x, q.y);
			hatch_grad = q.x > q.y ? sign(u_c) * t_hat : sign(v_c) * r_hat;
		}
	}
	float fw_sd = max(fwidth(hatch_sd), 0.00001);
	tone *= mix(1.0, disc_proc_hatch_tone, (1.0 - smoothstep(-fw_sd, fw_sd, hatch_sd)) * seam_fade);
	if (abs(hatch_sd) < d_seam) {
		d_seam = abs(hatch_sd);
		into_seam = (hatch_sd > 0.0 ? 1.0 : -1.0) * hatch_grad;
	}
	proc_groove(d_seam, into_seam, sun2, seam_fade, tone, highlight, seam_occ);

	// Rivets: one pattern per plate, chosen by disc_proc_rivet_weights.
	if (rivet_fade > 0.0) {
		float inset = disc_proc_rivet_inset_m;
		float spacing = disc_proc_rivet_spacing_m;
		if (is_hub) {
			float ring_r = hub - inset;
			if (ring_r > inset) {
				float n = max(3.0, floor(TAU * ring_r / max(disc_proc_rivet_row_spacing_m, 0.05)));
				float ang = round(atan(p.y, p.x) / TAU * n) / n * TAU;
				proc_rivet(p - vec2(cos(ang), sin(ang)) * ring_r, sun2, m_per_px, rivet_fade, tone, highlight);
			}
		} else {
			vec4 w = max(disc_proc_rivet_weights, vec4(0.0));
			float pick = proc_hash(plate_id, 5.0) * max(w.x + w.y + w.z + w.w, 0.0001);
			// Folded corner coordinates: distance from the nearest plate corner
			// along each edge; dir_a/dir_b point into the plate.
			float a = half_u - abs(u_c);
			float b = half_v - abs(v_c);
			vec2 dir_a = -sign(u_c) * t_hat;
			vec2 dir_b = -sign(v_c) * r_hat;
			bool any_rivet = true;
			vec2 o = vec2(0.0);
			if (pick < w.x) {
				any_rivet = false;
			} else if (pick < w.x + w.y) {
				float ka = clamp(round((a - inset) / spacing), 0.0, 1.0);
				o = dir_a * (inset + ka * spacing - a) + dir_b * (inset - b);
			} else if (pick < w.x + w.y + w.z) {
				float ka = clamp(round((a - inset) / spacing), 0.0, 1.0);
				float kb = clamp(round((b - inset) / spacing), 0.0, 1.0);
				o = dir_a * (inset + ka * spacing - a) + dir_b * (inset + kb * spacing - b);
			} else {
				float span = max(2.0 * (half_u - inset), 0.0);
				float n = max(1.0, floor(span / max(disc_proc_rivet_row_spacing_m, 0.05)));
				float step_u = span / n;
				float k = clamp(round((u_c + half_u - inset) / max(step_u, 0.0001)), 0.0, n);
				float cu = -half_u + inset + k * step_u;
				o = t_hat * (cu - u_c) + dir_b * (inset - b);
			}
			// o above points from the pixel to the rivet; proc_rivet wants the
			// pixel's offset from the rivet centre.
			if (any_rivet) {
				proc_rivet(-o, sun2, m_per_px, rivet_fade, tone, highlight);
			}
		}
	}

	tone *= 1.0 + (proc_hash(plate_id, 6.0) - 0.5) * 2.0 * disc_proc_tone_variation * seam_fade;
	vec2 tilt = (vec2(proc_hash(plate_id, 7.0), proc_hash(plate_id, 8.0)) - 0.5)
		* 2.0 * disc_proc_plate_tilt * seam_fade;
	plate_n = normalize(vec3(tilt.x, 1.0, tilt.y));

	// Brushed streaks along or across each plate (sheen/roughness only).
	float brush_coord = proc_hash(plate_id, 9.0) < 0.5 ? u_c : v_c;
	float scale = max(disc_proc_brush_scale_m, 0.001);
	float brush_fade = smoothstep(disc_proc_brush_fade_px, 2.0 * disc_proc_brush_fade_px, scale / m_per_px);
	brush = (value_noise_1d(brush_coord / scale + proc_hash(plate_id, 10.0) * 97.0) - 0.5)
		* 2.0 * disc_proc_brush_strength * brush_fade;
	rough = disc_proc_roughness
		+ (proc_hash(plate_id, 11.0) - 0.5) * 2.0 * disc_proc_roughness_variation * seam_fade
		+ brush * disc_proc_roughness_variation;
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
	// Bontago-xtq.11: no alpha_boost anymore -- the disk is opaque outright,
	// so tint/band/shimmer/rim already read at full strength through ALBEDO/
	// EMISSION with no opacity trick needed.
}

// DECISION (shaders/territory.gdshader, Bontago-1pi.11.1): bake the circle loop.
// Measured (tools/bench_perf_attrib, 300 asleep blocks): uploading only the 2
// home circles cut GPU 16.4 -> 7.6 ms, so the per-pixel circle loop (even
// binned) dominated and scales with pixels (3440x1440 is 2.4x 1080p). The
// loop's three outputs (best value, second-best team value, owner) are a pure
// function of the circle set, which changes at most ~5 Hz. game/
// TerritoryOverlay.gd therefore renders them into a texture with
// territory_circle_bake.gdshader only when the set changes, and this shader
// does two texture reads per pixel. Edge quality: the baked values are the
// continuous signed field (radius - distance, smooth-maxed), so the linear
// filter gives a smooth sub-texel boundary; only the discrete owner is nearest.
// Works identically on host and clients: both feed set_circles(). Pulse,
// shimmer, rim band, goals and the hole discard stay per-pixel and live.
// bake_valid is false (direct loop) until the first bake has rendered and
// whenever no renderer exists.
uniform bool bake_valid = false;
uniform vec2 bake_half_extent = vec2(45.0, 45.0);
uniform sampler2D circle_bake_linear : filter_linear, repeat_disable;
uniform sampler2D circle_bake_near : filter_nearest, repeat_disable;

// The analytic path (Bontago-cmc.5). `point` is disk-local (x, z).
//
// DECISION (shaders/territory.gdshader): cheap early-out, not a free one.
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
void circle_path(vec2 point, vec3 base, out vec3 albedo, out vec3 emission) {
	float best_overall = -1000000.0;
	float second_best = -1000000.0;
	int owner_team = -1;
	if (bake_valid) {
		// Bontago-1pi.11.1: the baked field (see the DECISION above); the
		// linear sampler reconstructs the continuous values, the nearest one the
		// discrete owner.
		vec2 bake_uv = point / (2.0 * bake_half_extent) + vec2(0.5);
		vec2 fields = texture(circle_bake_linear, bake_uv).rg;
		best_overall = (fields.r - 0.5) * 2.0 * BAKE_VALUE_CLAMP_M;
		second_best = (fields.g - 0.5) * 2.0 * BAKE_VALUE_CLAMP_M;
		owner_team = int(round(texture(circle_bake_near, bake_uv).b * OWNER_ENCODE_DIV)) - 1;
	} else {
		circle_field(point, best_overall, second_best, owner_team);
	}
	bool two_teams_inside = best_overall >= 0.0 && second_best >= 0.0;

	// Default (overlap) mode: two or more teams' circles covering the same
	// point is a contest (spec 2.2), drawn with no team tint at all, same as
	// the raster path's CONTESTED cells. argmax_mode (v2, hole_mode == OFF)
	// has no contested concept — TerritoryRaster._argmax() always picks
	// exactly one owner — so it never sets this.
	bool contested = !argmax_mode && two_teams_inside;

	albedo = base;
	emission = vec3(0.0);

	// DECISION (shaders/territory.gdshader, Bontago-xtq.14): the tint's own
	// coverage smoothstep now feathers over edge_softness_m (a few cm
	// default), not rim_soft_width (still 0.25 m, the glow band's own
	// property below) -- the two used to be the same value, which is what
	// made the ownership boundary itself read as blurred rather than the rim
	// glow around it. The `>= -edge_softness_m` gate matches, so tint starts
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
	// a goal zone blocks placement, not influence (spec 2.2) — and
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
	// Bontago-xtq.11: no alpha_boost anymore -- the disk is opaque outright,
	// so the tint, rim, contested shimmer and goal-zone shimmer above already
	// read at full strength through ALBEDO/EMISSION with no opacity trick
	// needed.
}

void fragment() {
	vec2 uv = v_local.xz * uv_scale + vec2(uv_offset);

	// Spec 3.3: "discards pixels where holes are". Read unfiltered, so the
	// gap is exactly the cell whose collision Field switched off. Holes stay
	// the raster's authority for physical floor in *both* paths — a hole is
	// never an analytic quantity (design note above).
	float state_near = round(texture(territory_state, uv).r * 255.0);
	if ((int(state_near) & STATE_HOLE) != 0) {
		discard;
	}

	vec3 albedo;
	vec3 emission;
	// Bontago-22y.6: weather snow composites disc -> snow -> territory: the
	// snow replaces the base albedo the territory tint is mixed onto, and the
	// tint fill, contour, shimmer and hole rim (path emission) stay on top.
	vec3 snow_flat_normal = NORMAL;
	float snow_depth = snow_strength > 0.0 ? snow_coverage(v_local.xz) : 0.0;
	float snow = snow_strength * smoothstep(0.0, max(snow_edge_soft, 0.001), snow_depth);
	v_snow = snow;
	vec3 snow_tone = mix(snow_tone_shade.rgb, snow_tone_mid.rgb,
		smoothstep(snow_tone_mid_at - snow_tone_width, snow_tone_mid_at + snow_tone_width, snow_depth));
	snow_tone = mix(snow_tone, snow_color.rgb,
		smoothstep(snow_tone_lit_at - snow_tone_width, snow_tone_lit_at + snow_tone_width, snow_depth));
	vec3 path_base = mix(base_color.rgb, snow_tone, snow);
	if (circles_valid) {
		circle_path(v_local.xz, path_base, albedo, emission);
	} else {
		raster_path(uv, path_base, albedo, emission);
	}
	// Snowy pixels keep the path result: the metal texture, plating, seams,
	// mirror and sheen below belong to the bare disc, not to snow on it.
	vec3 path_albedo = albedo;
	vec3 path_emission = emission;

	// Bontago-pt.12 part 2: top-surface brushed/plank grain -- see the
	// top_grain_* uniforms' own header comment. ALBEDO/EMISSION above are
	// already finalized (the territory tint/border/shimmer/hole-rim colors),
	// so this block only ever touches NORMAL/ROUGHNESS, run before the mirror
	// fresnel and disk_sheen blocks below so both read the grained NORMAL.
	//
	// DECISION (shaders/territory.gdshader, Bontago-pt.12 part 2): builds its
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
	// Bontago-adt.2: textured top (planar world-space UVs).
	vec3 tex_mod = vec3(1.0);
	float tex_rough = -1.0;
	float tex_metal = -1.0;
	if (disc_textured) {
		float rot = radians(disc_rotation_deg);
		mat2 rot_m = mat2(vec2(cos(rot), -sin(rot)), vec2(sin(rot), cos(rot)));
		vec2 tex_uv = rot_m * (v_local.xz / max(disc_tile_size_m, 0.01));
		float px_per_tile = 1.0 / max(length(fwidth(tex_uv)), 0.00001);
		float detail = smoothstep(disc_detail_fade_px * 0.5, disc_detail_fade_px, px_per_tile);
		vec3 tex_col = texture(disc_albedo_tex, tex_uv).rgb;
		tex_mod = mix(vec3(1.0), pow(tex_col, vec3(disc_albedo_contrast)) * disc_albedo_gain, disc_albedo_strength * detail);
		albedo *= tex_mod;
		tex_rough = mix(0.5, texture(disc_roughness_tex, tex_uv).r, detail);
		tex_metal = mix(0.5, texture(disc_metalness_tex, tex_uv).r, detail);
		vec3 n_ts = texture(disc_normal_tex, tex_uv).xyz * 2.0 - 1.0;
		vec2 grad_uv = vec2(n_ts.x, -n_ts.y) * disc_normal_strength * detail;
		// Back from texture space to disc-local xz (undo the rotation).
		vec2 grad_local = vec2(dot(grad_uv, rot_m[0]), dot(grad_uv, rot_m[1]));
		vec3 local_n = normalize(vec3(grad_local.x, max(n_ts.z, 0.2), grad_local.y));
		NORMAL = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * local_n);
	}
	// Bontago-adt.2: procedural cel plating (see proc_plating()). The plate
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

	// Bontago-adt.2: machined panel seams + per-panel brightness (albedo only).
	{
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

	// Bontago-xtq.12 step 2: the planar mirror, where it is wired and
	// enabled, blends mirror_strength of the true per-pixel reflection over
	// the disk (see the Bontago-xtq.20 DECISION inside the branch for how).
	if (mirror_enabled) {
		// game/DiscMirror.gd's own mirror_transform() DECISION comment: its
		// camera basis is deliberately proper (not a raw per-axis
		// reflection), which keeps triangle winding/culling correct but
		// renders the true mirror image flipped left-right -- flipping X
		// here undoes exactly that, so this samples the correct final image.
		vec3 mirror_color = texture(mirror_tex, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)).rgb;
		// Bontago-xtq.20: hue-preserving luminance cap -- see
		// mirror_max_luminance's own doc above.
		float mirror_luma = dot(mirror_color, vec3(0.2126, 0.7152, 0.0722));
		if (mirror_luma > mirror_max_luminance) {
			mirror_color *= mirror_max_luminance / max(mirror_luma, 0.0001);
		}
		// Bontago-mp0.3.2: fresnel-scaled blend amount -- see the
		// mirror_center_fraction/mirror_fresnel_power uniforms' own DECISION
		// above. NORMAL/VIEW are both view-space here (Godot spatial
		// fragment() built-ins), so this needs no extra transform.
		float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float fresnel = pow(1.0 - ndotv, mirror_fresnel_power);
		float mirror_amount = clamp(
			mix(mirror_strength * mirror_center_fraction, mirror_strength, fresnel), 0.0, 1.0
		);
		// DECISION (shaders/territory.gdshader, Bontago-xtq.20): the mirror is
		// composited as the surface's reflected light -- the lit albedo is
		// scaled down by the reflected fraction and the mirror image is added
		// as EMISSION (it is already a fully lit render, so it must not be lit
		// a second time). It used to be mixed into ALBEDO under METALLIC 0.85,
		// where albedo only tints the environment reflection: the true
		// per-pixel mirror image barely showed (the owner's "not very
		// reflective") while the sun's specular lobe dominated.
		albedo *= 1.0 - mirror_amount;
		// Bontago-adt.2: procedural seams cut through the reflection a little.
		mirror_color *= 1.0 - proc_seam_occ * disc_proc_seam_reflection_occlusion;
		emission += mirror_color * mirror_amount;
	}

	// Bontago-mp0.3.8 problem 1: the explicit warm-gold sheen -- see the
	// disk_sheen_* uniforms' own DECISION above (view-dependent mirror-
	// reflection term, not a fixed position mask). NORMAL/VIEW are both
	// view-space here (same as the mirror fresnel block above); sun_view_dir
	// is config/sun_flare.tres's own world-space sun_direction transformed
	// into that same view space so it can be compared directly. reflected is
	// "what direction would a perfect mirror at this point send the camera's
	// own view ray back out towards" -- when that lines up with the sun's own
	// direction, this point genuinely mirrors the sun toward the camera, the
	// same test a real specular highlight uses, just with a deliberately low
	// (broad, soft) exponent instead of a photorealistic sharp one.
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
		// Bontago-adt.2: cel sheen -- a broad sun lobe off each plate's own
		// slightly tilted normal, quantised into flat bands, so neighbouring
		// plates catch the sun in different steps; brushed streaks modulate it.
		vec3 plate_view_n = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * proc_plate_n);
		float plate_align = clamp(dot(reflect(-sheen_view, plate_view_n), sun_view_dir), 0.0, 1.0);
		float sun_lobe = pow(plate_align, disc_proc_sheen_exponent);
		// Sky part: the plate's own fresnel toward grazing angles, so the
		// banded facets show in every view, not only when facing the sun.
		float sky_lobe = pow(1.0 - clamp(dot(plate_view_n, sheen_view), 0.0, 1.0), disc_proc_sky_sheen_power)
			* disc_proc_sky_sheen_weight;
		float lobe = clamp(max(sun_lobe, sky_lobe), 0.0, 1.0);
		vec3 sheen_col = mix(disk_sky_sheen_color, disc_proc_highlight_color,
			sun_lobe / max(sun_lobe + sky_lobe, 0.0001));
		float bands = max(float(disc_proc_sheen_bands), 1.0);
		float q = lobe * bands;
		float band = floor(q);
		float band_aa = max(disc_proc_sheen_band_softness, fwidth(q));
		band += smoothstep(1.0 - band_aa, 1.0, q - band);
		float banded = band / bands;
		emission += sheen_col * disc_proc_sheen_strength * banded * (1.0 + proc_brush);
		emission += disc_proc_highlight_color * proc_highlight;
	}

	if (snow > 0.0) {
		albedo = mix(albedo, path_albedo, snow);
		emission = mix(emission, path_emission, snow);
	}
	ALBEDO = albedo;
	EMISSION = emission;
	// Bontago-xtq.11 (owner, 2026-09-23: "the disc is a mirror-like surface
	// and not glass, so it should be reflective but not transparent"): no
	// ALPHA write at all -- the whole disk (including the CylinderMesh's
	// vertical side wall, which shares this one ShaderMaterial) is
	// unconditionally opaque, so every ownership indicator (tint/rim/
	// shimmer/goal) reads at full strength through ALBEDO/EMISSION above with
	// no opacity trick needed.
	METALLIC = disc_textured ? mix(base_metallic, clamp(tex_metal * disc_metalness_scale, 0.0, 1.0), disc_metalness_map_mix) : base_metallic;
	SPECULAR = disk_specular;
	AO = disk_ambient_scale;
	AO_LIGHT_AFFECT = 0.0;
	// Bontago-pt.12 part 2: grain_h0 (the same coarse+fine grain height the
	// NORMAL perturbation above used, in [-0.5, 0.5]) also nudges ROUGHNESS a
	// little -- a purely additive, sign-symmetric variation so the grain
	// reads as fine streaks in the reflection's sharpness, not a visible
	// overall dulling of the whole disc (top_grain_roughness_strength = 0
	// leaves this identical to the old plain base_roughness assignment).
	ROUGHNESS = clamp(base_roughness + grain_h0 * top_grain_roughness_strength, 0.0, 1.0);
	if (disc_textured) {
		ROUGHNESS = clamp(mix(disc_roughness_min, disc_roughness_max, tex_rough), 0.0, 1.0);
	}
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
	if (wfog_strength > 0.0) {
		float wfog = clamp((length(VERTEX) - wfog_begin) / max(wfog_end - wfog_begin, 0.001), 0.0, 1.0) * wfog_strength;
		ALBEDO = mix(ALBEDO, vec3(0.0), wfog);
		EMISSION = mix(EMISSION, wfog_color.rgb, wfog);
		METALLIC = mix(METALLIC, 0.0, wfog);
	}
}
