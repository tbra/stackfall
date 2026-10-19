extends GutTest
## PeerFloodGate: one bucket per peer per intent, silent counted drops, forget_peer,
## and unknown intents are never limited. Synthetic clock only.

const INTENT_A: StringName = &"intent_a"
const INTENT_B: StringName = &"intent_b"
const INTENT_UNKNOWN: StringName = &"intent_unknown"
const PEER_1: int = 2
const PEER_2: int = 3
const BURST_A: int = 3
const REFILL_A: float = 1.0
const BURST_B: int = 5
const REFILL_B: float = 0.5
const T0: float = 10.0
const FLOOD_FACTOR: int = 3
const UNLIMITED_CALLS: int = 1000
const HONEST_SECONDS: int = 10


func _gate() -> PeerFloodGate:
	return PeerFloodGate.new({
		INTENT_A: Vector2(float(BURST_A), REFILL_A),
		INTENT_B: Vector2(float(BURST_B), REFILL_B),
	})


func _burst_calls(gate: PeerFloodGate, peer: int, intent: StringName, calls: int, now_s: float) -> int:
	var passed: int = 0
	for i: int in calls:
		if gate.allow(peer, intent, now_s):
			passed += 1
	return passed


func test_exactly_burst_pass_and_rest_are_counted_drops() -> void:
	var gate: PeerFloodGate = _gate()
	assert_eq(_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0), BURST_A)
	assert_eq(gate.dropped(PEER_1, INTENT_A), BURST_A * (FLOOD_FACTOR - 1))


func test_refill_after_one_period_lets_one_through() -> void:
	var gate: PeerFloodGate = _gate()
	_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0)
	assert_false(gate.allow(PEER_1, INTENT_A, T0 + 0.5 / REFILL_A))
	assert_true(gate.allow(PEER_1, INTENT_A, T0 + 1.0 / REFILL_A))
	assert_false(gate.allow(PEER_1, INTENT_A, T0 + 1.0 / REFILL_A))


func test_peers_are_isolated() -> void:
	var gate: PeerFloodGate = _gate()
	_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0)
	assert_eq(_burst_calls(gate, PEER_2, INTENT_A, BURST_A * FLOOD_FACTOR, T0), BURST_A)
	assert_eq(gate.dropped(PEER_2, INTENT_A), BURST_A * (FLOOD_FACTOR - 1))


func test_intents_are_isolated_per_peer() -> void:
	var gate: PeerFloodGate = _gate()
	_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0)
	assert_eq(_burst_calls(gate, PEER_1, INTENT_B, BURST_B * FLOOD_FACTOR, T0), BURST_B)
	assert_eq(gate.dropped(PEER_1, INTENT_B), BURST_B * (FLOOD_FACTOR - 1))
	assert_eq(gate.dropped(PEER_1, INTENT_A), BURST_A * (FLOOD_FACTOR - 1), "A's count unchanged by B")


func test_unknown_intent_is_never_limited_or_counted() -> void:
	var gate: PeerFloodGate = _gate()
	assert_eq(_burst_calls(gate, PEER_1, INTENT_UNKNOWN, UNLIMITED_CALLS, T0), UNLIMITED_CALLS)
	assert_eq(gate.dropped(PEER_1, INTENT_UNKNOWN), 0)


func test_empty_limits_never_limit() -> void:
	var gate: PeerFloodGate = PeerFloodGate.new({})
	assert_eq(_burst_calls(gate, PEER_1, INTENT_A, UNLIMITED_CALLS, T0), UNLIMITED_CALLS)


func test_forget_peer_restores_full_bucket_and_clears_counter() -> void:
	var gate: PeerFloodGate = _gate()
	_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0)
	_burst_calls(gate, PEER_2, INTENT_A, BURST_A * FLOOD_FACTOR, T0)
	gate.forget_peer(PEER_1)
	assert_eq(gate.dropped(PEER_1, INTENT_A), 0)
	assert_eq(_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0), BURST_A, "rejoin starts full")
	assert_eq(gate.dropped(PEER_2, INTENT_A), BURST_A * (FLOOD_FACTOR - 1), "other peer untouched")


func test_forget_unknown_peer_is_harmless() -> void:
	var gate: PeerFloodGate = _gate()
	gate.forget_peer(PEER_1)
	assert_true(gate.allow(PEER_1, INTENT_A, T0))


func test_dropped_for_untouched_peer_is_zero() -> void:
	var gate: PeerFloodGate = _gate()
	assert_eq(gate.dropped(PEER_1, INTENT_A), 0)


func test_honest_rate_never_drops() -> void:
	var gate: PeerFloodGate = _gate()
	var now_s: float = T0
	var step_s: float = 1.0 / REFILL_A
	for i: int in HONEST_SECONDS:
		assert_true(gate.allow(PEER_1, INTENT_A, now_s))
		now_s += step_s
	assert_eq(gate.dropped(PEER_1, INTENT_A), 0)


func test_limits_table_is_copied() -> void:
	var limits: Dictionary = {INTENT_A: Vector2(float(BURST_A), REFILL_A)}
	var gate: PeerFloodGate = PeerFloodGate.new(limits)
	limits.clear()
	assert_eq(_burst_calls(gate, PEER_1, INTENT_A, BURST_A * FLOOD_FACTOR, T0), BURST_A)
