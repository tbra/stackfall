extends GutTest
## SpecialBehavior checks (spec 2.6, docs/archive/M4_P2_PACKAGES.md P2a): arming,
## impact-triggered activation, the effect hooks, the fuse timeout, and the
## chain-cap semantics -- all pure logic, no physics simulation. Every test
## drives SpecialBehavior.advance(delta) directly (not _physics_process, and
## no scene-tree physics tick) with a stub Block whose linear_velocity/mass
## the test sets by hand, exactly as docs/archive/M4_P2_PACKAGES.md P2a specifies.

var _tuning: SpecialTuning = null


func before_each() -> void:
	_tuning = SpecialTuning.new()
	_tuning.max_chain_depth = 4


## Records every call SpecialBehavior makes into it, in order, so a test can
## assert both "did it get called" and "in what order relative to other
## hooks" (physics_tick before wants_early_trigger).
class StubEffect:
	extends SpecialEffect
	var physics_tick_calls: int = 0
	var wants_early_trigger_calls: int = 0
	var detonate_calls: int = 0
	var detonate_chain_depths: Array[int] = []
	var call_order: Array[String] = []
	var early_trigger_result: bool = false
	var impact_triggers_result: bool = true
	var needs_landing_result: bool = false
	var lifetime_result: float = -1.0
	var detaches_result: bool = false
	var triggers_on_impact_result: bool = true

	func needs_landing() -> bool:
		return needs_landing_result

	func effect_lifetime_s() -> float:
		return lifetime_result

	func detaches() -> bool:
		return detaches_result

	func triggers_on_impact() -> bool:
		return triggers_on_impact_result

	func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
		return impact_triggers_result

	func physics_tick(_block: Block, _behavior: SpecialBehavior, _delta: float) -> void:
		physics_tick_calls += 1
		call_order.append("physics_tick")

	func wants_early_trigger(_block: Block, _behavior: SpecialBehavior) -> bool:
		wants_early_trigger_calls += 1
		call_order.append("wants_early_trigger")
		return early_trigger_result

	func detonate(_block: Block, _behavior: SpecialBehavior, chain_depth: int) -> void:
		detonate_calls += 1
		detonate_chain_depths.append(chain_depth)
		call_order.append("detonate")


func _make_block(position: Vector3 = Vector3.ZERO, mass: float = 1.0) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = mass
	block.linear_velocity = Vector3.ZERO
	return block


func _make_def(
	arm_delay: float = 0.4, arm_impulse: float = 5.0, fuse_timeout_s: float = 6.0
) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"test_special"
	def.arm_delay = arm_delay
	def.arm_impulse = arm_impulse
	def.fuse_timeout_s = fuse_timeout_s
	return def


func _make_behavior(block: Block, def: SpecialDef) -> SpecialBehavior:
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, _tuning)
	return behavior


## -- bind() / initial state ----------------------------------------------------

