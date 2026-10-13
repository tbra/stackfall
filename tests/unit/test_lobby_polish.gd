extends GutTest
## Bontago-1pi.159.36 / .38 / .39 (owner playtest 2026-10-12): bot difficulty is a UiCycler (seat rows and
## the default), the gravity meter steps exactly 0.1x, the lobby buttons carry their device glyph centred
## with the label and inside the button.

const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const FRAMES: int = 3
const STEP_TOLERANCE: float = 0.0001
const CENTRE_TOLERANCE_PX: float = 1.5


func _make_lobby(bots: int) -> Lobby:
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	fake.slots_by_peer = {1: 0}
	var lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	lobby.net_provider = fake
	add_child_autofree(lobby)
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 1 + bots
	(lobby.get_node("%AiCountSpin") as SpinBox).value = bots
	lobby._on_setting_changed()
	return lobby


func _action(action: StringName, pressed: bool = true) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _seat_rows(lobby: Lobby) -> Array[LobbySeatRow]:
	var rows: Array[LobbySeatRow] = []
	for node: Node in lobby._players_panel._player_rows:
		rows.append(node as LobbySeatRow)
	return rows


func _settle(count: int = FRAMES) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


# --- .36: difficulty cyclers ---------------------------------------------------------------

func test_seat_difficulty_is_a_cycler_stepped_by_pad_keyboard_and_mouse() -> void:
	var lobby: Lobby = _make_lobby(1)
	var row: LobbySeatRow = _seat_rows(lobby)[1]
	var cycler: UiCycler = row.difficulty_option
	assert_not_null(cycler, "a bot row has a UiCycler difficulty")
	assert_eq(cycler.get_item_count(), 3)
	cycler._gui_input(_action(&"ui_right"))  # pad d-pad / stick / keyboard all arrive as ui_right
	cycler._gui_input(_action(&"ui_right", false))
	var seats: Dictionary = lobby._players_panel._seats
	assert_eq(LobbySeats.difficulty_of(seats, LobbySeats.bot_key(0)), MatchConfig.AiDifficulty.HARD, "Normal -> Hard")
	cycler = _seat_rows(lobby)[1].difficulty_option  # the row is rebuilt after a pick
	assert_eq(cycler.selected(), MatchConfig.AiDifficulty.HARD)
	cycler.next_button.button_down.emit()  # mouse on the ">" block
	cycler.next_button.button_up.emit()
	assert_eq(LobbySeats.difficulty_of(lobby._players_panel._seats, LobbySeats.bot_key(0)), MatchConfig.AiDifficulty.EASY, "wraps")


func test_seat_cycler_picks_reach_the_seat_table() -> void:
	var lobby: Lobby = _make_lobby(2)
	var cycler: UiCycler = _seat_rows(lobby)[1].difficulty_option
	cycler.nudge(1)
	var seats: Dictionary = lobby._players_panel._seats
	assert_eq(LobbySeats.difficulty_of(seats, LobbySeats.bot_key(0)), MatchConfig.AiDifficulty.HARD)
	assert_eq(LobbySeats.difficulty_of(seats, LobbySeats.bot_key(1)), MatchConfig.AiDifficulty.NORMAL)


func test_default_difficulty_is_a_cycler_and_keeps_its_config_round_trip() -> void:
	var lobby: Lobby = _make_lobby(2)
	var cycler: UiCycler = lobby.get_node("%AiDifficultyOption") as UiCycler
	assert_not_null(cycler, "the default selector is a UiCycler")
	cycler._gui_input(_action(&"ui_left"))
	cycler._gui_input(_action(&"ui_left", false))
	assert_eq(cycler.selected(), MatchConfig.AiDifficulty.EASY)
	assert_eq(lobby._config_from_controls().ai_difficulty, MatchConfig.AiDifficulty.EASY)
	var config: MatchConfig = MatchConfig.new()
	config.ai_difficulty = MatchConfig.AiDifficulty.HARD
	lobby._apply_data(config.to_dict())
	assert_eq(cycler.selected(), MatchConfig.AiDifficulty.HARD)
	cycler.next_button.button_down.emit()
	cycler.next_button.button_up.emit()
	assert_eq(cycler.selected(), MatchConfig.AiDifficulty.EASY, "mouse clicks the arrows")


# --- .38: gravity meter ----------------------------------------------------------------------

