extends GutTest
## The roster extracted from ui/lobby/Lobby.gd into ui/lobby/LobbyPlayersPanel behaves
## exactly as it did inside the Lobby, the narrow Lobby <-> panel hooks are installed
## (seats_data() merged into a host publish, apply(config, roster, seats) from
## the applied lobby data, on_roster_changed, finalize_start_config() after the peer clamp,
## start_blocker() in Start and the button gate, the request signals, focus entries),
## and (PL1a) the rows are ui/lobby/LobbySeatRow views over the panel's seat table:
## the host cycles a colour (swap on a clash) / team pick (1..cap, Random) with a
## click, a right click or ui_left / ui_right / ui_accept, picks a bot's difficulty and
## removes bots; a client's rows are read-only.


## A panel whose Start hooks can be scripted: stands in for what PL1 will do
## (resolve teams in finalize_start_config, block Start with a reason).
class HookPanel extends LobbyPlayersPanel:
	var blocker: String = ""
	var entries: Array[Control] = []
	var finalized_player_counts: Array[int] = []
	var seed_to_write: int = -1
	var finalize_reason: String = ""

	func start_blocker() -> String:
		return blocker

	func finalize_start_config(config: MatchConfig) -> String:
		finalized_player_counts.append(config.player_count)
		if seed_to_write >= 0:
			config.rng_seed = seed_to_write
		return finalize_reason

	func focus_entries() -> Array[Control]:
		return entries


## HookPanel with one focusable control, built before the Lobby wires its loop.
class FocusPanel extends HookPanel:
	func _ready() -> void:
		super()
		var button: Button = Button.new()
		button.name = "SeatButton"
		add_child(button)
		entries.append(button)


func after_each() -> void:
	DebugMode.clear_override_for_test()  # the debug-only row-style switch is a focus stop
	# synthetic events parsed into the global Input singleton stay latched
	# (stick axis, ui_* actions) for every later script in the same process; clear them.
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func _make_lobby(is_host: bool, panel_script: Script = null) -> Lobby:
	DebugMode.set_override_for_test(false)  # these tests pin the shipped (non-debug) panel
	var scene: PackedScene = load("res://ui/lobby/Lobby.tscn")
	var lobby: Lobby = autofree(scene.instantiate())
	if panel_script != null:
		# Before _ready(): the swapped script's @onready vars resolve normally.
		(lobby.get_node("%PlayersPanel") as Node).set_script(panel_script)
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _fake_of(lobby: Lobby) -> FakeNet:
	return lobby.net_provider as FakeNet


func _panel_of(lobby: Lobby) -> LobbyPlayersPanel:
	return lobby.get_node("%PlayersPanel") as LobbyPlayersPanel


func _header_of(lobby: Lobby) -> Label:
	return _panel_of(lobby).get_node("%PlayerCountLabel") as Label


func _last_published(lobby: Lobby) -> Dictionary:
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	return calls[calls.size() - 1]


func _row_name(row: Node) -> String:
	return (row as LobbySeatRow).name_label.text


func _row_subtitle(row: Node) -> String:
	return (row as LobbySeatRow).subtitle_label.text


func _row_badge(row: Node) -> String:
	var badge: UiStatusBadge = (row as LobbySeatRow).badge
	if UiStatusBadge.has_mark(badge.variant):
		return "tick" if badge.variant == UiStatusBadge.Look.READY else "hourglass"
	return badge.label.text


func _row_badge_name(row: Node) -> String:
	return (row as LobbySeatRow).badge.get_accessibility_name()


func _rows_of(lobby: Lobby) -> Array[LobbySeatRow]:
	return LobbyProbe.seat_rows(lobby)


func _two_humans_data(ready_guest: bool) -> Dictionary:
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": ready_guest},
	]
	return data


# --- Scene structure and wiring ---------------------------------------------------

