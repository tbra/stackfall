class_name ClientBlockMirror
extends RefCounted
## Client-side mirror of the host's block spawns and despawns: owns the set of
## net ids that have been spawned locally.
##
## STUB: signatures only; bodies are filled in by the M6 implementation.


## Applies a host spawn. Returns true when the block was spawned (false for a
## duplicate or malformed spawn).
func on_spawned(_net_id: int, _payload: Dictionary) -> bool:
	push_error("ClientBlockMirror.on_spawned: not implemented")
	return false


## Applies a host despawn for `net_id`; `reason` is the host's despawn reason.
func on_despawned(_net_id: int, _reason: int) -> void:
	push_error("ClientBlockMirror.on_despawned: not implemented")


## Reconciles the local blocks with the host's full roster. Returns true when
## the roster was well formed and applied.
func apply_roster(_roster: Array) -> bool:
	push_error("ClientBlockMirror.apply_roster: not implemented")
	return false


## True when `net_id` has been spawned locally and not despawned since.
func has_spawned(_net_id: int) -> bool:
	push_error("ClientBlockMirror.has_spawned: not implemented")
	return false
