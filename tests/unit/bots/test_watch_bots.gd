extends GutTest
## the debug "Watch bots" match -- menu entry, picker, command line, the all-bot
## match with no local seat, and the spectator camera / follow / speed controls.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const TEST_FIELD_RADIUS_M: float = 20.0
const TEST_BOTS: int = 2
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


func _make_main() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = TEST_FIELD_RADIUS_M
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_config.rng_seed = 1014
	_main.match_config = tiny_config
	add_child_autofree(_main)


# --- Menu entry and picker --------------------------------------------------------


# --- The match ---------------------------------------------------------------------


func test_watch_match_has_no_local_seat_and_a_bot_per_slot() -> void:
	_make_main()
	var options: WatchBotsOptions = WatchBotsOptions.defaults()
	options.bots = TEST_BOTS
	await _main.start_watch_bots(options)
	assert_eq(Match.slot_count(), TEST_BOTS)
	assert_eq(Match.config.player_count, Match.config.ai_count, "every seat is a bot")
	assert_null(_main._local_player, "no LocalPlayer: nothing to place, no ghost, no held block")
	assert_eq(_main._bot_controllers.size(), TEST_BOTS, "a bot controller per seat")
	assert_not_null(_main._spectator, "the spectator controller stands in for the player")
	for _i: int in range(PHYSICS_FRAMES):
		await get_tree().physics_frame
	assert_eq(MatchContext.current().local_held().slot_id, -1, "no local held block")


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
	watch_signals(spectator)
	var expected_order: Array[int] = [0, 1, 2, 0]
	for i: int in range(expected_order.size()):
		spectator.follow_next()
		assert_signal_emitted_with_parameters(spectator, "follow_changed", [expected_order[i]], i)
	spectator.follow_prev()
	assert_signal_emitted_with_parameters(spectator, "follow_changed", [FOLLOW_SLOTS - 1], 4)  # previous wraps to the last bot
	spectator.overview()
	assert_signal_emitted_with_parameters(spectator, "follow_changed", [SpectatorController.OVERVIEW], 5)
	spectator.follow_prev()
	assert_signal_emitted_with_parameters(spectator, "follow_changed", [FOLLOW_SLOTS - 1], 6)  # previous from the overview starts at the last bot


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
	assert_eq(Engine.time_scale, 0.0)
	spectator.toggle_pause()
	assert_eq(Engine.time_scale, speeds[0], "unpausing resumes the speed it had")


func test_time_scale_returns_to_normal_when_the_match_ends() -> void:
	var spectator: SpectatorController = _make_spectator(TEST_BOTS)
	spectator.cycle_speed()
	assert_ne(Engine.time_scale, 1.0)
	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.END)
	assert_eq(Engine.time_scale, 1.0, "results screen runs at normal speed")


func test_spectate_actions_work_through_the_input_map() -> void:
	var spectator: SpectatorController = _make_spectator(FOLLOW_SLOTS)
	var next: InputEventAction = InputEventAction.new()
	next.action = SpectatorController.NEXT_ACTION
	next.pressed = true
	watch_signals(spectator)
	spectator._unhandled_input(next)
	assert_signal_emitted_with_parameters(spectator, "follow_changed", [0])
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
