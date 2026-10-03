extends GutTest
## Lobby rework M1 (Bontago-1pi.53): the match-side consumers of the per-seat
## data MatchConfig now carries (slot_ai_difficulties, slot_team_ids,
## team_numbers):
##   * per-slot bot difficulty reaches every BotController (game/Main.gd);
##   * team-indexed colours (territory overlay, goal flags, minimap territory,
##     capture ring, winner tint, share bars) come from territory_colors() while
##     slot-indexed ones (home flags, minimap beacons) stay on player_colors;
##   * team labels (HUD, results screen, winner name) use team_number_for();
##   * the results quick-settings republish keeps the lobby "seats" table and
##     keeps the per-slot bot difficulties coherent (review F2).
## Every legacy case (no per-seat arrays) is asserted unchanged next to its
## resolved twin.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/HUD.tscn")
const RESULTS_SCENE: PackedScene = preload("res://ui/ResultsScreen.tscn")

## Slots 0..3: slot 0 human, 1..3 bots. Team ids (dense) per slot and the lobby
## number each team had: slots 1 and 2 form team id 0 (lobby team 1), slots 0 and
## 3 form team id 1 (lobby team 3).
const SLOT_TEAM_IDS: Array[int] = [1, 0, 0, 1]
const TEAM_NUMBERS: Array[int] = [1, 3]
const PLAYER_COUNT: int = 4
const BOT_COUNT: int = 3
## Per slot; slot 0 is the human seat, so its entry is ignored.
const SEAT_DIFFICULTIES: Array[int] = [
	MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.EASY,
	MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.EASY,
]


class RasterFakeMatch:
	extends FakeMatch
	## HUD._update_minimap() only forwards colours to the minimap when the match
	## provider can answer raster() (the real Match can, plain FakeMatch cannot).

	func raster() -> TerritoryRaster:
		return null


class FakeMatchNet:
	extends RefCounted

	func request_replay() -> void:
		pass

	func request_return_to_lobby() -> void:
		pass


var _main: Variant = null
var _tiny_map: MapDef = null
var _base_config: MatchConfig = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)
	await get_tree().process_frame
	await get_tree().process_frame


# --- Fixtures ------------------------------------------------------------------

func _resolved_config() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = PLAYER_COUNT
	config.ai_count = BOT_COUNT
	config.team_mode = MatchConfig.TeamMode.TEAMS_4
	config.slot_team_ids = PackedInt32Array(SLOT_TEAM_IDS)
	config.team_numbers = PackedInt32Array(TEAM_NUMBERS)
	config.slot_ai_difficulties = PackedInt32Array(SEAT_DIFFICULTIES)
	config.ai_difficulty = MatchConfig.AiDifficulty.NORMAL
	return config


func _legacy_config(team_mode: MatchConfig.TeamMode = MatchConfig.TeamMode.TEAMS_2) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = PLAYER_COUNT
	config.ai_count = BOT_COUNT
	config.team_mode = team_mode
	config.ai_difficulty = MatchConfig.AiDifficulty.HARD
	return config


