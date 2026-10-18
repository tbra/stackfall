extends GutTest
## The lobby players row has switchable looks (Classic, Roster tiles, Table, Versus board), all built by ONE LobbySeatRow for the vs-bots and the hosted lobby. Every control of the requirement
## table exists, is operable (synthetic clicks, ui_accept from a pad press, dropdown picks), a client cannot use
## the host's controls, pad focus reaches every control and the footer, and the debug-only switch keeps seat state.

const HUMANS: int = 5
const BOTS: int = 3
const NAMES: Array[String] = ["Atlas", "Tomas", "Ines", "Mira", "Kai"]
const STYLES: Array[int] = [
	LobbySeatVariants.Style.CLASSIC, LobbySeatVariants.Style.TILES,
	LobbySeatVariants.Style.TABLE, LobbySeatVariants.Style.BOARD,
]
const MAX_WALK: int = 200
const OWN_PEER_CLIENT: int = 2


func after_each() -> void:
	DebugMode.clear_override_for_test()
	LobbySeatVariants.chosen = LobbySeatVariants.Style.CLASSIC
	ChatMute.clear()
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


## A lobby for a host (vs-bots: offline; hosted: networked) with `humans` seated peers and `bots` bots.
func _host_lobby(style: int, hosted: bool, humans: int, bots: int, teams: bool) -> Lobby:
	DebugMode.set_override_for_test(true)
	LobbySeatVariants.chosen = style
	var lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = not hosted
	for index: int in range(humans):
		fake.slots_by_peer[index + 1] = index
		fake.names_by_peer[index + 1] = NAMES[index]
		fake.ready_by_peer[index + 1] = index % 2 == 0
	lobby.net_provider = fake
	var panel: LobbyPlayersPanel = _panel(lobby)
	panel.mute_column_override = func() -> bool: return hosted
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = humans + bots
	(lobby.get_node("%AiCountSpin") as SpinBox).value = bots
	lobby._on_setting_changed()
	await wait_frames(2)
	if teams:
		panel.teams_toggled.emit(true)
		await wait_frames(2)
	return lobby


## A client lobby (peer 2 is local) fed the host's data: `humans` peers, `bots` bots, teams on.
func _client_lobby(style: int) -> Lobby:
	DebugMode.set_override_for_test(true)
	LobbySeatVariants.chosen = style
	var lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = false
	fake.is_client_value = true
	fake.is_offline_value = false
	fake.local_peer_id_value = OWN_PEER_CLIENT
	lobby.net_provider = fake
	lobby._update_host_only_state()
	_panel(lobby).mute_column_override = func() -> bool: return true
	var config: MatchConfig = MatchConfig.new()
	config.player_count = HUMANS + BOTS
	config.ai_count = BOTS
	config.team_mode = MatchConfig.TeamMode.TEAMS_4
	var data: Dictionary = config.to_dict()
	var roster: Array[Dictionary] = []
	for index: int in range(HUMANS):
		roster.append({"peer_id": index + 1, "slot_id": index, "name": NAMES[index], "ready": index % 2 == 0})
	data["roster"] = roster
	Events.net_lobby_data_changed.emit(data)
	await wait_frames(3)
	return lobby


func _panel(lobby: Lobby) -> LobbyPlayersPanel:
	return lobby.get_node("%PlayersPanel") as LobbyPlayersPanel


func _rows(lobby: Lobby) -> Array[LobbySeatRow]:
	var rows: Array[LobbySeatRow] = []
	for node: Node in _panel(lobby)._player_rows:
		rows.append(node as LobbySeatRow)
	return rows


func _bot_rows(lobby: Lobby) -> Array[LobbySeatRow]:
	return _rows(lobby).filter(func(row: LobbySeatRow) -> bool: return row.is_bot)


func _row_of(lobby: Lobby, key: int) -> LobbySeatRow:
	for row: LobbySeatRow in _rows(lobby):
		if row.seat_key == key:
			return row
	return null


func _style_label(style: int) -> String:
	return LobbySeatVariants.NAMES[style]


# --- Requirement table: every control exists and works (host) ---------------------------

