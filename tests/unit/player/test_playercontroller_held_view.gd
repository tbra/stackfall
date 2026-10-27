extends GutTest
## PlayerController publishes the local held pose into MatchContext.local_held() every processed
## frame (after every early return), and clears it when it leaves the tree.

const CUBE_PATH: String = "res://config/blocks/cube.tres"
const BAR_PATH: String = "res://config/blocks/bar3.tres"
const FRAME: float = 1.0 / 60.0

var _saved: MatchContext = null
var _fake: FakeMatchContext = null
var _field: Field = null
var _blocks_root: Node3D = null
var _registry: BlockRegistry = null


func before_each() -> void:
	_saved = MatchContext.installed()
	_fake = FakeMatchContext.new()
	_fake.set_local_held(LocalHeldView.new())
	MatchContext.install(_fake)
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	MatchContext.install(_saved)
	Input.action_release(&"camera_snap_home")
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_match() -> void:
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = 2
	config.rng_seed = 24680
	Match.start_match(config)


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(FRAME)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the countdown ended")


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load(CUBE_PATH))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_acting_slot(0)
	return controller


func _view() -> LocalHeldView:
	return MatchContext.current().local_held()


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func test_a_normal_frame_publishes_the_held_pose() -> void:
	_start_match()
	_run_countdown()
	var controller: PlayerController = _make_controller()
	controller._process(FRAME)
	var view: LocalHeldView = _view()
	assert_eq(view.slot_id, 0)
	assert_not_null(view.shape, "the held shape is published")
	assert_eq(view.origin, controller._ghost.global_position, "the ghost position, not the cursor")
	assert_eq(view.orientation_index, controller._ghost.orientation_index)
	assert_true(view.visible)
	assert_gt(view.updated_msec, 0, "stamped with the publish time")


func test_publishing_works_offline() -> void:
	_start_match()
	_run_countdown()
	assert_true(Net.is_offline(), "fixture: no peer")
	_make_controller()._process(FRAME)
	assert_eq(_view().slot_id, 0)


func test_input_disabled_still_publishes() -> void:
	_start_match()
	_run_countdown()
	var controller: PlayerController = _make_controller()
	controller.input_gate.set_blocker(InputGate.Blocker.PANEL, true)
	controller._process(FRAME)
	assert_eq(_view().slot_id, 0, "an input gate does not hide the held piece from readers")
	assert_not_null(_view().shape)


func test_countdown_still_publishes() -> void:
	_start_match()
	assert_eq(Match.state(), Match.State.COUNTDOWN, "fixture: in the countdown")
	_make_controller()._process(FRAME)
	assert_eq(_view().slot_id, 0)
	assert_not_null(_view().shape)


func test_peek_still_publishes() -> void:
	_start_match()
	_run_countdown()
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/player/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.tuning.snap_enabled = true
	rig.tuning.focus_hold_threshold_s = 0.05
	rig.tuning.focus_peek_transition_s = 0.05
	controller.set_camera_rig(rig)
	rig.set_local_slot(0)
	Input.action_press(&"camera_snap_home")
	rig._unhandled_input(_action_event(&"camera_snap_home", true))
	for _i: int in range(30):
		rig._process(FRAME)
	assert_true(rig.is_peeking(), "fixture: PEEK is engaged")
	controller._process(FRAME)
	assert_eq(_view().slot_id, 0)
	assert_not_null(_view().shape)


func test_a_shape_change_shows_on_the_next_frame() -> void:
	_start_match()
	_run_countdown()
	var controller: PlayerController = _make_controller()
	controller._process(FRAME)
	var first: BlockShape = _view().shape
	var next: BlockShape = load(BAR_PATH)
	if first != null and first.id == next.id:
		next = load(CUBE_PATH)
	Events.feed_block_issued.emit(0, next.id, &"")
	controller._process(FRAME)
	var shown: BlockShape = _view().shape
	assert_not_null(shown)
	assert_eq(shown.id if shown != null else &"", next.id)


func test_an_eliminated_slot_publishes_not_visible() -> void:
	_start_match()
	_run_countdown()
	var controller: PlayerController = _make_controller()
	controller._process(FRAME)
	assert_true(_view().visible, "fixture: an alive slot is visible")
	_fake.slot_by_id[0] = Match.slot(0)
	Match.slot(0).home_flag_alive = false
	controller._process(FRAME)
	assert_eq(_view().slot_id, 0, "still published")
	assert_false(_view().visible)


func test_leaving_the_tree_clears_the_view() -> void:
	_start_match()
	_run_countdown()
	var controller: PlayerController = _make_controller()
	controller._process(FRAME)
	assert_eq(_view().slot_id, 0, "fixture: published")
	controller.get_parent().remove_child(controller)
	assert_null(_view().shape)
	assert_eq(_view().slot_id, -1)
	assert_false(_view().visible)
	controller.free()
