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
	# Bontago-fca.41: synthetic events parsed into the global Input singleton stay latched
	# (stick axis, ui_* actions) for every later script in the same process; clear them.
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


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


func _row_badge_tip(row: Node) -> String:
	var layout: HBoxContainer = _row_layout(row)
	return (layout.get_child(layout.get_child_count() - 1) as PanelContainer).tooltip_text


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


func test_lobby_layout_tuning_resource_agrees_with_script_defaults_and_is_sane() -> void:
	var tuning: LobbyLayoutTuning = load("res://config/lobby_layout_tuning.tres") as LobbyLayoutTuning
	assert_not_null(tuning)
	var fresh: LobbyLayoutTuning = LobbyLayoutTuning.new()
	var checked: int = 0
	for prop: Dictionary in tuning.get_property_list():
		if (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var prop_name: String = str(prop.get("name", ""))
		checked += 1
		assert_eq(tuning.get(prop_name), fresh.get(prop_name), ".tres and .gd defaults agree for %s" % prop_name)
		var value: Variant = tuning.get(prop_name)
		if value is int or value is float:
			assert_gte(float(value), 0.0, "%s is never negative" % prop_name)
	assert_gt(checked, 0, "fixture: the layout tuning exposes script variables")
	assert_gt(tuning.section_spacing_px, 0)
	assert_gt(tuning.advanced_indent_px, 0)
	var box_min: float = minf(tuning.color_box_size_px.x, tuning.color_box_size_px.y)
	assert_gt(box_min, 0.0, "the colour cube is visible")
	assert_lte(float(tuning.color_box_corner_radius_px), box_min * 0.5, "corner radius fits inside the cube")


# --- Rows: behaviour moved 1:1 out of the Lobby ----------------------------------

func test_human_rows_name_subtitle_and_ready_badge() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	assert_eq(rows.size(), 2)
	assert_eq(_row_name(rows[0]), "Host")
	assert_eq(_row_subtitle(rows[0]), "Host · you", "the local peer is peer 1 on a FakeNet")
	_assert_host_crown(rows[0])
	assert_eq(_header_of(lobby).text, "2 players · 2/%d seats" % MatchConfig.PLAYER_COUNT_MAX)
	assert_eq(_row_name(rows[1]), "Guest")
	assert_eq(_row_subtitle(rows[1]), "LAN · 0 ms")
	assert_eq(_row_badge(rows[1]), char(0x231A))
	assert_eq(_row_badge_tip(rows[1]), "Not ready")


func _assert_host_crown(row: Node) -> void:
	var layout: HBoxContainer = _row_layout(row)
	var badge: PanelContainer = layout.get_child(layout.get_child_count() - 1) as PanelContainer
	var crown: TextureRect = badge.get_child(0) as TextureRect
	assert_not_null(crown, "the host row shows a crown, not the Ready pill")
	assert_eq(crown.texture, UiArtTable.shared().lobby_icon(UiArtTable.KEY_HOST_CROWN))
	assert_eq(badge.tooltip_text, "Host")


func test_host_crown_shows_for_a_client_too_and_guest_keeps_its_pill() -> void:
	var lobby: Lobby = _make_lobby(false)
	_fake_of(lobby).local_peer_id_value = 2
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var rows: Array[Node] = _panel_of(lobby)._player_rows
	_assert_host_crown(rows[0])
	assert_eq(_row_badge(rows[1]), char(0x231A), "a guest still has the Ready pill")
	assert_eq(_row_badge_tip(rows[1]), "Not ready")


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
	var bot_names: PackedStringArray = _panel_of(lobby)._config.bot_names
	assert_eq(bot_names.size(), 2, "the host named both bots when they were added")
	assert_eq(_row_name(rows[1]), bot_names[0])
	assert_eq(_row_subtitle(rows[1]), "AI", "the difficulty is the dropdown beside the name now")
	assert_eq(_rows_of(lobby)[1].difficulty_option.selected, MatchConfig.AiDifficulty.HARD, "the old default dropdown sets every bot")
	assert_eq(_row_name(rows[2]), bot_names[1])
	assert_eq(_row_badge(rows[2]), char(0x2713), "bots are always ready")


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
		assert_eq(_box_color(icon), palette[slot], "seat %d shows its palette colour (new seats take the lowest free)" % slot)
		assert_eq(icon.custom_minimum_size, tuning.color_box_size_px)
		assert_true(icon.get_node("SlotDiamond") is SlotDiamond, "the seat colour is the shared diamond")


func test_the_header_and_row_styling_is_the_lobbys_menu_look() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_eq(_header_of(lobby).get_theme_color("font_color"), lobby.tuning.ink_color, "header ink colour is applied by the Lobby's visual style")
	var row: PanelContainer = _panel_of(lobby)._player_rows[0] as PanelContainer
	var pill: StyleBoxFlat = row.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(pill.bg_color, lobby.tuning.pill_white_color, "rows stay the raised white pill")
	var badge: PanelContainer = (row as LobbySeatRow).badge
	assert_eq((badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, lobby.layout_tuning.host_crown_pill_color, "host crown = yellow (1pi.120)")
	var guest_ready_badge: PanelContainer = _rows_of(lobby)[1].badge
	assert_eq((guest_ready_badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, lobby.tuning.pill_mint_color, "ready = mint")
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
	assert_eq(_box_color(rows[0].color_button), Color.RED, "colour index 0 is inside the palette")
	assert_eq(_box_color(rows[1].color_button), Color.GRAY, "index 1 is past the one-colour palette")
	assert_eq(_box_color(rows[2].color_button), Color.GRAY, "a spectator holds no seat")
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
	assert_eq(label.text, "%s %s" % [char(0x25CF), Lobby.ALL_READY_TEXT], "everyone ready: the pill says so (1pi.122)")


## Bontago-1pi.122: the host's seat shows the crown and Start is its consent, so a host row whose
## "ready" flag is false still counts: host + one ready guest is "2 of 2", not "1 of 2".
func test_the_waiting_pill_counts_the_host_as_ready() -> void:
	var lobby: Lobby = _make_lobby(true)
	var roster: Array[Dictionary] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": false},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": true},
		{"peer_id": 3, "slot_id": 2, "name": "Third", "ready": false},
	]
	Events.net_roster_changed.emit(roster)
	var label: Label = lobby.get_node("%WaitingStatusLabel") as Label
	assert_eq(label.text, "%s Waiting for players %s 2 of 3 ready" % [char(0x25CF), char(0xB7)])
	roster.remove_at(2)
	Events.net_roster_changed.emit(roster)
	assert_eq(label.text, "%s %s" % [char(0x25CF), Lobby.ALL_READY_TEXT])


## Bontago-1pi.120: the host crown pill is yellow (LobbyLayoutTuning.host_crown_pill_color).
func test_the_host_crown_pill_is_yellow() -> void:
	var lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	var host_badge: PanelContainer = _rows_of(lobby)[0].badge
	var fill: Color = (host_badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	assert_eq(fill, lobby.layout_tuning.host_crown_pill_color)
	assert_gt(fill.r, fill.b + 0.4, "yellow: red and green high, blue low")
	assert_gt(fill.g, fill.b + 0.4)


func test_the_panel_reports_rendered_counts() -> void:
	var lobby: Lobby = _make_lobby(false)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	watch_signals(panel)
	Events.net_lobby_data_changed.emit(_two_humans_data(false))
	assert_signal_emitted_with_parameters(panel, "roster_rendered", [1, 2])


# --- Hooks are no-op safe by default ------------------------------------------------

func test_the_default_hooks_are_safe_on_an_empty_lobby() -> void:
	var lobby: Lobby = _make_lobby(true)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_eq(panel.start_blocker(), "", "nothing blocks an empty lobby")
	assert_eq(panel.focus_entries(), [panel.get_node("%TeamsToggle"), panel.get_node("%AddBotButton")] as Array[Control], "no rows yet: only the host's header controls")
	assert_eq(LobbySeats.seat_count(panel.seats_data()), 0, "no seats before anyone is in the lobby")
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 5
	assert_eq(panel.finalize_start_config(config), "", "no peers, no bots: nothing to refuse")
	assert_eq(config.player_count, MatchConfig.PLAYER_COUNT_MIN, "the seats decide the count, never below the 2-seat floor")
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
	assert_eq(_header_of(lobby).text, "1 player · 1 bot · 2/8 seats")
	panel.add_bot_requested.emit()
	assert_eq(int(_last_published(lobby).get("ai_count")), 2)
	assert_eq(int(_last_published(lobby).get("player_count")), 3)
	assert_eq(_header_of(lobby).text, "1 player · 2 bots · 3/8 seats")
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
	var last_setting: Control = _last_settings_stop(lobby)
	var back: Control = lobby.get_node("%BackButton") as Control
	assert_eq(last_setting.get_node(last_setting.focus_neighbor_bottom), seat_button)
	assert_eq(seat_button.get_node(seat_button.focus_neighbor_top), last_setting)
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
	var last_setting: Control = _last_settings_stop(lobby)
	assert_eq(last_setting.get_node(last_setting.focus_neighbor_bottom), lobby.get_node("%BackButton"), "no panel entries: the loop is the pre-rework one")
	_assert_main_loop_is_closed(lobby)


func test_the_default_main_loop_is_closed_and_skips_the_roster() -> void:
	var lobby: Lobby = _make_lobby(true)
	var last_setting: Control = _last_settings_stop(lobby)
	assert_eq(last_setting.get_node(last_setting.focus_neighbor_bottom), _panel_of(lobby).get_node("%TeamsToggle"), "the host's Teams toggle follows the settings, then Add bot, then the footer")
	assert_eq(_panel_of(lobby).get_node("%AddBotButton").get_node(_panel_of(lobby).get_node("%AddBotButton").focus_neighbor_bottom), lobby.get_node("%BackButton"), "rows carry no focusable control yet")
	_assert_main_loop_is_closed(lobby)


## The last settings stop before the players panel's entries (Bontago-1pi.53 S1b: the
## EXPERIMENTS Advanced chip, while its block is collapsed; Bontago-1pi.61: headers are not stops).
func _last_settings_stop(lobby: Lobby) -> Control:
	return (lobby.get_node("%ExperimentsSection") as LobbySection).advanced_button


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
	return (button.get_node("SlotDiamond") as SlotDiamond).color


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


func test_ui_left_and_ui_right_on_the_colour_box_never_change_the_colour() -> void:
	# Bontago-1pi.93: held / echoed sideways navigation used to spin the palette.
	var lobby: Lobby = _host_lobby(2)
	var box: Button = _rows_of(lobby)[0].color_button
	# Bontago-1pi.107: the lobby's initial focus is the disc-size slider, which steps on left/right;
	# the test is about the colour box, so it must hold focus.
	box.grab_focus()
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	var events: Array[InputEvent] = [_pad(JOY_BUTTON_DPAD_RIGHT), _pad(JOY_BUTTON_DPAD_LEFT)]
	for action: StringName in [&"ui_left", &"ui_right"]:
		var act: InputEventAction = InputEventAction.new()
		act.action = action
		act.pressed = true
		events.append(act)
	for sign: float in [-1.0, 1.0]:
		var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
		motion.axis = JOY_AXIS_LEFT_X
		motion.axis_value = sign
		events.append(motion)
	var echo: InputEventKey = InputEventKey.new()
	echo.keycode = KEY_RIGHT
	echo.physical_keycode = KEY_RIGHT
	echo.pressed = true
	echo.echo = true
	events.append(echo)
	for event: InputEvent in events:
		for _repeat: int in range(5):
			box.gui_input.emit(event.duplicate())
			Input.parse_input_event(event.duplicate())
			await get_tree().process_frame
	assert_eq(_human_color(lobby, 1), 0, "colour unchanged by navigation input")
	assert_eq(_human_color(lobby, 2), 1)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published, "nothing published")
	box.pressed.emit()
	assert_eq(_human_color(lobby, 1), 1, "one click / ui_accept advances exactly once")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published + 1)


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


