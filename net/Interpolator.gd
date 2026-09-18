class_name Interpolator
extends RefCounted
## Client-side snapshot buffering and playback (spec 3.4 "Client
## interpolation": render 100 ms behind the host, the delay adapting to
## measured jitter, interpolating between the two surrounding snapshots, and
## extrapolating for at most 100 ms when they are late).
##
## Owned by net/SnapshotSync.gd; it holds no nodes and reads no clock of its
## own — `now` and `delta` are passed in — so a unit test can feed it a
## scripted stream of samples with injected jitter and assert the output pose
## curve frame by frame.
##
## **The render clock.** There is no clock synchronisation RPC. The client
## keeps its own `render_time_ms` advancing at real time and nudges it toward
## `newest_host_time_ms - delay_ms` by at most
## NetConfig.clock_correction_rate of real time per second. That is stable
## under one-way delay (which it never has to measure), self-correcting after
## a stall, and invisible at 15% — a hard snap would make every tower jump.
##
## The target that clock chases is the host time *projected forward* by how
## long ago the newest snapshot arrived, not the raw newest host time: the raw
## value is a 30 Hz staircase, so chasing it directly would park the render
## clock half an interval further behind than asked and sawtooth by 33 ms.
## `advance()` accumulates that projection, `note_snapshot()` resets it, and
## `render_lag_ms()` is therefore exactly `delay_ms()` on a clean stream.
##
## **Unknown net_ids are dropped, not buffered.** An unreliable snapshot can
## overtake the reliable spawn RPC that introduces a body, so a sample may name
## a net_id the client has never seen. Buffering those would need an unbounded
## side table keyed by ids that may never arrive (a despawned body's id can
## appear in a snapshot already in flight). Dropping costs at most one snapshot
## interval — 33 ms — before the next one carries the body again, by which
## time the reliable spawn has certainly landed. See docs/M3a_PLAN.md.
##
## The "has this body spawned?" question belongs to SnapshotSync, which owns
## the BlockRegistry; it is injected as a Callable through
## set_known_id_filter() so this class stays tree-free and the unit test can
## script the answer.

## One buffered pose. A class rather than a Dictionary because the buffer is
## touched 30 times a second per body.
class Sample:
	var host_time_ms: int = 0
	var position: Vector3 = Vector3.ZERO
	var rotation: Quaternion = Quaternion.IDENTITY
	var sleeping: bool = false

## Sequence numbers are u16 on the wire, so "newer than" is a distance test
## inside this modulus rather than a plain comparison.
const SEQUENCE_MODULUS: int = 65536
## A sequence delta above this many steps is read as an old packet arriving
## late rather than a colossal gap.
const SEQUENCE_HALF_RANGE: int = 32768

var _config: NetConfig = null

## net_id (int) -> Array[Sample], oldest first.
var _buffers: Dictionary = {}

## Host time of the newest sample from any body, and how long ago (in ms of
## real time) the snapshot carrying it arrived.
var _newest_host_time_ms: int = 0
var _ms_since_newest: float = 0.0
var _has_stream: bool = false

var _render_time_ms: float = 0.0
var _delay_ms: float = 0.0
var _jitter_ms: float = 0.0

var _last_sequence: int = -1
var _last_arrival: float = 0.0
## One [arrival_time, sequence_steps_covered] row per accepted snapshot,
## trimmed to config.stats_window. The rows are the received count and their
## steps sum to the expected count, which is all loss_fraction() needs.
var _arrivals: Array[Array] = []

var _dropped_unknown: int = 0
var _known_id_filter: Callable = Callable()


func _init(net_config: NetConfig = null) -> void:
	_config = net_config if net_config != null else NetConfig.new()
	_delay_ms = _config.base_interp_delay_ms


## SnapshotSync injects the predicate that answers "has this net_id's reliable
## spawn arrived?". `filter` takes an int and returns bool. An unset filter
## treats every id as known, which is what the wire-level tests want.
func set_known_id_filter(filter: Callable) -> void:
	_known_id_filter = filter


