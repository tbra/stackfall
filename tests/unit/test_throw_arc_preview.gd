extends GutTest
## game/ThrowArcPreview.gd coverage (M4 P2e, docs/M4_P2_PACKAGES.md P2e, spec
## 2.5 "Throw (specials only)"): the arc preview's own pure ballistic sampler
## (sample_arc()) matches the closed-form projectile formula the brief
## specifies, and the visibility lifecycle (hidden until update_arc(), gone
## again after clear_arc()) that game/PlayerController.gd's
## _drive_throw_visuals() drives every frame.
##
## Bontago-1en.25 (feedback/throw-arc.png, "arc leaves the screen while
## rising") adds the landing-cutoff coverage below: sample_arc()'s optional
## `field` argument stops the arc at the disc's own surface (or the floor
## below it once the throw has flown past the rim) instead of always
## sampling out to GhostTuning.throw_arc_max_time_s, which now reads only as
## a safety cap for a throw that never reaches any landing height.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")


func _make_arc() -> ThrowArcPreview:
	var arc: ThrowArcPreview = autofree(ThrowArcPreview.new())
	add_child_autofree(arc)
	return arc


## A real Field, same fixture pattern test_tuning_panel.gd's own territory-
## visuals tests use (autofree + add_child_autofree so _ready() builds a real,
## configured disk) -- needed here for the landing-cutoff tests below, since
## sample_arc()/update_arc()'s own landing height comes from Field.surface_y()
## /disk_local_from_world()/map_definition().field_radius, not from a plain
## number this test file could fake without a real Field.
func _make_field() -> Field:
	var field: Field = autofree(Field.new())
	add_child_autofree(field)
	return field


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


# --- Landing cutoff (Bontago-1en.25, feedback/throw-arc.png) -----------------
# "the arc leaves the screen while rising" -- the arc must stop the moment it
# reaches ground/disc contact, not always sample out to throw_arc_max_time_s.

func test_landing_arc_ends_at_the_disc_surface_and_never_dips_below_it_early() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var field: Field = _make_field()
	var origin: Vector3 = Vector3(0.0, 2.0, 0.0)
	var velocity: Vector3 = Vector3(6.0, 8.0, 0.0)

	var points: PackedVector3Array = arc.sample_arc(origin, velocity, field)

	assert_true(points.size() >= 2, "fixture: must actually sample something.")
	assert_true(points.size() <= arc.ghost_tuning.throw_arc_sample_count + 1, "must never exceed the safety-cap sample count.")
	var landing_y: float = field.surface_y()
	for i: int in range(points.size() - 1):
		assert_true(points[i].y > landing_y - 0.001, "sample %d dipped below the landing height before the arc actually ended." % i)
	assert_almost_eq(points[points.size() - 1].y, landing_y, 0.01, "the arc's last point must sit at the disc's own surface height.")


func test_hard_throw_has_more_samples_than_a_soft_throw_but_both_land() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var field: Field = _make_field()
	var origin: Vector3 = Vector3(0.0, 1.0, 0.0)
	var direction: Vector3 = Vector3(1.0, 1.0, 0.0).normalized()

	var soft_points: PackedVector3Array = arc.sample_arc(origin, direction * 3.0, field)
	var hard_points: PackedVector3Array = arc.sample_arc(origin, direction * 18.0, field)

	assert_true(
		hard_points.size() > soft_points.size(),
		"a harder throw hangs in the air longer, so its preview must sample more points before it lands (soft=%d, hard=%d)." % [soft_points.size(), hard_points.size()]
	)
	var landing_y: float = field.surface_y()
	assert_almost_eq(soft_points[soft_points.size() - 1].y, landing_y, 0.01, "the soft throw must still end at the landing height.")
	assert_almost_eq(hard_points[hard_points.size() - 1].y, landing_y, 0.01, "the hard throw must still end at the landing height.")


func test_off_disc_throw_falls_to_the_floor_below_the_disc_instead_of_the_surface() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var field: Field = _make_field()
	var radius: float = field.map_definition().field_radius
	var origin: Vector3 = Vector3(radius + 20.0, 1.0, 0.0)
	var velocity: Vector3 = Vector3(1.0, 2.0, 0.0)

	var points: PackedVector3Array = arc.sample_arc(origin, velocity, field)

	var expected_floor: float = field.surface_y() - arc.ghost_tuning.throw_arc_floor_below_disc_m
	assert_almost_eq(
		points[points.size() - 1].y, expected_floor, 0.01,
		"a throw whose XZ is past the disc's own rim must land on the floor below the disc, not the disc's own surface height."
	)


