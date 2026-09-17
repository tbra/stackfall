extends GutTest
## M1 acceptance: "You can build a stable 30-block tower... with mouse and
## keyboard and with a gamepad." This drives the real placement path
## (PlayerController._place_ghost_block) the way ghost_place does, stacks 30
## cubes, lets physics settle for 10 s, and checks the tower is still
## standing and asleep. The gamepad half is covered by
## test_playercontroller_gamepad.gd's synthetic-input test.

const TOWER_HEIGHT: int = 30
const SETTLE_SECONDS: float = 10.0
const MAX_TOP_DRIFT: float = 2.0
## Real settle time between placements rather than all 30 at once or a couple
## of ticks apart — spec 2.8's block timer is 3-12 s, never sub-frame, and a
## freshly dropped cube needs a moment to genuinely come to rest before the
## next one lands on it.
const TICKS_BETWEEN_PLACEMENTS: int = 30


func test_thirty_cube_tower_stands_and_sleeps() -> void:
	var field: Field = autofree(Field.new())
	add_child_autofree(field)

	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)

	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(cube_shape)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._spawn_parent = blocks_root

	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var edge: float = tuning.cube_size - tuning.cube_margin

	# Each new cube targets the PREVIOUS cube's actual settled position (not
	# a precomputed ideal grid coordinate), matching a real ghost raycasting
	# onto wherever the stack currently is.
	var next_position: Vector3 = Vector3(0.0, edge * 0.5, 0.0)
	for i: int in range(TOWER_HEIGHT):
		ghost.reset_rotation()
		ghost.global_position = next_position
		controller._place_ghost_block()
		# _place_ghost_block() advances the feed to a random shape for the
		# NEXT ghost (spec 2.4's plain M1 pick) — force it back to cube so
		# every block in this tower is uniform, which is the point of the
		# test. The real feed's variety is exercised by
		# test_simple_block_feed.gd instead.
		ghost.set_shape(cube_shape)

		for _settle_tick: int in range(TICKS_BETWEEN_PLACEMENTS):
			await get_tree().physics_frame

		var placed: Node3D = blocks_root.get_child(i)
		next_position = placed.global_position + Vector3(0.0, edge, 0.0)

	assert_eq(blocks_root.get_child_count(), TOWER_HEIGHT, "All 30 placements should have spawned a block.")

	var top_block: Block = blocks_root.get_child(TOWER_HEIGHT - 1) as Block
	assert_not_null(top_block)
	var start_top_y: float = top_block.global_position.y

	var ticks: int = int(round(SETTLE_SECONDS * Engine.physics_ticks_per_second))
	for _tick: int in range(ticks):
		await get_tree().physics_frame

	var end_top_y: float = top_block.global_position.y
	var drift: float = absf(end_top_y - start_top_y)
	assert_lt(drift, MAX_TOP_DRIFT, "The 30-cube tower should not collapse; top block drifted %.3f m." % drift)

	var awake_indices: Array[int] = []
	for i: int in range(blocks_root.get_child_count()):
		var body: RigidBody3D = blocks_root.get_child(i) as RigidBody3D
		if body != null and not body.sleeping:
			awake_indices.append(i)
	assert_eq(
		awake_indices, [] as Array[int],
		"All 30 blocks should be asleep after %.0f s of settling; still awake: %s" % [SETTLE_SECONDS, awake_indices]
	)
