extends GutTest
## The lobby's sudden-death length control: a stepper inside the SuddenDeathCol (shown with the
## sudden-death toggle, Classic only) that defaults to MatchConfig's default, takes its range and
## step from MatchConfig, publishes through the host's lobby data, mirrors remote lobby data
## without publishing, is read-only for a client, and steps with keyboard and gamepad.

const LOBBY_SCENE: PackedScene = preload("res://ui/lobby/Lobby.tscn")


func after_each() -> void:
	# Real joypad events flip Settings to gamepad mode; do not leak that into later files.
	Settings._input(InputEventKey.new())


func _make_lobby(is_host: bool) -> Lobby:
	var lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _fake_of(lobby: Lobby) -> FakeNet:
	return lobby.net_provider as FakeNet


## The length stepper, found by type inside the sudden-death column (its node name is the
## implementer's choice; its place in the column is the contract).
func _stepper(lobby: Lobby) -> UiStepper:
	var column: Control = lobby.get_node("%SuddenDeathCol") as Control
	for node: Node in column.find_children("*", "UiStepper", true, false):
		return node as UiStepper
	return null


## Turns sudden death on through the lobby's own toggle (the length stepper is read-only while it is off).
func _enable_sudden_death(lobby: Lobby) -> void:
	(lobby.get_node("%SuddenDeathCheck") as UiToggle).button_pressed = true


func _published(lobby: Lobby) -> MatchConfig:
	return MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: UiCycler = lobby.get_node("%GameModeOption") as UiCycler
	option.select(mode)
	option.item_selected.emit(mode)


func _push_remote(config: MatchConfig) -> void:
	Events.net_lobby_data_changed.emit(config.to_dict())


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _pad(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = pressed
	return event


func _tap(press: InputEvent, release: InputEvent) -> void:
	Input.parse_input_event(press)
	await get_tree().process_frame
	Input.parse_input_event(release)
	await get_tree().process_frame


func test_stepper_exists_in_the_sudden_death_column() -> void:
	var lobby: Lobby = _make_lobby(true)
	assert_not_null(_stepper(lobby), "SuddenDeathCol holds a UiStepper for the length")


func test_defaults_to_the_config_default_and_reads_as_two_minutes() -> void:
	var lobby: Lobby = _make_lobby(true)
	var stepper: UiStepper = _stepper(lobby)
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)
	assert_eq(MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS, 120)
	assert_eq(stepper.display_text(), "2:00")


func test_stepper_range_and_step_come_from_the_config_consts() -> void:
	var stepper: UiStepper = _stepper(_make_lobby(true))
	assert_eq(stepper.min_value, MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	assert_eq(stepper.max_value, MatchConfig.SUDDEN_DEATH_MAX_SECONDS)
	assert_eq(stepper.step, MatchConfig.SUDDEN_DEATH_STEP_SECONDS)


func test_nudges_move_one_step_and_stop_at_both_bounds() -> void:
	var lobby: Lobby = _make_lobby(true)
	_enable_sudden_death(lobby)
	var stepper: UiStepper = _stepper(lobby)
	var step: int = MatchConfig.SUDDEN_DEATH_STEP_SECONDS
	assert_true(stepper.nudge(1))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS + step)
	while stepper.nudge(1):
		pass
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_MAX_SECONDS)
	assert_false(stepper.nudge(1), "no step past the maximum")
	assert_eq(stepper.display_text(), "5:00")
	while stepper.nudge(-1):
		pass
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	assert_false(stepper.nudge(-1), "no step below the minimum")
	assert_eq(stepper.display_text(), "0:30")


func test_a_fresh_lobby_publishes_nothing_until_the_host_edits() -> void:
	var lobby: Lobby = _make_lobby(true)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


func test_host_edit_publishes_the_new_length() -> void:
	var lobby: Lobby = _make_lobby(true)
	_stepper(lobby).value = 60
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_gt(calls.size(), 0, "a host edit publishes lobby data")
	assert_eq(int(calls.back().get("sudden_death_seconds")), 60)
	assert_eq(_published(lobby).sudden_death_seconds, 60)


