shader_type canvas_item;
// Bontago-1pi.11.1: bakes territory.gdshader's per-pixel circle loop into a
// texture, rendered once per circle-set change by game/TerritoryOverlay.gd's
// SubViewport (see its DECISION comment). Channels (all in [0, 1]):
//   R = best value  (clamped to +-BAKE_VALUE_CLAMP_M, encoded v / (2*clamp) + 0.5)
//   G = second-best team value (same encoding)
//   B = (owner team + 1) / 16, 0 = unowned
// The disk shader samples R/G with a linear filter (the fields are continuous,
// so this reconstructs a smooth, anti-aliased edge) and B with nearest.
#include "res://shaders/territory_circle_field.gdshaderinc"

// Half size of the baked rectangle in disk-local metres (x, z).
uniform vec2 bake_half_extent = vec2(45.0, 45.0);

float encode_value(float v) {
	return clamp(v, -BAKE_VALUE_CLAMP_M, BAKE_VALUE_CLAMP_M) / (2.0 * BAKE_VALUE_CLAMP_M) + 0.5;
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * 2.0 * bake_half_extent;
	float best;
	float second;
	int owner_team;
	circle_field(point, best, second, owner_team);
	COLOR = vec4(encode_value(best), encode_value(second), float(owner_team + 1) / OWNER_ENCODE_DIV, 1.0);
}
