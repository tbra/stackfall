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


## The ribbon's centreline as drawn: the ImmediateMesh strip holds a left/right vertex pair per sample
## point, so the midpoint of each pair is the sample.
func _drawn_points(arc: ThrowArcPreview) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for child: Node in arc.get_children():
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance == null or not instance.mesh is ImmediateMesh or instance.mesh.get_surface_count() == 0:
			continue
		var verts: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i: int in range(0, verts.size() - 1, 2):
			points.append((verts[i] + verts[i + 1]) * 0.5)
	return points


## The landing-zone ring node: the arc's MeshInstance3D child that is not the ribbon.
func _end_ring(arc: ThrowArcPreview) -> MeshInstance3D:
	for child: Node in arc.get_children():
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance != null and not instance.mesh is ImmediateMesh:
			return instance
	return null


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
	assert_eq(_drawn_points(arc).size(), expected.size())
	for i: int in range(expected.size()):
		assert_true(_drawn_points(arc)[i].is_equal_approx(expected[i]))


func _make_special_controller(context: FakeMatchContext) -> Dictionary:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(CUBE_SHAPE)
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate() as CameraRig
	add_child_autofree(rig)

	var arc: ThrowArcPreview = _make_arc()

	var controller: PlayerController = autofree(PlayerController.new())
	controller.match_context = context
	controller.ghost_path = ghost.get_path()
	controller.arc_preview_path = arc.get_path()
	controller.set_acting_slot(0)
	add_child_autofree(controller)
	controller.set_camera_rig(rig)

	return {"ghost": ghost, "arc": arc, "controller": controller}


func _context_holding(special_id: StringName) -> FakeMatchContext:
	var context: FakeMatchContext = FakeMatchContext.new()
	context.held_special_by_slot[0] = special_id
	return context


func test_arc_is_shown_automatically_while_a_throwable_is_held_without_lt() -> void:
	var context: FakeMatchContext = _context_holding(&"bomb")
	var fixture: Dictionary = _make_special_controller(context)
	var arc: ThrowArcPreview = fixture["arc"]
	var controller: PlayerController = fixture["controller"]

	assert_false(arc.visible, "fixture: nothing drawn before the first frame")

	await wait_process_frames(2)  # the engine's own _process; no LT / throw_aim press anywhere

	assert_true(arc.visible, "a held throwable shows the arc automatically")
	var preview: Dictionary = controller.gift_launch_preview()
	# The context has no field, so the arc lands on no disc.
	var expected: PackedVector3Array = arc.sample_arc(
		preview["origin"] as Vector3, preview["velocity"] as Vector3, null, float(preview["gravity_scale"])
	)
	assert_eq(_drawn_points(arc).size(), expected.size())
	for i: int in range(expected.size()):
		assert_true(_drawn_points(arc)[i].is_equal_approx(expected[i]), "the arc is the host's GiftAim launch")


func test_the_arc_is_cleared_when_the_gift_is_gone() -> void:
	var context: FakeMatchContext = _context_holding(&"bomb")
	var fixture: Dictionary = _make_special_controller(context)
	var arc: ThrowArcPreview = fixture["arc"]
	await wait_process_frames(2)
	assert_true(arc.visible, "fixture: the arc shows while the gift is held")

	context.held_special_by_slot[0] = &""
	await wait_process_frames(2)

	assert_false(arc.visible, "no gift in hand, no arc")


func test_a_rocket_draws_no_arc_and_an_eliminated_slot_draws_none() -> void:
	var rocket: Dictionary = _make_special_controller(_context_holding(&"rocket"))
	await wait_process_frames(2)
	assert_false((rocket["arc"] as ThrowArcPreview).visible, "Rocket draws no arc")

	var eliminated_context: FakeMatchContext = _context_holding(&"bomb")
	var dead: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	dead.home_flag_alive = false
	eliminated_context.slot_by_id[0] = dead
	var eliminated: Dictionary = _make_special_controller(eliminated_context)
	await wait_process_frames(2)
	assert_false((eliminated["arc"] as ThrowArcPreview).visible, "an eliminated slot has no arc")


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
	var ring: MeshInstance3D = _end_ring(arc)
	assert_true(ring.visible)
	var end: Vector3 = _drawn_points(arc)[_drawn_points(arc).size() - 1]
	var lift: float = arc.ghost_tuning.throw_arc_end_marker_lift
	assert_true(ring.global_position.distance_to(end) <= 0.01 + lift)
	assert_true(ring.global_transform.basis.y.angle_to(Vector3.UP) < deg_to_rad(2.0))
	_ring_mesh_is_flat_annulus(ring, arc.ghost_tuning.throw_arc_end_marker_radius, arc.ghost_tuning.throw_arc_end_marker_width)
	arc.clear_arc()
	assert_false(ring.visible)