func test_unrelated_host_edit_publishes_the_default_length() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%SuddenDeathCheck") as UiToggle).button_pressed = true
	var config: MatchConfig = _published(lobby)
	assert_true(config.sudden_death)
	assert_eq(config.sudden_death_seconds, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)


func test_remote_lobby_data_sets_the_stepper_without_publishing() -> void:
	var lobby: Lobby = _make_lobby(false)
	var config: MatchConfig = MatchConfig.new()
	config.sudden_death_seconds = 240
	_push_remote(config)
	assert_eq(_stepper(lobby).value, 240)
	assert_eq(_stepper(lobby).display_text(), "4:00")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0, "mirroring remote data publishes nothing")


func test_host_applying_remote_data_does_not_republish() -> void:
	var lobby: Lobby = _make_lobby(true)
	var config: MatchConfig = MatchConfig.new()
	config.sudden_death_seconds = 90
	_push_remote(config)
	assert_eq(_stepper(lobby).value, 90)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


func test_out_of_range_and_off_step_remote_values_are_sanitized() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["sudden_death_seconds"] = 9999
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_stepper(lobby).value, MatchConfig.SUDDEN_DEATH_MAX_SECONDS)
	data["sudden_death_seconds"] = 1
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_stepper(lobby).value, MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	data["sudden_death_seconds"] = 100
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_stepper(lobby).value, 90, "100 snaps to the nearest 30 s step")


func test_old_lobby_data_without_the_key_shows_the_default() -> void:
	var lobby: Lobby = _make_lobby(false)
	var config: MatchConfig = MatchConfig.new()
	config.sudden_death_seconds = 270
	_push_remote(config)
	var data: Dictionary = MatchConfig.new().to_dict()
	data.erase("sudden_death_seconds")
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_stepper(lobby).value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)


func test_every_stop_round_trips_through_publish_and_apply() -> void:
	var host: Lobby = _make_lobby(true)
	var client: Lobby = _make_lobby(false)
	var seconds: int = MatchConfig.SUDDEN_DEATH_MIN_SECONDS
	while seconds <= MatchConfig.SUDDEN_DEATH_MAX_SECONDS:
		# Move off the target first so the host's edit is a real change that publishes.
		_stepper(host).set_value_silent(MatchConfig.SUDDEN_DEATH_MIN_SECONDS if seconds != MatchConfig.SUDDEN_DEATH_MIN_SECONDS else MatchConfig.SUDDEN_DEATH_MAX_SECONDS)
		_stepper(host).value = seconds
		var data: Dictionary = _fake_of(host).lobby_data_value
		assert_eq(MatchConfig.from_dict(data).sudden_death_seconds, seconds, "published %d" % seconds)
		Events.net_lobby_data_changed.emit(data)
		assert_eq(_stepper(client).value, seconds, "client shows %d" % seconds)
		seconds += MatchConfig.SUDDEN_DEATH_STEP_SECONDS


func test_hidden_outside_classic_and_back_with_value_kept() -> void:
	var lobby: Lobby = _make_lobby(true)
	var column: Control = lobby.get_node("%SuddenDeathCol") as Control
	assert_true(column.visible, "Classic shows the sudden-death length")
	_stepper(lobby).value = 180
	for mode: int in [
		MatchConfig.GameMode.ELIMINATION, MatchConfig.GameMode.REACH_THE_SKY, MatchConfig.GameMode.DOMINATION,
	]:
		_pick_mode(lobby, mode)
		assert_false(column.visible, "mode %d hides the sudden-death length" % mode)
		assert_false(_stepper(lobby).is_visible_in_tree())
	_pick_mode(lobby, MatchConfig.GameMode.CLASSIC)
	assert_true(column.visible)
	assert_eq(_stepper(lobby).value, 180, "leaving and re-entering Classic keeps the length")
	assert_eq(_published(lobby).sudden_death_seconds, 180)


