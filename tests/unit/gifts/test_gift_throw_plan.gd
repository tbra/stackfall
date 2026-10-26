extends GutTest
## GiftThrow.launch_plan contract: how a held gift leaves the hand for each mode (velocity, spawn
## point, faced pose as a faces/faced_basis pair, range scale and speed cap). Pure: no scene tree.
## Expected values are derived from the pieces the host used before the plan existed (GiftAim,
## FlightFacing, BlockFactory.muzzle_matched_origin), so this pins "the plan changes nothing".

const SURFACE_Y: float = 2.0
const ORIGIN: Vector3 = Vector3(3.0, 5.0, -4.0)
const EPS: float = 0.001

var _tuning: SpecialTuning
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _shape: BlockShape


func before_each() -> void:
	_tuning = SpecialTuning.new()
	_shape = BlockShape.new()
	_shape.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]


func _def(id: StringName, mode: GiftThrow.Mode, effect: SpecialEffect = null) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.throwable = mode == GiftThrow.Mode.THROW
	def.aimed_launch = mode == GiftThrow.Mode.AIMED
	def.effect = effect
	return def


func _plan(def: SpecialDef, mode: GiftThrow.Mode, aim: Vector3, range_scale: float = 1.0,
		origin: Vector3 = ORIGIN) -> GiftThrow.Plan:
	return GiftThrow.launch_plan(def, mode, aim, origin, SURFACE_Y, range_scale, _tuning, _shape)


func _assert_basis_eq(actual: Basis, expected: Basis, label: String) -> void:
	assert_true(actual.x.is_equal_approx(expected.x) and actual.y.is_equal_approx(expected.y)
			and actual.z.is_equal_approx(expected.z), "%s: %s vs %s" % [label, actual, expected])


# --- THROW -----------------------------------------------------------------------

func test_throw_velocity_is_the_ballistic_launch_for_the_aim() -> void:
	var aim: Vector3 = Vector3(0.6, 0.2, -0.8).normalized()
	var plan: GiftThrow.Plan = _plan(_def(&"gift_bomb", GiftThrow.Mode.THROW), GiftThrow.Mode.THROW, aim)
	assert_eq(plan.mode, GiftThrow.Mode.THROW)
	assert_true(plan.velocity.is_equal_approx(GiftAim.throw_velocity(aim, _tuning)), str(plan.velocity))
	assert_almost_eq(plan.velocity.length(), _tuning.gift_throw_speed_mps, EPS)


func test_throw_spawns_on_the_camera_line_above_the_surface() -> void:
	_tuning.gift_aim_back_m = 1.5
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var plan: GiftThrow.Plan = _plan(_def(&"gift_bomb", GiftThrow.Mode.THROW), GiftThrow.Mode.THROW, aim)
	assert_true(plan.spawn_origin.is_equal_approx(ORIGIN - aim * 1.5), str(plan.spawn_origin))


func test_throw_spawn_is_never_below_the_minimum_height_over_the_surface() -> void:
	var low: Vector3 = Vector3(1.0, SURFACE_Y - 0.5, 1.0)
	var plan: GiftThrow.Plan = _plan(_def(&"gift_bomb", GiftThrow.Mode.THROW), GiftThrow.Mode.THROW,
			Vector3(0.0, 0.0, -1.0), 1.0, low)
	assert_almost_eq(plan.spawn_origin.y, SURFACE_Y + _tuning.gift_aim_min_height_m, EPS)
	assert_almost_eq(plan.spawn_origin.x, low.x, EPS)
	assert_almost_eq(plan.spawn_origin.z, low.z, EPS)


func test_throw_range_scale_grows_speed_by_its_square_root_and_is_carried_on_the_plan() -> void:
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var def: SpecialDef = _def(&"gift_bomb", GiftThrow.Mode.THROW)
	var base: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, aim, 1.0)
	var scaled: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, aim, 1.44)
	assert_almost_eq(scaled.velocity.length(), base.velocity.length() * 1.2, EPS)
	assert_true(scaled.velocity.normalized().is_equal_approx(base.velocity.normalized()), "direction unchanged")
	assert_almost_eq(scaled.range_scale, 1.44, EPS)


func test_throw_speed_is_capped_at_the_scaled_max_speed() -> void:
	_tuning.gift_throw_speed_mps = 500.0
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var def: SpecialDef = _def(&"gift_bomb", GiftThrow.Mode.THROW)
	var plain: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, aim, 1.0)
	assert_almost_eq(plain.velocity.length(), _tuning.throw_max_speed, EPS)
	var scaled: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, aim, 4.0)
	assert_almost_eq(scaled.velocity.length(), _tuning.throw_max_speed * 2.0, EPS)


