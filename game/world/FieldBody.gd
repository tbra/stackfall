class_name FieldBody
extends AnimatableBody3D
## Light base of game/field/Field.gd: the geometry members
## world code reads, plus virtual stubs (tilt) Field overrides with identical signatures. Lets MatchContext
## and the specials name the field without compiling the whole Field scene closure.

@export var map_def: MapDef = preload("res://config/match/maps/round.tres")

## a drained batch applied these cells as holes (opened
## only; closing a hole needs no reaction). Emitted on host and client alike;
## game/blocks/HoleDissolver.gd ignores it off the host.
signal hole_cells_applied(opened: PackedInt32Array)
## A body the kill plane (spec 1.7) found below the disc edge; Field emits it,
## BlockRegistry removes the block on the host.
signal body_fell(body: Node3D)

## Layer constants. Everything else lives on layer 1. Beacon
## collision sits on its own bit so blocks (mask includes it) rest on beacons
## while placement/ghost queries (PLACEMENT_QUERY_MASK) never see them.
const BEACON_COLLISION_LAYER: int = 1 << 1
const PLACEMENT_QUERY_MASK: int = 1


func map_definition() -> MapDef:
	return map_def


## World Y of the disk pivot. Not the surface under a point once the disk is
## tilted: use surface_height_at().
func surface_y() -> float:
	return global_transform.origin.y


## World Y of the disk's top plane (local y = 0) on the vertical line through
## `world`'s XZ, for the live pose. A plane value: it ignores holes, blocks and
## the rim, so callers that need "over the disk" check disk_local_from_world().
func surface_height_at(world: Vector3) -> float:
	var n: Vector3 = global_transform.basis.y.normalized()
	var o: Vector3 = global_transform.origin
	return surface_y() - (n.x * (world.x - o.x) + n.z * (world.z - o.z)) / n.y


## World point -> disk-local (x, z), the convention CellGrid documents. This
## and world_from_disk_local() are the only two functions that change when the
## disk tilts.
func disk_local_from_world(world: Vector3) -> Vector2:
	var local: Vector3 = to_local(world)
	return Vector2(local.x, local.z)


## Disk-local (x, z) plus a height above the disk surface -> world point.
func world_from_disk_local(local: Vector2, height: float) -> Vector3:
	return to_global(Vector3(local.x, height, local.y))


# --- virtual stubs (Field overrides each with the same signature) ---------------

func tilt_vector() -> Vector2:
	return Vector2.ZERO


func apply_tilt_impulse(_direction: Vector2, _magnitude: float) -> void:
	pass


func apply_replicated_pose(_offset: Vector3, _tilt: Quaternion) -> void:
	pass


func grid() -> CellGrid:
	return null


func is_hole_cell(_index: int) -> bool:
	return false


func applied_hole_count() -> int:
	return 0


func set_tilt_enabled(_on: bool) -> void:
	pass


func set_physical_balance_enabled(_on: bool) -> void:
	pass
