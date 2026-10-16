extends GutTest
## Block's rebound-damping heuristic (run per tick by BlockStepBatch) must scale
## a REAL bounce off something solid, but must NOT scale a special effect's own
## intentional velocity write (a Bean's hop, a Rocket's thrust, a Propeller's
## lift, an explosion's knockback) just because that write also flips a
## falling block's vertical velocity to rising. Real RigidBody3D/Block physics
## throughout -- a real floor, real gravity, real awaited physics frames,
## synchronous free() in after_each() -- an end-to-end physics check rather
## than stubbing Block or PhysicsTuning.
##
## DECISION (tests/unit/blocks/test_block_rebound_physics.gd): every "peak" measured
## below is the vertical velocity at the one physics step the bounce/kick/
## explosion itself lands on (read straight from `linear_velocity.y` after
## `await wait_physics_frames(1)`, so it reflects whatever Block.
## _batch_tick() actually committed for that step), not a position
## traced over several later ticks. the rebound damping only ever touches that
## one step -- everything after is plain gravity acting on whatever velocity
## it left behind -- so this is the exact quantity the fix protects, and it
## sidesteps two sources of noise a position trace hit in an earlier revision
## of this file: Jolt's own contact-correction settling (a heavily damped
## bounce can transiently read a few cm BELOW the analytic rest height while
## the solver resolves residual penetration, which a "track the peak height"
## loop misreads as a negative "peak") and small per-run timing drift in
## exactly which tick samples a slow-moving parabola's apex.
##
## DECISION (tests/unit/blocks/test_block_rebound_physics.gd): (b) and (c) below
## isolate rebound_damping as the ONLY variable between their two runs -- a
## "damped" tuning (config/physics/presets/heavy_bouncy.tres as shipped) and
## an "undamped" copy of that exact same resource with rebound_damping forced
## back to 1.0 -- rather than comparing against config/physics/presets/
## current.tres, which also differs in cube_mass/gravity_multiplier/
## block_bounce and would make a peak mismatch ambiguous (damping bug, or
## just different physics?). Isolating the one field makes a peak difference
## attributable to nothing else.

const CUBE_SHAPE_PATH: String = "res://config/blocks/cube.tres"
const DROP_HEIGHT_M: float = 3.0
## Loose enough to absorb real-physics float noise across two independent
## runs -- including one stray extra/missing physics tick's worth of gravity
## (~0.23 m/s at heavy_bouncy's own gravity_multiplier) if a busy shared
## machine ever delivers one, per this file's own DECISION on seeding a fixed
## pre-kick/pre-explosion velocity rather than counting awaited ticks -- while
## still tight enough that a damping bug (which misses by ~10x on these
## numbers -- see this file's own test bodies) fails outright.
const PEAK_TOLERANCE_MPS: float = 0.3
## A block's own downward velocity the moment (b)/(c) below kick/explode it --
## deliberately a fixed script write, not counted-out free-fall ticks; see
## their own DECISION.
const FALLING_VELOCITY_MPS: float = -2.0
## (d): velocities as multiples of the noise floor, and the tolerance for the committed value.
const FLIP_CLEAR_FLOORS: float = 8.0
const FLIP_FLICKER_FLOORS: float = 0.5
const FLIP_TOLERANCE_MPS: float = 0.02
## The explosion in (c): a 5 m blast peaking at 40 m/s delta-v with a squared
## falloff, capped far above that so the cap never shapes the result.
const BLAST_RADIUS_M: float = 5.0
const BLAST_PEAK_SPEED_MPS: float = 40.0
const BLAST_MAX_DELTA_V_MPS: float = 1000.0
const BLAST_FALLOFF_EXPONENT: float = 2.0

var _nodes: Array[Node3D] = []


func after_each() -> void:
	for node: Node3D in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _floor(top_y: float, bounce: float, offset_x: float) -> StaticBody3D:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(8.0, 1.0, 8.0)
	collision.shape = shape
	floor_body.add_child(collision)
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.bounce = bounce
	floor_body.physics_material_override = material
	add_child(floor_body)  # before global_position: Node3D needs is_inside_tree() to resolve it
	floor_body.global_position = Vector3(offset_x, top_y - 0.5, 0.0)
	_nodes.append(floor_body)
	return floor_body


