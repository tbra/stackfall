extends GutTest
## Bontago-1pi.165: the network position band must reach the Reach the Sky
## target (100 m above the disc) plus a margin, so a held ghost, a host-accepted
## placement and a replicated body all work at 100+ m.

const TARGET_M: float = 100.0
const PROBE_ABOVE_TARGET_M: float = 5.0
## Worst 3D error of an int16 axis over the ~200 m band (see SPEC 3.4).
const POSITION_TOLERANCE_M: float = 0.0035

var _net_config: NetConfig
var _ghost: GhostTuning


func before_each() -> void:
	_net_config = load("res://config/net_config.tres")
	_ghost = load("res://config/ghost_tuning.tres")


func test_band_covers_the_target_plus_margin() -> void:
	assert_gte(_net_config.pos_max_y, TARGET_M + _net_config.build_height_margin_m, "band top >= target + margin")
	assert_gte(_net_config.pos_max_y - _ghost.hover_ceiling_margin, TARGET_M + PROBE_ABOVE_TARGET_M, "the ghost origin can reach 105 m")


func test_band_is_derived_from_the_target_height() -> void:
	var cfg: NetConfig = NetConfig.new()
	cfg.build_height_target_m = 160.0
	assert_gte(cfg.pos_max_y, 160.0 + cfg.build_height_margin_m, "a taller target lifts the band")


func test_hover_manual_max_does_not_cap_below_the_band() -> void:
	assert_gte(_ghost.hover_manual_max, _net_config.pos_max_y - _ghost.hover_ceiling_margin, "manual hover cap is not the binding limit")


func test_a_100m_plus_pose_round_trips_over_the_wire() -> void:
	var map_def: MapDef = load("res://config/maps/round_medium.tres")
	var bounds: AABB = _net_config.position_bounds(map_def)
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(Quantize.POSITION_BYTES)
	for y: float in [TARGET_M, TARGET_M + PROBE_ABOVE_TARGET_M, _net_config.pos_max_y - 1.0]:
		var p: Vector3 = Vector3(3.0, y, -4.0)
		Quantize.pack_position(buf, 0, p, bounds)
		var back: Vector3 = Quantize.unpack_position(buf, 0, bounds)
		assert_lt((back - p).length(), POSITION_TOLERANCE_M, "y=%f round trips" % y)
