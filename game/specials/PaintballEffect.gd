class_name PaintballEffect
extends SpecialEffect
## The thrown gift is the host-simulated glob. Its impact/fuse splashes a
## bounded sphere of real block colliders and converts each by net ID.

@export_range(0.5, 20.0, 0.1) var splash_radius_m: float = 3.5


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not Match._is_host() or Match.state() != Match.State.PLAYING:
		return
	if block.owner_slot < 0 or block.owner_slot >= Match.slot_count():
		return
	var hit_bodies: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		block.get_world_3d().direct_space_state,
		block.global_position,
		splash_radius_m,
		[block.get_rid()]
	)
	for body: RigidBody3D in hit_bodies:
		var target: Block = body as Block
		if target != null:
			Match.convert_block_owner(target, block.owner_slot)