## Adds a sample for `net_id`, keeping at most NetConfig.interp_buffer_samples
## per body and discarding one that is older than what is already buffered
## (a reordered packet). Returns false when it was rejected.
func push_sample(
	net_id: int, host_time_ms: int, position: Vector3, rotation: Quaternion, sleeping: bool
) -> bool:
	if not _is_known(net_id):
		_dropped_unknown += 1
		return false

	var buffer: Array = _buffers.get(net_id, []) as Array
	if not buffer.is_empty():
		var newest: Sample = buffer[buffer.size() - 1] as Sample
		# Equal timestamps are the same body appearing twice in one snapshot's
		# fragments; older ones are a reordered packet. Neither may disturb the
		# buffer, which sample_at_render_time() assumes is sorted.
		if host_time_ms <= newest.host_time_ms:
			return false

	var sample: Sample = Sample.new()
	sample.host_time_ms = host_time_ms
	sample.position = position
	sample.rotation = rotation
	sample.sleeping = sleeping
	buffer.append(sample)
	while buffer.size() > maxi(_config.interp_buffer_samples, 2):
		buffer.remove_at(0)
	_buffers[net_id] = buffer

	if not _has_stream or host_time_ms > _newest_host_time_ms:
		_newest_host_time_ms = host_time_ms
	if not _has_stream:
		_has_stream = true
		_render_time_ms = float(host_time_ms) - _delay_ms
	return true


## Notes that a snapshot with `sequence` arrived at local time `now`, which is
## what the jitter estimate and the loss measurement are built from. Call once
## per snapshot, not once per fragment.
func note_snapshot(sequence: int, host_time_ms: int, now: float) -> void:
	var steps: int = 1
	if _last_sequence >= 0:
		var delta_sequence: int = posmod(sequence - _last_sequence, SEQUENCE_MODULUS)
		if delta_sequence == 0 or delta_sequence >= SEQUENCE_HALF_RANGE:
			# A duplicate or a packet that arrived after a newer one. Neither is
			# a loss and neither is jitter; it is simply not this stream's next
			# sample, so nothing about the clock moves.
			return
		steps = delta_sequence

		var gap_ms: float = (now - _last_arrival) * 1000.0
		# DECISION (net/Interpolator.gd): the nominal interval is scaled by the
		# number of sequence steps the gap covers. A snapshot lost on the wire
		# doubles the inter-arrival time, and charging that to "jitter" would
		# make loss inflate the interpolation delay by 66 ms a packet — loss and
		# jitter are separate measurements and the delay must track only the
		# second. NetConfig owns both numbers; nothing here is a literal.
		var nominal_ms: float = 1000.0 / maxf(_config.snapshot_hz, 1.0) * float(steps)
		var deviation: float = absf(gap_ms - nominal_ms)
		var weight: float = clampf(_config.interp_delay_smoothing, 0.0, 1.0)
		_jitter_ms = lerpf(_jitter_ms, deviation, weight)
		_delay_ms = lerpf(_delay_ms, _target_delay_ms(), weight)

	_last_sequence = sequence
	_last_arrival = now
	_arrivals.append([now, steps])
	_trim_arrivals(now)

	if host_time_ms > _newest_host_time_ms or not _has_stream:
		_newest_host_time_ms = host_time_ms
	_ms_since_newest = 0.0
	if not _has_stream:
		_has_stream = true
		_render_time_ms = float(host_time_ms) - _delay_ms


## Advances the render clock by `delta` seconds and settles the adaptive delay.
func advance(delta: float) -> void:
	var delta_ms: float = delta * 1000.0
	_delay_ms = clampf(
		_delay_ms, _config.min_interp_delay_ms, _config.max_interp_delay_ms
	)
	if not _has_stream:
		return
	_ms_since_newest += delta_ms
	_render_time_ms += delta_ms

	var target_ms: float = float(_newest_host_time_ms) + _ms_since_newest - _delay_ms
	var error_ms: float = target_ms - _render_time_ms
	var budget_ms: float = maxf(_config.clock_correction_rate, 0.0) * delta_ms
	_render_time_ms += clampf(error_ms, -budget_ms, budget_ms)


## The pose to draw for `net_id` right now: interpolated between the two
## samples bracketing the render clock, extrapolated from the last two for at
## most NetConfig.max_extrapolation_ms past the newest, then held. `ok` is
## false when the body has no usable samples, and the caller must then leave
## the body where it is rather than snapping it to the origin.
func sample_at_render_time(net_id: int) -> Dictionary:
	var miss: Dictionary = {
		"ok": false, "position": Vector3.ZERO, "rotation": Quaternion.IDENTITY
	}
	var buffer: Array = _buffers.get(net_id, []) as Array
	if buffer.is_empty():
		return miss

	var newest: Sample = buffer[buffer.size() - 1] as Sample
	var oldest: Sample = buffer[0] as Sample

	if _render_time_ms <= float(oldest.host_time_ms):
		return _pose(oldest.position, oldest.rotation)

	if _render_time_ms >= float(newest.host_time_ms):
		return _extrapolate(buffer, newest)

	for index: int in range(buffer.size() - 1):
		var a: Sample = buffer[index] as Sample
		var b: Sample = buffer[index + 1] as Sample
		if _render_time_ms < float(b.host_time_ms):
			var span_ms: float = float(b.host_time_ms - a.host_time_ms)
			if span_ms <= 0.0:
				return _pose(b.position, b.rotation)
			var t: float = clampf((_render_time_ms - float(a.host_time_ms)) / span_ms, 0.0, 1.0)
			return _pose(a.position.lerp(b.position, t), a.rotation.slerp(b.rotation, t))
	return _pose(newest.position, newest.rotation)


