extends GutTest
## GiftFlight: one crate's flight record. Fall progress, sway-faded world position, landing and the
## snapshot shape MatchGifts.gift_state returns. Pure data, driven through its public methods.

const ORIGIN: Vector3 = Vector3(1.0, 20.0, 2.0)
const LANDING: Vector3 = Vector3(4.0, 10.0, -2.0)
const TOL: float = 0.0001

var _config: GiftConfig


func before_each() -> void:
	_config = GiftConfig.new()
	_config.fall_speed_m_s = 2.0
	_config.sway_amplitude_m = 0.0
	_config.sway_frequency_hz = 0.33


func _flight(id: int = 7) -> GiftFlight:
	return GiftFlight.new(id, Vector2(4.0, -2.0), ORIGIN, LANDING, GiftWirePhase.FALLING)


func _distance() -> float:
	return ORIGIN.distance_to(LANDING)


func test_constructor_fills_the_record() -> void:
	var flight: GiftFlight = _flight(9)
	assert_eq(flight.gift_id, 9)
	assert_eq(flight.position, Vector2(4.0, -2.0))
	assert_eq(flight.origin, ORIGIN)
	assert_eq(flight.landing, LANDING)
	assert_eq(flight.phase, GiftWirePhase.FALLING)
	assert_eq(flight.elapsed, 0.0)
	assert_eq(flight.age, 0.0)
	assert_false(flight.flight_received)


func test_progress_is_speed_times_time_over_distance() -> void:
	var flight: GiftFlight = _flight()
	var progress: float = flight.advance_fall(1.0, _config)
	assert_almost_eq(progress, 2.0 / _distance(), TOL)
	assert_almost_eq(flight.elapsed, 1.0, TOL)


func test_progress_accumulates_across_calls() -> void:
	var flight: GiftFlight = _flight()
	flight.advance_fall(0.5, _config)
	var progress: float = flight.advance_fall(0.5, _config)
	assert_almost_eq(flight.elapsed, 1.0, TOL)
	assert_almost_eq(progress, 2.0 / _distance(), TOL)


func test_progress_clamps_to_one() -> void:
	var flight: GiftFlight = _flight()
	assert_eq(flight.advance_fall(1000.0, _config), 1.0)
	assert_eq(flight.advance_fall(1.0, _config), 1.0, "stays at one")
	assert_almost_eq(flight.elapsed, 1001.0, TOL, "elapsed keeps counting")


func test_zero_delta_leaves_progress_at_zero() -> void:
	var flight: GiftFlight = _flight()
	assert_eq(flight.advance_fall(0.0, _config), 0.0)
	assert_eq(flight.elapsed, 0.0)


func test_zero_distance_is_progress_one() -> void:
	var flight: GiftFlight = GiftFlight.new(1, Vector2.ZERO, ORIGIN, ORIGIN, GiftWirePhase.FALLING)
	assert_eq(flight.advance_fall(0.0, _config), 1.0)
	assert_eq(flight.advance_fall(0.1, _config), 1.0)
	assert_almost_eq(flight.elapsed, 0.1, TOL)


func test_fall_speed_is_floored_so_a_stalled_config_still_moves() -> void:
	_config.fall_speed_m_s = 0.0
	var flight: GiftFlight = _flight()
	var progress: float = flight.advance_fall(1.0, _config)
	assert_almost_eq(progress, 0.001 / _distance(), 0.000001, "floor of 0.001 m/s")
	_config.fall_speed_m_s = -5.0
	var negative: GiftFlight = _flight()
	assert_almost_eq(negative.advance_fall(1.0, _config), 0.001 / _distance(), 0.000001)


func test_faster_fall_speed_gives_proportionally_more_progress() -> void:
	_config.fall_speed_m_s = 1.0
	var slow: float = _flight().advance_fall(1.0, _config)
	_config.fall_speed_m_s = 2.0
	var fast: float = _flight().advance_fall(1.0, _config)
	assert_almost_eq(fast, slow * 2.0, TOL)