func _make_main() -> void:
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	_base_config = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	_base_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(_base_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	_base_config.rng_seed = 90210
	_main.match_config = _base_config
	add_child_autofree(_main)
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")


## Starts a real match on the Main fixture, the way the headless bot path does
## (register_world -> start_match; Main's own match_state_changed reaction builds
## the world), so the colour and bot wiring under test is the shipped one.
func _start_world(config: MatchConfig) -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	var start: MatchConfig = _base_config.duplicate(true) as MatchConfig
	start.player_count = config.player_count
	start.ai_count = config.ai_count
	start.team_mode = config.team_mode
	start.slot_team_ids = config.slot_team_ids
	start.team_numbers = config.team_numbers
	start.slot_ai_difficulties = config.slot_ai_difficulties
	start.ai_difficulty = config.ai_difficulty
	start.hot_seat = false
	start.sandbox = false
	start.countdown_seconds = 0.0
	Match.register_world(_main._field, _main._registry, _main._blocks_container)
	Match.start_match(start)
	await get_tree().process_frame
	await get_tree().process_frame


func _make_hud(fake_match: FakeMatch) -> HUD:
	var hud: HUD = autofree(HUD_SCENE.instantiate())
	add_child_autofree(hud)
	# After add_child: HUD._ready() points match_provider at the real Match.
	if fake_match != null:
		hud.match_provider = fake_match
	return hud


func _fake_match_with(config: MatchConfig) -> RasterFakeMatch:
	var fake_match: RasterFakeMatch = RasterFakeMatch.new()
	fake_match.config = config
	for slot_id: int in range(config.player_count):
		fake_match.slots_by_id[slot_id] = PlayerSlot.new(
			slot_id, config.team_of_slot(slot_id), "P%d" % (slot_id + 1), config.player_colors[slot_id]
		)
	return fake_match


func _make_results_screen(config: MatchConfig, net: FakeNet) -> ResultsScreen:
	var screen: ResultsScreen = autofree(RESULTS_SCENE.instantiate())
	add_child_autofree(screen)
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = config
	screen.net_provider = net
	screen.match_net_provider = FakeMatchNet.new()
	screen.match_provider = fake_match
	return screen


func _team_payload(winner_id: int = 1) -> Dictionary:
	var rows: Array[Dictionary] = []
	for slot_id: int in range(PLAYER_COUNT):
		rows.append({
			"slot_id": slot_id, "name": "P%d" % (slot_id + 1), "team_id": SLOT_TEAM_IDS[slot_id],
			"is_bot": slot_id > 0, "blocks_placed": 1, "blocks_lost": 0, "gifts_claimed": 0,
			"specials_used": 0, "territory_share": 0.25, "eliminated_at": MatchStats.NOT_ELIMINATED,
		})
	return {
		"winner_kind": MatchStats.WINNER_KIND_TEAM,
		"winner_id": winner_id,
		"winner_name": "Team %d" % (winner_id + 1),
		"match_duration": 90.0,
		"rows": rows,
	}


func _row_team_texts(screen: ResultsScreen) -> Dictionary:
	var texts: Dictionary = {}
	for index: int in range(1, screen._rows_list.get_child_count()):
		var panel: PanelContainer = screen._rows_list.get_child(index) as PanelContainer
		var cells: Array[Node] = (panel.get_child(0) as HBoxContainer).get_children()
		texts[int(panel.get_meta(&"slot_id"))] = (cells[1] as Label).text
	return texts


# --- Bots: per-slot difficulty (game/Main.gd) -----------------------------------

func _bot_difficulties() -> Array[int]:
	var difficulties: Array[int] = []
	for bot: BotController in _main._bot_controllers:
		difficulties.append(int(bot._difficulty))
	return difficulties


func test_each_bot_controller_gets_its_own_seats_difficulty() -> void:
	_make_main()
	_main._spawn_bot_controllers(_resolved_config())

	assert_eq(_main._bot_controllers.size(), BOT_COUNT, "one controller per trailing bot slot")
	assert_eq(
		_bot_difficulties(),
		[MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.EASY],
		"slots 1..3 read slot_ai_difficulties[1..3]; the human slot 0 entry is never used"
	)


func test_legacy_config_gives_every_bot_the_shared_difficulty() -> void:
	_make_main()
	_main._spawn_bot_controllers(_legacy_config())

	assert_eq(_main._bot_controllers.size(), BOT_COUNT)
	assert_eq(
		_bot_difficulties(),
		[MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.HARD],
		"no per-slot array: ai_difficulty drives every bot, exactly as before"
	)


func test_a_short_per_slot_array_falls_back_to_the_shared_difficulty() -> void:
	_make_main()
	var config: MatchConfig = _legacy_config()
	config.slot_ai_difficulties = PackedInt32Array([MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.EASY])
	_main._spawn_bot_controllers(config)

	assert_eq(
		_bot_difficulties(),
		[MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.HARD],
		"slot 1 is covered by the array, slots 2 and 3 fall back to ai_difficulty"
	)


func test_built_match_world_reaches_bot_controllers_with_seat_difficulties() -> void:
	_make_main()
	await _start_world(_resolved_config())

	assert_eq(Match.config.slot_ai_difficulties, PackedInt32Array(SEAT_DIFFICULTIES), "start_match keeps the per-slot array")
	assert_eq(
		_bot_difficulties(),
		[MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.EASY]
	)


# --- Colours: team-indexed vs slot-indexed (game/Main.gd) -------------------------

func _assert_same_rgb(actual: Color, expected: Color, message: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.0001, message + " (r)")
	assert_almost_eq(actual.g, expected.g, 0.0001, message + " (g)")
	assert_almost_eq(actual.b, expected.b, 0.0001, message + " (b)")


func test_world_build_hands_the_overlay_and_goal_flags_the_team_colours() -> void:
	_make_main()
	await _start_world(_resolved_config())

	var colors: PackedColorArray = Match.config.player_colors
	var field: Field = _main._field
	# Team id 0 is slots 1+2 (lowest: slot 1), team id 1 is slots 0+3 (lowest: slot 0).
	_assert_same_rgb(field._color_for_index(0), colors[1], "team 0 shows its lowest slot's colour")
	_assert_same_rgb(field._color_for_index(1), colors[0], "team 1 shows its lowest slot's colour")
	for slot_id: int in range(PLAYER_COUNT):
		_assert_same_rgb(field.home_flags()[slot_id].color(), colors[slot_id], "home flag %d keeps its player's own colour" % slot_id)


func test_world_build_with_a_legacy_team_config_is_unchanged() -> void:
	_make_main()
	await _start_world(_legacy_config())

	var colors: PackedColorArray = Match.config.player_colors
	var field: Field = _main._field
	_assert_same_rgb(field._color_for_index(0), colors[0], "legacy: team t is slot t")
	_assert_same_rgb(field._color_for_index(1), colors[1], "legacy: team t is slot t")


# --- HUD labels and colours (ui/HUD.gd) -------------------------------------------

func test_hud_winner_banner_names_the_lobby_team_number() -> void:
	var hud: HUD = _make_hud(_fake_match_with(_resolved_config()))
	hud.show_winner(1, Color.GOLD)
	assert_eq(hud._winner_label.text, "Team 3 wins!", "dense team 1 was lobby team 3")
	hud.show_winner(0, Color.GOLD)
	assert_eq(hud._winner_label.text, "Team 1 wins!")


func test_hud_winner_banner_is_unchanged_without_resolved_teams() -> void:
	var hud: HUD = _make_hud(_fake_match_with(_legacy_config()))
	hud.show_winner(1, Color.GOLD)
	assert_eq(hud._winner_label.text, "Team 2 wins!")
	var bare_hud: HUD = _make_hud(null)
	bare_hud.show_winner(0, Color.GOLD)
	assert_eq(bare_hud._winner_label.text, "Team 1 wins!", "no provider/config at all keeps team id + 1")


func test_hud_winner_and_capture_tints_use_the_team_colour() -> void:
	var config: MatchConfig = _resolved_config()
	var hud: HUD = _make_hud(_fake_match_with(config))
	var team_colors: PackedColorArray = config.territory_colors()

	hud._on_match_won(0)
	assert_eq(hud._winner_label.modulate, team_colors[0], "team 0 = lowest slot 1's colour, not slot 0's")
	hud._on_goal_capture_progress(1, 0.5)
	assert_eq(hud._capture_color, team_colors[1])
	hud._on_goal_capture_progress(-1, 0.0)
	assert_eq(hud._capture_color, Color.WHITE, "no capturer stays white")


func test_hud_winner_and_capture_tints_are_unchanged_without_resolved_teams() -> void:
	var config: MatchConfig = _legacy_config()
	var hud: HUD = _make_hud(_fake_match_with(config))

	hud._on_match_won(1)
	assert_eq(hud._winner_label.modulate, config.player_colors[1], "legacy: team t shows slot t's colour")
	hud._on_goal_capture_progress(0, 0.5)
	assert_eq(hud._capture_color, config.player_colors[0])


func test_mode_score_text_labels_use_the_lobby_numbers() -> void:
	var numbers: PackedInt32Array = PackedInt32Array(TEAM_NUMBERS)
	var ctf: Dictionary = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [2.0, 5.0], "round_left": 0.0}
	assert_eq(HUD.mode_score_text(ctf, numbers), "1: 2.0  3: 5.0")
	assert_eq(HUD.mode_score_text(ctf), "1: 2.0  2: 5.0", "no numbers: the legacy team id + 1")
	var elimination: Dictionary = {"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [2, 0], "round_left": 0.0}
	assert_eq(HUD.mode_score_text(elimination, numbers), "1: 2 alive  3: out")
	var domination: Dictionary = {"mode_id": MatchConfig.GameMode.DOMINATION, "scores": [0.3, 0.6], "round_left": 0.0}
	assert_eq(HUD.mode_score_text(domination, numbers), "Leading: 3 (60%)")
	assert_eq(HUD.mode_score_text(domination), "Leading: 2 (60%)")


func test_hud_mode_score_label_reads_the_running_configs_numbers() -> void:
	var hud: HUD = _make_hud(_fake_match_with(_resolved_config()))
	hud._on_mode_state_changed({"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [1.0, 4.0], "round_left": 0.0})
	assert_eq(hud._mode_score_label.text, "1: 1.0  3: 4.0")

	var legacy_hud: HUD = _make_hud(_fake_match_with(_legacy_config()))
	legacy_hud._on_mode_state_changed({"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [1.0, 4.0], "round_left": 0.0})
	assert_eq(legacy_hud._mode_score_label.text, "1: 1.0  2: 4.0")


func test_hud_share_rows_use_team_numbers_colours_and_team_elimination() -> void:
	var config: MatchConfig = _resolved_config()
	var fake_match: RasterFakeMatch = _fake_match_with(config)
	var hud: HUD = _make_hud(fake_match)
	var team_colors: PackedColorArray = config.territory_colors()

	hud.set_territory_shares(PackedFloat32Array([0.6, 0.4]))
	assert_eq((hud._share_labels[0] as Label).text, "P1: 60%")
	assert_eq((hud._share_labels[1] as Label).text, "P3: 40%", "second team was lobby team 3")
	assert_eq((hud._share_bars[0] as ColorRect).color, team_colors[0])
	assert_eq((hud._share_bars[1] as ColorRect).color, team_colors[1])

	# Team id 0 = slots 1 and 2: one home flag lost leaves the team in.
	fake_match.slots_by_id[1].home_flag_alive = false
	hud.set_territory_shares(PackedFloat32Array([0.6, 0.4]))
	assert_false((hud._share_labels[0] as Label).text.contains("out"), "slot 2 still stands")
	assert_false((hud._share_labels[1] as Label).text.contains("out"), "slot 1 is on team id 0, not team id 1")
	fake_match.slots_by_id[2].home_flag_alive = false
	hud.set_territory_shares(PackedFloat32Array([0.6, 0.4]))
	assert_true((hud._share_labels[0] as Label).text.contains("out"), "every slot of team id 0 lost its home flag")
	assert_false((hud._share_labels[1] as Label).text.contains("out"))


func test_hud_share_rows_are_unchanged_without_resolved_teams() -> void:
	var config: MatchConfig = _legacy_config()
	var fake_match: RasterFakeMatch = _fake_match_with(config)
	fake_match.slots_by_id[1].home_flag_alive = false
	var hud: HUD = _make_hud(fake_match)

	hud.set_territory_shares(PackedFloat32Array([0.6, 0.4]))
	assert_eq((hud._share_labels[0] as Label).text, "P1: 60%")
	assert_eq((hud._share_labels[1] as Label).text, "P2: 40%  (out)", "legacy: team t is slot t")
	assert_eq((hud._share_bars[0] as ColorRect).color, fake_match.slots_by_id[0].color)


func test_hud_forwards_team_colours_and_slot_colours_to_the_minimap() -> void:
	var config: MatchConfig = _resolved_config()
	var hud: HUD = _make_hud(_fake_match_with(config))

	Events.territory_share_changed.emit(PackedFloat32Array([0.5, 0.5]))

	assert_eq(hud._minimap._team_colors, config.territory_colors(), "territory/goal colours are per team")
	assert_eq(hud._minimap._slot_colors, config.player_colors, "beacons stay per slot")
	assert_ne(hud._minimap._team_colors, hud._minimap._slot_colors, "fixture: the two palettes really differ")


func test_hud_forwards_the_same_array_for_both_with_a_legacy_config() -> void:
	var config: MatchConfig = _legacy_config()
	var hud: HUD = _make_hud(_fake_match_with(config))

	Events.territory_share_changed.emit(PackedFloat32Array([0.5, 0.5]))

	assert_eq(hud._minimap._team_colors, config.player_colors)
	assert_eq(hud._minimap._slot_colors, config.player_colors)


# --- Minimap (ui/Minimap.gd, review F3) ----------------------------------------------

func _make_minimap() -> Minimap:
	var minimap: Minimap = autofree(Minimap.new())
	add_child_autofree(minimap)
	return minimap


func test_minimap_beacons_use_slot_colours_not_team_colours() -> void:
	var minimap: Minimap = _make_minimap()
	var team_colors: PackedColorArray = PackedColorArray([Color.RED, Color.BLUE])
	var slot_colors: PackedColorArray = PackedColorArray([Color.GREEN, Color.RED, Color.RED, Color.YELLOW])
	minimap.set_match_state(null, team_colors, PackedVector2Array(), slot_colors)

	assert_eq(minimap._beacon_color(0), Color.GREEN)
	assert_eq(minimap._beacon_color(3), Color.YELLOW, "slot 3 has no team entry: it must not read WHITE")
	assert_eq(minimap._beacon_color(9), Color.WHITE, "a slot beyond the palette is the neutral fallback")


func test_minimap_beacons_fall_back_to_the_single_colour_array() -> void:
	var minimap: Minimap = _make_minimap()
	minimap.set_match_state(null, PackedColorArray([Color.RED, Color.BLUE]), PackedVector2Array())

	assert_eq(minimap._beacon_color(1), Color.BLUE, "legacy 3-argument call: beacons read the one array")
	assert_eq(minimap._beacon_color(2), Color.WHITE)


func test_minimap_goal_and_capture_colours_are_per_team() -> void:
	var minimap: Minimap = _make_minimap()
	minimap.set_match_state(
		null, PackedColorArray([Color.RED, Color.BLUE]), PackedVector2Array(),
		PackedColorArray([Color.GREEN, Color.YELLOW, Color.CYAN, Color.MAGENTA])
	)
	minimap._goal_controls = PackedInt32Array([1, 0])

	assert_eq(minimap.goal_marker_color(0), Color.BLUE, "goal held by team 1")
	assert_eq(minimap.goal_marker_color(1), Color.RED, "goal held by team 0")


func test_minimap_territory_rebuild_watches_the_team_colours() -> void:
	var minimap: Minimap = _make_minimap()
	var map_def: MapDef = MapDef.new()
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, load("res://config/territory_tuning.tres"))
	minimap.set_match_state(raster, PackedColorArray([Color.RED, Color.BLUE]), PackedVector2Array(), PackedColorArray([Color.GREEN]))
	minimap.render_now()
	assert_false(minimap._image_inputs_changed())

	minimap.set_match_state(raster, PackedColorArray([Color.RED, Color.BLUE]), PackedVector2Array(), PackedColorArray([Color.CYAN]))
	assert_false(minimap._image_inputs_changed(), "beacon colours are drawn on the canvas, not baked into the territory image")
	minimap.set_match_state(raster, PackedColorArray([Color.RED, Color.CYAN]), PackedVector2Array(), PackedColorArray([Color.CYAN]))
	assert_true(minimap._image_inputs_changed(), "a team colour change forces a territory rebuild")


# --- Results screen labels (ui/ResultsScreen.gd) ------------------------------------

func test_team_number_in_falls_back_to_id_plus_one() -> void:
	var numbers: PackedInt32Array = PackedInt32Array(TEAM_NUMBERS)
	assert_eq(ResultsScreen.team_number_in(numbers, 0), 1)
	assert_eq(ResultsScreen.team_number_in(numbers, 1), 3)
	assert_eq(ResultsScreen.team_number_in(numbers, 2), 3, "beyond the table: team id + 1")
	assert_eq(ResultsScreen.team_number_in(PackedInt32Array(), 1), 2, "no table: team id + 1")


func test_results_rows_show_the_lobby_team_numbers() -> void:
	var screen: ResultsScreen = _make_results_screen(_resolved_config(), FakeNet.host())
	screen.show_results(_team_payload())

	var texts: Dictionary = _row_team_texts(screen)
	assert_eq(texts[0], "Team 3")
	assert_eq(texts[1], "Team 1")
	assert_eq(texts[2], "Team 1")
	assert_eq(texts[3], "Team 3")


func test_results_rows_are_unchanged_without_resolved_teams() -> void:
	var screen: ResultsScreen = _make_results_screen(_legacy_config(), FakeNet.host())
	screen.show_results(_team_payload())

	var texts: Dictionary = _row_team_texts(screen)
	assert_eq(texts[0], "Team 2", "legacy: SLOT_TEAM_IDS[0] = 1, shown as team id + 1")
	assert_eq(texts[1], "Team 1")


func test_shared_win_and_mode_scores_use_the_lobby_numbers() -> void:
	var numbers: PackedInt32Array = PackedInt32Array(TEAM_NUMBERS)
	var results: Dictionary = _team_payload(0)
	results["mode"] = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [5.0, 5.0], "winners": "0,1"}

	assert_eq(ResultsScreen.shared_winners_text(results, numbers), "Teams 1 & 3 share the win!")
	assert_eq(ResultsScreen.shared_winners_text(results), "Teams 1 & 2 share the win!", "legacy numbering")
	assert_true(ResultsScreen.mode_outcome_text(results, numbers).contains("Team 3: 5.0"))
	assert_true(ResultsScreen.mode_outcome_text(results).contains("Team 2: 5.0"))

	var ffa: Dictionary = results.duplicate(true)
	ffa["winner_kind"] = MatchStats.WINNER_KIND_SLOT
	assert_eq(ResultsScreen.shared_winners_text(ffa, numbers), "Players 1 & 2 share the win!", "FFA labels are slot numbers, never lobby team numbers")


func test_results_headline_uses_the_shared_win_numbers_of_the_running_config() -> void:
	var screen: ResultsScreen = _make_results_screen(_resolved_config(), FakeNet.host())
	var results: Dictionary = _team_payload(0)
	results["mode"] = {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [5.0, 5.0], "winners": "0,1"}
	screen.show_results(results)

	assert_eq(screen._headline.text, "Teams 1 & 3 share the win!")
	var hud: HUD = _make_hud(_fake_match_with(_resolved_config()))
	hud._on_match_results_ready(results)
	assert_eq(hud._winner_label.text, "Teams 1 & 3 share the win!")


# --- Results quick settings: per-slot difficulty and the seat table (review F2) ------

func _seats_table() -> Dictionary:
	var seats: Dictionary = LobbySeats.empty()
	(seats[LobbySeats.KEY_HUMANS] as Array).append({LobbySeats.FIELD_PEER_ID: 1, LobbySeats.FIELD_COLOR: 0, LobbySeats.FIELD_TEAM: 1})
	for ordinal: int in range(BOT_COUNT):
		(seats[LobbySeats.KEY_BOTS] as Array).append({
			LobbySeats.FIELD_COLOR: ordinal + 1,
			LobbySeats.FIELD_TEAM: 2,
			LobbySeats.FIELD_DIFFICULTY: SEAT_DIFFICULTIES[ordinal + 1],
		})
	return seats


func _published_bot_difficulties(data: Dictionary) -> Array[int]:
	var difficulties: Array[int] = []
	var seats: Dictionary = data[ResultsScreen.LOBBY_SEATS_KEY] as Dictionary
	for bot: Dictionary in (seats[LobbySeats.KEY_BOTS] as Array):
		difficulties.append(int(bot[LobbySeats.FIELD_DIFFICULTY]))
	return difficulties


func test_apply_with_an_untouched_dropdown_keeps_the_per_seat_difficulties() -> void:
	var config: MatchConfig = _resolved_config()
	var net: FakeNet = FakeNet.host()
	net.lobby_data_value = {"roster": [], ResultsScreen.LOBBY_SEATS_KEY: _seats_table()}
	var screen: ResultsScreen = _make_results_screen(config, net)
	screen.show_results(_team_payload())

	screen._on_settings_pressed()
	screen._on_settings_apply_pressed()

	assert_eq(config.slot_ai_difficulties, PackedInt32Array(SEAT_DIFFICULTIES), "nothing changed, nothing overwritten")
	assert_eq(config.slot_team_ids, PackedInt32Array(SLOT_TEAM_IDS), "resolved teams ride along for the rematch")
	var data: Dictionary = net.set_lobby_data_calls[0]
	assert_eq(_published_bot_difficulties(data), [SEAT_DIFFICULTIES[1], SEAT_DIFFICULTIES[2], SEAT_DIFFICULTIES[3]])
	assert_eq(MatchConfig.from_dict(data).slot_ai_difficulties, PackedInt32Array(SEAT_DIFFICULTIES), "the republished config carries the per-slot array")


func test_changing_the_dropdown_sets_every_bot_and_stays_alive() -> void:
	var config: MatchConfig = _resolved_config()  # ai_difficulty NORMAL; bots EASY, HARD, EASY
	var net: FakeNet = FakeNet.host()
	net.lobby_data_value = {"roster": [], ResultsScreen.LOBBY_SEATS_KEY: _seats_table()}
	var screen: ResultsScreen = _make_results_screen(config, net)
	screen.show_results(_team_payload())

	screen._on_settings_pressed()
	screen._ai_difficulty_option.selected = MatchConfig.AiDifficulty.HARD
	screen._on_settings_apply_pressed()

	var hard: int = MatchConfig.AiDifficulty.HARD
	assert_eq(config.ai_difficulty, MatchConfig.AiDifficulty.HARD)
	for slot_id: int in range(1, PLAYER_COUNT):
		assert_eq(
			config.ai_difficulty_for_slot(slot_id), MatchConfig.AiDifficulty.HARD,
			"the dropdown must reach the bot in slot %d even though per-slot values exist" % slot_id
		)
	var data: Dictionary = net.set_lobby_data_calls[0]
	assert_eq(_published_bot_difficulties(data), [hard, hard, hard], "the republished seat table follows")


func test_a_seat_that_becomes_a_bot_takes_the_dropdown_difficulty() -> void:
	var config: MatchConfig = _resolved_config()
	config.ai_count = 2  # slots 2 and 3 are bots, slot 1 is a human seat
	config.slot_ai_difficulties = PackedInt32Array([
		MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.HARD,
		MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.EASY,
	])
	var screen: ResultsScreen = _make_results_screen(config, FakeNet.host())
	screen.show_results(_team_payload())

	screen._on_settings_pressed()
	screen._ai_count_spin.value = 3
	screen._on_settings_apply_pressed()

	assert_eq(config.ai_count, 3)
	assert_eq(config.ai_difficulty_for_slot(1), MatchConfig.AiDifficulty.NORMAL, "the newly converted seat gets the dropdown value")
	assert_eq(config.ai_difficulty_for_slot(2), MatchConfig.AiDifficulty.EASY, "an existing bot keeps its seat's difficulty")
	assert_eq(config.ai_difficulty_for_slot(3), MatchConfig.AiDifficulty.EASY)
	config.sanitize()
	assert_true(config.teams_resolved(), "player_count did not change, so the resolved teams stay valid")


func test_republish_without_a_seat_table_adds_none_and_legacy_difficulty_still_applies() -> void:
	var config: MatchConfig = _legacy_config()
	var net: FakeNet = FakeNet.host()
	net.lobby_data_value = {"roster": []}
	var screen: ResultsScreen = _make_results_screen(config, net)
	screen.show_results(_team_payload())

	screen._on_settings_pressed()
	screen._ai_difficulty_option.selected = MatchConfig.AiDifficulty.EASY
	screen._on_settings_apply_pressed()

	assert_eq(config.ai_difficulty, MatchConfig.AiDifficulty.EASY)
	assert_true(config.slot_ai_difficulties.is_empty(), "a legacy config never grows a per-slot array here")
	var data: Dictionary = net.set_lobby_data_calls[0]
	assert_false(data.has(ResultsScreen.LOBBY_SEATS_KEY), "no lobby seat table existed, none is invented")
	assert_true(data.has("roster"))
