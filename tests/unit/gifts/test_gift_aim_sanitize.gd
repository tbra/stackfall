extends GutTest
## GiftAim.sanitize_launch_direction (Rocket) and sanitize_downward_direction (Paintball):
## the host rejects non-finite or degenerate client aim and normalises the rest.

const TOL: float = 0.0001


func test_launch_direction_is_normalised() -> void:
	var out: Vector3 = GiftAim.sanitize_launch_direction(Vector3(3.0, 0.0, -4.0))
	assert_almost_eq(out.length(), 1.0, TOL)
	assert_almost_eq(out.x, 0.6, TOL)
	assert_almost_eq(out.z, -0.8, TOL)


func test_launch_direction_keeps_the_upward_part() -> void:
	var out: Vector3 = GiftAim.sanitize_launch_direction(Vector3(0.0, 5.0, 0.0))
	assert_almost_eq(out.y, 1.0, TOL, "straight up is allowed for a Rocket")
	var slanted: Vector3 = GiftAim.sanitize_launch_direction(Vector3(1.0, 1.0, 0.0))
	assert_gt(slanted.y, 0.0)
	assert_almost_eq(slanted.length(), 1.0, TOL)


func test_launch_direction_rejects_zero_and_below_minimum() -> void:
	assert_eq(GiftAim.sanitize_launch_direction(Vector3.ZERO), Vector3.ZERO)
	assert_eq(GiftAim.sanitize_launch_direction(Vector3(GiftAim.MIN_FORWARD_LENGTH * 0.5, 0, 0)), Vector3.ZERO)
	assert_ne(GiftAim.sanitize_launch_direction(Vector3(GiftAim.MIN_FORWARD_LENGTH * 2.0, 0, 0)), Vector3.ZERO,
		"just above the minimum is a direction")


func test_launch_direction_rejects_non_finite() -> void:
	for bad: Vector3 in [Vector3(NAN, 0, 1), Vector3(0, INF, 0), Vector3(0, 0, -INF), Vector3(NAN, NAN, NAN)]:
		assert_eq(GiftAim.sanitize_launch_direction(bad), Vector3.ZERO, "rejects %s" % bad)


func test_launch_direction_ignores_input_magnitude() -> void:
	var small: Vector3 = GiftAim.sanitize_launch_direction(Vector3(0.01, 0, 0))
	var huge: Vector3 = GiftAim.sanitize_launch_direction(Vector3(1.0e6, 0, 0))
	assert_almost_eq(small.x, 1.0, TOL)
	assert_almost_eq(huge.x, 1.0, TOL)


func test_downward_direction_drops_the_upward_part() -> void:
	var out: Vector3 = GiftAim.sanitize_downward_direction(Vector3(3.0, 5.0, 4.0))
	assert_eq(out.y, 0.0)
	assert_almost_eq(out.x, 0.6, TOL)
	assert_almost_eq(out.z, 0.8, TOL)


func test_downward_direction_keeps_the_downward_part_normalised() -> void:
	var out: Vector3 = GiftAim.sanitize_downward_direction(Vector3(1.0, -1.0, 0.0))
	assert_almost_eq(out.length(), 1.0, TOL)
	assert_lt(out.y, 0.0)
	assert_almost_eq(out.x, -out.y, TOL)
	var straight_down: Vector3 = GiftAim.sanitize_downward_direction(Vector3(0.0, -2.0, 0.0))
	assert_almost_eq(straight_down.y, -1.0, TOL)


func test_downward_direction_rejects_pure_upward_zero_and_non_finite() -> void:
	assert_eq(GiftAim.sanitize_downward_direction(Vector3.UP), Vector3.ZERO, "nothing left after dropping up")
	assert_eq(GiftAim.sanitize_downward_direction(Vector3.ZERO), Vector3.ZERO)
	assert_eq(GiftAim.sanitize_downward_direction(Vector3(NAN, -1, 0)), Vector3.ZERO)
	assert_eq(GiftAim.sanitize_downward_direction(Vector3(0, -INF, 0)), Vector3.ZERO)


func test_downward_direction_rejects_remainder_below_minimum() -> void:
	var tiny: Vector3 = Vector3(GiftAim.MIN_FORWARD_LENGTH * 0.5, 7.0, 0.0)
	assert_eq(GiftAim.sanitize_downward_direction(tiny), Vector3.ZERO, "upward part dropped leaves a degenerate vector")