func test_world_position_endpoints() -> void:
	var flight: GiftFlight = _flight()
	_config.sway_amplitude_m = 3.0
	assert_eq(flight.world_position(_config, 0.0), ORIGIN)
	assert_eq(flight.world_position(_config, -1.0), ORIGIN, "below zero is the origin")
	assert_eq(flight.world_position(_config, 1.0), LANDING)
	assert_eq(flight.world_position(_config, 2.5), LANDING, "above one is the landing")


func test_world_position_at_full_progress_is_the_exact_landing_with_sway() -> void:
	# 1 + ((1e-8) - 1) rounds to 0 in single precision, so a lerp at t=1 is not the landing.
	var origin: Vector3 = Vector3(1.0, 20.0, 1.0)
	var landing: Vector3 = Vector3(1.0e-8, 10.0, 1.0e-8)
	var flight: GiftFlight = GiftFlight.new(5, Vector2.ZERO, origin, landing, GiftWirePhase.FALLING)
	_config.sway_amplitude_m = 2.0
	flight.elapsed = 1.7
	assert_eq(flight.world_position(_config, 1.0), landing, "exact landing, not a lerp")
	assert_eq(flight.world_position(_config, 0.0), origin)


func test_world_position_without_sway_is_a_straight_line() -> void:
	var flight: GiftFlight = _flight()
	for progress: float in [0.1, 0.25, 0.5, 0.9]:
		var expected: Vector3 = ORIGIN.lerp(LANDING, progress)
		assert_true(flight.world_position(_config, progress).is_equal_approx(expected), "p=%s" % progress)


func test_sway_is_horizontal_and_bounded_by_the_faded_amplitude() -> void:
	_config.sway_amplitude_m = 0.45
	var flight: GiftFlight = _flight()
	flight.elapsed = 3.7
	for progress: float in [0.05, 0.2, 0.5, 0.8, 0.95]:
		var straight: Vector3 = ORIGIN.lerp(LANDING, progress)
		var offset: Vector3 = flight.world_position(_config, progress) - straight
		assert_almost_eq(offset.y, 0.0, TOL, "height stays linear at p=%s" % progress)
		var bound: float = 0.45 * sin(PI * progress)
		assert_lte(absf(offset.x), bound + TOL, "x within envelope at p=%s" % progress)
		assert_lte(absf(offset.z), bound + TOL, "z within envelope at p=%s" % progress)


func test_sway_fades_towards_both_ends() -> void:
	_config.sway_amplitude_m = 1.0
	var flight: GiftFlight = _flight()
	flight.elapsed = 1.3
	var near_start: Vector3 = flight.world_position(_config, 0.001) - ORIGIN.lerp(LANDING, 0.001)
	var near_end: Vector3 = flight.world_position(_config, 0.999) - ORIGIN.lerp(LANDING, 0.999)
	assert_lt(near_start.length(), 0.01)
	assert_lt(near_end.length(), 0.01)


func test_sway_reaches_the_envelope_peak_at_mid_fall() -> void:
	_config.sway_amplitude_m = 1.0
	var flight: GiftFlight = _flight()
	var best: float = 0.0
	for i: int in range(200):
		flight.elapsed = float(i) * 0.05
		var offset: Vector3 = flight.world_position(_config, 0.5) - ORIGIN.lerp(LANDING, 0.5)
		best = maxf(best, maxf(absf(offset.x), absf(offset.z)))
	assert_gt(best, 0.9, "sin(PI * 0.5) is the full amplitude")
	assert_lte(best, 1.0 + TOL)


func test_sway_amplitude_scales_the_offset() -> void:
	var flight: GiftFlight = _flight()
	flight.elapsed = 2.2
	_config.sway_amplitude_m = 0.5
	var half: Vector3 = flight.world_position(_config, 0.5) - ORIGIN.lerp(LANDING, 0.5)
	_config.sway_amplitude_m = 1.0
	var full: Vector3 = flight.world_position(_config, 0.5) - ORIGIN.lerp(LANDING, 0.5)
	assert_true((half * 2.0).is_equal_approx(full))
	assert_gt(full.length(), 0.0)


