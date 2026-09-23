extends GutTest
## PropellerEffect (spec 2.6 "stands where it lands, then lifts itself and
## blows"; docs/M4_SPECIALS_PACKAGES.md's P5-PROPELLER package, which
## supersedes spec's older "pushes nearby blocks sideways" framing per that
## doc's own note). Mirrors tests/unit/test_earthquake_effect.gd's/
## test_anvil_effect.gd's fixture shapes: a stub Block + real SpecialBehavior
## (no physics simulation) for the settle-gated timed pattern, and a real,
## tiny Field (via Match.register_world()) with a SpyField subclass to record
## exactly what reaches Field.apply_tilt_impulse() without depending on the
## spring's own integration math (already covered by test_field_tilt.gd).

const TICK: float = 1.0 / 60.0


# --- shared stub-Block/def/behavior fixture (no physics, no scene tree) -----

func _make_block(position: Vector3 = Vector3.ZERO) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = 1.0
	block.linear_velocity = Vector3.ZERO
	block.sleeping = false
	return block


func _make_def(effect: PropellerEffect, arm_delay: float = 0.0) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"propeller"
	def.arm_delay = arm_delay
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	return def


func _make_behavior(block: Block, def: SpecialDef) -> SpecialBehavior:
	var tuning: SpecialTuning = SpecialTuning.new()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, tuning)
	return behavior


# --- SpyField/small-map fixture for direction/magnitude assertions ----------

## Records exactly what reaches Field.apply_tilt_impulse() -- same shape as
## test_anvil_effect.gd's SpyField.
class SpyField:
	extends Field
	var call_count: int = 0
	var last_direction: Vector2 = Vector2.ZERO
	var last_magnitude: float = 0.0

	func apply_tilt_impulse(direction: Vector2, magnitude: float) -> void:
		call_count += 1
		last_direction = direction
		last_magnitude = magnitude


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_propeller"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


var _blocks_root: Node3D = null
var _registry: BlockRegistry = null


func after_each() -> void:
	Match.abort_match()


func _register_spy_field() -> SpyField:
	var field: SpyField = autofree(SpyField.new())
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)
	return field


# --- inert while airborne ----------------------------------------------------

func test_inert_while_airborne_no_velocity_change_no_tilt_impulse() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	effect.lift_speed = 4.0
	effect.tilt_strength = 0.3
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	block.sleeping = false  # still airborne
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)  # arms this tick (arm_delay == 0.0), still airborne

	assert_eq(block.linear_velocity.y, 0.0, "must not lift while airborne")
	assert_eq(spy.call_count, 0, "must not tilt the field while airborne")
	assert_false(behavior.is_triggered())


func test_stays_inert_across_several_airborne_ticks() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block()
	block.sleeping = false
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	for _i: int in range(30):
		behavior.advance(TICK)

	assert_eq(block.linear_velocity.y, 0.0)
	assert_eq(spy.call_count, 0)
	assert_false(
		behavior.is_triggered(), "must never self-trigger while airborne, regardless of arm_delay"
	)


# --- once settled: lift + tilt start ----------------------------------------

func test_lift_and_tilt_start_once_settled() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	effect.lift_speed = 4.0
	effect.tilt_strength = 0.3
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))  # distance 5 from centre
	block.sleeping = true  # already settled
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)

	assert_eq(block.linear_velocity.y, 4.0, "must lift at lift_speed once settled")
	assert_eq(spy.call_count, 1, "must tilt the field once settled")
	assert_almost_eq(spy.last_magnitude, 0.3 * 0.1, 0.0001, "tilt magnitude must scale with delta")


# --- tilt direction is away from the block's own disk position -------------

func test_tilt_direction_is_away_from_the_blocks_own_disk_position() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))  # local (3, 4), distance 5
	block.sleeping = true
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)

	assert_eq(spy.call_count, 1)
	# local.normalized() == (0.6, 0.8); "away from itself" negates it.
	assert_almost_eq(spy.last_direction.x, -0.6, 0.001)
	assert_almost_eq(spy.last_direction.y, -0.8, 0.001)


func test_no_tilt_impulse_when_settled_exactly_at_the_centre() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3.ZERO)  # exactly the disk centre
	block.sleeping = true
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)

	assert_eq(block.linear_velocity.y, effect.lift_speed, "lift itself is unaffected by position")
	assert_eq(spy.call_count, 0, "no side to name for 'away from itself' at the exact centre")


# --- lift + tilt run for exactly lift_duration_s, frame-rate independent ---

func test_wants_early_trigger_false_until_lift_duration_s_elapses() -> void:
	var effect: PropellerEffect = PropellerEffect.new()
	effect.lift_duration_s = 1.0
	var block: Block = _make_block()
	block.sleeping = true
	var def: SpecialDef = _make_def(effect, 0.25)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	for _i: int in range(4):
		behavior.advance(0.25)  # age reaches 1.0; elapsed-since-settled reaches 0.75
	assert_false(behavior.is_triggered(), "must not trigger before lift_duration_s elapses")

	behavior.advance(0.25)  # age reaches 1.25 == arm_delay + lift_duration_s
	assert_true(behavior.is_triggered(), "must trigger once lift_duration_s elapses")


