extends GutTest
## QoL Q0: the stall guard on core/rules/TimerPause (a pause is capped at pause_max_s, then re-arms).

const STEP_S: float = 0.25


func _qol(pause_max_s: float = 2.0) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new()
	qol.timer_pause_enabled = true
	qol.pause_event_s = 30.0
	qol.pause_tail_s = 1.5
	qol.topple_scan_interval_s = STEP_S
	qol.topple_moving_blocks_min = 4
	qol.pause_max_s = pause_max_s
	return qol


## Runs `seconds` of STEP_S updates feeding the same moving counts every step.
func _run(rule: TimerPause, seconds: float, counts: PackedInt32Array = PackedInt32Array()) -> void:
	for _i: int in range(int(round(seconds / STEP_S))):
		rule.update(STEP_S, counts)


func test_toggle_off_never_pauses_or_latches() -> void:
	var qol: QolExperiments = _qol()
	qol.timer_pause_enabled = false
	var rule: TimerPause = TimerPause.new(qol, 2)
	rule.note_special()
	_run(rule, 6.0, PackedInt32Array([9, 9]))
	assert_false(rule.is_paused(0))
	assert_false(rule.is_exhausted(0))


func test_continuous_pause_exhausts_exactly_at_the_cap_then_runs() -> void:
	var rule: TimerPause = TimerPause.new(_qol(2.0), 2)
	rule.note_special()
	_run(rule, 1.75)
	assert_true(rule.is_paused(0), "one step before the cap")
	assert_false(rule.is_exhausted(0))
	_run(rule, STEP_S)
	assert_false(rule.is_paused(0), "cap reached: the timer runs")
	assert_true(rule.is_exhausted(0))
	assert_false(rule.is_paused(1), "global cause: every slot is guarded together")
	_run(rule, 5.0)
	assert_false(rule.is_paused(0), "stays running while the raw cause persists")


func test_rearms_after_the_raw_cause_fully_clears() -> void:
	var qol: QolExperiments = _qol(2.0)
	qol.pause_event_s = 3.0
	var rule: TimerPause = TimerPause.new(qol, 1)
	rule.note_special()
	_run(rule, 2.0)
	assert_true(rule.is_exhausted(0))
	_run(rule, 1.0)
	assert_false(rule.is_exhausted(0), "the event window ran out: re-armed")
	assert_false(rule.is_paused(0))
	rule.note_special()
	assert_true(rule.is_paused(0), "the next cause pauses again")
	_run(rule, 1.75)
	assert_true(rule.is_paused(0), "with a fresh cap window, not the old one")
	_run(rule, STEP_S)
	assert_true(rule.is_exhausted(0), "and exhausts again after another full cap")


func test_topple_cause_exhausts_and_rearms_after_the_tail() -> void:
	var qol: QolExperiments = _qol(2.0)
	var rule: TimerPause = TimerPause.new(qol, 2)
	var avalanche: PackedInt32Array = PackedInt32Array([qol.topple_moving_blocks_min, 0])
	_run(rule, 1.75, avalanche)
	assert_true(rule.is_paused(0))
	assert_false(rule.is_paused(1), "only the toppling slot is paused")
	_run(rule, STEP_S, avalanche)
	assert_true(rule.is_exhausted(0))
	assert_false(rule.is_paused(0))
	_run(rule, 3.0, avalanche)
	assert_false(rule.is_paused(0), "a long avalanche cannot hold the timer past the cap")
	_run(rule, qol.pause_tail_s - STEP_S)
	assert_true(rule.is_exhausted(0), "the tail is still part of the raw cause")
	_run(rule, STEP_S)
	assert_false(rule.is_exhausted(0), "tail over: re-armed")
	_run(rule, STEP_S, avalanche)
	assert_true(rule.is_paused(0), "a new topple pauses again")

