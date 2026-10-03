extends GutTest
## Bontago-1pi.53 package E1 (docs/LOBBY_REWORK_PLAN.md "Right panel" + the E1 row):
## the roster extracted from ui/Lobby.gd into ui/lobby/LobbyPlayersPanel behaves
## exactly as it did inside the Lobby, and the narrow Lobby <-> panel hooks the seat
## package (PL1) builds on are installed and no-op safe: seats_data() merged into a
## host publish, apply(config, roster, seats) from _apply_data, on_roster_changed,
## finalize_start_config() after the peer clamp, start_blocker() in Start and the
## button gate, the four request signals, focus entries.


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


## A row's pieces, in the order the panel builds them: layout child 0 is the colour
## box, child 1 the name/subtitle column, child 2 the Ready badge.
func _row_layout(row: Node) -> HBoxContainer:
	return row.get_child(0) as HBoxContainer


func _row_name(row: Node) -> String:
	return ((_row_layout(row).get_child(1) as VBoxContainer).get_child(0) as Label).text


func _row_subtitle(row: Node) -> String:
	return ((_row_layout(row).get_child(1) as VBoxContainer).get_child(1) as Label).text


func _row_badge(row: Node) -> String:
	return ((_row_layout(row).get_child(2) as PanelContainer).get_child(0) as Label).text


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
	assert_eq(_row_subtitle(rows[1]), "AI · Hard")
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
		var icon: PanelContainer = _row_layout(rows[slot]).get_child(0) as PanelContainer
		var box: StyleBoxFlat = icon.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(box.bg_color, palette[slot], "slot %d shows its palette colour" % slot)
		assert_eq(icon.custom_minimum_size, tuning.color_box_size_px)
		assert_eq(box.corner_radius_top_left, tuning.color_box_corner_radius_px)


func test_the_header_and_row_styling_is_the_lobbys_menu_look() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_eq(_header_of(lobby).get_theme_color("font_color"), lobby.tuning.ink_color, "header ink colour is applied by the Lobby's visual style")
	var row: PanelContainer = _panel_of(lobby)._player_rows[0] as PanelContainer
	var pill: StyleBoxFlat = row.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(pill.bg_color, lobby.tuning.pill_white_color, "rows stay the raised white pill")
	var badge: PanelContainer = _row_layout(row).get_child(2) as PanelContainer
	assert_eq((badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, lobby.tuning.pill_mint_color, "ready = mint")
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var guest_badge: PanelContainer = _row_layout(_panel_of(lobby)._player_rows[1]).get_child(2) as PanelContainer
	assert_eq((guest_badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, lobby.tuning.ground_band_apricot_color, "not ready = apricot")


func test_a_slot_past_the_palette_reads_gray() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [{"peer_id": 5, "slot_id": 99, "name": "Far", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	var icon: PanelContainer = _row_layout(_panel_of(lobby)._player_rows[0]).get_child(0) as PanelContainer
	assert_eq((icon.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, Color.GRAY)


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
	assert_true(panel.seats_data().is_empty())
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 5
	var before: Dictionary = config.to_dict()
	panel.finalize_start_config(config)
	assert_eq(config.to_dict(), before, "finalize_start_config is a no-op until the seat package fills it")
	lobby._on_setting_changed()
	assert_false(_last_published(lobby).has("seats"), "a lobby with no seat table publishes the dict it always did")


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
	var seats: Dictionary = {
		"humans": [{"peer_id": 1, "color": 3, "team": 2}],
		"bots": [{"color": 5, "team": 0, "difficulty": 2}],
	}
	var data: Dictionary = MatchConfig.new().to_dict()
	data["seats"] = seats
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_panel_of(lobby).seats_data(), seats, "apply() stores the dict's seat table")
	# Any later host publish carries it, so a settings edit never drops it.
	lobby._on_setting_changed()
	assert_eq(_last_published(lobby).get("seats"), seats)


func test_a_seats_value_that_is_not_a_dictionary_is_ignored() -> void:
	var lobby: Lobby = _make_lobby(true)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["seats"] = [1, 2, 3]
	Events.net_lobby_data_changed.emit(data)
	assert_true(_panel_of(lobby).seats_data().is_empty())
	lobby._on_setting_changed()
	assert_false(_last_published(lobby).has("seats"))


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
