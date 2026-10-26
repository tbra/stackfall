class_name GhostOverlapProbe
extends RefCounted
## Test support: whether a held plain piece, at the pose its ghost shows, would overlap a placed
## block. The same boxes the host tests a release with (BlockFactory.overlap_probe_*), asked of the
## physics space directly so a test needs no read of the controller's own clearance state.


static func overlaps_placed_block(world: World3D, ghost: GhostPreview) -> bool:
	var shape: BlockShape = ghost.get_shape()
	if shape == null or world == null:
		return false
	var centers: Array[Vector3] = BlockFactory.overlap_probe_centers(shape, ghost.tuning, &"")
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE * BlockFactory.overlap_probe_size(ghost.tuning, &"")
	var pose: Transform3D = ghost.global_transform
	for local_center: Vector3 in centers:
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		params.shape = box
		params.transform = Transform3D(pose.basis, pose.origin + pose.basis * local_center)
		params.collide_with_bodies = true
		params.collide_with_areas = false
		params.collision_mask = Field.PLACEMENT_QUERY_MASK
		for hit: Dictionary in world.direct_space_state.intersect_shape(params, ghost.ghost_tuning.collision_probe_max_bodies):
			if hit.get("collider") is RigidBody3D:
				return true
	return false
