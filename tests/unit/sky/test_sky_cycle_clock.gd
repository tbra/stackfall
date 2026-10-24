extends GutTest
## SkyCycleClock: the clock cases of test_sky_themes, ported with the same expected values.

const LENGTH_S: float = 300.0
const START_PHASE: float = 0.10
const EPS: float = 0.0001
const RATE_PROBE_CLOCK_S: float = 1000.0


func _running(length_s: float = LENGTH_S, start_phase: float = START_PHASE, at_clock: float = 0.0) -> SkyCycleClock:
	var clock: SkyCycleClock = SkyCycleClock.new()
	clock.start(at_clock, length_s, -1.0, start_phase)
	return clock


## Asserts the length in force through the phase rate: a quarter of `length_s` of clock is a quarter turn.
func _assert_length(clock: SkyCycleClock, length_s: float, label: String) -> void:
	var from_s: float = RATE_PROBE_CLOCK_S
	var turned: float = fposmod(clock.phase_at(from_s + length_s * 0.25) - clock.phase_at(from_s), 1.0)
	assert_almost_eq(turned, 0.25, EPS, label)


func test_a_fresh_clock_is_inactive_until_started() -> void:
	var clock: SkyCycleClock = SkyCycleClock.new()
	assert_false(clock.is_active())
	assert_eq(clock.locked_phase(), -1.0)
	assert_eq(clock.night_index(), 0)
	clock.set_locked(0.5)
	assert_eq(clock.locked_phase(), -1.0, "locking before start is a no-op")
	assert_false(clock.is_active(), "and does not start it")
	clock.start(10.0, LENGTH_S, 0.5, START_PHASE)
	assert_true(clock.is_active())
	assert_almost_eq(clock.locked_phase(), 0.5, EPS)


func test_cycle_runs_a_full_loop_in_the_authored_length() -> void:
	var clock: SkyCycleClock = _running()
	_assert_length(clock, LENGTH_S, "the authored length")
	assert_almost_eq(clock.phase_at(0.0), START_PHASE, EPS, "opens at the start phase")
	assert_almost_eq(clock.advance(75.0, LENGTH_S), fposmod(START_PHASE + 0.25, 1.0), EPS, "a quarter of 5 min on")
	assert_almost_eq(clock.advance(150.0, LENGTH_S), fposmod(START_PHASE + 0.5, 1.0), EPS)
	assert_almost_eq(clock.phase_at(300.0), START_PHASE, EPS, "a full cycle takes 300 s")


func test_start_phase_holds_at_a_nonzero_start_clock() -> void:
	var clock: SkyCycleClock = _running(60.0, 0.62, 1234.5)
	assert_almost_eq(clock.phase_at(1234.5), 0.62, EPS, "the offset puts the start phase at the start clock")
	assert_almost_eq(clock.phase_at(1234.5 + 15.0), fposmod(0.62 + 0.25, 1.0), EPS)


func test_cycle_length_change_keeps_the_phase_continuous() -> void:
	var clock: SkyCycleClock = _running()
	clock.advance(100.0, LENGTH_S)
	var before: float = clock.phase_at(100.0)
	assert_almost_eq(clock.advance(100.0, 900.0), before, EPS, "no jump at the edit")
	_assert_length(clock, 900.0, "the new length")
	assert_almost_eq(clock.advance(190.0, 900.0), fposmod(before + 90.0 / 900.0, 1.0), EPS,
		"afterwards the phase advances at the new rate")
	assert_almost_eq(clock.advance(190.0, 60.0), fposmod(before + 90.0 / 900.0, 1.0), EPS, "shortening is continuous too")
	assert_almost_eq(clock.advance(220.0, 60.0), fposmod(before + 90.0 / 900.0 + 30.0 / 60.0, 1.0), EPS)
	var direct: float = clock.phase_at(220.0)
	assert_almost_eq(clock.advance(220.0, 120.0), direct, EPS, "an edit folded in on a clock update has no jump either")


func test_length_below_the_floor_is_clamped() -> void:
	var clock: SkyCycleClock = _running(0.2)
	_assert_length(clock, SkyCycleClock.MIN_LENGTH_S, "clamped to the floor")
	assert_almost_eq(clock.advance(0.0, 0.0), START_PHASE, EPS)
	_assert_length(clock, SkyCycleClock.MIN_LENGTH_S, "clamped to the floor")