func test_human_rows_name_subtitle_and_ready_badge() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_eq(rows.size(), 2)
	assert_eq(_row_name(rows[0]), "Host")
	assert_eq(_row_subtitle(rows[0]), "Host · you", "the local peer is peer 1 on a FakeNet")
	_assert_host_crown(rows[0])
	assert_eq(_header_of(lobby).text, "2 players · 2/%d seats" % MatchConfig.PLAYER_COUNT_MAX)
	assert_eq(_row_name(rows[1]), "Guest")
	assert_eq(_row_subtitle(rows[1]), "LAN · 0 ms")
	assert_eq(_row_badge(rows[1]), "hourglass")
	assert_eq(_row_badge_name(rows[1]), "Not ready")


func _assert_host_crown(row: Node) -> void:
	var badge: UiStatusBadge = (row as LobbySeatRow).badge
	var crown: TextureRect = badge.get_node_or_null("HostCrown") as TextureRect
	assert_not_null(crown, "the host row shows a crown, not the Ready pill")
	assert_eq(crown.texture, UiArtTable.shared().lobby_icon(UiArtTable.KEY_HOST_CROWN))
	assert_eq(badge.get_accessibility_name(), "Host")


func test_the_seat_table_round_trips_through_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0}
	var seats: Dictionary = {
		"humans": [{"peer_id": 1, "color": 3, "team": 2}],
		"bots": [{"color": 5, "team": 0, "difficulty": 2}],
	}
	var data: Dictionary = MatchConfig.new().to_dict()
	data["seats"] = seats
	data["player_count"] = 2
	data["ai_count"] = 1
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	# The table matches the live roster (peer 1 + one bot), so the reconcile keeps
	# every pick.
	var kept: Dictionary = _panel_of(lobby).seats_data()
	assert_eq(kept, seats, "apply() keeps a consistent table as it is")
	assert_eq(LobbySeats.color_of(kept, LobbySeats.human_key(1)), 3)
	assert_eq(LobbySeats.team_of(kept, LobbySeats.human_key(1)), 2)
	assert_eq(LobbySeats.color_of(kept, LobbySeats.bot_key(0)), 5)
	assert_eq(LobbySeats.difficulty_of(kept, LobbySeats.bot_key(0)), 2)
	# Any later host publish carries it, so a settings edit never drops it.
	lobby._on_setting_changed()
	assert_eq(LobbySeats.color_of(_last_published(lobby)["seats"] as Dictionary, LobbySeats.human_key(1)), 3)


func test_teams_toggled_writes_off_or_four_teams_and_publishes() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: OptionButton = lobby.get_node("%TeamModeOption") as OptionButton
	_panel_of(lobby).teams_toggled.emit(true)
	assert_eq(option.selected, int(MatchConfig.TeamMode.TEAMS_4), "on = up to 4 teams (plan D8)")
	assert_eq(int(_last_published(lobby).get("team_mode")), int(MatchConfig.TeamMode.TEAMS_4))
	_panel_of(lobby).teams_toggled.emit(false)
	assert_eq(option.selected, int(MatchConfig.TeamMode.OFF))
	assert_eq(int(_last_published(lobby).get("team_mode")), int(MatchConfig.TeamMode.OFF))


func test_add_bot_grows_the_seat_count_to_humans_plus_bots_and_publishes() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0}
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	panel.add_bot_requested.emit()
	assert_eq(int(_last_published(lobby).get("ai_count")), 1)
	assert_eq(int(_last_published(lobby).get("player_count")), 2, "1 human + 1 bot = 2 seats")
	assert_eq(_header_of(lobby).text, "1 player · 1 bot · 2/8 seats")
	panel.add_bot_requested.emit()
	assert_eq(int(_last_published(lobby).get("ai_count")), 2)
	assert_eq(int(_last_published(lobby).get("player_count")), 3)
	assert_eq(_header_of(lobby).text, "1 player · 2 bots · 3/8 seats")
	assert_eq(_rows_of(lobby).size(), 3)


