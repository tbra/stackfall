extends GutTest
## EarthquakeEffect (spec 2.6, docs/M4_SPECIALS_PACKAGES.md P5-EARTHQUAKE):
## the shake-every-armed-tick + leveling-nudge timed effect, driven through a
## real, tiny Field registered via Match.register_world() -- same fixture
## shape as tests/unit/test_field_tilt.gd's own _make_field(), plus the
## Match.register_world()/after_each() convention tests/unit/
## test_gift_claim.gd already uses.
##
## NOTE ON TICK HELPERS: Field.apply_tilt_impulse() only adds to the tilt
## spring's *velocity* (game/Field.gd:260-266) -- the tilt vector itself only
## moves once _update_tilt() integrates that velocity for a step, exactly the
## two-call shape tests/unit/test_field_tilt.gd's own tests use
## (apply_tilt_impulse() then _update_tilt(TICK)). _tick() below drives both
## SpecialBehavior.advance() and Field._update_tilt() together, once per
## simulated physics step, mirroring what Field._physics_process()/
## SpecialBehavior._physics_process() do independently every real tick.

const TICK: float = 1.0 / 60.0

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_earthquake"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	_field.set_tilt_enabled(true)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)


func _make_block(position: Vector3 = Vector3.ZERO) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = 1.0
	block.linear_velocity = Vector3.ZERO
	return block


func _make_def(effect: EarthquakeEffect, arm_delay: float = 0.0) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"earthquake"
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


## One simulated physics step: the behaviour's own advance() (which may call
## Field.apply_tilt_impulse() through the effect), then Field's own spring
## integration -- see the file header note above.
func _tick(behavior: SpecialBehavior, dt: float) -> void:
	behavior.advance(dt)
	_field._update_tilt(dt)


# --- physics_tick shakes the field --------------------------------------------

func test_an_armed_ticks_calls_apply_tilt_impulse_and_moves_the_tilt_vector() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.shake_magnitude = 0.5
	effect.leveling_strength = 0.0
	var block: Block = _make_block()
	var def: SpecialDef = _make_def(effect)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	assert_eq(_field.tilt_vector(), Vector2.ZERO, "fixture: level before any tick")
	_tick(behavior, TICK)  # arms this tick (arm_delay == 0.0) and shakes

	assert_ne(
		_field.tilt_vector(), Vector2.ZERO,
		"an armed tick's shake must apply_tilt_impulse and move the tilt vector"
	)


# --- leveling shrinks an existing tilt faster than natural decay alone ------

## Compares against a second, otherwise-identical Field that gets the exact
## same initial kick and its own natural critically damped spring decay --
## proven by tests/unit/test_field_tilt.gd -- but no earthquake leveling, so
## this isolates leveling's own contribution rather than re-proving the
## spring decays on its own. The initial kick (0.05) is small enough to stay
## well clear of TiltTuning.max_tilt_deg's clamp (game/Field.gd's
## _clamp_tilt(), 12 deg here) even at the critically damped impulse
## response's own peak (occurring at t == return_time_constant_s, 4 s here
## per config/tilt_tuning.tres) -- a saturated clamp would make both fields
## read the same value and hide leveling's effect entirely.
func test_with_zero_shake_magnitude_leveling_shrinks_tilt_faster_than_natural_decay_alone() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.shake_magnitude = 0.0
	effect.leveling_strength = 0.5
	var block: Block = _make_block()
	var def: SpecialDef = _make_def(effect)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	var control_field: Field = autofree(Field.new())
	control_field.map_def = _field.map_def
	add_child_autofree(control_field)
	control_field.set_tilt_enabled(true)

	var kick: Vector2 = Vector2(1.0, 0.0)
	var kick_magnitude: float = 0.05
	_field.apply_tilt_impulse(kick, kick_magnitude)
	control_field.apply_tilt_impulse(kick, kick_magnitude)

	for _i: int in range(180):  # 3 s of ticks, still well inside the rising phase
		_tick(behavior, TICK)
		control_field._update_tilt(TICK)

	assert_gt(
		control_field.tilt_vector().length(), 0.0,
		"fixture: the control field is genuinely tilted, not clamped to zero"
	)
	assert_lt(
		_field.tilt_vector().length(), control_field.tilt_vector().length(),
		"leveling, isolated from the (zeroed) shake, must shrink tilt faster than natural decay alone"
	)


