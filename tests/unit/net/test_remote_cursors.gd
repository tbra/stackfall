extends GutTest
## game/player/RemoteCursors.gd (spec 2.6): other players' ghosts. It reads the real
## Net session and the Events bus only, so these run against a real listen server
## (this instance holds slot 0) and the real Events signals.

const RemoteCursorsScene := preload("res://game/player/RemoteCursors.tscn")
const LOCAL_SLOT: int = 0
const REMOTE_SLOT: int = 1

var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()
	assert_true(Net.is_offline(), "fixture: the real Net starts offline")


func after_each() -> void:
	Net.leave()
	MatchContext.install(_previous_context)


func _host_and_make_cursors() -> RemoteCursors:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	assert_eq(Net.mode(), Net.Mode.HOST, "fixture: Net must really be the host")
	assert_true(Net.is_local_slot(LOCAL_SLOT), "fixture: the host drives slot 0")
	assert_false(Net.is_local_slot(REMOTE_SLOT), "fixture: slot 1 is another player's")
	var node: RemoteCursors = RemoteCursorsScene.instantiate()
	add_child_autofree(node)
	return node


# --- Remote ghosts ----------------------------------------------------------


func test_a_remote_cursor_creates_one_ghost_for_that_slot() -> void:
	var cursors: RemoteCursors = _host_and_make_cursors()

	Events.remote_cursor_updated.emit(REMOTE_SLOT, Vector3(4.0, 2.0, -1.0), 3, Quaternion.IDENTITY)

	var ghost: GhostPreview = cursors.ghost_for_slot(REMOTE_SLOT)
	assert_not_null(ghost, "A non-local slot's cursor should draw a ghost.")
	assert_eq(ghost.orientation_index, 3)
	assert_almost_eq(ghost.global_position.x, 4.0, 0.001)
	assert_almost_eq(ghost.global_position.y, 2.0, 0.001)
	assert_eq(cursors.get_child_count(), 1, "one ghost node for the one slot that moved")


func test_a_second_cursor_update_moves_the_same_ghost() -> void:
	var cursors: RemoteCursors = _host_and_make_cursors()
	Events.remote_cursor_updated.emit(REMOTE_SLOT, Vector3.ZERO, 0, Quaternion.IDENTITY)
	var first: GhostPreview = cursors.ghost_for_slot(REMOTE_SLOT)

	Events.remote_cursor_updated.emit(REMOTE_SLOT, Vector3(1.0, 5.0, 2.0), 2, Quaternion.IDENTITY)

	assert_eq(cursors.ghost_for_slot(REMOTE_SLOT), first, "the slot keeps its one ghost")
	assert_eq(cursors.get_child_count(), 1)
	assert_almost_eq(first.global_position.y, 5.0, 0.001)
	assert_eq(first.orientation_index, 2)


func test_the_local_slot_never_gets_a_remote_ghost() -> void:
	var cursors: RemoteCursors = _host_and_make_cursors()

	Events.remote_cursor_updated.emit(LOCAL_SLOT, Vector3.ZERO, 0, Quaternion.IDENTITY)

	assert_null(cursors.ghost_for_slot(LOCAL_SLOT), "The local player already has their own ghost.")
	assert_eq(cursors.get_child_count(), 0)


func test_offline_every_slot_is_local_so_no_remote_ghost_is_drawn() -> void:
	var cursors: RemoteCursors = RemoteCursorsScene.instantiate()
	add_child_autofree(cursors)

	Events.remote_cursor_updated.emit(REMOTE_SLOT, Vector3.ZERO, 0, Quaternion.IDENTITY)

	assert_null(cursors.ghost_for_slot(REMOTE_SLOT), "Offline, this instance drives every slot.")
	assert_eq(cursors.get_child_count(), 0)


func test_an_eliminated_player_stops_being_drawn() -> void:
	var cursors: RemoteCursors = _host_and_make_cursors()
	Events.remote_cursor_updated.emit(REMOTE_SLOT, Vector3.ZERO, 0, Quaternion.IDENTITY)

	Events.player_eliminated.emit(REMOTE_SLOT, 1)

	assert_null(cursors.ghost_for_slot(REMOTE_SLOT))


