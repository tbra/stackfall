extends GutTest
## game/player/ThrowArcPreview.gd coverage (spec
## 2.5 "Throw (specials only)"): the arc preview's own pure ballistic sampler
## (sample_arc()) matches the closed-form projectile formula the brief
## specifies, and the visibility lifecycle (hidden until update_arc(), gone
## again after clear_arc()) that game/player/PlayerController.gd's
## _drive_throw_visuals() drives every frame.
##
## (feedback/throw-arc.png, "arc leaves the screen while
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
	# never reaches any landing height at all (config/blocks/tuning/GhostTuning.gd's
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


func test_rocket_arc_is_straight_gravity_free() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var points: PackedVector3Array = arc.sample_arc(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 10.0, 10.0), null, 0.0)
	var direction: Vector3 = (points[1] - points[0]).normalized()
	for i: int in range(1, points.size()):
		assert_true((points[i] - points[i - 1]).normalized().is_equal_approx(direction), "straight line, no gravity")


# --- Landing-zone ring -----------------------------------

func _ring_mesh_is_flat_annulus(ring: MeshInstance3D, outer: float, width: float) -> void:
	var mesh: ArrayMesh = ring.mesh as ArrayMesh
	assert_not_null(mesh, "the end marker must be an ArrayMesh ring, not a sphere.")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_r: float = 0.0
	var min_r: float = INF
	for v: Vector3 in verts:
		assert_almost_eq(v.y, 0.0, 0.0001, "ring must be flat.")
		max_r = maxf(max_r, Vector2(v.x, v.z).length())
		min_r = minf(min_r, Vector2(v.x, v.z).length())
	assert_almost_eq(max_r, outer, 0.001, "outer radius equals config.")
	assert_almost_eq(min_r, outer - width, 0.001, "inner radius = outer - width.")


func test_end_ring_sits_at_landing_point_flat_field() -> void:
	var arc: ThrowArcPreview = _make_arc()
	var field: Field = _make_field()
	arc.update_arc(Vector3(0.0, 2.0, 0.0), Vector3(6.0, 8.0, 0.0), field)
	var ring: MeshInstance3D = arc.end_ring()
	assert_true(ring.visible)
	var end: Vector3 = arc.current_points()[arc.current_points().size() - 1]
	var lift: float = arc.ghost_tuning.throw_arc_end_marker_lift
	assert_true(ring.global_position.distance_to(end) <= 0.01 + lift)
	assert_true(ring.global_transform.basis.y.angle_to(Vector3.UP) < deg_to_rad(2.0))
	_ring_mesh_is_flat_annulus(ring, arc.ghost_tuning.throw_arc_end_marker_radius, arc.ghost_tuning.throw_arc_end_marker_width)
	arc.clear_arc()
	assert_false(ring.visible)

