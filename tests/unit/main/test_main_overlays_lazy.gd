extends GutTest
## MF5: Main creates PauseMenu / ResultsScreen / ScoreboardOverlay /
## LoadingScreen at first need (ensure), never in _ready(). Cold and while-prewarming paths work.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const PAUSE_PATH: String = "res://ui/menus/PauseMenu.tscn"
var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny
	var tiny_cfg: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_cfg.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_cfg as TinyMapMatchConfig).set_tiny_map(tiny)
	_main.match_config = tiny_cfg
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame


func _overlay_count() -> int:
	return MainNodes.count(_main, &"PauseMenu") + MainNodes.count(_main, &"ResultsScreen") 			+ MainNodes.count(_main, &"ScoreboardOverlay") + MainNodes.count(_main, &"LoadingScreen")


func test_ready_builds_none_of_the_overlays() -> void:
	assert_eq(_overlay_count(), 0)
	assert_not_null(MainNodes.main_menu(_main), "the menu still shows without them")


func test_hosting_builds_the_overlays_when_the_lobby_shows() -> void:
	assert_eq(Net.host_game(0, "Host", false), OK)
	assert_not_null(MainNodes.lobby(_main))
	assert_not_null(MainNodes.pause_menu(_main))
	assert_not_null(MainNodes.results_screen(_main))
	assert_not_null(MainNodes.first(_main, &"ScoreboardOverlay"))


func test_client_loading_announcement_creates_and_shows_the_loading_screen_cold() -> void:
	assert_eq(Match.state(), Match.State.LOBBY)
	Events.match_loading_announced.emit()
	var loading: LoadingScreen = MainNodes.loading_screen(_main)
	assert_not_null(loading)
	assert_true(loading.visible)
	assert_true(loading.is_pending())
	assert_not_null(MainNodes.results_screen(_main), "all four exist before LOBBY -> LOADING")
	assert_not_null(MainNodes.pause_menu(_main))
	assert_not_null(MainNodes.first(_main, &"ScoreboardOverlay"))


func test_start_match_straight_from_hosting_has_all_overlays() -> void:
	assert_eq(Net.host_game(0, "Host", false), OK)
	Match.start_match(_main.match_config)  # emits LOBBY -> LOADING straight at Main
	await get_tree().process_frame
	assert_not_null(MainNodes.results_screen(_main))
	assert_not_null(MainNodes.first(_main, &"ScoreboardOverlay"))
	assert_not_null(MainNodes.pause_menu(_main))
