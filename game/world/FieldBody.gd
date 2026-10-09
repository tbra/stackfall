class_name FieldBody
extends AnimatableBody3D
## Light base of game/Field.gd (docs/AUTOLOAD_DECOUPLING_PLAN.md, S1b, D8): the geometry members
## world code reads, plus virtual stubs Field overrides with identical signatures. Lets MatchContext
## and the specials name the field without compiling the whole Field scene closure.

@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")


func map_definition() -> MapDef:
	return map_def


## World Y of the disk's top surface. 0.0 while the disk is flat and centered;
## from M4 the tilt makes this only an approximation and callers that care use
## world_from_disk_local() instead.
func surface_y() -> float:
	return global_transform.origin.y


## World point -> disk-local (x, z), the convention CellGrid documents. This
## and world_from_disk_local() are the only two functions that change when the
## disk starts tilting in M4.
func disk_local_from_world(world: Vector3) -> Vector2:
	var local: Vector3 = to_local(world)
	return Vector2(local.x, local.z)


## Disk-local (x, z) plus a height above the disk surface -> world point.
func world_from_disk_local(local: Vector2, height: float) -> Vector3:
	return to_global(Vector3(local.x, height, local.y))


# --- virtual stubs (Field overrides each with the same signature) ---------------

func grid() -> CellGrid:
	return null


func tilt_vector() -> Vector2:
	return Vector2.ZERO


func apply_tilt_impulse(_direction: Vector2, _magnitude: float) -> void:
	pass


func apply_replicated_pose(_offset: Vector3, _tilt: Quaternion) -> void:
	pass


func is_hole_cell(_index: int) -> bool:
	return false


func remove_fallen_block(_body: RigidBody3D) -> void:
	pass