func test_gravity_meter_steps_exactly_a_tenth_and_reaches_one() -> void:
	var lobby: Lobby = _make_lobby(0)
	var meter: UiSegmentMeter = lobby.get_node("%GravityMeter") as UiSegmentMeter
	assert_eq(Lobby.GRAVITY_CELLS, roundi(MatchConfig.GRAVITY_MAX / MatchConfig.GRAVITY_STEP))
	assert_eq(meter.step_count, Lobby.GRAVITY_CELLS)
	var previous: float = -1.0
	for cells: int in range(1, Lobby.GRAVITY_CELLS + 1):
		meter.value = cells
		assert_almost_eq(lobby._gravity_value, 0.1 * float(cells), STEP_TOLERANCE, "cell %d" % cells)
		if previous >= 0.0:
			assert_almost_eq(lobby._gravity_value - previous, 0.1, STEP_TOLERANCE, "each step is 0.1x")
		previous = lobby._gravity_value
	meter.value = 10
	assert_almost_eq(lobby._gravity_value, 1.0, STEP_TOLERANCE, "1.0x is a cell")
	meter.value = 0
	assert_almost_eq(lobby._gravity_value, MatchConfig.GRAVITY_MIN, STEP_TOLERANCE, "an empty meter is the minimum")
	meter.value = Lobby.GRAVITY_CELLS
	assert_almost_eq(lobby._gravity_value, MatchConfig.GRAVITY_MAX, STEP_TOLERANCE)
	assert_eq(Lobby._gravity_cells_for(1.0), 10)
	assert_eq(Lobby._gravity_cells_for(MatchConfig.GRAVITY_MIN), 1)


func test_gravity_meter_steps_by_pad_one_tenth_at_a_time() -> void:
	var lobby: Lobby = _make_lobby(0)
	var meter: UiSegmentMeter = lobby.get_node("%GravityMeter") as UiSegmentMeter
	meter.value = 10
	meter._gui_input(_action(&"ui_right"))
	meter._gui_input(_action(&"ui_right", false))
	assert_almost_eq(lobby._gravity_value, 1.1, STEP_TOLERANCE)


# --- .39: button glyphs ---------------------------------------------------------------------

func _glyph_rect(button: Button) -> Rect2:
	var flow: InputPromptFlow = UiButtonHint.flow_of(button)
	return flow.get_global_transform() * Rect2(Vector2.ZERO, flow.size)


func test_options_and_back_carry_their_glyphs() -> void:
	var lobby: Lobby = _make_lobby(0)
	var options: InputPromptFlow = UiButtonHint.flow_of(lobby.get_node("%OptionsButton") as Button)
	var back: InputPromptFlow = UiButtonHint.flow_of(lobby.get_node("%BackButton") as Button)
	assert_not_null(options)
	assert_not_null(back)
	assert_eq(options.template, "{lobby_options}")
	assert_eq(back.template, "{ui_cancel}")


func test_glyphs_trail_the_label_centred_and_inside_the_button() -> void:
	var lobby: Lobby = _make_lobby(1)
	var buttons: Array[Button] = [
		lobby.get_node("%StartButton") as Button, lobby.get_node("%OptionsButton") as Button,
		lobby.get_node("%BackButton") as Button, lobby._players_panel.add_bot_button(),
	]
	for window_size: Vector2i in SIZES:
		lobby.set_anchors_preset(Control.PRESET_TOP_LEFT)
		lobby.size = Vector2(window_size)
		await _settle()
		for button: Button in buttons:
			if not button.is_visible_in_tree():
				continue
			var rect: Rect2 = button.get_global_rect()
			var glyph: Rect2 = _glyph_rect(button)
			var label: String = "%s at %s" % [button.name, window_size]
			assert_true(rect.encloses(glyph.grow(-0.5)), "%s: glyph %s inside %s" % [label, glyph, rect])
			var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
			var content: float = UiButtonHint.content_width(button)
			var right_gap: float = rect.end.x - glyph.end.x
			var left_gap: float = glyph.position.x - float(arcade.space_2_px) - content - rect.position.x
			assert_almost_eq(left_gap, right_gap, CENTRE_TOLERANCE_PX, "%s: glyph + label are centred" % label)
			var box: StyleBox = button.get_theme_stylebox(&"normal")
			var line_centre: float = rect.position.y + (box.content_margin_top + rect.size.y - box.content_margin_bottom) * 0.5
			var flow: InputPromptFlow = UiButtonHint.flow_of(button)
			var cap_centre: float = glyph.position.y + (glyph.size.y - float(arcade.drop_sm_px) * flow.scale.y) * 0.5
			assert_almost_eq(cap_centre, line_centre, CENTRE_TOLERANCE_PX, "%s: glyph cap is centred on the label line" % label)
