extends GutTest
## PropellerEffect (spec 2.6; docs/GIFT_EFFECTS_PLAN.md package D): the
## Anvil in reverse. After the carrier has LANDED (SpecialBehavior's
## LandedProbe -- never Jolt `sleeping`) it runs DiscForce.apply(sign -1) every
## tick for `disc_force.duration_s`. Stub-Block tests force the behaviour's
## landed state; the acceptance tests use real physics with an awake
## neighbour island (the case that broke the old `sleeping` gate) and compare
## the tilt with an Anvil at the same point.

const TICK: float = 1.0 / 60.0
const SEEDED_RUNS: int = 10
const AWAKE_RUN_MAX_FRAMES: int = 300
const MIN_IMPULSE_CALLS: int = 3
const NEIGHBOUR_KICK_EVERY_FRAMES: int = 6
const NEIGHBOUR_KICK_SPEED_MPS: float = 1.5
const TILT_KICK_EVERY_FRAMES: int = 12
const TILT_KICK: float = 0.05
const COMPARE_DISTANCE_M: float = 3.0
const COMPARE_SECONDS: float = 8.0
const MIN_PEAK_RATIO: float = 0.5
const MAX_PEAK_RATIO: float = 2.0


# --- shared stub-Block/def/behavior fixture (no physics simulation) ----------

func _make_block(position: Vector3 = Vector3.ZERO) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = 1.0
	block.linear_velocity = Vector3.ZERO
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


## Marks the behaviour as landed now (the real probe needs real physics;
## the landed-gating itself is covered by test_special_behavior.gd).
func _land(behavior: SpecialBehavior) -> void:
	behavior._landed_at_age = behavior.age()


# --- SpyField/small-map fixture for direction/magnitude assertions ----------

## Records what reaches Field.apply_tilt_impulse(). With `passthrough` the real
## spring still integrates it (physics tests).
class SpyField:
	extends Field
	var call_count: int = 0
	var last_direction: Vector2 = Vector2.ZERO
	var last_magnitude: float = 0.0
	var recording: bool = true
	var passthrough: bool = false

	func apply_tilt_impulse(direction: Vector2, magnitude: float) -> void:
		if recording:
			call_count += 1
			last_direction = direction
			last_magnitude = magnitude
		if passthrough:
			super.apply_tilt_impulse(direction, magnitude)


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
	MatchTestReset.clear_world()


func _register_field(field: Field) -> void:
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)


func _register_spy_field(passthrough: bool = false) -> SpyField:
	var field: SpyField = autofree(SpyField.new())
	field.passthrough = passthrough
	_register_field(field)
	return field


func _load_propeller_def() -> SpecialDef:
	var def: SpecialDef = SpecialDef.find_by_id(&"propeller")
	assert_not_null(def, "config/specials/propeller.tres must be found by id")
	return def


# --- inert until landed ------------------------------------------------------

func test_inert_until_landed_no_velocity_change_no_tilt_impulse() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

	for _i: int in range(30):
		behavior.advance(TICK)

	assert_true(effect.needs_landing(), "Propeller waits for the landing probe")
	assert_eq(block.linear_velocity, Vector3.ZERO, "never writes the carrier's velocity")
	assert_eq(spy.call_count, 0, "must not tilt the field before landing")
	assert_false(behavior.is_triggered(), "must not self-trigger while it has not landed")


# --- once landed: tilt starts, no physical lift ------------------------------

func test_tilt_starts_once_landed_and_never_writes_the_velocity() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))  # distance 5 from centre
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	behavior.advance(0.1)

	assert_eq(block.linear_velocity, Vector3.ZERO, "the carrier lift is gone (plan section 7)")
	assert_eq(spy.call_count, 1, "must tilt the field once landed")
	assert_almost_eq(
		spy.last_magnitude, effect.disc_force.strength * 5.0 * 0.1, 0.0001,
		"magnitude = strength * distance * delta"
	)


func test_tilt_direction_is_away_from_the_blocks_own_disk_position() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))  # local (3, 4), distance 5
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	behavior.advance(0.1)

	assert_eq(spy.call_count, 1)
	# local.normalized() == (0.6, 0.8); DiscForce sign -1 negates it.
	assert_almost_eq(spy.last_direction.x, -0.6, 0.001)
	assert_almost_eq(spy.last_direction.y, -0.8, 0.001)


