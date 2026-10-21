class_name ImpactReplicator
extends RefCounted
## Impact replication for MatchNet's net_block_impacts RPC (wire format: core/net/ImpactWire.gd).
## Host: collect() folds each detected impact into the current batch window, flush() turns the
## window into one packet. Client: receive() validates a packet and queues its events, drain()
## returns the ones whose moment the interpolated view has reached. The clock is the caller's:
## `now_ms` is any monotonic millisecond clock, and the view time drain() takes is that clock
## minus the interpolation delay.

## The "per second" of impact_client_max_per_second, in milliseconds.
const RATE_WINDOW_MS: int = 1000
const MS_PER_S: float = 1000.0

var _config: NetConfig = null
var _bucket: TokenBucket = null
## Host: coalesce key -> strongest event this window, as {speed, position, time_ms}. Cleared on
## every flush, so it never holds more than one window.
var _pending: Dictionary = {}
## Client: [due_ms, speed, position] rows waiting for the view to reach them.
var _queue: Array[Array] = []
## Client: arrival time of each event accepted within the last second.
var _accepted_ms: Array[int] = []


## `bucket` is the host's NetConfig.impact_max_per_second limiter; MatchNet wires both.
func _init(config: NetConfig, bucket: TokenBucket) -> void:
	_config = config
	_bucket = bucket


## Host: folds one detected impact into the current window. Events with the same
## impact_coalesce_cell_m cell keep only the strongest; a non-finite or non-positive speed and a
## position outside the quantized volume are skipped on their own (the client would reject them,
## and they must not cost their neighbours anything).
func collect(speed: float, position: Vector3, now_ms: int) -> void:
	if not is_finite(speed) or speed <= 0.0:
		return
	if not ImpactWire.position_in_range(position, _config.pos_min_y, _config.pos_max_y):
		return
	var clamped: float = minf(speed, _config.impact_speed_max)
	var key: Vector3i = ImpactWire.coalesce_key(position, _config.impact_coalesce_cell_m)
	var existing: Variant = _pending.get(key)
	if existing != null:
		if float((existing as Dictionary)[ImpactWire.KEY_SPEED]) >= clamped:
			return
	elif _pending.size() >= ImpactWire.MAX_EVENTS:
		return
	_pending[key] = {
		ImpactWire.KEY_SPEED: clamped,
		ImpactWire.KEY_POSITION: position,
		ImpactWire.KEY_TIME_MS: now_ms,
	}


## Host: the current window as one batch (strongest first, at most impact_max_per_batch and what
## the per-second token bucket allows), then clears the window. Events over the cap are dropped,
## not carried: a late thud is worse than a missing one. Empty = nothing to send.
func flush(now_ms: int) -> PackedByteArray:
	if _pending.is_empty():
		return PackedByteArray()
	var pending: Array[Dictionary] = []
	for event: Variant in _pending.values():
		pending.append(event as Dictionary)
	_pending.clear()
	var allowed: int = 0
	var cap: int = _batch_cap()
	while allowed < mini(cap, pending.size()) and _bucket.take(
		float(now_ms) / MS_PER_S, cap, float(maxi(_config.impact_max_per_second, 1))
	):
		allowed += 1
	if allowed <= 0:
		return PackedByteArray()
	var chosen: Array[Dictionary] = ImpactWire.strongest(pending, allowed)
	for event: Dictionary in chosen:
		event[ImpactWire.KEY_AGE_MS] = now_ms - int(event[ImpactWire.KEY_TIME_MS])
	return ImpactWire.encode(chosen)


## Client: validates a batch and queues each event for the moment it happened (arrival minus its
## age). A malformed batch is refused whole (false); events past the client's per-second budget or
## the queue bound are dropped one by one.
func receive(packet: PackedByteArray, now_ms: int) -> bool:
	var events: Array[Dictionary] = ImpactWire.decode(
		packet, _config.impact_speed_max, _config.pos_min_y, _config.pos_max_y, _batch_cap()
	)
	if events.is_empty():
		return false
	var budget: int = _client_budget(now_ms)
	if events.size() > budget:
		events.resize(budget)
	var queue_cap: int = _config.impact_max_per_second + _config.impact_max_per_batch
	for event: Dictionary in events:
		_accepted_ms.append(now_ms)
		if _queue.size() < queue_cap:
			var due_ms: float = float(now_ms) - float(event[ImpactWire.KEY_AGE_MS])
			_queue.append([due_ms, event[ImpactWire.KEY_SPEED], event[ImpactWire.KEY_POSITION]])
	return true


## Client: the queued impacts whose moment `view_ms` has reached, in arrival order, as
## [speed, position] rows.
func drain(view_ms: float) -> Array[Array]:
	var due: Array[Array] = []
	var keep: Array[Array] = []
	for row: Array in _queue:
		if float(row[0]) <= view_ms:
			due.append([row[1], row[2]])
		else:
			keep.append(row)
	_queue = keep
	return due


## The per-batch bound both ends share: impact_max_per_batch, held to what one max_packet_bytes
## packet carries (sanitize() does the same; this guards a config that skipped it).
func _batch_cap() -> int:
	return mini(
		maxi(_config.impact_max_per_batch, 1), ImpactWire.max_events_for_payload(_config.max_packet_bytes)
	)


## How many more events the sliding one-second window (impact_client_max_per_second) lets
## through at `now_ms`.
func _client_budget(now_ms: int) -> int:
	while not _accepted_ms.is_empty() and now_ms - _accepted_ms[0] >= RATE_WINDOW_MS:
		_accepted_ms.pop_front()
	return maxi(_config.impact_client_max_per_second - _accepted_ms.size(), 0)
