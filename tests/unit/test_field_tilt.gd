extends GutTest
## Field's SPECIALS_ONLY tilt controller (spec 2.1, 2.7, 3.5): the
## critically damped spring on Field._tilt, its max_tilt_deg clamp, and the
## AnimatableBody3D conversion (docs/M4_PLAN.md P0b).
##
## A deliberately tiny disk, same pattern test_field_cells.gd already uses:
## small enough that a real physics settle (the one test here that needs one)
## runs in a blink.

## PhysicsCallDriver (tests/unit/support/PhysicsCallDriver.gd) gets a call
## into a genuine physics step, needed for apply_replicated_pose():
## game/Field.gd's own DECISION on set_tilt_enabled() documents that once
## sync_to_physics is true (which it is, the moment set_tilt_enabled(true)
## runs), Godot's kinematic body only accepts transform writes made through
## the physics step -- calling field.apply_replicated_pose() as a bare
## synchronous test call (the same way
## test_coordinate_round_trip_at_a_synthetic_nonzero_tilt() below calls
## _apply_tilt_transform() directly) silently reverts to the last
## physics-synced transform, exactly the failure mode that DECISION describes
## for a direct field.global_position write. Wrapping the call in a node the
## SceneTree really ticks (await wait_physics_frames(1) below) is the same
## fix test_a_resting_block_stays_at_its_disk_local_point_during_a_slow_tilt()
## already relies on for its own tilt-driven physics. Review NIT
## (Bontago-1en.27): shared with tests/unit/test_snapshot_sync.gd, which
## previously carried an identical inner class of its own.
func _drive_during_physics(callable: Callable) -> void:
	var driver: PhysicsCallDriver = PhysicsCallDriver.new()
	driver.callable = callable
	add_child_autofree(driver)
	await wait_physics_frames(1)


const SETTLE_FRAMES: int = 90
## One manual _update_tilt() step at a time is a real 1/60 s physics tick's
## worth of the spring's own math -- no engine frame needed for the tests
## that only care about the ODE, so many "seconds" of decay run instantly.
const TICK: float = 1.0 / 60.0


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_tilt"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


func _make_field() -> Field:
	var field: Field = Field.new()
	field.map_def = _small_map()
	add_child_autofree(field)
	return field


# --- apply_tilt_impulse moves the tilt vector, then it decays -------------

func test_apply_tilt_impulse_moves_the_tilt_vector() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	assert_eq(field.tilt_vector(), Vector2.ZERO, "fixture: level before any impulse")

	field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)
	field._update_tilt(TICK)

	assert_ne(field.tilt_vector(), Vector2.ZERO, "one impulse moves the tilt vector off level")


func test_tilt_decays_back_toward_level_over_the_return_time_constant() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)

	# DECISION (tests/unit/test_field_tilt.gd): a critically damped system
	# given only an initial velocity (no initial displacement, exactly what
	# apply_tilt_impulse produces) does not decay from the first tick -- its
	# analytic impulse response v0 * t * e^(-t/tau) *rises* until t = tau,
	# then decays. So "peak" is tracked over the first 2 * return_time_constant_s
	# (comfortably past that t = tau maximum), not read one tick after the
	# impulse landed.
	var to_peak_window: int = int(field.tilt_tuning.return_time_constant_s * 2.0 / TICK)
	var peak: float = 0.0
	for _i: int in range(to_peak_window):
		field._update_tilt(TICK)
		peak = maxf(peak, field.tilt_vector().length())
	assert_gt(peak, 0.0, "fixture: the impulse produced a real peak to decay from")

	# A further 6x the tuning's return_time_constant_s (t = 8*tau total):
	# e^-8 ~= 0.00034 of the analytic amplitude, comfortably "decayed toward
	# level" relative to the tracked peak.
	var remaining_steps: int = int(field.tilt_tuning.return_time_constant_s * 6.0 / TICK)
	for _i: int in range(remaining_steps):
		field._update_tilt(TICK)

	assert_lt(
		field.tilt_vector().length(), peak * 0.05,
		"the tilt vector eases back toward level within a few return_time_constant_s"
	)


# --- max_tilt_deg clamp -----------------------------------------------------

func test_tilt_is_clamped_regardless_of_a_single_impulses_size() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	field.apply_tilt_impulse(Vector2(1.0, 0.0), 1.0e6)
	field._update_tilt(TICK)

	assert_lte(
		rad_to_deg(field.tilt_vector().length()), field.tilt_tuning.max_tilt_deg + 0.001,
		"an oversized single impulse still cannot exceed max_tilt_deg"
	)


