extends GutTest
## MatchConfig.sanitize()/to_dict()/from_dict() (spec 2.8, 3.6).


func test_to_dict_from_dict_round_trips_every_field() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.map_variant = MatchConfig.MapVariant.RING
	config.map_size = MapDef.MapSize.LARGE
	config.player_count = 6
	config.ai_count = 2
	config.ai_difficulty = MatchConfig.AiDifficulty.HARD
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	config.block_timer = 9.5
	config.gravity_multiplier = 1.5
	config.goal_flag_count = 3
	config.gifts_enabled = false
	config.special_frequency = 70
	config.enabled_specials = [&"rocket", &"bomb"]
	config.tilt_mode = MatchConfig.TiltMode.PHYSICAL_BALANCE
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	config.match_timer_minutes = 20
	config.sudden_death = true
	config.per_player_timer = false
	config.hot_seat = false
	config.player_colors = PackedColorArray([Color.RED, Color.BLUE])
	config.rng_seed = 42

	var data: Dictionary = config.to_dict()
	var restored: MatchConfig = MatchConfig.from_dict(data)

	assert_eq(restored.map_variant, config.map_variant)
	assert_eq(restored.map_size, config.map_size)
	assert_eq(restored.player_count, config.player_count)
	assert_eq(restored.ai_count, config.ai_count)
	assert_eq(restored.ai_difficulty, config.ai_difficulty)
	assert_eq(restored.team_mode, config.team_mode)
	assert_almost_eq(restored.block_timer, config.block_timer, 0.001)
	assert_almost_eq(restored.gravity_multiplier, config.gravity_multiplier, 0.001)
	assert_eq(restored.goal_flag_count, config.goal_flag_count)
	assert_eq(restored.gifts_enabled, config.gifts_enabled)
	assert_eq(restored.special_frequency, config.special_frequency)
	assert_eq(restored.enabled_specials, config.enabled_specials)
	assert_eq(restored.tilt_mode, config.tilt_mode)
	assert_eq(restored.hole_mode, config.hole_mode)
	assert_eq(restored.match_timer_minutes, config.match_timer_minutes)
	assert_eq(restored.sudden_death, config.sudden_death)
	assert_eq(restored.per_player_timer, config.per_player_timer)
	assert_eq(restored.hot_seat, config.hot_seat)
	assert_eq(restored.player_colors.size(), config.player_colors.size())
	for i: int in range(config.player_colors.size()):
		assert_eq(restored.player_colors[i], config.player_colors[i])
	assert_eq(restored.rng_seed, config.rng_seed)


func test_from_dict_keeps_defaults_for_unknown_or_missing_keys() -> void:
	var restored: MatchConfig = MatchConfig.from_dict({"player_count": 5, "not_a_real_field": 123})
	var defaults: MatchConfig = MatchConfig.new()
	assert_eq(restored.player_count, 5)
	assert_eq(restored.block_timer, defaults.block_timer)
	assert_eq(restored.hot_seat, defaults.hot_seat)


func test_sanitize_clamps_every_range() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 99
	config.block_timer = -5.0
	config.gravity_multiplier = 100.0
	config.goal_flag_count = 0
	config.special_frequency = -10
	config.match_timer_minutes = -3

	config.sanitize()

	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MAX)
	assert_eq(config.block_timer, MatchConfig.BLOCK_TIMER_MIN)
	assert_eq(config.gravity_multiplier, MatchConfig.GRAVITY_MAX)
	assert_eq(config.goal_flag_count, MatchConfig.GOAL_FLAG_MIN)
	assert_eq(config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MIN)
	assert_eq(config.match_timer_minutes, 0)


func test_sanitize_clamps_low_end_of_every_range() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = -1
	config.block_timer = 999.0
	config.gravity_multiplier = -1.0
	config.goal_flag_count = 999
	config.special_frequency = 999

	config.sanitize()

	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MIN)
	assert_eq(config.block_timer, MatchConfig.BLOCK_TIMER_MAX)
	assert_eq(config.gravity_multiplier, MatchConfig.GRAVITY_MIN)
	assert_eq(config.goal_flag_count, MatchConfig.GOAL_FLAG_MAX)
	assert_eq(config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MAX)


func test_sanitize_pads_short_player_colors() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.player_colors = PackedColorArray([Color.RED, Color.GREEN])
	config.sanitize()
	assert_eq(config.player_colors.size(), MatchConfig.PLAYER_COUNT_MAX)
	assert_eq(config.player_colors[0], Color.RED)
	assert_eq(config.player_colors[1], Color.GREEN)


func test_clamp_to_connected_peers_matches_player_count_to_peers_and_zeroes_ai() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 8
	config.ai_count = 3

	config.clamp_to_connected_peers(2)

	assert_eq(config.player_count, 2, "no slot may be left without a connected peer (Bontago-mv0.7)")
	assert_eq(config.ai_count, 0, "bots don't exist until M5")


func test_clamp_to_connected_peers_respects_the_spec_28_range() -> void:
	var config: MatchConfig = MatchConfig.new()

	config.clamp_to_connected_peers(0)
	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MIN)

	config.clamp_to_connected_peers(99)
	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MAX)


func test_team_of_slot_is_free_for_all_by_default() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 4
	for i: int in range(4):
		assert_eq(config.team_of_slot(i), i)
	assert_eq(config.team_count(), 4)


func test_map_def_resolves_from_map_size() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.map_size = MapDef.MapSize.SMALL
	assert_almost_eq(config.field_radius(), MapDef.RADIUS_SMALL, 0.001)
	config.map_size = MapDef.MapSize.LARGE
	assert_almost_eq(config.field_radius(), MapDef.RADIUS_LARGE, 0.001)