func test_the_team_button_cycles_backwards_on_right_click_and_ignores_ui_left_right() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	_rows_of(lobby)[0].team_button.gui_input.emit(_right_click())
	assert_eq(_human_team(lobby, 1), MatchConfig.TEAM_PICK_RANDOM, "1 steps back to Random")
	_rows_of(lobby)[0].team_button.gui_input.emit(_right_click())
	assert_eq(_human_team(lobby, 1), 4, "Random steps back to the last team")
	_rows_of(lobby)[0].team_button.gui_input.emit(_pad(JOY_BUTTON_DPAD_LEFT))
	_rows_of(lobby)[0].team_button.gui_input.emit(_pad(JOY_BUTTON_DPAD_RIGHT))
	assert_eq(_human_team(lobby, 1), 4, "ui_left / ui_right only move focus (Bontago-1pi.94)")


func test_the_team_cycle_follows_a_legacy_two_team_lobby_and_teams_off_has_no_button() -> void:
	var lobby: Lobby = _host_lobby(2)
	for row: LobbySeatRow in _rows_of(lobby):
		assert_null(row.team_button, "no team button with teams off")
	assert_eq(_panel_of(lobby).focus_entries().size(), 4, "the two header controls and the two colour boxes: no team buttons")
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
	assert_eq(str((roster[1] as Dictionary)["name"]), "%s (Hard)" % _panel_of(lobby)._config.bot_names[0], "the published roster entry carries the bot's own difficulty")
	assert_eq(str((roster[2] as Dictionary)["name"]), "%s (Normal)" % _panel_of(lobby)._config.bot_names[1])


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
	_fake_of(lobby).local_peer_id_value = 99
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	Events.net_lobby_data_changed.emit(_two_humans_data(true))
	assert_true(panel.focus_entries().is_empty())
	_fake_of(lobby).is_host_value = true
	watch_signals(panel)
	lobby._update_host_only_state()
	assert_signal_emitted(panel, "focus_entries_changed")
	assert_eq(panel.focus_entries().size(), 4, "Teams toggle, Add bot and the two colour boxes")
	assert_false(_rows_of(lobby)[0].color_button.disabled)
	var drawn: Array[Node] = panel._player_rows.duplicate()
	lobby._update_host_only_state()
	assert_eq(panel._player_rows, drawn, "the per-frame push redraws nothing while the state is unchanged")


