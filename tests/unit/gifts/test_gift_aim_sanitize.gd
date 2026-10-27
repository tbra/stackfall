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


func _tuning() -> SpecialTuning:
	var t: SpecialTuning = SpecialTuning.new()
	t.gift_throw_reference_radius = 40.0
	t.gift_throw_range_scale_min = 0.5
	t.gift_throw_range_scale_max = 2.0
	return t


func test_range_scale_is_radius_over_reference() -> void:
	assert_almost_eq(GiftAim.range_scale(50.0, _tuning()), 1.25, TOL)
	assert_almost_eq(GiftAim.range_scale(30.0, _tuning()), 0.75, TOL)


func test_range_scale_clamps_to_the_tuning_limits() -> void:
	assert_almost_eq(GiftAim.range_scale(1.0, _tuning()), 0.5, TOL, "tiny field hits the minimum")
	assert_almost_eq(GiftAim.range_scale(1000.0, _tuning()), 2.0, TOL, "huge field hits the maximum")


func test_range_scale_is_one_for_a_non_positive_radius() -> void:
	assert_eq(GiftAim.range_scale(0.0, _tuning()), 1.0, "zero radius is unscaled, not the clamped minimum")
	assert_eq(GiftAim.range_scale(-5.0, _tuning()), 1.0)


func test_range_scale_is_one_for_a_non_positive_reference() -> void:
	var t: SpecialTuning = _tuning()
	t.gift_throw_reference_radius = 0.0
	assert_eq(GiftAim.range_scale(30.0, t), 1.0, "zero reference is unscaled, not the clamped maximum")
	t.gift_throw_reference_radius = -4.0
	assert_eq(GiftAim.range_scale(30.0, t), 1.0)


func test_flat_range_is_twice_horizontal_times_vertical_speed_over_gravity() -> void:
	var t: SpecialTuning = _tuning()
	var velocity: Vector3 = GiftAim.throw_velocity(Vector3.FORWARD, t, 1.0)
	var expected: float = 2.0 * Vector2(velocity.x, velocity.z).length() * velocity.y / 9.8
	assert_gt(expected, 0.0)
	assert_almost_eq(GiftAim.flat_range(t, 1.0, 9.8), expected, TOL)
	assert_almost_eq(GiftAim.flat_range(t, 1.0, 19.6), expected * 0.5, TOL, "double gravity halves the range")


func test_flat_range_grows_with_range_scale() -> void:
	var t: SpecialTuning = _tuning()
	assert_almost_eq(GiftAim.flat_range(t, 2.0, 9.8), GiftAim.flat_range(t, 1.0, 9.8) * 2.0, TOL)


func test_flat_range_is_zero_for_non_positive_gravity() -> void:
	assert_eq(GiftAim.flat_range(_tuning(), 1.0, 0.0), 0.0)
	assert_eq(GiftAim.flat_range(_tuning(), 1.0, -9.8), 0.0)
