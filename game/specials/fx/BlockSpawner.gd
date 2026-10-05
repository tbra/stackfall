class_name BlockSpawner
## Projectile spawning module for continuous effects (Volcano, Stackfall).
##
## `spawn` creates a new block at world position via Match's projectile path,
## respecting the active-body cap and not counting as a placement.
## Blocks use owner's colour, identity basis (no rotation), and the given shape.
##
## Depends on: Match, Block, BlockShape


## Spawns a projectile block of the given shape at world_origin with the given basis and velocity.
## Respects the active-body cap. Blocks are not counted as placements and use owner colour.
## Host only. Returns the spawned Block, or null if cap is reached.
static func spawn(shape: BlockShape, world_origin: Vector3, basis: Basis, owner_slot: int, velocity: Vector3, cap: int) -> Block:
	return null
