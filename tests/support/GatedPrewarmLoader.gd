class_name GatedPrewarmLoader
extends PrewarmLoader
## A PrewarmLoader test double: requests are recorded and report IN_PROGRESS until `released`
## (or until `polls_to_load` status polls when set); collect()/load_now() really load the path
## unless `fake_resources` is set. `missing` paths do not exist.
## `wire()` is the single place that hands a loader to a MenuPrewarmQueue.

var released: bool = false
## When > 0 a request reports LOADED after this many status polls instead of waiting for `released`.
var polls_to_load: int = 0
var fake_resources: bool = false
var in_flight: Array[String] = []
var max_in_flight: int = 0
var requests: Array[String] = []
var collected: Array[String] = []
var sync_loads: Array[String] = []
var missing: Array[String] = []
var _polls: Dictionary = {}


func request(path: String) -> bool:
	in_flight.append(path)
	requests.append(path)
	_polls[path] = 0
	max_in_flight = maxi(max_in_flight, in_flight.size())
	return true


func status(path: String) -> ResourceLoader.ThreadLoadStatus:
	if polls_to_load > 0:
		_polls[path] = int(_polls.get(path, 0)) + 1
		if int(_polls[path]) >= polls_to_load:
			return ResourceLoader.THREAD_LOAD_LOADED
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return ResourceLoader.THREAD_LOAD_LOADED if released else ResourceLoader.THREAD_LOAD_IN_PROGRESS


func collect(path: String) -> Resource:
	in_flight.erase(path)
	collected.append(path)
	return _resource(path)


func load_now(path: String) -> Resource:
	sync_loads.append(path)
	return _resource(path)


func exists(path: String) -> bool:
	return not missing.has(path)


func _resource(path: String) -> Resource:
	return Resource.new() if fake_resources else load(path)


## Hands `loader` to `queue` (the queue's loader seam).
static func wire(queue: MenuPrewarmQueue, loader: PrewarmLoader) -> void:
	queue.request_callable = func(path: String) -> int: return OK if loader.request(path) else ERR_CANT_CREATE
	queue.status_callable = loader.status
	queue.collect_callable = loader.collect
	queue.load_callable = loader.load_now
	queue.exists_callable = loader.exists


## A queue over `chunk_list` (an Array of Arrays of paths) that loads through `loader`.
static func make_queue(loader: PrewarmLoader, chunk_list: Array) -> MenuPrewarmQueue:
	var cfg: MenuPrewarmConfig = MenuPrewarmConfig.new()
	var chunks: Array[PackedStringArray] = []
	for entry: Variant in chunk_list:
		chunks.append(PackedStringArray(entry as Array))
	cfg.chunks = chunks
	var queue: MenuPrewarmQueue = MenuPrewarmQueue.new()
	queue.config = cfg
	wire(queue, loader)
	return queue
