extends GutTest
## Bontago-1pi.212: the debug "Watch bots" match -- menu entry, picker, command line, the all-bot
## match with no local seat, and the spectator camera / follow / speed controls.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const MENU_SCENE: PackedScene = preload("res://ui/MainMenu.tscn")
const TEST_FIELD_RADIUS_M: float = 20.0
const TEST_BOTS: int = 2
const SETTLE_FRAMES: int = 3
const PHYSICS_FRAMES: int = 4
const FOLLOW_SLOTS: int = 3

var _main: Variant = null
var _picked: WatchBotsOptions = null


func before_each() -> void:
	DebugMode.set_override_for_test(true)
	Engine.time_scale = 1.0
	_picked = null


func after_each() -> void:
	Engine.time_scale = 1.0
	DebugMode.clear_override_for_test()
	if _main != null:
		Net.leave()
		Match.abort_match()
		SnapshotSync.end_match()
		Match.set_process(true)
		_main = null
		await get_tree().process_frame
		await get_tree().process_frame


func _make_menu(debug_enabled: bool) -> MainMenu:
	DebugMode.set_override_for_test(debug_enabled)
	var menu: MainMenu = autofree(MENU_SCENE.instantiate())
	add_child_autofree(menu)
	Net.stop_discovery()
	var fake: FakeNet = FakeNet.new()
	menu.net_provider = fake
	menu._apply_steam_availability()
	return menu


func _make_main() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = TEST_FIELD_RADIUS_M
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_config.rng_seed = 1014
	_main.match_config = tiny_config
	add_child_autofree(_main)


func _on_picked(options: WatchBotsOptions) -> void:
	_picked = options


# --- Menu entry and picker --------------------------------------------------------

func test_debug_mode_shows_watch_bots_on_the_debug_page() -> void:
	var menu: MainMenu = _make_menu(true)
	var button: Button = menu.get_node("%WatchBotsButton") as Button
	assert_false(button.is_visible_in_tree(), "hidden on the home page")
	menu._on_debug_pressed()
	assert_true(button.is_visible_in_tree(), "debug mode: the Debug page offers Watch bots")
	assert_not_null(menu._watch_bots_dialog)


func test_player_build_has_no_watch_bots_entry() -> void:
	var menu: MainMenu = _make_menu(false)
	assert_false((menu.get_node("%DebugButton") as Button).visible, "no Debug entry without debug mode")
	assert_null(menu._watch_bots_dialog, "no picker is built without debug mode")
	menu._on_watch_bots_pressed()
	menu._on_watch_bots_confirmed(WatchBotsOptions.defaults())
	assert_false((menu.get_node("%WatchBotsButton") as Button).is_visible_in_tree())


func test_picker_start_builds_an_all_bot_config_with_the_chosen_values() -> void:
	var dialog: WatchBotsDialog = WatchBotsDialog.new()
	add_child_autofree(dialog)
	dialog.confirmed.connect(_on_picked)
	var chosen: WatchBotsOptions = WatchBotsOptions.new()
	chosen.bots = 6
	chosen.mode = MatchConfig.GameMode.ELIMINATION
	chosen.difficulty = WatchBotsOptions.Difficulty.HARD
	chosen.gifts = false
	chosen.weather = false
	dialog.apply_options(chosen)
	dialog.actions()[0].pressed.emit()
	assert_not_null(_picked, "Start emits the choices")
	var config: MatchConfig = _picked.build_config(load("res://config/match_defaults.tres") as MatchConfig)
	assert_eq(config.player_count, 6)
	assert_eq(config.ai_count, 6, "player_count == ai_count: no human seat")
	assert_eq(config.game_mode, MatchConfig.GameMode.ELIMINATION)
	assert_eq(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.HARD)
	assert_eq(config.ai_difficulty_for_slot(5), MatchConfig.AiDifficulty.HARD)
	assert_false(config.gifts_enabled)
	assert_eq(config.weather_mode, MatchConfig.WeatherMode.OFF)


