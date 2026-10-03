extends GutTest
## Bontago-1pi.53 packages E1 + PL1a (docs/LOBBY_REWORK_PLAN.md "Right panel"):
## the roster extracted from ui/Lobby.gd into ui/lobby/LobbyPlayersPanel behaves
## exactly as it did inside the Lobby, the narrow Lobby <-> panel hooks are installed
## (seats_data() merged into a host publish, apply(config, roster, seats) from
## _apply_data, on_roster_changed, finalize_start_config() after the peer clamp,
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

	func start_blocker() -> String:
		return blocker

	func finalize_start_config(config: MatchConfig) -> void:
		finalized_player_counts.append(config.player_count)
		if seed_to_write >= 0:
			config.rng_seed = seed_to_write

	func focus_entries() -> Array[Control]:
		return entries


## HookPanel with one focusable control, built before the Lobby wires its loop.
class FocusPanel extends HookPanel:
	func _ready() -> void:
		var button: Button = Button.new()
		button.name = "SeatButton"
		add_child(button)
		entries.append(button)


func _make_lobby(is_host: bool, panel_script: Script = null) -> Lobby:
	var scene: PackedScene = load("res://ui/Lobby.tscn")
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


func _list_of(lobby: Lobby) -> VBoxContainer:
	return _panel_of(lobby).get_node("%PlayerList") as VBoxContainer


func _header_of(lobby: Lobby) -> Label:
	return _panel_of(lobby).get_node("%PlayerCountLabel") as Label


func _last_published(lobby: Lobby) -> Dictionary:
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	return calls[calls.size() - 1]


## A row's pieces: layout child 0 is the colour box, child 1 the name/subtitle column;
## the Ready badge is the layout's last child (team / difficulty / remove controls sit
## between them when a row has any).
func _row_layout(row: Node) -> HBoxContainer:
	return row.get_child(0) as HBoxContainer


func _row_name(row: Node) -> String:
	return ((_row_layout(row).get_child(1) as VBoxContainer).get_child(0) as Label).text


func _row_subtitle(row: Node) -> String:
	return ((_row_layout(row).get_child(1) as VBoxContainer).get_child(1) as Label).text


func _row_badge(row: Node) -> String:
	var layout: HBoxContainer = _row_layout(row)
	return ((layout.get_child(layout.get_child_count() - 1) as PanelContainer).get_child(0) as Label).text


func _rows_of(lobby: Lobby) -> Array[LobbySeatRow]:
	var rows: Array[LobbySeatRow] = []
	for node: Node in _panel_of(lobby)._player_rows:
		rows.append(node as LobbySeatRow)
	return rows


func _two_humans_data(ready_guest: bool) -> Dictionary:
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": ready_guest},
	]
	return data


# --- Scene structure and wiring ---------------------------------------------------

func test_the_panel_sits_in_the_players_card_between_the_card_top_and_the_footer() -> void:
	var lobby: Lobby = _make_lobby(true)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_not_null(panel, "%PlayersPanel resolves from the Lobby")
	var players: Node = panel.get_parent()
	assert_eq(players.get_parent(), lobby.get_node("%PlayersCard"), "the panel is the Players column's first child")
	assert_eq(panel.get_index(), 0)
	var footer: Node = (lobby.get_node("%ReadyCheck") as Node).get_parent()
	assert_eq(footer.get_parent(), players)
	assert_eq(footer.get_index(), panel.get_index() + 1, "the Ready/Invite footer stays directly under the panel")
	assert_eq(panel.get_child(0).name, &"TitleRow")
	assert_eq((panel.get_child(0).get_child(0) as Label).text, "Players")


func test_the_lobby_hands_the_panel_its_tunables_palette_and_net_seam() -> void:
	var lobby: Lobby = _make_lobby(true)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_eq(panel.tuning, lobby.tuning)
	assert_eq(panel.layout_tuning, lobby.layout_tuning)
	assert_eq(panel.palette, lobby.default_config.player_colors)
	assert_eq(panel.net_provider, lobby.net_provider, "a net_provider swapped after _ready() is forwarded to the panel")
	var other: FakeNet = FakeNet.new()
	lobby.net_provider = other
	assert_eq(panel.net_provider, other)


func test_lobby_layout_tuning_ships_todays_look_as_defaults() -> void:
	var tuning: LobbyLayoutTuning = load("res://config/lobby_layout_tuning.tres") as LobbyLayoutTuning
	assert_not_null(tuning)
	var fresh: LobbyLayoutTuning = LobbyLayoutTuning.new()
	assert_eq(tuning.color_box_size_px, Vector2(24.0, 24.0), "the 24 px clay-cube the rows always drew")
	assert_eq(tuning.color_box_corner_radius_px, 6)
	assert_eq(tuning.seat_row_separation_px, 10)
	assert_eq(tuning.seat_text_separation_px, 0)
	assert_eq(tuning.seat_name_font_size, 16)
	assert_eq(tuning.seat_row_min_height_px, 0, "0 = natural row height, no visual change in E1")
	assert_gt(tuning.section_spacing_px, 0)
	assert_gt(tuning.advanced_indent_px, 0)
	assert_eq(tuning.section_spacing_px, fresh.section_spacing_px, ".tres and .gd defaults agree")
	assert_eq(tuning.advanced_indent_px, fresh.advanced_indent_px)
	assert_eq(tuning.color_box_size_px, fresh.color_box_size_px)