func test_remove_bot_shrinks_bots_and_seats_together() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0}
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	panel.add_bot_requested.emit()
	panel.add_bot_requested.emit()
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 2)
	panel.remove_bot_requested.emit(0)
	assert_eq(int(_last_published(lobby).get("ai_count")), 1)
	assert_eq(int(_last_published(lobby).get("player_count")), 2)
	panel.remove_bot_requested.emit(0)
	assert_eq(int(_last_published(lobby).get("ai_count")), 0)
	assert_eq(_header_of(lobby).text.substr(0, 9), "1 player ", "no bots left to announce")
	panel.remove_bot_requested.emit(0)
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 0, "never below zero")


func test_a_start_blocker_disables_start_explains_it_and_gates_every_start_path() -> void:
	var lobby: Lobby = _make_lobby(true, HookPanel)
	var panel: HookPanel = _panel_of(lobby) as HookPanel
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	var start: Button = lobby.get_node("%StartButton") as Button
	lobby._update_host_only_state()
	assert_false(start.disabled, "ready and unblocked: Start is live")
	assert_eq(start.tooltip_text, "")

	panel.blocker = "Teams are on but every player is on the same team."
	lobby._update_host_only_state()
	assert_true(start.disabled)
	assert_eq(start.tooltip_text, "", "Start carries no tooltip")

	watch_signals(lobby)
	lobby._on_start_pressed()
	assert_signal_not_emitted(lobby, "start_requested", "a direct call (the X shortcut) honours the blocker too")
	assert_true(panel.finalized_player_counts.is_empty(), "a blocked Start never reaches finalize")

	var x_event: InputEventAction = InputEventAction.new()
	x_event.action = "lobby_confirm"
	x_event.pressed = true
	lobby._input(x_event)
	assert_signal_not_emitted(lobby, "start_requested")

	panel.blocker = ""
	lobby._update_host_only_state()
	assert_false(start.disabled)
	assert_eq(start.tooltip_text, "")
	lobby._on_start_pressed()
	assert_signal_emitted(lobby, "start_requested")


## A host lobby with `humans` peers (peer n holds slot n - 1), `bots` bots and, optionally,
## teams on, published once so the rows and the seat table exist.
func _host_lobby(humans: int, bots: int = 0, teams_on: bool = false) -> Lobby:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	for index: int in range(humans):
		fake.slots_by_peer[index + 1] = index
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = clampi(humans + bots, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	(lobby.get_node("%AiCountSpin") as SpinBox).value = bots
	if teams_on:
		_panel_of(lobby).teams_toggled.emit(true)
	lobby._on_setting_changed()
	return lobby


## The seat table of the last host publish.
func _seat_table(lobby: Lobby) -> Dictionary:
	return _last_published(lobby)["seats"] as Dictionary


func _human_color(lobby: Lobby, peer_id: int) -> int:
	return LobbySeats.color_of(_seat_table(lobby), LobbySeats.human_key(peer_id))


func _box_color(button: Button) -> Color:
	return (button.get_node("SlotDiamond") as SlotDiamond).color


func _right_click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func test_the_host_colour_click_cycles_the_colour_and_swaps_on_a_clash() -> void:
	var lobby: Lobby = _host_lobby(2)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_eq(_human_color(lobby, 1), 0, "new seats take the lowest free colour")
	assert_eq(_human_color(lobby, 2), 1)
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	watch_signals(panel)
	_rows_of(lobby)[0].color_button.pressed.emit()
	assert_signal_emitted(panel, "seats_changed")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published + 1, "one republish per edit")
	assert_eq(_human_color(lobby, 1), 1, "the click takes the next colour")
	assert_eq(_human_color(lobby, 2), 0, "the seat that held it swaps into the old colour")
	var palette: PackedColorArray = lobby.default_config.player_colors
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_eq(_box_color(rows[0].color_button), palette[1], "the rows are redrawn from the table")
	assert_eq(_box_color(rows[1].color_button), palette[0])