func test_throw_with_an_unresolved_def_is_still_a_ballistic_throw_without_facing() -> void:
	var aim: Vector3 = Vector3(0.0, 0.3, -1.0).normalized()
	var plan: GiftThrow.Plan = _plan(null, GiftThrow.Mode.THROW, aim)
	assert_true(plan.velocity.is_equal_approx(GiftAim.throw_velocity(aim, _tuning)))
	assert_false(plan.faces)


func test_throw_with_a_malformed_aim_has_no_launch_velocity_and_no_facing() -> void:
	var def: SpecialDef = _def(&"gift_bomb", GiftThrow.Mode.THROW)
	for bad: Vector3 in [Vector3.ZERO, Vector3(NAN, 0.0, 1.0), Vector3(0.0, 0.0, INF)]:
		var plan: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, bad)
		assert_eq(plan.velocity, Vector3.ZERO, str(bad))
		assert_false(plan.faces, str(bad))


# --- THROW facing (Magnet) -------------------------------------------------------

func test_magnet_faces_its_launch_velocity() -> void:
	var magnet: MagnetEffect = MagnetEffect.new()
	var aim: Vector3 = Vector3(0.5, 0.1, -0.7).normalized()
	var plan: GiftThrow.Plan = _plan(_def(&"gift_magnet", GiftThrow.Mode.THROW, magnet), GiftThrow.Mode.THROW, aim)
	assert_true(plan.faces)
	var launch: Vector3 = GiftAim.throw_velocity(aim, _tuning)
	_assert_basis_eq(plan.faced_basis, FlightFacing.nose_basis(magnet.model_nose_axis, launch), "magnet")


func test_other_thrown_gifts_keep_the_upright_pose() -> void:
	var plan: GiftThrow.Plan = _plan(_def(&"gift_bomb", GiftThrow.Mode.THROW), GiftThrow.Mode.THROW, Vector3(0.0, 0.0, -1.0))
	assert_false(plan.faces, "bomb has no faced pose")
	_assert_basis_eq(plan.faced_basis, Basis.IDENTITY, "unused faced_basis stays IDENTITY")


# --- AIMED -----------------------------------------------------------------------

func test_rocket_faces_its_aim_even_when_aimed_upward() -> void:
	var rocket: RocketEffect = RocketEffect.new()
	var up_aim: Vector3 = Vector3(0.2, 0.9, -0.3).normalized()
	var plan: GiftThrow.Plan = _plan(_def(&"gift_rocket", GiftThrow.Mode.AIMED, rocket), GiftThrow.Mode.AIMED, up_aim)
	assert_eq(plan.mode, GiftThrow.Mode.AIMED)
	assert_true(plan.faces)
	_assert_basis_eq(plan.faced_basis, FlightFacing.nose_basis(rocket.model_nose_axis, up_aim), "rocket up")
	var level: Vector3 = Vector3(0.0, 0.0, -1.0)
	var level_plan: GiftThrow.Plan = _plan(_def(&"gift_rocket", GiftThrow.Mode.AIMED, rocket), GiftThrow.Mode.AIMED, level)
	_assert_basis_eq(level_plan.faced_basis, FlightFacing.nose_basis(rocket.model_nose_axis, level), "rocket level")


func test_paintball_faces_a_downward_shot_upright() -> void:
	var paintball: PaintballEffect = PaintballEffect.new()
	var aim: Vector3 = Vector3(0.3, -0.5, -0.8).normalized()
	var plan: GiftThrow.Plan = _plan(_def(&"gift_paintball", GiftThrow.Mode.AIMED, paintball), GiftThrow.Mode.AIMED, aim)
	assert_true(plan.faces)
	_assert_basis_eq(plan.faced_basis, FlightFacing.upright_nose_basis(paintball.model_nose_axis, aim), "paintball")


func test_paintball_drops_the_upward_part_of_an_upward_aim() -> void:
	var paintball: PaintballEffect = PaintballEffect.new()
	var aim: Vector3 = Vector3(0.3, 0.6, -0.8).normalized()
	var plan: GiftThrow.Plan = _plan(_def(&"gift_paintball", GiftThrow.Mode.AIMED, paintball), GiftThrow.Mode.AIMED, aim)
	var down: Vector3 = RocketEffect.sanitize_downward_direction(aim)
	if down == Vector3.ZERO:
		assert_false(plan.faces, "no usable downward direction keeps the upright pose")
	else:
		assert_true(plan.faces)
		_assert_basis_eq(plan.faced_basis, FlightFacing.upright_nose_basis(paintball.model_nose_axis, down), "paintball up")