# --- Rows: behaviour moved 1:1 out of the Lobby ----------------------------------

func test_human_rows_name_subtitle_and_ready_badge() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	assert_eq(rows.size(), 2)
	assert_eq(_row_name(rows[0]), "Host")
	assert_eq(_row_subtitle(rows[0]), "Host · you", "the local peer is peer 1 on a FakeNet")
	assert_eq(_row_badge(rows[0]), "%s Ready" % char(0x2713))
	assert_eq(_row_name(rows[1]), "Guest")
	assert_eq(_row_subtitle(rows[1]), "LAN · 0 ms")
	assert_eq(_row_badge(rows[1]), "%s Not ready" % char(0x231A))


func test_remote_subtitles_follow_the_transport_and_the_local_peer() -> void:
	var lobby: Lobby = _make_lobby(false)
	_fake_of(lobby).local_peer_id_value = 2
	_fake_of(lobby).is_steam_session_value = true
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	assert_eq(_row_subtitle(rows[0]), "Host", "the host row reads 'Host' for everyone else")
	assert_eq(_row_subtitle(rows[1]), "you")
	_fake_of(lobby).local_peer_id_value = 1
	var data: Dictionary = _two_humans_data(true)
	var roster: Array = data["roster"] as Array
	roster.append({"peer_id": 3, "slot_id": 2, "name": "Third", "ready": true, "ping_ms": 42.0})
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_row_subtitle(_panel_of(lobby)._player_rows[2]), "Steam · 42 ms")


func test_bot_rows_are_rebuilt_from_the_config_and_split_into_name_and_difficulty() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0}
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 4
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 2
	(lobby.get_node("%AiDifficultyOption") as OptionButton).select(MatchConfig.AiDifficulty.HARD)
	lobby._on_option_changed(MatchConfig.AiDifficulty.HARD)
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	assert_eq(rows.size(), 3, "one human + two bots")
	assert_eq(_row_name(rows[1]), "Bot 1")
	assert_eq(_row_subtitle(rows[1]), "AI", "the difficulty is the dropdown beside the name now")
	assert_eq(_rows_of(lobby)[1].difficulty_option.selected, MatchConfig.AiDifficulty.HARD, "the old default dropdown sets every bot")
	assert_eq(_row_name(rows[2]), "Bot 2")
	assert_eq(_row_badge(rows[2]), "%s Ready" % char(0x2713), "bots are always ready")


func test_a_live_roster_without_bot_rows_still_draws_the_configured_bots() -> void:
	# Bontago-1pi.9b: Net's own roster events never carry bot rows; the panel
	# re-derives them from the applied config on every path.
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1, 3: 2}
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 8
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 2
	var roster: Array[Dictionary] = []
	for peer_id: int in [1, 2, 3]:
		roster.append({"peer_id": peer_id, "slot_id": peer_id - 1, "name": "P%d" % peer_id, "ready": true})
	Events.net_roster_changed.emit(roster)
	assert_true(_header_of(lobby).text.begins_with("3 players · 2 bots · 5/"), _header_of(lobby).text)
	assert_eq(_panel_of(lobby)._player_rows.size(), 5)


func test_the_colour_box_uses_the_slot_colour_and_the_layout_tuning_size() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	var palette: PackedColorArray = lobby.default_config.player_colors
	var tuning: LobbyLayoutTuning = lobby.layout_tuning
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	for slot: int in range(2):
		var icon: Button = _row_layout(rows[slot]).get_child(0) as Button
		var box: StyleBoxFlat = icon.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(box.bg_color, palette[slot], "seat %d shows its palette colour (new seats take the lowest free)" % slot)
		assert_eq(icon.custom_minimum_size, tuning.color_box_size_px)
		assert_eq(box.corner_radius_top_left, tuning.color_box_corner_radius_px)


