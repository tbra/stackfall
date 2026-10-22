extends GutTest
## DiscTilt (core/physics/DiscTilt.gd): the disc's tilt spring, driven only through
## its public methods under the shipped TiltTuning. Spec 1.7, 1.2, 2.7.

const TICK: float = 1.0 / 60.0
## Long enough for the 4 s spring to settle and the rest deadband to latch.
const SETTLE_S: float = 60.0

var _tuning: TiltTuning


func before_each() -> void:
	_tuning = load("res://config/physics/tilt_tuning.tres") as TiltTuning


func _make() -> DiscTilt:
	return DiscTilt.new(_tuning)


## Steps `seconds` of ticks, marking each reported write as applied the way Field does;
## returns how many step() calls reported true.
func _run(
	disc: DiscTilt,
	seconds: float,
	balance: DiscTilt.Balance = DiscTilt.Balance.OFF,
	samples: PackedVector3Array = PackedVector3Array(),
) -> int:
	var writes: int = 0
	for _i: int in range(int(seconds / TICK)):
		if disc.step(TICK, balance, samples):
			writes += 1
			disc.mark_applied()
	return writes


## One sample is (disk-local x, mass, disk-local z); a load at +x drives tilt.y
## negative, with an equilibrium well under the clamp.
func _load_samples(x: float = 2.0, mass: float = 100.0) -> PackedVector3Array:
	return PackedVector3Array([Vector3(x, mass, 0.0)])


func _equilibrium_y(x: float, mass: float) -> float:
	return -x * mass * _tuning.physical_balance_torque_gain / _tuning.spring_stiffness()


# --- impulse and the spring -------------------------------------------------

func test_a_fresh_disc_is_level() -> void:
	var disc: DiscTilt = _make()
	assert_eq(disc.tilt(), Vector2.ZERO)
	assert_true(disc.basis().is_equal_approx(Basis.IDENTITY))


func test_an_impulse_then_a_step_tilts_the_disc_and_asks_for_a_write() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.5)
	assert_true(disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array()), "a moved tilt must be written")
	assert_ne(disc.tilt(), Vector2.ZERO, "the impulse moved the tilt")
	assert_false(disc.is_at_rest())


func test_the_impulse_dips_the_side_it_points_at() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	_run(disc, 1.0)
	# Vector2(dir.y, -dir.x) * magnitude: +x dips tilt.y negative.
	assert_lt(disc.tilt().y, 0.0)
	assert_almost_eq(disc.tilt().x, 0.0, 0.0001)
	var other: DiscTilt = _make()
	other.impulse(Vector2(0.0, 1.0), 0.1)
	_run(other, 1.0)
	assert_gt(other.tilt().x, 0.0, "+z dips tilt.x positive")
	assert_almost_eq(other.tilt().y, 0.0, 0.0001)


func test_basis_is_the_two_axis_rotation_of_the_tilt_vector() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 1.0), 0.1)
	_run(disc, 1.0)
	var tilt: Vector2 = disc.tilt()
	assert_ne(tilt, Vector2.ZERO, "fixture: tilted")
	var expected: Basis = Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.BACK, tilt.y)
	assert_true(disc.basis().is_equal_approx(expected))


func test_a_zero_impulse_does_nothing() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2.ZERO, 5.0)
	disc.impulse(Vector2.RIGHT, 0.0)
	_run(disc, 1.0)
	assert_eq(disc.tilt(), Vector2.ZERO)


func test_an_impulse_eases_back_to_level_under_the_shipped_tuning() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	var peak: float = 0.0
	for _i: int in range(int(SETTLE_S / TICK)):
		disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array())
		disc.mark_applied()
		peak = maxf(peak, disc.tilt().length())
	assert_gt(peak, 0.01, "fixture: the impulse produced a real tilt to decay from")
	assert_lt(disc.tilt().length(), peak * 0.01, "the tilt returns to level")


func test_the_return_follows_the_critically_damped_time_constant() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	# Impulse response v0 * t * e^(-t/tau): at t = tau the tilt is v0 * tau / e.
	var tau: float = _tuning.return_time_constant_s
	_run(disc, tau)
	assert_almost_eq(disc.tilt().length(), 0.1 * tau / exp(1.0), 0.002)


