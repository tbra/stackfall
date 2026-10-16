extends GutTest
## FreezeEffect (spec 2.6 "[NEW] (defensive, cuts down on luck)" row --
## "Makes your own blocks within 6 m static for 20 s"; docs/M8_PLAN.md's P2
## package). detonate() has no physics_tick()/wants_early_trigger() override
## -- every scenario below calls it directly against real Block bodies added
## to the test's own tree, the same physics-smoke-test shape
## tests/unit/gifts/test_glue_effect.gd uses.
##
## The 20 s release Timer is driven synthetically by finding the Timer child
## FreezeEffect._freeze_and_schedule_release() parents under the frozen block
## and emitting its own `timeout` signal directly -- no real wait, matching
## this package's brief ("drive the Timer via its timeout emit... don't wait
## 20 s").

const RADIUS: float = 6.0
const DURATION: float = 20.0

var _nodes: Array[Node] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in
## the physics world for even one frame into the next test, mirroring
## tests/unit/gifts/test_glue_effect.gd's own after_each().
func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


## A real Block with a small sphere collider and owner_slot set, mirroring
## tests/unit/gifts/test_glue_effect.gd's own _make_block().
func _make_block(position: Vector3, owner_slot: int) -> Block:
	var block: Block = Block.new()
	block.owner_slot = owner_slot
	block.mass = 1.0
	block.gravity_scale = 0.0
	block.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.linear_damp = 0.0
	block.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.angular_damp = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	block.add_child(collision)
	# DECISION (tests/unit/gifts/test_freeze_effect.gd, matches
	# tests/unit/gifts/test_glue_effect.gd's own DECISION): add_child() before
	# setting global_position -- Node3D.global_position needs
	# is_inside_tree() to resolve a global transform.
	add_child(block)
	block.global_position = position
	_nodes.append(block)
	return block


func _make_effect() -> FreezeEffect:
	var effect: FreezeEffect = FreezeEffect.new()
	effect.freeze_radius_m = RADIUS
	effect.freeze_duration_s = DURATION
	return effect


## Every release Timer this special creates is a direct child of the block it
## freezes (FreezeEffect.freeze_block()'s own build order).
func _find_release_timer(block: Node) -> Timer:
	return block.get_node_or_null(NodePath(FreezeEffect.TIMER_NAME)) as Timer


# --- detonate(): own-owner blocks within radius are frozen ------------------

func test_detonate_freezes_own_owner_blocks_within_radius() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var neighbor: Block = _make_block(Vector3(2.0, 0.0, 0.0), 3)
	var effect: FreezeEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)

	assert_true(host.is_freeze_static(), "the detonating block is one of 'your own blocks' too")
	assert_true(neighbor.is_freeze_static(), "an own-owner block within radius must be frozen")
	assert_not_null(_find_release_timer(host), "the host must get its own release Timer")
	assert_not_null(_find_release_timer(neighbor), "the neighbor must get its own release Timer")


# --- detonate(): an enemy block within radius is left untouched -------------

func test_detonate_does_not_freeze_an_enemy_block_within_radius() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var enemy: Block = _make_block(Vector3(2.0, 0.0, 0.0), 4)
	var effect: FreezeEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)

	assert_false(enemy.is_freeze_static(), "a different player's block within radius must not be frozen")
	assert_null(_find_release_timer(enemy), "an untouched block gets no release Timer")


# --- detonate(): an own-owner block outside radius is left untouched --------

func test_detonate_does_not_freeze_an_own_owner_block_outside_radius() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var far: Block = _make_block(Vector3(RADIUS + 2.0, 0.0, 0.0), 3)
	var effect: FreezeEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)

	assert_false(far.is_freeze_static(), "an own-owner block outside freeze_radius_m must not be frozen")
	assert_null(_find_release_timer(far), "an untouched block gets no release Timer")


# --- release Timer: firing calls release_freeze_static() and unfreezes -----

func test_release_timer_timeout_unfreezes_the_block() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var effect: FreezeEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)
	assert_true(host.is_freeze_static())

	var timer: Timer = _find_release_timer(host)
	assert_not_null(timer, "the host must have its own release Timer")
	timer.timeout.emit()

	assert_false(host.is_freeze_static(), "the release Timer's own timeout must unfreeze the block")
	assert_false(host.freeze)


# --- release Timer: a block also held by the stable-freeze reason stays ----
# --- frozen after the Freeze release (reason-keyed independence) -----------

func test_release_timer_timeout_does_not_unfreeze_a_block_still_held_stable() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var effect: FreezeEffect = _make_effect()
	await wait_physics_frames(2)

	# A separate freeze source (StableBlockManager's own reason, per
	# docs/M8_PLAN.md's P5 package) holds this block frozen independently of
	# the Freeze special.
	host.request_freeze_static(Block.FREEZE_REASON_STABLE)

	effect.detonate(host, null, 0)
	assert_true(host.is_freeze_static())

	var timer: Timer = _find_release_timer(host)
	assert_not_null(timer)
	timer.timeout.emit()

	assert_true(
		host.is_freeze_static(), "a block still held by another freeze reason must stay frozen"
	)
	assert_true(host.freeze)

	# Cleanup: release the remaining reason so this test doesn't leak state
	# into is_freeze_static()'s own contract for anything reading `host` after.
	host.release_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_false(host.is_freeze_static())


# --- Bontago-8or.2 additions -------------------------------------------------

func test_explosion_impulse_and_wake_do_not_move_a_frozen_block() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var effect: FreezeEffect = _make_effect()
	await wait_physics_frames(2)
	effect.detonate(host, null, 0)
	SpecialPhysics.wake_and_impulse(host, Vector3(0, 50, 0))
	await wait_physics_frames(3)
	assert_true(host.is_freeze_static(), "Freeze holds against wake_and_impulse")
	assert_almost_eq(host.global_position.y, 0.0, 0.001)
	_find_release_timer(host).timeout.emit()
	SpecialPhysics.wake_and_impulse(host, Vector3(0, 5, 0))
	assert_false(host.is_freeze_static())


func test_gift_body_is_not_frozen_and_despawns_after_action() -> void:
	var gift: Block = _make_block(Vector3.ZERO, 3)
	var neighbor: Block = _make_block(Vector3(1.0, 0.0, 0.0), 3)
	var effect: FreezeEffect = _make_effect()
	var def: SpecialDef = SpecialDef.new()
	def.arm_delay = 0.1
	def.effect = effect
	var tuning: SpecialTuning = SpecialTuning.new()
	tuning.gift_despawn_delay_s = 0.5
	var behavior: SpecialBehavior = SpecialBehavior.new()
	gift.add_child(behavior)
	behavior.bind(gift, def, tuning)
	behavior.despawn_when_done = true
	watch_signals(behavior)
	await wait_physics_frames(2)
	behavior.trigger(0)
	assert_true(neighbor.is_freeze_static())
	assert_false(gift.is_freeze_static(), "the despawning gift is not frozen")
	for _i: int in range(40):
		behavior.advance(1.0 / 60.0)
	assert_signal_emit_count(behavior, "completed", 1)