func test_tilt_is_clamped_regardless_of_how_many_impulses_land_in_one_frame() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	for _i: int in range(50):
		field.apply_tilt_impulse(Vector2(0.0, 1.0), 10.0)
	field._update_tilt(TICK)

	assert_lte(
		rad_to_deg(field.tilt_vector().length()), field.tilt_tuning.max_tilt_deg + 0.001,
		"many impulses stacked in one frame still cannot exceed max_tilt_deg"
	)

	# The clamp has to keep holding as the spring keeps integrating with the
	# huge left-over velocity these impulses gave it, not just on the one
	# frame the impulses landed.
	for _i: int in range(30):
		field._update_tilt(TICK)
		assert_lte(
			rad_to_deg(field.tilt_vector().length()), field.tilt_tuning.max_tilt_deg + 0.001
		)


# --- disk_local_from_world / world_from_disk_local round-trip at tilt ------

func test_coordinate_round_trip_at_a_synthetic_nonzero_tilt() -> void:
	var field: Field = _make_field()
	# A synthetic tilt set directly (not by waiting out the spring), per the
	# plan's own test list. set_tilt_enabled() is not required for this --
	# the conversion functions only read the node's live transform.
	field._tilt = Vector2(deg_to_rad(7.0), deg_to_rad(-4.0))
	field._apply_tilt_transform()

	var local: Vector2 = Vector2(2.0, -1.5)
	var world: Vector3 = field.world_from_disk_local(local, 3.0)
	var back: Vector2 = field.disk_local_from_world(world)

	assert_almost_eq(back.x, local.x, 0.0001)
	assert_almost_eq(back.y, local.y, 0.0001)
	# The tilt is real, not a no-op: a flat conversion would put world.y at
	# exactly 3.0 (the requested height above a level disk).
	assert_ne(world.y, 3.0)


# --- tilt disabled: nothing moves -------------------------------------------

func test_tilt_disabled_leaves_the_disk_untouched() -> void:
	var field: Field = _make_field()
	var identity: Basis = field.transform.basis
	field.apply_tilt_impulse(Vector2(1.0, 0.0), 5.0)
	for _i: int in range(10):
		field._physics_process(TICK)

	assert_eq(field.tilt_vector(), Vector2.ZERO, "a disabled controller never accumulates a tilt")
	assert_true(
		field.transform.basis.is_equal_approx(identity),
		"a disabled controller never rotates the disk"
	)


# --- sync_to_physics carries a resting block along --------------------------

## Bontago M4 P0b: "a block resting on the disk at a fixed disk-local point
## stays at that point ... across several frames of a slow tilt change,
## proving sync_to_physics actually carries it." A modest impulse (peak well
## under max_tilt_deg) keeps the per-tick rotation small -- "slow" relative to
## the 1/60 s physics step -- while still exercising the real engine's
## kinematic sync, not a hand-stepped ODE.
func test_a_resting_block_stays_at_its_disk_local_point_during_a_slow_tilt() -> void:
	var field: Field = _make_field()
	var body: RigidBody3D = BlockFactory.build(load("res://config/blocks/cube.tres"), field.tuning)
	field.get_parent().add_child(body)
	autofree(body)
	body.global_position = Vector3(0.5, 2.0, 0.5)
	await wait_physics_frames(SETTLE_FRAMES)
	# Same fixture pattern as tests/unit/test_field_cells.gd: force sleep
	# rather than trust the engine's own sleep timer landed within
	# SETTLE_FRAMES, so the tilt phase below starts from a clean rest state.
	body.sleeping = true

	var start_local: Vector2 = field.disk_local_from_world(body.global_position)

	field.set_tilt_enabled(true)
	field.apply_tilt_impulse(Vector2(1.0, 0.3), 0.05)

	for _i: int in range(30):
		await wait_physics_frames(1)
		var now_local: Vector2 = field.disk_local_from_world(body.global_position)
		assert_almost_eq(
			now_local.x, start_local.x, 0.05,
			"the block's disk-local x should not drift as the disk tilts under it"
		)
		assert_almost_eq(
			now_local.y, start_local.y, 0.05,
			"the block's disk-local z should not drift as the disk tilts under it"
		)

	assert_gt(
		field.tilt_vector().length(), 0.0,
		"fixture: the disk actually tilted during the sampled frames"
	)


