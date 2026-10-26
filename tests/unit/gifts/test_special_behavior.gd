extends GutTest
## SpecialBehavior checks (spec 1.6): arming,
## impact-triggered activation, the effect hooks, the fuse timeout, and the
## chain-cap semantics -- all pure logic, no physics simulation. Every test
## drives SpecialBehavior.advance(delta) directly (not _physics_process, and
## no scene-tree physics tick) with a stub Block whose linear_velocity/mass
## the test sets by hand, exactly as the design specifies.

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
## activation requires both the impact AND having already armed (spec 1.6).
func test_impact_before_arming_does_not_trigger() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(1.0, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(0.1)  # age 0.1, not armed yet
	block.linear_velocity = Vector3.ZERO  # a hard "impact" while still unarmed
	behavior.advance(0.1)  # age 0.2, still not armed
	assert_false(behavior.is_triggered(), "An impact while unarmed must never trigger.")


## Once armed, a deceleration at or above arm_impulse (mass * speed drop)
## triggers on the very tick it's detected.
func test_impact_at_or_above_arm_impulse_after_arming_triggers() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(0.1, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms this tick; decel sampled against itself, no trigger
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

	block.linear_velocity = Vector3(2.0, 0.0, 0.0)
	behavior.advance(0.01)
	block.linear_velocity = Vector3(0.0, 0.0, 0.0)  # mass(1) * (2 - 0) = 2 < 5
	behavior.advance(0.01)
	assert_false(behavior.is_triggered())


## Review fix: game/blocks/Block.gd:61-63 skips its own
## velocity-drop impact detection while `sleeping` because Jolt stops
## integrating a sleeping body -- without the matching guard here, a settled
## armed special that later gets bumped awake would read the wake-up itself
## as a false "impact" and detonate spuriously.
func test_impact_while_sleeping_does_not_trigger_even_with_a_large_velocity_drop() -> void:
	var block: Block = _make_block(Vector3.ZERO, 1.0)
	var def: SpecialDef = _make_def(0.1, 5.0, 999.0)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)  # arms

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
## effect vetoes it -- the arming-tick self-trigger bug this
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


func test_trigger_others_in_range_triggers_only_candidates_within_radius() -> void:
	var near: SpecialBehavior = _behavior_at(Vector3(2.0, 0.0, 0.0))
	var far: SpecialBehavior = _behavior_at(Vector3(20.0, 0.0, 0.0))
	var self_behavior: SpecialBehavior = _behavior_at(Vector3.ZERO)

	self_behavior.trigger_others_in_range(Vector3.ZERO, 5.0, 0)

	assert_true(near.is_triggered(), "a special inside the radius is chained")
	assert_false(far.is_triggered(), "a special outside the radius is left alone")
	assert_false(self_behavior.is_triggered(), "the caller is never its own chain target")


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


## -- chain order, cap, freed candidates (through real behaviours) --------------------

## Detonating chains into everything within `reach` of the carrier, as the real effects do.
class ChainEffect:
	extends SpecialEffect
	var reach: float = 1.5
	var order: Array[StringName] = []

	func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
		order.append(StringName(block.name))
		behavior.trigger_others_in_range(block.global_position, reach, chain_depth)


class CountingState:
	extends EffectState
	var marker: int = 7


class StatefulEffect:
	extends SpecialEffect

	func new_state() -> EffectState:
		return CountingState.new()


func _chain_link(effect: SpecialEffect, link_name: String, position: Vector3) -> SpecialBehavior:
	var block: Block = _make_block(position)
	block.name = link_name
	var def: SpecialDef = _make_def()
	def.effect = effect
	return _make_behavior(block, def)


func test_live_lists_bound_behaviours_in_the_order_they_were_bound() -> void:
	var third: SpecialBehavior = _behavior_at(Vector3(3.0, 0.0, 0.0))
	var first: SpecialBehavior = _behavior_at(Vector3(1.0, 0.0, 0.0))
	var second: SpecialBehavior = _behavior_at(Vector3(2.0, 0.0, 0.0))

	var mine: Array[SpecialBehavior] = []
	for behavior: SpecialBehavior in SpecialBehavior.live(get_tree()):
		if behavior == first or behavior == second or behavior == third:
			mine.append(behavior)

	assert_eq(mine, [third, first, second] as Array[SpecialBehavior])


func test_live_excludes_a_freed_behaviour() -> void:
	var kept: SpecialBehavior = _behavior_at(Vector3.ZERO)
	var gone: SpecialBehavior = _behavior_at(Vector3(1.0, 0.0, 0.0))
	var gone_id: int = gone.get_instance_id()

	gone.free()

	var live: Array[SpecialBehavior] = SpecialBehavior.live(get_tree())
	assert_true(kept in live)
	for behavior: SpecialBehavior in live:
		assert_ne(behavior.get_instance_id(), gone_id, "live() never lists the freed behaviour")


func test_live_skips_nodes_in_the_group_that_are_not_behaviours() -> void:
	var impostor: Node = Node.new()
	impostor.add_to_group(SpecialBehavior.GROUP)
	add_child_autofree(impostor)
	var real: SpecialBehavior = _behavior_at(Vector3.ZERO)

	var live: Array[SpecialBehavior] = SpecialBehavior.live(get_tree())

	assert_true(real in live)
	for behavior: SpecialBehavior in live:
		assert_ne(behavior.get_instance_id(), impostor.get_instance_id())


func test_live_omits_a_behaviour_that_was_never_bound() -> void:
	var unbound: SpecialBehavior = SpecialBehavior.new()
	add_child_autofree(unbound)
	assert_false(unbound in SpecialBehavior.live(get_tree()))


func test_chain_triggers_in_binding_order_one_depth_deeper_each_link() -> void:
	var effect: ChainEffect = ChainEffect.new()
	var a: SpecialBehavior = _chain_link(effect, "a", Vector3.ZERO)
	var b: SpecialBehavior = _chain_link(effect, "b", Vector3(1.0, 0.0, 0.0))
	var c: SpecialBehavior = _chain_link(effect, "c", Vector3(2.0, 0.0, 0.0))

	a.trigger(0)

	assert_eq(effect.order, [&"a", &"b", &"c"] as Array[StringName])
	assert_eq([a.chain_depth(), b.chain_depth(), c.chain_depth()], [0, 1, 2])


func test_chain_stops_extending_at_the_depth_cap_but_the_capped_link_still_detonates() -> void:
	_tuning.max_chain_depth = 2
	var effect: ChainEffect = ChainEffect.new()
	var links: Array[SpecialBehavior] = []
	for i: int in range(5):
		links.append(_chain_link(effect, "n%d" % i, Vector3(float(i), 0.0, 0.0)))

	links[0].trigger(0)

	assert_true(links[2].is_triggered(), "the link reached at the cap still detonates")
	assert_eq(links[2].chain_depth(), 2)
	assert_false(links[3].is_triggered(), "a detonation at the cap starts no further chain")
	assert_false(links[4].is_triggered())


func test_chain_below_the_cap_reaches_and_at_the_cap_does_not() -> void:
	var origin: SpecialBehavior = _behavior_at(Vector3.ZERO)
	var neighbor: SpecialBehavior = _behavior_at(Vector3(1.0, 0.0, 0.0))

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, _tuning.max_chain_depth)
	assert_false(neighbor.is_triggered(), "chain_depth at max_chain_depth extends nothing")

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, _tuning.max_chain_depth - 1)
	assert_true(neighbor.is_triggered())
	assert_eq(neighbor.chain_depth(), _tuning.max_chain_depth)


