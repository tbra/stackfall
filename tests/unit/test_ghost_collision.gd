extends GutTest
## Ghost-vs-placed-block collision (Bontago-mv0.23, spec 2.5 "Held-block
## behaviour" [ORIGINAL], owner test 2026-09-22): the held ghost must collide
## with an already placed block -- it cannot pass through a tower -- but must
## never push or knock one. Drives real BlockFactory-built blocks through
## real physics (see tests/unit/test_field_cells.gd's drop-and-settle
## pattern) and drives the ghost through the same entry points real input
## uses (synthetic InputEventMouseMotion/InputEventMouseButton plus
## PlayerController's own per-frame update functions), never by teleporting
## the cursor straight to its final position.

const SETTLE_FRAMES: int = 90


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_ghost_collision"
	map_def.field_radius = 12.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	return map_def


func _make_field() -> Field:
	var field: Field = Field.new()
	field.map_def = _small_map()
	add_child_autofree(field)
	return field


## A real BlockFactory block, dropped from above onto the disk at (x, z) so
## its resting height/collision box match a genuinely placed block exactly
## (not a hand-built stand-in) -- BlockFactory itself is out of this
## package's ownership, so it is used as-is, unmodified.
func _spawn_block(field: Field, tuning: PhysicsTuning, x: float, z: float) -> Block:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres"), tuning)
	field.get_parent().add_child(block)
	autofree(block)
	block.global_position = Vector3(x, 5.0, z)
	return block


func _make_controller(ghost_tuning: GhostTuning) -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.ghost_tuning = ghost_tuning
	return controller


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	return event


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


## One simulated frame: the collision clamp, then the raycast/placement
## update that reads its result -- exactly PlayerController._process()'s own
## order (see its DECISION comment on why the clamp runs between the two).
func _advance(controller: PlayerController) -> void:
	controller._clamp_cursor_collision()
	controller._update_ghost_transform()


func _half_size(tuning: PhysicsTuning) -> float:
	return (tuning.cube_size - tuning.cube_margin) * 0.5


# --- Horizontal: pushing the cursor into a tower stops short of it ---------

func test_moving_horizontally_into_a_placed_block_stops_short_of_it() -> void:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ghost_tuning: GhostTuning = GhostTuning.new()
	var field: Field = _make_field()
	var block: Block = _spawn_block(field, tuning, 4.0, 0.0)
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true

	var controller: PlayerController = _make_controller(ghost_tuning)
	controller._cursor = Vector3(-2.0, 0.0, 0.0)
	_advance(controller)

	for _i: int in range(160):
		controller._unhandled_input(_motion(Vector2(50.0, 0.0)))
		_advance(controller)

	var half_size: float = _half_size(tuning)
	var gap: float = (block.global_position.x - half_size) - (controller._ghost.global_position.x + half_size)
	assert_gt(gap, 0.0, "the ghost must never touch or overlap a placed block.")
	assert_lt(
		gap, ghost_tuning.ghost_collision_skin + tuning.cube_size,
		"the ghost should stop right at the collision skin's gap, not far short of the block."
	)

	# Pressing further for 30 more frames must never move or wake the block.
	var block_transform_before: Transform3D = block.global_transform
	for _i: int in range(30):
		controller._unhandled_input(_motion(Vector2(50.0, 0.0)))
		_advance(controller)

	assert_true(
		block.global_transform.is_equal_approx(block_transform_before),
		"the placed block's transform must be untouched by the ghost pressing into it."
	)
	assert_true(block.sleeping, "the placed block must never wake from the ghost's shape queries.")


func test_moving_parallel_to_a_wall_slides() -> void:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ghost_tuning: GhostTuning = GhostTuning.new()
	var field: Field = _make_field()
	var block: Block = _spawn_block(field, tuning, 4.0, 0.0)
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true

	var controller: PlayerController = _make_controller(ghost_tuning)
	controller._cursor = Vector3(-2.0, 0.0, 0.0)
	_advance(controller)

	# First press straight into the block (+X) until it stops, exactly like
	# the pure-X test above.
	for _i: int in range(160):
		controller._unhandled_input(_motion(Vector2(50.0, 0.0)))
		_advance(controller)

	var half_size: float = _half_size(tuning)
	var gap_while_pressed: float = (
		(block.global_position.x - half_size) - (controller._ghost.global_position.x + half_size)
	)
	assert_gt(gap_while_pressed, 0.0, "fixture: the ghost must be stopped at the block before testing the slide.")

	# Now drag sideways (+Z) while still pressed against the wall -- an
	# unobstructed direction -- and it must keep advancing instead of
	# sticking just because X is blocked.
	for _i: int in range(60):
		controller._unhandled_input(_motion(Vector2(0.0, 50.0)))
		_advance(controller)

	assert_gt(
		controller._ghost.global_position.z, 2.0,
		"sliding along the wall (Z, unobstructed) must keep advancing while X stays blocked."
	)
	var gap_after_slide: float = (
		(block.global_position.x - half_size) - (controller._ghost.global_position.x + half_size)
	)
	assert_lt(
		gap_after_slide, ghost_tuning.ghost_collision_skin + tuning.cube_size,
		"the X component must still stay at the wall while sliding, not drift away or through it."
	)