func test_mixed_difficulty_spreads_levels_over_the_seats() -> void:
	var options: WatchBotsOptions = WatchBotsOptions.new()
	options.bots = FOLLOW_SLOTS + 1
	options.difficulty = WatchBotsOptions.Difficulty.MIXED
	var config: MatchConfig = options.build_config(load("res://config/match_defaults.tres") as MatchConfig)
	assert_eq(config.ai_difficulty_for_slot(0), MatchConfig.AiDifficulty.EASY)
	assert_eq(config.ai_difficulty_for_slot(1), MatchConfig.AiDifficulty.NORMAL)
	assert_eq(config.ai_difficulty_for_slot(2), MatchConfig.AiDifficulty.HARD)
	assert_eq(config.ai_difficulty_for_slot(3), MatchConfig.AiDifficulty.EASY)


func test_command_line_builds_the_same_config_as_the_picker() -> void:
	var from_cli: WatchBotsOptions = WatchBotsOptions.from_args(PackedStringArray(["--watch-bots=2", "--mode=ctf", "--difficulty=hard"]), WatchBotsOptions.defaults())
	var by_hand: WatchBotsOptions = WatchBotsOptions.defaults()
	by_hand.bots = 2
	by_hand.mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	by_hand.difficulty = WatchBotsOptions.Difficulty.HARD
	var base: MatchConfig = load("res://config/match_defaults.tres") as MatchConfig
	var a: MatchConfig = from_cli.build_config(base)
	var b: MatchConfig = by_hand.build_config(base)
	assert_eq(a.to_dict(), b.to_dict(), "one code path: the CLI and the picker give the same config")
	assert_eq(a.player_count, 2)
	assert_eq(a.ai_count, 2)
	assert_true(WatchBotsOptions.has_cli(PackedStringArray(["--watch-bots=2"])))
	assert_false(WatchBotsOptions.has_cli(PackedStringArray(["--headless-host", "--bots=2"])))


func test_bot_count_is_clamped_to_the_tuned_range() -> void:
	var low: WatchBotsOptions = WatchBotsOptions.from_args(PackedStringArray(["--watch-bots=1"]), WatchBotsOptions.defaults())
	var high: WatchBotsOptions = WatchBotsOptions.from_args(PackedStringArray(["--watch-bots=99"]), WatchBotsOptions.defaults())
	assert_eq(low.bots, WatchBotsOptions.tuning().min_bots)
	assert_eq(high.bots, WatchBotsOptions.tuning().max_bots)


# --- The match ---------------------------------------------------------------------

func test_watch_match_has_no_local_seat_and_a_bot_per_slot() -> void:
	_make_main()
	var options: WatchBotsOptions = WatchBotsOptions.defaults()
	options.bots = TEST_BOTS
	await _main.start_watch_bots(options)
	assert_eq(Match.slot_count(), TEST_BOTS)
	assert_eq(Match.config.player_count, Match.config.ai_count, "every seat is a bot")
	assert_null(_main._hot_seat, "no HotSeat: nothing to place, no ghost, no held block")
	assert_eq(_main._bot_controllers.size(), TEST_BOTS, "a bot controller per seat")
	assert_not_null(_main._spectator, "the spectator controller stands in for the player")
	for _i: int in range(PHYSICS_FRAMES):
		await get_tree().physics_frame
	assert_eq(get_tree().get_nodes_in_group(GhostPreview.LOCAL_HELD_GROUP).size(), 0, "no local held block")


func test_player_build_never_builds_a_spectator() -> void:
	DebugMode.set_override_for_test(false)
	_make_main()
	var options: WatchBotsOptions = WatchBotsOptions.defaults()
	options.bots = TEST_BOTS
	await _main.start_watch_bots(options)
	assert_null(_main._spectator)
	assert_false(_main._watch_bots_active)


# --- Spectator controls ------------------------------------------------------------

func _make_spectator(slots: int) -> SpectatorController:
	var spectator: SpectatorController = SpectatorController.new()
	add_child_autofree(spectator)
	spectator.setup(null, slots)
	return spectator


