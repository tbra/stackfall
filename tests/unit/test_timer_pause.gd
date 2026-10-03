extends GutTest
## Bontago-1pi.18.4 (QoL Q0): the stall guard on core/rules/TimerPause.gd.
## A slot continuously paused for pause_max_s latches "exhausted" (reports
## not-paused, so its block timer runs) until the raw pause cause fully clears,
## then re-arms. Pure rule: no Match, no scene tree. Steps are powers of two so
## the float32 accumulators stay exact and boundaries can be asserted tightly.

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


func test_default_cap_is_ten_seconds_and_in_range() -> void:
	var qol: QolExperiments = QolExperiments.new()
	assert_eq(qol.pause_max_s, 10.0)
	assert_eq(qol.effective_pause_max_s(), 10.0)


func test_toggle_off_never_pauses_or_latches() -> void:
	var qol: QolExperiments = _qol()
	qol.timer_pause_enabled = false
	var rule: TimerPause = TimerPause.new(qol, 2)
	rule.note_special()
	_run(rule, 6.0, PackedInt32Array([9, 9]))
	assert_false(rule.is_paused(0))
	assert_false(rule.is_exhausted(0))


func test_pause_shorter_than_the_cap_is_untouched() -> void:
	var qol: QolExperiments = _qol(10.0)
	qol.pause_event_s = 4.0
	var rule: TimerPause = TimerPause.new(qol, 2)
	rule.note_special()
	_run(rule, 3.5)
	assert_true(rule.is_paused(0) and rule.is_paused(1), "still inside the event window")
	assert_false(rule.is_exhausted(0))
	_run(rule, 0.5)
	assert_false(rule.is_paused(0), "event window over")
	assert_false(rule.is_exhausted(0), "never reached the cap")


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


func test_default_cap_with_chained_specials() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.timer_pause_enabled = true
	var rule: TimerPause = TimerPause.new(qol, 1)
	var elapsed_s: float = 0.0
	var paused_at_9_75: bool = false
	while elapsed_s < 20.0:
		if int(round(elapsed_s / STEP_S)) % 4 == 0:
			rule.note_special()
		rule.update(STEP_S, PackedInt32Array())
		elapsed_s += STEP_S
		if is_equal_approx(elapsed_s, 9.75):
			paused_at_9_75 = rule.is_paused(0)
		if is_equal_approx(elapsed_s, 10.0):
			assert_false(rule.is_paused(0), "ten seconds of an unbroken chain exhausts the guard")
	assert_true(paused_at_9_75, "still paused just before the cap")
	assert_false(rule.is_paused(0), "the chain kept refreshing but the guard held")
	assert_true(rule.is_exhausted(0))


func test_refresh_while_exhausted_does_not_restart_the_pause() -> void:
	var rule: TimerPause = TimerPause.new(_qol(2.0), 1)
	rule.note_special()
	_run(rule, 2.0)
	assert_true(rule.is_exhausted(0))
	rule.note_special()
	assert_false(rule.is_paused(0), "a refreshed cause that never cleared stays guarded")
	_run(rule, 1.0)
	rule.note_special()
	assert_false(rule.is_paused(0))


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


func test_slots_exhaust_and_rearm_independently() -> void:
	var qol: QolExperiments = _qol(2.0)
	qol.pause_event_s = 3.0
	var rule: TimerPause = TimerPause.new(qol, 2)
	var slot0_topple: PackedInt32Array = PackedInt32Array([qol.topple_moving_blocks_min, 0])
	rule.note_special()
	_run(rule, 2.0, slot0_topple)
	assert_true(rule.is_exhausted(0) and rule.is_exhausted(1), "both capped under the shared event")
	_run(rule, 1.0, slot0_topple)
	assert_false(rule.is_exhausted(1), "slot 1's cause (the event) cleared at 3.0 s: re-armed")
	assert_true(rule.is_exhausted(0), "slot 0's own topple tail keeps it latched")
	rule.note_special()
	assert_true(rule.is_paused(1), "slot 1 pauses again for the next event")
	assert_false(rule.is_paused(0), "slot 0 stays guarded")


func test_two_runs_with_the_same_inputs_agree_step_for_step() -> void:
	var a: TimerPause = TimerPause.new(_qol(1.5), 3)
	var b: TimerPause = TimerPause.new(_qol(1.5), 3)
	var counts: PackedInt32Array = PackedInt32Array([4, 0, 5])
	a.note_special()
	b.note_special()
	for step: int in range(60):
		var feed: PackedInt32Array = counts if step < 20 else PackedInt32Array()
		a.update(STEP_S, feed)
		b.update(STEP_S, feed)
		for slot: int in range(3):
			assert_eq(a.is_paused(slot), b.is_paused(slot), "step %d slot %d" % [step, slot])
			assert_eq(a.is_exhausted(slot), b.is_exhausted(slot))


func test_out_of_range_slots_and_unsanitized_caps_are_safe() -> void:
	var qol: QolExperiments = _qol(0.0)
	var rule: TimerPause = TimerPause.new(qol, 1)
	rule.note_special()
	assert_false(rule.is_paused(-1))
	assert_false(rule.is_paused(1))
	assert_false(rule.is_exhausted(7))
	_run(rule, 0.5)
	assert_true(rule.is_paused(0), "a cap of 0 reads as the 1 s floor, not instant exhaustion")
	_run(rule, 0.5)
	assert_true(rule.is_exhausted(0))
	qol.pause_max_s = NAN
	assert_eq(qol.effective_pause_max_s(), 10.0, "non-finite falls back to the default")