func test_the_host_focus_entries_run_colour_team_difficulty_remove_row_by_row() -> void:
	var lobby: Lobby = _host_lobby(1, 1, true)
	var rows: Array[LobbySeatRow] = _rows_of(lobby)
	var entries: Array[Control] = _panel_of(lobby).focus_entries()
	assert_eq(entries, [
		_panel_of(lobby).get_node("%TeamsToggle"), _panel_of(lobby).get_node("%AddBotButton"),
		rows[0].color_button, rows[0].team_button,
		rows[1].color_button, rows[1].team_button, rows[1].difficulty_option, rows[1].remove_button,
	] as Array[Control])
	var bot: LobbySeatRow = rows[1]
	assert_eq(bot.difficulty_option.get_node(bot.difficulty_option.focus_neighbor_right), bot.remove_button)
	assert_eq(bot.remove_button.get_node(bot.remove_button.focus_neighbor_left), bot.difficulty_option)
	assert_eq(bot.difficulty_option.get_node(bot.difficulty_option.focus_neighbor_left), bot.team_button)
	var back: Control = lobby.get_node("%BackButton") as Control
	assert_eq(entries[0].get_node(entries[0].focus_neighbor_top), _last_settings_stop(lobby), "the header controls and rows follow the settings in the loop")
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


# --- PL1b: Teams toggle, Add bot, client self-edit, Start ----------------------------------

