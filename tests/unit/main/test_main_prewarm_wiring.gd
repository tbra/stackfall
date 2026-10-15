extends GutTest
## Bontago-1pi.11.84 (MF4): Main builds MenuPrewarmQueue on the interactive path. The Lobby chunk
## is collected before the menu shows, the rest prewarms behind it one request at a time, an
## early menu click shows "Loading..." and proceeds, and a window close during an in-flight chunk
## waits for it (R7). Headless/flag runs stay synchronous. A fake loader gates the requests.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const LOBBY: String = "res://ui/lobby/Lobby.tscn"
const SANDBOX_FLOW: String = "res://game/main/MainSandboxFlow.gd"
const SANDBOX_SCENE: String = "res://game/sandbox/Sandbox.tscn"
const MATCH_FLOW: String = "res://game/main/MainMatchFlow.gd"
const FRAME_LIMIT: int = 600


class GatedLoader:
	extends RefCounted
	## status() reports IN_PROGRESS until `released`; collect()/load_sync() really load the path.
	var released: bool = false
	var in_flight: Array[String] = []
	var max_in_flight: int = 0
	var requests: Array[String] = []
	var collected: Array[String] = []

	func request(path: String) -> int:
		in_flight.append(path)
		requests.append(path)
		max_in_flight = maxi(max_in_flight, in_flight.size())
		return OK

	func status(_path: String) -> int:
		return ResourceLoader.THREAD_LOAD_LOADED if released else ResourceLoader.THREAD_LOAD_IN_PROGRESS

	func collect(path: String) -> Resource:
		in_flight.erase(path)
		collected.append(path)
		return load(path)

	func load_sync(path: String) -> Resource:
		return load(path)

	func exists(_path: String) -> bool:
		return true


var _main: Variant = null
var _loader: GatedLoader = null
var _quit_calls: int = 0


func _count_quit() -> void:
	_quit_calls += 1


func _fake_queue(chunk_list: Array) -> MenuPrewarmQueue:
	_loader = GatedLoader.new()
	var cfg: MenuPrewarmConfig = MenuPrewarmConfig.new()
	var chunks: Array[PackedStringArray] = []
	for entry: Variant in chunk_list:
		chunks.append(PackedStringArray(entry as Array))
	# The match flow is reached by any state change (Net.leave -> LOBBY), so it is always known.
	chunks.append(PackedStringArray([MATCH_FLOW]))
	cfg.chunks = chunks
	var queue: MenuPrewarmQueue = MenuPrewarmQueue.new()
	queue.config = cfg
	queue.request_callable = _loader.request
	queue.status_callable = _loader.status
	queue.collect_callable = _loader.collect
	queue.load_callable = _loader.load_sync
	queue.exists_callable = _loader.exists
	return queue


func _make_main(queue: MenuPrewarmQueue) -> Variant:
	var main: Variant = MAIN_SCENE.instantiate()
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny
	if queue != null:
		main._prewarm_queue = queue
		main.force_background_prewarm = true
		main.quit_callable = _count_quit
	return main


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_quit_calls = 0


func after_each() -> void:
	if _loader != null:
		_loader.released = true
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	get_tree().auto_accept_quit = true
	await get_tree().process_frame
	await get_tree().process_frame


func test_headless_and_default_runs_stay_synchronous() -> void:
	_main = _make_main(null)
	add_child_autofree(_main)
	assert_false(_main._prewarm_background, "headless takes the synchronous on-demand path")
	assert_false(_main._wants_background_prewarm())
	assert_not_null(_main._main_menu, "the menu is up at once")
	assert_true(get_tree().auto_accept_quit, "the engine keeps the close request")


func test_lobby_chunk_is_loaded_before_the_menu_shows() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW, SANDBOX_SCENE]])
	var menu_missing_at_lobby_ready: Array = []
	queue.path_ready.connect(func(path: String) -> void:
		if path == LOBBY:
			menu_missing_at_lobby_ready.append(_main._main_menu == null))
	_main = _make_main(queue)
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "the menu is shown")
	assert_true(queue.is_ready(LOBBY), "Lobby chunk ready by then")
	assert_eq(menu_missing_at_lobby_ready, [true], "the Lobby arrived while no menu existed yet")
	assert_eq(_loader.requests, [LOBBY], "only the Lobby chunk was requested before the menu")
	assert_false(queue.is_ready(SANDBOX_FLOW), "the remaining chunks wait for the menu")


func test_early_click_shows_loading_then_proceeds() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW, SANDBOX_SCENE]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	var menu: MainMenu = _main._main_menu as MainMenu
	assert_false(queue.is_ready(SANDBOX_FLOW))
	_main.start_sandbox_from_menu()
	assert_eq(menu._status_label.text, Main.LOADING_STATUS_TEXT, "Loading... is shown on the menu")
	assert_null(_main._sandbox, "the sandbox has not started in the click frame")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_not_null(_main._sandbox, "the click proceeds once the frame has rendered the status")


func test_close_during_inflight_chunk_waits_then_quits() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW], [MATCH_FLOW]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	await get_tree().process_frame  # polling requests the second chunk
	assert_true(queue.has_in_flight(), "a chunk is in flight")
	_main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_quit_calls, 0, "no quit while the chunk loads")
	await get_tree().process_frame
	assert_eq(_quit_calls, 0)
	_loader.released = true
	var frames: int = 0
	while _quit_calls == 0 and frames < FRAME_LIMIT:
		await get_tree().process_frame
		frames += 1
	assert_eq(_quit_calls, 1, "quits once the chunk is collected")
	assert_eq(_loader.requests, [LOBBY, SANDBOX_FLOW], "no further chunk starts after the close")
	assert_true(queue.is_ready(SANDBOX_FLOW), "the in-flight chunk was collected, not cancelled")


func test_close_during_splash_shows_no_menu_and_quits_once() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	# Simulate the splash window: menu not shown yet, polling off, a chunk in flight.
	_main._clear_menu_and_lobby()
	_main._prewarm_polling = false
	queue.poll()
	assert_true(queue.has_in_flight())
	_main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_quit_calls, 0, "waits for the in-flight chunk")
	_loader.released = true
	var frames: int = 0
	while _quit_calls == 0 and frames < FRAME_LIMIT:
		await get_tree().process_frame
		frames += 1
	assert_eq(_quit_calls, 1, "quits during the splash once the chunk is collected")
	_main._show_main_menu_after_prewarm()  # the splash ending afterwards
	assert_null(_main._main_menu, "no menu is shown after a close request")
	assert_eq(_quit_calls, 1, "quit is called exactly once")