func test_follow_next_and_prev_cycle_the_bot_slots_and_wrap() -> void:
	var spectator: SpectatorController = _make_spectator(FOLLOW_SLOTS)
	assert_eq(spectator.follow_slot(), SpectatorController.OVERVIEW)
	for expected: int in [0, 1, 2, 0]:
		spectator.follow_next()
		assert_eq(spectator.follow_slot(), expected)
	spectator.follow_prev()
	assert_eq(spectator.follow_slot(), FOLLOW_SLOTS - 1, "previous wraps to the last bot")
	spectator.overview()
	assert_false(spectator.is_following())
	spectator.follow_prev()
	assert_eq(spectator.follow_slot(), FOLLOW_SLOTS - 1, "previous from the overview starts at the last bot")


func test_overview_returns_to_the_free_camera() -> void:
	var spectator: SpectatorController = _make_spectator(FOLLOW_SLOTS)
	watch_signals(spectator)
	spectator.follow_next()
	spectator.overview()
	assert_eq(spectator.follow_slot(), SpectatorController.OVERVIEW)
	assert_signal_emit_count(spectator, "follow_changed", 2)


func test_speed_steps_1x_2x_4x_and_back_and_pause_freezes() -> void:
	var spectator: SpectatorController = _make_spectator(TEST_BOTS)
	var speeds: PackedFloat32Array = WatchBotsOptions.tuning().speeds
	assert_eq(Engine.time_scale, speeds[0])
	for step: int in range(1, speeds.size()):
		spectator.cycle_speed()
		assert_eq(Engine.time_scale, speeds[step])
	spectator.cycle_speed()
	assert_eq(Engine.time_scale, speeds[0], "4x steps back to 1x")
	spectator.toggle_pause()
	assert_true(spectator.is_paused())
	assert_eq(Engine.time_scale, 0.0)
	spectator.toggle_pause()
	assert_eq(Engine.time_scale, speeds[0], "unpausing resumes the speed it had")


func test_time_scale_returns_to_normal_when_the_match_ends() -> void:
	var spectator: SpectatorController = _make_spectator(TEST_BOTS)
	spectator.cycle_speed()
	assert_ne(Engine.time_scale, 1.0)
	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.END)
	assert_eq(Engine.time_scale, 1.0, "results screen runs at normal speed")


func test_time_scale_returns_to_normal_when_the_spectator_leaves_the_tree() -> void:
	var spectator: SpectatorController = SpectatorController.new()
	add_child(spectator)
	spectator.setup(null, TEST_BOTS)
	spectator.cycle_speed()
	spectator.toggle_pause()
	spectator.free()
	assert_eq(Engine.time_scale, 1.0)


func test_spectate_actions_work_through_the_input_map() -> void:
	var spectator: SpectatorController = _make_spectator(FOLLOW_SLOTS)
	var next: InputEventAction = InputEventAction.new()
	next.action = SpectatorController.NEXT_ACTION
	next.pressed = true
	spectator._unhandled_input(next)
	assert_eq(spectator.follow_slot(), 0)
	var speed: InputEventAction = InputEventAction.new()
	speed.action = SpectatorController.SPEED_UP_ACTION
	speed.pressed = true
	spectator._unhandled_input(speed)
	assert_eq(Engine.time_scale, WatchBotsOptions.tuning().speeds[1])


func test_every_spectate_action_has_a_keyboard_and_a_gamepad_binding() -> void:
	for action: StringName in [
		SpectatorController.NEXT_ACTION, SpectatorController.PREV_ACTION, SpectatorController.OVERVIEW_ACTION,
		SpectatorController.SPEED_UP_ACTION, SpectatorController.PAUSE_ACTION,
	]:
		assert_true(InputMap.has_action(action), "%s exists" % action)
		var has_key: bool = false
		var has_pad: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			has_key = has_key or event is InputEventKey
			has_pad = has_pad or event is InputEventJoypadButton
			assert_eq(event.device, -1, "%s accepts any device" % action)
		assert_true(has_key, "%s has a keyboard binding" % action)
		assert_true(has_pad, "%s has a gamepad binding" % action)