func _build_block(tuning: PhysicsTuning) -> Block:
	var shape: BlockShape = load(CUBE_SHAPE_PATH)
	var block: Block = BlockFactory.build(shape, tuning)
	add_child(block)
	_nodes.append(block)
	return block


# --- (a) the wiring end-to-end: rebound_damping -> Block._batch_tick() -
# --- -> a real Jolt bounce off a real floor ----------------------------------

## A cube dropped from DROP_HEIGHT_M with heavy_bouncy's own rebound_damping
## (0.3) must rebound at a LOWER, still-positive peak velocity than the
## identical drop with rebound_damping restored to 1.0 -- every other tuning
## number (mass, gravity, block_bounce, friction) held byte-identical between
## the two runs, so only rebound_damping itself can explain any difference.
func test_heavy_bouncy_rebound_peak_is_lower_than_undamped() -> void:
	var damped_tuning: PhysicsTuning = load("res://config/physics/presets/heavy_bouncy.tres")
	var undamped_tuning: PhysicsTuning = damped_tuning.duplicate() as PhysicsTuning
	undamped_tuning.rebound_damping = 1.0

	var undamped_peak: float = await _drop_and_measure_bounce_peak(undamped_tuning, -15.0)
	var damped_peak: float = await _drop_and_measure_bounce_peak(damped_tuning, 15.0)

	assert_gt(undamped_peak, 0.0, "fixture: the undamped drop must actually bounce upward.")
	var ratio: float = damped_peak / undamped_peak
	assert_true(
		ratio < 1.0 and ratio > 0.0,
		(
			"damped rebound velocity (%.4f m/s) should be a lower, still-positive fraction of the "
			+ "undamped rebound velocity (%.4f m/s); ratio=%.4f"
		) % [damped_peak, undamped_peak, ratio]
	)


## Drops a fresh cube from DROP_HEIGHT_M above a real floor and returns the
## vertical velocity at the exact physics step it first bounces (the
## falling-to-rising transition the rebound damping gates on) -- whatever
## Block._batch_tick() actually committed for that step, damped or not.
## `offset_x` keeps this run's floor/block spatially separate from any other
## run already in the tree within the same test method.
func _drop_and_measure_bounce_peak(tuning: PhysicsTuning, offset_x: float) -> float:
	var floor_top_y: float = 0.0
	_floor(floor_top_y, tuning.block_bounce, offset_x)
	var block: Block = _build_block(tuning)
	var half_edge: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	block.global_position = Vector3(offset_x, floor_top_y + half_edge + DROP_HEIGHT_M, 0.0)
	block.linear_velocity = Vector3.ZERO

	var prev_velocity_y: float = 0.0
	var max_ticks: int = int(Engine.physics_ticks_per_second * 5.0)
	for _i: int in range(max_ticks):
		await wait_physics_frames(1)
		var velocity_y: float = block.linear_velocity.y
		if prev_velocity_y < 0.0 and velocity_y > 0.0:
			return velocity_y  # the bounce tick itself: whatever this step committed
		prev_velocity_y = velocity_y
	fail_test("fixture: the block never bounced within %d ticks." % max_ticks)
	return 0.0


# --- (b) a Bean-style kick must not be damped as if it were a bounce --------

## MUST FAIL before the fix: a bare `linear_velocity =` write (what
## JumpingBeanEffect._hop() used to do) reads to _batch_tick() as
## exactly the falling-to-rising transition a real bounce produces, so
## heavy_bouncy's own rebound_damping = 0.3 would scale the kick down to
## ~30% of its intended peak -- kick() marking its own step exempt fixes it.
func test_kick_reaches_the_same_peak_regardless_of_rebound_damping() -> void:
	var damped_tuning: PhysicsTuning = load("res://config/physics/presets/heavy_bouncy.tres")
	var undamped_tuning: PhysicsTuning = damped_tuning.duplicate() as PhysicsTuning
	undamped_tuning.rebound_damping = 1.0

	var undamped_peak: float = await _drop_kick_and_measure_peak(undamped_tuning, -25.0)
	var damped_peak: float = await _drop_kick_and_measure_peak(damped_tuning, 25.0)

	assert_almost_eq(
		damped_peak, undamped_peak, PEAK_TOLERANCE_MPS,
		(
			"block.kick() must reach the same peak velocity whether or not this tuning's "
			+ "rebound_damping < 1 (damped=%.4f m/s, undamped=%.4f m/s)."
		) % [damped_peak, undamped_peak]
	)


