extends GutTest
## NetRateMeter: a cumulative counter turned into a per-second rate over a
## sliding window, on an injected clock.

const WINDOW_S: float = 2.0
const STEP_S: float = 0.5
const BYTES_PER_S: int = 1000
const BYTES_PER_STEP: int = 500
const TOLERANCE: float = 0.001
const NEW_MATCH_TOTAL: int = 100
const OLD_MATCH_TOTAL: int = 100000
const STALE_TOTAL: int = 999999

var _meter: NetRateMeter = null


func before_each() -> void:
	_meter = NetRateMeter.new(WINDOW_S)


## Samples a counter growing at BYTES_PER_S every STEP_S from `from_s` to `to_s` inclusive;
## returns the last total.
func _feed_steady(from_s: float, to_s: float, base_total: int) -> int:
	var total: int = base_total
	var now_s: float = from_s
	_meter.sample(total, now_s)
	while now_s < to_s - TOLERANCE:
		now_s += STEP_S
		total += BYTES_PER_STEP
		_meter.sample(total, now_s)
	return total


func test_no_samples_reads_zero() -> void:
	assert_eq(_meter.per_second(), 0.0)


func test_one_sample_reads_zero() -> void:
	_meter.sample(5000, 1.0)
	assert_eq(_meter.per_second(), 0.0)


func test_a_window_that_is_not_yet_full_reads_zero() -> void:
	_feed_steady(0.0, WINDOW_S - STEP_S, 0)
	assert_eq(_meter.per_second(), 0.0, "samples span less than the window")


func test_a_steady_counter_reads_its_rate_once_the_window_is_full() -> void:
	_feed_steady(0.0, WINDOW_S, 0)
	assert_almost_eq(_meter.per_second(), float(BYTES_PER_S), TOLERANCE)


func test_the_rate_stays_steady_as_the_window_slides() -> void:
	_feed_steady(0.0, 10.0, 0)
	assert_almost_eq(_meter.per_second(), float(BYTES_PER_S), TOLERANCE)


func test_the_rate_follows_the_recent_window_not_the_whole_history() -> void:
	var total: int = _feed_steady(0.0, WINDOW_S, 0)
	var now_s: float = WINDOW_S
	# The counter then stops growing: after one more full window the rate is zero.
	while now_s < 2.0 * WINDOW_S - TOLERANCE:
		now_s += STEP_S
		_meter.sample(total, now_s)
	assert_almost_eq(_meter.per_second(), 0.0, TOLERANCE)


func test_a_counter_that_never_moves_reads_zero() -> void:
	for step: int in range(8):
		_meter.sample(42, float(step) * STEP_S)
	assert_almost_eq(_meter.per_second(), 0.0, TOLERANCE)


func test_a_smaller_total_restarts_the_window() -> void:
	_feed_steady(0.0, 5.0, OLD_MATCH_TOTAL)
	assert_gt(_meter.per_second(), 0.0, "fixture: a rate was reading")
	_meter.sample(NEW_MATCH_TOTAL, 5.5)
	assert_eq(_meter.per_second(), 0.0, "the new match has no full window yet")


func test_after_a_restart_the_rate_ignores_the_old_total() -> void:
	_feed_steady(0.0, 5.0, OLD_MATCH_TOTAL)
	_meter.sample(NEW_MATCH_TOTAL, 5.5)
	var total: int = NEW_MATCH_TOTAL
	var now_s: float = 5.5
	while now_s < 5.5 + WINDOW_S - TOLERANCE:
		now_s += STEP_S
		total += BYTES_PER_STEP
		_meter.sample(total, now_s)
	assert_almost_eq(_meter.per_second(), float(BYTES_PER_S), TOLERANCE)


func test_a_sample_from_an_earlier_time_is_ignored() -> void:
	var total: int = _feed_steady(0.0, 4.0, 0)
	var before: float = _meter.per_second()
	assert_almost_eq(before, float(BYTES_PER_S), TOLERANCE, "fixture: a steady rate was reading")
	_meter.sample(STALE_TOTAL, 1.0)
	assert_almost_eq(_meter.per_second(), before, TOLERANCE, "a backwards clock changes nothing")
	_meter.sample(total + BYTES_PER_STEP, 4.5)
	assert_almost_eq(_meter.per_second(), float(BYTES_PER_S), TOLERANCE, "the stream carries on afterwards")


func test_two_meters_do_not_share_state() -> void:
	var other: NetRateMeter = NetRateMeter.new(WINDOW_S)
	_feed_steady(0.0, 4.0, 0)
	assert_eq(other.per_second(), 0.0)
