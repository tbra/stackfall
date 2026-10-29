extends GutTest
## NetPing.jitter_ms(peer_id): mean absolute deviation of the peer's kept RTT
## samples, in ms. Driven on a synthetic millisecond clock like test_net_ping.

const PEER: int = 2
const OTHER_PEER: int = 3
const UNKNOWN_PEER: int = 99
const FIRST_PING_MS: int = 100000
const MS_PER_S: int = 1000
const SPIKE_RTT_MS: int = 500
const STEADY_RTT_MS: int = 60
const TOLERANCE: float = 0.001

var _config: NetConfig = null
var _ping: NetPing = null


func before_each() -> void:
	_config = (load("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
	_config.sanitize()
	var seams: NetPing.Seams = NetPing.Seams.new()
	seams.targets = func() -> Array: return [PEER, OTHER_PEER]
	seams.send_ping = func(_peer_id: int, _sent_at_ms: int) -> void: pass
	_ping = NetPing.new(_config, PeerFloodGate.new(FloodLimits.from_config(_config)), seams)


func _jitter(peer_id: int) -> float:
	return _ping.jitter_ms(peer_id)


## Round trip number `index`: the ping goes out and the echo returns `rtt_ms` later.
func _round_trip(index: int, rtt_ms: int, peer_id: int = PEER) -> void:
	var sent_ms: int = FIRST_PING_MS + index * MS_PER_S
	_ping.tick(sent_ms)
	_ping.on_pong(peer_id, sent_ms, sent_ms + rtt_ms)


func test_a_peer_with_no_sample_has_zero_jitter() -> void:
	assert_eq(_jitter(PEER), 0.0)
	assert_eq(_jitter(UNKNOWN_PEER), 0.0)


func test_one_sample_has_zero_jitter() -> void:
	_round_trip(0, 50)
	assert_eq(_jitter(PEER), 0.0)


func test_equal_samples_have_zero_jitter() -> void:
	for index: int in range(4):
		_round_trip(index, STEADY_RTT_MS)
	assert_almost_eq(_jitter(PEER), 0.0, TOLERANCE)


func test_spread_samples_have_positive_jitter() -> void:
	_round_trip(0, 50)
	_round_trip(1, 90)
	assert_gt(_jitter(PEER), 0.0)


func test_jitter_is_the_mean_absolute_deviation() -> void:
	_round_trip(0, 50)
	_round_trip(1, 70)
	assert_almost_eq(_jitter(PEER), 10.0, TOLERANCE, "samples 50 and 70: mean 60, each 10 away")
	_round_trip(2, 60)
	assert_almost_eq(_jitter(PEER), 20.0 / 3.0, TOLERANCE, "samples 50, 70, 60: (10 + 10 + 0) / 3")


func test_wider_spread_means_larger_jitter() -> void:
	_round_trip(0, 50)
	_round_trip(1, 70)
	var narrow: float = _jitter(PEER)
	_round_trip(2, 300)
	assert_gt(_jitter(PEER), narrow)


func test_a_stale_echo_does_not_change_the_jitter() -> void:
	_round_trip(0, 50)
	_round_trip(1, 70)
	var before: float = _jitter(PEER)
	var third_ping_ms: int = FIRST_PING_MS + 2 * MS_PER_S
	_ping.tick(third_ping_ms)
	# The echo of the first ping arrives after the third went out: older than the last ping sent.
	_ping.on_pong(PEER, FIRST_PING_MS, third_ping_ms + SPIKE_RTT_MS)
	assert_almost_eq(_jitter(PEER), before, TOLERANCE)


func test_each_peer_has_its_own_jitter() -> void:
	_round_trip(0, 50)
	_round_trip(1, 90)
	_round_trip(0, STEADY_RTT_MS, OTHER_PEER)
	assert_gt(_jitter(PEER), 0.0)
	assert_eq(_jitter(OTHER_PEER), 0.0, "one sample on the other peer")


func test_only_the_kept_history_counts() -> void:
	_round_trip(0, SPIKE_RTT_MS)
	for index: int in range(1, _config.ping_history + 1):
		_round_trip(index, STEADY_RTT_MS)
	assert_almost_eq(_jitter(PEER), 0.0, TOLERANCE, "the spike fell out of the window")


func test_a_forgotten_peer_has_no_jitter() -> void:
	_round_trip(0, 50)
	_round_trip(1, 90)
	_ping.forget_peer(PEER)
	assert_eq(_jitter(PEER), 0.0)


func test_reset_clears_the_jitter() -> void:
	_round_trip(0, 50)
	_round_trip(1, 90)
	_ping.reset()
	assert_eq(_jitter(PEER), 0.0)


func test_net_reports_zero_jitter_for_an_unknown_peer() -> void:
	assert_eq(Net.peer_rtt_jitter_ms(UNKNOWN_PEER), 0.0)