func test_the_header_and_row_styling_is_the_lobbys_menu_look() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_eq(_header_of(lobby).get_theme_color("font_color"), lobby.tuning.ink_color, "header ink colour is applied by the Lobby's visual style")
	var row: PanelContainer = _panel_of(lobby)._player_rows[0] as PanelContainer
	var pill: StyleBoxFlat = row.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(pill.bg_color, lobby.tuning.pill_white_color, "rows stay the raised white pill")
	var badge: PanelContainer = (row as LobbySeatRow).badge
	assert_eq((badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, lobby.tuning.pill_mint_color, "ready = mint")
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var guest_badge: PanelContainer = _rows_of(lobby)[1].badge
	assert_eq((guest_badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, lobby.tuning.ground_band_apricot_color, "not ready = apricot")


func test_a_colour_past_the_palette_and_a_seatless_row_read_gray() -> void:
	var lobby: Lobby = _make_lobby(false)
	_panel_of(lobby).palette = PackedColorArray([Color.RED])
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 5, "slot_id": 0, "name": "Near", "ready": true},
		{"peer_id": 6, "slot_id": 1, "name": "Far", "ready": true},
		{"peer_id": 7, "slot_id": -1, "name": "Watcher", "ready": true},
	]
	Events.net_lobby_data_changed.emit(data)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_eq((rows[0].color_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, Color.RED, "colour index 0 is inside the palette")
	assert_eq((rows[1].color_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, Color.GRAY, "index 1 is past the one-colour palette")
	assert_eq((rows[2].color_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, Color.GRAY, "a spectator holds no seat")
	assert_eq(rows[2].seat_key, LobbySeats.KEY_NONE)


func test_row_layout_values_come_from_the_layout_tuning() -> void:
	var lobby: Lobby = _make_lobby(false)
	var custom: LobbyLayoutTuning = LobbyLayoutTuning.new()
	custom.seat_row_min_height_px = 52
	custom.seat_row_separation_px = 14
	custom.seat_text_separation_px = 3
	custom.seat_name_font_size = 19
	custom.color_box_size_px = Vector2(30.0, 31.0)
	_panel_of(lobby).layout_tuning = custom
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	var row: PanelContainer = _panel_of(lobby)._player_rows[0] as PanelContainer
	assert_eq(row.custom_minimum_size.y, 52.0)
	var layout: HBoxContainer = _row_layout(row)
	assert_eq(layout.get_theme_constant("separation"), 14)
	var text_column: VBoxContainer = layout.get_child(1) as VBoxContainer
	assert_eq(text_column.get_theme_constant("separation"), 3)
	assert_eq((text_column.get_child(0) as Label).get_theme_font_size("font_size"), 19)
	assert_eq((layout.get_child(0) as Control).custom_minimum_size, Vector2(30.0, 31.0))


func test_default_rows_have_no_minimum_height() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_eq((_panel_of(lobby)._player_rows[0] as PanelContainer).custom_minimum_size, Vector2.ZERO)


func test_header_format_spells_out_humans_bots_and_seats() -> void:
	assert_eq(LobbyPlayersPanel.format_roster_header(1, 0, 4), "1 player · 1/4 seats")
	assert_eq(LobbyPlayersPanel.format_roster_header(3, 0, 8), "3 players · 3/8 seats")
	assert_eq(LobbyPlayersPanel.format_roster_header(1, 1, 2), "1 player · 1 bot · 2/2 seats")
	assert_eq(LobbyPlayersPanel.format_roster_header(3, 2, 8), "3 players · 2 bots · 5/8 seats")


func test_data_without_a_roster_key_leaves_the_rows_alone() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_eq(_panel_of(lobby)._player_rows.size(), 2)
	Events.net_lobby_data_changed.emit(MatchConfig.new().to_dict())
	assert_eq(_panel_of(lobby)._player_rows.size(), 2, "settings-only lobby data does not redraw or clear the rows")


func test_a_roster_that_is_not_an_array_draws_no_human_rows() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = "not a roster"
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_panel_of(lobby)._player_rows.size(), 0)


func test_the_waiting_pill_counts_ready_seats_of_the_rows_just_drawn() -> void:
	var lobby: Lobby = _make_lobby(true)
	var roster: Array[Dictionary] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": false},
	]
	Events.net_roster_changed.emit(roster)
	var label: Label = lobby.get_node("%WaitingStatusLabel") as Label
	assert_eq(label.text, "%s Waiting for players %s 1 of 2 ready" % [char(0x25CF), char(0xB7)])
	roster[1]["ready"] = true
	Events.net_roster_changed.emit(roster)
	assert_eq(label.text, "%s Waiting for players %s 2 of 2 ready" % [char(0x25CF), char(0xB7)])


func test_the_panel_reports_rendered_counts() -> void:
	var lobby: Lobby = _make_lobby(false)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	watch_signals(panel)
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	assert_signal_emitted_with_parameters(panel, "roster_rendered", [1, 2])


# --- Hooks are no-op safe by default ------------------------------------------------

func test_the_default_hooks_change_nothing() -> void:
	var lobby: Lobby = _make_lobby(true)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_eq(panel.start_blocker(), "", "nothing blocks Start in E1")
	assert_true(panel.focus_entries().is_empty())
	assert_eq(LobbySeats.seat_count(panel.seats_data()), 0, "no seats before anyone is in the lobby")
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 5
	var before: Dictionary = config.to_dict()
	panel.finalize_start_config(config)
	assert_eq(config.to_dict(), before, "finalize_start_config is a no-op until the seat package fills it")
	lobby._on_setting_changed()
	var published: Dictionary = _last_published(lobby)
	assert_true(published.has("seats"), "PL1a: the first host publish carries the (here empty) reconciled table")
	assert_eq(LobbySeats.seat_count(published["seats"] as Dictionary), 0)


func test_set_editable_follows_the_host_state_every_update() -> void:
	var host_lobby: Lobby = _make_lobby(true)
	assert_true(_panel_of(host_lobby).is_editable())
	var client_lobby: Lobby = _make_lobby(false)
	assert_false(_panel_of(client_lobby).is_editable())
	_fake_of(client_lobby).is_host_value = true
	client_lobby._update_host_only_state()
	assert_true(_panel_of(client_lobby).is_editable(), "pushed on every _update_host_only_state()")


# --- seats_data() / apply(config, roster, seats) -----------------------------------

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


func test_a_seats_value_that_is_not_a_dictionary_is_ignored() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0}
	var data: Dictionary = MatchConfig.new().to_dict()
	data["seats"] = [1, 2, 3]
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	var table: Dictionary = _panel_of(lobby).seats_data()
	assert_eq(LobbySeats.seat_count(table), 1, "garbage is dropped: the table is rebuilt from the roster")
	assert_eq(LobbySeats.color_of(table, LobbySeats.human_key(1)), 0)