func test_paintball_straight_up_has_no_faced_pose() -> void:
	var plan: GiftThrow.Plan = _plan(_def(&"gift_paintball", GiftThrow.Mode.AIMED, PaintballEffect.new()),
			GiftThrow.Mode.AIMED, Vector3.UP)
	assert_false(plan.faces)


func test_aimed_launch_has_no_ballistic_arc_and_flies_along_the_aim_if_it_has_a_velocity() -> void:
	# The AIMED velocity is not pinned to one value: before the plan the host left the carrier at
	# rest and the effect applied the flight, so ZERO is as valid as a straight velocity. What is
	# never valid is the ballistic (lofted) throw velocity.
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var plan: GiftThrow.Plan = _plan(_def(&"gift_rocket", GiftThrow.Mode.AIMED, RocketEffect.new()), GiftThrow.Mode.AIMED, aim)
	assert_false(plan.velocity.is_equal_approx(GiftAim.throw_velocity(aim, _tuning)), "no loft ratio on an aimed flight")
	if plan.velocity != Vector3.ZERO:
		assert_true(plan.velocity.normalized().is_equal_approx(aim), str(plan.velocity))


func test_aimed_spawn_is_matched_to_the_held_model_when_faced() -> void:
	var rocket: RocketEffect = RocketEffect.new()
	var aim: Vector3 = Vector3(0.2, 0.9, -0.3).normalized()
	var plan: GiftThrow.Plan = _plan(_def(&"gift_rocket", GiftThrow.Mode.AIMED, rocket), GiftThrow.Mode.AIMED, aim)
	var on_line: Vector3 = GiftAim.spawn_point(ORIGIN, aim, SURFACE_Y, _tuning)
	var expected: Vector3 = BlockFactory.muzzle_matched_origin(on_line, plan.faced_basis, _shape, _physics, &"gift_rocket")
	assert_true(plan.spawn_origin.is_equal_approx(expected), "%s vs %s" % [plan.spawn_origin, expected])


func test_aimed_spawn_without_a_faced_pose_is_just_the_camera_line_point() -> void:
	var aim: Vector3 = Vector3.UP
	var plan: GiftThrow.Plan = _plan(_def(&"gift_paintball", GiftThrow.Mode.AIMED, PaintballEffect.new()), GiftThrow.Mode.AIMED, aim)
	assert_true(plan.spawn_origin.is_equal_approx(GiftAim.spawn_point(ORIGIN, aim, SURFACE_Y, _tuning)))


func test_range_scale_does_not_change_an_aimed_launch_speed() -> void:
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var def: SpecialDef = _def(&"gift_rocket", GiftThrow.Mode.AIMED, RocketEffect.new())
	var a: GiftThrow.Plan = _plan(def, GiftThrow.Mode.AIMED, aim, 1.0)
	var b: GiftThrow.Plan = _plan(def, GiftThrow.Mode.AIMED, aim, 4.0)
	assert_true(a.velocity.is_equal_approx(b.velocity), "map size scales the ballistic throw only")


# --- NONE ------------------------------------------------------------------------

func test_none_mode_is_a_refused_plan_with_no_launch() -> void:
	var plan: GiftThrow.Plan = _plan(_def(&"gift_anvil", GiftThrow.Mode.NONE), GiftThrow.Mode.NONE, Vector3(0.0, 0.0, -1.0))
	assert_eq(plan.mode, GiftThrow.Mode.NONE)
	assert_eq(plan.velocity, Vector3.ZERO)
	assert_false(plan.faces)


# --- stability -------------------------------------------------------------------

func test_a_plan_is_a_fresh_object_and_planning_does_not_mutate_the_tuning() -> void:
	var def: SpecialDef = _def(&"gift_bomb", GiftThrow.Mode.THROW)
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var speed: float = _tuning.gift_throw_speed_mps
	var first: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, aim)
	var second: GiftThrow.Plan = _plan(def, GiftThrow.Mode.THROW, aim)
	assert_ne(first, second)
	assert_true(first.velocity.is_equal_approx(second.velocity))
	assert_eq(_tuning.gift_throw_speed_mps, speed)
