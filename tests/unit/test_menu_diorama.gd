extends GutTest


func test_diorama_reuses_visual_block_and_pauses_when_hidden() -> void:
	var diorama: MenuDiorama = MenuDiorama.new()
	add_child_autofree(diorama)
	assert_not_null(diorama._falling_block)
	assert_false(diorama._falling_block is RigidBody3D)
	var count: int = diorama._viewport.get_child_count()
	diorama._elapsed_s = diorama.tuning.falling_block_interval_s * 0.5
	diorama._animate_falling_block()
	assert_false(diorama._falling_block.visible)
	diorama._elapsed_s = 0.0
	diorama._animate_falling_block()
	assert_true(diorama._falling_block.visible)
	assert_eq(diorama._viewport.get_child_count(), count)
	diorama.hide()
	assert_false(diorama.is_processing())
	assert_eq(diorama._viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	diorama.show()
	assert_true(diorama.is_processing())
