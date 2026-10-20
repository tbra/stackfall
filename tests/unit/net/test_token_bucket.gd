extends GutTest
## TokenBucket: starts full, refills linearly, caps at the burst, ignores a clock that
## steps backwards. Synthetic clock only.

const BURST: int = 4
const REFILL_PER_S: float = 2.0
const T0: float = 100.0
const HALF_STEP_S: float = 0.25
const LONG_IDLE_S: float = 1000.0
const BACKWARD_STEP_S: float = 50.0


func _drain(bucket: TokenBucket, now_s: float) -> int:
	var passed: int = 0
	while bucket.take(now_s, BURST, REFILL_PER_S) and passed <= BURST * 2:
		passed += 1
	return passed


func test_starts_full() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	assert_eq(_drain(bucket, T0), BURST)


func test_refill_after_one_period_passes_exactly_one() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	_drain(bucket, T0)
	assert_false(bucket.take(T0 + HALF_STEP_S, BURST, REFILL_PER_S), "half a token is not enough")
	assert_true(bucket.take(T0 + 2.0 * HALF_STEP_S, BURST, REFILL_PER_S), "1 / refill later one passes")
	assert_false(bucket.take(T0 + 2.0 * HALF_STEP_S, BURST, REFILL_PER_S))


func test_refill_caps_at_burst() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	_drain(bucket, T0)
	assert_eq(_drain(bucket, T0 + LONG_IDLE_S), BURST)


func test_negative_clock_step_refills_nothing_and_rebases() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	_drain(bucket, T0)
	assert_false(bucket.take(T0 - BACKWARD_STEP_S, BURST, REFILL_PER_S))
	# the earlier time is the new reference: refill counts from there, not from T0
	assert_false(bucket.take(T0 - BACKWARD_STEP_S + HALF_STEP_S, BURST, REFILL_PER_S))
	assert_true(bucket.take(T0 - BACKWARD_STEP_S + 2.0 * HALF_STEP_S, BURST, REFILL_PER_S))


func test_zero_refill_never_recovers() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	for i: int in BURST:
		assert_true(bucket.take(T0, BURST, 0.0))
	assert_false(bucket.take(T0 + LONG_IDLE_S, BURST, 0.0))


func test_negative_refill_is_treated_as_zero() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	_drain(bucket, T0)
	assert_false(bucket.take(T0 + LONG_IDLE_S, BURST, -REFILL_PER_S))


func test_zero_burst_still_holds_one_token() -> void:
	var bucket: TokenBucket = TokenBucket.new()
	assert_true(bucket.take(T0, 0, REFILL_PER_S))
	assert_false(bucket.take(T0, 0, REFILL_PER_S))