# --- wants_early_trigger flips at shake_duration_s, frame-rate independent ---

## arm_delay is set to the same step size used below (0.25 s, exact in binary
## floating point) so the tick that arms is also the tick that seeds the
## effect's `<key>_start_age` meta at an age exactly equal to arm_delay --
## docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern samples
## `behavior.age()` (already incremented for the current tick) on that first
## armed tick, so "elapsed" only reads exactly shake_duration_s once total
## age reaches arm_delay + shake_duration_s.
func test_wants_early_trigger_flips_at_shake_duration_s() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.shake_duration_s = 1.0
	var block: Block = _make_block()
	var def: SpecialDef = _make_def(effect, 0.25)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	for _i: int in range(4):
		_tick(behavior, 0.25)  # age reaches 1.0; elapsed-since-armed reaches 0.75
	assert_false(behavior.is_triggered(), "must not trigger before shake_duration_s elapses")

	_tick(behavior, 0.25)  # age reaches 1.25 == arm_delay + shake_duration_s
	assert_true(behavior.is_triggered(), "must trigger once shake_duration_s elapses")


## Two different step sizes must trigger within about one tick's worth of
## simulated time of each other -- "frame-rate independent" in the sense
## docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern promises (driven by
## simulation time, not tick count), not bit-for-bit identical real time
## (each step size's own first-armed-tick sampling offset differs slightly).
func test_wants_early_trigger_is_frame_rate_independent() -> void:
	var dt_a: float = 0.05
	var dt_b: float = 0.01

	var effect_a: EarthquakeEffect = EarthquakeEffect.new()
	effect_a.shake_duration_s = 1.0
	var behavior_a: SpecialBehavior = _make_behavior(_make_block(), _make_def(effect_a))

	var effect_b: EarthquakeEffect = EarthquakeEffect.new()
	effect_b.shake_duration_s = 1.0
	var behavior_b: SpecialBehavior = _make_behavior(_make_block(), _make_def(effect_b))

	var real_time_a: float = 0.0
	while not behavior_a.is_triggered() and real_time_a < 5.0:
		_tick(behavior_a, dt_a)
		real_time_a += dt_a

	var real_time_b: float = 0.0
	while not behavior_b.is_triggered() and real_time_b < 5.0:
		_tick(behavior_b, dt_b)
		real_time_b += dt_b

	assert_true(behavior_a.is_triggered(), "coarse ticks must eventually reach shake_duration_s")
	assert_true(behavior_b.is_triggered(), "fine ticks must eventually reach shake_duration_s")
	assert_almost_eq(
		real_time_a, real_time_b, dt_a + dt_b,
		"trigger time must be frame-rate independent within about one coarse tick"
	)


# --- no further impulses after trigger ----------------------------------------

## Counts physics_tick() calls -- the only place this effect ever calls
## apply_tilt_impulse() -- so "no further impulses after trigger" can be
## proven directly rather than through a physical proxy (a residual
## pre-trigger spring velocity can legitimately keep moving the tilt vector
## for a while with zero further impulses, a critically damped spring is not
## guaranteed monotonic the instant its forcing stops, so tilt magnitude
## alone is not a reliable witness here).
class _CountingEarthquakeEffect:
	extends EarthquakeEffect
	var physics_tick_calls: int = 0

	func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
		physics_tick_calls += 1
		super.physics_tick(block, behavior, delta)


