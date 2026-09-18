class_name NetSim
extends RefCounted
## Application-level lag and packet-loss simulator (spec Part 4 M3: "a client
## with 100 ms of simulated lag and 2% packet loss sees smooth towers").
##
## `ENetConnection` has no netem, and wrapping the peer in a
## MultiplayerPeerExtension would let us drop packets *below* ENet's
## reliability layer — which would silently destroy reliable RPCs rather than
## simulate a lossy link. So the simulation lives one level up, in the two
## places that own their own traffic:
##   - net/SnapshotSync.gd runs every inbound snapshot packet through a NetSim
##     (these are unreliable, so dropping them is exactly right);
##   - autoload/Net.gd runs outbound intents and cursor updates through one,
##     delaying reliable traffic and dropping only the unreliable kind.
##
## Pure and clock-injected: `now` is passed in rather than read, so a unit test
## can push 1000 packets through a simulated 100 ms / 2% link and assert the
## delivery order and drop rate without waiting a second (CLAUDE.md: core/ has
## no scene-tree dependence).
##
## `lag_ms` is **one-way** added delay. Enabling 100 ms on a client alone makes
## that client see the world 100 ms later and its intents arrive 100 ms late,
## which is what the acceptance criterion describes.

## One queued payload: `deliver_at` is the simulated monotonic time (seconds)
## at which drain() may release it.
class _Entry:
	var payload: Variant
	var deliver_at: float


var _lag_ms: float = 0.0
var _jitter_ms: float = 0.0
var _loss: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _queue: Array[_Entry] = []
var _submitted_count: int = 0
var _dropped_count: int = 0


## `lag_ms` one-way delay, `jitter_ms` random +- spread on top of it, `loss`
## the fraction of droppable packets discarded (0..1). `rng_seed` >= 0 makes a
## run reproducible; -1 randomizes.
func _init(lag_ms: float = 0.0, jitter_ms: float = 0.0, loss: float = 0.0, rng_seed: int = -1) -> void:
	_lag_ms = maxf(lag_ms, 0.0)
	_jitter_ms = maxf(jitter_ms, 0.0)
	_loss = clampf(loss, 0.0, 1.0)
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


## Re-tunes a live simulator without dropping what is already queued.
func configure(lag_ms: float, jitter_ms: float, loss: float) -> void:
	_lag_ms = maxf(lag_ms, 0.0)
	_jitter_ms = maxf(jitter_ms, 0.0)
	_loss = clampf(loss, 0.0, 1.0)


## True when nothing is being delayed or dropped, so callers can skip the
## queue entirely on the common path.
func is_idle() -> bool:
	return _lag_ms <= 0.0 and _jitter_ms <= 0.0 and _loss <= 0.0


## Offers a payload to the link at time `now` (seconds, monotonic). Returns
## false when the simulator dropped it — only ever possible when
## `droppable` is true, which callers set for unreliable traffic and clear for
## reliable traffic. A kept packet becomes deliverable at now + lag + jitter.
func submit(payload: Variant, now: float, droppable: bool) -> bool:
	_submitted_count += 1
	if droppable and _loss > 0.0 and _rng.randf() < _loss:
		_dropped_count += 1
		return false
	var jitter: float = 0.0
	if _jitter_ms > 0.0:
		jitter = _rng.randf_range(-_jitter_ms, _jitter_ms)
	var delay_ms: float = maxf(_lag_ms + jitter, 0.0)
	var entry: _Entry = _Entry.new()
	entry.payload = payload
	entry.deliver_at = now + delay_ms / 1000.0
	_queue.append(entry)
	return true


## Everything whose delivery time has arrived, oldest first, removed from the
## queue. Order is preserved even when jitter would reorder it: a packet never
## overtakes one submitted earlier, because reordering is a separate failure
## mode from jitter and simulating it would make "never duplicated or lost"
## untestable.
func drain(now: float) -> Array:
	var result: Array = []
	while not _queue.is_empty() and _queue[0].deliver_at <= now:
		var entry: _Entry = _queue.pop_front()
		result.append(entry.payload)
	return result


## Payloads still waiting.
func pending_count() -> int:
	return _queue.size()


## Packets submitted since the last reset, for the debug overlay.
func submitted_count() -> int:
	return _submitted_count


## Packets dropped since the last reset, for the debug overlay.
func dropped_count() -> int:
	return _dropped_count


## Empties the queue and the counters.
func reset() -> void:
	_queue.clear()
	_submitted_count = 0
	_dropped_count = 0