func test_hidden_stepper_is_not_a_focus_stop_outside_classic() -> void:
	var lobby: Lobby = _make_lobby(true)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	var stepper: UiStepper = _stepper(lobby)
	for control: Control in lobby._visible_chain(lobby._main_chain):
		assert_ne(control, stepper, "a hidden stepper is never a focus stop")


func test_client_stepper_is_read_only() -> void:
	var lobby: Lobby = _make_lobby(false)
	var stepper: UiStepper = _stepper(lobby)
	assert_true(stepper.disabled, "a client cannot edit the length")
	assert_false(stepper.nudge(1))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


func test_host_stepper_follows_the_sudden_death_toggle() -> void:
	var lobby: Lobby = _make_lobby(true)
	var stepper: UiStepper = _stepper(lobby)
	assert_true(stepper.disabled, "sudden death starts off, so the length is read-only")
	assert_false(stepper.nudge(1))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)
	var toggle: UiToggle = lobby.get_node("%SuddenDeathCheck") as UiToggle
	toggle.button_pressed = true
	assert_false(stepper.disabled, "the toggle on makes the length editable")
	toggle.button_pressed = false
	assert_true(stepper.disabled, "the toggle off makes it read-only again")


func test_non_host_stepper_stays_read_only_with_sudden_death_on() -> void:
	var lobby: Lobby = _make_lobby(false)
	var config: MatchConfig = MatchConfig.new()
	config.sudden_death = true
	config.sudden_death_seconds = 150
	_push_remote(config)
	var stepper: UiStepper = _stepper(lobby)
	assert_eq(stepper.value, 150)
	assert_true(stepper.disabled)
	assert_false(stepper.nudge(1))


func test_arrow_keys_step_the_focused_stepper() -> void:
	var lobby: Lobby = _make_lobby(true)
	_enable_sudden_death(lobby)
	await wait_process_frames(2)
	var stepper: UiStepper = _stepper(lobby)
	stepper.grab_focus()
	assert_true(stepper.has_focus(), "the stepper takes focus")
	await _tap(_key(KEY_RIGHT, true), _key(KEY_RIGHT, false))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS + MatchConfig.SUDDEN_DEATH_STEP_SECONDS)
	await _tap(_key(KEY_LEFT, true), _key(KEY_LEFT, false))
	await _tap(_key(KEY_LEFT, true), _key(KEY_LEFT, false))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS - MatchConfig.SUDDEN_DEATH_STEP_SECONDS)
	assert_eq(_published(lobby).sudden_death_seconds, stepper.value, "the key step is published")


func test_dpad_steps_the_focused_stepper() -> void:
	var lobby: Lobby = _make_lobby(true)
	_enable_sudden_death(lobby)
	await wait_process_frames(2)
	var stepper: UiStepper = _stepper(lobby)
	stepper.grab_focus()
	assert_true(stepper.has_focus())
	await _tap(_pad(JOY_BUTTON_DPAD_RIGHT, true), _pad(JOY_BUTTON_DPAD_RIGHT, false))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS + MatchConfig.SUDDEN_DEATH_STEP_SECONDS)
	await _tap(_pad(JOY_BUTTON_DPAD_LEFT, true), _pad(JOY_BUTTON_DPAD_LEFT, false))
	await _tap(_pad(JOY_BUTTON_DPAD_LEFT, true), _pad(JOY_BUTTON_DPAD_LEFT, false))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS - MatchConfig.SUDDEN_DEATH_STEP_SECONDS)
	assert_eq(_published(lobby).sudden_death_seconds, stepper.value, "the pad step is published")


func test_client_keys_and_dpad_do_not_change_the_length() -> void:
	var lobby: Lobby = _make_lobby(false)
	await wait_process_frames(2)
	var stepper: UiStepper = _stepper(lobby)
	stepper.grab_focus()
	await _tap(_key(KEY_RIGHT, true), _key(KEY_RIGHT, false))
	await _tap(_pad(JOY_BUTTON_DPAD_RIGHT, true), _pad(JOY_BUTTON_DPAD_RIGHT, false))
	assert_eq(stepper.value, MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)
