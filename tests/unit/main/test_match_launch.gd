extends GutTest
## MatchLaunch: the pure config builders and CLI parsers of the non-lobby modes.


func _base() -> MatchConfig:
	var base: MatchConfig = MatchConfig.new()
	base.player_count = 6
	base.ai_count = 3
	base.sandbox = false
	base.scripted_gifts = false
	base.gifts_enabled = false
	base.special_frequency = 55
	base.countdown_seconds = 7.0
	base.block_timer = 5.0
	base.weather_mode = MatchConfig.WeatherMode.STORM
	base.enabled_specials = [&"rocket", &"bomb"]
	return base


func _preset(frequency_override: int, default_players: int) -> SandboxConfig:
	var preset: SandboxConfig = SandboxConfig.new()
	preset.special_frequency_override = frequency_override
	preset.default_player_count = default_players
	return preset


# --- sandbox_config ---------------------------------------------------------

func test_sandbox_config_sets_relaxed_solo_rules() -> void:
	var config: MatchConfig = MatchLaunch.sandbox_config(_base(), 3, _preset(-1, 2))
	assert_true(config.sandbox, "sandbox flag set")
	assert_eq(config.ai_count, 0, "no bots")
	assert_eq(config.player_count, 3, "requested player count")


func test_sandbox_config_accepts_one_player() -> void:
	var config: MatchConfig = MatchLaunch.sandbox_config(_base(), 1, _preset(-1, 2))
	assert_eq(config.player_count, 1)
	assert_true(config.sandbox)


func test_sandbox_config_preset_frequency_override_enables_gifts() -> void:
	var config: MatchConfig = MatchLaunch.sandbox_config(_base(), 2, _preset(80, 2))
	assert_true(config.gifts_enabled, "override forces gifts on")
	assert_eq(config.special_frequency, 80)


func test_sandbox_config_zero_override_is_applied() -> void:
	var config: MatchConfig = MatchLaunch.sandbox_config(_base(), 2, _preset(0, 2))
	assert_true(config.gifts_enabled)
	assert_eq(config.special_frequency, 0, "0 is a real override, only negatives mean none")


func test_sandbox_config_negative_override_keeps_base_gift_settings() -> void:
	var config: MatchConfig = MatchLaunch.sandbox_config(_base(), 2, _preset(-1, 2))
	assert_false(config.gifts_enabled)
	assert_eq(config.special_frequency, 55)


func test_sandbox_config_null_preset_keeps_base_gift_settings() -> void:
	var config: MatchConfig = MatchLaunch.sandbox_config(_base(), 2, null)
	assert_true(config.sandbox)
	assert_false(config.gifts_enabled)
	assert_eq(config.special_frequency, 55)


func test_sandbox_config_leaves_base_untouched() -> void:
	var base: MatchConfig = _base()
	var config: MatchConfig = MatchLaunch.sandbox_config(base, 2, _preset(80, 2))
	assert_ne(config, base, "a copy, not the base")
	assert_false(base.sandbox)
	assert_eq(base.player_count, 6)
	assert_eq(base.ai_count, 3)
	assert_false(base.gifts_enabled)
	assert_eq(base.special_frequency, 55)


# --- tutorial_config --------------------------------------------------------

func test_tutorial_config_is_one_player_with_real_rules() -> void:
	var config: MatchConfig = MatchLaunch.tutorial_config(_base(), TutorialConfig.new())
	assert_eq(config.player_count, 1)
	assert_eq(config.ai_count, 0)
	assert_false(config.sandbox, "tutorial uses real rules")
	assert_true(config.scripted_gifts)


func test_tutorial_config_weather_off() -> void:
	var config: MatchConfig = MatchLaunch.tutorial_config(_base(), TutorialConfig.new())
	assert_eq(config.weather_mode, MatchConfig.WeatherMode.OFF)


func test_tutorial_config_enables_only_the_lesson_gift() -> void:
	var lesson: TutorialConfig = TutorialConfig.new()
	lesson.demo_special_id = &"rocket"
	var config: MatchConfig = MatchLaunch.tutorial_config(_base(), lesson)
	assert_true(config.gifts_enabled)
	assert_eq(config.enabled_specials, [&"rocket"] as Array[StringName])
	assert_eq(config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MIN, "no random crates")


func test_tutorial_config_skips_countdown_and_never_times_out_a_block() -> void:
	var config: MatchConfig = MatchLaunch.tutorial_config(_base(), TutorialConfig.new())
	assert_eq(config.countdown_seconds, 0.0)
	assert_eq(config.block_timer, MatchConfig.BLOCK_TIMER_MAX)


func test_tutorial_config_leaves_base_untouched() -> void:
	var base: MatchConfig = _base()
	var config: MatchConfig = MatchLaunch.tutorial_config(base, TutorialConfig.new())
	assert_ne(config, base)
	assert_eq(base.player_count, 6)
	assert_false(base.scripted_gifts)
	assert_eq(base.weather_mode, MatchConfig.WeatherMode.STORM)
	assert_eq(base.enabled_specials, [&"rocket", &"bomb"] as Array[StringName])
	assert_eq(base.countdown_seconds, 7.0)


# --- sandbox_player_count ---------------------------------------------------

func test_player_count_reads_players_arg() -> void:
	var count: int = MatchLaunch.sandbox_player_count(PackedStringArray(["players=5"]), _preset(-1, 3), _preset(-1, 2))
	assert_eq(count, 5)


func test_player_count_accepts_leading_dashes() -> void:
	assert_eq(MatchLaunch.sandbox_player_count(PackedStringArray(["--players=4"]), null, _preset(-1, 2)), 4)
	assert_eq(MatchLaunch.sandbox_player_count(PackedStringArray(["-players=7"]), null, _preset(-1, 2)), 7)


func test_player_count_finds_arg_among_others() -> void:
	var args: PackedStringArray = PackedStringArray(["--sandbox", "--force-special=bomb", "--players=8"])
	assert_eq(MatchLaunch.sandbox_player_count(args, null, _preset(-1, 2)), 8)


func test_player_count_falls_back_to_preset() -> void:
	assert_eq(MatchLaunch.sandbox_player_count(PackedStringArray(["--sandbox"]), _preset(-1, 3), _preset(-1, 2)), 3)


func test_player_count_falls_back_to_defaults_without_preset() -> void:
	assert_eq(MatchLaunch.sandbox_player_count(PackedStringArray(), null, _preset(-1, 2)), 2)


func test_player_count_ignores_lookalike_args() -> void:
	var args: PackedStringArray = PackedStringArray(["--max-players=6", "xplayers=6"])
	assert_eq(MatchLaunch.sandbox_player_count(args, _preset(-1, 3), _preset(-1, 2)), 3)


# --- forced_special_arg -----------------------------------------------------

func test_forced_special_parses_id() -> void:
	assert_eq(MatchLaunch.forced_special_arg(PackedStringArray(["--force-special=bomb"])), &"bomb")
	assert_eq(MatchLaunch.forced_special_arg(PackedStringArray(["force-special=rocket"])), &"rocket")


func test_forced_special_finds_arg_among_others() -> void:
	var args: PackedStringArray = PackedStringArray(["--sandbox", "-force-special=glue", "--players=2"])
	assert_eq(MatchLaunch.forced_special_arg(args), &"glue")


func test_forced_special_absent_is_empty() -> void:
	assert_eq(MatchLaunch.forced_special_arg(PackedStringArray()), &"")
	assert_eq(MatchLaunch.forced_special_arg(PackedStringArray(["--sandbox", "--players=3"])), &"")
