extends GutTest
## PlacementPoint: the legality point is the rotated footprint's centre, projected down (spec 2.5).

const CUBE: float = 1.0


func _xz(shape: BlockShape, basis: Basis, cube_size: float) -> Vector2:
	var offset: Vector3 = PlacementPoint.centre_offset(shape, basis, cube_size)
	return Vector2(offset.x, offset.z)


func _shape(id: String) -> BlockShape:
	return load("res://config/blocks/%s.tres" % id) as BlockShape


func test_upright_piece_is_judged_at_its_pivot() -> void:
	for id: String in ["cube", "pillar", "bar3", "plate9", "L3", "T4"]:
		var shape: BlockShape = _shape(id)
		var offset: Vector2 = _xz(shape, Basis.IDENTITY, CUBE)
		assert_almost_eq(offset.length(), 0.0, 0.0001, "%s upright: point is the pivot" % id)


func test_yawed_piece_keeps_the_pivot_column() -> void:
	var basis: Basis = Basis(Vector3.UP, 0.7)
	var offset: Vector2 = _xz(_shape("pillar"), basis, CUBE)
	assert_almost_eq(offset.length(), 0.0, 0.0001)


func test_pillar_lying_along_x_is_judged_at_its_middle() -> void:
	var basis: Basis = Basis(Vector3.BACK, PI * 0.5)
	var pivot: Vector3 = Vector3(4.0, 1.0, -2.0)
	var point: Vector3 = PlacementPoint.legality_point(pivot, _shape("pillar"), basis, CUBE)
	# Pillar cell centres run y 0.5..2.5 above the pivot: the middle is 1.5 cubes up, tipped onto -x.
	assert_almost_eq(point.x, pivot.x - 1.5 * CUBE, 0.0001)
	assert_almost_eq(point.z, pivot.z, 0.0001)


func test_pillar_lying_along_z_is_judged_at_its_middle() -> void:
	var basis: Basis = Basis(Vector3.RIGHT, PI * 0.5)
	var offset: Vector2 = _xz(_shape("pillar"), basis, CUBE)
	assert_almost_eq(offset.x, 0.0, 0.0001)
	assert_almost_eq(absf(offset.y), 1.5 * CUBE, 0.0001)


func test_tilted_piece_scales_with_cube_size_and_tilt() -> void:
	var basis: Basis = Basis(Vector3.BACK, PI * 0.25)
	var offset: Vector2 = _xz(_shape("pillar"), basis, 2.0)
	# Local middle is (0, 3, 0) at cube_size 2; 45 degrees about z moves it to x = -3 sin(45).
	assert_almost_eq(offset.x, -3.0 * sin(PI * 0.25), 0.0001)
	assert_almost_eq(offset.y, 0.0, 0.0001)


func test_rolled_bar_swings_its_middle_off_the_pivot() -> void:
	# bar3 is flat (y 0 only): a quarter roll about x stands it on edge; its middle stays over x = 0
	# but moves along z by half a cube.
	var basis: Basis = Basis(Vector3.RIGHT, PI * 0.5)
	var offset: Vector2 = _xz(_shape("bar3"), basis, CUBE)
	assert_almost_eq(offset.x, 0.0, 0.0001)
	assert_almost_eq(absf(offset.y), 0.5 * CUBE, 0.0001)


func test_null_shape_is_the_pivot() -> void:
	assert_eq(PlacementPoint.centre_offset(null, Basis.IDENTITY, CUBE), Vector3.ZERO)
