extends GutTest
## Bontago-adt.3: core/ambient/PerchPlanner.gd -- landing-spot selection respects
## distances, flee triggers, tower (block-top) selection and block-moved detection.

const DISC_RADIUS: float = 30.0


func _circle(world_xz: Vector2) -> bool:
	return world_xz.length() <= DISC_RADIUS


func _radii(count: int, radius: float) -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	radii.resize(count)
	radii.fill(radius)
	return radii


func test_is_clear_uses_horizontal_distance() -> void:
	var points: PackedVector3Array = PackedVector3Array([Vector3(10.0, 50.0, 0.0)])
	assert_false(PerchPlanner.is_clear(Vector3(15.0, 0.0, 0.0), points, _radii(1, 6.0)), "5 m away horizontally is too close even 50 m below")
	assert_true(PerchPlanner.is_clear(Vector3(17.0, 0.0, 0.0), points, _radii(1, 6.0)))


func test_is_on_disc_requires_margin_all_round() -> void:
	var on_disc: Callable = Callable(self, "_circle")
	assert_true(PerchPlanner.is_on_disc(Vector3(0.0, 0.0, 0.0), 3.0, on_disc))
	assert_true(PerchPlanner.is_on_disc(Vector3(26.0, 0.0, 0.0), 3.0, on_disc))
	assert_false(PerchPlanner.is_on_disc(Vector3(28.0, 0.0, 0.0), 3.0, on_disc), "inside the disc but within the edge margin")
	assert_false(PerchPlanner.is_on_disc(Vector3(40.0, 0.0, 0.0), 3.0, on_disc))


func test_pick_spot_respects_every_hazard_distance() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var hazards: PackedVector3Array = PackedVector3Array([
		Vector3(10.0, 0.0, 0.0), Vector3(-10.0, 2.0, 5.0), Vector3(0.0, 0.0, -15.0),
	])
	var radii: PackedFloat32Array = _radii(3, 12.0)
	var found: int = 0
	for _i: int in range(200):
		var spot: Variant = PerchPlanner.pick_spot(rng, Vector3.ZERO, DISC_RADIUS, 3.0, Callable(self, "_circle"), hazards, radii, 24)
		if spot == null:
			continue
		found += 1
		var point: Vector3 = spot as Vector3
		assert_true(PerchPlanner.is_clear(point, hazards, radii), "spot %s is within a hazard radius" % point)
		assert_lte(Vector2(point.x, point.z).length(), DISC_RADIUS - 3.0 * 0.95, "spot is inside the edge margin")
	assert_gt(found, 100, "with room left on the disc most attempts succeed")


func test_pick_spot_returns_null_when_everything_is_hazardous() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var hazards: PackedVector3Array = PackedVector3Array([Vector3.ZERO])
	assert_null(PerchPlanner.pick_spot(rng, Vector3.ZERO, DISC_RADIUS, 3.0, Callable(self, "_circle"), hazards, _radii(1, 100.0), 30))


func test_flee_reason_camera_cursor_overhead_and_calm() -> void:
	var bird: Vector3 = Vector3(5.0, 0.4, 5.0)
	var none: PackedVector3Array = PackedVector3Array()
	assert_eq(PerchPlanner.flee_reason(bird, null, none, none, 9.0, 8.0, 3.5, 0.4), &"")
	assert_eq(PerchPlanner.flee_reason(bird, Vector3(5.0, 8.0, 5.0), none, none, 9.0, 8.0, 3.5, 0.4), &"camera")
	assert_eq(PerchPlanner.flee_reason(bird, Vector3(60.0, 8.0, 5.0), none, none, 9.0, 8.0, 3.5, 0.4), &"")
	assert_eq(PerchPlanner.flee_reason(bird, null, PackedVector3Array([Vector3(9.0, 0.4, 5.0)]), none, 9.0, 8.0, 3.5, 0.4), &"cursor")
	assert_eq(PerchPlanner.flee_reason(bird, null, PackedVector3Array([Vector3(30.0, 0.4, 5.0)]), none, 9.0, 8.0, 3.5, 0.4), &"")
	assert_eq(PerchPlanner.flee_reason(bird, null, none, PackedVector3Array([Vector3(6.0, 5.0, 5.0)]), 9.0, 8.0, 3.5, 0.4), &"overhead")
	assert_eq(PerchPlanner.flee_reason(bird, null, none, PackedVector3Array([Vector3(6.0, 0.5, 5.0)]), 9.0, 8.0, 3.5, 0.4), &"", "a block beside (not above) the bird is not overhead")
	assert_eq(PerchPlanner.flee_reason(bird, null, none, PackedVector3Array([Vector3(20.0, 5.0, 5.0)]), 9.0, 8.0, 3.5, 0.4), &"", "a block far above and aside is not overhead")


