extends GutTest
## game/blocks/Block.gd's reason-tracked freeze API (spec 3.5 "Stable-block
## optimization" [NEW], docs/M8_PLAN.md P5, Interface stubs item 2):
## request_freeze_static()/release_freeze_static()/is_freeze_static()/
## wake_for_impulse(). A bare Block (no BlockFactory, no BlockRegistry, no
## real physics step) is enough here -- these are plain field/property writes,
## the same bare-stub-Block pattern tests/unit/gifts/test_special_behavior.gd and
## tests/unit/gifts/test_jumping_bean_effect.gd already use for Block-only checks.


func _make_block() -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	return block


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


