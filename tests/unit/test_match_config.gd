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


# --- HoleMode.TEMPORARY, the default again (Bontago-cmc.7) --------------------
# docs/TERRITORY_V2_PLAN.md's HoleMode.OFF (the v2 no-overlap mode) was the
# default for a while; SPEC.md's 2026-09-20 evidence audit ("Decisions made —
# current target": "restore overlap holes as the fidelity target... The
# no-overlap v2 mode is optional, not the default") reverted it back to
# TEMPORARY, matching the installed original's own tutorial text
# (docs/ORIGINAL_INSTALL_EVIDENCE.md: overlap sinking).

func test_holes_are_temporary_by_default() -> void:
	assert_eq(MatchConfig.new().hole_mode, MatchConfig.HoleMode.TEMPORARY,
		"SPEC.md 2026-09-20 audit: overlap holes are the fidelity target again.")


func test_the_shipped_defaults_resource_also_says_temporary() -> void:
	var defaults: MatchConfig = load("res://config/match_defaults.tres") as MatchConfig
	assert_eq(defaults.hole_mode, MatchConfig.HoleMode.TEMPORARY,
		"config/match_defaults.tres stores the raw int, so it has to be "
		+ "re-saved when the enum's default moves.")


func test_every_hole_mode_round_trips_by_its_int() -> void:
	for mode: MatchConfig.HoleMode in [
		MatchConfig.HoleMode.TEMPORARY, MatchConfig.HoleMode.PERMANENT, MatchConfig.HoleMode.OFF
	]:
		var config: MatchConfig = MatchConfig.new()
		config.hole_mode = mode
		var restored: MatchConfig = MatchConfig.from_dict(config.to_dict())
		assert_eq(restored.hole_mode, mode)


func test_the_existing_hole_mode_ints_did_not_move() -> void:
	## OFF was appended rather than inserted, so a raw 0 or 1 from an old save
	## or from a peer running the previous build still means what it meant.
	assert_eq(int(MatchConfig.HoleMode.TEMPORARY), 0)
	assert_eq(int(MatchConfig.HoleMode.PERMANENT), 1)
	assert_eq(int(MatchConfig.HoleMode.OFF), 2)
	assert_eq(MatchConfig.from_dict({"hole_mode": 0}).hole_mode, MatchConfig.HoleMode.TEMPORARY)
	assert_eq(MatchConfig.from_dict({"hole_mode": 1}).hole_mode, MatchConfig.HoleMode.PERMANENT)


func test_sanitize_clamps_hole_mode_to_the_three_modes() -> void:
	var low: MatchConfig = MatchConfig.new()
	low.hole_mode = -3 as MatchConfig.HoleMode
	low.sanitize()
	assert_eq(low.hole_mode, MatchConfig.HoleMode.TEMPORARY,
		"A garbage value clamps to a real mode, never silently to OFF.")

	var high: MatchConfig = MatchConfig.new()
	high.hole_mode = 99 as MatchConfig.HoleMode
	high.sanitize()
	assert_eq(high.hole_mode, MatchConfig.HoleMode.OFF)

	for mode: MatchConfig.HoleMode in [
		MatchConfig.HoleMode.TEMPORARY, MatchConfig.HoleMode.PERMANENT, MatchConfig.HoleMode.OFF
	]:
		var config: MatchConfig = MatchConfig.new()
		config.hole_mode = mode
		config.sanitize()
		assert_eq(config.hole_mode, mode, "sanitize() leaves a legal mode alone.")