func test_a_bots_dropdown_sets_only_that_bots_difficulty() -> void:
	var lobby: Lobby = _host_lobby(1, 2)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_null(rows[0].difficulty_option, "a human has no difficulty")
	assert_eq(rows[1].difficulty_option.get_item_count(), 3, "Easy / Normal / Hard")
	assert_eq(rows[1].difficulty_option.get_item_text(2), "Hard")
	watch_signals(panel)
	rows[1].difficulty_option.item_selected.emit(MatchConfig.AiDifficulty.HARD)
	assert_signal_emitted(panel, "seats_changed")
	var seats: Dictionary = _seat_table(lobby)
	assert_eq(LobbySeats.difficulty_of(seats, LobbySeats.bot_key(0)), MatchConfig.AiDifficulty.HARD)
	assert_eq(LobbySeats.difficulty_of(seats, LobbySeats.bot_key(1)), MatchConfig.AiDifficulty.NORMAL)
	assert_eq(_rows_of(lobby)[1].difficulty_option.selected(), MatchConfig.AiDifficulty.HARD, "the row shows it")
	var roster: Array = _last_published(lobby)["roster"] as Array
	assert_eq(str((roster[1] as Dictionary)["name"]), "%s (Hard)" % _panel_of(lobby)._config.bot_names[0], "the published roster entry carries the bot's own difficulty")
	assert_eq(str((roster[2] as Dictionary)["name"]), "%s (Normal)" % _panel_of(lobby)._config.bot_names[1])


func test_remove_bot_drops_the_seat_compacts_the_rest_and_asks_the_lobby_for_one_fewer() -> void:
	var lobby: Lobby = _host_lobby(1, 2)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	var second_color: int = LobbySeats.color_of(_seat_table(lobby), LobbySeats.bot_key(1))
	watch_signals(panel)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_not_null(rows[1].remove_button)
	assert_null(rows[0].remove_button, "a human cannot be removed")
	rows[1].remove_button.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "remove_bot_requested", [0])
	assert_eq(int(_last_published(lobby).get("ai_count")), 1)
	var seats: Dictionary = _seat_table(lobby)
	assert_eq(LobbySeats.bot_count(seats), 1)
	assert_eq(LobbySeats.color_of(seats, LobbySeats.bot_key(0)), second_color, "the later bot moved down with its picks")
	assert_eq(_rows_of(lobby).size(), 2, "one human + one bot row left")
	assert_eq(_header_of(lobby).text, "1 player · 1 bot · 2/8 seats")


func test_a_clients_rows_are_read_only() -> void:
	var lobby: Lobby = _make_lobby(false)
	# A client that holds no seat of its own (a spectator): nothing at all is editable.
	_fake_of(lobby).local_peer_id_value = 99
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	var data: Dictionary = _two_humans_data(true)
	data["team_mode"] = MatchConfig.TeamMode.TEAMS_4
	data["player_count"] = 3
	data["ai_count"] = 1
	Events.net_lobby_data_changed.emit(data)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_eq(rows.size(), 3)
	for row: LobbySeatRow in rows:
		assert_true(row.color_button.disabled)
		assert_eq(row.color_button.focus_mode, Control.FOCUS_NONE)
		assert_not_null(row.team_button, "the numbers are shown...")
		assert_true(row.team_button.disabled, "...but not editable")
		assert_null(row.remove_button, "no remove button for a client")
	assert_true(rows[2].difficulty_option.disabled)
	assert_eq(rows[2].difficulty_option.selected(), MatchConfig.AiDifficulty.NORMAL, "a client still sees the bot's difficulty")
	assert_true(panel.focus_entries().is_empty(), "nothing of a client's rows joins the focus loop")
	var before: Dictionary = panel.seats_data()
	watch_signals(panel)
	rows[0].color_button.pressed.emit()
	rows[0].color_button.gui_input.emit(_right_click())
	rows[0].team_button.pressed.emit()
	rows[2].difficulty_option.item_selected.emit(MatchConfig.AiDifficulty.HARD)
	panel._on_color_cycle_requested(rows[0].seat_key, false)
	panel._on_team_cycle_requested(rows[0].seat_key, false)
	panel._on_difficulty_chosen(rows[2].seat_key, MatchConfig.AiDifficulty.HARD)
	panel._on_remove_requested(rows[2].seat_key)
	assert_signal_not_emitted(panel, "seats_changed")
	assert_signal_not_emitted(panel, "remove_bot_requested")
	assert_eq(panel.seats_data(), before, "the table did not move")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


