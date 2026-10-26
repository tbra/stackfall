class_name CatSession
extends RefCounted
## The one running Cat activation (host simulation or client replica) for a match.
## Stub revision: neutral until the cat package moves the Match cat code here.

var _match: MatchAutoload = null
var _parent: Node = null


## `parent` is where the cat body is added.
func setup(match_ref: MatchAutoload, parent: Node) -> void:
	_match = match_ref
	_parent = parent


## The running cat body, or null.
func active() -> RigidBody3D:
	return null


## Host: starts a cat for `owner_slot` at `position`; false when refused.
func start(_owner_slot: int, _position: Vector3, _effect: Resource) -> bool:
	return false


## Host: points the cat of `slot_id` at `point`; false when refused.
func set_target(_slot_id: int, _point: Vector3) -> bool:
	return false


## Client: starts the replica of activation `id`; false when refused.
func apply_replicated_start(_id: int, _slot_id: int, _position: Vector3, _duration: float) -> bool:
	return false


## Client: applies a snapshot of activation `id`.
func apply_replicated_state(
	_id: int, _position: Vector3, _velocity: Vector3, _point: Vector3, _remaining: float
) -> void:
	pass


## Ends activation `id`; a different id is a no-op.
func end(_id: int) -> void:
	pass


## Ends the active cat and restarts the activation serial.
func reset() -> void:
	pass