## A FakeNet that, like the real Net, reports a running match.
class RunningMatchNet extends FakeNet:
	var in_progress: bool = false

	func match_in_progress() -> bool:
		return in_progress


func _teams_toggle(lobby: Lobby) -> CheckButton:
	return _panel_of(lobby).get_node("%TeamsToggle") as CheckButton


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


func _human_team_of_panel(lobby: Lobby, peer_id: int) -> int:
	return LobbySeats.team_of(_panel_of(lobby).seats_data(), LobbySeats.human_key(peer_id))


# --- Header controls ---

func test_the_seats_key_has_one_definition() -> void:
	assert_eq(Lobby.SEATS_KEY, "seats")


func test_the_host_header_has_a_live_teams_toggle_and_add_bot_button() -> void:
	var lobby: Lobby = _host_lobby(2)
	assert_true(_teams_toggle(lobby).visible)
	assert_false(_teams_toggle(lobby).disabled)
	assert_false(_teams_toggle(lobby).button_pressed, "teams start off")
	assert_eq(_teams_toggle(lobby).text, "Teams")
	assert_true(_add_bot_button(lobby).visible)
	assert_false(_add_bot_button(lobby).disabled)
	assert_eq(_add_bot_button(lobby).text, "+ Add bot")


func test_a_client_sees_the_teams_state_read_only_and_no_add_bot_button() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.TEAMS_4, {})
	assert_true(_teams_toggle(lobby).button_pressed, "the published state is shown")
	assert_true(_teams_toggle(lobby).disabled, "but a client cannot change it")
	assert_eq(_teams_toggle(lobby).focus_mode, Control.FOCUS_NONE)
	assert_false(_add_bot_button(lobby).visible)
	var option: OptionButton = lobby.get_node("%TeamModeOption") as OptionButton
	_teams_toggle(lobby).toggled.emit(false)
	assert_eq(option.selected, int(MatchConfig.TeamMode.TEAMS_4), "a forced toggle signal changes nothing for a client")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


func test_the_toggle_follows_the_published_team_mode_including_legacy_two_teams() -> void:
	var lobby: Lobby = _host_lobby(2)
	watch_signals(_panel_of(lobby))
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.TEAMS_2, {})
	assert_true(_teams_toggle(lobby).button_pressed, "a legacy TEAMS_2 lobby reads as teams on")
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.OFF, {})
	assert_false(_teams_toggle(lobby).button_pressed)
	assert_signal_not_emitted(_panel_of(lobby), "teams_toggled", "applying data never fires the toggle's own signal")


func test_pressing_the_teams_toggle_turns_teams_on_seeds_the_picks_and_publishes() -> void:
	var lobby: Lobby = _host_lobby(2, 2)
	# Hidden leftovers from an earlier teams session: switching on re-seeds 1, 2, 1, 2.
	_apply_seats(lobby, 2, 2, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 0, 4), _human_seat(2, 1, 3)],
		"bots": [_bot_seat(2, 2, 1), _bot_seat(3, 0, 1)],
	})
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	_teams_toggle(lobby).button_pressed = true
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published + 1, "one republish")
	assert_eq(int(_last_published(lobby).get("team_mode")), int(MatchConfig.TeamMode.TEAMS_4))
	var table: Dictionary = _seat_table(lobby)
	assert_eq(_human_team(lobby, 1), 1)
	assert_eq(_human_team(lobby, 2), 2)
	assert_eq(LobbySeats.team_of(table, LobbySeats.bot_key(0)), 1)
	assert_eq(LobbySeats.team_of(table, LobbySeats.bot_key(1)), 2)
	for row: LobbySeatRow in _rows_of(lobby):
		assert_not_null(row.team_button, "every seat shows its number")
	assert_true(_teams_toggle(lobby).button_pressed)


func test_switching_teams_off_keeps_the_picks_and_hides_the_buttons() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	_rows_of(lobby)[1].team_button.pressed.emit()
	var pick: int = _human_team(lobby, 2)
	_teams_toggle(lobby).button_pressed = false
	assert_eq(int(_last_published(lobby).get("team_mode")), int(MatchConfig.TeamMode.OFF))
	assert_eq(_human_team(lobby, 2), pick, "the picks stay in the table, hidden")
	for row: LobbySeatRow in _rows_of(lobby):
		assert_null(row.team_button)
	assert_false(_teams_toggle(lobby).button_pressed)


func test_the_add_bot_button_adds_a_default_bot_and_publishes_the_seats() -> void:
	var lobby: Lobby = _host_lobby(1)
	_add_bot_button(lobby).pressed.emit()
	assert_eq(int(_last_published(lobby).get("ai_count")), 1)
	assert_eq(int(_last_published(lobby).get("player_count")), 2)
	var table: Dictionary = _seat_table(lobby)
	assert_eq(LobbySeats.bot_count(table), 1)
	assert_eq(LobbySeats.difficulty_of(table, LobbySeats.bot_key(0)), MatchConfig.AiDifficulty.NORMAL, "the lobby's default difficulty")
	assert_eq(LobbySeats.color_of(table, LobbySeats.bot_key(0)), 1, "the lowest free colour")
	assert_eq(_rows_of(lobby).size(), 2)
	assert_eq(_header_of(lobby).text, "1 player · 1 bot · 2/8 seats")
	_add_bot_button(lobby).pressed.emit()
	assert_eq(LobbySeats.bot_count(_seat_table(lobby)), 2)


