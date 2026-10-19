class_name DiskPoseSmoother
extends RefCounted
## Client-side presentation of the host's disk pose (spec 2.6 "Disk state:
## tilt quaternion and position offset, sent every snapshot").
##
## A 2-sample bracket (oldest, newest) kept the same way Interpolator.Track
## keeps one per body, sampled at the Interpolator's render time so the disc
## moves on the same render clock bodies do. Not folded into Interpolator
## itself: it buffers per net_id through a BlockRegistry-backed "is this id
## spawned yet?" filter (net/Interpolator.gd's set_known_id_filter()) that the
## disk -- one pose, no net_id, never absent -- does not need and should not be
## made to fake one for. -1 means "no sample yet".
##
## Convergence state for the pose is the scalar (there is only ever one disk)
## equivalent of Interpolator.Track's error_position/error_rotation/
## last_position/last_rotation/was_clamped fields: leaving a held/extrapolated
## pose is the one place a jump can appear, so that is the one place an offset
## is seeded, and it decays everywhere else. Without it a snapshot that broke a
## stall at a materially different tilt would snap the mirrored disc straight
## there.
##
## DECISION: reuses NetConfig.max_extrapolation_ms rather than adding a second
## tunable. The disk rides the same NetConfig resource and the same render clock
## every synced body does; a second knob for the same "how late is late"
## question would let the disk and the bodies disagree about it for no reason a
## player could ever perceive.

## Below this squared length (m^2) the convergence offset is treated as spent
## and snapped to zero, so decay() goes back to its steady-state early return.
const NEGLIGIBLE_OFFSET_SQUARED: float = 1e-12

var _config: NetConfig = null

var _prev_time_ms: int = -1
var _prev_position: Vector3 = Vector3.ZERO
var _prev_rotation: Quaternion = Quaternion.IDENTITY
var _next_time_ms: int = -1
var _next_position: Vector3 = Vector3.ZERO
var _next_rotation: Quaternion = Quaternion.IDENTITY

var _error_position: Vector3 = Vector3.ZERO
var _error_rotation: Quaternion = Quaternion.IDENTITY
var _last_position: Vector3 = Vector3.ZERO
var _last_rotation: Quaternion = Quaternion.IDENTITY
var _has_last: bool = false
var _was_clamped: bool = false


func _init(net_config: NetConfig) -> void:
	_config = net_config


## Forgets every sample and the convergence offset (match start and end).
func reset() -> void:
	_prev_time_ms = -1
	_next_time_ms = -1
	_error_position = Vector3.ZERO
	_error_rotation = Quaternion.IDENTITY
	_has_last = false
	_was_clamped = false


## Buffers one decoded disk sample as the (prev, next) bracket pose_at() needs.
## A late or duplicate host_time_ms is dropped rather than reordering the
## bracket, the same rule Interpolator.push_sample() applies per body.
func push_sample(host_time_ms: int, position: Vector3, rotation: Quaternion) -> void:
	if host_time_ms <= _next_time_ms:
		return
	_prev_time_ms = _next_time_ms
	_prev_position = _next_position
	_prev_rotation = _next_rotation
	_next_time_ms = host_time_ms
	_next_position = position
	_next_rotation = rotation


