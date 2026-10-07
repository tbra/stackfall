extends Node
## First autoload (non-singleton, Bontago-1pi.11.55 slice A). Compiles the remaining
## autoload scripts on a worker thread, one request at a time, while the main thread keeps
## the window message pump alive. Without it the autoload phase (several seconds of GDScript
## compilation) runs with no message pump and Windows shows "Not responding".
## Headless runs (tests, dedicated hosts) skip it entirely.

# DECISION: implementation constant, not a tunable. Short enough to keep pump gaps far below
# the OS hang threshold, long enough not to spin a core.
const PUMP_INTERVAL_MS: int = 5

# DECISION: implementation constant, not a tunable. Generous per-path cap for a slow disk or
# antivirus scan; after it the wait for that path ends silently and main.cpp loads it itself.
const MAX_WAIT_MS: int = 60000

const SELF_PATH: String = "res://autoload/StartupPump.gd"
const AUTOLOAD_PREFIX: String = "autoload/"
const SINGLETON_MARK: String = "*"
const SCRIPT_EXTENSION: String = ".gd"

var _held: Array[Resource] = []


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_held = pump_until_loaded(
		autoload_script_paths(), DisplayServer.force_process_and_drop_events, PUMP_INTERVAL_MS
	)


func _ready() -> void:
	# main.cpp owns the loaded scripts now; dropping ours avoids an exit-time leak delta.
	_held.clear()


## Autoload script paths in ProjectSettings order, "*" stripped, .gd only, excluding this file.
static func autoload_script_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key: String = prop["name"]
		if not key.begins_with(AUTOLOAD_PREFIX):
			continue
		var value: String = String(ProjectSettings.get_setting(key)).trim_prefix(SINGLETON_MARK)
		if value.ends_with(SCRIPT_EXTENSION) and value != SELF_PATH:
			paths.append(value)
	return paths


## Loads each path on the loader thread, one request at a time, calling `pump` between polls.
## A failed or invalid status ends that path's wait silently; the engine's own synchronous
## load reports the error later.
static func pump_until_loaded(
	paths: PackedStringArray,
	pump: Callable,
	sleep_ms: int,
	max_wait_ms: int = MAX_WAIT_MS,
	status_fn: Callable = Callable()
) -> Array[Resource]:
	var loaded: Array[Resource] = []
	for path: String in paths:
		if ResourceLoader.load_threaded_request(path) != OK:
			continue
		var started_ms: int = Time.get_ticks_msec()
		var status: int = _status(path, status_fn)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if Time.get_ticks_msec() - started_ms >= max_wait_ms:
				break
			pump.call()
			OS.delay_msec(sleep_ms)
			status = _status(path, status_fn)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var res: Resource = ResourceLoader.load_threaded_get(path)
			if res != null:
				loaded.append(res)
	return loaded


static func _status(path: String, status_fn: Callable) -> int:
	if status_fn.is_valid():
		return status_fn.call(path)
	return ResourceLoader.load_threaded_get_status(path)