func test_add_bot_is_disabled_at_eight_seats_and_returns_when_a_bot_is_removed() -> void:
	var lobby: Lobby = _host_lobby(4, 4)
	assert_true(_add_bot_button(lobby).disabled, "4 humans + 4 bots fill the 8 seats")
	assert_eq(_add_bot_button(lobby).focus_mode, Control.FOCUS_NONE)
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	_add_bot_button(lobby).pressed.emit()
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published, "a refused press publishes nothing")
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 4)
	_rows_of(lobby)[4].remove_button.pressed.emit()
	assert_false(_add_bot_button(lobby).disabled, "a free seat again")
	assert_eq(_add_bot_button(lobby).focus_mode, Control.FOCUS_ALL)


func test_focus_leaves_add_bot_when_it_fills_the_last_seat() -> void:
	var lobby: Lobby = _host_lobby(4, 3)
	_add_bot_button(lobby).grab_focus()
	assert_true(_add_bot_button(lobby).has_focus())
	_add_bot_button(lobby).pressed.emit()
	assert_true(_add_bot_button(lobby).disabled)
	assert_false(_add_bot_button(lobby).has_focus())
	assert_true(_teams_toggle(lobby).has_focus(), "focus is not lost: the Teams toggle takes it")
	assert_false(_panel_of(lobby).focus_entries().has(_add_bot_button(lobby)), "a disabled button is no focus stop")
	_assert_main_loop_is_closed(lobby)


func test_the_header_controls_are_in_the_gamepad_loop_before_the_rows() -> void:
	var lobby: Lobby = _host_lobby(1, 1)
	var entries: Array[Control] = _panel_of(lobby).focus_entries()
	assert_eq(entries[0], _teams_toggle(lobby))
	assert_eq(entries[1], _add_bot_button(lobby))
	assert_eq(entries[2], _rows_of(lobby)[0].color_button)
	assert_eq(entries[0].get_node(entries[0].focus_neighbor_bottom), entries[1])
	assert_eq(entries[1].get_node(entries[1].focus_neighbor_bottom), entries[2])
	_assert_main_loop_is_closed(lobby)


func test_the_header_controls_use_the_chip_and_pill_look() -> void:
	var lobby: Lobby = _host_lobby(1)
	var tuning: MenuVisualTuning = lobby.tuning
	assert_eq((_teams_toggle(lobby).get_theme_stylebox("normal") as StyleBoxFlat).bg_color, tuning.pill_cream_color)
	assert_eq((_teams_toggle(lobby).get_theme_stylebox("pressed") as StyleBoxFlat).bg_color, tuning.pill_mint_color, "on = mint")
	assert_eq((_add_bot_button(lobby).get_theme_stylebox("normal") as StyleBoxFlat).bg_color, tuning.pill_powder_blue_color)


# --- Client self-edit ---

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
	# A client has no Start button, so walk the loop from its first visible stop.
	var chain: Array[Control] = lobby._visible_chain(lobby._main_chain)
	assert_true(chain.has(rows[1].color_button) and chain.has(rows[1].team_button))
	assert_false(chain.has(rows[0].color_button), "the host's row is no focus stop for a client")
	for index: int in range(chain.size()):
		var current: Control = chain[index]
		assert_eq(current.get_node(current.focus_neighbor_bottom), chain[(index + 1) % chain.size()], "%s leads on" % current.name)


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


func test_a_client_colour_request_wraps_around_the_palette() -> void:
	var last: int = LobbySeats.palette_size() - 1
	var lobby: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, last, 2)],
		"bots": [],
	})
	_rows_of(lobby)[1].color_button.pressed.emit()
	assert_eq(_fake_of(lobby).request_seat_pref_calls[0]["color_index"], 0)


func test_a_clients_team_click_asks_for_the_next_number_including_random() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 4)],
		"bots": [],
	})
	var net: FakeNet = _fake_of(lobby)
	_rows_of(lobby)[1].team_button.pressed.emit()
	assert_eq(net.request_seat_pref_calls[0], {"color_index": -1, "team_pick": MatchConfig.TEAM_PICK_RANDOM}, "4 -> Random")
	_rows_of(lobby)[1].team_button.gui_input.emit(_right_click())
	assert_eq(net.request_seat_pref_calls[1], {"color_index": -1, "team_pick": 3}, "right click: 4 -> 3")


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


func test_a_client_without_a_team_pill_sends_no_team_request() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)],
		"bots": [],
	})
	assert_null(_rows_of(lobby)[1].team_button, "teams off: no pill")
	_panel_of(lobby)._on_team_cycle_requested(LobbySeats.human_key(2), false)
	assert_true(_fake_of(lobby).request_seat_pref_calls.is_empty())


func test_the_hosts_own_row_is_edited_directly_not_through_the_net() -> void:
	var lobby: Lobby = _host_lobby(2)
	_rows_of(lobby)[0].color_button.pressed.emit()
	assert_true(_fake_of(lobby).request_seat_pref_calls.is_empty(), "the host owns the table: no intent needed")
	assert_eq(_human_color(lobby, 1), 1)


# --- Host applies a client's request ---