## {"ok": bool, "position": Vector3, "rotation": Quaternion} for the disk at
## `render_ms` -- lerp/slerp between the buffered bracket the same way
## Interpolator.sample_at_render_time() blends a body's two bracketing samples,
## extrapolating past the newest sample for at most
## config.max_extrapolation_ms and then holding, with a convergence offset
## seeded the moment a hold/extrapolation cap ends so the resumed pose eases
## back in step rather than snapping (the disk's own spring is irrelevant on a
## client: once apply_replicated_pose() mirrors the disc the spring never runs,
## so nothing else smooths a stall). `ok` is false until the first sample.
func pose_at(render_ms: float) -> Dictionary:
	if _next_time_ms < 0:
		return {"ok": false, "position": Vector3.ZERO, "rotation": Quaternion.IDENTITY}

	# With only one sample ever buffered there is no "oldest" distinct from
	# "newest" yet; treat the lone sample as both, the same degenerate case
	# Interpolator's own single-sample buffer collapses to.
	var has_prev: bool = _prev_time_ms >= 0
	var oldest_time_ms: int = _prev_time_ms if has_prev else _next_time_ms
	var oldest_position: Vector3 = _prev_position if has_prev else _next_position
	var oldest_rotation: Quaternion = _prev_rotation if has_prev else _next_rotation

	var raw_position: Vector3 = _next_position
	var raw_rotation: Quaternion = _next_rotation
	var clamped: bool = false

	if render_ms <= float(oldest_time_ms):
		raw_position = oldest_position
		raw_rotation = oldest_rotation
	elif render_ms >= float(_next_time_ms):
		var ahead_ms: float = render_ms - float(_next_time_ms)
		clamped = ahead_ms > _config.max_extrapolation_ms
		var extrapolated: Dictionary = _extrapolate(has_prev, ahead_ms)
		raw_position = extrapolated["position"] as Vector3
		raw_rotation = extrapolated["rotation"] as Quaternion
	else:
		var span_ms: float = float(_next_time_ms - oldest_time_ms)
		var t: float = clampf((render_ms - float(oldest_time_ms)) / span_ms, 0.0, 1.0)
		raw_position = oldest_position.lerp(_next_position, t)
		raw_rotation = oldest_rotation.slerp(_next_rotation, t)

	# Leaving the hold/extrapolation cap is the one place a jump can appear, so
	# that is the one place an offset is seeded; everywhere else the raw pose
	# is continuous in render time and the offset only decays (decay(), called
	# once per client tick).
	if _was_clamped and not clamped and _has_last:
		_error_position = _last_position - raw_position
		_error_rotation = (_last_rotation * raw_rotation.inverse()).normalized()
	_was_clamped = clamped

	_last_position = raw_position + _error_position
	_last_rotation = (_error_rotation * raw_rotation).normalized()
	_has_last = true
	return {"ok": true, "position": _last_position, "rotation": _last_rotation}


## Relaxes the convergence offset toward zero with a time constant of
## config.max_extrapolation_ms, the same decay Interpolator._decay_errors()
## runs per body, so the disk catches up over roughly the same window the
## hold froze it for. Exponential, so it is frame-rate independent and never
## overshoots. Called once per client tick, unconditionally -- a no-op while
## the offset is already zero, which is the steady-state case.
func decay(delta_ms: float) -> void:
	if _error_position == Vector3.ZERO and _error_rotation == Quaternion.IDENTITY:
		return
	var tau_ms: float = maxf(_config.max_extrapolation_ms, 1.0)
	var keep: float = exp(-delta_ms / tau_ms)
	_error_position *= keep
	_error_rotation = Quaternion.IDENTITY.slerp(_error_rotation, keep).normalized()
	if _error_position.length_squared() < NEGLIGIBLE_OFFSET_SQUARED:
		_error_position = Vector3.ZERO


## Past the newest sample: continues the (prev, next) segment's velocity for at
## most config.max_extrapolation_ms, then holds. `ahead_ms` is the *uncapped*
## time past the newest sample (the caller uses it to decide `clamped` too);
## this clamps it internally so the hold is exact, same as
## Interpolator._extrapolate(): clamping the elapsed time rather than the
## result is what makes the hold exact.
func _extrapolate(has_prev: bool, ahead_ms: float) -> Dictionary:
	var capped_ahead_ms: float = clampf(ahead_ms, 0.0, _config.max_extrapolation_ms)
	if not has_prev or capped_ahead_ms <= 0.0:
		return {"position": _next_position, "rotation": _next_rotation}
	var span_ms: float = float(_next_time_ms - _prev_time_ms)
	if span_ms <= 0.0:
		return {"position": _next_position, "rotation": _next_rotation}
	var t: float = capped_ahead_ms / span_ms
	var position: Vector3 = _next_position + (_next_position - _prev_position) * t
	var rotation: Quaternion = _prev_rotation.slerp(_next_rotation, 1.0 + t).normalized()
	return {"position": position, "rotation": rotation}