## A FakeNet that, like the real Net, reports a running match.
class RunningMatchNet extends FakeNet:
	var in_progress: bool = false

	func match_in_progress() -> bool:
		return in_progress


func _teams_toggle(lobby: Lobby) -> UiToggle:
	return _panel_of(lobby).get_node("%TeamsToggle") as UiToggle


func _add_bot_button(lobby: Lobby) -> Button:
	return _panel_of(lobby).get_node("%AddBotButton") as Button


func _blocker_label(lobby: Lobby) -> Label:
	return _panel_of(lobby).get_node("%StartBlockerLabel") as Label


## Lobby data as a host publishes it: `humans` peers (peer n holds slot n - 1), `bots` bots,
## the given team mode and seat table, applied like an inbound lobby-data event (so nothing is
## republished). FakeNet's slot map follows.
func _apply_seats(lobby: Lobby, humans: int, bots: int, team_mode: int, seats: Dictionary) -> void:
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer.clear()
	var roster: Array[Dictionary] = []
	for index: int in range(humans):
		fake.slots_by_peer[index + 1] = index
		roster.append({"peer_id": index + 1, "slot_id": index, "name": "P%d" % (index + 1), "ready": true})
	var data: Dictionary = MatchConfig.new().to_dict()
	data["team_mode"] = team_mode
	data["player_count"] = clampi(humans + bots, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	data["ai_count"] = bots
	data["roster"] = roster
	data["seats"] = seats
	Events.net_lobby_data_changed.emit(data)


func _human_seat(peer_id: int, color: int, team: int) -> Dictionary:
	return {"peer_id": peer_id, "color": color, "team": team}


func _bot_seat(color: int, team: int, difficulty: int) -> Dictionary:
	return {"color": color, "team": team, "difficulty": difficulty}


## A client lobby whose local player is `local_peer`, showing `humans` peers + `bots` bots.
func _client_lobby(local_peer: int, humans: int, bots: int, team_mode: int, seats: Dictionary) -> Lobby:
	var lobby: Lobby = _make_lobby(false)
	_fake_of(lobby).local_peer_id_value = local_peer
	_apply_seats(lobby, humans, bots, team_mode, seats)
	return lobby


## Presses Start (everyone ready) and returns the config it emitted, or null when it did not
## start.
func _press_start(lobby: Lobby) -> MatchConfig:
	_fake_of(lobby).all_peers_ready_value = true
	var started: Array[MatchConfig] = []
	var collect: Callable = func(config: MatchConfig) -> void: started.append(config)
	lobby.start_requested.connect(collect)
	lobby._on_start_pressed()
	lobby.start_requested.disconnect(collect)
	return started[0] if not started.is_empty() else null


func test_a_client_may_change_only_its_own_colour_and_team() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 1, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)],
		"bots": [_bot_seat(2, 1, 1)],
	})
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_true(rows[0].color_button.disabled, "the host's row is read-only for a client")
	assert_true(rows[2].color_button.disabled and rows[2].team_button.disabled, "so is the bot's")
	assert_false(rows[1].color_button.disabled, "its own colour box is live")
	assert_false(rows[1].team_button.disabled, "and its own team number")
	assert_true(rows[2].difficulty_option.disabled, "a bot's difficulty stays the host's")
	assert_null(rows[1].remove_button, "no remove button for anyone but the host")
	assert_eq(_panel_of(lobby).focus_entries(), [rows[1].color_button, rows[1].team_button] as Array[Control], "only the own row joins the loop")
	# A client has no Start button: the pad loop through its own row closes and never stops on an invisible one.
	var stops: Array[Control] = FocusWalk.loop(rows[1].color_button)
	assert_true(stops.has(rows[1].team_button), "the own team number is on the loop")
	assert_false(stops.has(rows[0].color_button), "the host's row is no focus stop for a client")
	assert_true(FocusWalk.is_closed(stops, rows[1].color_button), "the loop wraps back to where it started")
	for stop: Control in stops:
		assert_true(stop.is_visible_in_tree(), "%s is no invisible stop" % stop.name)