func test_the_end_of_a_match_clears_every_remote_ghost() -> void:
	var cursors: RemoteCursors = _host_and_make_cursors()
	Events.remote_cursor_updated.emit(REMOTE_SLOT, Vector3.ZERO, 0, Quaternion.IDENTITY)

	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.END)

	assert_null(cursors.ghost_for_slot(REMOTE_SLOT))


# --- PlayerController, networked ---------------------------------------------
# These five bind a FakeSessionPort into the controller (bind_session) and install a
# FakeMatchContext, which the controller picks up from MatchContext.current().

func _make_controller(session: FakeNet, context: FakeMatchContext) -> PlayerController:
	MatchContext.install(context)
	var scene: PackedScene = load("res://game/main/LocalPlayer.tscn")
	var local_player: LocalPlayer = autofree(scene.instantiate())
	add_child_autofree(local_player)
	var controller: PlayerController = local_player.controller()
	controller.bind_session(FakeSessionPort.new(session))
	local_player.ghost().set_shape(load("res://config/blocks/cube.tres"))
	return controller


func _context_with_slots() -> FakeMatchContext:
	var context: FakeMatchContext = FakeMatchContext.new()
	context.slot_by_id[0] = PlayerSlot.new(0, 0, "P1", Color(0.9, 0.2, 0.2))
	context.slot_by_id[1] = PlayerSlot.new(1, 1, "P2", Color(0.2, 0.4, 0.9))
	return context


func _press_place(controller: PlayerController) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ghost_place"
	press.pressed = true
	controller._unhandled_input(press)


func test_online_the_controller_acts_for_its_own_slot_not_the_turn() -> void:
	var context: FakeMatchContext = _context_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), context)

	# Events.turn_changed (the turn-based hand-off) must not move a
	# networked controller off its own slot.
	Events.turn_changed.emit(0)
	_press_place(controller)

	assert_eq(context.submit_place_calls.size(), 1)
	assert_eq(context.submit_place_calls[0]["slot_id"], 1, "One instance drives one player.")


func test_a_client_does_not_auto_drop_itself() -> void:
	var context: FakeMatchContext = _context_with_slots()
	_make_controller(FakeNet.client(1), context)

	Events.feed_timer_expired.emit(1)

	assert_eq(
		context.submit_place_calls.size(),
		0,
		"Spec 1.4's auto-drop happens on the host, from the last cursor it received."
	)


func test_a_locked_ghost_sends_no_second_intent() -> void:
	var context: FakeMatchContext = _context_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), context)

	_press_place(controller)
	_press_place(controller)

	assert_eq(
		context.submit_place_calls.size(),
		1,
		"A second click inside one round trip must not spend a second block."
	)


func test_the_hosts_answer_unlocks_the_ghost() -> void:
	var context: FakeMatchContext = _context_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), context)
	_press_place(controller)
	_press_place(controller)
	assert_eq(context.submit_place_calls.size(), 1, "fixture: the ghost is locked")

	Events.feed_block_issued.emit(1, &"cube", &"")

	_press_place(controller)
	assert_eq(context.submit_place_calls.size(), 2, "and the next click goes through")


func test_a_rejection_unlocks_the_ghost() -> void:
	var context: FakeMatchContext = _context_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), context)
	_press_place(controller)

	Events.placement_rejected.emit(1, PlacementRules.REASON_OUTSIDE_TERRITORY)

	_press_place(controller)
	assert_eq(context.submit_place_calls.size(), 2, "a refused intent frees the next click")


func test_the_lock_expires_on_its_own_after_intent_ack_timeout() -> void:
	var context: FakeMatchContext = _context_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), context)
	var timeout: float = load("res://config/net/net_config.tres").intent_ack_timeout
	_press_place(controller)
	assert_eq(context.submit_place_calls.size(), 1)

	# A host that never answers must not lock a player out for good.
	controller._process(timeout + 0.1)

	_press_place(controller)
	assert_eq(context.submit_place_calls.size(), 2)
