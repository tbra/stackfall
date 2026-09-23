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
render_mode cull_disabled, specular_schlick_ggx;

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
// Bontago-xtq.11: mirror-like defaults (docs/original_single-block.png,
// docs/original_stacked-tower.png) match TerritoryVisuals.gd's disk_metallic/
// disk_roughness; only used if TerritoryOverlay never pushes the real
// resource values (it always does in practice -- see refresh_visual_uniforms()).
uniform float base_metallic : hint_range(0.0, 1.0) = 0.85;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.18;

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
uniform sampler2D mirror_tex : filter_linear;
uniform bool mirror_enabled = false;
uniform float mirror_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
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
	float shimmer = 0.5 + 0.5 * sin(
		(uv.x + uv.y) * contested_shimmer_scale * TAU - TIME * contested_shimmer_rate * TAU
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
	for (int i = 0; i < loop_n; i++) {
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
		float shimmer = 0.5 + 0.5 * sin(
			(point.x + point.y) * contested_shimmer_scale * TAU
			- TIME * contested_shimmer_rate * TAU
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
		float shimmer = 0.5 + 0.5 * sin(
			(point.x + point.y) * contested_shimmer_scale * TAU
			- TIME * contested_shimmer_rate * TAU
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

	// Bontago-xtq.12 step 2: the planar mirror REPLACES the metallic/probe/
	// SSR reflection response where it is wired and enabled, scaled by both
	// disk_metallic (a more metallic disk shows more of the mirror, same as
	// it would show more of any other reflection) and mirror_strength (an
	// independent knob to dial the mirror back without touching the disk's
	// own material feel) -- a mix() into ALBEDO, not an EMISSION add, is
	// deliberate: METALLIC's own IBL/probe/SSR response is itself driven by
	// ALBEDO, so this reads as "swap in the true per-pixel reflection where
	// we have one" rather than stacking a second, brighter reflection on top
	// of the first.
	if (mirror_enabled) {
		// game/DiscMirror.gd's own mirror_transform() DECISION comment: its
		// camera basis is deliberately proper (not a raw per-axis
		// reflection), which keeps triangle winding/culling correct but
		// renders the true mirror image flipped left-right -- flipping X
		// here undoes exactly that, so this samples the correct final image.
		vec3 mirror_color = texture(mirror_tex, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)).rgb;
		float mirror_amount = clamp(base_metallic * mirror_strength, 0.0, 1.0);
		albedo = mix(albedo, mirror_color, mirror_amount);
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
	METALLIC = base_metallic;
	ROUGHNESS = base_roughness;
}