func test_no_tilt_impulse_when_landed_exactly_at_the_centre() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	behavior.advance(0.1)

	assert_eq(spy.call_count, 0, "no side to name at the exact centre")


# --- the effect window is disc_force.duration_s after landing ----------------

func test_wants_early_trigger_false_until_duration_elapses_after_landing() -> void:
	var effect: PropellerEffect = PropellerEffect.new()
	effect.disc_force.duration_s = 1.0
	var block: Block = _make_block()
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	for _i: int in range(3):
		behavior.advance(0.25)
	assert_false(behavior.is_triggered(), "must not trigger before duration_s has elapsed")

	behavior.advance(0.25)  # landed_age reaches 1.0
	assert_true(behavior.is_triggered(), "must trigger once duration_s has elapsed")


func test_duration_is_frame_rate_independent() -> void:
	var dt_a: float = 0.05
	var dt_b: float = 0.01
	var effect_a: PropellerEffect = PropellerEffect.new()
	effect_a.disc_force.duration_s = 1.0
	var behavior_a: SpecialBehavior = _make_behavior(_make_block(), _make_def(effect_a))
	_land(behavior_a)
	var effect_b: PropellerEffect = PropellerEffect.new()
	effect_b.disc_force.duration_s = 1.0
	var behavior_b: SpecialBehavior = _make_behavior(_make_block(), _make_def(effect_b))
	_land(behavior_b)

	var real_time_a: float = 0.0
	while not behavior_a.is_triggered() and real_time_a < 5.0:
		behavior_a.advance(dt_a)
		real_time_a += dt_a
	var real_time_b: float = 0.0
	while not behavior_b.is_triggered() and real_time_b < 5.0:
		behavior_b.advance(dt_b)
		real_time_b += dt_b

	assert_true(behavior_a.is_triggered())
	assert_true(behavior_b.is_triggered())
	assert_almost_eq(real_time_a, real_time_b, dt_a + dt_b, "within about one coarse tick")


## Counts physics_tick() calls so "stops the instant it triggers" is direct.
class _CountingPropellerEffect:
	extends PropellerEffect
	var physics_tick_calls: int = 0

	func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
		physics_tick_calls += 1
		super.physics_tick(block, behavior, delta)


func test_no_further_physics_ticks_after_trigger() -> void:
	var effect: _CountingPropellerEffect = _CountingPropellerEffect.new()
	effect.disc_force.duration_s = 0.1
	var block: Block = _make_block()
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	behavior.advance(0.05)
	assert_false(behavior.is_triggered())
	behavior.advance(0.05)  # landed_age 0.1 == duration_s
	assert_true(behavior.is_triggered())
	var calls_at_trigger: int = effect.physics_tick_calls
	assert_gt(calls_at_trigger, 0, "fixture: the effect ran before triggering")

	for _i: int in range(10):
		behavior.advance(TICK)

	assert_eq(effect.physics_tick_calls, calls_at_trigger, "no ticks after trigger")


func test_tilt_impulse_fires_every_tick_for_the_whole_window() -> void:
	var spy: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	effect.disc_force.duration_s = 10.0
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	for _i: int in range(20):
		behavior.advance(0.1)

	assert_eq(spy.call_count, 20, "one DiscForce impulse per armed tick")


func test_two_blocks_with_the_same_def_keep_independent_landed_timers() -> void:
	var effect: PropellerEffect = PropellerEffect.new()
	effect.disc_force.duration_s = 1.0
	var shared_def: SpecialDef = _make_def(effect, 0.25)
	var behavior_a: SpecialBehavior = _make_behavior(_make_block(Vector3(1.0, 0.0, 0.0)), shared_def)
	var behavior_b: SpecialBehavior = _make_behavior(_make_block(Vector3(-1.0, 0.0, 0.0)), shared_def)
	_land(behavior_a)

	for _i: int in range(5):
		behavior_a.advance(0.25)
	behavior_b.advance(0.25)

	assert_true(behavior_a.is_triggered(), "block_a's own landed timer ran out")
	assert_false(behavior_b.is_triggered(), "block_b never landed, so its window never opened")

	_land(behavior_b)
	behavior_b.advance(0.25)
	assert_false(behavior_b.is_triggered(), "block_b's window starts at its own landing")


