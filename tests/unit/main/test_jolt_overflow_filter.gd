extends GutTest
## the suite-wide Jolt job-overflow handler (pre-run hook).

const OVERFLOW: String = "Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please report this. Waiting for jobs to become available..."


func _log(tracker: GutErrorTracker, text: String, fn: String = "some_fn") -> GutTrackedError:
	return tracker.add_error(fn, "file.cpp", 1, text, "", false, Logger.ERROR_TYPE_WARNING, [])


func test_overflow_engine_error_is_handled() -> void:
	var tracker: JoltOverflowErrorTracker = JoltOverflowErrorTracker.new()
	tracker.start_test("t")
	var err: GutTrackedError = _log(tracker, OVERFLOW)
	assert_true(err.handled)
	assert_false(tracker.should_test_fail_from_errors("t"))


func test_other_engine_error_still_fails() -> void:
	var tracker: JoltOverflowErrorTracker = JoltOverflowErrorTracker.new()
	tracker.start_test("t")
	var err: GutTrackedError = _log(tracker, "Some other engine problem")
	assert_false(err.handled)
	assert_true(tracker.should_test_fail_from_errors("t"))


func test_push_error_with_overflow_text_still_fails() -> void:
	var tracker: JoltOverflowErrorTracker = JoltOverflowErrorTracker.new()
	tracker.start_test("t")
	var err: GutTrackedError = _log(tracker, OVERFLOW, "push_error")
	assert_false(err.handled)
	assert_true(tracker.should_test_fail_from_errors("t"))

