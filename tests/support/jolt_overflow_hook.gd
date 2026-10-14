extends GutHookScript
## GUT pre-run hook (configured as pre_run_script in .gutconfig.json,
## tools/run_gut.ps1 and tools/full_gate.py configs) that swaps GUT's error
## tracker for JoltOverflowErrorTracker, so the Jolt job-overflow warning is
## handled in every test of every runner (Bontago-fca.119).


func run() -> void:
	var old_tracker: GutErrorTracker = gut.error_tracker
	if old_tracker is JoltOverflowErrorTracker:
		return
	var tracker: JoltOverflowErrorTracker = JoltOverflowErrorTracker.new()
	tracker.treat_gut_errors_as = old_tracker.treat_gut_errors_as
	tracker.treat_engine_errors_as = old_tracker.treat_engine_errors_as
	tracker.treat_push_error_as = old_tracker.treat_push_error_as
	tracker.disabled = old_tracker.disabled
	var was_registered: bool = GutErrorTracker.registered_loggers.has(old_tracker)
	GutErrorTracker.deregister_logger(old_tracker)
	GutUtils._error_tracker = tracker
	gut.error_tracker = tracker
	if was_registered:
		GutErrorTracker.register_logger(tracker)