func test_the_host_applies_a_clients_seat_request_swaps_colours_and_republishes() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	Events.net_seat_pref_requested.emit(2, 0, 3)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published + 1, "one republish")
	assert_eq(_human_color(lobby, 2), 0, "the guest took colour 0")
	assert_eq(_human_color(lobby, 1), 1, "the host swapped into the guest's old colour")
	assert_eq(_human_team(lobby, 2), 3)
	assert_eq(_box_color(_rows_of(lobby)[1].color_button), lobby.default_config.player_colors[0], "the rows follow")


func test_the_host_refuses_requests_the_lobby_cannot_honour() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	var before: Dictionary = _panel_of(lobby).seats_data()
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	Events.net_seat_pref_requested.emit(7, 3, -1)
	Events.net_seat_pref_requested.emit(2, 99, -1)
	Events.net_seat_pref_requested.emit(2, -1, 9)
	Events.net_seat_pref_requested.emit(2, -1, -1)
	Events.net_seat_pref_requested.emit(0, 3, -1)
	assert_eq(_panel_of(lobby).seats_data(), before, "an unseated peer, bad ranges and a no-op change nothing")
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published)
	# The same request that is fine under 4 teams is refused under a legacy 2-team lobby.
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.TEAMS_2, before)
	Events.net_seat_pref_requested.emit(2, -1, 3)
	assert_ne(_human_team_of_panel(lobby, 2), 3, "team 3 is over the 2-team cap")
	Events.net_seat_pref_requested.emit(2, -1, 2)
	assert_eq(_human_team_of_panel(lobby, 2), 2)


func test_a_team_request_is_refused_while_teams_are_off() -> void:
	var lobby: Lobby = _host_lobby(2)
	var published: int = _fake_of(lobby).set_lobby_data_calls.size()
	Events.net_seat_pref_requested.emit(2, -1, 2)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published)
	Events.net_seat_pref_requested.emit(2, 4, 2)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), published, "all or nothing: the colour half is not applied either")
	assert_eq(_human_color(lobby, 2), 1)


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


func test_the_host_ignores_seat_requests_while_a_match_is_in_progress() -> void:
	var lobby: Lobby = _host_lobby(2)
	var net: RunningMatchNet = RunningMatchNet.new()
	net.slots_by_peer = {1: 0, 2: 1}
	lobby.net_provider = net
	lobby._update_host_only_state()
	net.in_progress = true
	var before: Dictionary = _panel_of(lobby).seats_data()
	Events.net_seat_pref_requested.emit(2, 5, -1)
	assert_eq(_panel_of(lobby).seats_data(), before)
	net.in_progress = false
	Events.net_seat_pref_requested.emit(2, 5, -1)
	assert_eq(LobbySeats.color_of(_panel_of(lobby).seats_data(), LobbySeats.human_key(2)), 5, "and works again in the lobby")


func test_a_clients_lobby_never_applies_a_seat_request() -> void:
	var lobby: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)],
		"bots": [],
	})
	var before: Dictionary = _panel_of(lobby).seats_data()
	Events.net_seat_pref_requested.emit(2, 6, 3)
	assert_eq(_panel_of(lobby).seats_data(), before)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


# --- Start: blocker ---

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
	assert_eq(start.tooltip_text, TeamAssigner.BLOCKER_ONE_TEAM)
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


func test_a_random_pick_is_not_a_blocker_and_teams_off_never_blocks() -> void:
	var lobby: Lobby = _host_lobby(2)
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 0)],
		"bots": [],
	})
	assert_eq(_panel_of(lobby).start_blocker(), "", "1 and Random: the Random seat can still join team 2")
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 1)],
		"bots": [],
	})
	assert_eq(_panel_of(lobby).start_blocker(), "", "teams off: the picks are hidden and irrelevant")


func test_the_blocker_follows_edits_and_a_client_never_sees_one() -> void:
	var lobby: Lobby = _host_lobby(2, 0, true)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_eq(panel.start_blocker(), "", "seeded 1, 2")
	_rows_of(lobby)[1].team_button.gui_input.emit(_right_click())
	assert_eq(_human_team(lobby, 2), 1, "right click: 2 -> 1, everyone is on team 1")
	assert_eq(panel.start_blocker(), TeamAssigner.BLOCKER_ONE_TEAM)
	_rows_of(lobby)[1].team_button.pressed.emit()
	assert_eq(panel.start_blocker(), "")
	var client: Lobby = _client_lobby(2, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 1)],
		"bots": [],
	})
	assert_eq(_panel_of(client).start_blocker(), "")
	assert_false(_blocker_label(client).visible)


func test_a_seat_that_clashes_with_the_bot_slots_blocks_start_with_its_reason() -> void:
	var lobby: Lobby = _host_lobby(2)
	_fake_of(lobby).slots_by_peer = {1: 0, 2: 5}
	lobby._update_host_only_state()
	assert_eq(_panel_of(lobby).start_blocker(), LobbySeats.BLOCKER_SLOT_CONFLICT)
	assert_null(_press_start(lobby))


func test_a_refusing_finalize_stops_the_start() -> void:
	var lobby: Lobby = _make_lobby(true, HookPanel)
	(_panel_of(lobby) as HookPanel).finalize_reason = "no way"
	assert_null(_press_start(lobby), "the reason cancels the start; no config goes out")


# --- Start: the match config ---

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