func test_seats_data_returns_a_copy() -> void:
	var lobby: Lobby = _make_lobby(true)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["seats"] = {"humans": [], "bots": []}
	Events.net_lobby_data_changed.emit(data)
	var copy: Dictionary = _panel_of(lobby).seats_data()
	copy["humans"] = [{"peer_id": 9}]
	assert_true((_panel_of(lobby).seats_data()["humans"] as Array).is_empty(), "callers cannot edit the panel's table")


func test_seats_changed_republishes_with_the_table_for_a_host_only() -> void:
	var lobby: Lobby = _make_lobby(true)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["seats"] = {"humans": [{"peer_id": 1, "color": 1, "team": 1}], "bots": []}
	Events.net_lobby_data_changed.emit(data)
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 0, "an inbound apply never republishes")
	_panel_of(lobby).seats_changed.emit()
	assert_eq(calls.size(), 1)
	assert_true(_last_published(lobby).has("seats"))

	var client: Lobby = _make_lobby(false)
	_panel_of(client).seats_changed.emit()
	assert_eq(_fake_of(client).set_lobby_data_calls.size(), 0, "a client never publishes lobby data")


# --- Teams toggle, add/remove bot -------------------------------------------------

func test_teams_toggled_writes_off_or_four_teams_and_publishes() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: OptionButton = lobby.get_node("%TeamModeOption") as OptionButton
	_panel_of(lobby).teams_toggled.emit(true)
	assert_eq(option.selected, int(MatchConfig.TeamMode.TEAMS_4), "on = up to 4 teams (plan D8)")
	assert_eq(int(_last_published(lobby).get("team_mode")), int(MatchConfig.TeamMode.TEAMS_4))
	assert_true((lobby.get_node("%Team4Button") as Button).button_pressed, "the segmented front end follows")
	_panel_of(lobby).teams_toggled.emit(false)
	assert_eq(option.selected, int(MatchConfig.TeamMode.OFF))
	assert_eq(int(_last_published(lobby).get("team_mode")), int(MatchConfig.TeamMode.OFF))


func test_a_client_cannot_toggle_teams() -> void:
	var lobby: Lobby = _make_lobby(false)
	var option: OptionButton = lobby.get_node("%TeamModeOption") as OptionButton
	var before: int = option.selected
	_panel_of(lobby).teams_toggled.emit(true)
	assert_eq(option.selected, before)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


func test_add_bot_grows_the_seat_count_to_humans_plus_bots_and_publishes() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0}
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	panel.add_bot_requested.emit()
	assert_eq(int(_last_published(lobby).get("ai_count")), 1)
	assert_eq(int(_last_published(lobby).get("player_count")), 2, "1 human + 1 bot = 2 seats")
	assert_eq(_header_of(lobby).text, "1 player · 1 bot · 2/2 seats")
	panel.add_bot_requested.emit()
	assert_eq(int(_last_published(lobby).get("ai_count")), 2)
	assert_eq(int(_last_published(lobby).get("player_count")), 3)
	assert_eq(_header_of(lobby).text, "1 player · 2 bots · 3/3 seats")
	assert_eq(_panel_of(lobby)._player_rows.size(), 3)


func test_add_bot_stops_at_the_seat_cap() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).slots_by_peer = {1: 0, 2: 1, 3: 2, 4: 3}
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 8
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 4
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	_panel_of(lobby).add_bot_requested.emit()
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 4, "4 humans + 4 bots already fill the 8 seats")
	assert_eq(int((lobby.get_node("%PlayerCountSpin") as SpinBox).value), 8)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published, "a refused request publishes nothing")


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


func test_a_client_cannot_add_or_remove_bots() -> void:
	var lobby: Lobby = _make_lobby(false)
	var spin: SpinBox = lobby.get_node("%AiCountSpin") as SpinBox
	var before: int = int(spin.value)
	_panel_of(lobby).add_bot_requested.emit()
	_panel_of(lobby).remove_bot_requested.emit(0)
	assert_eq(int(spin.value), before)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


# --- Start hooks: blocker and finalize --------------------------------------------

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
	assert_eq(start.tooltip_text, panel.blocker, "the reason is shown")

	watch_signals(lobby)
	lobby._on_start_pressed()
	assert_signal_not_emitted(lobby, "start_requested", "a direct call (the X shortcut) honours the blocker too")
	assert_true(panel.finalized_player_counts.is_empty(), "a blocked Start never reaches finalize")

	var x_event: InputEventAction = InputEventAction.new()
	x_event.action = "lobby_quick_start"
	x_event.pressed = true
	lobby._unhandled_input(x_event)
	assert_signal_not_emitted(lobby, "start_requested")

	panel.blocker = ""
	lobby._update_host_only_state()
	assert_false(start.disabled)
	assert_eq(start.tooltip_text, "")
	lobby._on_start_pressed()
	assert_signal_emitted(lobby, "start_requested")