## A hard deceleration before arm_delay has elapsed must not trigger --
## activation requires both the impact AND having already armed (spec 2.6).
func test_impact_before_arming_does_not_trigger() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(1.0, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(0.1)  # age 0.1, not armed yet
	block.linear_velocity = Vector3.ZERO  # a hard "impact" while still unarmed
	behavior.advance(0.1)  # age 0.2, still not armed
	assert_false(behavior.is_triggered(), "An impact while unarmed must never trigger.")
	assert_false(behavior.is_armed())


## Once armed, a deceleration at or above arm_impulse (mass * speed drop)
## triggers on the very tick it's detected.
func test_impact_at_or_above_arm_impulse_after_arming_triggers() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(0.1, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms this tick; decel sampled against itself, no trigger
	assert_true(behavior.is_armed())
	assert_false(behavior.is_triggered())

	block.linear_velocity = Vector3(10.0, 0.0, 0.0)  # now moving fast
	behavior.advance(0.01)  # speeding up, never a "decel" -- must not trigger
	assert_false(behavior.is_triggered())

	block.linear_velocity = Vector3.ZERO  # sudden stop: mass(1) * (10 - 0) = 10 >= 5
	behavior.advance(0.01)
	assert_true(behavior.is_triggered(), "mass * speed-drop crossing arm_impulse must trigger.")


func test_impact_below_arm_impulse_after_arming_does_not_trigger() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(0.1, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)
	assert_true(behavior.is_armed())

	block.linear_velocity = Vector3(2.0, 0.0, 0.0)
	behavior.advance(0.01)
	block.linear_velocity = Vector3(0.0, 0.0, 0.0)  # mass(1) * (2 - 0) = 2 < 5
	behavior.advance(0.01)
	assert_false(behavior.is_triggered())


## Review fix (Bontago-1en.12): game/blocks/Block.gd:61-63 skips its own
## velocity-drop impact detection while `sleeping` because Jolt stops
## integrating a sleeping body -- without the matching guard here, a settled
## armed special that later gets bumped awake would read the wake-up itself
## as a false "impact" and detonate spuriously.
func test_impact_while_sleeping_does_not_trigger_even_with_a_large_velocity_drop() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(0.1, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms
	assert_true(behavior.is_armed())

	block.sleeping = true
	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(0.01)  # asleep: baseline re-seeds to 10, no drop test runs
	block.linear_velocity = Vector3.ZERO  # a hard "drop" while still asleep
	behavior.advance(0.01)
	assert_false(
		behavior.is_triggered(),
		"A velocity change on a sleeping body must never be read as an impact."
	)


## A hard deceleration past arm_impulse must NOT call trigger() when the
## effect vetoes it -- the arming-tick self-trigger bug (Bontago-1en.22) this
## hook exists to fix. physics_tick() must keep running regardless (the
## effect's own timed window is what SpecialBehavior must never cut short).
func test_impact_does_not_trigger_when_the_effect_vetoes_it() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(0.1, 5.0, 999.0)
	var stub: StubEffect = StubEffect.new()
	stub.impact_triggers_result = false
	def.effect = stub
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms this tick
	assert_true(behavior.is_armed())

	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(0.01)
	block.linear_velocity = Vector3.ZERO  # mass(1) * (10 - 0) = 10 >= 5: would trigger if allowed
	behavior.advance(0.01)

	assert_false(
		behavior.is_triggered(),
		"impact_triggers() == false must veto the decel-based trigger entirely."
	)
	assert_gt(
		stub.physics_tick_calls, 0,
		"physics_tick() must keep running on every armed tick despite the vetoed impact."
	)


## Chain triggering must bypass the veto entirely: trigger_others_in_range()
## calls trigger() directly, never _check_impact()/impact_triggers().
func test_chain_trigger_still_detonates_an_effect_that_vetoes_impact_triggering() -> void:
	var origin_block: Block = _make_block(Vector3.ZERO)
	var origin_def: SpecialDef = _make_def()
	var origin: SpecialBehavior = _make_behavior(origin_block, origin_def)

	var neighbor_block: Block = _make_block(Vector3(2.0, 0.0, 0.0))
	var neighbor_def: SpecialDef = _make_def()
	var neighbor_stub: StubEffect = StubEffect.new()
	neighbor_stub.impact_triggers_result = false
	neighbor_def.effect = neighbor_stub
	var neighbor: SpecialBehavior = _make_behavior(neighbor_block, neighbor_def)

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, 0)

	assert_true(
		neighbor.is_triggered(),
		"a chain trigger must still detonate an effect that vetoes decel-based impact triggering."
	)
	assert_eq(neighbor_stub.detonate_calls, 1)


## -- effect hooks: physics_tick / wants_early_trigger ------------------------------

func test_force_triggers_at_arm_delay_plus_fuse_timeout_regardless_of_effect() -> void:
	var block: Block = _make_block()
	# 0.25 s steps are exact in binary floating point (unlike 0.1), so summing
	# them can't drift below the 1.0 s threshold by a rounding error and make
	# this test flaky.
	var def: SpecialDef = _make_def(0.25, 999.0, 0.75)  # force-trigger at age 1.0
	var stub: StubEffect = StubEffect.new()
	stub.early_trigger_result = false  # never opts in on its own
	def.effect = stub
	var behavior: SpecialBehavior = _make_behavior(block, def)

	for _i: int in range(3):
		behavior.advance(0.25)  # age reaches 0.75
	assert_false(behavior.is_triggered(), "Must not fire before the fuse timeout.")

	behavior.advance(0.25)  # age reaches 1.0 == arm_delay + fuse_timeout_s
	assert_true(behavior.is_triggered(), "Fuse must force-trigger once the timeout elapses.")


## -- trigger() idempotency and signal -----------------------------------------------

func test_trigger_is_idempotent() -> void:
	var block: Block = _make_block()
	var def: SpecialDef = _make_def()
	var stub: StubEffect = StubEffect.new()
	def.effect = stub
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.trigger(0)
	behavior.trigger(0)
	behavior.trigger(1)
	assert_eq(stub.detonate_calls, 1, "detonate() must run exactly once no matter how many times trigger() is called.")


func _behavior_at(position: Vector3) -> SpecialBehavior:
	var block: Block = _make_block(position)
	var def: SpecialDef = _make_def()
	return _make_behavior(block, def)


func test_filter_in_range_keeps_only_candidates_within_radius() -> void:
	var near: SpecialBehavior = _behavior_at(Vector3(2.0, 0.0, 0.0))
	var far: SpecialBehavior = _behavior_at(Vector3(20.0, 0.0, 0.0))
	var self_behavior: SpecialBehavior = _behavior_at(Vector3.ZERO)
	var candidates: Array[SpecialBehavior] = [near, far]

	var result: Array[SpecialBehavior] = self_behavior._filter_in_range(candidates, Vector3.ZERO, 5.0, 0)
	assert_eq(result, [near])


func test_trigger_others_in_range_triggers_survivors_one_depth_deeper() -> void:
	var origin_block: Block = _make_block(Vector3.ZERO)
	var origin_def: SpecialDef = _make_def()
	var origin: SpecialBehavior = _make_behavior(origin_block, origin_def)

	var neighbor_block: Block = _make_block(Vector3(2.0, 0.0, 0.0))
	var neighbor_def: SpecialDef = _make_def()
	var neighbor: SpecialBehavior = _make_behavior(neighbor_block, neighbor_def)

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, 1)
	assert_true(neighbor.is_triggered())
	assert_eq(neighbor.chain_depth(), 2)