func test_every_look_has_every_control_in_vsbots_and_hosted_lobbies() -> void:
	for style: int in STYLES:
		for hosted: bool in [false, true]:
			var humans: int = HUMANS if hosted else 1
			for teams: bool in [true, false]:
				var lobby: Lobby = await _host_lobby(style, hosted, humans, BOTS, teams)
				var label: String = "%s %s teams=%s" % [_style_label(style), "hosted" if hosted else "vs-bots", teams]
				var rows: Array[LobbySeatRow] = _rows(lobby)
				assert_eq(rows.size(), humans + BOTS, "%s: one row per seat" % label)
				for row: LobbySeatRow in rows:
					assert_eq(row.variant, style, "%s: the row builds the chosen look" % label)
					assert_true(row.color_button.is_visible_in_tree() and not row.color_button.disabled, "%s: marker is a live control" % label)
					assert_ne(row.name_label.text, "", "%s: name" % label)
					assert_ne(row.subtitle_label.text, "", "%s: sub line" % label)
					assert_not_null(row.badge, "%s: ready / host state" % label)
					assert_eq(row.team_control_of_row() != null, teams, "%s: team control exactly in a team mode (%s)" % [label, row.display_name])
					if row.is_bot:
						assert_not_null(row.difficulty_control(), "%s: bot difficulty" % label)
						assert_not_null(row.remove_button, "%s: remove bot" % label)
						assert_eq(row.mute_button, null, "%s: a bot cannot be muted" % label)
					else:
						assert_null(row.difficulty_control(), "%s: no difficulty on a human" % label)
						assert_null(row.remove_button, "%s: no remove on a human" % label)
						var can_mute: bool = hosted and row.seat_key != Net.local_peer_id() and row.seat_key != 1
						assert_eq(row.mute_button != null, can_mute, "%s: mute only on other humans of a hosted lobby (%s)" % [label, row.display_name])
				assert_eq(_panel(lobby)._open_seat_row.visible, humans + BOTS < MatchConfig.PLAYER_COUNT_MAX, "%s: open seat + Add bot while a seat is free" % label)
				lobby.queue_free()
				await wait_frames(1)


func test_host_can_operate_difficulty_remove_team_and_mute_in_every_look() -> void:
	for style: int in STYLES:
		var lobby: Lobby = await _host_lobby(style, true, HUMANS, BOTS, true)
		var panel: LobbyPlayersPanel = _panel(lobby)
		var label: String = _style_label(style)
		# Difficulty: a press on the skill block / a step on the cycler.
		var bot_key: int = _bot_rows(lobby)[0].seat_key
		var skill: Control = _row_of(lobby, bot_key).difficulty_control()
		if skill is UiIconButton:
			(skill as UiIconButton).pressed.emit()  # Normal -> Hard
		else:
			(skill as UiCycler).nudge(1)
		assert_eq(LobbySeats.difficulty_of(panel._seats, bot_key), MatchConfig.AiDifficulty.HARD, "%s: bot difficulty changed" % label)
		# Team: the cycling team block / the classic dropdown pick.
		var human_key: int = LobbySeats.human_key(2)
		var before: int = LobbySeats.team_of(panel._seats, human_key)
		var team_row: LobbySeatRow = _row_of(lobby, human_key)
		if team_row.team_cycle_button != null:
			team_row.team_cycle_button.pressed.emit()
		else:
			team_row.team_button.pick(before + 1 if before < 4 else 1)
		assert_ne(LobbySeats.team_of(panel._seats, human_key), before, "%s: team changed" % label)
		# Mute: a click toggles the chat mute of that peer.
		var mute: Button = _row_of(lobby, LobbySeats.human_key(3)).mute_button
		assert_not_null(mute, "%s: mute button" % label)
		mute.pressed.emit()
		assert_true(ChatMute.is_muted(3), "%s: muted" % label)
		_row_of(lobby, LobbySeats.human_key(3)).mute_button.pressed.emit()
		assert_false(ChatMute.is_muted(3), "%s: unmuted" % label)
		# Remove: the bot's X drops the seat.
		var bots_before: int = LobbySeats.bot_count(panel._seats)
		_row_of(lobby, bot_key).remove_button.pressed.emit()
		assert_eq(LobbySeats.bot_count(panel._seats), bots_before - 1, "%s: bot removed" % label)
		lobby.queue_free()
		await wait_frames(1)


