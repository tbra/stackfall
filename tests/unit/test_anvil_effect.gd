extends GutTest
## AnvilEffect (spec 2.6 "a tilting anvil"; docs/M4_SPECIALS_PACKAGES.md's
## P5-ANVIL package): the one-shot mass override, the settled-triggers-early
## rule, and detonate()'s landing-point tilt impulse. Mass/wants_early_trigger
## tests drive SpecialBehavior directly with a stub Block (no physics
## simulation), mirroring tests/unit/test_special_behavior.gd's own pattern.
## detonate() tests use a real, tiny Field via Match.register_world() (same
## fixture tests/unit/test_field_tilt.gd uses), reset in after_each.

const TICK: float = 1.0 / 60.0


# --- shared stub-Block/def/behavior fixture (no physics, no scene tree) -----

func _make_block(position: Vector3 = Vector3.ZERO, mass: float = 1.0) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = mass
	block.linear_velocity = Vector3.ZERO
	return block


func _make_def(effect: AnvilEffect, arm_delay: float = 0.1) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"anvil"
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


# --- mass override: once armed, idempotent, never before arming -------------

func test_mass_override_not_applied_before_arming() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	effect.mass = 60.0
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(effect, 1.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.5)  # well short of arm_delay == 1.0
	assert_false(behavior.is_armed(), "fixture: must still be unarmed")
	assert_eq(block.mass, 1.0, "mass must not change before the special has armed")


func test_mass_override_applied_on_the_first_armed_tick() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	effect.mass = 60.0
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(effect, 0.1)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms this same tick
	assert_true(behavior.is_armed(), "fixture: must have armed")
	assert_eq(block.mass, 60.0, "mass must be overridden the instant the special arms")


func test_mass_override_is_idempotent_across_later_ticks() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	effect.mass = 60.0
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(effect, 0.1)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms, overrides mass
	assert_eq(block.mass, 60.0)

	# Simulate something else (or a bug) changing mass back after the
	# override -- a later armed tick must not re-apply it, proving the
	# override genuinely only ever fires once, not merely "every tick
	# happens to set the same value".
	block.mass = 1.0
	behavior.advance(0.1)
	behavior.advance(0.1)
	assert_eq(
		block.mass, 1.0,
		"the mass override must fire exactly once (on the first armed tick), never again"
	)


# --- wants_early_trigger: true only once the block has settled --------------

func test_wants_early_trigger_false_while_airborne() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	var block: Block = _make_block()
	block.sleeping = false
	assert_false(effect.wants_early_trigger(block, null))


func test_wants_early_trigger_true_once_sleeping() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	var block: Block = _make_block()
	block.sleeping = true
	assert_true(effect.wants_early_trigger(block, null))


## End-to-end through SpecialBehavior.advance(): the settled block actually
## triggers (and detonate() runs) once physics_tick()+wants_early_trigger()
## are both wired in via the real behavior, not just the effect in isolation.
func test_settling_triggers_the_behavior_through_advance() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(effect, 0.1)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	block.sleeping = false
	behavior.advance(0.1)  # arms; still airborne, must not trigger yet
	assert_false(behavior.is_triggered())

	block.sleeping = true
	behavior.advance(0.1)
	assert_true(behavior.is_triggered(), "settling (sleeping) must early-trigger once armed")


# --- detonate(): landing-point tilt impulse, real Field fixture -------------

## Records exactly what reaches Field.apply_tilt_impulse() without depending
## on the spring's own integration math (already covered by
## tests/unit/test_field_tilt.gd) -- a thin test-only subclass overriding the
## one public entry point AnvilEffect calls.
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
	map_def.id = &"test_anvil"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


var _registry: BlockRegistry = null
var _blocks_root: Node3D = null


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


func test_detonate_pushes_an_impulse_toward_the_landing_point() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: AnvilEffect = AnvilEffect.new()
	effect.tilt_impulse_per_distance = 0.02
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))  # distance 5 from centre
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	effect.detonate(block, behavior, 0)

	assert_eq(spy.call_count, 1)
	assert_almost_eq(spy.last_direction.x, 0.6, 0.001)
	assert_almost_eq(spy.last_direction.y, 0.8, 0.001)
	assert_almost_eq(spy.last_magnitude, 0.02 * 5.0, 0.001)


func test_detonate_magnitude_scales_with_distance_from_centre() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: AnvilEffect = AnvilEffect.new()
	var near_block: Block = _make_block(Vector3(1.0, 0.0, 0.0))
	var behavior: SpecialBehavior = _make_behavior(near_block, _make_def(effect))
	effect.detonate(near_block, behavior, 0)
	var near_magnitude: float = spy.last_magnitude

	var far_block: Block = _make_block(Vector3(4.0, 0.0, 0.0))
	var far_behavior: SpecialBehavior = _make_behavior(far_block, _make_def(effect))
	effect.detonate(far_block, far_behavior, 0)
	var far_magnitude: float = spy.last_magnitude

	assert_gt(far_magnitude, near_magnitude, "a farther landing point must push a larger impulse")


func test_detonate_at_the_exact_centre_applies_no_impulse() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: AnvilEffect = AnvilEffect.new()
	var block: Block = _make_block(Vector3.ZERO)  # exactly the disk centre
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	effect.detonate(block, behavior, 0)

	assert_eq(spy.call_count, 0, "landing exactly at the centre must push no impulse")


## Proves the real Field's own tilt-disabled guard is enough -- AnvilEffect
## needs no guard of its own -- by exercising the actual apply_tilt_impulse()
## (not the spy override above) with tilt left disabled.
func test_detonate_respects_tilt_mode_off_via_the_real_field_guard() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)
	# field.set_tilt_enabled() deliberately not called: tilt stays disabled.

	var effect: AnvilEffect = AnvilEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	effect.detonate(block, behavior, 0)
	field._update_tilt(TICK)

	assert_eq(field.tilt_vector(), Vector2.ZERO, "tilt_mode OFF must leave the disk untouched")


# --- anvil.tres loads through the shared loader ------------------------------

func test_anvil_tres_loads_with_expected_id_and_effect() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var anvil_def: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"anvil":
			anvil_def = def
	assert_not_null(anvil_def, "config/specials/anvil.tres must load with id \"anvil\"")
	assert_true(
		anvil_def.effect is AnvilEffect,
		"anvil.tres's effect sub-resource must be an AnvilEffect"
	)