func test_the_tilt_never_exceeds_the_max_angle_however_many_impulses_land() -> void:
	var disc: DiscTilt = _make()
	for _i: int in range(50):
		disc.impulse(Vector2(0.0, 1.0), 10.0)
	disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array())
	assert_lte(rad_to_deg(disc.tilt().length()), _tuning.max_tilt_deg + 0.001)
	var peak_deg: float = rad_to_deg(disc.tilt().length())
	for _i: int in range(120):
		disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array())
		assert_lte(rad_to_deg(disc.tilt().length()), _tuning.max_tilt_deg + 0.001)
		peak_deg = maxf(peak_deg, rad_to_deg(disc.tilt().length()))
	assert_almost_eq(peak_deg, _tuning.max_tilt_deg, 0.01, "the clamp is reached, not undershot")


# --- the rest deadband --------------------------------------------------------

func test_the_disc_latches_at_rest_once_it_settles_and_stops_asking_for_writes() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	assert_gt(_run(disc, 1.0), 0, "fixture: it writes while moving")
	assert_false(disc.is_at_rest())
	_run(disc, SETTLE_S)
	assert_true(disc.is_at_rest(), "settled and held past rest_hold_s")
	var latched: Vector2 = disc.tilt()
	for _i: int in range(60):
		assert_false(disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array()), "no transform rewrite at rest")
	assert_eq(disc.tilt(), latched, "the tilt is bit-static at rest")


func test_the_latch_needs_the_hold_time_not_just_one_quiet_tick() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	_run(disc, SETTLE_S)
	assert_true(disc.is_at_rest(), "fixture: latched")
	disc.reset()
	# A level disc has zero velocity and zero error, but rest_hold_s must elapse first.
	_run(disc, _tuning.rest_hold_s * 0.5)
	assert_false(disc.is_at_rest(), "not latched before rest_hold_s")
	_run(disc, _tuning.rest_hold_s * 0.5 + 0.2)
	assert_true(disc.is_at_rest(), "latched once rest_hold_s has passed")


func test_an_impulse_wakes_a_resting_disc() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	_run(disc, SETTLE_S)
	assert_true(disc.is_at_rest(), "fixture: latched")
	disc.impulse(Vector2(0.0, 1.0), 0.1)
	assert_false(disc.is_at_rest(), "an impulse wakes the disc")
	assert_true(disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array()))
	assert_ne(disc.tilt(), Vector2.ZERO)


func test_a_tilt_that_was_not_marked_applied_keeps_reporting_a_write() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	assert_true(disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array()))
	# Not marked applied: the transform still differs from the tilt.
	assert_true(disc.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array()))


# --- mirror mode --------------------------------------------------------------

func test_set_pose_decomposes_the_quaternion_into_the_tilt_vector() -> void:
	var disc: DiscTilt = _make()
	var pose: Vector2 = Vector2(0.1, -0.05)
	var quat: Quaternion = (
		Basis(Vector3.RIGHT, pose.x) * Basis(Vector3.BACK, pose.y)
	).get_rotation_quaternion()
	disc.set_pose(quat)
	assert_almost_eq(disc.tilt().x, pose.x, 0.0001)
	assert_almost_eq(disc.tilt().y, pose.y, 0.0001)
	assert_lt(disc.basis().get_rotation_quaternion().angle_to(quat), 0.0001)


func test_a_posed_disc_ignores_impulses() -> void:
	var quat: Quaternion = (
		Basis(Vector3.RIGHT, 0.08) * Basis(Vector3.BACK, -0.03)
	).get_rotation_quaternion()
	var posed: DiscTilt = _make()
	posed.set_pose(quat)
	var twin: DiscTilt = _make()
	twin.set_pose(quat)
	assert_ne(posed.tilt(), Vector2.ZERO, "fixture: the pose took")
	posed.impulse(Vector2(1.0, 0.0), 5.0)
	posed.impulse(Vector2(0.0, 1.0), 5.0)
	for _i: int in range(120):
		posed.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array())
		twin.step(TICK, DiscTilt.Balance.OFF, PackedVector3Array())
	assert_eq(posed.tilt(), twin.tilt(), "impulses change nothing in mirror mode")


# --- PHYSICAL_BALANCE torque (Balance) -------------------------------------------