func test_a_client_cannot_operate_host_only_controls_in_any_look() -> void:
	for style: int in STYLES:
		var lobby: Lobby = await _client_lobby(style)
		var label: String = _style_label(style)
		var rows: Array[LobbySeatRow] = _rows(lobby)
		assert_eq(rows.size(), HUMANS + BOTS, "%s: the client sees every seat" % label)
		for row: LobbySeatRow in rows:
			if row.is_bot:
				assert_null(row.remove_button, "%s: no remove for a client" % label)
				var skill: Control = row.difficulty_control()
				assert_true(skill != null and skill.focus_mode == Control.FOCUS_NONE, "%s: difficulty is read-only" % label)
				assert_true(row.color_button.disabled, "%s: a bot's marker is inert" % label)
			elif row.seat_key == LobbySeats.human_key(OWN_PEER_CLIENT):
				assert_false(row.color_button.disabled, "%s: own marker works" % label)
				var team_control: Control = row.team_control_of_row()
				assert_true(team_control == null or team_control.focus_mode != Control.FOCUS_NONE, "%s: own team works" % label)
			else:
				assert_true(row.color_button.disabled, "%s: another human's marker is inert" % label)
				var other_team: Control = row.team_control_of_row()
				assert_true(other_team == null or other_team.focus_mode == Control.FOCUS_NONE, "%s: another human's team is read-only" % label)
		var offered: Array[Control] = _panel(lobby).focus_entries()
		for control: Control in offered:
			assert_false(control is UiIconButton and (control as UiIconButton).tone == UiIconButton.Tone.DANGER, "%s: no remove X is offered" % label)
		lobby.queue_free()
		await wait_frames(1)


# --- One row class for both lobbies ------------------------------------------------------


func test_vsbots_and_hosted_lobbies_build_the_same_row_for_the_same_seat() -> void:
	for style: int in STYLES:
		var shapes: Array[Array] = []
		for hosted: bool in [false, true]:
			var lobby: Lobby = await _host_lobby(style, hosted, 1, BOTS, true)
			var shape: Array = []
			for row: LobbySeatRow in _rows(lobby):
				shape.append([row.get_script(), row.focusable_controls().size()])
			shapes.append(shape)
			lobby.queue_free()
			await wait_frames(2)
		assert_eq(shapes[0].size(), 1 + BOTS, "%s: every seat is drawn" % _style_label(style))
		assert_eq(shapes[0], shapes[1], "%s: one row class with the same operable controls in both lobbies" % _style_label(style))


func test_pad_focus_reaches_every_control_and_a_pad_press_operates_it() -> void:
	for style: int in STYLES:
		var lobby: Lobby = await _host_lobby(style, true, HUMANS, BOTS, true)
		var panel: LobbyPlayersPanel = _panel(lobby)
		var offered: Array[Control] = panel.focus_entries()
		var label: String = _style_label(style)
		for row: LobbySeatRow in _rows(lobby):
			var controls: Array[Control] = row.focusable_controls()
			for control: Control in controls:
				assert_true(offered.has(control), "%s: %s is a focus stop" % [label, control.name])
				assert_ne(control.focus_mode, Control.FOCUS_NONE, "%s: %s takes focus" % [label, control.name])
			# left / right walk the whole row without a dead end.
			var walked: int = 1
			var at: Control = controls[0]
			while walked < controls.size():
				var next: Control = at.get_node(at.focus_neighbor_right) as Control
				assert_ne(next, at, "%s: no dead end inside %s's row" % [label, row.display_name])
				if next == at:
					break
				at = next
				walked += 1
		var bot: LobbySeatRow = _bot_rows(lobby)[0]
		var bot_key: int = bot.seat_key
		var skill: Control = bot.difficulty_control()
		if skill is UiIconButton:
			var before: int = LobbySeats.difficulty_of(panel._seats, bot_key)
			skill.grab_focus()
			assert_true(skill.has_focus(), "%s: skill takes pad focus" % label)
			var press: InputEventJoypadButton = InputEventJoypadButton.new()
			press.button_index = JOY_BUTTON_A
			press.pressed = true
			Input.parse_input_event(press)
			await wait_frames(2)
			var release: InputEventJoypadButton = InputEventJoypadButton.new()
			release.button_index = JOY_BUTTON_A
			release.pressed = false
			Input.parse_input_event(release)
			await wait_frames(2)
			assert_ne(LobbySeats.difficulty_of(panel._seats, bot_key), before, "%s: a pad accept changes the skill" % label)
		lobby.queue_free()
		await wait_frames(1)