func test_negative_sway_settings_are_treated_as_zero() -> void:
	var flight: GiftFlight = _flight()
	flight.elapsed = 2.0
	_config.sway_amplitude_m = -2.0
	assert_true(flight.world_position(_config, 0.5).is_equal_approx(ORIGIN.lerp(LANDING, 0.5)), "negative amplitude")
	_config.sway_amplitude_m = 1.0
	_config.sway_frequency_hz = -3.0
	var negative_freq: Vector3 = flight.world_position(_config, 0.5)
	_config.sway_frequency_hz = 0.0
	assert_true(negative_freq.is_equal_approx(flight.world_position(_config, 0.5)), "negative frequency acts as zero")


func test_sway_is_deterministic_and_differs_per_gift_id() -> void:
	_config.sway_amplitude_m = 1.0
	var first: GiftFlight = _flight(3)
	var again: GiftFlight = _flight(3)
	var other: GiftFlight = _flight(4)
	first.elapsed = 1.0
	again.elapsed = 1.0
	other.elapsed = 1.0
	assert_eq(first.world_position(_config, 0.5), again.world_position(_config, 0.5), "host and client agree")
	assert_ne(first.world_position(_config, 0.5), other.world_position(_config, 0.5), "id seeds the phase")


func test_sway_moves_with_elapsed_time() -> void:
	_config.sway_amplitude_m = 1.0
	var flight: GiftFlight = _flight()
	flight.elapsed = 0.0
	var before: Vector3 = flight.world_position(_config, 0.5)
	flight.elapsed = 0.7
	assert_ne(flight.world_position(_config, 0.5), before)


func test_land_marks_landed_at_the_given_point() -> void:
	var flight: GiftFlight = _flight()
	flight.age = 4.0
	var at: Vector3 = Vector3(4.0, 0.5, -2.0)
	flight.land(at)
	assert_eq(flight.phase, GiftWirePhase.LANDED)
	assert_eq(flight.landing, at)
	assert_eq(flight.age, 0.0)
	assert_eq(flight.origin, ORIGIN, "origin untouched")


func test_snapshot_has_the_gift_state_shape() -> void:
	var flight: GiftFlight = _flight(12)
	flight.advance_fall(0.5, _config)
	var snap: Dictionary = flight.snapshot()
	var keys: Array = snap.keys()
	keys.sort()
	assert_eq(keys, ["elapsed", "id", "landed_age", "landing", "origin", "phase", "position"])
	assert_eq(snap["id"], 12)
	assert_eq(snap["phase"], GiftWirePhase.FALLING)
	assert_eq(snap["position"], Vector2(4.0, -2.0))
	assert_eq(snap["origin"], ORIGIN)
	assert_eq(snap["landing"], LANDING)
	assert_almost_eq(float(snap["elapsed"]), 0.5, TOL)
	assert_eq(float(snap["landed_age"]), 0.0)


func test_snapshot_reflects_landing_and_age() -> void:
	var flight: GiftFlight = _flight()
	flight.land(Vector3(1, 2, 3))
	flight.age = 6.5
	var snap: Dictionary = flight.snapshot()
	assert_eq(snap["phase"], GiftWirePhase.LANDED)
	assert_eq(snap["landing"], Vector3(1, 2, 3))
	assert_almost_eq(float(snap["landed_age"]), 6.5, TOL)


func test_snapshot_is_a_copy() -> void:
	var flight: GiftFlight = _flight()
	var snap: Dictionary = flight.snapshot()
	snap["elapsed"] = 99.0
	snap["phase"] = GiftWirePhase.LANDED
	assert_eq(flight.elapsed, 0.0)
	assert_eq(flight.phase, GiftWirePhase.FALLING)
	assert_eq(float(flight.snapshot()["elapsed"]), 0.0)