func test_lock_and_unlock_a_running_cycle_keep_the_phase_continuous() -> void:
	var clock: SkyCycleClock = _running()
	clock.advance(30.0, LENGTH_S)
	clock.set_locked(0.75)
	assert_almost_eq(clock.locked_phase(), 0.75, EPS)
	assert_almost_eq(clock.phase_at(30.0), 0.75, EPS, "the lock applies at once")
	assert_almost_eq(clock.advance(60.0, LENGTH_S), 0.75, EPS, "the clock does not move a locked sky")
	clock.set_locked(1.25)
	assert_almost_eq(clock.locked_phase(), 0.25, EPS, "a lock wraps into 0..1")
	clock.unlock(60.0)
	assert_eq(clock.locked_phase(), -1.0, "running again")
	assert_almost_eq(clock.phase_at(60.0), 0.25, EPS, "no jump at the unlock")
	assert_almost_eq(clock.advance(90.0, LENGTH_S), 0.35, EPS, "and it carries on at the cycle rate")
	clock.unlock(90.0)
	assert_almost_eq(clock.phase_at(90.0), 0.35, EPS, "unlocking a running cycle is a no-op")


func test_unlock_uses_the_clock_at_the_unlock_not_the_last_one_seen() -> void:
	var clock: SkyCycleClock = _running()
	clock.advance(30.0, LENGTH_S)
	clock.set_locked(0.40)
	clock.unlock(500.0)
	assert_almost_eq(clock.phase_at(500.0), 0.40, EPS, "continues from the locked phase at the unlock clock")
	assert_almost_eq(clock.phase_at(530.0), 0.50, EPS, "then at the cycle rate")


func test_start_locked_ignores_the_clock() -> void:
	var clock: SkyCycleClock = SkyCycleClock.new()
	clock.start(500.0, LENGTH_S, 0.5, START_PHASE)
	assert_almost_eq(clock.locked_phase(), 0.5, EPS)
	assert_almost_eq(clock.phase_at(9999.0), 0.5, EPS)
	assert_eq(clock.night_index(), 0, "a locked sky is night 0")


func test_length_edit_while_locked_applies_at_the_unlock() -> void:
	var clock: SkyCycleClock = _running()
	clock.advance(40.0, LENGTH_S)
	clock.set_locked(0.40)
	assert_almost_eq(clock.advance(80.0, 600.0), 0.40, EPS, "locked phase holds through a length edit")
	clock.unlock(80.0)
	assert_almost_eq(clock.phase_at(80.0), 0.40, EPS)
	assert_almost_eq(clock.phase_at(140.0), 0.50, EPS, "60 s at the new 600 s length")


func test_night_index_counts_whole_cycles() -> void:
	var clock: SkyCycleClock = _running(100.0, 0.10)
	assert_eq(clock.night_index(), 0)
	clock.advance(50.0, 100.0)
	assert_eq(clock.night_index(), 0, "0.6 into the first cycle")
	clock.advance(95.0, 100.0)
	assert_eq(clock.night_index(), 1, "0.10 + 0.95 crosses into night 1")
	clock.advance(250.0, 100.0)
	assert_eq(clock.night_index(), 2)
	clock.set_locked(0.75)
	assert_eq(clock.night_index(), 0, "locked is night 0")
	clock.unlock(250.0)
	assert_eq(clock.night_index(), 0, "unlocking re-bases the offset onto the held phase 0.75")


func test_a_lock_at_phase_zero_is_a_lock() -> void:
	var started: SkyCycleClock = SkyCycleClock.new()
	started.start(500.0, LENGTH_S, 0.0, START_PHASE)
	assert_eq(started.locked_phase(), 0.0, "locked at dawn from the start")
	assert_eq(started.phase_at(9999.0), 0.0, "and the clock is ignored")
	assert_eq(started.advance(7777.0, 600.0), 0.0, "a length edit does not move it")
	assert_eq(started.night_index(), 0)
	var clock: SkyCycleClock = _running()
	clock.advance(30.0, LENGTH_S)
	clock.set_locked(0.0)
	assert_eq(clock.locked_phase(), 0.0, "a lock at exactly 0 holds")
	assert_eq(clock.advance(60.0, LENGTH_S), 0.0)
	clock.unlock(60.0)
	assert_eq(clock.locked_phase(), -1.0, "and unlocks")
	assert_almost_eq(clock.phase_at(60.0), 0.0, EPS, "no jump at the unlock")
	assert_almost_eq(clock.phase_at(90.0), 0.10, EPS, "then it runs on")
