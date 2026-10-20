extends GutTest
## NetPing: the host never trusts a client-sent timestamp. Driven on a synthetic
## millisecond clock: tick() sends the due pings, on_pong() takes the echo.

const PEER: int = 2
const OTHER_PEER: int = 3
const FIRST_PING_MS: int = 100000
const HONEST_RTT_MS: int = 50
const SECOND_RTT_MS: int = 70
const FLOOD_RTT_MS: int = 90
const FLOOD_CALLS: int = 60
const HONEST_PONGS: int = 20
const SPIKE_RTT_MS: int = 200
const BASE_RTT_MS: int = 100
const MS_PER_S: int = 1000
const HUGE_MS: int = 4611686018427387904
const INT32_MIN_MS: int = -2147483648

var _config: NetConfig
var _ping: NetPing
## Every ping_changed the host published, as [peer_id, ms], in order.
var _changes: Array = []


func before_each() -> void:
	_config = (load("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
	_config.sanitize()
	var seams: NetPing.Seams = NetPing.Seams.new()
	seams.targets = func() -> Array: return [PEER, OTHER_PEER]
	seams.send_ping = func(_peer_id: int, _sent_at_ms: int) -> void: pass
	_changes.clear()
	_ping = NetPing.new(_config, PeerFloodGate.new(FloodLimits.from_config(_config)), seams)
	_ping.ping_changed.connect(func(peer_id: int, ms: float) -> void: _changes.append([peer_id, ms]))


## The latest ping published for `peer_id`, 0.0 when none was.
func _published(peer_id: int) -> float:
	for i: int in range(_changes.size() - 1, -1, -1):
		if int((_changes[i] as Array)[0]) == peer_id:
			return float((_changes[i] as Array)[1])
	return 0.0


func _publish_count(peer_id: int) -> int:
	return _changes.filter(func(change: Array) -> bool: return int(change[0]) == peer_id).size()


## One honest round trip: a ping goes out at `sent_ms`, the echo returns `rtt_ms` later.
func _round_trip(sent_ms: int, rtt_ms: int) -> void:
	_ping.tick(sent_ms)
	_ping.on_pong(PEER, sent_ms, sent_ms + rtt_ms)


func test_a_peer_with_no_sample_publishes_nothing() -> void:
	_ping.tick(FIRST_PING_MS)
	assert_eq(_changes.size(), 0)
	assert_eq(_published(PEER), 0.0)


func test_an_honest_echo_reports_its_round_trip() -> void:
	_round_trip(FIRST_PING_MS, HONEST_RTT_MS)
	assert_eq(_published(PEER), float(HONEST_RTT_MS))


func test_samples_are_averaged() -> void:
	_round_trip(FIRST_PING_MS, HONEST_RTT_MS)
	_round_trip(FIRST_PING_MS + MS_PER_S, SECOND_RTT_MS)
	assert_almost_eq(_published(PEER), float(HONEST_RTT_MS + SECOND_RTT_MS) / 2.0, 0.001)


func test_each_peer_has_its_own_average() -> void:
	_round_trip(FIRST_PING_MS, HONEST_RTT_MS)
	_ping.on_pong(OTHER_PEER, FIRST_PING_MS, FIRST_PING_MS + SECOND_RTT_MS)
	assert_eq(_published(PEER), float(HONEST_RTT_MS))
	assert_eq(_published(OTHER_PEER), float(SECOND_RTT_MS))


func test_a_negative_sent_at_leaves_the_ping_unchanged() -> void:
	_round_trip(FIRST_PING_MS, HONEST_RTT_MS)
	var now_ms: int = FIRST_PING_MS + MS_PER_S
	for bad: int in [-1, -MS_PER_S, INT32_MIN_MS, -HUGE_MS]:
		_ping.on_pong(PEER, bad, now_ms)
		assert_eq(_published(PEER), float(HONEST_RTT_MS), "sent_at %d" % bad)
		assert_eq(_publish_count(PEER), 1, "sent_at %d published nothing" % bad)


func test_a_huge_sent_at_never_pushes_the_ping_out_of_range() -> void:
	_round_trip(FIRST_PING_MS, HONEST_RTT_MS)
	_ping.on_pong(PEER, HUGE_MS, FIRST_PING_MS + MS_PER_S)
	_ping.on_pong(PEER, HUGE_MS, FIRST_PING_MS + 2 * MS_PER_S)
	var reported: float = _published(PEER)
	assert_gte(reported, 0.0, "never negative")
	assert_lte(reported, float(HONEST_RTT_MS), "a forged future stamp cannot raise the ping")


func test_an_echo_far_slower_than_the_cap_is_bounded_by_the_cap() -> void:
	# An echo that arrives long after its ping is a (clamped or dropped) sample, never a bigger one.
	_ping.tick(FIRST_PING_MS)
	_ping.on_pong(PEER, FIRST_PING_MS, FIRST_PING_MS + _config.ping_rtt_max_ms * 100)
	var reported: float = _published(PEER)
	assert_gte(reported, 0.0)
	assert_lte(reported, float(_config.ping_rtt_max_ms))


func test_a_stale_echo_is_ignored() -> void:
	_round_trip(FIRST_PING_MS, HONEST_RTT_MS)
	var second_ping_ms: int = FIRST_PING_MS + MS_PER_S
	_ping.tick(second_ping_ms)
	# The echo of the FIRST ping arriving after the second went out is older than the last ping sent.
	_ping.on_pong(PEER, FIRST_PING_MS, second_ping_ms + SPIKE_RTT_MS)
	assert_eq(_published(PEER), float(HONEST_RTT_MS), "the stale echo changed nothing")
	assert_eq(_publish_count(PEER), 1, "and published nothing")
	_ping.on_pong(PEER, second_ping_ms, second_ping_ms + SECOND_RTT_MS)
	assert_almost_eq(_published(PEER), float(HONEST_RTT_MS + SECOND_RTT_MS) / 2.0, 0.001, "the current echo counts")


func test_honest_pongs_at_the_ping_rate_are_never_clipped() -> void:
	var interval_ms: int = roundi(float(MS_PER_S) / _config.ping_hz)
	var window: int = _config.ping_history
	for i: int in HONEST_PONGS - 1:
		_round_trip(FIRST_PING_MS + i * interval_ms, BASE_RTT_MS)
	_round_trip(FIRST_PING_MS + (HONEST_PONGS - 1) * interval_ms, SPIKE_RTT_MS)
	var expected: float = float(BASE_RTT_MS * (window - 1) + SPIKE_RTT_MS) / float(window)
	assert_almost_eq(_published(PEER), expected, 0.001, "the last honest sample was taken")


func test_a_pong_flood_is_bounded_by_the_pong_bucket() -> void:
	var now_ms: int = FIRST_PING_MS + HONEST_RTT_MS
	_ping.tick(FIRST_PING_MS)
	for i: int in _config.flood_pong_burst:
		_ping.on_pong(PEER, FIRST_PING_MS, now_ms)
	assert_eq(_published(PEER), float(HONEST_RTT_MS))
	# Ten milliseconds later a flood of slower echoes: the bucket refilled a fraction of a token.
	for i: int in FLOOD_CALLS:
		_ping.on_pong(PEER, FIRST_PING_MS, now_ms + FLOOD_RTT_MS - HONEST_RTT_MS)
	assert_eq(_published(PEER), float(HONEST_RTT_MS), "the flooded samples were dropped")
	assert_eq(_publish_count(PEER), _config.flood_pong_burst, "one publish per accepted pong, none for the flood")


func test_one_peers_flood_does_not_block_another_peers_pong() -> void:
	_ping.tick(FIRST_PING_MS)
	for i: int in FLOOD_CALLS:
		_ping.on_pong(PEER, FIRST_PING_MS, FIRST_PING_MS + HONEST_RTT_MS)
	_ping.on_pong(OTHER_PEER, FIRST_PING_MS, FIRST_PING_MS + SECOND_RTT_MS)
	assert_eq(_published(OTHER_PEER), float(SECOND_RTT_MS))
