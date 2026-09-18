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
## **Unknown net_ids are dropped, not buffered.** An unreliable snapshot can
## overtake the reliable spawn RPC that introduces a body, so a sample may name
## a net_id the client has never seen. Buffering those would need an unbounded
## side table keyed by ids that may never arrive (a despawned body's id can
## appear in a snapshot already in flight). Dropping costs at most one snapshot
## interval — 33 ms — before the next one carries the body again, by which
## time the reliable spawn has certainly landed. See docs/M3a_PLAN.md.

## One buffered pose. A class rather than a Dictionary because the buffer is
## touched 30 times a second per body.
class Sample:
	var host_time_ms: int = 0
	var position: Vector3 = Vector3.ZERO
	var rotation: Quaternion = Quaternion.IDENTITY
	var sleeping: bool = false

@warning_ignore_start("unused_parameter")


func _init(net_config: NetConfig = null) -> void:
	pass


## Adds a sample for `net_id`, keeping at most NetConfig.interp_buffer_samples
## per body and discarding one that is older than what is already buffered
## (a reordered packet). Returns false when it was rejected.
func push_sample(net_id: int, host_time_ms: int, position: Vector3, rotation: Quaternion, sleeping: bool) -> bool:
	return false


## Notes that a snapshot with `sequence` arrived at local time `now`, which is
## what the jitter estimate and the loss measurement are built from. Call once
## per snapshot, not once per fragment.
func note_snapshot(sequence: int, host_time_ms: int, now: float) -> void:
	pass


## Advances the render clock by `delta` seconds and settles the adaptive delay.
func advance(delta: float) -> void:
	pass


## The pose to draw for `net_id` right now: interpolated between the two
## samples bracketing the render clock, extrapolated from the last two for at
## most NetConfig.max_extrapolation_ms past the newest, then held. `ok` is
## false when the body has no usable samples, and the caller must then leave
## the body where it is rather than snapping it to the origin.
func sample_at_render_time(net_id: int) -> Dictionary:
	return {"ok": false, "position": Vector3.ZERO, "rotation": Quaternion.IDENTITY}


## net_ids with at least one buffered sample.
func tracked_ids() -> PackedInt32Array:
	return PackedInt32Array()


## Drops every sample for a body the host despawned.
func forget(net_id: int) -> void:
	pass


func clear() -> void:
	pass


## The delay currently applied, in milliseconds (see the class docs).
func delay_ms() -> float:
	return 0.0


## Smoothed absolute deviation of inter-arrival time from the nominal snapshot
## interval, in milliseconds. This is the "measured jitter" the delay tracks.
func jitter_ms() -> float:
	return 0.0


## Fraction of snapshots missing from the sequence, 0..1, over the recent
## window. Reported, never acted on: a lossy link must change the delay, not
## the simulation.
func loss_fraction() -> float:
	return 0.0


## Samples currently held for `net_id`, for tests and the debug overlay.
func buffered_count(net_id: int) -> int:
	return 0


## Snapshot samples that named a net_id the client has not seen spawn, since
## the last clear(). A number that keeps climbing means spawn replication is
## broken, so the harness asserts it stays bounded.
func dropped_unknown_count() -> int:
	return 0


@warning_ignore_restore("unused_parameter")