# --- visual-only rise ---------------------------------------------------------

func test_rise_is_visual_only_and_follows_the_landed_age() -> void:
	var effect: PropellerEffect = PropellerEffect.new()
	effect.carrier_rise_m = 0.6
	effect.disc_force.duration_s = 2.0
	assert_eq(effect.rise_at(0.0), 0.0)
	assert_almost_eq(effect.rise_at(1.0), 0.3, 0.0001, "smoothstep midpoint is half the rise")
	assert_almost_eq(effect.rise_at(5.0), 0.6, 0.0001, "clamped at the full rise")

	var block: Block = _make_block()
	var visual: Node3D = Node3D.new()
	visual.name = BlockFactory.GIFT_VISUAL_NODE
	visual.position = Vector3(0.0, 0.5, 0.0)
	block.add_child(visual)
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)
	behavior.advance(1.0)

	assert_almost_eq(visual.position.y, 0.5 + 0.3, 0.0001, "gift model rises from its rest height")
	assert_eq(block.linear_velocity, Vector3.ZERO, "the body itself is not lifted")


# --- propeller.tres loads through the shared loader -------------------------

func test_propeller_tres_loads_with_expected_id_and_effect() -> void:
	var found: SpecialDef = _load_propeller_def()
	assert_true(found.effect is PropellerEffect)
	var effect: PropellerEffect = found.effect as PropellerEffect
	assert_true(effect.needs_landing())
	assert_almost_eq(effect.disc_force.duration_s, 3.0, 0.0001)
	assert_gt(effect.effect_lifetime_s(), 0.0, "lifetime drives the fuse backstop")


## The real Field's own tilt-disabled guard is enough.
func test_respects_tilt_mode_off_via_the_real_field_guard() -> void:
	var field: Field = autofree(Field.new())
	_register_field(field)
	# field.set_tilt_enabled() deliberately not called: tilt stays disabled.
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(3.0, 0.0, 4.0))
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	_land(behavior)

	behavior.advance(0.1)
	field._update_tilt(TICK)

	assert_eq(field.tilt_vector(), Vector2.ZERO, "tilt_mode OFF must leave the disk untouched")


# --- chain trigger and impact veto -------------------------------------------

func test_hard_impact_does_not_trigger_but_a_chain_trigger_still_does() -> void:
	var effect: PropellerEffect = PropellerEffect.new()
	var block: Block = _make_block(Vector3(1.0, 0.0, 0.0))
	var def: SpecialDef = _make_def(effect, 0.0)
	def.arm_impulse = 5.0
	var behavior: SpecialBehavior = _make_behavior(block, def)
	behavior.advance(0.1)
	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(0.01)
	block.linear_velocity = Vector3.ZERO
	behavior.advance(0.01)
	assert_false(behavior.is_triggered(), "the impact veto stands (Bontago-1en.22)")

	var neighbor_behavior: SpecialBehavior = _make_behavior(
		_make_block(Vector3.ZERO), _make_def(PropellerEffect.new())
	)
	neighbor_behavior.trigger_others_in_range(Vector3.ZERO, 5.0, 0)
	assert_true(behavior.is_triggered(), "a chain trigger must still detonate a Propeller")


# --- acceptance (plan section 5 D): real physics, awake neighbour island ------

