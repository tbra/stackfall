class_name SpawnClearance
extends RefCounted
## Keeps the held ghost clear of placed blocks: raises the next ghost above the piece just
## placed once that piece has settled, lifts a pose before release and undoes the lift on a
## refusal, decays the raise back to the player's hover, and carries the first piece's home
## raise. Ticked synchronously from PlayerController, never a node.

## Floor for the time between two settle samples, so the speed bound never divides by zero.
const MIN_SAMPLE_DT: float = 0.0001

## One frame's observation of a frozen block, for the settled test.
class Sample extends RefCounted:
	var frame: int
	var position: Vector3
	var still: bool
	var elapsed: float

	func _init(frame_: int, position_: Vector3, still_: bool, elapsed_: float) -> void:
		frame = frame_
		position = position_
		still = still_
		elapsed = elapsed_


var _ghost: GhostPreview
var _overlaps: Callable
var _camera: CameraRig
var _tuning: GhostTuning
var _physics: PhysicsTuning
var _hover_ceiling: Callable
var _surface_point: Vector3 = Vector3.ZERO
var _surface_normal: Vector3 = Vector3.UP
## A placement request is waiting for the next ghost to be cleared.
var _pending: bool = false
## The previous piece's raise was already taken back for the pending spawn (once per placement).
var _waiting: bool = false
## The host issued the piece that follows the pending placement (a client can lag a round trip).
var _fed: bool = false
var _settle_elapsed: float = 0.0
var _settle_samples: Dictionary = {}
## How much of the ghost's manual_hover_offset is spawn-clearance raise (including the release
## lift) rather than the player's own hover input; taken back at the next spawn or decayed.
var _raise: float = 0.0
## Part of `_raise` added by the release-time lift; undone if the host refuses the release.
var _release_raise: float = 0.0
## The first piece's raise above the home beacon, tracked apart from the player's own hover.
var _home_raise: float = 0.0


## `overlaps`: Callable() -> Array[RigidBody3D], the placed bodies the ghost's release pose
## touches right now. `camera` may be null. `physics` supplies sleep_linear_threshold for the
## settled test of a frozen body. `hover_ceiling`: Callable() -> float, the highest
## manual_hover_offset the ghost may reach.
func _init(
	ghost: GhostPreview, overlaps: Callable, camera: CameraRig, tuning: GhostTuning,
	physics: PhysicsTuning, hover_ceiling: Callable
) -> void:
	_ghost = ghost
	_overlaps = overlaps
	_camera = camera
	_tuning = tuning
	_physics = physics
	_hover_ceiling = hover_ceiling


## The camera is wired after the controller is built; it may be null.
func set_camera(camera: CameraRig) -> void:
	_camera = camera


## The surface hit the ghost is posed from (PlayerController's last hit point and normal).
func set_surface(point: Vector3, normal: Vector3) -> void:
	_surface_point = point
	_surface_normal = normal


## A placement request was sent: restart the settle wait.
func begin_pending() -> void:
	_pending = true
	_settle_samples.clear()
	_waiting = false
	_settle_elapsed = 0.0
	_fed = false


## The host issued the piece that follows the pending placement.
func mark_fed() -> void:
	if _pending:
		_fed = true


## The placement was refused or relocated away from the cursor: stop waiting.
func cancel_pending() -> void:
	_settle_samples.clear()
	_pending = false
	_waiting = false
	_fed = false


## One physics-synced frame (call after the ghost pose update): resolve a pending spawn
## (waiting for the overlapped block to settle when `wait_for_settle`), then decay the raise.
##
## The next piece is issued in the same call that spawns the dropped block, at the very same
## pose, so a one-shot overlap query would find the dropped block, still falling from where
## the ghost had been, and raise the new ghost by a whole block height that the decay would
## then sink back. So a block is not counted until it has settled: while the ghost overlaps an
## unsettled block the check waits, bounded by spawn_clearance_settle_timeout_s, and only then
## raises, by the minimal amount, if the ghost really is inside a settled block. The release
## lift and the host's own lift still count every block: they protect the real spawn.
## `wait_for_settle` is true in the real game; false resolves at once.
func step(delta: float, wait_for_settle: bool = false) -> void:
	_apply_pending(delta, wait_for_settle)
	_decay(delta)


## Lifts the ghost just clear of every placed block before a release is sent.
##
## The host spawns a released block exactly where the ghost stands and never checks it for
## overlap, so a pose that interpenetrates a placed block makes Jolt shove the older body
## away. The post-placement check looks once, before the previous block has settled, and a
## rotation is not swept at all, so every release re-checks the pose first. Shares
## spawn_clearance_enabled with the post-placement raise (the host's validation is
## unconditional).
func lift_for_release() -> void:
	_release_raise = 0.0
	if not _active():
		return
	var offset_before: float = _ghost.manual_hover_offset
	_raise_until_clear(true)
	_release_raise = _ghost.manual_hover_offset - offset_before


## The release was refused: take its lift back off.
func undo_release_lift() -> void:
	if _release_raise > 0.0:
		_ghost.manual_hover_offset = maxf(_ghost.manual_hover_offset - _release_raise, 0.0)
		_raise = maxf(_raise - _release_raise, 0.0)
	_release_raise = 0.0


## The player took over the hover height: the remaining raise is theirs.
func absorb() -> void:
	_raise = 0.0
	_home_raise = 0.0


## Raises the first piece until it clears the home beacon: `clear_height_above_disc` is an
## absolute height above the disc (GhostTuning.home_spawn_clear_hover), not a hover offset;
## the raise is that minus the base hover height and the current hover offset. Replaces any
## earlier home raise.
func seed_home(clear_height_above_disc: float) -> void:
	_take_back_home_raise()
	var raise: float = maxf(clear_height_above_disc - _physics.hover_height - _ghost.manual_hover_offset, 0.0)
	_ghost.manual_hover_offset += raise
	_home_raise = raise


