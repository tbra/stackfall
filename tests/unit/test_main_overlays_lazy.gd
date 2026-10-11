extends GutTest
## Bontago-1pi.11.84.6 (MF5): Main creates PauseMenu / ResultsScreen / ScoreboardOverlay /
## LoadingScreen at first need (ensure), never in _ready(). Cold and while-prewarming paths work.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const PAUSE_PATH: String = "res://ui/PauseMenu.tscn"
const FRAME_LIMIT: int = 120

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny
	var tiny_cfg: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_cfg.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func test_each_overlay_is_created_on_first_access_once() -> void:
	var pause: PauseMenu = _main._pause_menu
	assert_not_null(pause)
	assert_true(pause.suppressed, "inert until a world exists")
	assert_same(_main._pause_menu, pause, "created once")
	assert_null(_main._results_screen_node, "touching one does not build the others")
	assert_not_null(_main._results_screen)
	assert_not_null(_main._scoreboard)
	assert_not_null(_main._loading_screen)
	assert_eq(_main.get_children().filter(func(n: Node) -> bool: return n is LoadingScreen).size(), 1)


func test_main_menu_and_territory_callbacks_do_not_create_overlays() -> void:
	_main._show_main_menu()
	_main._on_loading_territory_updated(null, null)
	_main._on_loading_territory_replicated(null)
	_main._on_pause_leave_requested()
	assert_null(_main._pause_menu_node)
	assert_null(_main._loading_screen_node)
	assert_null(_main._scoreboard_node)


func test_client_loading_announcement_creates_and_shows_the_loading_screen_cold() -> void:
	assert_eq(Match.state(), Match.State.LOBBY)
	_main._on_match_loading_announced()
	assert_not_null(_main._loading_screen_node)
	assert_true(_main._loading_screen_node.visible)
	assert_true(_main._loading_screen_node.is_pending())
	assert_not_null(_main._results_screen_node, "all four exist before LOBBY -> LOADING")
	assert_not_null(_main._pause_menu_node)
	assert_not_null(_main._scoreboard_node)


func test_host_lobby_start_creates_the_loading_screen_cold() -> void:
	assert_eq(Net.host_game(0, "Host", false), OK)
	assert_not_null(_main._pause_menu_node, "lobby entry builds the overlays")
	_drop_overlays()  # simulate a path that reaches Start without them
	var config: MatchConfig = _main.match_config.duplicate(true) as MatchConfig
	_main._on_lobby_start_pressed(config)
	assert_not_null(_main._loading_screen_node)
	assert_true(_main._loading_screen_node.is_pending())
	_main._start_pending = false


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


func test_overlays_are_queued_behind_the_menu_in_the_prewarm_config() -> void:
	var cfg: MenuPrewarmConfig = load("res://config/menu_prewarm.tres") as MenuPrewarmConfig
	var paths: PackedStringArray = cfg.all_paths()
	for p: String in ["res://ui/LoadingScreen.tscn", PAUSE_PATH, "res://ui/ResultsScreen.tscn", "res://ui/ScoreboardOverlay.tscn"]:
		assert_true(paths.has(p), p)
		assert_gt(paths.find(p), paths.find("res://ui/Lobby.tscn"))
