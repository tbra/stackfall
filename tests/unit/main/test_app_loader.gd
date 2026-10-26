extends GutTest
## AppLoader: the background prewarm, late activation and scene loading Main delegates to. The
## Lobby chunk is collected before the menu shows, the rest loads behind it one request at a
## time, a click on a still-loading target shows "Loading..." once, and a window close during an
## in-flight chunk waits for it, never cancels it and quits once. A GatedPrewarmLoader replaces
## ResourceLoader. Contract tests: red against the null-object stub.

const LOBBY: String = "res://ui/lobby/Lobby.tscn"
const SANDBOX_FLOW: String = "res://game/main/MainSandboxFlow.gd"
const SANDBOX_SCENE: String = "res://game/sandbox/Sandbox.tscn"
const MATCH_FLOW: String = "res://game/main/MainMatchFlow.gd"
const OUTSIDE_SCENE: String = "res://ui/menus/PauseMenu.tscn"
const LOADING_TEXT: String = "Loading..."
const FRAME_LIMIT: int = 600
const IDLE_FRAMES: int = 5

var _gated: GatedPrewarmLoader = null
var _queue: MenuPrewarmQueue = null
var _quit: DeferredQuit = null
var _app: AppLoader = null
var _quit_calls: int = 0
var _status_texts: Array[String] = []


func _count_quit() -> void:
	_quit_calls += 1


func _record_status(text: String) -> void:
	_status_texts.append(text)


func _make_app(chunk_list: Array) -> AppLoader:
	_quit_calls = 0
	_status_texts.clear()
	_gated = GatedPrewarmLoader.new()
	_queue = GatedPrewarmLoader.make_queue(_gated, chunk_list)
	_quit = DeferredQuit.new()
	_quit.quit_callable = _count_quit
	_app = AppLoader.new()
	_app.queue = _queue
	_app.quit = _quit
	_app.loading_status_requested.connect(_record_status)
	add_child_autofree(_app)
	return _app


func _frames_until_quit() -> void:
	var frames: int = 0
	while _quit_calls == 0 and frames < FRAME_LIMIT:
		await get_tree().process_frame
		frames += 1


func after_each() -> void:
	if _gated != null:
		_gated.released = true
	get_tree().auto_accept_quit = true
	await get_tree().process_frame


func test_headless_run_does_not_want_the_background_prewarm() -> void:
	var app: AppLoader = _make_app([[LOBBY]])
	assert_false(app.wants_background(), "headless takes the synchronous on-demand path")
	assert_true(get_tree().auto_accept_quit, "the engine keeps the close request")


func test_begin_requests_only_the_lobby_chunk_and_owns_the_close_request() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW, SANDBOX_SCENE]])
	app.begin(LOBBY)
	assert_eq(_gated.requests, [LOBBY], "the Lobby chunk loads while the splash plays")
	assert_false(get_tree().auto_accept_quit, "the loader owns the close request while it prewarms")


func test_menu_shown_collects_the_lobby_first_and_the_rest_waits() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW, SANDBOX_SCENE]])
	app.begin(LOBBY)
	assert_true(app.menu_shown(LOBBY), "no close request: the menu may show")
	assert_true(_queue.is_ready(LOBBY), "Lobby is loaded before the menu shows")
	assert_false(_queue.is_ready(SANDBOX_FLOW), "the remaining chunks load behind the menu")
	assert_eq(_gated.requests, [LOBBY])


func test_chunks_load_serially_in_order_and_the_close_request_is_returned_when_drained() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW], [MATCH_FLOW]])
	app.begin(LOBBY)
	app.menu_shown(LOBBY)
	for _i: int in range(IDLE_FRAMES):
		await get_tree().process_frame
		assert_lte(_gated.in_flight.size(), 1, "never two requests in flight")
	assert_eq(_gated.requests, [LOBBY, SANDBOX_FLOW], "one more chunk is in flight, the third waits")
	_gated.released = true
	var frames: int = 0
	while not _queue.is_drained() and frames < FRAME_LIMIT:
		await get_tree().process_frame
		frames += 1
	assert_true(_queue.is_drained(), "everything loaded")
	assert_eq(_gated.requests, [LOBBY, SANDBOX_FLOW, MATCH_FLOW], "chunk order is kept")
	assert_eq(_gated.max_in_flight, 1, "the loader never saw two overlapping requests")
	await get_tree().process_frame
	assert_true(get_tree().auto_accept_quit, "once drained the engine owns the close request again")


func test_await_prewarmed_of_a_loading_target_shows_status_then_proceeds() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW]])
	app.begin(LOBBY)
	app.menu_shown(LOBBY)
	var results: Array[bool] = []
	var click: Callable = func() -> void: results.append(await app.await_prewarmed(PackedStringArray([SANDBOX_FLOW])))
	click.call()
	assert_eq(_status_texts, [LOADING_TEXT] as Array[String], "Loading... is requested in the click frame")
	assert_eq(results, [] as Array[bool], "the click waits one frame for the status to render")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(results, [true] as Array[bool], "then it proceeds")


func test_await_prewarmed_returns_false_while_a_click_is_pending() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW]])
	app.begin(LOBBY)
	app.menu_shown(LOBBY)
	var results: Array[bool] = []
	var click: Callable = func() -> void: results.append(await app.await_prewarmed(PackedStringArray([SANDBOX_FLOW])))
	click.call()
	var second: bool = await app.await_prewarmed(PackedStringArray([SANDBOX_FLOW]))
	assert_false(second, "the second activation is dropped while one waits")
	assert_eq(_status_texts.size(), 1, "and shows no second status")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(results, [true] as Array[bool])
	var third: bool = await app.await_prewarmed(PackedStringArray([LOBBY]))
	assert_true(third, "once the click settled, activations are accepted again")