func test_no_further_physics_ticks_after_trigger() -> void:
	var effect: _CountingEarthquakeEffect = _CountingEarthquakeEffect.new()
	effect.shake_duration_s = 0.1
	effect.shake_magnitude = 0.5
	var block: Block = _make_block()
	var def: SpecialDef = _make_def(effect)  # arm_delay == 0.0
	var behavior: SpecialBehavior = _make_behavior(block, def)

	_tick(behavior, 0.1)  # arms; seeds start_age at age()==0.1; elapsed 0, no trigger yet
	assert_false(behavior.is_triggered(), "setup: the arming tick itself must not trigger")
	_tick(behavior, 0.1)  # age 0.2; elapsed 0.1 == shake_duration_s -> triggers
	assert_true(behavior.is_triggered())
	var calls_at_trigger: int = effect.physics_tick_calls
	assert_gt(calls_at_trigger, 0, "fixture: physics_tick() actually ran before triggering")

	for _i: int in range(10):
		_tick(behavior, TICK)

	assert_eq(
		effect.physics_tick_calls, calls_at_trigger,
		"once triggered, SpecialBehavior.advance() must never call physics_tick() (and so never "
		+ "apply_tilt_impulse()) again"
	)


# --- two blocks sharing the same SpecialDef/effect keep independent timers ---

func test_two_blocks_with_the_same_def_keep_independent_elapsed_timers() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.shake_duration_s = 1.0
	var shared_def: SpecialDef = _make_def(effect, 0.25)  # one SpecialDef/effect instance

	var block_a: Block = _make_block(Vector3(1.0, 0.0, 0.0))
	var behavior_a: SpecialBehavior = _make_behavior(block_a, shared_def)
	var block_b: Block = _make_block(Vector3(-1.0, 0.0, 0.0))
	var behavior_b: SpecialBehavior = _make_behavior(block_b, shared_def)

	for _i: int in range(4):
		_tick(behavior_a, 0.25)  # block_a reaches age 1.0 (elapsed-since-armed 0.75)
	_tick(behavior_b, 0.1)  # block_b reaches age 0.1 only -- not even armed yet

	assert_false(behavior_a.is_triggered(), "setup: block_a not at shake_duration_s yet either")
	assert_false(behavior_b.is_triggered())

	_tick(behavior_a, 0.25)  # block_a reaches age 1.25 == arm_delay + shake_duration_s -> triggers
	assert_true(behavior_a.is_triggered(), "block_a's own elapsed timer must trigger it")
	assert_false(
		behavior_b.is_triggered(),
		"block_b's independent elapsed timer must not have been advanced by block_a's ticks"
	)


# --- the .tres loads with the right id and a real EarthquakeEffect -----------

func test_the_tres_loads_via_load_all_specials_with_id_and_effect() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"earthquake":
			found = def
			break

	assert_not_null(found, "config/specials/earthquake.tres must be found by load_all_specials()")
	assert_not_null(found.effect, "earthquake.tres must carry a non-null effect")
	assert_true(
		found.effect is EarthquakeEffect,
		"earthquake.tres's effect must be an EarthquakeEffect instance"
	)


# --- impact_triggers() veto (Bontago-1en.22) ---------------------------------

## A hard deceleration past arm_impulse right on/after the arming tick must
## not detonate this timed effect -- its own end is entirely time-driven
## (wants_early_trigger()) or a chain trigger; physics_tick() must still run
## and start the shake regardless.
func test_hard_impact_after_arming_does_not_prematurely_trigger_and_the_shake_still_runs() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	var def: SpecialDef = _make_def(effect, 0.0)
	def.arm_impulse = 5.0
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms this tick; decel sampled against itself, no trigger
	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(0.01)
	block.linear_velocity = Vector3.ZERO  # mass(1) * (10 - 0) = 10 >= 5: would trigger pre-fix
	behavior.advance(0.01)

	assert_false(
		behavior.is_triggered(),
		"EarthquakeEffect must veto the decel-based impact trigger (Bontago-1en.22)."
	)
	assert_true(
		block.has_meta(EarthquakeEffect.START_AGE_META),
		"physics_tick() must have run and started the shake despite the hard impact."
	)
