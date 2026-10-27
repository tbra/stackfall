extends GutTest
## MF0: MenuPrewarmQueue is strictly serial, ensure() collects an in-flight
## path or dequeues a queued one, collect_in_flight() finishes
## the request, and unknown paths push one error. A fake loader replaces ResourceLoader.

const PATH_A: String = "res://fake/a.tscn"
const PATH_B: String = "res://fake/b.gd"
const PATH_C: String = "res://fake/c.tscn"
const PATH_UNKNOWN: String = "res://fake/unknown.tscn"
const REAL_PATH: String = "res://config/match/MenuPrewarmConfig.gd"
## Polls a fake request needs before it reports LOADED.
const FAKE_POLLS_TO_LOAD: int = 2
const POLL_LIMIT: int = 100


func _fake() -> GatedPrewarmLoader:
	var fake: GatedPrewarmLoader = GatedPrewarmLoader.new()
	fake.polls_to_load = FAKE_POLLS_TO_LOAD
	fake.fake_resources = true
	return fake


func _make(fake: GatedPrewarmLoader, chunk_list: Array) -> MenuPrewarmQueue:
	return GatedPrewarmLoader.make_queue(fake, chunk_list)


func test_requests_are_strictly_serial_and_in_order() -> void:
	var fake: GatedPrewarmLoader = _fake()
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
	var fake: GatedPrewarmLoader = _fake()
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
	var fake: GatedPrewarmLoader = _fake()
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


func test_missing_files_are_skipped_in_the_background() -> void:
	var fake: GatedPrewarmLoader = _fake()
	fake.missing = [PATH_A]
	var queue: MenuPrewarmQueue = _make(fake, [[PATH_A, PATH_B]])
	queue.start(get_tree())
	for _i: int in range(POLL_LIMIT):
		queue.poll()
	assert_eq(fake.requests, [PATH_B])
	assert_false(queue.is_ready(PATH_A))