func test_await_prewarmed_of_loaded_targets_shows_no_status() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW]])
	app.begin(LOBBY)
	app.menu_shown(LOBBY)
	app.ensure_late_active()
	_queue.ensure(SANDBOX_FLOW)
	var proceeded: bool = await app.await_prewarmed(PackedStringArray([LOBBY, SANDBOX_FLOW]))
	assert_true(proceeded)
	assert_eq(_status_texts, [] as Array[String], "nothing to wait for: no Loading... flash")


func test_await_prewarmed_without_background_proceeds_at_once() -> void:
	var app: AppLoader = _make_app([[LOBBY]])
	var proceeded: bool = await app.await_prewarmed(PackedStringArray([LOBBY]))
	assert_true(proceeded, "the synchronous path never waits")
	assert_eq(_status_texts, [] as Array[String])
	assert_true(app.is_late_active(), "late state is activated before the flow starts")


func test_ensure_late_active_activates_the_autoload_facades() -> void:
	var app: AppLoader = _make_app([[LOBBY]])
	app.ensure_late_active()
	assert_true(app.is_late_active())
	app.ensure_late_active()
	assert_true(app.is_late_active(), "idempotent")


func test_close_during_inflight_chunk_waits_then_quits_once() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW], [MATCH_FLOW]])
	app.begin(LOBBY)
	app.menu_shown(LOBBY)
	await get_tree().process_frame  # polling requests the second chunk
	assert_true(_queue.has_in_flight(), "a chunk is in flight")
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_quit_calls, 0, "no quit while the chunk loads")
	await get_tree().process_frame
	assert_eq(_quit_calls, 0)
	_gated.released = true
	await _frames_until_quit()
	assert_eq(_quit_calls, 1, "quits once the chunk is collected")
	assert_eq(_gated.requests, [LOBBY, SANDBOX_FLOW], "no further chunk starts after the close")
	assert_true(_queue.is_ready(SANDBOX_FLOW), "the in-flight chunk was collected, not cancelled")
	for _i: int in range(IDLE_FRAMES):
		await get_tree().process_frame
	assert_eq(_quit_calls, 1, "quit is not repeated")


func test_close_during_splash_quits_once_and_the_menu_never_shows() -> void:
	var app: AppLoader = _make_app([[LOBBY], [SANDBOX_FLOW]])
	app.begin(LOBBY)
	assert_true(_queue.has_in_flight(), "the Lobby chunk is in flight during the splash")
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_quit_calls, 0, "waits for the in-flight chunk")
	_gated.released = true
	await _frames_until_quit()
	assert_eq(_quit_calls, 1, "quits during the splash once the chunk is collected")
	assert_false(app.menu_shown(LOBBY), "the splash ending afterwards shows no menu")
	assert_eq(_quit_calls, 1, "quit is called exactly once")


func test_close_after_the_queue_drained_is_left_to_the_engine() -> void:
	var app: AppLoader = _make_app([[LOBBY]])
	app.begin(LOBBY)
	_gated.released = true
	app.menu_shown(LOBBY)
	for _i: int in range(IDLE_FRAMES):
		await get_tree().process_frame
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await get_tree().process_frame
	assert_eq(_quit_calls, 0, "drained: the engine alone quits (one quit path)")
	assert_true(get_tree().auto_accept_quit)


func test_close_without_background_prewarm_is_left_to_the_engine() -> void:
	var app: AppLoader = _make_app([[LOBBY]])
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await get_tree().process_frame
	assert_eq(_quit_calls, 0, "no deferred quit: the engine handles a close when nothing prewarms")
	assert_true(get_tree().auto_accept_quit)


func test_load_scene_collects_an_in_flight_chunk_instead_of_loading_beside_it() -> void:
	var app: AppLoader = _make_app([[SANDBOX_SCENE], [LOBBY]])
	app.begin(SANDBOX_SCENE)
	assert_eq(_gated.requests, [SANDBOX_SCENE])
	var scene: PackedScene = app.load_scene(SANDBOX_SCENE)
	assert_not_null(scene)
	assert_eq(_gated.collected, [SANDBOX_SCENE], "the threaded request was collected")
	assert_eq(_gated.sync_loads, [] as Array[String], "no synchronous load beside the in-flight chunk")


func test_load_scene_outside_the_queue_loads_directly() -> void:
	var app: AppLoader = _make_app([[SANDBOX_SCENE]])
	app.begin(SANDBOX_SCENE)
	var scene: PackedScene = app.load_scene(OUTSIDE_SCENE)
	assert_not_null(scene, "a path the queue does not know still loads")
	assert_false(_gated.requests.has(OUTSIDE_SCENE))
	assert_false(_gated.collected.has(OUTSIDE_SCENE))


func test_load_scene_without_background_loads_directly() -> void:
	var app: AppLoader = _make_app([[SANDBOX_SCENE]])
	assert_not_null(app.load_scene(SANDBOX_SCENE))
	assert_eq(_gated.requests, [] as Array[String], "the synchronous path never requests")


func test_ensure_script_returns_the_queued_script() -> void:
	var app: AppLoader = _make_app([[SANDBOX_FLOW]])
	app.begin(SANDBOX_FLOW)
	var script: GDScript = app.ensure_script(SANDBOX_FLOW)
	assert_not_null(script)
	if script != null:
		assert_eq(script.resource_path, SANDBOX_FLOW)
	assert_true(_queue.is_ready(SANDBOX_FLOW))