## net_ids with at least one buffered sample.
func tracked_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for key: Variant in _buffers.keys():
		ids.append(int(key))
	return ids


## Drops every sample for a body the host despawned.
func forget(net_id: int) -> void:
	_buffers.erase(net_id)


func clear() -> void:
	_buffers.clear()
	_arrivals.clear()
	_newest_host_time_ms = 0
	_ms_since_newest = 0.0
	_has_stream = false
	_render_time_ms = 0.0
	_delay_ms = _config.base_interp_delay_ms
	_jitter_ms = 0.0
	_last_sequence = -1
	_last_arrival = 0.0
	_dropped_unknown = 0


## The delay currently applied, in milliseconds (see the class docs).
func delay_ms() -> float:
	return clampf(_delay_ms, _config.min_interp_delay_ms, _config.max_interp_delay_ms)


## Smoothed absolute deviation of inter-arrival time from the nominal snapshot
## interval, in milliseconds. This is the "measured jitter" the delay tracks.
func jitter_ms() -> float:
	return _jitter_ms


## Fraction of snapshots missing from the sequence, 0..1, over the recent
## window. Reported, never acted on: a lossy link must change the delay, not
## the simulation.
func loss_fraction() -> float:
	var expected: int = 0
	for row: Array in _arrivals:
		expected += int(row[1])
	if expected <= 0:
		return 0.0
	return clampf(1.0 - float(_arrivals.size()) / float(expected), 0.0, 1.0)


## Samples currently held for `net_id`, for tests and the debug overlay.
func buffered_count(net_id: int) -> int:
	return (_buffers.get(net_id, []) as Array).size()


## Snapshot samples that named a net_id the client has not seen spawn, since
## the last clear(). A number that keeps climbing means spawn replication is
## broken, so the harness asserts it stays bounded.
func dropped_unknown_count() -> int:
	return _dropped_unknown


## The host time the client is currently drawing, in milliseconds. Exposed for
## tests and the debug overlay; gameplay never reads it.
func render_time_ms() -> float:
	return _render_time_ms


## How far behind the host the render clock actually sits right now, in
## milliseconds, against the host clock projected forward from the newest
## snapshot. On a clean stream this equals delay_ms().
func render_lag_ms() -> float:
	if not _has_stream:
		return 0.0
	return float(_newest_host_time_ms) + _ms_since_newest - _render_time_ms


## True once any sample has been accepted, so a caller can tell "nothing has
## arrived yet" from "the body is at the origin".
func has_stream() -> bool:
	return _has_stream


func _target_delay_ms() -> float:
	return clampf(
		_config.base_interp_delay_ms + _config.jitter_multiplier * _jitter_ms,
		_config.min_interp_delay_ms,
		_config.max_interp_delay_ms
	)


func _is_known(net_id: int) -> bool:
	if not _known_id_filter.is_valid():
		return true
	return bool(_known_id_filter.call(net_id))


func _trim_arrivals(now: float) -> void:
	var window: float = maxf(_config.stats_window, 0.1)
	while not _arrivals.is_empty() and now - float(_arrivals[0][0]) > window:
		_arrivals.remove_at(0)


func _pose(position: Vector3, rotation: Quaternion) -> Dictionary:
	return {"ok": true, "position": position, "rotation": rotation}


## Past the newest sample: continue the last segment's velocity for at most
## NetConfig.max_extrapolation_ms, then hold. Clamping the elapsed time rather
## than the result is what makes the hold exact — the pose simply stops
## advancing instead of drifting, and there is no snap when it stops.
func _extrapolate(buffer: Array, newest: Sample) -> Dictionary:
	var ahead_ms: float = clampf(
		_render_time_ms - float(newest.host_time_ms), 0.0, _config.max_extrapolation_ms
	)
	if buffer.size() < 2 or newest.sleeping or ahead_ms <= 0.0:
		return _pose(newest.position, newest.rotation)

	var previous: Sample = buffer[buffer.size() - 2] as Sample
	var span_ms: float = float(newest.host_time_ms - previous.host_time_ms)
	if span_ms <= 0.0:
		return _pose(newest.position, newest.rotation)

	var t: float = ahead_ms / span_ms
	var position: Vector3 = newest.position + (newest.position - previous.position) * t
	var rotation: Quaternion = previous.rotation.slerp(newest.rotation, 1.0 + t).normalized()
	return _pose(position, rotation)