func test_a_clients_colour_click_asks_the_host_for_the_next_colour_and_changes_nothing_locally() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 5, 2)],
		"bots": [],
	})
	var net: FakeNet = _fake_of(lobby)
	var before: Dictionary = _panel_of(lobby).seats_data()
	_rows_of(lobby)[1].color_button.pressed.emit()
	assert_eq(net.request_seat_pref_calls, [{"color_index": 6, "team_pick": -1}] as Array[Dictionary], "next colour, team untouched")
	_rows_of(lobby)[1].color_button.gui_input.emit(_right_click())
	assert_eq(net.request_seat_pref_calls[1], {"color_index": 4, "team_pick": -1}, "right click: the previous colour")
	assert_eq(_panel_of(lobby).seats_data(), before, "no optimistic update: the row follows the host's echo")
	assert_eq(net.set_lobby_data_calls.size(), 0, "a client never publishes")


func test_a_client_cannot_reach_another_seat_even_with_a_direct_call() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 1, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)],
		"bots": [_bot_seat(2, 1, 1)],
	})
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	panel._on_color_cycle_requested(LobbySeats.human_key(1), false)
	panel._on_team_cycle_requested(LobbySeats.bot_key(0), false)
	panel._on_color_cycle_requested(LobbySeats.KEY_NONE, false)
	assert_true(_fake_of(lobby).request_seat_pref_calls.is_empty())


func test_the_host_ignores_seat_requests_once_start_went_ahead() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	assert_not_null(_press_start(lobby), "Start went through")
	var before: Dictionary = _panel_of(lobby).seats_data()
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	Events.net_seat_pref_requested.emit(2, 5, 4)
	assert_eq(_panel_of(lobby).seats_data(), before, "the table the match was built from stays put")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published)
	assert_true(_teams_toggle(lobby).disabled, "and the header controls close with it")
	assert_true(_add_bot_button(lobby).disabled)


func test_start_is_blocked_with_one_team_and_the_reason_is_shown_near_start() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	_fake_of(lobby).all_peers_ready_value = true
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 1)],
		"bots": [],
	})
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	lobby._update_host_only_state()
	assert_eq(panel.start_blocker(), TeamAssigner.BLOCKER_ONE_TEAM)
	var start: Button = lobby.get_node("%StartButton") as Button
	assert_true(start.disabled)
	assert_eq(_blocker_label(lobby).text, TeamAssigner.BLOCKER_ONE_TEAM, "the reason is written under the rows")
	assert_true(_blocker_label(lobby).visible, "the reason is written under the rows, not only in a tooltip")
	assert_eq(_blocker_label(lobby).text, TeamAssigner.BLOCKER_ONE_TEAM)
	assert_null(_press_start(lobby), "a direct Start (the X shortcut) is refused too")
	# One seat moves to team 2: unblocked, label gone.
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)],
		"bots": [],
	})
	lobby._update_host_only_state()
	assert_eq(panel.start_blocker(), "")
	assert_false(start.disabled)
	assert_false(_blocker_label(lobby).visible)
	assert_not_null(_press_start(lobby))


