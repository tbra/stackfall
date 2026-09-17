extends GutTest
## Step 4 (spec 2.5/3.2): ghost_place spawns the real block at the ghost's
## transform, feeds the ghost its next shape, and reports on the Events bus.


func test_place_spawns_block_at_ghost_transform_and_feeds_next() -> void:
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	ghost.set_shape(cube_shape)
	ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(0))
	ghost.global_position = Vector3(3.0, 7.0, -2.0)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._spawn_parent = blocks_root

	watch_signals(Events)

	controller._place_ghost_block()

	assert_eq(blocks_root.get_child_count(), 1, "ghost_place should spawn exactly one block.")
	var placed: Block = blocks_root.get_child(0) as Block
	assert_not_null(placed)
	assert_eq(placed.shape_id, cube_shape.id)
	assert_true(placed.global_position.is_equal_approx(Vector3(3.0, 7.0, -2.0)))
	assert_true(
		placed.global_transform.basis.is_equal_approx(BlockOrientations.get_basis(BlockOrientations.step_yaw_ccw(0))),
		"The spawned block should carry the ghost's exact orientation."
	)

	assert_signal_emitted(Events, "block_placed")
	assert_signal_emitted_with_parameters(Events, "block_placed", [placed, cube_shape.id])

	assert_not_null(ghost.get_shape(), "Placing should immediately feed the ghost a new shape (spec 2.5).")


func test_ghost_place_action_triggers_placement() -> void:
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._spawn_parent = blocks_root

	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.device = -1
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(click.is_action_pressed(&"ghost_place"), "Left click should map to ghost_place.")

	controller._unhandled_input(click)

	assert_eq(blocks_root.get_child_count(), 1, "A left-click ghost_place should place a block.")