func test_safety_cap_still_applies_when_a_velocity_never_lands() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var field: Field = _make_field()
	var saved_enabled: bool = arc.ghost_tuning.throw_arc_floor_enabled
	arc.ghost_tuning.throw_arc_floor_enabled = false
	var radius: float = field.map_definition().field_radius
	# Off-disc, and the floor below the disc is disabled above -- this throw
	# never reaches any landing height at all (config/GhostTuning.gd's
	# throw_arc_floor_enabled doc comment), so the safety cap alone must
	# still bound sample_arc()'s own loop.
	var origin: Vector3 = Vector3(radius + 20.0, 1.0, 0.0)
	var velocity: Vector3 = Vector3(1.0, 2.0, 0.0)

	var points: PackedVector3Array = arc.sample_arc(origin, velocity, field)

	arc.ghost_tuning.throw_arc_floor_enabled = saved_enabled
	assert_eq(
		points.size(), arc.ghost_tuning.throw_arc_sample_count + 1,
		"with no floor and no disc under it, the safety cap (throw_arc_max_time_s) must still bound the sample, not an unbounded fall."
	)


func test_no_field_wired_keeps_the_pre_landing_fixed_sample_count() -> void:
	# The bare-unit-test/no-active-match case (field == null, the default) --
	# game/PlayerController.gd's own _drive_throw_visuals() passes Match.field(),
	# which is null in every test here that never wires a real Field to Match.
	var arc: ThrowArcPreview = _make_arc()
	var points: PackedVector3Array = arc.sample_arc(Vector3(0.0, 2.0, 0.0), Vector3(4.0, 6.0, -2.0))
	assert_eq(points.size(), arc.ghost_tuning.throw_arc_sample_count + 1, "no Field wired must mean no landing cutoff at all, only the safety cap.")


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
	fake.held_special_by_slot[slot_id] = &"bomb"
	return fake


func test_arc_is_shown_automatically_while_a_throwable_is_held_without_lt() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var fixture: Dictionary = _make_special_controller(fake)
	var arc: ThrowArcPreview = fixture["arc"]
	var controller: PlayerController = fixture["controller"]

	assert_false(arc.visible, "fixture: nothing drawn before the first frame")

	controller._update_throw_aim(1.0 / 60.0)  # no LT / throw_aim press anywhere

	assert_true(arc.visible, "a held throwable shows the arc automatically")
	var preview: Dictionary = controller.gift_launch_preview()
	var expected: PackedVector3Array = arc.sample_arc(
		preview["origin"] as Vector3, preview["velocity"] as Vector3, Match.field(), float(preview["gravity_scale"])
	)
	assert_eq(arc.current_points().size(), expected.size())
	for i: int in range(expected.size()):
		assert_true(arc.current_points()[i].is_equal_approx(expected[i]), "the arc is the host's GiftAim launch")


func test_arc_follows_the_camera_forward() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var fixture: Dictionary = _make_special_controller(fake)
	var arc: ThrowArcPreview = fixture["arc"]
	var controller: PlayerController = fixture["controller"]
	controller._update_throw_aim(1.0 / 60.0)
	var first: Vector3 = arc.current_points()[arc.current_points().size() - 1]
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	rig._yaw = PI * 0.5
	controller._camera_rig = rig
	controller._update_throw_aim(1.0 / 60.0)
	var second: Vector3 = arc.current_points()[arc.current_points().size() - 1]
	assert_false(first.is_equal_approx(second), "moving the camera moves the arc, nothing else needed")


func test_arc_hides_when_the_gift_is_gone() -> void:
	var fake: FakeMatch = _fake_match_with_special(0)
	var fixture: Dictionary = _make_special_controller(fake)
	var arc: ThrowArcPreview = fixture["arc"]
	var controller: PlayerController = fixture["controller"]
	controller._update_throw_aim(1.0 / 60.0)
	assert_true(arc.visible)
	fake.held_special_by_slot.erase(0)
	controller._update_throw_aim(1.0 / 60.0)
	assert_false(arc.visible, "an ordinary piece has no arc")


func test_rocket_arc_is_straight_gravity_free() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var points: PackedVector3Array = arc.sample_arc(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 10.0, 10.0), null, 0.0)
	var direction: Vector3 = (points[1] - points[0]).normalized()
	for i: int in range(1, points.size()):
		assert_true((points[i] - points[i - 1]).normalized().is_equal_approx(direction), "straight line, no gravity")
