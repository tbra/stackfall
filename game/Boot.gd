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

var _threaded: bool = false


func _ready() -> void:
	# _process is auto-enabled by its override; only the threaded path polls (the sync path
	# would otherwise report a second, bogus failure).
	set_process(false)
	_threaded = (DisplayServer.get_name() != "headless"
			and ResourceLoader.load_threaded_request(main_scene_path) == OK)
	if not _threaded:
		# Deferred: the root is still adding its main scene while _ready runs, so the swap
		# happens on the next idle step instead of inside this callback.
		_start_main.call_deferred(load(main_scene_path) as PackedScene)
		return
	set_process(true)


func _process(_delta: float) -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(main_scene_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	set_process(false)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("Could not load %s (threaded load status %d)." % [main_scene_path, status])
		return
	_start_main(ResourceLoader.load_threaded_get(main_scene_path) as PackedScene)


func _start_main(scene: PackedScene) -> void:
	if scene == null:
		_fail("Could not load %s." % main_scene_path)
		return
	var main: Node = scene.instantiate()
	if main == null:
		_fail("Could not instantiate %s." % main_scene_path)
		return
	main.name = MAIN_NODE_NAME
	var tree: SceneTree = get_tree()
	tree.root.add_child(main)
	tree.current_scene = main
	queue_free()


func _fail(message: String) -> void:
	load_failed = true
	push_error("Boot: " + message)
	if not quit_on_failure:
		return
	if DisplayServer.get_name() != "headless":
		OS.alert(message, LOAD_FAILURE_TITLE)
	get_tree().quit(LOAD_FAILURE_EXIT_CODE)