func test_balance_off_ignores_the_samples() -> void:
	var disc: DiscTilt = _make()
	_run(disc, 10.0, DiscTilt.Balance.OFF, _load_samples())
	assert_eq(disc.tilt(), Vector2.ZERO, "OFF gives zero torque")


func test_balance_sampled_tilts_toward_the_load_and_settles_at_the_spring_equilibrium() -> void:
	var disc: DiscTilt = _make()
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples())
	assert_lt(disc.tilt().y, 0.0, "a +x load dips tilt.y negative")
	assert_almost_eq(disc.tilt().x, 0.0, 0.0005)
	assert_almost_eq(disc.tilt().y, _equilibrium_y(2.0, 100.0), 0.002, "gain * torque / stiffness")
	for _i: int in range(60):
		assert_false(
			disc.step(TICK, DiscTilt.Balance.HOLD, PackedVector3Array()),
			"a settled load stops asking for transform writes"
		)


func test_balance_sampled_recomputes_from_each_call() -> void:
	var disc: DiscTilt = _make()
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples(2.0, 100.0))
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples(-2.0, 100.0))
	assert_almost_eq(disc.tilt().y, -_equilibrium_y(2.0, 100.0), 0.002, "the new samples replace the old torque")


func test_balance_hold_keeps_the_previous_torque_and_ignores_the_samples() -> void:
	var disc: DiscTilt = _make()
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples())
	var settled: Vector2 = disc.tilt()
	assert_lt(settled.y, -0.01, "fixture: tilted under load")
	_run(disc, SETTLE_S, DiscTilt.Balance.HOLD, _load_samples(-2.0, 100.0))
	assert_almost_eq(disc.tilt().y, settled.y, 0.002, "HOLD keeps the latch; the offered samples are not read")


func test_balance_hold_with_nothing_latched_stays_level() -> void:
	var disc: DiscTilt = _make()
	_run(disc, 10.0, DiscTilt.Balance.HOLD, _load_samples())
	assert_eq(disc.tilt(), Vector2.ZERO)


func test_balance_empty_zeroes_the_latch_and_the_disc_returns_to_level() -> void:
	var disc: DiscTilt = _make()
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples())
	assert_lt(disc.tilt().y, -0.01, "fixture: tilted under load")
	_run(disc, SETTLE_S, DiscTilt.Balance.EMPTY)
	assert_lt(disc.tilt().length(), 0.002, "removing the load levels the disc")
	# The latch is gone: HOLD afterwards has nothing to hold.
	_run(disc, 10.0, DiscTilt.Balance.HOLD)
	assert_lt(disc.tilt().length(), 0.002)


func test_balance_off_after_a_load_also_drops_the_torque() -> void:
	var disc: DiscTilt = _make()
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples())
	assert_lt(disc.tilt().y, -0.01, "fixture: tilted under load")
	_run(disc, SETTLE_S, DiscTilt.Balance.OFF)
	assert_lt(disc.tilt().length(), 0.002)


func test_a_large_load_is_clamped_to_the_max_angle() -> void:
	var disc: DiscTilt = _make()
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples(6.0, 100000.0))
	assert_almost_eq(rad_to_deg(disc.tilt().length()), _tuning.max_tilt_deg, 0.01)


func test_a_load_wakes_a_resting_disc() -> void:
	var disc: DiscTilt = _make()
	_run(disc, 2.0)
	assert_true(disc.is_at_rest(), "fixture: level and latched")
	_run(disc, SETTLE_S, DiscTilt.Balance.SAMPLED, _load_samples())
	assert_lt(disc.tilt().y, -0.01, "the moved target woke the deadband")


# --- reset ----------------------------------------------------------------------

func test_reset_returns_to_level_and_clears_the_rest_latch() -> void:
	var disc: DiscTilt = _make()
	disc.impulse(Vector2(1.0, 0.0), 0.1)
	_run(disc, 1.0)
	assert_ne(disc.tilt(), Vector2.ZERO, "fixture: tilted")
	disc.reset()
	assert_eq(disc.tilt(), Vector2.ZERO)
	assert_true(disc.basis().is_equal_approx(Basis.IDENTITY))
	_run(disc, SETTLE_S)
	assert_true(disc.is_at_rest(), "fixture: latched after settling")
	disc.reset()
	assert_false(disc.is_at_rest(), "reset clears the latch")
