extends GutTest
## AnvilEffect (spec 1.6 "a tilting anvil"): the one-shot mass override, the settled-triggers-early
## rule, and detonate()'s landing-point tilt impulse. Mass/wants_early_trigger
## tests drive SpecialBehavior directly with a stub Block (no physics
## simulation), mirroring tests/unit/gifts/test_special_behavior.gd's own pattern.
## detonate() tests use a real, tiny Field via Match.register_world() (same
## fixture tests/unit/field/test_field_tilt.gd uses), reset in after_each.

const AWAKE_MAX_FRAMES: int = 480
const AWAKE_KICK_EVERY_FRAMES: int = 6
const AWAKE_KICK_IMPULSE: float = 1.0
const TICK: float = 1.0 / 60.0
const MOVING_SPEED_MPS: float = 5.0
const MOVING_TICKS: int = 10
## Past LandedTuning.landed_hold_s (0.2 s) at 60 ticks per second.
const HOLD_TICKS: int = 15
## Physics frames for a dropped cube to come to rest on the field.
const SETTLE_FRAMES: int = 20
const NEVER_IMPACT: float = 1.0e9
## Cube centre height above the field surface: resting, inside the landing probe's reach.
const RESTING_OFFSET_M: float = 0.52


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


## A real, tiny Field registered with Match (the same fixture the awake-disc test uses).
func _register_real_field() -> Field:
	var field: Field = autofree(Field.new())
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)
	return field


## A real cube placed just above the field surface, so the landing probe finds contact.
func _make_resting_block(field: Field) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(shape, tuning)
	add_child_autofree(block)
	block.global_position = Vector3(1.0, field.surface_y() + RESTING_OFFSET_M, 1.0)
	return block


# --- mass override: once armed, idempotent, never before arming -------------

func test_mass_override_applied_on_the_first_armed_tick() -> void:
	var effect: AnvilEffect = AnvilEffect.new()
	effect.mass = 60.0
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(effect, 0.1)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms this same tick
	assert_eq(block.mass, 60.0, "mass must be overridden the instant the special arms")


## End-to-end through SpecialBehavior.advance(): a real block resting on a real Field
## is "landed" once its speed relative to the support stays under the landing threshold
## for the hold time. The block velocity is the only stub (no physics frames run while
## the behaviour is driven), so the landing probe reads exactly what it reads in game.
func test_landing_triggers_the_behavior_through_advance() -> void:
	var field: Field = _register_real_field()
	var block: Block = _make_resting_block(field)
	await wait_physics_frames(SETTLE_FRAMES)  # let the cube come to rest on the field
	var effect: AnvilEffect = AnvilEffect.new()
	var def: SpecialDef = _make_def(effect, 0.1)
	def.arm_impulse = NEVER_IMPACT  # the stubbed velocity steps must not read as a crash
	var behavior: SpecialBehavior = _make_behavior(block, def)
	behavior.set_physics_process(false)  # only this test advances the behaviour

	block.linear_velocity = Vector3(MOVING_SPEED_MPS, 0.0, 0.0)
	for _i: int in range(MOVING_TICKS):
		behavior.advance(TICK)
	assert_eq(block.mass, effect.mass, "armed: heavy before it lands")
	assert_false(behavior.is_triggered(), "a moving anvil has not landed")

	block.linear_velocity = Vector3.ZERO
	behavior.advance(TICK)
	assert_false(behavior.is_triggered(), "one slow tick is not the landing hold time")
	for _i: int in range(HOLD_TICKS):
		behavior.advance(TICK)
	assert_true(behavior.is_triggered(), "landing must early-trigger once armed")


## The Anvil fires from the landing probe even while the island around it
## never sleeps (the real-physics case that broke the old `sleeping` gate).
func test_anvil_triggers_on_a_continuously_tilting_awake_disc() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)
	field.set_tilt_enabled(true)
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var physics_tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var anvil: Block = BlockFactory.build(shape, physics_tuning)
	_blocks_root.add_child(anvil)
	anvil.global_position = Vector3(2.0, field.surface_y() + 1.0, 0.0)
	var neighbour: Block = BlockFactory.build(shape, physics_tuning)
	_blocks_root.add_child(neighbour)
	neighbour.global_position = Vector3(-2.0, field.surface_y() + 0.8, 0.0)
	var def: SpecialDef = SpecialDef.find_by_id(&"anvil")
	var behavior: SpecialBehavior = SpecialBehavior.new()
	anvil.add_child(behavior)
	behavior.bind(anvil, def, SpecialTuning.new())

	var frames: int = 0
	while frames < AWAKE_MAX_FRAMES and not behavior.is_triggered():
		if frames % AWAKE_KICK_EVERY_FRAMES == 0:
			neighbour.wake_for_impulse()
			neighbour.apply_central_impulse(Vector3(0.0, 0.0, AWAKE_KICK_IMPULSE))
		await wait_physics_frames(1)
		frames += 1

	assert_true(behavior.is_triggered(), "the anvil must trigger by landing, not wait on `sleeping`")
	assert_eq(anvil.mass, 60.0, "the mass override ran on arming")


# --- detonate(): landing-point tilt impulse, real Field fixture -------------

## Records exactly what reaches Field.apply_tilt_impulse() without depending
## on the spring's own integration math (already covered by
## tests/unit/field/test_field_tilt.gd) -- a thin test-only subclass overriding the
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
	MatchTestReset.clear_world()


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
	effect.disc_force.strength = 0.02
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))  # distance 5 from centre
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	effect.detonate(block, behavior, 0)

	assert_eq(spy.call_count, 1)
	assert_almost_eq(spy.last_direction.x, 0.6, 0.001)
	assert_almost_eq(spy.last_direction.y, 0.8, 0.001)
	assert_almost_eq(spy.last_magnitude, effect.disc_force.strength * 5.0, 0.001)
