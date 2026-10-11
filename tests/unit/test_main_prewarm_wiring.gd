extends GutTest
## Bontago-1pi.11.84 (MF4): Main builds MenuPrewarmQueue on the interactive path. The Lobby chunk
## is collected before the menu shows, the rest prewarms behind it one request at a time, an
## early menu click shows "Loading..." and proceeds, and a window close during an in-flight chunk
## waits for it (R7). Headless/flag runs stay synchronous. A fake loader gates the requests.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const LOBBY: String = "res://ui/Lobby.tscn"
const SANDBOX_FLOW: String = "res://game/MainSandboxFlow.gd"
const SANDBOX_SCENE: String = "res://game/Sandbox.tscn"
const MATCH_FLOW: String = "res://game/MainMatchFlow.gd"
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
	var tiny: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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


func test_eager_flags_force_synchronous_startup() -> void:
	var cfg: MenuPrewarmConfig = load("res://config/menu_prewarm.tres") as MenuPrewarmConfig
	for flag: String in ["--hot-seat", "--sandbox", "--headless-host", "--host", "--join", "--host-online"]:
		assert_true(cfg.wants_eager(PackedStringArray([flag])), flag)
	assert_false(cfg.wants_eager(PackedStringArray(["--bots=2", "--agent-probe"])))


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


func test_remaining_chunks_prewarm_behind_the_menu_one_at_a_time() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW], [MATCH_FLOW]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	_loader.released = true
	var frames: int = 0
	while not queue.is_drained():
		await get_tree().process_frame
		frames += 1
		if frames > FRAME_LIMIT:
			break
	assert_true(queue.is_drained(), "all chunks loaded")
	assert_eq(_loader.requests, [LOBBY, SANDBOX_FLOW, MATCH_FLOW], "chunk order kept")
	assert_eq(_loader.max_in_flight, 1, "never two threaded loads at once (R1)")
	await get_tree().process_frame
	assert_true(get_tree().auto_accept_quit, "close request handed back once drained")


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


func test_click_on_a_ready_chunk_does_not_wait() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW, SANDBOX_SCENE]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	queue.ensure(SANDBOX_FLOW)
	queue.ensure(SANDBOX_SCENE)
	_main.start_sandbox_from_menu()
	assert_not_null(_main._sandbox, "no frame wait when the chunk is loaded")


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


func test_close_with_nothing_in_flight_quits_at_once() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	assert_false(queue.has_in_flight())
	_main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_quit_calls, 1)


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


func test_double_activation_in_loading_frame_runs_the_flow_once() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], [SANDBOX_FLOW, SANDBOX_SCENE]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	_main.start_sandbox_from_menu()
	_main.start_sandbox_from_menu()  # mouse plus gamepad in the same Loading... frame
	await get_tree().process_frame
	await get_tree().process_frame
	var sandboxes: int = 0
	for child: Node in _main.get_children():
		if child is Sandbox:
			sandboxes += 1
	assert_eq(sandboxes, 1, "the sandbox is built once")


## Bontago-1pi.11.85.2: the LateScripts paths are the second chunk, right behind the Lobby.
func test_late_scripts_chunk_follows_the_lobby_chunk() -> void:
	var cfg: MenuPrewarmConfig = load("res://config/menu_prewarm.tres") as MenuPrewarmConfig
	assert_eq(cfg.chunks[0], PackedStringArray([LOBBY]))
	assert_eq(cfg.chunks[1], LateScripts.paths(), "same paths, same order as LateScripts")


## Every flow's ensure collects the in-flight request first (never cancelled, F1/R7), then loads
## the missing LateScripts paths through the queue.
func test_load_late_paths_collects_in_flight_then_loads_the_rest() -> void:
	var late: Array = Array(LateScripts.paths())
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY], late, [SANDBOX_FLOW]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	await get_tree().process_frame  # polling requests the first late path
	assert_true(queue.has_in_flight())
	var in_flight: String = _loader.in_flight[0]
	_main._load_late_paths()
	assert_false(queue.has_in_flight(), "nothing left in flight after the ensure")
	assert_true(_loader.collected.has(in_flight), "the in-flight request was collected, not cancelled")
	for path: String in LateScripts.paths():
		assert_true(queue.is_ready(path), path)
	assert_eq(_loader.max_in_flight, 1)


func test_late_paths_outside_the_queue_config_are_ignored() -> void:
	var queue: MenuPrewarmQueue = _fake_queue([[LOBBY]])
	_main = _make_main(queue)
	add_child_autofree(_main)
	assert_true(_main._late_paths_in_queue().is_empty())
	_main._load_late_paths()  # no error, nothing to load
	assert_true(_main._late_active())
