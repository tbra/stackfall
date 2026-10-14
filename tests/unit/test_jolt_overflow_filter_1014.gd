extends GutTest
## Bontago-fca.119: the suite-wide Jolt job-overflow handler (pre-run hook).

const OVERFLOW: String = "Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please report this. Waiting for jobs to become available..."


func _log(tracker: GutErrorTracker, text: String, fn: String = "some_fn") -> GutTrackedError:
	return tracker.add_error(fn, "file.cpp", 1, text, "", false, Logger.ERROR_TYPE_WARNING, [])


## Every runner config names the hook. Checked statically (not via gut.error_tracker at run
## time) so the test also passes when an older runner without the hook runs it, e.g. the
## main-branch gate integrating this very change (Bontago-fca.119 integration, 2026-10-14).
const HOOK_PATH: String = "res://tests/support/jolt_overflow_hook.gd"
const RUNNER_FILES: Array[String] = ["res://.gutconfig.json", "res://tools/full_gate.py", "res://tools/run_gut.ps1"]


func test_every_runner_config_names_the_hook() -> void:
	for path: String in RUNNER_FILES:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.contains(HOOK_PATH), "%s configures the Jolt overflow pre-run hook" % path)


func test_hook_installs_the_filtering_tracker() -> void:
	if gut.error_tracker is JoltOverflowErrorTracker:
		assert_true(true, "this runner installed the hook")
		return
	pending("this run did not use the hook (older runner); the static config test covers the runners")


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


func test_gut_error_with_overflow_text_still_fails() -> void:
	var tracker: JoltOverflowErrorTracker = JoltOverflowErrorTracker.new()
	tracker.start_test("t")
	var err: GutTrackedError = tracker.add_error("t", "f", 1, OVERFLOW, "", false, GutUtils.GUT_ERROR_TYPE, [])
	assert_false(err.handled)
	assert_true(tracker.should_test_fail_from_errors("t"))
