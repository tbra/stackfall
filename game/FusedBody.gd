class_name FusedBody
extends Block
## Glue fusion (docs/GLUE_FUSION_PLAN.md WP0): one RigidBody3D carrying several
## glued cubes as members. WP0 is interface stubs only: every method is a no-op
## or returns a default; behaviour lands in WP1+.

var members: Array[Block] = []
## instance id (int) -> true; non-empty = disc-anchored.
var anchored_members: Dictionary = {}


func is_disc_anchored() -> bool:
	return false


func member_shapes(_member: Block) -> Array[CollisionShape3D]:
	return []


func members_in_sphere(_center: Vector3, _radius: float) -> Array[Block]:
	return []


func owner_slot_at(_world_point: Vector3) -> int:
	return -1


func sync_followers() -> void:
	pass


func remove_member(_member: Block, _reason: StringName) -> void:
	pass


func remove_all_members(_reason: StringName) -> void:
	pass
