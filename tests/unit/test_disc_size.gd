extends GutTest
## Bontago-1pi.107: the disc-size slider's factor table, the scaled MapDef and
## the match_config round trip (with and without the field).

const EXPECTED_FACTORS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75]
const EXPECTED_LABELS: Array[String] = ["Tiny", "Small", "Medium", "Large", "Huge", "Enormous"]


func test_table_has_six_steps_with_the_owner_factors_and_labels() -> void:
	var tuning: DiscSizeTuning = DiscSizeTuning.shared()
	assert_eq(tuning.step_count(), EXPECTED_FACTORS.size())
	for step: int in range(EXPECTED_FACTORS.size()):
		assert_almost_eq(tuning.factor_for(step), EXPECTED_FACTORS[step], 0.0001)
		assert_eq(tuning.label_for(step), EXPECTED_LABELS[step])
	assert_almost_eq(tuning.factor_for(MatchConfig.DISC_SIZE_STEP_DEFAULT), 1.0, 0.0001)
	assert_eq(tuning.value_text(0), "Tiny - 50%")
	assert_eq(tuning.value_text(99), "Enormous - 175%", "out of range clamps")


func test_default_config_uses_the_unscaled_default_map() -> void:
	var config: MatchConfig = MatchConfig.new()
	assert_eq(config.map_def(), load("res://config/maps/round_medium.tres"), "same resource, untouched")
	assert_eq(config.map_def(), config.map_def(), "cached: one instance per config")


func test_scaling_multiplies_geometric_lengths_and_keeps_the_rest() -> void:
	var base: MapDef = load("res://config/maps/round_medium.tres") as MapDef
	for step: int in range(EXPECTED_FACTORS.size()):
		var config: MatchConfig = MatchConfig.new()
		config.disc_size_step = step
		var map: MapDef = config.map_def()
		var factor: float = EXPECTED_FACTORS[step]
		assert_almost_eq(map.field_radius, base.field_radius * factor, 0.001)
		assert_eq(map.territory_res, roundi(base.territory_res * factor))
		assert_eq(map.cell_size, base.cell_size, "one cell stays one metre")
		assert_eq(map.disk_height, base.disk_height)
		assert_almost_eq(map.home_flag_position(0, 4).x, base.home_flag_position(0, 4).x * factor, 0.001)
		var goals: PackedVector2Array = map.goal_flag_positions(3)
		assert_almost_eq(goals[0].x, base.goal_flag_positions(3)[0].x * factor, 0.001)
	assert_almost_eq(base.field_radius, MapDef.RADIUS_MEDIUM, 0.0001, "the base resource is never mutated")


func test_match_config_round_trip_carries_the_step() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = 5
	var restored: MatchConfig = MatchConfig.from_dict(config.to_dict())
	assert_eq(restored.disc_size_step, 5)
	assert_almost_eq(restored.map_def().field_radius, MapDef.RADIUS_MEDIUM * 1.75, 0.001)


func test_old_lobby_data_without_the_field_defaults_to_medium() -> void:
	var data: Dictionary = MatchConfig.new().to_dict()
	data.erase("disc_size_step")
	var restored: MatchConfig = MatchConfig.from_dict(data)
	assert_eq(restored.disc_size_step, MatchConfig.DISC_SIZE_STEP_DEFAULT)
	assert_almost_eq(restored.map_def().field_radius, MapDef.RADIUS_MEDIUM, 0.0001)


func test_sanitize_clamps_a_wire_step_into_range() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = 40
	config.sanitize()
	assert_eq(config.disc_size_step, EXPECTED_FACTORS.size() - 1)
	config.disc_size_step = -3
	config.sanitize()
	assert_eq(config.disc_size_step, 0)


func test_other_sizes_still_scale_through_the_same_path() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.map_size = MapDef.MapSize.LARGE
	config.disc_size_step = 0
	var base: MapDef = MapDef.for_variant_and_size(MatchConfig.MapVariant.ROUND, MapDef.MapSize.LARGE)
	assert_almost_eq(config.map_def().field_radius, base.field_radius * 0.5, 0.001)


func test_camera_zoom_limit_grows_with_a_large_disc_but_never_shrinks() -> void:
	var rig: CameraRig = autofree(CameraRig.new())
	rig.tuning = load("res://config/camera_tuning.tres") as CameraTuning
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = 5
	rig.set_map_def(config.map_def())
	assert_almost_eq(rig._zoom_max(), rig.tuning.zoom_max * 1.75, 0.001)
	config.disc_size_step = 0
	rig.set_map_def(config.map_def())
	assert_almost_eq(rig._zoom_max(), rig.tuning.zoom_max, 0.001)


func test_cloud_exclusion_follows_the_disc_radius() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	var huge: float = MapDef.RADIUS_MEDIUM * 1.75
	assert_almost_eq(CloudSea.exclusion_radius_m(theme, huge), huge * (1.0 + theme.cloud_disc_clearance_ratio), 0.001)
	assert_almost_eq(CloudSea.exclusion_radius_m(theme), MapDef.RADIUS_LARGE * (1.0 + theme.cloud_disc_clearance_ratio), 0.001)