## Spawns a fresh cube already in free-fall (no floor -- nothing here needs a
## real bounce, only a genuinely falling body to kick) with "a small downward
## velocity" ('s own bug report), then issues a Bean-style
## block.kick(UP * 6.0) and returns the committed vertical velocity for that
## exact step.
##
## DECISION (tests/unit/blocks/test_block_rebound_physics.gd): the falling velocity
## is a fixed script write (FALLING_VELOCITY_MPS), not several `await
## wait_physics_frames(1)` calls counted out and left to accumulate real
## gravity -- an earlier revision of this file did exactly that (6 ticks) and
## an early diagnostic run on this shared machine caught two otherwise-
## identical runs landing a whole physics tick apart (one run's "6 awaited
## frames" apparently delivered 7 physics steps, not 6 -- the busy-machine
## caveat that makes benchmarks unreliable turns out to bite tick-counted
## fixtures too, not just timed ones). One await (below) still carries that same small risk, but only
## once, not accumulated over six chances -- combined with PEAK_TOLERANCE_MPS
## comfortably covering one stray tick's worth of gravity, this is stable in
## practice while a real rebound_damping bug (which misses by ~10x on these
## numbers) still fails outright.
func _drop_kick_and_measure_peak(tuning: PhysicsTuning, offset_x: float) -> float:
	var block: Block = _build_block(tuning)
	block.global_position = Vector3(offset_x, 20.0, 0.0)
	block.linear_velocity = Vector3(0.0, FALLING_VELOCITY_MPS, 0.0)
	await wait_physics_frames(1)  # lets this land in _prev_step_linear_velocity_y as "falling"
	assert_lt(block.linear_velocity.y, 0.0, "fixture: the block must still be falling when kicked.")

	block.kick(Vector3.UP * 6.0)
	await wait_physics_frames(1)  # the flag is consumed by the very next _batch_tick() step
	return block.linear_velocity.y


# --- (c) explosion knockback on an airborne block must not be damped --------

## The blast's impulse goes through SpecialPhysics.wake_and_impulse(), which
## calls mark_script_kick() on every Block it hits; without that mark an
## airborne block's own knockback flips its vertical velocity exactly like a
## real bounce and is scaled by rebound_damping on top of the blast's own
## falloff, the same way (b) guards for kick().
func test_explosion_reaches_the_same_peak_regardless_of_rebound_damping() -> void:
	var damped_tuning: PhysicsTuning = load("res://config/physics/presets/heavy_bouncy.tres")
	var undamped_tuning: PhysicsTuning = damped_tuning.duplicate() as PhysicsTuning
	undamped_tuning.rebound_damping = 1.0

	var undamped_peak: float = await _drop_explode_and_measure_peak(undamped_tuning, -35.0)
	var damped_peak: float = await _drop_explode_and_measure_peak(damped_tuning, 35.0)

	assert_gt(undamped_peak, 0.0, "fixture: the blast must push the block upward.")
	assert_almost_eq(
		damped_peak, undamped_peak, PEAK_TOLERANCE_MPS,
		(
			"an explosion's own knockback must reach the same peak velocity whether or not this "
			+ "tuning's rebound_damping < 1 (damped=%.4f m/s, undamped=%.4f m/s)."
		) % [damped_peak, undamped_peak]
	)


