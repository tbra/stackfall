extends GutTest
## Bontago-1pi.11.84 (MF0): MenuPrewarmQueue is strictly serial, ensure() collects an in-flight
## path or dequeues a queued one, run_blocking loads everything, collect_in_flight() finishes
## the request, and unknown paths push one error. A fake loader replaces ResourceLoader.

const PATH_A: String = "res://fake/a.tscn"
const PATH_B: String = "res://fake/b.gd"
const PATH_C: String = "res://fake/c.tscn"
const PATH_UNKNOWN: String = "res://fake/unknown.tscn"
const REAL_PATH: String = "res://config/MenuPrewarmConfig.gd"
## Polls a fake request needs before it reports LOADED.
const FAKE_POLLS_TO_LOAD: int = 2
const POLL_LIMIT: int = 100


class FakeLoader:
	extends RefCounted
	var polls_to_load: int = FAKE_POLLS_TO_LOAD
	var in_flight: Array[String] = []
	var max_in_flight: int = 0
	var requests: Array[String] = []
	var collected: Array[String] = []
	var sync_loads: Array[String] = []
	var missing: Array[String] = []
	var _polls: Dictionary = {}

	func request(path: String) -> int:
		in_flight.append(path)
		requests.append(path)
		_polls[path] = 0
		max_in_flight = maxi(max_in_flight, in_flight.size())
		return OK

	func status(path: String) -> int:
		_polls[path] = int(_polls[path]) + 1
		if int(_polls[path]) >= polls_to_load:
			return ResourceLoader.THREAD_LOAD_LOADED
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS

	func collect(path: String) -> Resource:
		in_flight.erase(path)
		collected.append(path)
		return Resource.new()

	func load_sync(path: String) -> Resource:
		sync_loads.append(path)
		return Resource.new()

	func exists(path: String) -> bool:
		return not missing.has(path)


func _chunks(list: Array) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for entry: Variant in list:
		result.append(PackedStringArray(entry as Array))
	return result


func _make(fake: FakeLoader, chunk_list: Array) -> MenuPrewarmQueue:
	var cfg: MenuPrewarmConfig = MenuPrewarmConfig.new()
	cfg.chunks = _chunks(chunk_list)
	var queue: MenuPrewarmQueue = MenuPrewarmQueue.new()
	queue.config = cfg
	queue.request_callable = fake.request
	queue.status_callable = fake.status
	queue.collect_callable = fake.collect
	queue.load_callable = fake.load_sync
	queue.exists_callable = fake.exists
	return queue


func test_requests_are_strictly_serial_and_in_order() -> void:
	var fake: FakeLoader = FakeLoader.new()
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A], [PATH_B, PATH_C]])
	var drained: Array[bool] = [false]
	queue.drained.connect(func() -> void: drained[0] = true)
	queue.start(get_tree())
	for _i: int in range(POLL_LIMIT):
		queue.poll()
		assert_lte(fake.in_flight.size(), 1, "never two requests in flight")
		if drained[0]:
			break
	assert_true(drained[0], "drained() fires once everything loaded")
	assert_eq(fake.max_in_flight, 1, "the fake loader never saw two overlapping requests")
	assert_eq(fake.requests, [PATH_A, PATH_B, PATH_C], "chunk order is kept")
	assert_true(queue.is_ready(PATH_A) and queue.is_ready(PATH_B) and queue.is_ready(PATH_C))
	assert_false(queue.has_in_flight())


func test_ensure_of_in_flight_path_collects_it() -> void:
	var fake: FakeLoader = FakeLoader.new()
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A], [PATH_B]])
	queue.start(get_tree())
	assert_true(queue.has_in_flight())
	var resource: Resource = queue.ensure(PATH_A)
	assert_not_null(resource)
	assert_eq(fake.collected, [PATH_A], "collected through the threaded request")
	assert_eq(fake.sync_loads.size(), 0, "no synchronous load for an in-flight path")
	assert_true(queue.is_ready(PATH_A))
	assert_false(queue.has_in_flight(), "nothing in flight until the next poll")
	assert_eq(queue.ensure(PATH_A), resource, "second ensure returns the cached resource")


func test_ensure_of_queued_path_dequeues_it() -> void:
	var fake: FakeLoader = FakeLoader.new()
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A], [PATH_B], [PATH_C]])
	queue.start(get_tree())  # PATH_A in flight, B and C queued
	var resource: Resource = queue.ensure(PATH_C)
	assert_not_null(resource)
	assert_eq(fake.sync_loads, [PATH_C], "loaded synchronously")
	for _i: int in range(POLL_LIMIT):
		queue.poll()
	assert_false(fake.requests.has(PATH_C), "the dequeued path is never requested again")
	assert_eq(fake.max_in_flight, 1)
	assert_true(queue.is_ready(PATH_B))


func test_collect_in_flight_returns_after_completion() -> void:
	var fake: FakeLoader = FakeLoader.new()
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A], [PATH_B]])
	queue.start(get_tree())
	assert_true(queue.has_in_flight())
	queue.halt()
	queue.collect_in_flight()
	assert_false(queue.has_in_flight(), "the request completed")
	assert_true(queue.is_ready(PATH_A))
	assert_eq(fake.in_flight.size(), 0, "collected, never cancelled")
	queue.poll()
	assert_false(queue.has_in_flight(), "halt() stops further requests")
	assert_false(fake.requests.has(PATH_B))
	queue.collect_in_flight()  # idempotent when nothing is in flight
	assert_eq(fake.collected, [PATH_A])


func test_unknown_path_pushes_one_error_and_returns_null() -> void:
	var fake: FakeLoader = FakeLoader.new()
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A]])
	assert_null(queue.ensure(PATH_UNKNOWN))
	assert_push_error_count(1)
	assert_null(queue.ensure_script(PATH_UNKNOWN))
	assert_push_error_count(2)
	assert_eq(fake.sync_loads.size(), 0)


func test_missing_files_are_skipped_in_the_background() -> void:
	var fake: FakeLoader = FakeLoader.new()
	fake.missing = [PATH_A]
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A, PATH_B]])
	queue.start(get_tree())
	for _i: int in range(POLL_LIMIT):
		queue.poll()
	assert_eq(fake.requests, [PATH_B])
	assert_false(queue.is_ready(PATH_A))


func test_load_all_blocking_loads_every_path_in_order() -> void:
	var fake: FakeLoader = FakeLoader.new()
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A], [PATH_B, PATH_C]])
	queue.load_all_blocking()
	assert_eq(fake.sync_loads, [PATH_A, PATH_B, PATH_C])
	assert_eq(fake.requests.size(), 0, "no threaded request on the blocking path")
	assert_true(queue.is_ready(PATH_C))


func test_run_blocking_loads_a_real_resource() -> void:
	var cfg: MenuPrewarmConfig = MenuPrewarmConfig.new()
	cfg.chunks = _chunks([[REAL_PATH]])
	MenuPrewarmQueue.run_blocking(get_tree(), cfg)
	assert_not_null(load(REAL_PATH), "run_blocking completes without errors for an existing path")


func test_default_config_resource_loads_and_has_eager_flags() -> void:
	var cfg: MenuPrewarmConfig = load("res://config/menu_prewarm.tres") as MenuPrewarmConfig
	assert_not_null(cfg)
	assert_gt(cfg.chunks.size(), 0)
	assert_true(cfg.eager_flags.has("hot-seat"))
	assert_eq(cfg.all_paths()[0], "res://ui/Lobby.tscn", "lobby is the first chunk")
