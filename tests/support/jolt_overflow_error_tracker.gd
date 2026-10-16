class_name JoltOverflowErrorTracker
extends GutErrorTracker
## GUT error tracker that treats Jolt's job-queue overflow warning as handled.
##
## memories jolt-job-limit-flakes, jolt-job-overflow-flake:
## under CPU oversubscription in the parallel full gate, Jolt emits a
## WARN_PRINT_ONCE "job system exceeded the maximum number of jobs" that GUT
## counts as an unexpected engine error and attributes to whichever physics
## test is running. Serial runs never hit it. Only this exact message is
## handled; every other engine error, push_error and GUT error still fails.

const JOLT_JOB_OVERFLOW_TEXT: String = "Jolt Physics job system exceeded the maximum number of jobs"


## True when [param error] is an engine error carrying the Jolt overflow text.
static func is_jolt_job_overflow(error: GutTrackedError) -> bool:
	return error != null and error.is_engine_error() and error.contains_text(JOLT_JOB_OVERFLOW_TEXT)


func add_error(function: String, file: String, line: int,
		code: String, rationale: String, editor_notify: bool,
		error_type: int, script_backtraces: Array) -> GutTrackedError:
	var err: GutTrackedError = super(function, file, line, code, rationale,
		editor_notify, error_type, script_backtraces)
	if is_jolt_job_overflow(err):
		err.handled = true
	return err