func test_start_writes_the_seat_colours_teams_and_difficulties_into_the_match_config() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 2, 2, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 4, 2), _human_seat(2, 6, 2)],
		"bots": [_bot_seat(1, 1, MatchConfig.AiDifficulty.HARD), _bot_seat(3, 3, MatchConfig.AiDifficulty.EASY)],
	})
	var config: MatchConfig = _press_start(lobby)
	assert_not_null(config)
	var palette: PackedColorArray = lobby.default_config.player_colors
	assert_eq(config.player_count, 4)
	assert_eq(config.ai_count, 2)
	# Slot 0 / 1 are the humans, 2 / 3 the bots in order.
	assert_eq(config.player_colors[0], palette[4])
	assert_eq(config.player_colors[1], palette[6])
	assert_eq(config.player_colors[2], palette[1])
	assert_eq(config.player_colors[3], palette[3])
	assert_eq(config.slot_ai_difficulties[2], MatchConfig.AiDifficulty.HARD)
	assert_eq(config.slot_ai_difficulties[3], MatchConfig.AiDifficulty.EASY)
	# Picks per slot 2, 2, 1, 3: team numbers 1, 2, 3 -> dense ids 1, 1, 0, 2.
	assert_eq(config.slot_team_ids, PackedInt32Array([1, 1, 0, 2]))
	assert_eq(config.team_numbers, PackedInt32Array([1, 2, 3]))
	assert_eq(config.team_mode, MatchConfig.TeamMode.TEAMS_4)
	# The same config survives the sanitize every match start runs.
	var sanitized: MatchConfig = MatchConfig.from_dict(config.to_dict())
	sanitized.sanitize()
	assert_true(sanitized.teams_resolved(), "the per-slot arrays match player_count and are kept")
	assert_eq(sanitized.slot_team_ids, config.slot_team_ids)


func test_start_is_flattened_after_the_peer_clamp_so_the_team_arrays_survive() -> void:
	# match_defaults ships player_count 4; the two connected peers clamp it to 2. P1 review F1:
	# a team array sized for the old count would be dropped by sanitize.
	var lobby: Lobby = _make_lobby(true)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["team_mode"] = MatchConfig.TeamMode.TEAMS_4
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "A", "ready": true}, {"peer_id": 2, "slot_id": 1, "name": "B", "ready": true},
	]
	data["seats"] = {"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)], "bots": []}
	_fake_of(lobby).slots_by_peer = {1: 0, 2: 1}
	Events.net_lobby_data_changed.emit(data)
	var config: MatchConfig = _press_start(lobby)
	assert_eq(config.player_count, 2)
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 1]))
	var sanitized: MatchConfig = MatchConfig.from_dict(config.to_dict())
	sanitized.sanitize()
	assert_true(sanitized.teams_resolved())
	assert_eq(sanitized.slot_team_ids, PackedInt32Array([0, 1]), "the picks, not a 4-team interleave")


func test_after_a_lobby_leave_start_maps_the_seats_by_the_current_slots() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 3, 1, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2), _human_seat(3, 2, 1)],
		"bots": [_bot_seat(5, 2, MatchConfig.AiDifficulty.HARD)],
	})
	# Peer 2 leaves; Net compacts the lobby's slots (peer 3 moves from slot 2 to 1) and
	# the old slot of peer 3 now belongs to the bot. The panel was not told a thing.
	_fake_of(lobby).slots_by_peer = {1: 0, 3: 1}
	var config: MatchConfig = _press_start(lobby)
	assert_not_null(config, "a stale slot map would have clashed with the bot's slot")
	assert_eq(config.player_count, 3)
	assert_eq(config.ai_count, 1)
	var palette: PackedColorArray = lobby.default_config.player_colors
	assert_eq(config.player_colors[0], palette[0], "the host keeps slot 0")
	assert_eq(config.player_colors[1], palette[2], "peer 3's own colour is now at slot 1")
	assert_eq(config.player_colors[2], palette[5], "the bot trails")
	assert_eq(config.slot_ai_difficulties[2], MatchConfig.AiDifficulty.HARD)
	assert_eq(config.slot_team_ids, PackedInt32Array([0, 0, 1]), "picks 1, 1, 2 (the bot): peer 3 shares the host's team")


const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")


