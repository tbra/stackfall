shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Territory on the disk (spec 2.10, 3.3).
//
// game/TerritoryOverlay.gd uploads one ImageTexture per raster tick, the cell
// grid upscaled bilinearly to MapDef.territory_res. Channels:
//
//   R = team_id + 1, 0 = unowned. Bilinear interpolation makes this a ramp
//       across a territory edge, which is exactly what the smoothstep below
//       turns into spec 2.10's "soft tint".
//   G = the raw TerritoryRaster state bits (STATE_CONTESTED | STATE_HOLE),
//       kept as the M2 plan documents them so the texture can be read back
//       and checked against the raster.
//   B = 255 on a hole cell, A = 255 on a contested cell. Interpolating packed
//       bit flags is ambiguous (1 and 2 average to "hole"), so each flag also
//       gets a channel of its own where a 0.5 threshold lands exactly on the
//       cell boundary. See TerritoryOverlay's DECISION note.
//
// Disk-local (x, z) maps to UV with uv_scale / uv_offset, which carry
// CellGrid's convention: cell (0, 0) is the -x/-z corner of the square that
// covers the disk.

const int SLOT_COLOR_MAX = 8;

uniform sampler2D territory_tex : filter_linear, repeat_disable;
// Per-slot colors from MatchConfig.player_colors, already converted to linear
// by TerritoryOverlay; indexed by R - 1.
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
	vec4 cell = texture(territory_tex, uv);

	// Spec 3.3: "discards pixels where holes are".
	float hole = cell.b;
	if (hole > 0.5) {
		discard;
	}

	float owner_f = cell.r * 255.0;
	// Soft edge: the bilinear ramp from unowned (0) to owned (>= 1) crosses
	// 0.5 exactly on the cell boundary.
	float presence = clamp(owner_f, 0.0, 1.0);
	float coverage = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, presence);

	int owner_id = int(round(owner_f)) - 1;
	int color_index = clamp(owner_id, 0, SLOT_COLOR_MAX - 1);
	vec3 team_color = slot_colors[color_index].rgb;
	float owned = coverage * step(0.0, float(owner_id));

	vec3 albedo = mix(base_color.rgb, team_color, owned * tint_alpha);
	vec3 emission = vec3(0.0);

	// Animated outline along the territory's rim.
	float band = 1.0 - smoothstep(0.0, outline_width, abs(presence - 0.5));
	float pulse = mix(
		1.0 - outline_pulse_depth,
		1.0,
		0.5 + 0.5 * sin(TIME * outline_speed * TAU)
	);
	emission += team_color * band * outline_strength * pulse;

	// Contested cells shimmer with travelling bands (spec 2.10).
	float contested = cell.a;
	float shimmer = 0.5 + 0.5 * sin(
		(uv.x + uv.y) * contested_shimmer_scale * TAU - TIME * contested_shimmer_rate * TAU
	);
	emission += contested_color.rgb * contested * shimmer * contested_shimmer_strength;

	// Hole edges glow (spec 2.10); the hole itself is already discarded.
	float rim = smoothstep(0.5 - hole_rim_width, 0.5, hole);
	emission += hole_rim_color.rgb * rim * hole_rim_glow;

	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = base_metallic;
	ROUGHNESS = base_roughness;
}
