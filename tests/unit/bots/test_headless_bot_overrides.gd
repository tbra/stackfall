extends GutTest
## `MatchLaunch.headless_bot_config`: `--bot-difficulty`, `--match-seed` and the other
## training overrides of a headless bot match, built from the command line alone.

const DEFAULTS_PATH: String = "res://config/match/match_defaults.tres"


## The config a headless bot match starts from when no `--match-config` is given.
func _defaults() -> MatchConfig:
	return load(DEFAULTS_PATH) as MatchConfig


## `bots` bot seats from the shipped defaults, shaped by the `extra` flags.
func _build(bots: int, extra: PackedStringArray = PackedStringArray()) -> MatchConfig:
	return MatchLaunch.headless_bot_config(_defaults(), bots, extra)


func test_difficulty_flag_sets_every_bot_slot() -> void:
	for name_and_value: Array in [["easy", MatchConfig.AiDifficulty.EASY], ["hard", MatchConfig.AiDifficulty.HARD], ["2", MatchConfig.AiDifficulty.HARD]]:
		var config: MatchConfig = _build(4, PackedStringArray(["--bot-difficulty=%s" % name_and_value[0]]))
		assert_not_null(config, "a config is built for %s" % name_and_value[0])
		if config == null:
			continue
		for slot_id: int in range(4):
			assert_eq(config.ai_difficulty_for_slot(slot_id), name_and_value[1], "slot %d %s" % [slot_id, name_and_value[0]])
	var unset: MatchConfig = _build(4)
	assert_not_null(unset)
	if unset != null:
		assert_eq(unset.ai_difficulty, _defaults().ai_difficulty, "no flag keeps the configured difficulty")


func test_difficulty_flag_unknown_value_keeps_configured_difficulty() -> void:
	var config: MatchConfig = _build(2, PackedStringArray(["--bot-difficulty=godlike"]))
	assert_not_null(config)
	if config != null:
		assert_eq(config.ai_difficulty, _defaults().ai_difficulty)


func test_difficulty_flag_clears_configured_per_slot_levels() -> void:
	var config: MatchConfig = _build(3, PackedStringArray(["--bot-difficulty=hard"]))
	assert_not_null(config)
	if config != null:
		assert_eq(config.slot_ai_difficulties.size(), 0, "the flag covers every bot slot, so per-slot levels are cleared")


func test_match_seed_is_deterministic() -> void:
	var first: MatchConfig = _build(2, PackedStringArray(["--match-seed=4242"]))
	var second: MatchConfig = _build(2, PackedStringArray(["--match-seed=4242"]))
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_eq(first.rng_seed, 4242)
	assert_eq(second.rng_seed, 4242)
	assert_eq(_build(2).rng_seed, _defaults().rng_seed, "no flag keeps the configured seed")


func test_flags_accept_any_number_of_leading_dashes_or_none() -> void:
	var built: MatchConfig = MatchLaunch.headless_bot_config(_defaults(), 2, PackedStringArray(["---match-seed=77"]))
	assert_not_null(built)
	if built != null:
		assert_eq(built.rng_seed, 77, "any number of leading dashes is stripped")
		assert_eq(built.ai_count, 2, "a flag without dashes still parses")


func test_round_timer_flag_per_mode() -> void:
	var elim: MatchConfig = _build(4, PackedStringArray(["--mode=elimination", "--round-timer=0"]))
	assert_not_null(elim)
	if elim == null:
		return
	assert_eq(elim.round_timer_minutes, MatchConfig.ROUND_TIMER_OFF_MINUTES, "Elimination: 0 turns the round timer off")
	assert_eq(_build(4, PackedStringArray(["--mode=elimination", "--round-timer=7"])).round_timer_minutes, 7)
	assert_eq(_build(4, PackedStringArray(["--round-timer=0", "--mode=elimination"])).round_timer_minutes, MatchConfig.ROUND_TIMER_OFF_MINUTES, "arg order does not matter: applied after the mode")
	var classic: MatchConfig = _build(4, PackedStringArray(["--mode=classic", "--round-timer=0"]))
	assert_eq(classic.round_timer_minutes, MatchConfig.clamp_round_timer(0, MatchConfig.GameMode.CLASSIC), "Classic clamps 0 to its minimum")
	assert_gt(classic.round_timer_minutes, 0)
	var absent: MatchConfig = _build(4, PackedStringArray(["--mode=elimination"]))
	assert_eq(absent.round_timer_minutes, MatchConfig.clamp_round_timer(_defaults().round_timer_minutes, MatchConfig.GameMode.ELIMINATION))


