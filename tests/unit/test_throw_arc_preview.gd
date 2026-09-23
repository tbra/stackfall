extends GutTest
## game/ThrowArcPreview.gd coverage (M4 P2e, docs/M4_P2_PACKAGES.md P2e, spec
## 2.5 "Throw (specials only)"): the arc preview's own pure ballistic sampler
## (sample_arc()) matches the closed-form projectile formula the brief
## specifies, and the visibility lifecycle (hidden until update_arc(), gone
## again after clear_arc()) that game/PlayerController.gd's
## _drive_throw_visuals() drives every frame.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")


func _make_arc() -> ThrowArcPreview:
	var arc: ThrowArcPreview = autofree(ThrowArcPreview.new())
	add_child_autofree(arc)
	return arc


func _expected_gravity(arc: ThrowArcPreview) -> Vector3:
	return Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity")) * arc.physics_tuning.gravity_multiplier


# --- sample_arc(): the pure ballistic formula --------------------------------

func test_sample_arc_matches_the_closed_form_ballistic_formula() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var origin: Vector3 = Vector3(1.0, 2.0, 3.0)
	var velocity: Vector3 = Vector3(4.0, 6.0, -2.0)
	var gravity: Vector3 = _expected_gravity(arc)

	var points: PackedVector3Array = arc.sample_arc(origin, velocity)

	assert_eq(points.size(), arc.ghost_tuning.throw_arc_sample_count + 1, "one point per segment endpoint, inclusive.")
	assert_true(points[0].is_equal_approx(origin), "the first sample must be the launch origin itself (t=0).")
	for i: int in range(points.size()):
		var t: float = arc.ghost_tuning.throw_arc_max_time_s * float(i) / float(arc.ghost_tuning.throw_arc_sample_count)
		var expected: Vector3 = origin + velocity * t + 0.5 * gravity * t * t
		assert_true(
			points[i].is_equal_approx(expected),
			"sample %d: expected %s, got %s" % [i, expected, points[i]]
		)


func test_sample_arc_is_a_pure_function_of_its_own_arguments() -> void:
	# No scene-tree/PlayerController dependence -- the brief's own "provable
	# without physics" bar (docs/M4_P2_PACKAGES.md P2a's wording, reused here
	# for this package's own pure math).
	var arc: ThrowArcPreview = _make_arc()
	var a: PackedVector3Array = arc.sample_arc(Vector3.ZERO, Vector3(1.0, 5.0, 0.0))
	var b: PackedVector3Array = arc.sample_arc(Vector3.ZERO, Vector3(1.0, 5.0, 0.0))
	assert_eq(a.size(), b.size())
	for i: int in range(a.size()):
		assert_true(a[i].is_equal_approx(b[i]))


# --- Visibility lifecycle -----------------------------------------------------

func test_hidden_before_any_update_arc_call() -> void:
	var arc: ThrowArcPreview = _make_arc()
	assert_false(arc.visible, "must start hidden -- nothing is aiming yet.")
	assert_eq(arc.current_points().size(), 0)


func test_update_arc_shows_it_and_matches_sample_arc() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var origin: Vector3 = Vector3(0.0, 1.0, 0.0)
	var velocity: Vector3 = Vector3(3.0, 4.0, 0.0)

	arc.update_arc(origin, velocity)

	assert_true(arc.visible, "update_arc() must show the arc.")
	var expected: PackedVector3Array = arc.sample_arc(origin, velocity)
	assert_eq(arc.current_points().size(), expected.size())
	for i: int in range(expected.size()):
		assert_true(arc.current_points()[i].is_equal_approx(expected[i]))


func test_clear_arc_hides_it_and_drops_its_points() -> void:
	var arc: ThrowArcPreview = _make_arc()
	arc.update_arc(Vector3.ZERO, Vector3(2.0, 3.0, 0.0))
	assert_true(arc.visible, "fixture: must be visible before clearing.")

	arc.clear_arc()

	assert_false(arc.visible, "clear_arc() must hide the arc.")
	assert_eq(arc.current_points().size(), 0, "clear_arc() must drop the cached points too.")


# --- Integration: PlayerController drives the arc + ghost hint together -----
# (docs/M4_P2_PACKAGES.md P2e: "hidden unless is_aiming_throw() is true";
# owner amendment: "below the thresholds ... show no arc but keep the hint").

func _make_special_controller(fake: FakeMatch) -> Dictionary:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(CUBE_SHAPE)

	var arc: ThrowArcPreview = _make_arc()

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._arc_preview = arc
	controller._active_slot = 0
	controller._match = fake

	return {"ghost": ghost, "arc": arc, "controller": controller}


func _fake_match_with_special(slot_id: int) -> FakeMatch:
	var fake: FakeMatch = FakeMatch.new()
	fake.held_special_by_slot[slot_id] = &"rocket"
	return fake


func test_arc_and_hint_appear_once_a_throwable_drag_starts() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var fixture: Dictionary = _make_special_controller(fake)
	var ghost: GhostPreview = fixture["ghost"]
	var arc: ThrowArcPreview = fixture["arc"]
	var controller: PlayerController = fixture["controller"]

	assert_false(arc.visible, "fixture: not aiming yet.")

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)
	assert_eq(ghost.current_state(), GhostPreview.STATE_THROW, "the ghost must show the throw hint as soon as aiming starts.")
	assert_false(arc.visible, "a still-zero drag must not show an arc (it would place, not throw).")

	# A real drag, well past throw_drag_min_distance_m/throw_drag_min_speed_mps
	# defaults -- same convention test_playercontroller_throw.gd's own
	# test_real_drag_throws_with_velocity_clamped_by_drag_distance uses.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(500.0, 0.0)
	controller._unhandled_input(motion)
	controller._update_throw_aim(1.0 / 60.0)

	assert_true(arc.visible, "a real throwable drag must show the arc.")
	var expected: PackedVector3Array = arc.sample_arc(ghost.global_position, controller.current_throw_velocity())
	assert_eq(arc.current_points().size(), expected.size())
	for i: int in range(expected.size()):
		assert_true(arc.current_points()[i].is_equal_approx(expected[i]), "the arc must use current_throw_velocity()'s own formula.")

	Input.action_release(&"throw_aim")
	controller._update_throw_aim(1.0 / 60.0)

	assert_false(arc.visible, "releasing must clear the arc.")
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID, "releasing must also drop the throw hint.")
	assert_eq(fake.request_throw_calls.size(), 1, "fixture: the drag was real enough to actually throw.")


func test_current_throw_velocity_matches_the_velocity_commit_throw_aim_would_send() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var fixture: Dictionary = _make_special_controller(fake)
	var controller: PlayerController = fixture["controller"]

	Input.action_press(&"throw_aim")
	controller._update_throw_aim(0.05)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(500.0, 0.0)
	controller._unhandled_input(motion)
	controller._update_throw_aim(0.05)

	var live_velocity: Vector3 = controller.current_throw_velocity()

	Input.action_release(&"throw_aim")
	controller._update_throw_aim(0.05)

	assert_eq(fake.request_throw_calls.size(), 1)
	var committed_velocity: Vector3 = fake.request_throw_calls[0]["velocity"]
	assert_true(
		live_velocity.is_equal_approx(committed_velocity),
		"current_throw_velocity() must share the exact formula _commit_throw_aim() uses on release."
	)
