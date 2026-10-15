class_name BlockSpawner
## Projectile spawning module for continuous effects (Volcano, Stackfall).
##
## Wraps Match.spawn_special_projectile(): host only, no feed/rules check, not
## counted as a placement (blocks_placed is untouched), owner-coloured, and
## refused once the blocks root holds `cap` children (same convention as
## StackfallRain's body cap).
##
## Depends on: MatchContext, Block, BlockShape


## Spawns `shape` at `world_origin` with `basis` and launch `velocity`.
## Returns the Block, or null (client, cap reached, bad input, not in live play).
static func spawn(shape: BlockShape, world_origin: Vector3, basis: Basis, owner_slot: int, velocity: Vector3, cap: int) -> Block:
	if shape == null or not world_origin.is_finite() or not velocity.is_finite():
		return null
	var ctx: MatchContext = MatchContext.current()
	if not ctx.has_authority():
		return null
	var parent: Node3D = ctx.blocks_parent()
	if parent == null or parent.get_child_count() >= maxi(cap, 1):
		return null
	return ctx.spawn_special_projectile(shape, world_origin, basis, owner_slot, velocity, null, null) as Block
