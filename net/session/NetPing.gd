class_name NetPing
extends RefCounted
## Host-side ping of the Net autoload. The host stamps each ping with its own
## clock and checks the echo against what it sent: a client-sent timestamp is
## never trusted (negative or huge values clamp to [0, ping_rtt_max_ms], an echo
## older than the last ping sent to that peer is dropped), and each peer's pongs
## pass the shared flood gate. Sends and the roster are Net's: it supplies the
## two Callables below and listens to ping_changed.

## Peer `peer_id` has a new averaged round trip, in ms (Net writes it to the roster
## and reports it to the peer).
signal ping_changed(peer_id: int, ms: float)

const MS_PER_S: float = 1000.0
## `_last_tick_ms` before the first tick: no ping is outstanding.
const NEVER_MS: int = -1
## Lowest ping_hz honoured, so a zero rate cannot divide by zero.
const MIN_PING_HZ: float = 0.001


class Seams extends RefCounted:
	## () -> Array : the peer ids to ping now. Unset means none.
	var targets: Callable = Callable()
	## (peer_id: int, sent_at_ms: int) -> void : one ping send.
	var send_ping: Callable = Callable()


var _config: NetConfig = null
var _flood: PeerFloodGate = null
var _seams: NetPing.Seams = null
## peer_id -> RTT samples (ms), at most config.ping_history.
var _samples: Dictionary = {}
## peer_id -> the sent_at_ms of the last ping sent to it.
var _last_sent_ms: Dictionary = {}
var _last_tick_ms: int = NEVER_MS


func _init(config: NetConfig, flood: PeerFloodGate, seams: NetPing.Seams) -> void:
	_config = config
	_flood = flood
	_seams = seams


## Sends a ping to every target once per 1 / ping_hz seconds.
func tick(now_ms: int) -> void:
	var interval_ms: int = roundi(MS_PER_S / maxf(_config.ping_hz, MIN_PING_HZ))
	if _last_tick_ms != NEVER_MS and now_ms - _last_tick_ms < interval_ms:
		return
	_last_tick_ms = now_ms
	if not _seams.targets.is_valid():
		return
	for peer_id: int in _seams.targets.call() as Array:
		_last_sent_ms[peer_id] = now_ms
		if _seams.send_ping.is_valid():
			_seams.send_ping.call(peer_id, now_ms)


## A pong from `sender` echoing `sent_at_ms`: flood-gated, stale echoes dropped,
## rtt clamped to [0, ping_rtt_max_ms], averaged over ping_history samples.
func on_pong(sender: int, sent_at_ms: int, now_ms: int) -> void:
	if not _flood.allow(sender, FloodLimits.INTENT_PONG, float(now_ms) / MS_PER_S):
		return
	var expected: int = int(_last_sent_ms.get(sender, _last_tick_ms))
	if expected != NEVER_MS and sent_at_ms < expected:
		return
	var rtt: float = clampf(float(now_ms - sent_at_ms), 0.0, float(_config.ping_rtt_max_ms))
	var samples: Array = _samples.get(sender, [])
	samples.append(rtt)
	while samples.size() > _config.ping_history:
		samples.pop_front()
	_samples[sender] = samples
	ping_changed.emit(sender, _average_ms(sender))


## Averaged RTT in ms for `peer_id`, 0.0 when it has no sample.
func _average_ms(peer_id: int) -> float:
	var samples: Array = _samples.get(peer_id, [])
	if samples.is_empty():
		return 0.0
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	return total / samples.size()


## Mean absolute deviation of `peer_id`'s kept RTT samples in ms; 0.0 with fewer than two.
func jitter_ms(peer_id: int) -> float:
	var samples: Array = _samples.get(peer_id, [])
	if samples.size() < 2:
		return 0.0
	var mean: float = _average_ms(peer_id)
	var total: float = 0.0
	for sample: float in samples:
		total += absf(sample - mean)
	return total / samples.size()


## A peer left: its samples and last ping go with it.
func forget_peer(peer_id: int) -> void:
	_samples.erase(peer_id)
	_last_sent_ms.erase(peer_id)


## Session end.
func reset() -> void:
	_samples.clear()
	_last_sent_ms.clear()
	_last_tick_ms = NEVER_MS
