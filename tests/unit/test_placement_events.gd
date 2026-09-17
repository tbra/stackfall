extends GutTest
## Step 4 (spec 2.5/3.2), updated for M2 (docs/M2_PLAN.md P4): ghost_place now
## sends exactly one placement intent to Match.request_place() (spec 3.4,
## "clients send intents; the host checks every intent before acting on
## it") instead of building the Block itself. Match — a FakeMatch here,
## standing in for P2's not-yet-landed implementation, see
## tests/unit/support/FakeMatch.gd — decides whether to spawn it and reports
## back on the Events bus exactly as the real one will.


func test_place_sends_the_ghost_transform_to_match_which_spawns_and_reports() -> void:
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
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.spawn_parent = blocks_root
	fake_match.spawn_on_ok = true
	fake_match.held_shapes[0] = cube_shape
	controller._match = fake_match

	watch_signals(Events)

	controller._place_ghost_block()

	assert_eq(fake_match.request_place_calls.size(), 1, "ghost_place should send exactly one placement intent.")
	assert_eq(fake_match.request_place_calls[0]["slot_id"], 0)

	assert_eq(blocks_root.get_child_count(), 1, "Match should have spawned exactly one block.")
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


func test_ghost_place_action_sends_exactly_one_intent() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	ghost.set_shape(cube_shape)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.held_shapes[0] = cube_shape
	controller._match = fake_match

	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.device = -1
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(click.is_action_pressed(&"ghost_place"), "Left click should map to ghost_place.")

	controller._unhandled_input(click)

	assert_eq(
		fake_match.request_place_calls.size(), 1,
		"A left-click ghost_place should send exactly one placement intent."
	)


func test_a_rejected_placement_emits_the_event_and_spawns_nothing_locally() -> void:
	# docs/M2_PLAN.md owner decision 2: every invalid release burns the block
	# — decided inside Match.request_place, which the controller never
	# second-guesses. From PlayerController's side a rejection only means
	# Events.placement_rejected fires and the ghost plays its reject flash
	# (game/GhostPreview.gd); it never spawns anything itself either way.
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	ghost.set_shape(cube_shape)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.held_shapes[0] = cube_shape
	fake_match.next_request_result = PlacementRules.REASON_CONTESTED
	controller._match = fake_match

	watch_signals(Events)

	controller._place_ghost_block()

	assert_signal_emitted_with_parameters(Events, "placement_rejected", [0, PlacementRules.REASON_CONTESTED])
	assert_almost_eq(
		ghost.current_tint_color().r, ghost.ghost_tuning.reject_flash_color.r, 0.001,
		"A rejected placement should flash the ghost (spec 2.2's reject animation)."
	)
