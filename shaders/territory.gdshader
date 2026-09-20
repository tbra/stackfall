shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Territory on the disk (spec 2.10, 3.3).
//
// game/TerritoryOverlay.gd uploads three single-channel textures per raster
// tick, all carrying TerritoryRaster's own cell bytes:
//
//   territory_tex          the owner grid (R = team_id + 1, 0 = unowned)
//                          upscaled bilinearly to MapDef.territory_res and
//                          sampled with filter_linear. This ramp is what the
//                          smoothstep below turns into spec 2.10's "soft
//                          tint", and what the outline band rides on.
//   territory_cells        the same owner grid at cell resolution, unblended.
//                          *Which* team owns a pixel has to come from here:
//                          the upscale invents ids between two teams --
//                          halfway between team 0 (1) and team 2 (3) is team
//                          1 -- which rings every border in a third player's
//                          color.
//   territory_state        STATE_CONTESTED (1) | STATE_HOLE (2) |
//   territory_state_soft   STATE_GOAL_ZONE (4) per cell, at cell resolution,
//                          bound twice. The unfiltered sampler answers "is
//                          this a hole", so the gap you see is exactly the
//                          cell whose collision Field.set_hole_cells()
//                          switched off; the filtered one gives the hole rim
//                          its falloff. Territory v2 (docs/TERRITORY_V2_PLAN.md,
//                          hole_mode == OFF) never sets STATE_CONTESTED/HOLE,
//                          only STATE_GOAL_ZONE, a static no-build disc around
//                          each goal flag that shimmers the same way a
//                          contested cell used to (both mean "something's
//                          different about this ground").
//
// Disk-local (x, z) maps to UV with uv_scale / uv_offset, which carry
// CellGrid's convention: cell (0, 0) is the -x/-z corner of the square that
// covers the disk.

const int SLOT_COLOR_MAX = 8;
// TerritoryRaster's per-cell state bits.
const int STATE_CONTESTED = 1;
const int STATE_HOLE = 2;
// Territory v2 (docs/TERRITORY_V2_PLAN.md): a static no-build disc around a
// goal flag. Coexists with STATE_CONTESTED/STATE_HOLE in the byte, but never
// fires alongside them in practice — the v2 fill (hole_mode == OFF) that sets
// this bit never sets the legacy bits, and the legacy fill never sets this
// one.
const int STATE_GOAL_ZONE = 4;

uniform sampler2D territory_tex : filter_linear, repeat_disable;
uniform sampler2D territory_cells : filter_nearest, repeat_disable;
uniform sampler2D territory_state : filter_nearest, repeat_disable;
uniform sampler2D territory_state_soft : filter_linear, repeat_disable;
// Per-slot colors from MatchConfig.player_colors, already converted to linear
// by TerritoryOverlay; indexed by the owner byte - 1.
uniform vec4 slot_colors[SLOT_COLOR_MAX];

uniform vec4 base_color : source_color = vec4(0.68, 0.70, 0.74, 1.0);
uniform float base_metallic : hint_range(0.0, 1.0) = 0.1;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.45;

uniform float uv_scale = 0.011111;
uniform float uv_offset = 0.5;

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

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = v_local.xz * uv_scale + vec2(uv_offset);
	float owner_near = round(texture(territory_cells, uv).r * 255.0);
	float owner_soft = texture(territory_tex, uv).r * 255.0;
	float state_near = round(texture(territory_state, uv).r * 255.0);
	float state_soft = texture(territory_state_soft, uv).r * 255.0;

	// Spec 3.3: "discards pixels where holes are". Read unfiltered, so the gap
	// is exactly the cell whose collision Field switched off. A plain
	// `state_near >= STATE_HOLE` threshold worked while STATE_HOLE (2) was the
	// highest bit in play, but STATE_GOAL_ZONE (4, docs/TERRITORY_V2_PLAN.md)
	// is numerically above it too and must never discard — a goal zone has no
	// physical hole, only a placement restriction — so this tests the HOLE bit
	// itself, exact since state_near is a rounded, unfiltered sample.
	if ((int(state_near) & STATE_HOLE) != 0) {
		discard;
	}

	int owner_id = int(owner_near) - 1;
	bool owned = owner_id >= 0;

	// Soft edge. The filtered ramp is normalized by this cell's own owner
	// value so the fade is the same width whatever the team id is.
	float presence = clamp(owner_soft / max(owner_near, 1.0), 0.0, 1.0);
	float coverage = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, presence);
	float tint = owned ? coverage : 0.0;

	vec3 team_color = slot_colors[clamp(owner_id, 0, SLOT_COLOR_MAX - 1)].rgb;
	vec3 albedo = mix(base_color.rgb, team_color, tint * tint_alpha);
	vec3 emission = vec3(0.0);

	// Animated outline, drawn just inside the territory's rim.
	float band = 1.0 - smoothstep(0.0, outline_width, abs(presence - 0.5));
	float pulse = mix(
		1.0 - outline_pulse_depth,
		1.0,
		0.5 + 0.5 * sin(TIME * outline_speed * TAU)
	);
	emission += team_color * band * outline_strength * pulse * (owned ? 1.0 : 0.0);

	// Contested cells shimmer with travelling bands (spec 2.10). Territory v2
	// (docs/TERRITORY_V2_PLAN.md package C) reuses the same shimmer for a
	// goal flag's no-build zone — both mean "something's different about this
	// ground" — rather than inventing a second animated look.
	int state_bits = int(state_near);
	float shimmer_active = ((state_bits & (STATE_CONTESTED | STATE_GOAL_ZONE)) != 0) ? 1.0 : 0.0;
	float shimmer = 0.5 + 0.5 * sin(
		(uv.x + uv.y) * contested_shimmer_scale * TAU - TIME * contested_shimmer_rate * TAU
	);
	emission += contested_color.rgb * shimmer_active * shimmer * contested_shimmer_strength;

	// Hole edges glow (spec 2.10); the hole itself is already discarded. The
	// filtered state ramps toward STATE_HOLE as it nears one, so a smoothstep
	// over the last hole_rim_width of that climb is the rim.
	// # DECISION (shaders/territory.gdshader, Territory v2 package C): under
	// v2 (hole_mode == OFF) a cell's state byte only ever blends between 0 and
	// STATE_GOAL_ZONE (4) at a zone's edge, which numerically passes through
	// this same smoothstep window on its way up — so a goal zone's boundary
	// picks up this glow too, on top of its own shimmer. Kept rather than
	// suppressed: it reads as an extra "warning ring" right at the no-build
	// line, which only helps the "clearly visible ring" ask, and isolating it
	// per-bit would need a second filtered channel from TerritoryOverlay.gd
	// (out of this package's ownership) for a coincidence that already looks
	// intentional. Revisit with a dedicated goal-zone channel if the owner
	// wants the rim colour to differ from a real hole's.
	float rim = smoothstep(
		float(STATE_HOLE) - hole_rim_width * 2.0, float(STATE_HOLE), state_soft
	);
	emission += hole_rim_color.rgb * rim * hole_rim_glow;

	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = base_metallic;
	ROUGHNESS = base_roughness;
}