# --- Vertical: lowering onto a block stops on top of it --------------------

func test_lowering_onto_a_block_stops_on_top_of_it() -> void:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ghost_tuning: GhostTuning = GhostTuning.new()
	var field: Field = _make_field()
	var block: Block = _spawn_block(field, tuning, 0.0, 0.0)
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true

	var controller: PlayerController = _make_controller(ghost_tuning)
	controller._cursor = Vector3.ZERO
	_advance(controller)

	var half_size: float = _half_size(tuning)
	for _i: int in range(30):
		controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
		_advance(controller)
	assert_gt(
		controller._ghost.global_position.y, block.global_position.y + half_size,
		"fixture: the ghost should start well above the block once raised."
	)

	for _i: int in range(80):
		controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
		_advance(controller)

	var gap: float = (controller._ghost.global_position.y - half_size) - (block.global_position.y + half_size)
	assert_gt(gap, 0.0, "the ghost must not sink into the block from above.")
	assert_lt(gap, ghost_tuning.ghost_collision_skin + tuning.cube_size, "the ghost should land right on top, not float far above.")

	var block_transform_before: Transform3D = block.global_transform
	for _i: int in range(30):
		controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
		_advance(controller)

	assert_true(
		block.global_transform.is_equal_approx(block_transform_before),
		"the placed block's transform must be untouched by the ghost pressing down on it."
	)
	assert_true(block.sleeping, "the placed block must never wake from the ghost's shape queries.")


# --- Bontago-mv0.25 (docs/rotation-issue.png): 3-DOF rotate_drag must not
# break the box sweep --------------------------------------------------------

## collision_box_local_centers()/collision_half_size() and the sweep in
## game/PlayerController.gd all read `_ghost.basis` directly, so they were
## already generic to any rotation -- this pins that a non-axis-aligned
## (pitched) held shape still gets swept correctly, not just the 24-entry
## orientation table's axis-aligned poses.
func test_moving_horizontally_into_a_placed_block_stops_short_of_it_at_a_pitched_rotation() -> void:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ghost_tuning: GhostTuning = GhostTuning.new()
	var field: Field = _make_field()
	var block: Block = _spawn_block(field, tuning, 4.0, 0.0)
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true

	var controller: PlayerController = _make_controller(ghost_tuning)
	controller._ghost.set_shape(load("res://config/blocks/bar3.tres"))
	controller._ghost.apply_free_rotation_delta(0.0, deg_to_rad(30.0), Vector3.RIGHT)
	controller._cursor = Vector3(-2.0, 0.0, 0.0)
	_advance(controller)

	for _i: int in range(160):
		controller._unhandled_input(_motion(Vector2(50.0, 0.0)))
		_advance(controller)

	var boxes: Array[Vector3] = controller._ghost.collision_box_local_centers()
	assert_false(boxes.is_empty(), "fixture: bar3 has collision boxes to sweep.")
	var half_size: float = controller._ghost.collision_half_size()
	var min_gap: float = INF
	for local_center: Vector3 in boxes:
		var world_center: Vector3 = controller._ghost.global_position + controller._ghost.basis * local_center
		var gap: float = (block.global_position.x - half_size) - (world_center.x + half_size)
		min_gap = minf(min_gap, gap)

	assert_gt(
		min_gap, 0.0,
		"the pitched ghost's own collision boxes must still stop clear of the placed block."
	)
	assert_lt(
		min_gap, ghost_tuning.ghost_collision_skin + tuning.cube_size * 2.0,
		"the pitched ghost should stop right at the collision skin's gap, not far short of the block."
	)


# --- Master switch (F4 tuning panel) ----------------------------------------

func test_ghost_collision_disabled_passes_through_a_placed_block() -> void:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ghost_tuning: GhostTuning = GhostTuning.new()
	ghost_tuning.ghost_collision_enabled = false
	var field: Field = _make_field()
	var block: Block = _spawn_block(field, tuning, 4.0, 0.0)
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true

	var controller: PlayerController = _make_controller(ghost_tuning)
	controller._cursor = Vector3(-2.0, 0.0, 0.0)
	_advance(controller)

	for _i: int in range(160):
		controller._unhandled_input(_motion(Vector2(50.0, 0.0)))
		_advance(controller)

	assert_gt(
		controller._ghost.global_position.x, block.global_position.x,
		"with ghost_collision_enabled = false the cursor must pass straight through the block."
	)