## A second, independent Net instance with its own MultiplayerAPI (the way
## test_net_session.gd plays host and client in one process); `Variant` because Net.gd has no
## class_name.
func _make_net_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func _wait_for(condition: Callable, frames: int = 300) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## Host Lobby on a REAL Net host, a real ENet client: the client's own-seat request travels the
## wire, the host panel applies it and republishes, and Start maps the client's pick onto its
## real slot of the match config.
func test_over_enet_a_clients_colour_and_team_requests_reach_the_hosts_start_config() -> void:
	var host: Variant = _make_net_side("PL1bHostNet")
	var client: Variant = _make_net_side("PL1bClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie"), OK)
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var joined: bool = await _wait_for(func() -> bool:
		return host.peer_ids().size() == 2 and client.local_slot() == 1
	)
	assert_true(joined, "the client is seated in slot 1")

	var lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	lobby.net_provider = host
	lobby._update_host_only_state()
	(lobby.get_node("%TeamModeOption") as OptionButton).select(MatchConfig.TeamMode.TEAMS_4)
	lobby._on_setting_changed()
	var client_id: int = client.local_peer_id()
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_true(LobbySeats.has_seat(panel.seats_data(), LobbySeats.human_key(client_id)), "the client has a seat in the host's table")
	assert_eq(LobbySeats.color_of(panel.seats_data(), LobbySeats.human_key(client_id)), 1)

	client.request_seat_pref(5, 3)
	var applied: bool = await _wait_for(func() -> bool:
		return LobbySeats.color_of(panel.seats_data(), LobbySeats.human_key(client_id)) == 5
	)
	assert_true(applied, "the host applied the request that came over ENet")
	assert_eq(LobbySeats.team_of(panel.seats_data(), LobbySeats.human_key(client_id)), 3)
	var published: Dictionary = host.lobby_data()
	assert_eq(LobbySeats.color_of(published["seats"] as Dictionary, LobbySeats.human_key(client_id)), 5, "and republished the table")
	assert_eq(LobbySeats.color_of(panel.seats_data(), LobbySeats.human_key(Net.HOST_PEER_ID)), 0, "the host's own colour is untouched")

	# Start: everyone ready, host + client + one bot-free lobby; the client sits in its real slot.
	client.set_local_ready(true)
	var ready_ok: bool = await _wait_for(func() -> bool: return host.all_peers_ready())
	assert_true(ready_ok)
	var started: Array[MatchConfig] = []
	lobby.start_requested.connect(func(config: MatchConfig) -> void: started.append(config))
	lobby._on_start_pressed()
	assert_eq(started.size(), 1, "Start went through on a real session")
	var config: MatchConfig = started[0]
	assert_eq(config.player_count, 2)
	assert_eq(config.player_colors[1], lobby.default_config.player_colors[5], "the client's colour sits at its own slot")
	assert_eq(config.player_colors[0], lobby.default_config.player_colors[0])
	assert_eq(config.team_numbers.size(), 2, "host (team 1) and client (team 3): two teams")
	assert_eq(config.team_number_for(config.slot_team_ids[1]), 3, "the client's team number survives for the labels")

	# Once Start went ahead the table is closed even to a client that still asks.
	var before: Dictionary = panel.seats_data()
	client.request_seat_pref(2, -1)
	for _i: int in range(20):
		await get_tree().process_frame
	assert_eq(panel.seats_data(), before, "late requests never touch the table the match was built from")
	client.leave()
	host.leave()
	await get_tree().process_frame
	await get_tree().process_frame


## DECISION in ui/lobby/Lobby.gd: the host's Start is its consent -- enabled once every
## OTHER seat is ready -- and its own Ready toggle is hidden; a client keeps its toggle.
func test_host_start_needs_no_own_ready_and_hides_the_ready_toggle_but_a_client_keeps_it() -> void:
	var host: Lobby = _host_lobby(1, 3)
	_fake_of(host).all_peers_ready_value = true
	host._update_host_only_state()
	assert_false((host.get_node("%StartButton") as Button).disabled, "every other seat ready: Start is live")
	assert_false((host.get_node("%ReadyCheck") as CheckButton).visible, "the host's Ready toggle is redundant")
	assert_not_null(_press_start(host), "pressing Start emits the start request")
	var client: Lobby = _make_lobby(false)
	assert_true((client.get_node("%ReadyCheck") as CheckButton).visible, "a client still readies up")
	assert_false((client.get_node("%StartButton") as Button).visible)