func test_round_timer_flag_rejects_non_numbers() -> void:
	var config: MatchConfig = _build(2, PackedStringArray(["--round-timer=soon"]))
	assert_not_null(config)
	if config != null:
		assert_eq(config.round_timer_minutes, _defaults().round_timer_minutes, "a bad value keeps the configured timer")


func test_mode_flag_names_and_ids() -> void:
	var cases: Array = [
		["classic", MatchConfig.GameMode.CLASSIC],
		["ctf", MatchConfig.GameMode.CAPTURE_THE_FLAG],
		["capture_the_flag", MatchConfig.GameMode.CAPTURE_THE_FLAG],
		["elimination", MatchConfig.GameMode.ELIMINATION],
		["sky", MatchConfig.GameMode.REACH_THE_SKY],
		["reach_the_sky", MatchConfig.GameMode.REACH_THE_SKY],
		["ELIMINATION", MatchConfig.GameMode.ELIMINATION],
	]
	for pair: Array in cases:
		var config: MatchConfig = _build(2, PackedStringArray(["--mode=%s" % pair[0]]))
		assert_not_null(config)
		if config != null:
			assert_eq(config.game_mode, MatchConfig.resolve_game_mode(pair[1]), "--mode=%s" % pair[0])
	var by_id: MatchConfig = _build(2, PackedStringArray(["--mode=%d" % MatchConfig.GameMode.ELIMINATION]))
	assert_not_null(by_id)
	if by_id != null:
		assert_eq(by_id.game_mode, MatchConfig.GameMode.ELIMINATION, "the GameMode integer picks the mode")
	var absent: MatchConfig = _build(2)
	assert_not_null(absent)
	if absent != null:
		assert_eq(absent.game_mode, _defaults().game_mode, "no flag keeps the configured mode")


func test_gifts_flag_disables_gifts_only_when_zero() -> void:
	var off: MatchConfig = _build(2, PackedStringArray(["--gifts=0"]))
	assert_not_null(off)
	if off == null:
		return
	assert_false(off.gifts_enabled, "--gifts=0 disables gifts")
	assert_eq(_build(2).gifts_enabled, _defaults().gifts_enabled, "absent flag keeps the configured default")
	assert_eq(_build(2, PackedStringArray(["--gifts=1"])).gifts_enabled, _defaults().gifts_enabled, "only 0 changes anything")


func test_weather_flag_zero_off_one_on_absent_unchanged() -> void:
	var off: MatchConfig = _build(2, PackedStringArray(["--weather=0"]))
	assert_not_null(off)
	if off == null:
		return
	assert_eq(off.weather_mode, MatchConfig.WeatherMode.OFF, "--weather=0 turns weather off")
	assert_eq(_build(2).weather_mode, _defaults().weather_mode, "absent keeps the default")
	assert_ne(_build(2, PackedStringArray(["--weather=1"])).weather_mode, MatchConfig.WeatherMode.OFF, "--weather=1 leaves weather on")


func test_goals_flag_is_clamped_and_zero_means_absent() -> void:
	var many: MatchConfig = _build(2, PackedStringArray(["--goals=99"]))
	assert_not_null(many)
	if many == null:
		return
	assert_eq(many.goal_flag_count, MatchConfig.GOAL_FLAG_MAX, "above the range clamps to the maximum")
	assert_eq(_build(2, PackedStringArray(["--goals=%d" % MatchConfig.GOAL_FLAG_MIN])).goal_flag_count, MatchConfig.GOAL_FLAG_MIN)
	assert_eq(_build(2, PackedStringArray(["--goals=0"])).goal_flag_count, _defaults().goal_flag_count, "0 is the absent value")
	assert_eq(_build(2).goal_flag_count, _defaults().goal_flag_count)


