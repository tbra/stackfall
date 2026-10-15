extends GutTest
## Bontago-1t5.13 (BT5): `--bot-difficulty`, `--match-seed` and the other training overrides on the headless
## bot flow.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var cfg: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	cfg.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(cfg as TinyMapMatchConfig).set_tiny_map(tiny_map)
	cfg.rng_seed = 90210
	_main.match_config = cfg
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _flow() -> Variant:
	return _main._headless_bots_flow_port()


func test_difficulty_flag_sets_every_bot_slot() -> void:
	for name_and_value: Array in [["easy", MatchConfig.AiDifficulty.EASY], ["hard", MatchConfig.AiDifficulty.HARD], ["2", MatchConfig.AiDifficulty.HARD]]:
		var config: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--bot-difficulty=%s" % name_and_value[0]]))
		for slot_id: int in range(4):
			assert_eq(config.ai_difficulty_for_slot(slot_id), name_and_value[1], "slot %d %s" % [slot_id, name_and_value[0]])
	var unset: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray())
	assert_eq(unset.ai_difficulty, MatchConfig.AiDifficulty.NORMAL, "no flag keeps the configured difficulty")


func test_match_seed_is_deterministic() -> void:
	var args: PackedStringArray = PackedStringArray(["--match-seed=4242"])
	assert_eq(_flow()._build_headless_bot_config(2, args).rng_seed, 4242)
	assert_eq(_flow()._build_headless_bot_config(2, args).rng_seed, 4242)
	assert_eq(_flow()._derived_loop_seed(4242, 1), 4242)
	assert_eq(_flow()._derived_loop_seed(4242, 2), _flow()._derived_loop_seed(4242, 2))
	assert_ne(_flow()._derived_loop_seed(4242, 2), _flow()._derived_loop_seed(4242, 3))
	assert_eq(_flow()._build_headless_bot_config(2, PackedStringArray()).rng_seed, 90210, "no flag keeps the configured seed")


func test_round_timer_flag_per_mode() -> void:
	var elim: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--mode=elimination", "--round-timer=0"]))
	assert_eq(elim.round_timer_minutes, MatchConfig.ROUND_TIMER_OFF_MINUTES, "Elimination: 0 turns the round timer off")
	var elim_n: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--mode=elimination", "--round-timer=7"]))
	assert_eq(elim_n.round_timer_minutes, 7)
	var order: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--round-timer=0", "--mode=elimination"]))
	assert_eq(order.round_timer_minutes, MatchConfig.ROUND_TIMER_OFF_MINUTES, "arg order does not matter: applied after the mode")
	var classic: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--mode=classic", "--round-timer=0"]))
	assert_eq(classic.round_timer_minutes, MatchConfig.clamp_round_timer(0, MatchConfig.GameMode.CLASSIC), "Classic clamps 0 to its minimum")
	assert_gt(classic.round_timer_minutes, 0)
	var absent: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--mode=elimination"]))
	assert_eq(absent.round_timer_minutes, MatchConfig.clamp_round_timer(_main.match_config.round_timer_minutes, MatchConfig.GameMode.ELIMINATION))


func test_gifts_flag_disables_gifts_only_when_zero() -> void:
	var off: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray(["--gifts=0"]))
	assert_false(off.gifts_enabled, "--gifts=0 disables gifts")
	var absent: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray())
	assert_eq(absent.gifts_enabled, _main.match_config.gifts_enabled, "absent flag keeps the configured default")
	var other: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray(["--gifts=1"]))
	assert_eq(other.gifts_enabled, _main.match_config.gifts_enabled, "only 0 changes anything")


func test_weather_flag_zero_off_one_on_absent_unchanged() -> void:
	var off: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray(["--weather=0"]))
	assert_eq(off.weather_mode, MatchConfig.WeatherMode.OFF, "--weather=0 turns weather off")
	var absent: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray())
	assert_eq(absent.weather_mode, _main.match_config.weather_mode, "absent keeps the default")
	var on: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray(["--weather=1"]))
	assert_ne(on.weather_mode, MatchConfig.WeatherMode.OFF, "--weather=1 leaves weather on")


func test_difficulty_slots_fill_named_slots_only() -> void:
	var args: PackedStringArray = PackedStringArray(["--bot-difficulty=normal", "--bot-difficulty-slots=0:hard,2:easy,3:2"])
	var config: MatchConfig = _flow()._build_headless_bot_config(4, args)
	assert_eq(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.HARD)
	assert_eq(config.ai_difficulty_for_slot(1), MatchConfig.AiDifficulty.NORMAL, "unnamed slot keeps --bot-difficulty")
	assert_eq(config.ai_difficulty_for_slot(2), MatchConfig.AiDifficulty.EASY)
	assert_eq(config.ai_difficulty_for_slot(3), MatchConfig.AiDifficulty.HARD)


func test_difficulty_slots_bad_input_keeps_defaults() -> void:
	var args: PackedStringArray = PackedStringArray(["--bot-difficulty-slots=9:hard,1:godlike,x,1,0:easy"])
	var config: MatchConfig = _flow()._build_headless_bot_config(2, args)
	assert_eq(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.EASY, "the valid entry still applies")
	assert_eq(config.ai_difficulty_for_slot(1), _main.match_config.ai_difficulty_for_slot(1), "bad level leaves slot 1 alone")
	var none: MatchConfig = _flow()._build_headless_bot_config(2, PackedStringArray(["--bot-difficulty-slots=7:hard"]))
	assert_eq(none.ai_difficulty_for_slot(0), _main.match_config.ai_difficulty_for_slot(0))