func test_start_with_teams_off_carries_colours_and_difficulties_but_no_teams() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 1, 1, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 7, 2)],
		"bots": [_bot_seat(0, 1, MatchConfig.AiDifficulty.HARD)],
	})
	var config: MatchConfig = _press_start(lobby)
	assert_eq(config.player_colors[0], lobby.default_config.player_colors[7])
	assert_eq(config.player_colors[1], lobby.default_config.player_colors[0])
	assert_eq(config.slot_ai_difficulties[1], MatchConfig.AiDifficulty.HARD)
	assert_true(config.slot_team_ids.is_empty())
	assert_true(config.team_numbers.is_empty())
	assert_false(config.teams_enabled())


func test_random_picks_are_resolved_at_start_and_re_rolled_each_start() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 4, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 0, 0), _human_seat(2, 1, 0), _human_seat(3, 2, 0), _human_seat(4, 3, 0)],
		"bots": [],
	})
	var seen_orders: Dictionary = {}
	for _attempt: int in range(8):
		var config: MatchConfig = _press_start(lobby)
		assert_true(config.teams_resolved(), "Random is gone by match start")
		assert_eq(config.team_numbers, PackedInt32Array([1, 2]), "all Random: balanced fill of teams 1..2")
		var sizes: Array[int] = [0, 0]
		for team_id: int in config.slot_team_ids:
			sizes[team_id] += 1
		assert_eq(sizes, [2, 2] as Array[int], "2 v 2")
		seen_orders[str(config.slot_team_ids)] = true
	assert_gt(seen_orders.size(), 1, "each Start shuffles afresh (no resolved teams are remembered)")


func test_a_fixed_match_seed_makes_the_random_split_repeatable() -> void:
	var lobby: Lobby = _make_lobby(true)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["rng_seed"] = 1234
	data["team_mode"] = MatchConfig.TeamMode.TEAMS_4
	data["player_count"] = 4
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "A", "ready": true}, {"peer_id": 2, "slot_id": 1, "name": "B", "ready": true},
		{"peer_id": 3, "slot_id": 2, "name": "C", "ready": true}, {"peer_id": 4, "slot_id": 3, "name": "D", "ready": true},
	]
	data["seats"] = {
		"humans": [_human_seat(1, 0, 0), _human_seat(2, 1, 0), _human_seat(3, 2, 0), _human_seat(4, 3, 0)],
		"bots": [],
	}
	_fake_of(lobby).slots_by_peer = {1: 0, 2: 1, 3: 2, 4: 3}
	Events.net_lobby_data_changed.emit(data)
	var first: MatchConfig = _press_start(lobby)
	var second: MatchConfig = _press_start(lobby)
	assert_eq(first.slot_team_ids, second.slot_team_ids, "the seed decides, the call count does not")


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


func test_the_lobbys_own_config_is_never_written_by_start() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.TEAMS_4, {
		"humans": [_human_seat(1, 3, 1), _human_seat(2, 4, 2)],
		"bots": [],
	})
	var shown: MatchConfig = lobby._last_config
	var before: Dictionary = shown.to_dict()
	_press_start(lobby)
	assert_eq(shown.to_dict(), before)


# --- Start: slots move (lobby leave / kick) ---

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


func test_start_seats_a_peer_that_joined_after_the_last_publish_and_drops_one_that_left() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.OFF, {
		"humans": [_human_seat(1, 2, 1), _human_seat(2, 3, 2)],
		"bots": [],
	})
	# Peer 2 left, peers 4 and 5 joined; no roster event reached the panel yet.
	_fake_of(lobby).slots_by_peer = {1: 0, 4: 1, 5: 2}
	var config: MatchConfig = _press_start(lobby)
	assert_not_null(config)
	assert_eq(config.player_count, 3, "the live peers decide the seats")
	var palette: PackedColorArray = lobby.default_config.player_colors
	assert_eq(config.player_colors[0], palette[2], "the host keeps its pick")
	assert_eq(config.player_colors[1], palette[0], "a newcomer takes the lowest free colour")
	assert_eq(config.player_colors[2], palette[1])


func test_a_spectator_holds_no_seat_at_start() -> void:
	var lobby: Lobby = _make_lobby(true)
	_apply_seats(lobby, 2, 0, MatchConfig.TeamMode.OFF, {"humans": [_human_seat(1, 0, 1), _human_seat(2, 1, 2)], "bots": []})
	_fake_of(lobby).slots_by_peer = {1: 0, 2: 1, 9: -1}
	var config: MatchConfig = _press_start(lobby)
	assert_not_null(config)
	assert_eq(config.player_count, 2)


# --- PL1b: the same flow over a real ENet session ----------------------------------------

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

	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
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


func test_the_header_controls_tell_the_loop_when_they_become_focus_stops() -> void:
	var lobby: Lobby = _make_lobby(false)
	var panel: LobbyPlayersPanel = _panel_of(lobby)
	assert_true(panel.focus_entries().is_empty(), "a client without a seat: no stops")
	watch_signals(panel)
	_fake_of(lobby).is_host_value = true
	lobby._update_host_only_state()
	assert_signal_emitted(panel, "focus_entries_changed", "no row was redrawn, the header alone changed")
	assert_eq(panel.focus_entries(), [_teams_toggle(lobby), _add_bot_button(lobby)] as Array[Control])
	_assert_main_loop_is_closed(lobby)


