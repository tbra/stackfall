extends GutTest
## EarthquakeEffect (spec 1.6):
## the shake-every-armed-tick + leveling-nudge timed effect, driven through a
## real, tiny Field registered via Match.register_world() -- same fixture
## shape as tests/unit/field/test_field_tilt.gd's own _make_field(), plus the
## Match.register_world()/after_each() convention
## tests/unit/gifts/test_gift_claim.gd already uses.
##
## NOTE ON TICK HELPERS: Field.apply_tilt_impulse() only adds to the tilt
## spring's *velocity* (game/field/Field.gd:260-266) -- the tilt vector itself only
## moves once Field._physics_process() integrates that velocity for a step, exactly the
## two-call shape tests/unit/field/test_field_tilt.gd's own tests use
## (apply_tilt_impulse() then _physics_process(TICK)). _tick() below drives both
## SpecialBehavior.advance() and Field._physics_process() together, once per
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
	MatchTestReset.clear_world()


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
	_field._physics_process(dt)


# --- physics_tick shakes the field --------------------------------------------

func test_an_armed_ticks_calls_apply_tilt_impulse_and_moves_the_tilt_vector() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.disc_force.shake_amplitude_m = 30.0
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
## proven by tests/unit/field/test_field_tilt.gd -- but no earthquake leveling, so
## this isolates leveling's own contribution rather than re-proving the
## spring decays on its own. The initial kick (0.05) is small enough to stay
## well clear of TiltTuning.max_tilt_deg's clamp (game/field/Field.gd's
## _clamp_tilt(), 12 deg here) even at the critically damped impulse
## response's own peak (occurring at t == return_time_constant_s, 4 s here
## per config/physics/tilt_tuning.tres) -- a saturated clamp would make both fields
## read the same value and hide leveling's effect entirely.
func test_with_zero_shake_magnitude_leveling_shrinks_tilt_faster_than_natural_decay_alone() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.disc_force.shake_amplitude_m = 0.0
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
		control_field._physics_process(TICK)

	assert_gt(
		control_field.tilt_vector().length(), 0.0,
		"fixture: the control field is genuinely tilted, not clamped to zero"
	)
	assert_lt(
		_field.tilt_vector().length(), control_field.tilt_vector().length(),
		"leveling, isolated from the (zeroed) shake, must shrink tilt faster than natural decay alone"
	)


# --- wants_early_trigger flips at shake_duration_s ---------------------------

## arm_delay is set to the same step size used below (0.25 s, exact in binary
## floating point) so the tick that arms is also the tick that seeds the
## effect's `<key>_start_age` meta at an age exactly equal to arm_delay --
## the timed-effect pattern samples
## `behavior.age()` (already incremented for the current tick) on that first
## armed tick, so "elapsed" only reads exactly shake_duration_s once total
## age reaches arm_delay + shake_duration_s.
func test_wants_early_trigger_flips_at_shake_duration_s() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.disc_force.duration_s = 1.0
	var block: Block = _make_block()
	var def: SpecialDef = _make_def(effect, 0.25)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	for _i: int in range(4):
		_tick(behavior, 0.25)  # age reaches 1.0; elapsed-since-armed reaches 0.75
	assert_false(behavior.is_triggered(), "must not trigger before shake_duration_s elapses")

	_tick(behavior, 0.25)  # age reaches 1.25 == arm_delay + shake_duration_s
	assert_true(behavior.is_triggered(), "must trigger once shake_duration_s elapses")


func test_the_shake_kick_comes_from_disc_force_and_stops_after_the_duration() -> void:
	var effect: EarthquakeEffect = EarthquakeEffect.new()
	effect.leveling_strength = 0.0
	effect.disc_force.duration_s = 0.5
	var behavior: SpecialBehavior = _make_behavior(_make_block(), _make_def(effect))
	_tick(behavior, TICK)
	assert_gt(_field.tilt_vector().length(), 0.0, "the first armed tick kicks the disc")
	# Level the disc (public reset path), then shake past the duration: nothing moves.
	_field.set_tilt_enabled(false)
	_field.set_tilt_enabled(true)
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "fixture: level again")
	DiscForce.shake(_field, effect.disc_force, effect.disc_force.duration_s + 0.1, TICK)
	for _i: int in range(10):
		_field._physics_process(TICK)
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "no kick once past the duration")
