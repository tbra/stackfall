class_name GhostSweep
extends RefCounted
## Slides the held shape's collision boxes through the physics space without passing a placed
## block: the full motion, then its X-only and Z-only remainders (a motion blocked on one axis
## still slides along the other; a purely vertical motion just stops). Only RigidBody3D
## colliders block; other colliders are skipped, bounded per cast.

var _tuning: GhostTuning


func _init(tuning: GhostTuning) -> void:
	_tuning = tuning


## Furthest point from `from` towards `to` that keeps every box (centre offsets `centres`
## rotated by `basis`, cube half-edge `half`, inflated by the collision skin) clear of every
## placed block. Max skipped non-block colliders per cast: tuning.collision_probe_max_bodies.
func sweep(
	space: PhysicsDirectSpaceState3D, centres: Array[Vector3], half: float, basis: Basis,
	from: Vector3, to: Vector3
) -> Vector3:
	var result: Vector3 = from + _motion(space, centres, half, basis, from, to - from)
	var remainder: Vector3 = to - result
	if remainder.length() > 0.0:
		result += _motion(space, centres, half, basis, result, Vector3(remainder.x, 0.0, 0.0))
		remainder = to - result
		result += _motion(space, centres, half, basis, result, Vector3(0.0, 0.0, remainder.z))
	return result


## The safe portion of `motion` (ZERO if none is clear, `motion` if all is) over every box.
## The swept box is inflated by the skin so the result always leaves that gap.
func _motion(
	space: PhysicsDirectSpaceState3D, centres: Array[Vector3], half: float, basis: Basis,
	position: Vector3, motion: Vector3
) -> Vector3:
	if motion.length() <= 0.0:
		return Vector3.ZERO
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3.ONE * ((half + _tuning.ghost_collision_skin) * 2.0)
	var min_safe_fraction: float = 1.0
	for local_center: Vector3 in centres:
		var world_center: Vector3 = position + basis * local_center
		min_safe_fraction = minf(
			min_safe_fraction, _cast_one_box(space, box_shape, basis, world_center, motion)
		)
	return motion * clampf(min_safe_fraction, 0.0, 1.0)


## Safe fraction of `motion` (1.0 = clear) for one box. A box already overlapping a placed
## block at its start gets the full motion: the ghost's baseline hover ignores the tower under
## the cursor, so it routinely starts embedded and raising past the block is the only way out
## (cast_motion from an overlap can report a permanent 0.0 and freeze the hover).
func _cast_one_box(
	space: PhysicsDirectSpaceState3D, box_shape: BoxShape3D, basis: Basis, world_center: Vector3,
	motion: Vector3
) -> float:
	var max_bodies: int = _tuning.collision_probe_max_bodies
	var start_probe: PhysicsShapeQueryParameters3D = _query(box_shape, Transform3D(basis, world_center))
	for start_overlap: Dictionary in space.intersect_shape(start_probe, max_bodies):
		if start_overlap.get("collider") is RigidBody3D:
			return 1.0

	var params: PhysicsShapeQueryParameters3D = _query(box_shape, Transform3D(basis, world_center))
	params.motion = motion
	var exclude: Array[RID] = []
	var attempts: int = 0
	while attempts <= max_bodies:
		params.exclude = exclude
		var cast_result: PackedFloat32Array = space.cast_motion(params)
		var safe_fraction: float = cast_result[0] if cast_result.size() > 0 else 1.0
		if safe_fraction >= 1.0:
			return 1.0
		# Probe at the unsafe fraction: the safe one is just before contact, so a probe there
		# can come back empty even when something blocked the cast.
		var unsafe_fraction: float = cast_result[1] if cast_result.size() > 1 else safe_fraction
		var probe: PhysicsShapeQueryParameters3D = _query(
			box_shape, Transform3D(basis, world_center + motion * unsafe_fraction)
		)
		probe.exclude = exclude
		var non_block_rids: Array[RID] = []
		for overlap: Dictionary in space.intersect_shape(probe, max_bodies):
			if overlap.get("collider") is RigidBody3D:
				return safe_fraction
			non_block_rids.append(overlap["rid"] as RID)
		if non_block_rids.is_empty():
			return 1.0
		exclude.append_array(non_block_rids)
		attempts += 1
	return 0.0


func _query(box_shape: BoxShape3D, at: Transform3D) -> PhysicsShapeQueryParameters3D:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = box_shape
	query.transform = at
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = FieldBody.PLACEMENT_QUERY_MASK
	return query