func test_a_client_never_shows_a_blocker() -> void:
	var lobby: Lobby = _make_lobby(false, HookPanel)
	(_panel_of(lobby) as HookPanel).blocker = "blocked"
	lobby._update_host_only_state()
	assert_eq((lobby.get_node("%StartButton") as Button).tooltip_text, "")


func test_finalize_runs_after_the_peer_clamp_on_the_config_that_is_emitted() -> void:
	# P1 review F1: sanitize drops team arrays whose length != player_count, and
	# clamp_to_connected_peers() changes player_count -- so finalize must see the
	# clamped config. match_defaults ships player_count 4; two peers clamp it to 2.
	var lobby: Lobby = _make_lobby(true, HookPanel)
	var panel: HookPanel = _panel_of(lobby) as HookPanel
	panel.seed_to_write = 4242
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	fake.slots_by_peer = {1: 0, 2: 1}
	watch_signals(lobby)
	lobby._on_start_pressed()
	assert_signal_emitted(lobby, "start_requested")
	assert_eq(panel.finalized_player_counts, [2], "finalize saw the clamped player_count, not the lobby's 4")
	var config: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	assert_eq(config.player_count, 2)
	assert_eq(config.rng_seed, 4242, "what finalize wrote is what Start emits")


func test_finalize_runs_once_per_start_on_a_copy_not_the_lobbys_last_config() -> void:
	var lobby: Lobby = _make_lobby(true, HookPanel)
	var panel: HookPanel = _panel_of(lobby) as HookPanel
	panel.seed_to_write = 77
	_fake_of(lobby).all_peers_ready_value = true
	var shown: MatchConfig = lobby._last_config
	lobby._on_start_pressed()
	lobby._on_start_pressed()
	assert_eq(panel.finalized_player_counts.size(), 2, "every Start resolves afresh (Random re-rolls)")
	assert_ne(shown.rng_seed, 77, "the config the lobby shows is never written by finalize")


# --- Focus entries ---------------------------------------------------------------------

func test_panel_focus_entries_join_the_main_loop_between_the_settings_and_the_footer() -> void:
	var lobby: Lobby = _make_lobby(true, FocusPanel)
	var panel: HookPanel = _panel_of(lobby) as HookPanel
	var seat_button: Control = panel.entries[0]
	var adv_bar: Control = lobby.get_node("%AdvRulesBar") as Control
	var back: Control = lobby.get_node("%BackButton") as Control
	assert_eq(adv_bar.get_node(adv_bar.focus_neighbor_bottom), seat_button)
	assert_eq(seat_button.get_node(seat_button.focus_neighbor_top), adv_bar)
	assert_eq(seat_button.get_node(seat_button.focus_neighbor_bottom), back)
	_assert_main_loop_is_closed(lobby)


func test_focus_entries_changed_rewires_the_loop() -> void:
	var lobby: Lobby = _make_lobby(true, FocusPanel)
	var panel: HookPanel = _panel_of(lobby) as HookPanel
	var extra: Button = Button.new()
	extra.name = "SeatButtonTwo"
	panel.add_child(extra)
	panel.entries.append(extra)
	panel.focus_entries_changed.emit()
	var first: Control = panel.entries[0]
	assert_eq(first.get_node(first.focus_neighbor_bottom), extra)
	assert_eq(extra.get_node(extra.focus_neighbor_bottom), lobby.get_node("%BackButton"))
	_assert_main_loop_is_closed(lobby)
	panel.entries.clear()
	panel.focus_entries_changed.emit()
	var adv_bar: Control = lobby.get_node("%AdvRulesBar") as Control
	assert_eq(adv_bar.get_node(adv_bar.focus_neighbor_bottom), lobby.get_node("%BackButton"), "no panel entries: the loop is the pre-rework one")
	_assert_main_loop_is_closed(lobby)


func test_the_default_main_loop_is_closed_and_skips_the_roster() -> void:
	var lobby: Lobby = _make_lobby(true)
	var adv_bar: Control = lobby.get_node("%AdvRulesBar") as Control
	assert_eq(adv_bar.get_node(adv_bar.focus_neighbor_bottom), lobby.get_node("%BackButton"), "rows carry no focusable control yet")
	_assert_main_loop_is_closed(lobby)


## Walks focus_neighbor_bottom from the first control of the main chain and checks it
## visits every wired control once and returns to the start.
func _assert_main_loop_is_closed(lobby: Lobby) -> void:
	var start: Control = lobby.get_node("%StartButton") as Control
	var current: Control = start
	var visited: Dictionary = {}
	var steps: int = 0
	while steps <= lobby._main_chain.size() + 1:
		current = current.get_node(current.focus_neighbor_bottom) as Control
		steps += 1
		if current == start:
			break
		assert_false(visited.has(current), "%s visited twice before the loop closed" % current.name)
		visited[current] = true
	assert_eq(current, start, "walking down from Start returns to Start")
	for control: Control in lobby._visible_chain(lobby._main_chain):
		assert_true(control == start or visited.has(control), "%s is part of the loop" % control.name)


