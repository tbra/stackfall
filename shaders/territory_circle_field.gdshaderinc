// Owner id encoding shared by the bake pass and the disc decode (Bontago-1pi.11.1).
const float OWNER_ENCODE_DIV = 16.0;
// Bontago-1pi.11.1: the analytic influence-circle field, shared by
// shaders/territory.gdshader (direct fallback) and
// shaders/territory_circle_bake.gdshader (the once-per-change bake). Declares
// the circle/bin uniforms both shaders read and circle_field(), which evaluates
// the per-team smooth union at a disk-local point. Moved verbatim out of
// territory.gdshader's circle_path().

const int SLOT_COLOR_MAX = 8;
// Field values are baked clamped to +-BAKE_VALUE_CLAMP_M (metres): every drawn
// effect (tint edge, rim band <= rim_width's 2 m hint max) reads |value| below
// it, and the sign is preserved for the contested test.
const float BAKE_VALUE_CLAMP_M = 2.0;

uniform sampler2D circle_tex : filter_nearest, repeat_disable;
uniform int circle_count = 0;
uniform int max_shader_circles = 400;
uniform sampler2D circle_bin_tex : filter_nearest, repeat_disable;
uniform bool circle_bins_valid = false;
uniform int circle_bin_grid = 1;
uniform float circle_bin_half_extent = 1.0;
const int CIRCLE_BIN_TEX_WIDTH = 256;
uniform float metaball_blend : hint_range(0.0, 3.0) = 0.3;
uniform float rim_soft_width : hint_range(0.001, 2.0) = 0.25;

// Polynomial smooth min (Inigo Quilez). k <= 0 degrades to a hard min.
float smin(float a, float b, float k) {
	if (k <= 0.0) {
		return min(a, b);
	}
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float smax(float a, float b, float k) {
	return -smin(-a, -b, k);
}

// Best (union) value, second-best team value (for the contested test, -1e6
// when fewer than two teams reach the point) and owning team (-1 if none).
void circle_field(vec2 point, out float best_overall, out float second_best, out int owner_team) {
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

	owner_team = -1;
	best_overall = -1000000.0;
	second_best = -1000000.0;
	for (int t = 0; t < SLOT_COLOR_MAX; t++) {
		if (!team_seen[t]) {
			continue;
		}
		if (team_best[t] > best_overall) {
			second_best = best_overall;
			best_overall = team_best[t];
			owner_team = t;
		} else if (team_best[t] > second_best) {
			second_best = team_best[t];
		}
	}
}
