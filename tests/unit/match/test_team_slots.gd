extends GutTest
## Lobby rework M1: match-side consumers of per-seat difficulty, team ids and team numbers.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/HUD.tscn")
const RESULTS_SCENE: PackedScene = preload("res://ui/menus/ResultsScreen.tscn")

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
	Settings._input(InputEventKey.new())
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


func _make_main() -> void:
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	_base_config = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	_base_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
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


# --- Bots: per-slot difficulty (game/main/Main.gd) -----------------------------------

func _bot_difficulties() -> Array[int]:
	var difficulties: Array[int] = []
	for node: Node in _main.find_children("*", "BotController", true, false):
		var bot: BotController = node as BotController
		difficulties.append(int(bot._difficulty))
	return difficulties


func test_each_bot_controller_gets_its_own_seats_difficulty() -> void:
	_make_main()
	_main._match_flow_port().call(&"spawn_bot_controllers", _resolved_config())

	assert_eq(MainNodes.count(_main, &"BotController"), BOT_COUNT, "one controller per trailing bot slot")
	assert_eq(
		_bot_difficulties(),
		[MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.HARD, MatchConfig.AiDifficulty.EASY],
		"slots 1..3 read slot_ai_difficulties[1..3]; the human slot 0 entry is never used"
	)


# --- Colours: team-indexed vs slot-indexed (game/main/Main.gd) -------------------------

func _assert_same_rgb(actual: Color, expected: Color, message: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.0001, message + " (r)")
	assert_almost_eq(actual.g, expected.g, 0.0001, message + " (g)")
	assert_almost_eq(actual.b, expected.b, 0.0001, message + " (b)")


## The colour a goal flag's capture ring shows for `team_id`, read after the
## replicated capture-progress event the game itself emits.
func _team_ring_color(field: Field, team_id: int) -> Color:
	Events.goal_capture_progress.emit(team_id, 0.5)
	var ring: MeshInstance3D = field.goal_flags()[0].find_child(&"CaptureRing", true, false) as MeshInstance3D
	return (ring.material_override as StandardMaterial3D).albedo_color


func test_world_build_hands_the_overlay_and_goal_flags_the_team_colours() -> void:
	_make_main()
	await _start_world(_resolved_config())

	var colors: PackedColorArray = Match.config.player_colors
	var field: Field = _main._field
	# Team id 0 is slots 1+2 (lowest: slot 1), team id 1 is slots 0+3 (lowest: slot 0).
	_assert_same_rgb(_team_ring_color(field, 0), colors[1], "team 0 shows its lowest slot's colour")
	_assert_same_rgb(_team_ring_color(field, 1), colors[0], "team 1 shows its lowest slot's colour")
	for slot_id: int in range(PLAYER_COUNT):
		_assert_same_rgb(field.home_flags()[slot_id].color(), colors[slot_id], "home flag %d keeps its player's own colour" % slot_id)


# --- HUD labels and colours (ui/hud/HUD.gd) -------------------------------------------

func test_hud_winner_banner_names_the_lobby_team_number() -> void:
	var hud: HUD = _make_hud(_fake_match_with(_resolved_config()))
	hud.show_winner(1, Color.GOLD)
	assert_eq(hud._winner_label.text, "Team 3 wins!", "dense team 1 was lobby team 3")
	hud.show_winner(0, Color.GOLD)
	assert_eq(hud._winner_label.text, "Team 1 wins!")


# --- Minimap (ui/hud/Minimap.gd, review F3) ----------------------------------------------

# --- Results screen labels (ui/menus/ResultsScreen.gd) ------------------------------------

func test_results_rows_show_the_lobby_team_numbers() -> void:
	var screen: ResultsScreen = _make_results_screen(_resolved_config(), FakeNet.host())
	screen.show_results(_team_payload())

	var texts: Dictionary = _row_team_texts(screen)
	assert_eq(texts[0], "Team 3")
	assert_eq(texts[1], "Team 1")
	assert_eq(texts[2], "Team 1")
	assert_eq(texts[3], "Team 3")