# --- PL1a: seat rows (colour box, team button, bot difficulty, remove) -----------------

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


func _human_team(lobby: Lobby, peer_id: int) -> int:
	return LobbySeats.team_of(_seat_table(lobby), LobbySeats.human_key(peer_id))


func _box_color(button: Button) -> Color:
	return (button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


func _right_click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


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


func test_a_right_click_cycles_the_colour_backwards_and_a_left_press_in_gui_input_does_nothing() -> void:
	var lobby: Lobby = _host_lobby(2)
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	var left: InputEventMouseButton = InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	_rows_of(lobby)[0].color_button.gui_input.emit(left)
	var release: InputEventMouseButton = _right_click()
	release.pressed = false
	_rows_of(lobby)[0].color_button.gui_input.emit(release)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published, "only a right-button PRESS cycles")
	_rows_of(lobby)[0].color_button.gui_input.emit(_right_click())
	assert_eq(_human_color(lobby, 1), LobbySeats.palette_size() - 1, "0 wraps backwards to the last colour (nobody holds it)")
	assert_eq(_human_color(lobby, 2), 1, "no clash, no swap")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published + 1)


func test_ui_right_and_ui_left_on_the_colour_box_cycle_forwards_and_backwards() -> void:
	var lobby: Lobby = _host_lobby(2)
	_rows_of(lobby)[0].color_button.gui_input.emit(_pad(JOY_BUTTON_DPAD_RIGHT))
	assert_eq(_human_color(lobby, 1), 1, "ui_right = next colour")
	assert_eq(_human_color(lobby, 2), 0, "swapped")
	_rows_of(lobby)[0].color_button.gui_input.emit(_pad(JOY_BUTTON_DPAD_LEFT))
	assert_eq(_human_color(lobby, 1), 0, "ui_left = previous colour")
	assert_eq(_human_color(lobby, 2), 1)
	var other: InputEventJoypadButton = _pad(JOY_BUTTON_DPAD_UP)
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	_rows_of(lobby)[0].color_button.gui_input.emit(other)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published, "ui_up is focus navigation, not a cycle")


func test_a_pad_can_reach_and_activate_the_colour_box() -> void:
	# BaseButton turns ui_accept into `pressed` (the click path every test above drives
	# with pressed.emit()); what this row owes the pad is: focusable, enabled, and an
	# Input Map whose ui_accept has a gamepad button.
	var lobby: Lobby = _host_lobby(2)
	var box: Button = _rows_of(lobby)[0].color_button
	assert_eq(box.focus_mode, Control.FOCUS_ALL)
	assert_false(box.disabled)
	box.grab_focus()
	assert_true(box.has_focus(), "the colour box takes focus")
	assert_true(_panel_of(lobby).focus_entries().has(box), "and is in the Lobby's focus loop")
	var a_button: InputEventJoypadButton = _pad(JOY_BUTTON_A)
	assert_true(a_button.is_action_pressed(&"ui_accept"), "the pad's A button is ui_accept")
	assert_true(_pad(JOY_BUTTON_DPAD_LEFT).is_action_pressed(&"ui_left"))
	assert_true(_pad(JOY_BUTTON_DPAD_RIGHT).is_action_pressed(&"ui_right"))


func test_the_team_button_cycles_one_to_four_then_random_then_one() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	assert_eq(_human_team(lobby, 1), 1, "teams on seed 1, 2, 1, 2...")
	assert_eq(_human_team(lobby, 2), 2)
	var expected: Array[int] = [2, 3, 4, MatchConfig.TEAM_PICK_RANDOM, 1]
	for pick: int in expected:
		_rows_of(lobby)[0].team_button.pressed.emit()
		assert_eq(_human_team(lobby, 1), pick)
		assert_eq(_rows_of(lobby)[0].team_button.text, LobbySeatRow.team_text(pick))
	assert_eq(LobbySeatRow.team_text(MatchConfig.TEAM_PICK_RANDOM), "?", "Random shows as ?")
	assert_eq(_human_team(lobby, 2), 2, "other seats are untouched")


func test_the_team_button_cycles_backwards_on_right_click_and_ui_left() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	_rows_of(lobby)[0].team_button.gui_input.emit(_right_click())
	assert_eq(_human_team(lobby, 1), MatchConfig.TEAM_PICK_RANDOM, "1 steps back to Random")
	_rows_of(lobby)[0].team_button.gui_input.emit(_pad(JOY_BUTTON_DPAD_LEFT))
	assert_eq(_human_team(lobby, 1), 4, "Random steps back to the last team")
	_rows_of(lobby)[0].team_button.gui_input.emit(_pad(JOY_BUTTON_DPAD_RIGHT))
	assert_eq(_human_team(lobby, 1), MatchConfig.TEAM_PICK_RANDOM, "ui_right steps forward again")


