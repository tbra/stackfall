class_name MenuPrewarmQueue
extends RefCounted
## Bontago-1pi.11.84 (MF0): the single serial background loader behind the main menu
## (docs/MENU_FIRST_PLAN.md 3.1). At most one threaded request is ever in flight (F1: overlapping
## threaded loads of scripts with shared closures can hang), and every on-demand load goes through
## ensure() so a main-thread load never stalls behind a different chunk (F2). Never reuse Boot's
## own request: Boot frees itself at hand-over. Main owns the queue and drives poll() per frame.

signal path_ready(path: String)
signal drained()

## Ordered path chunks; assigning it rebuilds the set of known paths.
var config: MenuPrewarmConfig = null:
	set(value):
		config = value
		_rebuild_known()

## Test seams (default to ResourceLoader): request(path) -> Error, status(path) -> ThreadLoadStatus,
## collect(path) -> Resource (blocks until done), load_sync(path) -> Resource, exists(path) -> bool.
var request_callable: Callable = Callable()
var status_callable: Callable = Callable()
var collect_callable: Callable = Callable()
var load_callable: Callable = Callable()
var exists_callable: Callable = Callable()

var _known: Dictionary = {}
var _queue: PackedStringArray = PackedStringArray()
var _in_flight: String = ""
var _started: bool = false
var _drained_emitted: bool = false
## Strong references: the engine's resource cache only holds weak ones.
var _loaded: Dictionary = {}


func _init() -> void:
	request_callable = _default_request
	status_callable = _default_status
	collect_callable = _default_collect
	load_callable = _default_load
	exists_callable = _default_exists


## Interactive path only: begins background loading (headless and flag runs use run_blocking()).
func start(_tree: SceneTree) -> void:
	_started = true
	_drained_emitted = false
	_queue = _all_known_in_order()
	_advance()


## Drives the queue one step; call once per frame. Never has two requests in flight.
func poll() -> void:
	if not _started:
		return
	if not _in_flight.is_empty():
		var status: int = status_callable.call(_in_flight)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_collect_in_flight_path()
		else:
			# DECISION: a failed background load is dropped silently; ensure() later falls back
			# to a synchronous load() that reports the real error to the caller.
			_in_flight = ""
	_advance()


## The loaded resource for `path`. Collects the in-flight request when it is `path`, otherwise
## removes `path` from the queue and loads it synchronously. Unknown paths push one error.
func ensure(path: String) -> Resource:
	if _loaded.has(path):
		return _loaded[path] as Resource
	if not _known.has(path):
		push_error("MenuPrewarmQueue: '%s' is not a configured prewarm path." % path)
		return null
	if _in_flight == path:
		_collect_in_flight_path()
		return _loaded.get(path) as Resource
	var index: int = _queue.find(path)
	if index >= 0:
		_queue.remove_at(index)
	var resource: Resource = load_callable.call(path) as Resource
	if resource != null:
		_store(path, resource)
	return resource


func ensure_script(path: String) -> GDScript:
	return ensure(path) as GDScript


func is_ready(path: String) -> bool:
	return _loaded.has(path)


## True once start() ran and nothing is queued or in flight.
func is_drained() -> bool:
	return _started and _in_flight.is_empty() and _queue.is_empty()


func has_in_flight() -> bool:
	return not _in_flight.is_empty()


## Window close / _exit_tree: blocks until the in-flight request finishes so it is never
## cancelled (a cancelled worker compile logs "Could not preload" and may hang, 1pi.11.80).
func collect_in_flight() -> void:
	if not _in_flight.is_empty():
		_collect_in_flight_path()


## Drops everything still queued (no new requests); an in-flight one is left for
## collect_in_flight().
func halt() -> void:
	_queue = PackedStringArray()


## Loads every configured path synchronously, in order (paths whose file does not exist yet are
## skipped, as in the background path).
func load_all_blocking() -> void:
	collect_in_flight()
	_queue = PackedStringArray()
	for path: String in _all_known_in_order():
		if not _loaded.has(path) and exists_callable.call(path):
			ensure(path)


## Headless/test/CLI path: load everything now.
static func run_blocking(_tree: SceneTree, cfg: MenuPrewarmConfig) -> void:
	var queue: MenuPrewarmQueue = MenuPrewarmQueue.new()
	queue.config = cfg
	queue.load_all_blocking()


func _all_known_in_order() -> PackedStringArray:
	return config.all_paths() if config != null else PackedStringArray()


func _rebuild_known() -> void:
	_known.clear()
	for path: String in _all_known_in_order():
		_known[path] = true


## Requests the next queued path that exists; emits drained() once when nothing is left.
func _advance() -> void:
	while _in_flight.is_empty() and not _queue.is_empty():
		var path: String = _queue[0]
		_queue.remove_at(0)
		if _loaded.has(path) or not exists_callable.call(path):
			continue  # already loaded, or not created yet (later package): skip
		if request_callable.call(path) == OK:
			_in_flight = path
		# else: could not queue; ensure() falls back to a synchronous load.
	if _in_flight.is_empty() and _queue.is_empty() and _started and not _drained_emitted:
		_drained_emitted = true
		drained.emit()


func _collect_in_flight_path() -> void:
	var path: String = _in_flight
	_in_flight = ""
	var resource: Resource = collect_callable.call(path) as Resource
	if resource != null:
		_store(path, resource)


func _store(path: String, resource: Resource) -> void:
	_loaded[path] = resource
	path_ready.emit(path)


func _default_request(path: String) -> int:
	return ResourceLoader.load_threaded_request(path)


func _default_status(path: String) -> int:
	return ResourceLoader.load_threaded_get_status(path)


func _default_collect(path: String) -> Resource:
	return ResourceLoader.load_threaded_get(path)


func _default_load(path: String) -> Resource:
	return load(path)


func _default_exists(path: String) -> bool:
	return ResourceLoader.exists(path)
