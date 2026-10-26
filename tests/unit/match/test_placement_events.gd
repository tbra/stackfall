extends GutTest
## PlayerController sends exactly one placement intent through its MatchContext and reacts to the host's reply on
## the Events bus (spec 2.6). The host's answer (the spawn, the rejection) is the host's: this
## controller never builds a block itself.

## How long the rejection kick is let run before the ghost is read (the kick lasts
## GhostTuning.reject_arc_duration; half of it is the rise).
const KICK_WAIT_S: float = 0.1
## The ghost has to have lifted by at least this much of its reject arc by then.
const MIN_KICK_RISE_M: float = 0.05

var _cube_shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape


## A controller acting for slot 0 on a ghost holding a cube, talking to `context`.
func _make_controller(context: FakeMatchContext, ghost: GhostPreview) -> PlayerController:
	ghost.set_shape(_cube_shape)
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = ghost.get_path()
	controller.match_context = context
	add_child_autofree(controller)
	controller.set_acting_slot(0)
	return controller


## The ghost_place press the Input Map delivers.
func _click_place(controller: PlayerController) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ghost_place"
	press.pressed = true
	controller._unhandled_input(press)


func test_place_sends_one_intent_with_the_ghost_transform_and_spawns_nothing_locally() -> void:
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(_cube_shape)
	ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(0))
	ghost.global_position = Vector3(3.0, 7.0, -2.0)
	var context: FakeMatchContext = FakeMatchContext.new()
	context.held_shape_by_slot[0] = _cube_shape
	var controller: PlayerController = _make_controller(context, ghost)

	watch_signals(Events)

	_click_place(controller)

	assert_eq(context.submit_place_calls.size(), 1, "ghost_place should send exactly one placement intent.")
	var call: Dictionary = context.submit_place_calls[0]
	assert_eq(call["slot_id"], 0)
	assert_true((call["origin"] as Vector3).is_equal_approx(Vector3(3.0, 7.0, -2.0)), "the intent carries the ghost's position")
	assert_eq(call["orientation_index"], BlockOrientations.step_yaw_ccw(0), "and the ghost's exact orientation")
	assert_eq(call["auto_drop"], false, "a click is not an auto-drop")
	assert_eq(blocks_root.get_child_count(), 0, "Only the host spawns the block.")
	assert_signal_not_emitted(Events, "block_placed")


func test_a_rejected_placement_flashes_the_ghost_and_spawns_nothing_locally() -> void:
	# Every invalid release burns the block
	# - decided by the host, which the controller never second-guesses. From the
	# controller's side a rejection only means Events.placement_rejected arrives and the ghost plays
	# its reject arc (game/player/GhostPreview.gd); it never spawns anything itself either way.
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var context: FakeMatchContext = FakeMatchContext.new()
	context.held_shape_by_slot[0] = _cube_shape
	context.submit_place_result = PlacementRules.REASON_CONTESTED
	var controller: PlayerController = _make_controller(context, ghost)
	await wait_process_frames(2)
	var rest_y: float = ghost.global_position.y

	watch_signals(Events)
	_click_place(controller)
	assert_eq(context.submit_place_calls.size(), 1, "the intent went to the host")
	Events.placement_rejected.emit(0, PlacementRules.REASON_CONTESTED)
	await get_tree().create_timer(KICK_WAIT_S).timeout

	assert_gt(
		ghost.global_position.y, rest_y + MIN_KICK_RISE_M,
		"A rejected placement should play the ghost's reject arc (spec 1.5's reject animation)."
	)
	assert_signal_not_emitted(Events, "block_placed")
