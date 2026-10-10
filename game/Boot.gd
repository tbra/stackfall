class_name Boot
extends Node
## Bontago-1pi.11.53: the project's main scene. Compiling Main.gd and the menu/lobby/match
## script graph it names takes seconds; as the main scene that ran before the first frame with
## the window already open and no message pump, so Windows flagged "Not responding". Boot is
## trivially small: it queues game/Main.tscn on a worker thread, keeps the main loop (and so the
## window's message pump) running, then swaps Main in. Headless runs (tests, dedicated hosts)
## load synchronously so their startup order is unchanged.

const MAIN_SCENE_PATH: String = "res://game/Main.tscn"
const MAIN_NODE_NAME: String = "Main"
## Process exit code when the game scene cannot be loaded (review of 1pi.11.53: never leave a
## black window forever).
const LOAD_FAILURE_EXIT_CODE: int = 1
const LOAD_FAILURE_TITLE: String = "Stackfall"

## Test seams: the scene to load, and whether a load failure quits the process.
var main_scene_path: String = MAIN_SCENE_PATH
var quit_on_failure: bool = true
## Set when loading failed (read by tests).
var load_failed: bool = false
## Test seams: take the threaded path even headless; how a deferred close request quits.
var force_threaded: bool = false
var quit_callable: Callable = Callable()
## Set (force_threaded only) to the last collected resource so tests can observe that the
## load completed; the resource cache itself only holds weak references.
var collected_resource: Resource = null

var _threaded: bool = false
## Threaded path: Main.tscn once loaded, then LateScripts paths prewarmed one request at a time.
var _main_scene: PackedScene = null
var _prewarm_paths: PackedStringArray = PackedStringArray()
var _prewarm_index: int = -1
## Bontago-1pi.11.80: the threaded request not yet collected. Exit cleanup cancels an in-flight
## load and the cancelled worker compile logs "Could not preload" for the whole script graph
## (and can hang), so _exit_tree collects it first.
var _pending_path: String = ""
var _quit_requested: bool = false


func _ready() -> void:
	# _process is auto-enabled by its override; only the threaded path polls (the sync path
	# would otherwise report a second, bogus failure).
	set_process(false)
	_threaded = ((force_threaded or DisplayServer.get_name() != "headless")
			and ResourceLoader.load_threaded_request(main_scene_path) == OK)
	if not _threaded:
		# Deferred: the root is still adding its main scene while _ready runs, so the swap
		# happens on the next idle step instead of inside this callback.
		var scene: PackedScene = load(main_scene_path) as PackedScene
		if scene != null:
			for path: String in LateScripts.paths():
				load(path)
		_start_main.call_deferred(scene)
		return
	_pending_path = main_scene_path
	# DECISION: while the load is in flight a window close is deferred until it is collected,
	# so the message pump stays alive instead of blocking in _exit_tree ("Not responding").
	get_tree().auto_accept_quit = false
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not quit_callable.is_valid():  # test seam: no real quit
		QuitFlag.mark()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _threaded:
		_quit_requested = true
		if _pending_path.is_empty():
			_quit_now()  # nothing in flight (e.g. between phases): quit at once


func _exit_tree() -> void:
	_collect_pending()


## Collects the in-flight threaded request (blocks until it finishes) so it is never cancelled.
func _collect_pending() -> Object:
	if _pending_path.is_empty():
		return null
	var path: String = _pending_path
	_pending_path = ""
	var resource: Resource = ResourceLoader.load_threaded_get(path)
	if force_threaded:
		collected_resource = resource
	return resource


func _quit_now() -> void:
	set_process(false)  # review nit: never poll again once quitting
	if quit_callable.is_valid():
		quit_callable.call()
	else:
		QuitFlag.mark()
		get_tree().quit()


func _process(_delta: float) -> void:
	if _prewarm_index >= 0:
		_poll_prewarm()
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(main_scene_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	set_process(false)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_pending_path = ""
		_fail("Could not load %s (threaded load status %d)." % [main_scene_path, status])
		return
	_main_scene = _collect_pending() as PackedScene
	if _quit_requested:
		_quit_now()
		return
	_prewarm_paths = LateScripts.paths()
	_prewarm_index = 0
	if not _request_prewarm():
		_finish_threaded()
		return
	set_process(true)


## Requests the current prewarm path; false when the list is exhausted.
func _request_prewarm() -> bool:
	while _prewarm_index < _prewarm_paths.size():
		if ResourceLoader.load_threaded_request(_prewarm_paths[_prewarm_index]) == OK:
			_pending_path = _prewarm_paths[_prewarm_index]
			return true
		_prewarm_index += 1  # could not queue: the facade's load() falls back to sync
	return false


func _poll_prewarm() -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_prewarm_paths[_prewarm_index])
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_collect_pending()
	_prewarm_index += 1
	if _quit_requested:
		_quit_now()  # no new prewarm requests once a close was requested
		return
	if not _request_prewarm():
		_finish_threaded()


func _finish_threaded() -> void:
	_prewarm_index = -1
	set_process(false)
	_start_main(_main_scene)


func _start_main(scene: PackedScene) -> void:
	get_tree().auto_accept_quit = true
	if scene == null:
		_fail("Could not load %s." % main_scene_path)
		return
	var main: Node = scene.instantiate()
	if main == null:
		_fail("Could not instantiate %s." % main_scene_path)
		return
	main.name = MAIN_NODE_NAME
	var tree: SceneTree = get_tree()
	# S2b: facades that deferred their late state build it now, before Main exists.
	LateScripts.activate_autoloads(tree)
	tree.root.add_child(main)
	tree.current_scene = main
	queue_free()


func _fail(message: String) -> void:
	load_failed = true
	get_tree().auto_accept_quit = true
	push_error("Boot: " + message)
	if not quit_on_failure:
		return
	if DisplayServer.get_name() != "headless":
		OS.alert(message, LOAD_FAILURE_TITLE)
	QuitFlag.mark()
	get_tree().quit(LOAD_FAILURE_EXIT_CODE)