func test_the_team_cycle_follows_a_legacy_two_team_lobby_and_teams_off_has_no_button() -> void:
	var lobby: Lobby = _host_lobby(2)
	for row: LobbySeatRow in _rows_of(lobby):
		assert_null(row.team_button, "no team button with teams off")
	assert_eq(_panel_of(lobby).focus_entries().size(), 2, "just the two colour boxes")
	(lobby.get_node("%TeamModeOption") as OptionButton).select(MatchConfig.TeamMode.TEAMS_2)
	lobby._on_option_changed(MatchConfig.TeamMode.TEAMS_2)
	var seen: Array[int] = []
	for _step: int in range(3):
		_rows_of(lobby)[0].team_button.pressed.emit()
		seen.append(_human_team(lobby, 1))
	assert_eq(seen, [2, MatchConfig.TEAM_PICK_RANDOM, 1], "cap 2: 1, 2, Random")


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
	assert_eq(_rows_of(lobby)[1].difficulty_option.selected, MatchConfig.AiDifficulty.HARD, "the row shows it")
	var roster: Array = _last_published(lobby)["roster"] as Array
	assert_eq(str((roster[1] as Dictionary)["name"]), "Bot 1 (Hard)", "the published roster entry carries the bot's own difficulty")
	assert_eq(str((roster[2] as Dictionary)["name"]), "Bot 2 (Normal)")


func test_changing_the_lobby_default_difficulty_sets_every_bot_but_other_edits_keep_each_bot() -> void:
	var lobby: Lobby = _host_lobby(1, 2)
	(lobby.get_node("%AiDifficultyOption") as OptionButton).select(MatchConfig.AiDifficulty.HARD)
	lobby._on_option_changed(MatchConfig.AiDifficulty.HARD)
	for ordinal: int in range(2):
		assert_eq(LobbySeats.difficulty_of(_seat_table(lobby), LobbySeats.bot_key(ordinal)), MatchConfig.AiDifficulty.HARD)
	_rows_of(lobby)[1].difficulty_option.item_selected.emit(MatchConfig.AiDifficulty.EASY)
	lobby._on_setting_changed()
	assert_eq(LobbySeats.difficulty_of(_seat_table(lobby), LobbySeats.bot_key(0)), MatchConfig.AiDifficulty.EASY, "an unrelated publish keeps the bot's own pick")
	assert_eq(LobbySeats.difficulty_of(_seat_table(lobby), LobbySeats.bot_key(1)), MatchConfig.AiDifficulty.HARD)


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
	assert_eq(_panel_of(lobby)._player_rows.size(), 2, "one human + one bot row left")
	assert_eq(_header_of(lobby).text, "1 player · 1 bot · 2/2 seats")


func test_a_clients_rows_are_read_only() -> void:
	var lobby: Lobby = _make_lobby(false)
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
	assert_eq(rows[2].difficulty_option.selected, MatchConfig.AiDifficulty.NORMAL, "a client still sees the bot's difficulty")
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


func test_the_host_gets_live_rows_when_editable_flips_and_the_loop_is_told() -> void:
	var lobby: Lobby = _make_lobby(false)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_true(panel.focus_entries().is_empty())
	_fake_of(lobby).is_host_value = true
	watch_signals(panel)
	lobby._update_host_only_state()
	assert_signal_emitted(panel, "focus_entries_changed")
	assert_eq(panel.focus_entries().size(), 2, "two colour boxes")
	assert_false(_rows_of(lobby)[0].color_button.disabled)
	var drawn: Array[Node] = panel._player_rows.duplicate()
	lobby._update_host_only_state()
	assert_eq(panel._player_rows, drawn, "the per-frame push redraws nothing while the state is unchanged")


func test_the_host_focus_entries_run_colour_team_difficulty_remove_row_by_row() -> void:
	var lobby: Lobby = _host_lobby(1, 1, true)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	var entries: Array[Control] = _panel_of(lobby).focus_entries()
	assert_eq(entries, [
		rows[0].color_button, rows[0].team_button,
		rows[1].color_button, rows[1].team_button, rows[1].difficulty_option, rows[1].remove_button,
	] as Array[Control])
	var bot: LobbySeatRow = rows[1]
	assert_eq(bot.difficulty_option.get_node(bot.difficulty_option.focus_neighbor_right), bot.remove_button)
	assert_eq(bot.remove_button.get_node(bot.remove_button.focus_neighbor_left), bot.difficulty_option)
	assert_eq(bot.difficulty_option.get_node(bot.difficulty_option.focus_neighbor_left), bot.team_button)
	var back: Control = lobby.get_node("%BackButton") as Control
	assert_eq(entries[0].get_node(entries[0].focus_neighbor_top), lobby.get_node("%AdvRulesBar"), "the rows follow the settings in the loop")
	assert_eq(entries[entries.size() - 1].get_node(entries[entries.size() - 1].focus_neighbor_bottom), back, "and precede the footer")
	_assert_main_loop_is_closed(lobby)


func test_focus_stays_on_the_same_control_after_an_edit_redraws_the_rows() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	var old_team: Button = _rows_of(lobby)[1].team_button
	old_team.grab_focus()
	assert_true(old_team.has_focus())
	old_team.pressed.emit()
	var new_team: Button = _rows_of(lobby)[1].team_button
	assert_ne(new_team, old_team, "the rows were redrawn")
	assert_true(new_team.has_focus(), "focus follows the same seat and control")
	assert_eq(new_team.text, "3", "and the pick moved on")