func test_top_face_of_upright_and_rotated_boxes() -> void:
	var half: Vector3 = Vector3(0.5, 0.5, 0.5)
	var upright: Variant = PerchPlanner.top_face(Transform3D(Basis.IDENTITY, Vector3(2.0, 1.5, 3.0)), half)
	assert_not_null(upright)
	assert_eq(((upright as Dictionary)["center"] as Vector3), Vector3(2.0, 2.0, 3.0))
	assert_eq(((upright as Dictionary)["size"] as Vector2), Vector2(1.0, 1.0))
	var on_side: Transform3D = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.0, 0.0))
	assert_not_null(PerchPlanner.top_face(on_side, Vector3(0.5, 1.0, 0.5)), "a 90 degree turn still has an axis-aligned top")
	var tilted: Transform3D = Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3.ZERO)
	assert_null(PerchPlanner.top_face(tilted, half), "a tilted block offers no flat top")


func test_top_is_free_detects_a_block_stacked_above() -> void:
	var half: Vector3 = Vector3(0.5, 0.5, 0.5)
	var lower: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	var above: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0))
	var inverses: Array[Transform3D] = [lower.affine_inverse(), above.affine_inverse()]
	var halves: PackedVector3Array = PackedVector3Array([half, half])
	var origins: PackedVector3Array = PackedVector3Array([lower.origin, above.origin])
	var bounds: PackedFloat32Array = PackedFloat32Array([0.9, 0.9])
	var face: Vector3 = Vector3(0.0, 1.0, 0.0)
	assert_false(PerchPlanner.top_is_free(face, 0.3, 1.4, inverses, halves, origins, bounds, 0), "a block sits on the top face")
	var one_inverse: Array[Transform3D] = [lower.affine_inverse()]
	assert_true(PerchPlanner.top_is_free(face, 0.3, 1.4, one_inverse, PackedVector3Array([half]), PackedVector3Array([lower.origin]), PackedFloat32Array([0.9]), 0))
	var beside: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.9, 1.5, 0.0))
	var side_inverses: Array[Transform3D] = [lower.affine_inverse(), beside.affine_inverse()]
	assert_false(
		PerchPlanner.top_is_free(face, 0.45, 1.4, side_inverses, halves, PackedVector3Array([lower.origin, beside.origin]), bounds, 0),
		"a block overlapping the bird footprint above the face blocks it"
	)


func test_pick_candidate_skips_hazardous_faces() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var faces: PackedVector3Array = PackedVector3Array([Vector3(0.0, 5.0, 0.0), Vector3(20.0, 3.0, 0.0), Vector3(-20.0, 8.0, 0.0)])
	var hazards: PackedVector3Array = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(-20.0, 0.0, 1.0)])
	for _i: int in range(20):
		assert_eq(PerchPlanner.pick_candidate(rng, faces, hazards, _radii(2, 10.0)), 1, "only the far face is clear")
	assert_eq(PerchPlanner.pick_candidate(rng, faces, PackedVector3Array([Vector3(20.0, 0.0, 0.0)]), _radii(1, 200.0)), -1)
	assert_eq(PerchPlanner.pick_candidate(rng, PackedVector3Array(), hazards, _radii(2, 10.0)), -1)


func test_block_moved_detects_translation_and_rotation() -> void:
	var anchor: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	assert_false(PerchPlanner.block_moved(anchor, anchor, 0.02))
	assert_false(PerchPlanner.block_moved(anchor, Transform3D(Basis.IDENTITY, Vector3(1.005, 2.0, 3.0)), 0.02), "sub-epsilon jitter is not movement")
	assert_true(PerchPlanner.block_moved(anchor, Transform3D(Basis.IDENTITY, Vector3(1.3, 2.0, 3.0)), 0.02))
	assert_true(PerchPlanner.block_moved(anchor, Transform3D(Basis(Vector3.UP, 0.2), Vector3(1.0, 2.0, 3.0)), 0.02))