func test_chain_skips_a_special_that_already_triggered() -> void:
	var effect: ChainEffect = ChainEffect.new()
	var origin: SpecialBehavior = _chain_link(effect, "o", Vector3.ZERO)
	var done: SpecialBehavior = _chain_link(effect, "done", Vector3(1.0, 0.0, 0.0))
	done.trigger(0)
	effect.order.clear()

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, 3)

	assert_eq(done.chain_depth(), 0, "an already-triggered special keeps its own depth")
	assert_eq(effect.order.size(), 0, "and detonates no second time")


func test_chain_ignores_a_freed_neighbour_and_still_reaches_the_rest() -> void:
	var origin: SpecialBehavior = _behavior_at(Vector3.ZERO)
	var gone: SpecialBehavior = _behavior_at(Vector3(1.0, 0.0, 0.0))
	var alive: SpecialBehavior = _behavior_at(Vector3(2.0, 0.0, 0.0))
	gone.free()

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, 0)

	assert_true(alive.is_triggered())


func test_chain_ignores_non_behaviour_nodes_in_the_group() -> void:
	var impostor: Node = Node.new()
	impostor.add_to_group(SpecialBehavior.GROUP)
	add_child_autofree(impostor)
	var origin: SpecialBehavior = _behavior_at(Vector3.ZERO)
	var neighbor: SpecialBehavior = _behavior_at(Vector3(1.0, 0.0, 0.0))

	origin.trigger_others_in_range(Vector3.ZERO, 5.0, 0)

	assert_true(neighbor.is_triggered())


## -- def_id() / state() ---------------------------------------------------------------

func test_def_id_is_empty_before_bind_and_the_def_id_after() -> void:
	var fresh: SpecialBehavior = SpecialBehavior.new()
	add_child_autofree(fresh)
	assert_eq(fresh.def_id(), &"")

	var def: SpecialDef = _make_def()
	def.id = &"probe_special"
	fresh.bind(_make_block(), def, _tuning)

	assert_eq(fresh.def_id(), &"probe_special")


func test_state_is_null_before_bind() -> void:
	var fresh: SpecialBehavior = SpecialBehavior.new()
	add_child_autofree(fresh)
	assert_null(fresh.state())


func test_state_is_null_for_a_stateless_effect_and_for_a_def_without_effect() -> void:
	var plain: SpecialBehavior = _behavior_at(Vector3.ZERO)
	assert_null(plain.state(), "no effect assigned")

	var def: SpecialDef = _make_def()
	def.effect = StubEffect.new()
	var stateless: SpecialBehavior = _make_behavior(_make_block(), def)
	assert_null(stateless.state(), "an effect whose new_state() is null")


func test_state_is_the_effects_state_after_bind() -> void:
	var def: SpecialDef = _make_def()
	def.effect = StatefulEffect.new()
	var behavior: SpecialBehavior = _make_behavior(_make_block(), def)

	var state: EffectState = behavior.state()

	assert_true(state is CountingState)
	assert_same(behavior.state(), state, "state() keeps returning the one taken at bind")


func test_each_bind_takes_a_fresh_state_per_activation() -> void:
	var def: SpecialDef = _make_def()
	def.effect = StatefulEffect.new()
	var first: SpecialBehavior = _make_behavior(_make_block(), def)
	var second: SpecialBehavior = _make_behavior(_make_block(), def)

	assert_not_same(first.state(), second.state(), "two activations of one shared effect never share state")

	var before: EffectState = first.state()
	first.bind(first.get_parent() as Block, def, _tuning)
	assert_not_same(first.state(), before, "re-binding takes a new state")