func _active() -> bool:
	return _tuning.spawn_clearance_enabled and _ghost.get_shape() != null


func _refresh_pose() -> void:
	_ghost.update_placement(_surface_point, _surface_normal)


func _apply_pending(delta: float, wait_for_settle: bool) -> void:
	if not _pending:
		return
	if not _waiting:
		_waiting = true
		# The previous piece's raise comes off first, so a raise never compounds across drops.
		_take_back_raise()
	if not _active():
		cancel_pending()
		return
	_refresh_pose()
	_settle_elapsed += delta
	if wait_for_settle and _settle_elapsed < _tuning.spawn_clearance_settle_timeout_s and (
		not _fed or _overlaps_any_unsettled()
	):
		return
	cancel_pending()
	_raise_until_clear()


## Raises the ghost by the minimum amount that leaves it clear of every placed block; a no-op
## when it already is. Release lifts are limited only by the hover ceiling, not by
## spawn_clearance_max_raise: the settle wait keeps the ghost unraised until the previous block
## rests, so a release lift cannot lean on a carried-over raise to clear a tall tower.
func _raise_until_clear(for_release: bool = false) -> void:
	if _overlapping().is_empty():
		return
	var base_offset: float = _ghost.manual_hover_offset
	var cap: float = maxf(float(_hover_ceiling.call()) - base_offset, 0.0)
	if not for_release:
		cap = minf(_tuning.spawn_clearance_max_raise, cap)
	var raise_amount: float = ClearanceRaise.first_clear_raise(
			func(r: float) -> bool: return _overlaps_with_offset(base_offset + r),
			_tuning.spawn_clearance_step, cap, _tuning.spawn_clearance_bisect_steps, _tuning.spawn_clearance)
	if raise_amount == ClearanceRaise.NOT_CLEARED:
		raise_amount = cap
	_ghost.manual_hover_offset = base_offset + raise_amount
	_raise += raise_amount
	_refresh_pose()
	if _camera != null and raise_amount > 0.0:
		# One discontinuous re-target: ease the camera onto the raised ghost.
		_camera.begin_follow_transition()


## Whether the held shape would overlap a placed block with the given total hover offset;
## leaves the ghost (and its offset) exactly as it was.
func _overlaps_with_offset(offset: float) -> bool:
	var saved_offset: float = _ghost.manual_hover_offset
	_ghost.manual_hover_offset = offset
	_refresh_pose()
	var overlaps: bool = not _overlapping().is_empty()
	_ghost.manual_hover_offset = saved_offset
	_refresh_pose()
	return overlaps


## The raise decays back to the player's own hover once it is no longer needed: each frame,
## lower by spawn_clearance_decay_speed * delta if the ghost would still be clear at that lower
## pose. Stops the moment lowering would overlap again; costs nothing while no raise is active.
func _decay(delta: float) -> void:
	if _raise <= 0.0 or _ghost.get_shape() == null:
		return
	var step_size: float = minf(_tuning.spawn_clearance_decay_speed * delta, _raise)
	if step_size <= 0.0:
		return
	var lowered: float = maxf(_ghost.manual_hover_offset - step_size, 0.0)
	if _overlaps_with_offset(lowered):
		return
	_ghost.manual_hover_offset = lowered
	_raise -= step_size
	_refresh_pose()


## Removes the spawn-clearance share from the hover offset (back to the player's own hover).
func _take_back_raise() -> void:
	if _raise > 0.0:
		_ghost.manual_hover_offset = maxf(_ghost.manual_hover_offset - _raise, 0.0)
	_raise = 0.0
	_take_back_home_raise()


func _take_back_home_raise() -> void:
	if _home_raise > 0.0:
		_ghost.manual_hover_offset = maxf(_ghost.manual_hover_offset - _home_raise, 0.0)
	_home_raise = 0.0


func _overlapping() -> Array[RigidBody3D]:
	return _overlaps.call() as Array[RigidBody3D]


func _overlaps_any_unsettled() -> bool:
	for body: RigidBody3D in _overlapping():
		if not _is_settled_body(body):
			return true
	return false


## Whether a placed body has come to rest. On the physics authority that is Jolt's own sleep
## (or a static freeze: stable-block freeze, Freeze special); a client's mirrored blocks are
## always frozen kinematic, so there it is the replicated sleeping flag the snapshot drives
## into Block.is_contributing_visual().
func _is_settled_body(body: RigidBody3D) -> bool:
	var block: Block = body as Block
	if block == null:
		return body.sleeping
	if block.is_freeze_static():
		return true
	if block.freeze:
		return block.is_contributing_visual() or _frozen_body_is_still(block)
	return block.sleeping


## A client's mirrored block is frozen kinematic and is_contributing_visual() is only written
## when a BlockMesh exists, so it can stay false forever. DECISION: also treat a frozen block
## as settled once its replicated pose has moved no more than sleep_linear_threshold * elapsed
## since the previous process frame it was sampled on (position only, one entry per body; the
## first sample is "not settled").
func _frozen_body_is_still(block: Block) -> bool:
	var id: int = block.get_instance_id()
	var frame: int = Engine.get_process_frames()
	var prev: Sample = _settle_samples.get(id) as Sample
	if prev != null and prev.frame == frame:
		return prev.still
	var still: bool = false
	if prev != null:
		var dt: float = maxf(_settle_elapsed - prev.elapsed, MIN_SAMPLE_DT)
		still = block.global_position.distance_to(prev.position) <= _physics.sleep_linear_threshold * dt
	_settle_samples[id] = Sample.new(frame, block.global_position, still, _settle_elapsed)
	return still
