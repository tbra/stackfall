extends GutTest
## game/Block.gd's reason-tracked freeze API (spec 3.5 "Stable-block
## optimization" [NEW], docs/M8_PLAN.md P5, Interface stubs item 2):
## request_freeze_static()/release_freeze_static()/is_freeze_static()/
## wake_for_impulse(). A bare Block (no BlockFactory, no BlockRegistry, no
## real physics step) is enough here -- these are plain field/property writes,
## the same bare-stub-Block pattern tests/unit/test_special_behavior.gd and
## tests/unit/test_jumping_bean_effect.gd already use for Block-only checks.


func _make_block() -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	return block


func test_no_reason_ever_requested_leaves_freeze_state_at_rigidbody_defaults() -> void:
	var block: Block = _make_block()
	assert_false(block.is_freeze_static(), "a fresh block holds no freeze reason")
	assert_false(block.freeze, "freeze is off by default")
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_STATIC,
		"freeze_mode is STATIC by default (RigidBody3D's own class default; there is no FREEZE_MODE_RIGID -- freeze_mode is simply inert while freeze is false)"
	)


func test_request_freeze_static_freezes_and_release_unfreezes() -> void:
	var block: Block = _make_block()

	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_true(block.is_freeze_static())
	assert_true(block.freeze)
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC)

	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_false(block.is_freeze_static())
	assert_false(block.freeze)
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_STATIC,
		"freeze_mode is left at STATIC after release -- it's inert once freeze is false, nothing resets it"
	)


func test_two_independent_reasons_both_required_to_unfreeze() -> void:
	var block: Block = _make_block()
	var other_reason: StringName = &"a_future_freeze_special"

	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	block.request_freeze_static(other_reason)
	assert_true(block.is_freeze_static())
	assert_true(block.freeze)
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC)

	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_true(block.is_freeze_static(), "the other reason still holds it frozen")
	assert_true(block.freeze, "freeze must stay on while any reason remains")
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC)

	block.release_freeze_static(other_reason)
	assert_false(block.is_freeze_static(), "unfrozen only once every reason is gone")
	assert_false(block.freeze)
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_STATIC,
		"freeze_mode is left at STATIC after release -- it's inert once freeze is false, nothing resets it"
	)


func test_request_freeze_static_is_idempotent_for_the_same_reason() -> void:
	var block: Block = _make_block()
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_true(block.is_freeze_static())

	# A single release of the same reason is enough -- a duplicate request
	# never opened a second, separately-held copy of it.
	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_false(block.is_freeze_static())


func test_release_freeze_static_on_an_unheld_reason_is_a_no_op() -> void:
	var block: Block = _make_block()
	# Never frozen at all -- releasing a reason it never held must not throw
	# and must not disturb its (already-unfrozen) state.
	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_false(block.is_freeze_static())
	assert_false(block.freeze)

	# Held by one reason; releasing an unrelated, never-requested reason must
	# leave the real one untouched.
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	block.release_freeze_static(&"never_requested")
	assert_true(block.is_freeze_static())
	assert_true(block.freeze)


func test_wake_for_impulse_releases_only_the_stable_reason() -> void:
	var block: Block = _make_block()
	var other_reason: StringName = &"a_future_freeze_special"

	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	block.request_freeze_static(other_reason)

	block.wake_for_impulse()
	assert_true(block.is_freeze_static(), "the other reason must survive wake_for_impulse()")
	assert_true(block.freeze)
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC)

	block.release_freeze_static(other_reason)
	assert_false(block.is_freeze_static())


func test_wake_for_impulse_on_a_block_frozen_only_by_stable_fully_unfreezes_it() -> void:
	var block: Block = _make_block()
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)

	block.wake_for_impulse()
	assert_false(block.is_freeze_static())
	assert_false(block.freeze)
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_STATIC,
		"freeze_mode is left at STATIC after release -- it's inert once freeze is false, nothing resets it"
	)


func test_wake_for_impulse_on_a_never_frozen_block_is_a_no_op() -> void:
	var block: Block = _make_block()
	block.wake_for_impulse()
	assert_false(block.is_freeze_static())
	assert_false(block.freeze)
