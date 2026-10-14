extends GutTest
## Bontago-1pi.159.43 (round 2): the lobby players row has switchable looks (Classic, Slot, Team groups, Seat
## cards), all built by ONE LobbySeatRow for the vs-bots and the hosted lobby. Every control of the requirement
## table exists, is operable (synthetic clicks, ui_accept from a pad press, dropdown picks), a client cannot use
## the host's controls, pad focus reaches every control and the footer, and the debug-only switch keeps seat state.

const HUMANS: int = 5
const BOTS: int = 3
const NAMES: Array[String] = ["Atlas", "Tomas", "Ines", "Mira", "Kai"]
const STYLES: Array[int] = [
	LobbySeatVariants.Style.CLASSIC, LobbySeatVariants.Style.SLOT,
	LobbySeatVariants.Style.GROUPED, LobbySeatVariants.Style.CARDS,
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
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
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
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
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


func _human_rows(lobby: Lobby) -> Array[LobbySeatRow]:
	return _rows(lobby).filter(func(row: LobbySeatRow) -> bool: return not row.is_bot)


func _row_of(lobby: Lobby, key: int) -> LobbySeatRow:
	for row: LobbySeatRow in _rows(lobby):
		if row.seat_key == key:
			return row
	return null


func _pad_press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


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
		# Difficulty: a pick on the dropdown / a step on the cycler.
		var bot_key: int = _bot_rows(lobby)[0].seat_key
		var skill: Control = _row_of(lobby, bot_key).difficulty_control()
		if skill is UiDropdown:
			(skill as UiDropdown).pick(MatchConfig.AiDifficulty.HARD)
		else:
			(skill as UiCycler).nudge(1)  # Normal -> Hard
		assert_eq(LobbySeats.difficulty_of(panel._seats, bot_key), MatchConfig.AiDifficulty.HARD, "%s: bot difficulty changed" % label)
		# Team: the chip's popup pick / the mover button.
		var human_key: int = LobbySeats.human_key(2)
		var before: int = LobbySeats.team_of(panel._seats, human_key)
		var team_row: LobbySeatRow = _row_of(lobby, human_key)
		if team_row.team_move_button != null:
			team_row.team_move_button.pressed.emit()
		else:
			team_row.team_button.pick(before + 1 if before < 4 else 1)
		assert_ne(LobbySeats.team_of(panel._seats, human_key), before, "%s: team changed" % label)
		# Mute: a click toggles the chat mute of that peer.
		var mute: UiBlockButton = _row_of(lobby, LobbySeats.human_key(3)).mute_button
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


func test_a_pad_accept_presses_the_focused_remove_and_move_buttons() -> void:
	for style: int in [LobbySeatVariants.Style.SLOT, LobbySeatVariants.Style.GROUPED, LobbySeatVariants.Style.CARDS]:
		var lobby: Lobby = await _host_lobby(style, true, HUMANS, BOTS, true)
		var panel: LobbyPlayersPanel = _panel(lobby)
		var bot_key: int = _bot_rows(lobby)[0].seat_key
		var row: LobbySeatRow = _row_of(lobby, bot_key)
		if row.team_move_button != null:
			var before: int = LobbySeats.team_of(panel._seats, bot_key)
			row.team_move_button.grab_focus()
			_pad_press(JOY_BUTTON_A)
			await wait_frames(1)
			assert_ne(LobbySeats.team_of(panel._seats, bot_key), before, "%s: pad A moves the seat to another team" % _style_label(style))
		var bots_before: int = LobbySeats.bot_count(panel._seats)
		_row_of(lobby, bot_key).remove_button.grab_focus()
		_pad_press(JOY_BUTTON_A)
		await wait_frames(1)
		assert_eq(LobbySeats.bot_count(panel._seats), bots_before - 1, "%s: pad A on the X removes the bot" % _style_label(style))
		lobby.queue_free()
		await wait_frames(1)


# --- A client cannot use the host's controls ------------------------------------------------

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
		var solo: Lobby = await _host_lobby(style, false, 1, 3, true)
		var solo_scripts: Array[Script] = []
		var solo_signatures: Array[Array] = []
		for row: LobbySeatRow in _rows(solo):
			solo_scripts.append(row.get_script() as Script)
			solo_signatures.append(_signature(row) if row.is_bot else [])
		solo.queue_free()
		await wait_frames(1)
		var hosted: Lobby = await _host_lobby(style, true, 1, 3, true)
		var rows: Array[LobbySeatRow] = _rows(hosted)
		assert_eq(rows.size(), solo_scripts.size(), "%s: same seats" % _style_label(style))
		for index: int in range(rows.size()):
			assert_eq(rows[index].get_script(), solo_scripts[index], "%s: same row class" % _style_label(style))
			if rows[index].is_bot:
				assert_eq(_signature(rows[index]), solo_signatures[index], "%s: a bot row has the same controls in both lobbies" % _style_label(style))
		hosted.queue_free()
		await wait_frames(1)


func _signature(row: LobbySeatRow) -> Array[String]:
	var names: Array[String] = []
	for control: Control in row.focusable_controls():
		names.append(str(control.name))
	return names


# --- Pad focus walks every control and reaches the footer -------------------------------------

func test_pad_focus_reaches_every_control_and_the_footer_in_every_look() -> void:
	for style: int in STYLES:
		var lobby: Lobby = await _host_lobby(style, true, HUMANS, BOTS, true)
		await wait_frames(3)  # the spatial rewire runs a frame after the rows
		var label: String = _style_label(style)
		var panel: LobbyPlayersPanel = _panel(lobby)
		var entries: Array[Control] = panel.focus_entries()
		assert_gt(entries.size(), HUMANS + BOTS, "%s: many focus stops" % label)
		var reached: Dictionary = {}
		var queue: Array[Control] = [entries[0]]
		var steps: int = 0
		while not queue.is_empty() and steps < MAX_WALK * 4:
			steps += 1
			var current: Control = queue.pop_front()
			if reached.has(current):
				continue
			reached[current] = true
			for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
				var path: NodePath = current.get_focus_neighbor(side)
				var next: Control = current.get_node_or_null(path) as Control if not path.is_empty() else null
				if next != null and next.focus_mode != Control.FOCUS_NONE and not reached.has(next):
					queue.append(next)
		for control: Control in entries:
			assert_true(reached.has(control), "%s: pad can reach %s" % [label, control.get_path()])
		assert_true(reached.has(lobby.get_node("%StartButton")), "%s: the footer's Start is reachable" % label)
		# A real D-pad press from a row lands on its bottom neighbour.
		var start: Control = entries[mini(2, entries.size() - 1)]
		start.grab_focus()
		var expected: Control = start.get_node(start.focus_neighbor_bottom) as Control
		_pad_press(JOY_BUTTON_DPAD_DOWN)
		await wait_frames(1)
		assert_eq(lobby.get_viewport().gui_get_focus_owner(), expected, "%s: D-pad down follows the wiring" % label)
		lobby.queue_free()
		await wait_frames(1)


func test_the_card_grid_hops_sideways_between_cards() -> void:
	var lobby: Lobby = await _host_lobby(LobbySeatVariants.Style.CARDS, true, HUMANS, BOTS, true)
	await wait_frames(3)
	var rows: Array[LobbySeatRow] = _rows(lobby)
	var left_last: Control = rows[0].focusable_controls().back()
	var right_first: Control = rows[1].focusable_controls().front()
	left_last.grab_focus()
	_pad_press(JOY_BUTTON_DPAD_RIGHT)
	await wait_frames(1)
	assert_eq(lobby.get_viewport().gui_get_focus_owner(), right_first, "D-pad right leaves the left card for the right card")


# --- Team groups ---------------------------------------------------------------------------

func test_team_groups_order_the_rows_under_their_headers() -> void:
	var lobby: Lobby = await _host_lobby(LobbySeatVariants.Style.GROUPED, true, HUMANS, BOTS, true)
	var panel: LobbyPlayersPanel = _panel(lobby)
	var headers: Array[LobbySeatGroupHeader] = []
	for extra: Node in panel._extras:
		headers.append(extra as LobbySeatGroupHeader)
	assert_gt(headers.size(), 0, "team headers exist")
	var last_pick: int = 0
	for row: LobbySeatRow in _rows(lobby):
		var group: int = panel._group_of(row)
		assert_gte(group, last_pick, "rows run in group order (%s)" % row.display_name)
		last_pick = group
	# FFA: one group.
	var ffa: Lobby = await _host_lobby(LobbySeatVariants.Style.GROUPED, true, HUMANS, BOTS, false)
	var ffa_headers: Array[Node] = _panel(ffa)._extras
	assert_eq(ffa_headers.size(), 1, "free-for-all is one group")
	assert_eq((ffa_headers[0] as LobbySeatGroupHeader).label.text, "FREE FOR ALL")


# --- The debug-only switch -------------------------------------------------------------------

func test_the_switch_exists_only_with_debug_mode_and_defaults_to_classic() -> void:
	DebugMode.set_override_for_test(false)
	LobbySeatVariants.chosen = LobbySeatVariants.Style.CARDS
	var plain: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(plain)
	assert_null(_panel(plain).style_selector(), "no switch with debug mode off")
	assert_eq(LobbySeatVariants.current(), LobbySeatVariants.Style.CLASSIC, "debug off always shows the shipped row")
	_panel(plain).set_row_style(LobbySeatVariants.Style.SLOT)
	assert_eq(LobbySeatVariants.chosen, LobbySeatVariants.Style.CARDS, "set_row_style is ignored with debug mode off")
	DebugMode.set_override_for_test(true)
	LobbySeatVariants.chosen = LobbySeatVariants.Style.CLASSIC
	var debug: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(debug)
	var selector: UiDropdown = _panel(debug).style_selector()
	assert_not_null(selector, "the switch exists with debug mode on")
	assert_eq(selector.get_item_count(), STYLES.size())
	assert_eq(selector.selected, LobbySeatVariants.Style.CLASSIC, "defaults to the shipped row")
	assert_true(_panel(debug).focus_entries().has(selector), "the pad can reach the switch")


func test_switching_the_look_rebuilds_rows_without_losing_seat_state() -> void:
	var lobby: Lobby = await _host_lobby(LobbySeatVariants.Style.CLASSIC, true, HUMANS, BOTS, true)
	var panel: LobbyPlayersPanel = _panel(lobby)
	var bot_key: int = _bot_rows(lobby)[1].seat_key
	panel._on_difficulty_chosen(bot_key, MatchConfig.AiDifficulty.HARD)
	panel._on_team_chosen(LobbySeats.human_key(1), 2)
	var table: Dictionary = panel.seats_data()
	var count: int = _rows(lobby).size()
	var selector: UiDropdown = panel.style_selector()
	for style: int in STYLES:
		selector.pick(style)
		await wait_frames(1)
		assert_eq(LobbySeatVariants.chosen, style)
		assert_eq(panel.seats_data(), table, "%s: the seat table is untouched" % _style_label(style))
		var rows: Array[LobbySeatRow] = _rows(lobby)
		assert_eq(rows.size(), count, "%s: same seats" % _style_label(style))
		for row: LobbySeatRow in rows:
			assert_eq(row.variant, style, "%s: rebuilt in the new look" % _style_label(style))
		assert_eq(_row_of(lobby, bot_key).difficulty, MatchConfig.AiDifficulty.HARD, "%s: the bot is still Hard" % _style_label(style))
		assert_eq(_row_of(lobby, LobbySeats.human_key(1)).team_pick, 2, "%s: the host is still on team 2" % _style_label(style))