## Spawns a fresh cube already in free-fall with a genuine downward velocity
## (see _drop_kick_and_measure_peak()'s own DECISION for why this is a fixed
## script write, not counted-out ticks), then detonates an ExplosionFx.blast()
## centred directly beneath it (a real PhysicsDirectSpaceState3D query;
## upward_bias 0 keeps it a pure outward/upward push) and returns the committed
## vertical velocity for that exact step.
func _drop_explode_and_measure_peak(tuning: PhysicsTuning, offset_x: float) -> float:
	var block: Block = _build_block(tuning)
	block.global_position = Vector3(offset_x, 20.0, 0.0)
	block.linear_velocity = Vector3(0.0, FALLING_VELOCITY_MPS, 0.0)
	await wait_physics_frames(1)  # lets this land in _prev_step_linear_velocity_y as "falling"
	assert_lt(block.linear_velocity.y, 0.0, "fixture: the block must still be falling when it explodes.")

	var center: Vector3 = block.global_position - Vector3(0.0, 1.0, 0.0)
	var blast_tuning: ExplosionTuning = ExplosionTuning.new()
	blast_tuning.radius_m = BLAST_RADIUS_M
	blast_tuning.peak_speed_mps = BLAST_PEAK_SPEED_MPS
	blast_tuning.max_delta_v_mps = BLAST_MAX_DELTA_V_MPS
	blast_tuning.falloff_exponent = BLAST_FALLOFF_EXPONENT
	blast_tuning.upward_bias = 0.0
	var no_exclude: Array[RID] = []
	ExplosionFx.blast(get_viewport().world_3d.direct_space_state, center, blast_tuning, no_exclude)
	await wait_physics_frames(1)  # the impulse reaches linear_velocity, and the flag is consumed
	return block.linear_velocity.y


# --- (d) the noise floor: a resting stack's solver flicker is not a bounce ---

## Regression for the bench_tower collapse: a sign flip that never clears
## the noise floor (PhysicsTuning.sleep_linear_threshold) on both sides is solver
## jitter, not a bounce, and must not be scaled however small rebound_damping is.
## The control flip (clearly falling to clearly rising) with the same
## rebound_damping = 0.0 is scaled to a standstill, so the fixture is sensitive.
func test_flicker_within_the_noise_floor_is_not_damped_but_a_real_bounce_is() -> void:
	var tuning: PhysicsTuning = (load("res://config/physics/presets/heavy_bouncy.tres") as PhysicsTuning).duplicate() as PhysicsTuning
	tuning.rebound_damping = 0.0
	tuning.gravity_multiplier = 0.0
	tuning.block_linear_damp = 0.0
	var floor_mps: float = tuning.sleep_linear_threshold

	var bounce_y: float = await _flip_and_measure(tuning, -FLIP_CLEAR_FLOORS * floor_mps, FLIP_CLEAR_FLOORS * floor_mps, -45.0)
	assert_almost_eq(bounce_y, 0.0, FLIP_TOLERANCE_MPS, "control: a clear falling-to-rising flip is scaled by rebound_damping = 0.")

	var flicker_y: float = await _flip_and_measure(tuning, -FLIP_FLICKER_FLOORS * floor_mps, FLIP_FLICKER_FLOORS * floor_mps, -55.0)
	assert_almost_eq(flicker_y, FLIP_FLICKER_FLOORS * floor_mps, FLIP_TOLERANCE_MPS, "a flip inside the noise floor on both sides passes through.")

	var prev_only_y: float = await _flip_and_measure(tuning, -FLIP_CLEAR_FLOORS * floor_mps, FLIP_FLICKER_FLOORS * floor_mps, -65.0)
	assert_almost_eq(prev_only_y, FLIP_FLICKER_FLOORS * floor_mps, FLIP_TOLERANCE_MPS, "rising only within the floor is not a bounce.")

	var current_only_y: float = await _flip_and_measure(tuning, -FLIP_FLICKER_FLOORS * floor_mps, FLIP_CLEAR_FLOORS * floor_mps, -75.0)
	assert_almost_eq(current_only_y, FLIP_CLEAR_FLOORS * floor_mps, FLIP_TOLERANCE_MPS, "falling only within the floor is not a bounce.")


## A gravity-free, undamped cube given `prev_y`, then (one physics step later)
## `next_y` by plain script writes; returns the vertical velocity committed for
## the step after the second write.
func _flip_and_measure(tuning: PhysicsTuning, prev_y: float, next_y: float, offset_x: float) -> float:
	var block: Block = _build_block(tuning)
	block.global_position = Vector3(offset_x, 20.0, 0.0)
	block.linear_velocity = Vector3(0.0, prev_y, 0.0)
	await wait_physics_frames(1)  # lets this land in _prev_step_linear_velocity_y
	block.linear_velocity = Vector3(0.0, next_y, 0.0)
	await wait_physics_frames(1)
	return block.linear_velocity.y