# --- apply_replicated_pose (Bontago-1en.27: a client's mirror) --------------
#
# net/SnapshotSync.gd calls this on a client's Field once per client_tick(),
# never on a host's -- these tests exercise Field's own contract directly, at
# the same level test_apply_tilt_impulse_moves_the_tilt_vector() etc. already
# do above, without needing a live SnapshotSync/interpolator.

func test_apply_replicated_pose_sets_the_transform_and_tilt_vector() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	var tilt_vector: Vector2 = Vector2(0.1, -0.05)
	var tilt_quat: Quaternion = (
		Basis(Vector3.RIGHT, tilt_vector.x) * Basis(Vector3.BACK, tilt_vector.y)
	).get_rotation_quaternion()
	var offset: Vector3 = Vector3(0.2, 0.0, -0.3)

	await _drive_during_physics(func() -> void: field.apply_replicated_pose(offset, tilt_quat))

	assert_lt(
		(field.global_transform.origin - offset).length(), 0.001,
		"the replicated offset lands on the transform"
	)
	assert_lt(
		field.global_transform.basis.get_rotation_quaternion().angle_to(tilt_quat),
		deg_to_rad(0.01),
		"the replicated tilt lands on the transform"
	)
	assert_almost_eq(
		field.tilt_vector().x, tilt_vector.x, 0.001,
		"tilt_vector() reflects the replicated tilt's X component"
	)
	assert_almost_eq(
		field.tilt_vector().y, tilt_vector.y, 0.001,
		"tilt_vector() reflects the replicated tilt's Y component"
	)


func test_apply_replicated_pose_suppresses_the_local_spring_and_impulses() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	var tilt_quat: Quaternion = Quaternion(Vector3.RIGHT, 0.08)
	await _drive_during_physics(func() -> void: field.apply_replicated_pose(Vector3.ZERO, tilt_quat))
	var mirrored_transform: Transform3D = field.global_transform

	# A stray apply_tilt_impulse() (never actually called on a client's own
	# Field in real play, since specials simulate host-side only) must not
	# make the mirrored pose drift once _physics_process() runs again --
	# real physics frames this time, since _mirrored is now sticky state and
	# Field's own _physics_process() (dispatched for real by the engine
	# below) is exactly what must skip _update_tilt().
	field.apply_tilt_impulse(Vector2(1.0, 0.0), 5.0)
	await wait_physics_frames(10)

	assert_lt(
		(field.global_transform.origin - mirrored_transform.origin).length(), 0.0001,
		"a mirrored Field's origin does not drift on its own"
	)
	assert_lt(
		field.global_transform.basis.get_rotation_quaternion().angle_to(
			mirrored_transform.basis.get_rotation_quaternion()
		),
		deg_to_rad(0.001),
		"a mirrored Field's tilt does not drift on its own, even with a queued impulse"
	)


func test_clear_match_state_ends_mirroring_and_levels_the_disc() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	await _drive_during_physics(
		func() -> void: field.apply_replicated_pose(Vector3(0.0, 0.0, 0.0), Quaternion(Vector3.RIGHT, 0.1))
	)
	assert_gt(field.tilt_vector().length(), 0.0, "fixture: mirrored to a non-level tilt")

	# clear_match_state() writes `transform` too (_apply_tilt_transform()),
	# under the same sync_to_physics constraint apply_replicated_pose() is
	# under, so it needs the same real-physics-frame treatment to check the
	# transform it left behind.
	await _drive_during_physics(func() -> void: field.clear_match_state())

	assert_lt(
		field.global_transform.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY),
		deg_to_rad(0.01),
		"clear_match_state levels the disc"
	)
	assert_eq(field.tilt_vector(), Vector2.ZERO, "clear_match_state zeroes the tilt vector")
	assert_false(field._mirrored, "clear_match_state ends mirroring")

	# Mirroring is over: the local spring must be able to move the disc again
	# (a rehost, or a fresh match starting on the same persistent Field).
	field.apply_tilt_impulse(Vector2(1.0, 0.0), 5.0)
	await wait_physics_frames(10)
	assert_gt(
		field.tilt_vector().length(), 0.0,
		"the local spring resumes moving the disc once mirroring has ended"
	)


func test_a_fresh_field_is_not_mirrored_and_ticks_its_own_spring() -> void:
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)
	field._physics_process(TICK)
	assert_gt(
		field.tilt_vector().length(), 0.0,
		"a Field that never mirrored a replicated pose still runs its own spring (the host path)"
	)