## Two different step sizes must trigger within about one tick's worth of
## simulated time of each other -- driven by simulation time, not tick count,
## same shape as test_earthquake_effect.gd's own frame-rate-independence test.
func test_lift_duration_is_frame_rate_independent() -> void:
	var dt_a: float = 0.05
	var dt_b: float = 0.01

	var effect_a: PropellerEffect = PropellerEffect.new()
	effect_a.lift_duration_s = 1.0
	var block_a: Block = _make_block()
	block_a.sleeping = true
	var behavior_a: SpecialBehavior = _make_behavior(block_a, _make_def(effect_a))

	var effect_b: PropellerEffect = PropellerEffect.new()
	effect_b.lift_duration_s = 1.0
	var block_b: Block = _make_block()
	block_b.sleeping = true
	var behavior_b: SpecialBehavior = _make_behavior(block_b, _make_def(effect_b))

	var real_time_a: float = 0.0
	while not behavior_a.is_triggered() and real_time_a < 5.0:
		behavior_a.advance(dt_a)
		real_time_a += dt_a

	var real_time_b: float = 0.0
	while not behavior_b.is_triggered() and real_time_b < 5.0:
		behavior_b.advance(dt_b)
		real_time_b += dt_b

	assert_true(behavior_a.is_triggered(), "coarse ticks must eventually reach lift_duration_s")
	assert_true(behavior_b.is_triggered(), "fine ticks must eventually reach lift_duration_s")
	assert_almost_eq(
		real_time_a, real_time_b, dt_a + dt_b,
		"trigger time must be frame-rate independent within about one coarse tick"
	)


## Counts physics_tick() calls -- proves the lift+tilt pattern actually runs
## for the whole window and stops the instant it triggers, mirroring
## test_earthquake_effect.gd's own "no further impulses after trigger" test.
class _CountingPropellerEffect:
	extends PropellerEffect
	var physics_tick_calls: int = 0

	func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
		physics_tick_calls += 1
		super.physics_tick(block, behavior, delta)


func test_no_further_physics_ticks_after_trigger() -> void:
	var effect: _CountingPropellerEffect = _CountingPropellerEffect.new()
	effect.lift_duration_s = 0.1
	var block: Block = _make_block()
	block.sleeping = true
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))  # arm_delay == 0.0

	behavior.advance(0.1)  # arms+settles; seeds start_age at age()==0.1; elapsed 0, no trigger yet
	assert_false(behavior.is_triggered(), "setup: the settling tick itself must not trigger")
	behavior.advance(0.1)  # age 0.2; elapsed 0.1 == lift_duration_s -> triggers
	assert_true(behavior.is_triggered())
	var calls_at_trigger: int = effect.physics_tick_calls
	assert_gt(calls_at_trigger, 0, "fixture: physics_tick() actually ran before triggering")

	for _i: int in range(10):
		behavior.advance(TICK)

	assert_eq(
		effect.physics_tick_calls, calls_at_trigger,
		"once triggered, SpecialBehavior.advance() must never call physics_tick() again"
	)


# --- lift+tilt must keep running once Jolt wakes the block back up ---------

## Review fix (Bontago-1en.6): the very first lift tick writes
## `block.linear_velocity.y = lift_speed`, and in a live match that write is
## exactly what wakes a sleeping Jolt body (any RigidBody3D velocity write/
## motion clears `sleeping`) -- so this fixture reproduces that by flipping
## `block.sleeping` back to false and zeroing linear_velocity right after the
## settling tick, the same way physics would the tick after. A regression
## that re-checks `block.sleeping` every tick (instead of only gating the
## first-ever settle) sees `sleeping == false` again from here on and stops
## lifting/tilting forever -- this must NOT happen.
func test_lift_and_tilt_continue_after_jolt_wakes_the_block() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	effect.lift_speed = 4.0
	effect.lift_duration_s = 10.0
	effect.tilt_strength = 0.3
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	block.sleeping = true  # settles
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)  # settling tick: lifts once, wakes the body
	assert_eq(block.linear_velocity.y, 4.0, "settling tick must lift")

	# Mirror what Jolt actually does the instant a velocity write wakes a
	# sleeping body: sleeping flips false, and physics re-integrates from
	# whatever velocity is present (zeroed here to make a regression obvious:
	# if the lift stops, linear_velocity.y stays 0.0 forever after this).
	block.sleeping = false
	block.linear_velocity = Vector3.ZERO

	for i: int in range(5):
		behavior.advance(0.1)
		assert_eq(
			block.linear_velocity.y, effect.lift_speed,
			"tick %d: must keep lifting even though the block is awake again" % i
		)

	assert_eq(
		spy.call_count, 6,
		"tilt impulse must keep firing every armed tick, not just the settling tick"
	)


