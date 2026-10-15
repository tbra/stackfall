extends GutTest
## / .38 / .39: bot difficulty is a UiCycler (seat rows and
## the default), the gravity meter steps exactly 0.1x, the lobby buttons carry their device glyph centred
## with the label and inside the button.

const LOBBY_SCENE: PackedScene = preload("res://ui/lobby/Lobby.tscn")
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