func _cube(root: Node3D, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(shape, tuning)
	root.add_child(block)
	block.global_position = at
	return block


## One seeded run: a tilting disc, a Propeller carrier at disc-local +X and
## neighbours kicked every few frames so the island never sleeps. Returns the
## field spy, whether the gift landed and the gift block.
func _awake_island_run(seed_value: int) -> Dictionary:
	var spy: SpyField = _register_spy_field(true)
	spy.set_tilt_enabled(true)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var surface: float = spy.surface_y()
	var gift: Block = _cube(_blocks_root, Vector3(COMPARE_DISTANCE_M, surface + 0.7, 0.0))
	var neighbours: Array[Block] = []
	for offset: Vector3 in [Vector3(1.2, 0.0, 0.0), Vector3(0.0, 0.0, 1.2), Vector3(0.0, 0.0, -1.2)]:
		neighbours.append(_cube(_blocks_root, gift.global_position + offset))
	var behavior: SpecialBehavior = SpecialBehavior.new()
	gift.add_child(behavior)
	behavior.bind(gift, _load_propeller_def(), SpecialTuning.new())
	var frames: int = 0
	while frames < AWAKE_RUN_MAX_FRAMES and spy.call_count < MIN_IMPULSE_CALLS:
		if frames % NEIGHBOUR_KICK_EVERY_FRAMES == 0:
			for neighbour: Block in neighbours:
				var kick: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
				neighbour.wake_for_impulse()
				neighbour.apply_central_impulse(kick * NEIGHBOUR_KICK_SPEED_MPS * neighbour.mass)
		if frames % TILT_KICK_EVERY_FRAMES == 0:
			spy.recording = false
			var tilt_sign: float = 1.0 if rng.randf() < 0.5 else -1.0
			spy.apply_tilt_impulse(Vector2(0.0, tilt_sign), TILT_KICK)
			spy.recording = true
		await wait_physics_frames(1)
		frames += 1
	return {"spy": spy, "landed": behavior.has_landed(), "gift": gift}


func test_awake_neighbour_island_propeller_applies_disc_force_every_seeded_run() -> void:
	for run: int in range(SEEDED_RUNS):
		var result: Dictionary = await _awake_island_run(run + 1)
		var spy: SpyField = result["spy"] as SpyField
		assert_true(result["landed"] as bool, "run %d: the carrier must register as landed" % run)
		assert_gte(
			spy.call_count, MIN_IMPULSE_CALLS,
			"run %d: DiscForce(-1) must start despite the awake island" % run
		)
		var gift: Block = result["gift"] as Block
		var away: Vector2 = -spy.disk_local_from_world(gift.global_position).normalized()
		assert_gt(spy.last_direction.dot(away), 0.9, "run %d: tilts away from the gift's side" % run)
		# Tear this run's world down before the next one registers its own.
		spy.free()
		_blocks_root.free()
		Match.abort_match()
		MatchTestReset.clear_world()


## Peak |tilt| of a real Field and the tilt vector at that peak: one Anvil
## detonate, or the Propeller ticking over its whole window at the same point.
func _real_field_tilt(use_anvil: bool) -> Dictionary:
	var field: Field = autofree(Field.new())
	_register_field(field)
	field.set_tilt_enabled(true)
	var block: Block = _make_block(field.world_from_disk_local(Vector2(COMPARE_DISTANCE_M, 0.0), 0.0))
	var propeller: PropellerEffect = _load_propeller_def().effect as PropellerEffect
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(propeller))
	_land(behavior)
	if use_anvil:
		AnvilEffect.new().detonate(block, behavior, 0)
	var peak: float = 0.0
	var peak_tilt: Vector2 = Vector2.ZERO
	var elapsed: float = 0.0
	for _tick: int in range(int(COMPARE_SECONDS / TICK)):
		if not use_anvil and elapsed < propeller.disc_force.duration_s:
			propeller.physics_tick(block, behavior, TICK)
		elapsed += TICK
		field._update_tilt(TICK)
		if field.tilt_vector().length() > peak:
			peak = field.tilt_vector().length()
			peak_tilt = field.tilt_vector()
	return {"peak": peak, "tilt": peak_tilt}


func test_propeller_tilts_opposite_to_an_anvil_at_the_same_point() -> void:
	var anvil: Dictionary = _real_field_tilt(true)
	Match.abort_match()
	MatchTestReset.clear_world()
	var prop: Dictionary = _real_field_tilt(false)
	var anvil_tilt: Vector2 = anvil["tilt"] as Vector2
	var prop_tilt: Vector2 = prop["tilt"] as Vector2
	assert_gt(float(anvil["peak"]), 0.0, "fixture: the anvil tilted the disc")
	assert_lt(anvil_tilt.normalized().dot(prop_tilt.normalized()), -0.9, "opposite tilt")
	var ratio: float = float(prop["peak"]) / float(anvil["peak"])
	assert_gt(ratio, MIN_PEAK_RATIO, "propeller peak tilt comparable to the anvil's (ratio %f)" % ratio)
	assert_lt(ratio, MAX_PEAK_RATIO, "propeller peak tilt comparable to the anvil's (ratio %f)" % ratio)