func test_focus_moves_to_the_next_bot_when_the_focused_bot_is_removed() -> void:
	var lobby: Lobby = _host_lobby(1, 2)
	_rows_of(lobby)[1].remove_button.grab_focus()
	_rows_of(lobby)[1].remove_button.pressed.emit()
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_eq(rows.size(), 2)
	assert_true(rows[1].remove_button.has_focus(), "the remaining bot's remove button takes the focus")
	rows[1].remove_button.pressed.emit()
	assert_eq(_rows_of(lobby).size(), 1)
	assert_true(_rows_of(lobby)[0].color_button.has_focus(), "no bot left: the nearest row's colour box")


func test_a_roster_join_and_leave_reconcile_the_table_colours() -> void:
	var lobby: Lobby = _host_lobby(2)
	var fake: FakeNet = _fake_of(lobby)
	var roster: Array[Dictionary] = []
	for peer_id: int in [1, 2, 3]:
		roster.append({"peer_id": peer_id, "slot_id": peer_id - 1, "name": "P%d" % peer_id, "ready": true})
	fake.slots_by_peer[3] = 2
	Events.net_roster_changed.emit(roster)
	assert_eq(LobbySeats.color_of(_panel_of(lobby).seats_data(), LobbySeats.human_key(3)), 2, "a joiner takes the lowest free colour")
	roster.remove_at(1)
	fake.slots_by_peer.erase(2)
	Events.net_roster_changed.emit(roster)
	var seats: Dictionary = _panel_of(lobby).seats_data()
	assert_false(LobbySeats.has_seat(seats, LobbySeats.human_key(2)), "a leaver's seat is gone")
	assert_eq(LobbySeats.color_of(seats, LobbySeats.human_key(3)), 2, "the others keep their picks")
	fake.slots_by_peer[4] = 3
	roster.append({"peer_id": 4, "slot_id": 3, "name": "P4", "ready": true})
	Events.net_roster_changed.emit(roster)
	assert_eq(LobbySeats.color_of(_panel_of(lobby).seats_data(), LobbySeats.human_key(4)), 1, "the leaver's colour is free again")


func test_a_spectator_row_has_no_seat_controls() -> void:
	var lobby: Lobby = _make_lobby(true)
	var roster: Array[Dictionary] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 9, "slot_id": -1, "name": "Watcher", "ready": true},
	]
	_fake_of(lobby).slots_by_peer = {1: 0}
	Events.net_roster_changed.emit(roster)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	assert_eq(rows.size(), 2)
	assert_eq(rows[1].seat_key, LobbySeats.KEY_NONE)
	assert_true(rows[1].focusable_controls().is_empty())
	assert_true(rows[1].color_button.disabled)
	assert_eq(LobbySeats.seat_count(_panel_of(lobby).seats_data()), 1, "only the seated human has a seat")


func test_rows_are_ordered_by_slot_not_by_roster_order() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 7, "slot_id": 1, "name": "Second", "ready": true},
		{"peer_id": 1, "slot_id": 0, "name": "First", "ready": true},
	]
	Events.net_lobby_data_changed.emit(data)
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	assert_eq(_row_name(rows[0]), "First")
	assert_eq(_row_name(rows[1]), "Second")


func test_seat_row_sizes_come_from_the_layout_tuning() -> void:
	var lobby: Lobby = _host_lobby(1, 1, true)
	var custom: LobbyLayoutTuning = LobbyLayoutTuning.new()
	custom.seat_team_button_min_size_px = Vector2(40.0, 33.0)
	custom.seat_difficulty_min_width_px = 111
	custom.seat_remove_button_min_size_px = Vector2(26.0, 27.0)
	custom.seat_color_focus_border_px = 5
	_panel_of(lobby).layout_tuning = custom
	_panel_of(lobby).set_editable(false)
	_panel_of(lobby).set_editable(true)
	var bot: LobbySeatRow = _rows_of(lobby)[1]
	assert_eq(bot.team_button.custom_minimum_size, Vector2(40.0, 33.0))
	assert_eq(bot.difficulty_option.custom_minimum_size.x, 111.0)
	assert_eq(bot.remove_button.custom_minimum_size, Vector2(26.0, 27.0))
	assert_eq((bot.color_button.get_theme_stylebox("focus") as StyleBoxFlat).border_width_left, 5)
	var fresh: LobbyLayoutTuning = LobbyLayoutTuning.new()
	var shipped: LobbyLayoutTuning = load("res://config/lobby_layout_tuning.tres") as LobbyLayoutTuning
	assert_eq(shipped.seat_team_button_min_size_px, fresh.seat_team_button_min_size_px, ".tres and .gd defaults agree")
	assert_eq(shipped.seat_difficulty_min_width_px, fresh.seat_difficulty_min_width_px)
	assert_eq(shipped.seat_remove_button_min_size_px, fresh.seat_remove_button_min_size_px)
	assert_eq(shipped.seat_color_focus_border_px, fresh.seat_color_focus_border_px)
