extends GutTest
## Bontago-mp0.124 part A: map pictograms (lobby picker, thumbnail, loading screen) and the
## lobby rework icons (section headers, Teams / bot controls, difficulty, Advanced chips)
## resolve through config/ui_art_table.tres and the widgets display them.

const LOBBY_KEYS: Array[StringName] = [
	UiArtTable.KEY_SECTION_GAME, UiArtTable.KEY_SECTION_ROUND, UiArtTable.KEY_SECTION_GIFTS,
	UiArtTable.KEY_SECTION_EXPERIMENTS, UiArtTable.KEY_BOT_ADD, UiArtTable.KEY_BOT_REMOVE,
	UiArtTable.KEY_TEAMS, UiArtTable.KEY_TEAM_RANDOM, UiArtTable.KEY_COLOUR_SWAP,
	UiArtTable.KEY_ADVANCED_OPEN, UiArtTable.KEY_ADVANCED_CLOSED,
	&"difficulty_easy", &"difficulty_normal", &"difficulty_hard",
]


func _make_lobby(bots: int = 0) -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	fake.slots_by_peer[1] = 0
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 1 + bots
	(lobby.get_node("%AiCountSpin") as SpinBox).value = bots
	lobby._on_setting_changed()
	return lobby


func test_every_map_variant_has_a_pictogram() -> void:
	var table: UiArtTable = UiArtTable.shared()
	assert_not_null(table)
	var seen: Array[Rect2] = []
	for variant: int in MatchConfig.MapVariant.values():
		var tex: Texture2D = table.map_pictogram(variant)
		assert_not_null(tex, "map variant %d" % variant)
		seen.append((tex as AtlasTexture).region)
	for i: int in range(seen.size()):
		for j: int in range(i + 1, seen.size()):
			assert_ne(seen[i], seen[j], "distinct regions")
	assert_null(table.map_pictogram(99))


func test_every_lobby_icon_key_resolves() -> void:
	var table: UiArtTable = UiArtTable.shared()
	for key: StringName in LOBBY_KEYS:
		assert_not_null(table.lobby_icon(key), String(key))
	assert_null(table.lobby_icon(&"nope"))
	for difficulty: int in MatchConfig.AiDifficulty.values():
		assert_not_null(table.difficulty_icon(difficulty))


func test_lobby_map_picker_and_thumbnail_use_the_pictograms() -> void:
	var lobby: Lobby = _make_lobby()
	var combo: OptionButton = lobby.get_node("%MapComboOption") as OptionButton
	var size_count: int = Lobby.MAP_SIZE_LABELS.size()
	for index: int in range(combo.item_count):
		assert_eq(combo.get_item_icon(index), UiArtTable.shared().map_pictogram(index / size_count), "row %d" % index)
	var ring_index: int = MatchConfig.MapVariant.RING * size_count
	combo.select(ring_index)
	lobby._on_map_combo_selected(ring_index)
	assert_eq(lobby.map_thumbnail_texture(), UiArtTable.shared().map_pictogram(MatchConfig.MapVariant.RING))


func test_lobby_section_headers_and_chips_show_icons() -> void:
	var lobby: Lobby = _make_lobby()
	var expected: Dictionary = {
		"%GameSection": UiArtTable.KEY_SECTION_GAME, "%RoundSection": UiArtTable.KEY_SECTION_ROUND,
		"%GiftsSection": UiArtTable.KEY_SECTION_GIFTS, "%ExperimentsSection": UiArtTable.KEY_SECTION_EXPERIMENTS,
	}
	for path: String in expected:
		var section: LobbySection = lobby.get_node(path) as LobbySection
		assert_eq(section.header_icon(), UiArtTable.shared().lobby_icon(expected[path] as StringName), path)
		if section.advanced_button != null:
			assert_eq(section.advanced_button.icon, UiArtTable.shared().lobby_icon(UiArtTable.KEY_ADVANCED_CLOSED))
			section.set_advanced_open(true)
			assert_eq(section.advanced_button.icon, UiArtTable.shared().lobby_icon(UiArtTable.KEY_ADVANCED_OPEN))


func test_lobby_bot_and_team_controls_show_icons() -> void:
	var lobby: Lobby = _make_lobby(2)
	var panel: LobbyPlayersPanel = lobby.get_node("%PlayersPanel") as LobbyPlayersPanel
	var table: UiArtTable = UiArtTable.shared()
	assert_eq((panel.get_node("%AddBotButton") as Button).icon, table.lobby_icon(UiArtTable.KEY_BOT_ADD))
	assert_eq((panel.get_node("%TeamsToggle") as Button).icon, table.lobby_icon(UiArtTable.KEY_TEAMS))
	var bot_rows: int = 0
	for node: Node in panel._player_rows:
		var row: LobbySeatRow = node as LobbySeatRow
		if row.remove_button == null:
			continue
		bot_rows += 1
		assert_eq(row.remove_button.icon, table.lobby_icon(UiArtTable.KEY_BOT_REMOVE))
		for index: int in range(row.difficulty_option.item_count):
			assert_eq(row.difficulty_option.get_item_icon(index), table.difficulty_icon(index))
	assert_eq(bot_rows, 2)


func test_loading_screen_shows_the_map_pictogram() -> void:
	var screen: LoadingScreen = autofree((load("res://ui/LoadingScreen.tscn") as PackedScene).instantiate())
	add_child_autofree(screen)
	screen.tuning = LoadingScreenTuning.new()
	for variant: int in MatchConfig.MapVariant.values():
		var config: MatchConfig = MatchConfig.new()
		config.map_variant = variant
		screen.show_pending(config)
		assert_eq(screen.map_icon_texture(), UiArtTable.shared().map_pictogram(variant), "variant %d" % variant)
	screen.show_pending(null)
	assert_null(screen.map_icon_texture())