func test_disc_size_flag_is_clamped_to_a_step() -> void:
	var tiny: MatchConfig = _build(2, PackedStringArray(["--disc-size=0"]))
	assert_not_null(tiny)
	if tiny == null:
		return
	assert_eq(tiny.disc_size_step, DiscSizeTuning.shared().clamp_step(0), "step 0 is a real value")
	assert_eq(_build(2, PackedStringArray(["--disc-size=999"])).disc_size_step, DiscSizeTuning.shared().clamp_step(999))
	assert_eq(_build(2).disc_size_step, _defaults().disc_size_step, "absent keeps the configured step")


func test_difficulty_slots_fill_named_slots_only() -> void:
	var config: MatchConfig = _build(4, PackedStringArray(["--bot-difficulty=normal", "--bot-difficulty-slots=0:hard,2:easy,3:2"]))
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.HARD)
	assert_eq(config.ai_difficulty_for_slot(1), MatchConfig.AiDifficulty.NORMAL, "unnamed slot keeps --bot-difficulty")
	assert_eq(config.ai_difficulty_for_slot(2), MatchConfig.AiDifficulty.EASY)
	assert_eq(config.ai_difficulty_for_slot(3), MatchConfig.AiDifficulty.HARD)


func test_difficulty_slots_bad_input_keeps_defaults() -> void:
	var config: MatchConfig = _build(2, PackedStringArray(["--bot-difficulty-slots=9:hard,1:godlike,x,1,0:easy"]))
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.EASY, "the valid entry still applies")
	assert_eq(config.ai_difficulty_for_slot(1), _defaults().ai_difficulty_for_slot(1), "bad level leaves slot 1 alone")
	var none: MatchConfig = _build(2, PackedStringArray(["--bot-difficulty-slots=7:hard"]))
	assert_eq(none.ai_difficulty_for_slot(0), _defaults().ai_difficulty_for_slot(0))


func test_difficulty_slots_are_absolute_when_humans_take_the_first_seats() -> void:
	# --players=4 with --bots=2: slots 0-1 are idle human seats, slots 2-3 the bots.
	var config: MatchConfig = _build(2, PackedStringArray(["--players=4", "--bot-difficulty-slots=2:hard,0:easy"]))
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.ai_difficulty_for_slot(2), MatchConfig.AiDifficulty.HARD, "a bot slot is named by its absolute id")
	assert_ne(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.EASY, "a human seat is not a bot slot")


# --- the fixed rules of a headless bot match -------------------------------

func test_bot_match_shape_defaults() -> void:
	var config: MatchConfig = _build(3)
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.ai_count, 3)
	assert_eq(config.player_count, 3, "every seat is a bot unless --players says more")
	assert_false(config.sandbox, "real timers and win loop")
	assert_eq(config.countdown_seconds, 0.0, "no human to wait for")


func test_players_flag_raises_the_seat_count_past_the_bots_but_never_below() -> void:
	var more: MatchConfig = _build(2, PackedStringArray(["--players=5"]))
	assert_not_null(more)
	if more == null:
		return
	assert_eq(more.player_count, 5)
	assert_eq(more.ai_count, 2)
	assert_eq(_build(4, PackedStringArray(["--players=2"])).player_count, 4, "fewer players than bots keeps one seat per bot")


func test_builder_returns_its_own_copy_and_leaves_the_shared_defaults_alone() -> void:
	var before_seed: int = _defaults().rng_seed
	var before_ai: int = _defaults().ai_count
	var first: MatchConfig = _build(5, PackedStringArray(["--match-seed=1", "--gifts=0", "--mode=elimination"]))
	var second: MatchConfig = _build(5)
	assert_not_null(first)
	assert_not_null(second)
	assert_eq(_defaults().rng_seed, before_seed)
	assert_eq(_defaults().ai_count, before_ai)
	if first != null and second != null:
		assert_ne(first, second, "each call returns its own copy")


func test_override_config_wins_over_the_default_base() -> void:
	var override: MatchConfig = _defaults().duplicate(true) as MatchConfig
	override.block_timer = _defaults().block_timer + 3.0
	override.rng_seed = 99
	var config: MatchConfig = MatchLaunch.headless_bot_config(override, 2, PackedStringArray(["--gifts=0"]))
	assert_eq(config.block_timer, override.block_timer, "the base passed in is the duplication source")
	assert_eq(config.rng_seed, 99)
	assert_false(config.gifts_enabled, "flags still apply on top of the override")
