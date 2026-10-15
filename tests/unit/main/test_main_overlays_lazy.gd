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


func _drop_overlays() -> void:
	for node: Node in [_main._pause_menu_node, _main._results_screen_node, _main._scoreboard_node, _main._loading_screen_node]:
		if node != null:
			node.free()
	_main._pause_menu_node = null
	_main._results_screen_node = null
	_main._scoreboard_node = null
	_main._loading_screen_node = null


func test_ready_builds_none_of_the_overlays() -> void:
	assert_null(_main._pause_menu_node)
	assert_null(_main._results_screen_node)
	assert_null(_main._scoreboard_node)
	assert_null(_main._loading_screen_node)
	assert_not_null(_main._main_menu, "the menu still shows without them")


func test_client_loading_announcement_creates_and_shows_the_loading_screen_cold() -> void:
	assert_eq(Match.state(), Match.State.LOBBY)
	_main._on_match_loading_announced()
	assert_not_null(_main._loading_screen_node)
	assert_true(_main._loading_screen_node.visible)
	assert_true(_main._loading_screen_node.is_pending())
	assert_not_null(_main._results_screen_node, "all four exist before LOBBY -> LOADING")
	assert_not_null(_main._pause_menu_node)
	assert_not_null(_main._scoreboard_node)


func test_loading_state_change_builds_overlays_for_entries_that_skip_the_lobby() -> void:
	assert_eq(Net.host_game(0, "Host", false), OK)
	_drop_overlays()
	Match.start_match(_main.match_config)  # emits LOBBY -> LOADING straight at Main
	await get_tree().process_frame
	assert_not_null(_main._results_screen_node)
	assert_not_null(_main._scoreboard_node)
	assert_not_null(_main._pause_menu_node)


func test_overlay_still_prewarming_is_collected_on_demand() -> void:
	var queue: MenuPrewarmQueue = MenuPrewarmQueue.new()
	var cfg: MenuPrewarmConfig = MenuPrewarmConfig.new()
	var chunks: Array[PackedStringArray] = [PackedStringArray([PAUSE_PATH])]
	cfg.chunks = chunks
	queue.config = cfg
	queue.request_callable = func(_p: String) -> int: return OK
	queue.status_callable = func(_p: String) -> int: return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	queue.collect_callable = func(p: String) -> Resource: return load(p)
	queue.load_callable = func(p: String) -> Resource: return load(p)
	queue.exists_callable = func(_p: String) -> bool: return true
	_main._prewarm_queue = queue
	_main._prewarm_background = true
	queue.start(get_tree())
	var pause: PauseMenu = _main._pause_menu
	assert_not_null(pause, "ensure() resolves the in-flight chunk instead of loading beside it")
	assert_true(queue.is_ready(PAUSE_PATH))
	_main._prewarm_background = false
	_main._prewarm_queue = null  # Main builds its default queue lazily (after_each aborts via the match flow)

