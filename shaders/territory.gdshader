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
render_mode cull_disabled, specular_disabled;

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

const int SLOT_COLOR_MAX = 8;
// TerritoryRaster's per-cell state bits.
const int STATE_CONTESTED = 1;
const int STATE_HOLE = 2;
const int STATE_GOAL_ZONE = 4;
// Goal discs the analytic path loops; mirrors game/TerritoryOverlay.gd's
// GOAL_TEXELS_MAX. Spec 2.2 allows only 1-5 goal flags, so this is a wire/
// shader safety cap, not a rule.
const int GOAL_MAX = 8;

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
uniform sampler2D circle_tex : filter_nearest, repeat_disable;
uniform int circle_count = 0;
// TerritoryVisuals.max_shader_circles: the cap actually looped, independent
// of TerritoryTuning.max_circles so a weaker GPU can loop fewer circles
// without touching the rules.
uniform int max_shader_circles = 400;
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
uniform sampler2D circle_bin_tex : filter_nearest, repeat_disable;
uniform bool circle_bins_valid = false;
uniform int circle_bin_grid = 1;
uniform float circle_bin_half_extent = 1.0;
const int CIRCLE_BIN_TEX_WIDTH = 256;

uniform float metaball_blend : hint_range(0.0, 3.0) = 0.3;
uniform float rim_soft_width : hint_range(0.001, 2.0) = 0.25;
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

varying vec3 v_local;

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
	DIFFUSE_LIGHT += ALBEDO * cool_light * ATTENUATION * disk_diffuse_response;
}

// Polynomial smooth min (Inigo Quilez). k <= 0 degrades to a hard min, so
// TerritoryVisuals.metaball_blend = 0 is a plain (still curved) union.
float smin(float a, float b, float k) {
	if (k <= 0.0) {
		return min(a, b);
	}
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Smooth max is smooth min of the negated inputs, negated back — the
// "positive inside" convention InfluenceCircle/TerritoryRaster._argmax()
// already uses (value = radius - distance) reads directly as a smooth union
// with no sign flip at the call site below.
float smax(float a, float b, float k) {
	return -smin(-a, -b, k);
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

void raster_path(vec2 uv, out vec3 albedo, out vec3 emission) {
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
	albedo = mix(base_color.rgb, team_color, tint * tint_alpha);
	emission = vec3(0.0);

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
void circle_path(vec2 point, out vec3 albedo, out vec3 emission) {
	float team_best[SLOT_COLOR_MAX];
	bool team_seen[SLOT_COLOR_MAX];
	bool team_done[SLOT_COLOR_MAX];
	for (int t = 0; t < SLOT_COLOR_MAX; t++) {
		team_best[t] = -1000000.0;
		team_seen[t] = false;
		team_done[t] = false;
	}

	int loop_n = min(circle_count, max_shader_circles);
	float saturation = metaball_blend + rim_soft_width;
	int bin_start = 0;
	int bin_n = loop_n;
	bool use_bins = false;
	if (circle_bins_valid && circle_bin_grid > 0) {
		vec2 cell_f = (point + vec2(circle_bin_half_extent))
			/ (2.0 * circle_bin_half_extent) * float(circle_bin_grid);
		if (cell_f.x >= 0.0 && cell_f.y >= 0.0
			&& cell_f.x < float(circle_bin_grid) && cell_f.y < float(circle_bin_grid)) {
			int k = int(floor(cell_f.y)) * circle_bin_grid + int(floor(cell_f.x));
			vec2 bin_range = texelFetch(
				circle_bin_tex, ivec2(k % CIRCLE_BIN_TEX_WIDTH, k / CIRCLE_BIN_TEX_WIDTH), 0
			).rg;
			bin_start = int(bin_range.x + 0.5);
			bin_n = int(bin_range.y + 0.5);
			use_bins = true;
		}
	}
	for (int j = 0; j < bin_n; j++) {
		int i = j;
		if (use_bins) {
			int ref_k = bin_start + j;
			i = int(texelFetch(
				circle_bin_tex, ivec2(ref_k % CIRCLE_BIN_TEX_WIDTH, ref_k / CIRCLE_BIN_TEX_WIDTH), 0
			).r + 0.5);
		}
		if (i >= loop_n) {
			continue;
		}
		vec4 c = texelFetch(circle_tex, ivec2(i, 0), 0);
		int team = int(round(c.a));
		if (team < 0 || team >= SLOT_COLOR_MAX || team_done[team]) {
			continue;
		}
		float value = c.b - distance(point, c.xy);
		if (!team_seen[team]) {
			team_best[team] = value;
			team_seen[team] = true;
		} else {
			team_best[team] = smax(team_best[team], value, metaball_blend);
		}
		if (team_best[team] > saturation) {
			team_done[team] = true;
		}
	}

	int owner_team = -1;
	int inside_count = 0;
	float best_overall = -1000000.0;
	for (int t = 0; t < SLOT_COLOR_MAX; t++) {
		if (!team_seen[t]) {
			continue;
		}
		if (team_best[t] > best_overall) {
			best_overall = team_best[t];
			owner_team = t;
		}
		if (team_best[t] >= 0.0) {
			inside_count += 1;
		}
	}

	// Default (overlap) mode: two or more teams' circles covering the same
	// point is a contest (spec 2.2), drawn with no team tint at all, same as
	// the raster path's CONTESTED cells. argmax_mode (v2, hole_mode == OFF)
	// has no contested concept — TerritoryRaster._argmax() always picks
	// exactly one owner — so it never sets this.
	bool contested = !argmax_mode && inside_count >= 2;

	albedo = base_color.rgb;
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
		albedo = mix(base_color.rgb, team_color, coverage * tint_alpha);

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
	if (circles_valid) {
		circle_path(v_local.xz, albedo, emission);
	} else {
		raster_path(uv, albedo, emission);
	}

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

	ALBEDO = albedo;
	EMISSION = emission;
	// Bontago-xtq.11 (owner, 2026-09-23: "the disc is a mirror-like surface
	// and not glass, so it should be reflective but not transparent"): no
	// ALPHA write at all -- the whole disk (including the CylinderMesh's
	// vertical side wall, which shares this one ShaderMaterial) is
	// unconditionally opaque, so every ownership indicator (tint/rim/
	// shimmer/goal) reads at full strength through ALBEDO/EMISSION above with
	// no opacity trick needed.
	METALLIC = base_metallic;
	// Bontago-pt.12 part 2: grain_h0 (the same coarse+fine grain height the
	// NORMAL perturbation above used, in [-0.5, 0.5]) also nudges ROUGHNESS a
	// little -- a purely additive, sign-symmetric variation so the grain
	// reads as fine streaks in the reflection's sharpness, not a visible
	// overall dulling of the whole disc (top_grain_roughness_strength = 0
	// leaves this identical to the old plain base_roughness assignment).
	ROUGHNESS = clamp(base_roughness + grain_h0 * top_grain_roughness_strength, 0.0, 1.0);
}
