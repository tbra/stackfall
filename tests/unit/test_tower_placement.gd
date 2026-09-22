extends GutTest
## M1 acceptance: "You can build a stable 30-block tower... with mouse and
## keyboard and with a gamepad." This drives the real placement path
## (PlayerController._place_ghost_block) the way ghost_place does, stacks 30
## cubes, lets physics settle for 10 s, and checks the tower is still
## standing and asleep. The gamepad half is covered by
## test_playercontroller_gamepad.gd's synthetic-input test.
##
## Updated for M2 (docs/M2_PLAN.md P4): placement is intent-only now (spec
## 3.4) — PlayerController calls Match.request_place() and never builds a
## Block itself. P2's real Match hasn't landed on this branch yet, so this
## uses FakeMatch (tests/unit/support/FakeMatch.gd) with spawn_on_ok = true,
## which spawns the same way the real Match eventually will, keeping this
## acceptance test's physics half (a stable, sleeping tower) exercised
## end-to-end.

const TOWER_HEIGHT: int = 30
const SETTLE_SECONDS: float = 10.0
const MAX_TOP_DRIFT: float = 2.0
## Real settle time between placements rather than all 30 at once or a couple
## of ticks apart — spec 2.8's block timer is 3-12 s, never sub-frame, and a
## freshly dropped cube needs a moment to genuinely come to rest before the
## next one lands on it.
const TICKS_BETWEEN_PLACEMENTS: int = 30

## DECISION (Bontago-mv0.3): this test genuinely needs ~1500 real physics
## ticks (900 while placing, 600 to settle) -- it is exactly the "inherently
## slow, keep it" case CLAUDE.md's own workflow calls out, since a 30-cube
## tower's stability is the thing under test. Tried Engine.time_scale = 8 to
## pack more physics ticks into less real time: it broke the test outright
## (an out-of-bounds child index reading blocks_root mid-placement, and
## FakeMatch/PlayerController's own add_child() landing later than the test's
## next physics_frame await expected) rather than just changing timing, so it
## is not used here. The map-size fix below is the safe win for this file.

func test_thirty_cube_tower_stands_and_sleeps() -> void:
	var field: Field = autofree(Field.new())
	# DECISION (Bontago-mv0.3): Field.new()'s default map_def is
	# round_medium.tres (45 m, ~6300 in-disk 1 m cells); building that
	# collision once cost ~11 s by itself here (measured), on top of this
	# test's genuinely-real ~1500 physics_frame settle waits it otherwise
	# does not need -- a 30-cube tower at the origin never comes near a 45 m
	# edge. 6 m (test_field_cells.gd's own tiny-map convention) still leaves
	# a wide margin around the tower's footprint (cube_size-scale, well under
	# 1 m per block).
	field.map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	field.map_def.field_radius = 6.0
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
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.spawn_parent = blocks_root
	fake_match.spawn_on_ok = true
	fake_match.held_shapes[0] = cube_shape
	controller._match = fake_match

	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var edge: float = tuning.cube_size - tuning.cube_margin

	# Each new cube targets the PREVIOUS cube's actual settled position (not
	# a precomputed ideal grid coordinate), matching a real ghost raycasting
	# onto wherever the stack currently is. Unlike M1, the ghost's shape
	# never changes on its own now (Match owns the feed via
	# Events.feed_block_issued/turn_changed), so every block in this tower
	# stays a cube without needing to reset it after each placement.
	var next_position: Vector3 = Vector3(0.0, edge * 0.5, 0.0)
	for i: int in range(TOWER_HEIGHT):
		ghost.reset_rotation()
		ghost.global_position = next_position
		controller._place_ghost_block()

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
