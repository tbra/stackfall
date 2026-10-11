extends GutTest
## Bontago-1pi.11.53: game/Boot.tscn is the main scene and hands over to Main. Headless
## (this suite) takes the synchronous path, so Main exists right after Boot's _ready.

const MAIN_SCENE_SETTING: String = "application/run/main_scene"


func test_project_main_scene_is_boot() -> void:
	assert_eq(ProjectSettings.get_setting(MAIN_SCENE_SETTING), "res://game/Boot.tscn")
	assert_eq(Boot.MAIN_SCENE_PATH, "res://game/Main.tscn")


func test_headless_boot_adds_main_to_root_and_frees_itself() -> void:
	var boot: Boot = Boot.new()
	add_child(boot)
	# The hand-over is deferred one idle step (never add to the root inside _ready).
	await get_tree().process_frame
	var main: Node = get_tree().root.get_node_or_null(NodePath(Boot.MAIN_NODE_NAME))
	assert_not_null(main, "Main is added to the root after the deferred hand-over when headless")
	assert_true(not is_instance_valid(boot) or boot.is_queued_for_deletion(), "Boot removes itself after the hand-over")
	assert_eq(get_tree().current_scene, main)
	if main != null:
		main.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame


## Review of 1pi.11.53: a scene that cannot load must fail loudly (error + quit in the real
## game), never leave a black window waiting forever.
func test_missing_main_scene_fails_instead_of_hanging() -> void:
	var boot: Boot = Boot.new()
	boot.main_scene_path = "res://game/__missing_main_for_test__.tscn"
	boot.quit_on_failure = false
	add_child(boot)
	await get_tree().process_frame
	assert_true(boot.load_failed, "the failed load is reported")
	await get_tree().process_frame
	assert_push_error_count(1, "Boot reports the failure exactly once (no _process re-poll)")
	assert_engine_error_count(2, "the engine reports the failed sync load (open + condition)")
	boot.queue_free()


## S2b: (synchronous path) the late scripts are loaded and autoloads activated before Main joins the root.
func test_activation_hook_runs_before_main_is_added() -> void:
	var probe: Node = Node.new()
	probe.set_script(load("res://tests/unit/support/LateActivationProbe.gd"))
	get_tree().root.add_child(probe)
	var boot: Boot = Boot.new()
	add_child(boot)
	await get_tree().process_frame
	assert_eq(probe.get("calls"), 1, "late_activate called once by Boot")
	assert_false(probe.get("main_present_at_call"), "Main did not exist yet at activation")
	var main: Node = get_tree().root.get_node_or_null(NodePath(Boot.MAIN_NODE_NAME))
	if main != null:
		main.queue_free()
	probe.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame


const FIXTURE_SCENE: String = "res://tests/unit/support/BootFixture.tscn"
## Frames the quit-deferral test waits for the worker before giving up.
const WAIT_FRAME_LIMIT: int = 600

var _quit_calls: int = 0


func _count_quit() -> void:
	_quit_calls += 1


func _threaded_boot(path: String) -> Boot:
	var boot: Boot = Boot.new()
	boot.main_scene_path = path
	boot.quit_on_failure = false
	boot.force_threaded = true
	return boot


## Bontago-1pi.11.80: exit cleanup cancels an in-flight threaded load (and logs "Could not
## preload" for the whole script graph), so Boot collects it in _exit_tree.
func test_exit_collects_inflight_main_load() -> void:
	var boot: Boot = _threaded_boot(FIXTURE_SCENE)
	add_child(boot)
	remove_child(boot)  # same frame: the request is still pending; exit must collect it
	assert_eq(ResourceLoader.load_threaded_get_status(FIXTURE_SCENE), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"the request was collected (no pending task left for cleanup to cancel)")
	assert_not_null(boot.collected_resource, "the load completed rather than being cancelled")
	assert_false(boot.load_failed)
	boot.free()
	get_tree().auto_accept_quit = true


## Bontago-1pi.11.85.2: the threaded path hands Main over right after Main.tscn is collected, with
## no LateScripts prewarm and no autoload activation (Main does both behind the menu).
func test_threaded_boot_starts_main_without_prewarm_or_activation() -> void:
	var probe: Node = Node.new()
	probe.set_script(load("res://tests/unit/support/LateActivationProbe.gd"))
	get_tree().root.add_child(probe)
	var boot: Boot = _threaded_boot(FIXTURE_SCENE)
	add_child(boot)
	var frames: int = 0
	while get_tree().root.get_node_or_null(NodePath(Boot.MAIN_NODE_NAME)) == null and frames < WAIT_FRAME_LIMIT:
		await get_tree().process_frame
		frames += 1
	var main: Node = get_tree().root.get_node_or_null(NodePath(Boot.MAIN_NODE_NAME))
	assert_not_null(main, "Main started once Main.tscn was collected")
	assert_eq(probe.get("calls"), 0, "Boot does not activate the autoloads on the threaded path")
	assert_true(get_tree().auto_accept_quit, "the engine owns the close request again")
	if main != null:
		main.queue_free()
	probe.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame


func test_close_request_is_deferred_until_load_collected() -> void:
	_quit_calls = 0
	var boot: Boot = _threaded_boot("res://game/Main.tscn")
	boot.quit_callable = _count_quit
	add_child(boot)
	assert_false(get_tree().auto_accept_quit, "threaded boot owns the close request")
	boot.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_quit_calls, 0, "no quit while the load is in flight")
	var frames: int = 0
	while _quit_calls == 0 and frames < WAIT_FRAME_LIMIT:
		await get_tree().process_frame
		frames += 1
	assert_eq(_quit_calls, 1, "quits once the in-flight request is collected")
	assert_null(get_tree().root.get_node_or_null(NodePath(Boot.MAIN_NODE_NAME)), "Main is not started after a close request")
	boot.free()
	get_tree().auto_accept_quit = true