func test_right_click_cycles_team_and_skill_backwards() -> void:
	for style: int in [LobbySeatVariants.Style.TILES, LobbySeatVariants.Style.TABLE, LobbySeatVariants.Style.BOARD]:
		var lobby: Lobby = await _host_lobby(style, true, HUMANS, BOTS, true)
		var panel: LobbyPlayersPanel = _panel(lobby)
		var bot: LobbySeatRow = _bot_rows(lobby)[0]
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		var before: int = LobbySeats.difficulty_of(panel._seats, bot.seat_key)
		bot.skill_button.gui_input.emit(click)
		assert_eq(LobbySeats.difficulty_of(panel._seats, bot.seat_key), posmod(before - 1, 3), "%s: right click = previous skill" % _style_label(style))
		var human_key: int = LobbySeats.human_key(2)
		var team_before: int = LobbySeats.team_of(panel._seats, human_key)
		var row: LobbySeatRow = _row_of(lobby, human_key)
		row.team_cycle_button.gui_input.emit(click)
		assert_ne(LobbySeats.team_of(panel._seats, human_key), team_before, "%s: right click moves the team" % _style_label(style))
		lobby.queue_free()
		await wait_frames(1)


func test_switching_the_look_rebuilds_the_rows_without_touching_the_seats() -> void:
	var lobby: Lobby = await _host_lobby(LobbySeatVariants.Style.CLASSIC, true, HUMANS, BOTS, true)
	var panel: LobbyPlayersPanel = _panel(lobby)
	var table: Dictionary = panel.seats_data()
	for style: int in STYLES:
		panel.set_row_style(style)
		await wait_frames(2)
		assert_eq(_rows(lobby).size(), HUMANS + BOTS, "%s: every seat is still drawn" % _style_label(style))
		assert_eq(panel.seats_data(), table, "%s: the seat table is untouched" % _style_label(style))
		var has_header: bool = panel._extras.any(func(node: Node) -> bool: return node is LobbySeatTableHeader)
		assert_eq(has_header, style == LobbySeatVariants.Style.TABLE, "%s: the header exists only in the table" % _style_label(style))
	DebugMode.set_override_for_test(false)
	assert_eq(LobbySeatVariants.current(), LobbySeatVariants.Style.CLASSIC, "without debug mode only the classic row ships")
	lobby.queue_free()
	await wait_frames(1)


func test_board_makes_a_lane_per_team_and_free_for_all_two_neutral_lanes() -> void:
	var teams: Lobby = await _host_lobby(LobbySeatVariants.Style.BOARD, true, HUMANS, BOTS, true)
	var lanes: Array[Node] = _panel(teams).find_children("*", "LobbySeatLane", true, false)
	assert_gte(lanes.size(), 2, "a lane for each team")
	var seated: int = 0
	for lane: Node in lanes:
		seated += (lane as LobbySeatLane).rows_box.get_children().filter(func(child: Node) -> bool: return child is LobbySeatRow).size()
	assert_eq(seated, HUMANS + BOTS, "every seat sits in exactly one lane")
	teams.queue_free()
	var ffa: Lobby = await _host_lobby(LobbySeatVariants.Style.BOARD, true, HUMANS, BOTS, false)
	var ffa_lanes: Array[Node] = _panel(ffa).find_children("*", "LobbySeatLane", true, false)
	assert_eq(ffa_lanes.size(), 2, "free-for-all: two lanes")
	for lane: Node in ffa_lanes:
		assert_null((lane as LobbySeatLane).cap, "free-for-all lanes carry no team cap")
	ffa.queue_free()
	await wait_frames(1)
