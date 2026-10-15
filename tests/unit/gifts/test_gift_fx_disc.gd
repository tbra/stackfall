extends GutTest
## DiscForce (Bontago-1pi.85.8): sign +1 dips the landing side, -1 raises it;
## shake sweeps and stops after the duration.

var _field: Field
var _tuning: DiscForceTuning


func before_each() -> void:
	_field = autofree(Field.new())
	add_child_autofree(_field)
	_field.set_tilt_enabled(true)
	_tuning = DiscForceTuning.new()


func _edge() -> Vector3:
	return _field.world_from_disk_local(Vector2(5.0, 0.0), 0.0)


func test_sign_plus_and_minus_tilt_opposite_ways() -> void:
	DiscForce.apply(_field, _edge(), 1.0, _tuning, 0.0)
	var down: Vector2 = _field._tilt_velocity
	_field._tilt_velocity = Vector2.ZERO
	DiscForce.apply(_field, _edge(), -1.0, _tuning, 0.0)
	var up: Vector2 = _field._tilt_velocity
	assert_lt(down.y, 0.0, "+1 dips the +X side (rotation about Z negative)")
	assert_gt(up.y, 0.0, "-1 raises it")
	assert_almost_eq(down.y, -up.y, 0.00001)
	assert_almost_eq(absf(down.y), _tuning.strength * 5.0, 0.0001, "strength per metre")


func test_delta_scales_per_tick_use() -> void:
	DiscForce.apply(_field, _edge(), -1.0, _tuning, 0.5)
	assert_almost_eq(_field._tilt_velocity.y, _tuning.strength * 5.0 * 0.5, 0.0001)


func test_tilt_vector_moves_opposite_after_physics() -> void:
	DiscForce.apply(_field, _edge(), 1.0, _tuning, 0.0)
	await wait_physics_frames(10)
	var anvil: Vector2 = _field.tilt_vector()
	_field.set_tilt_enabled(false)
	_field.set_tilt_enabled(true)
	DiscForce.apply(_field, _edge(), -1.0, _tuning, 0.0)
	await wait_physics_frames(10)
	var prop: Vector2 = _field.tilt_vector()
	assert_lt(anvil.y, 0.0)
	assert_gt(prop.y, 0.0)


func test_centre_null_and_bad_input_are_noops() -> void:
	DiscForce.apply(_field, _field.world_from_disk_local(Vector2.ZERO, 0.0), 1.0, _tuning, 0.0)
	DiscForce.apply(null, _edge(), 1.0, _tuning, 0.0)
	DiscForce.apply(_field, Vector3(INF, 0.0, 0.0), 1.0, _tuning, 0.0)
	DiscForce.apply(_field, _edge(), 0.0, _tuning, 0.0)
	DiscForce.apply(_field, _edge(), 1.0, null, 0.0)
	assert_eq(_field._tilt_velocity, Vector2.ZERO)


func test_shake_applies_then_stops_after_duration() -> void:
	DiscForce.shake(_field, _tuning, 0.0, 0.1)
	assert_gt(_field._tilt_velocity.length(), 0.0)
	_field._tilt_velocity = Vector2.ZERO
	DiscForce.shake(_field, _tuning, _tuning.duration_s + 0.01, 0.1)
	DiscForce.shake(null, _tuning, 0.0, 0.1)
	assert_eq(_field._tilt_velocity, Vector2.ZERO)


func test_shake_direction_sweeps() -> void:
	var a: Vector2 = DiscForce.shake_direction(_tuning, 0.0)
	var b: Vector2 = DiscForce.shake_direction(_tuning, 0.1)
	assert_almost_eq(a.length(), 1.0, 0.0001)
	assert_gt(absf(a.angle_to(b)), 0.1, "axis rotates over time")
