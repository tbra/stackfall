extends GutTest
## game/player/RemoteCursors.gd and PlayerController's networked half (spec 2.6):
## other players' ghosts, which slot a controller acts
## for once a session is running, and the ghost lock that stops a double click
## inside one round trip from spending two blocks.

const RemoteCursorsScene := preload("res://game/player/RemoteCursors.tscn")


func _make_cursors(session: FakeNet, fake_match: FakeMatch) -> RemoteCursors:
	var node: RemoteCursors = RemoteCursorsScene.instantiate()
	add_child_autofree(node)
	node.set_providers(session, fake_match)
	return node


func _fake_match_with_slots() -> FakeMatch:
	var fake: FakeMatch = FakeMatch.new()
	fake.slots_by_id[0] = PlayerSlot.new(0, 0, "P1", Color(0.9, 0.2, 0.2))
	fake.slots_by_id[1] = PlayerSlot.new(1, 1, "P2", Color(0.2, 0.4, 0.9))
	return fake


# --- Remote ghosts ----------------------------------------------------------


func test_a_remote_cursor_creates_one_ghost_for_that_slot() -> void:
	var cursors: RemoteCursors = _make_cursors(FakeNet.client(0), _fake_match_with_slots())

	Events.remote_cursor_updated.emit(1, Vector3(4.0, 2.0, -1.0), 3, Quaternion.IDENTITY)

	var ghost: GhostPreview = cursors.ghost_for_slot(1)
	assert_not_null(ghost, "A non-local slot's cursor should draw a ghost.")
	assert_eq(ghost.orientation_index, 3)
	assert_almost_eq(ghost.global_position.x, 4.0, 0.001)
	assert_almost_eq(ghost.global_position.y, 2.0, 0.001)
	assert_eq(cursors.get_child_count(), 1, "one ghost node for the one slot that moved")


func test_the_local_slot_never_gets_a_remote_ghost() -> void:
	var cursors: RemoteCursors = _make_cursors(FakeNet.client(0), _fake_match_with_slots())

	Events.remote_cursor_updated.emit(0, Vector3.ZERO, 0, Quaternion.IDENTITY)

	assert_null(cursors.ghost_for_slot(0), "The local player already has their own ghost.")
	assert_eq(cursors.get_child_count(), 0)


func test_an_eliminated_player_stops_being_drawn() -> void:
	var cursors: RemoteCursors = _make_cursors(FakeNet.client(0), _fake_match_with_slots())
	Events.remote_cursor_updated.emit(1, Vector3.ZERO, 0, Quaternion.IDENTITY)

	Events.player_eliminated.emit(1, 1)

	assert_null(cursors.ghost_for_slot(1))


func test_the_end_of_a_match_clears_every_remote_ghost() -> void:
	var cursors: RemoteCursors = _make_cursors(FakeNet.client(0), _fake_match_with_slots())
	Events.remote_cursor_updated.emit(1, Vector3.ZERO, 0, Quaternion.IDENTITY)

	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.END)

	assert_null(cursors.ghost_for_slot(1))


# --- PlayerController, networked ---------------------------------------------


func _make_controller(session: FakeNet, fake_match: FakeMatch) -> PlayerController:
	var scene: PackedScene = load("res://game/main/HotSeat.tscn")
	var hot_seat: HotSeat = autofree(scene.instantiate())
	add_child_autofree(hot_seat)
	var controller: PlayerController = hot_seat.controller()
	controller._match = fake_match
	controller.set_session_provider(session)
	(hot_seat.get_node("GhostPreview") as GhostPreview).set_shape(load("res://config/blocks/cube.tres"))
	return controller


func test_online_the_controller_acts_for_its_own_slot_not_the_turn() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	fake_match.held_shapes[1] = load("res://config/blocks/cube.tres")
	var controller: PlayerController = _make_controller(FakeNet.client(1), fake_match)

	# Events.turn_changed is hot-seat's mechanism and must not move a
	# networked controller off its own slot.
	Events.turn_changed.emit(0)
	controller._place_ghost_block()

	assert_eq(fake_match.request_place_calls.size(), 1)
	assert_eq(fake_match.request_place_calls[0]["slot_id"], 1, "One instance drives one player.")


func test_a_client_does_not_auto_drop_itself() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), fake_match)

	Events.feed_timer_expired.emit(1)

	assert_eq(
		fake_match.request_place_calls.size(),
		0,
		"Spec 1.4's auto-drop happens on the host, from the last cursor it received."
	)


func test_a_locked_ghost_sends_no_second_intent() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), fake_match)
	controller._intent_lock_left = load("res://config/net/net_config.tres").intent_ack_timeout

	controller._place_ghost_block()

	assert_eq(
		fake_match.request_place_calls.size(),
		0,
		"A second click inside one round trip must not spend a second block."
	)


func test_the_hosts_answer_unlocks_the_ghost() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), fake_match)
	controller._intent_lock_left = 1.0

	Events.feed_block_issued.emit(1, &"cube", &"")

	assert_eq(controller._intent_lock_left, 0.0)
	controller._place_ghost_block()
	assert_eq(fake_match.request_place_calls.size(), 1, "and the next click goes through")


func test_the_lock_expires_on_its_own_after_intent_ack_timeout() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	var controller: PlayerController = _make_controller(FakeNet.client(1), fake_match)
	var timeout: float = load("res://config/net/net_config.tres").intent_ack_timeout
	controller._intent_lock_left = timeout

	# A host that never answers must not lock a player out for good.
	controller._process(timeout + 0.1)

	assert_eq(controller._intent_lock_left, 0.0)


# --- Glue presentation ---------------------------------------

