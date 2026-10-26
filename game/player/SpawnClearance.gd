class_name SpawnClearance
extends RefCounted
## Keeps the held ghost clear of placed blocks: raises the next ghost above the piece just
## placed once that piece has settled, lifts a pose before release and undoes the lift on a
## refusal, decays the raise back to the player's hover, and carries the first piece's home
## raise. Ticked synchronously from PlayerController, never a node. Stub: every call is a no-op
## until PlayerController's machine moves here.

var _ghost: GhostPreview
var _overlaps: Callable
var _camera: CameraRig
var _tuning: GhostTuning
var _physics: PhysicsTuning
var _hover_ceiling: Callable


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


## The surface hit the ghost is posed from (PlayerController's last hit point and normal).
func set_surface(_point: Vector3, _normal: Vector3) -> void:
	pass


## A placement request was sent.
func begin_pending() -> void:
	pass


## The host issued the piece that follows the pending placement.
func mark_fed() -> void:
	pass


## The placement was refused or relocated away from the cursor: stop waiting.
func cancel_pending() -> void:
	pass


## One physics-synced frame (call after the ghost pose update): resolve a pending spawn
## (waiting for the overlapped block to settle when `wait_for_settle`), then decay the raise.
func step(_delta: float, _wait_for_settle: bool = false) -> void:
	pass


## Lifts the ghost just clear of every placed block before a release is sent.
func lift_for_release() -> void:
	pass


## The release was refused: take its lift back off.
func undo_release_lift() -> void:
	pass


## The player took over the hover height: the remaining raise is theirs.
func absorb() -> void:
	pass


## Raises the first piece until it clears the home beacon: `clear_height_above_disc` is an
## absolute height above the disc (GhostTuning.home_spawn_clear_hover), not a hover offset;
## the raise is that minus the base hover height and the current hover offset. Replaces any
## earlier home raise.
func seed_home(_clear_height_above_disc: float) -> void:
	pass


## Total of the spawn, release and home raises currently inside the ghost's hover offset.
func raise_total() -> float:
	return 0.0
