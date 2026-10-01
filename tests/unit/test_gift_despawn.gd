extends GutTest
## Bontago-t8x.5: an activated gift's body despawns once its action completed.
## Three categories: consumed instantly, survives its action then despawns,
## and an action that never completes (bounded timeout). Pure-logic cases
## drive SpecialBehavior.advance() on a stub Block.

var _tuning: SpecialTuning = null
var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	_tuning = SpecialTuning.new()
	_tuning.gift_despawn_delay_s = 0.5
	_tuning.gift_max_lifetime_s = 10.0


class StubEffect:
	extends SpecialEffect
	var early_trigger_result: bool = false
	var detonations: int = 0

	func wants_early_trigger(_block: Block, _behavior: SpecialBehavior) -> bool:
		return early_trigger_result

	func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
		detonations += 1


func _make(effect: SpecialEffect, gift: bool, fuse: float = 6.0) -> SpecialBehavior:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	var def: SpecialDef = SpecialDef.new()
	def.arm_delay = 0.1
	def.arm_impulse = 5.0
	def.fuse_timeout_s = fuse
	def.effect = effect
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, _tuning)
	behavior.despawn_when_done = gift
	return behavior


func _run(behavior: SpecialBehavior, seconds: float) -> void:
	var steps: int = int(ceil(seconds * 60.0))
	for _i: int in range(steps):
		behavior.advance(1.0 / 60.0)


## Category 1: instant effect (Bomb/Anvil/Cat/Glue/Paintball/Stackfall shape);
## the action finishes inside detonate(), so the body goes after the linger.
func test_instant_effect_despawns_after_linger_once() -> void:
	var behavior: SpecialBehavior = _make(StubEffect.new(), true)
	watch_signals(behavior)
	_run(behavior, 0.2)
	behavior.trigger(0)
	assert_signal_not_emitted(behavior, "completed", "not before the linger elapses")
	_run(behavior, 0.4)
	assert_signal_not_emitted(behavior, "completed")
	_run(behavior, 0.2)
	assert_signal_emit_count(behavior, "completed", 1)
	_run(behavior, 1.0)
	assert_signal_emit_count(behavior, "completed", 1, "completes exactly once")


## Category 2: timed window (Propeller/Jumping Bean/Earthquake/Volcano/Magnet/
## Rocket); the body survives its whole window, completion follows the
## window-end trigger.
func test_timed_window_survives_until_its_window_ends_then_despawns() -> void:
	var effect: StubEffect = StubEffect.new()
	var behavior: SpecialBehavior = _make(effect, true)
	watch_signals(behavior)
	_run(behavior, 2.0)
	assert_signal_not_emitted(behavior, "completed", "mid-window the gift is alive")
	assert_false(behavior.is_triggered())
	effect.early_trigger_result = true
	_run(behavior, 0.1)
	assert_true(behavior.is_triggered())
	assert_signal_not_emitted(behavior, "completed")
	_run(behavior, 0.6)
	assert_signal_emit_count(behavior, "completed", 1)


## Category 3: an action that never completes still goes, first through the
## fuse timeout, and past a def with an absurd fuse via the config backstop.
func test_dud_gift_despawns_via_fuse_timeout() -> void:
	var behavior: SpecialBehavior = _make(StubEffect.new(), true, 2.0)
	watch_signals(behavior)
	_run(behavior, 2.4)
	assert_true(behavior.is_triggered(), "fuse fired")
	_run(behavior, 0.7)
	assert_signal_emit_count(behavior, "completed", 1)


func test_dud_gift_with_no_fuse_hits_the_max_lifetime_backstop() -> void:
	var behavior: SpecialBehavior = _make(StubEffect.new(), true, 99999.0)
	watch_signals(behavior)
	_run(behavior, 9.5)
	assert_signal_not_emitted(behavior, "completed")
	_run(behavior, 1.0)
	assert_signal_emit_count(behavior, "completed", 1)
	assert_false(behavior.is_triggered(), "never triggered, only removed")


## Non-gift behaviors (Volcano orbs, plain blocks) are never despawned.
func test_non_gift_behavior_never_completes() -> void:
	var behavior: SpecialBehavior = _make(StubEffect.new(), false, 1.0)
	watch_signals(behavior)
	_run(behavior, 5.0)
	assert_true(behavior.is_triggered())
	assert_signal_not_emitted(behavior, "completed")


# --- host integration: normal removal path ----------------------------------


func _start_host_match() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 13579
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	if _blocks_root != null and is_instance_valid(_blocks_root):
		for child: Node in _blocks_root.get_children():
			child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func test_host_gift_removal_uses_block_removed_and_leaves_plain_blocks() -> void:
	_start_host_match()
	var cube: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var plain: Block = Match.spawn_special_projectile(
		cube, _field.to_global(Vector3(0.0, 5.0, 0.0)), Basis.IDENTITY, 0, Vector3.ZERO, null, null
	)
	var gift: Block = Match.spawn_special_projectile(
		cube, _field.to_global(Vector3(3.0, 5.0, 0.0)), Basis.IDENTITY, 0, Vector3.ZERO, null, null
	)
	Match._gifts.apply_replicated_claim(1, 0, &"bomb")
	Match._gifts.activate_next_special(0)
	Match._placement._attach_pending_special(gift, 0)
	var behavior: SpecialBehavior = null
	for child: Node in gift.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior)
	assert_true(behavior.despawn_when_done)
	var removed: Array = []
	var on_removed: Callable = func(b: RigidBody3D, reason: String) -> void: removed.append([b, reason])
	Events.block_removed.connect(on_removed)
	var revision: int = _registry.territory_revision()

	behavior.trigger(0)
	_run(behavior, 1.0)

	Events.block_removed.disconnect(on_removed)
	assert_eq(removed.size(), 1)
	assert_eq(removed[0][0], gift)
	assert_eq(removed[0][1], String(Events.REASON_GIFT_DESPAWN))
	assert_true(gift.is_queued_for_deletion())
	assert_false(plain.is_queued_for_deletion())
	assert_gt(_registry.territory_revision(), revision, "registry updated through block_removed")