func test_a_junk_seat_table_off_the_wire_is_normalized_and_never_errors() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
	data["seats"] = {"humans": [1, "a", null, {"peer_id": 1, "color": 2.0, "team": "x"}], "bots": 7}
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_rows_of(lobby).size(), 1)
	var table: Dictionary = _panel_of(lobby).seats_data()
	assert_eq(LobbySeats.color_of(table, LobbySeats.human_key(1)), 2, "a JSON float colour is read as the int it carries")
	assert_eq(LobbySeats.bot_count(table), 0)
	# A seats table with no roster yet (a late joiner's first snapshot) is cleaned too.
	var late: Lobby = _make_lobby(false)
	var bare: Dictionary = MatchConfig.new().to_dict()
	bare["seats"] = {"humans": [5, {"peer_id": "x"}], "bots": [null]}
	Events.net_lobby_data_changed.emit(bare)
	assert_eq(LobbySeats.seat_count(_panel_of(late).seats_data()), 0)


## Bontago-1pi.95: no Select/Back hint row in the lobby; Start stays a normal button.
func test_lobby_has_no_select_back_hint_row_and_start_is_not_stretched() -> void:
	var lobby: Lobby = _host_lobby(2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(lobby.get_node_or_null("%GamepadHintBar"), "no hint bar")
	assert_null(lobby.get_node_or_null("%GamepadHintPill"), "no hint pill")
	var start: Button = lobby.get_node("%StartButton") as Button
	var bar: Control = start.get_parent() as Control
	assert_eq(bar.name, &"BottomBar")
	assert_eq(start.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "not stretched by the row")
	assert_lte(start.size.y, maxf(start.get_combined_minimum_size().y, start.custom_minimum_size.y) + 1.0)


## Bontago-1pi.95: eight seats scroll inside the panel and never move the layout.
func test_seven_bots_scroll_inside_the_players_panel_without_moving_the_layout() -> void:
	var lobby: Lobby = _host_lobby(1, 0, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var names: Array[String] = ["%SettingsCard", "%PlayersCard", "%StartButton"]
	var before: Array[Rect2] = []
	for node_name: String in names:
		before.append((lobby.get_node(node_name) as Control).get_global_rect())
	var root_before: Vector2 = lobby.size
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 8
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 7
	lobby._on_option_changed(0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_rows_of(lobby).size(), 8, "host + 7 bots")
	assert_eq(lobby.size, root_before)
	for index: int in range(names.size()):
		assert_eq((lobby.get_node(names[index]) as Control).get_global_rect(), before[index], "%s unchanged" % names[index])
	var scroll: ScrollContainer = _panel_of(lobby).get_node("%PlayerScroll") as ScrollContainer
	assert_true(scroll is FocusScrollContainer)
	assert_true(scroll.follow_focus, "gamepad focus scrolls to the focused seat")
	assert_eq(_list_of(lobby).get_parent(), scroll, "seats live in the ScrollContainer")


## Bontago-1pi.95: at 1280x720 and 1920x1080 (the same 1280x720 logical canvas, the one UI
## scale rule) every seat's name label is at least as wide as its text, so a short bot name is
## never clipped to a letter by the fixed-width controls beside it.
func test_seat_names_keep_their_text_width_with_seven_bots_at_common_resolutions() -> void:
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]
	for window: Vector2i in sizes:
		var viewport: SubViewport = UiScale.make_viewport(window)
		add_child_autofree(viewport)
		var lobby: Lobby = (load("res://ui/Lobby.tscn") as PackedScene).instantiate() as Lobby
		viewport.add_child(lobby)
		var fake: FakeNet = FakeNet.new()
		fake.is_host_value = true
		fake.is_offline_value = true
		lobby.net_provider = fake
		lobby._update_host_only_state()
		fake.slots_by_peer = {1: 0}
		var data: Dictionary = MatchConfig.new().to_dict()
		data["player_count"] = 8
		data["ai_count"] = 7
		data["bot_names"] = PackedStringArray(["Velocity", "Monolith", "Gantry", "Velocity", "Monolith", "Gantry", "Velocity"])
		data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
		Events.net_lobby_data_changed.emit(data)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var rows: Array[LobbySeatRow] = _rows_of(lobby)
		assert_eq(rows.size(), 8, "host + 7 bots at %s" % window)
		var scroll_width: float = (_list_of(lobby).get_parent() as Control).size.x
		for row: LobbySeatRow in rows:
			assert_lte(row.size.x, scroll_width + 0.5, "a seat row fits the card without a sideways scroll at %s" % window)
			var label: Label = row.name_label
			var font: Font = label.get_theme_font(&"font")
			var wanted: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size(&"font_size")).x
			assert_gte(label.size.x + 0.5, wanted, "'%s' unclipped at %s (width %s, text %s)" % [label.text, window, label.size.x, wanted])


## Bontago-1pi.95 (DECISION in ui/Lobby.gd): the host's Start is its consent -- enabled once every
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


## The real Net's own gate: a host alone (or with ready bots) is startable without flipping its toggle.
func test_real_net_host_gate_ignores_the_hosts_own_ready_flag() -> void:
	var err: Error = Net.host_game(0, "Host", false)
	assert_eq(err, OK)
	assert_false(bool(Net.peer_info(Net.local_peer_id()).get("ready", true)), "the host flag stays false")
	assert_true(Net.all_peers_ready(), "host consent is Start itself")
	Net.leave()
