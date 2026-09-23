class_name PhysicsCallDriver
extends Node
## A live node the engine actually dispatches _physics_process() on, so a
## direct-call test can get a write into a genuine physics step.
##
## Needed by anything that writes into an AnimatableBody3D/RigidBody3D with
## `sync_to_physics = true` (game/Field.gd's own set_tilt_enabled() DECISION
## documents this for the disk): once that flag is on, Godot's kinematic body
## only accepts transform writes made through an actual physics step, and
## calling the write as a bare synchronous test call silently reverts it to
## the last physics-synced transform -- exactly the failure mode that would
## make a test compare two untouched (identity) transforms and pass for the
## wrong reason.
##
## Shared (Bontago-1en.27 review NIT) between tests/unit/test_field_tilt.gd
## (driving Field.apply_replicated_pose()/clear_match_state() directly) and
## tests/unit/test_snapshot_sync.gd (driving a whole client_tick() through the
## same real physics step). Both previously carried their own identical inner
## class.
var callable: Callable = Callable()
## Fires once, not every physics frame this driver lives -- a test that drives
## more than one call across separate driver instances must not have an
## earlier driver, still alive and only autofreed at test teardown, keep
## re-firing its own callable underneath a later assertion.
var _fired: bool = false


func _physics_process(_delta: float) -> void:
	if not _fired and callable.is_valid():
		_fired = true
		callable.call()
