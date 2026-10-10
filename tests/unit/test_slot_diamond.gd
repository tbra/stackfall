extends GutTest
## Bontago-1pi.81 / 1pi.83: the colour diamond is ONE shared component used by the HUD
## share rows, the lobby seat rows and the round score table; plus the lobby's bot names,
## session badge, Advanced disclosure and one-row prompt.

const DIAMOND_SCENE: String = "res://ui/SlotDiamond.tscn"


func _make_lobby(is_host: bool = true) -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_diamond_draws_the_colour_it_is_given_at_the_tuned_size() -> void:
	var diamond: SlotDiamond = SlotDiamond.create(Color.RED)
	add_child_autofree(diamond)
	assert_eq(diamond.scene_file_path, DIAMOND_SCENE)
	assert_eq(diamond.color, Color.RED)
	diamond.set_color(Color.BLUE)
	assert_eq(diamond.color, Color.BLUE)
	assert_eq(diamond.custom_minimum_size, Vector2.ONE * diamond.tuning.hud_row_glyph_size_px)
	assert_eq(SlotDiamond.points(Vector2.ZERO, 2.0)[1], Vector2(2.0, 0.0))


func test_hud_share_rows_instance_the_shared_diamond() -> void:
	var hud: HUD = autofree((load("res://ui/HUD.tscn") as PackedScene).instantiate())
	add_child_autofree(hud)
	hud._ensure_share_row_count(2)
	assert_eq(hud._share_glyphs.size(), 2)
	for glyph: Variant in hud._share_glyphs:
		assert_true(glyph is SlotDiamond)
		assert_eq((glyph as SlotDiamond).scene_file_path, DIAMOND_SCENE)


func test_lobby_seat_rows_instance_the_shared_diamond() -> void:
	var lobby: Lobby = _make_lobby()
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	var rows: Array[Node] = (lobby.get_node("%PlayersPanel") as LobbyPlayersPanel)._player_rows
	assert_gt(rows.size(), 0)
	for row: Node in rows:
		var diamond: SlotDiamond = (row as LobbySeatRow).color_button.get_node("SlotDiamond") as SlotDiamond
		assert_eq(diamond.scene_file_path, DIAMOND_SCENE)


func test_score_table_name_cells_instance_the_shared_diamond() -> void:
	var cell: Label = Label.new()
	add_child_autofree(cell)
	ScoreTable._mark_with_slot_colour(cell, Color.GREEN, MenuVisualTuning.new())
	var diamond: SlotDiamond = cell.get_node("SlotDiamond") as SlotDiamond
	assert_eq(diamond.scene_file_path, DIAMOND_SCENE)
	assert_eq(diamond.color, Color.GREEN)


func test_a_seeded_vs_bots_bot_gets_a_themed_name_not_bot_n() -> void:
	var lobby: Lobby = _make_lobby()
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 2
	config.ai_count = 1
	var data: Dictionary = config.to_dict()
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	lobby._republish_roster_if_host()
	var names: PackedStringArray = (lobby.get_node("%PlayersPanel") as LobbyPlayersPanel)._config.bot_names
	assert_eq(names.size(), 1)
	assert_false(names[0].begins_with("Bot "), names[0])
	assert_true(BotNames.all_names().has(names[0]))


func test_status_badge_names_the_session_kind() -> void:
	assert_eq(Lobby.status_badge_text(true, false, true), "Vs bots")
	assert_eq(Lobby.status_badge_text(true, false, false), "Hosting %s LAN" % char(0xB7))
	assert_eq(Lobby.status_badge_text(false, true, false), "Joined %s Steam" % char(0xB7))
	var lobby: Lobby = _make_lobby()
	(lobby.net_provider as FakeNet).is_private_session_value = true
	lobby._update_status_badge()
	assert_eq((lobby.get_node("%StatusBadgeLabel") as Label).text, "Vs bots")


func test_advanced_is_a_flat_text_disclosure_that_toggles() -> void:
	var section: LobbySection = (_make_lobby().get_node("%GameSection") as LobbySection)
	var toggle: Button = section.advanced_button
	assert_true(toggle.get_theme_stylebox(&"normal") is StyleBoxFlat, "Arcade (Bontago-hfa.5): a disc-700 bar, not a block button")
	assert_eq(toggle.text, "%s Advanced" % LobbySection.DISCLOSURE_CLOSED)
	toggle.button_pressed = true
	assert_true(section.is_advanced_open())
	assert_eq(toggle.text, "%s Advanced" % LobbySection.DISCLOSURE_OPEN)
	assert_eq(toggle.focus_mode, Control.FOCUS_ALL, "reachable by pad and keyboard")