## Review fix (Bontago-1en.6): the tilt impulse must accumulate every armed
## tick for the whole `lift_duration_s` window, not just once on the
## settling tick. Uses the real Field (not SpyField, whose
## apply_tilt_impulse() override never touches Field's own spring state) and
## reads `field.tilt_vector()`'s underlying spring velocity directly rather
## than integrating position every tick: `_update_tilt()`'s own critically
## damped response to a SINGLE impulse keeps rising for several seconds
## after it fires (`TiltTuning.return_time_constant_s` == 4.0), so comparing
## `tilt_vector()` at two points in time while integrating every tick would
## still show growth even under the bug (the natural single-impulse rise),
## masking the regression. Withholding `_update_tilt()` until the very end
## isolates exactly what this test means to check: does
## `field.tilt_vector()`'s magnitude, read after fully integrating the
## accumulated spring velocity in one step, come out bigger when many
## "awake" ticks each contributed their own impulse than when only the
## settling tick did.
func test_tilt_impulse_accumulates_over_the_whole_duration_not_once() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)
	field.set_tilt_enabled(true)

	var effect: PropellerEffect = PropellerEffect.new()
	effect.lift_speed = 4.0
	effect.lift_duration_s = 10.0
	effect.tilt_strength = 0.3
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	block.sleeping = true
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)  # settling tick: exactly one impulse into _tilt_velocity
	# Wake the block back up exactly like Jolt would, same as the test above.
	block.sleeping = false
	block.linear_velocity = Vector3.ZERO
	field._update_tilt(TICK)  # integrate that one impulse into a position
	var magnitude_after_one_tick: float = field.tilt_vector().length()

	# Reset the spring to a clean, comparable starting point, then replay:
	# one settling-equivalent impulse plus 20 more "awake" ticks worth of
	# advance() calls -- but withhold _update_tilt() until after all of them,
	# so only the FIXED code's repeated apply_tilt_impulse() calls (not the
	# spring's own multi-second rise) can grow _tilt_velocity further.
	field._tilt = Vector2.ZERO
	field._tilt_velocity = Vector2.ZERO
	for _i: int in range(20):
		behavior.advance(0.1)
	field._update_tilt(TICK)
	var magnitude_after_many_ticks: float = field.tilt_vector().length()

	assert_gt(
		magnitude_after_many_ticks, magnitude_after_one_tick,
		"tilt must keep accumulating across many awake ticks, not stop after the first"
	)


# --- two blocks sharing the effect keep independent timers ------------------

func test_two_blocks_with_the_same_def_keep_independent_elapsed_timers() -> void:
	var effect: PropellerEffect = PropellerEffect.new()
	effect.lift_duration_s = 1.0
	var shared_def: SpecialDef = _make_def(effect, 0.25)  # one SpecialDef/effect instance

	var block_a: Block = _make_block(Vector3(1.0, 0.0, 0.0))
	block_a.sleeping = true  # settles immediately
	var behavior_a: SpecialBehavior = _make_behavior(block_a, shared_def)

	var block_b: Block = _make_block(Vector3(-1.0, 0.0, 0.0))
	block_b.sleeping = false  # still airborne -- must not even start its timer
	var behavior_b: SpecialBehavior = _make_behavior(block_b, shared_def)

	for _i: int in range(4):
		behavior_a.advance(0.25)  # block_a reaches age 1.0 (elapsed-since-settled 0.75)
	behavior_b.advance(0.1)  # block_b still airborne -- no settle, no start-age meta

	assert_false(behavior_a.is_triggered(), "setup: block_a not at lift_duration_s yet either")
	assert_false(behavior_b.is_triggered())

	behavior_a.advance(0.25)  # block_a reaches age 1.25 == arm_delay + lift_duration_s -> triggers
	assert_true(behavior_a.is_triggered(), "block_a's own elapsed timer must trigger it")
	assert_false(
		behavior_b.is_triggered(),
		"block_b's independent (unstarted) timer must not have been advanced by block_a's ticks"
	)

	# Now let block_b settle and confirm it gets its own fresh start_age, not
	# block_a's already-elapsed one (would immediately over-trigger).
	block_b.sleeping = true
	behavior_b.advance(0.25)  # block_b's own first settled tick
	assert_false(
		behavior_b.is_triggered(),
		"block_b's timer must start fresh from its own settle tick, not inherit block_a's elapsed time"
	)


# --- propeller.tres loads through the shared loader -------------------------

func test_propeller_tres_loads_with_expected_id_and_effect() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"propeller":
			found = def
			break
	assert_not_null(found, "config/specials/propeller.tres must be found by load_all_specials()")
	assert_true(
		found.effect is PropellerEffect,
		"propeller.tres's effect sub-resource must be a PropellerEffect"
	)


## Proves the real Field's own tilt-disabled guard is enough -- PropellerEffect
## needs no guard of its own -- mirroring test_anvil_effect.gd's equivalent.
func test_respects_tilt_mode_off_via_the_real_field_guard() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)
	# field.set_tilt_enabled() deliberately not called: tilt stays disabled.

	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	block.sleeping = true
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	behavior.advance(0.1)
	field._update_tilt(TICK)

	assert_eq(field.tilt_vector(), Vector2.ZERO, "tilt_mode OFF must leave the disk untouched")
