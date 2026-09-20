extends GutTest
## PlayerController.gd: MMB is bound to both rotate_pitch_fwd (a tap) and
## camera_orbit_hold (a hold); CLAUDE.md requires the split to go through the
## Input Map ("All input goes through the Input Map. ... Never check raw
## keycodes in code"), so this exercises it with synthetic
## InputEventMouseButton presses/releases rather than a raw
## MOUSE_BUTTON_MIDDLE check in the source.
##
## Also carries a Bontago-mv0.7 regression pin (Part B, "the host cannot
## place"): the real root cause turned out to be ui/Lobby.gd sending
## hot_seat = true (see tests/unit/test_lobby.gd's
## test_default_lobby_data_is_never_hot_seat), but PlayerController's own
## networked gating -- _acting_slot() reading Net.local_slot() rather than
## waiting on Events.turn_changed -- is the layer that would have hidden a
## reintroduced version of the same class of bug, so it gets its own direct
## pin here too.


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


func _mmb_event(pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event


func test_quick_mmb_tap_rotates_pitch_forward() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	controller._unhandled_input(_mmb_event(true))
	controller._unhandled_input(_mmb_event(false))

	assert_eq(
		controller._ghost.orientation_index,
		BlockOrientations.step_pitch_fwd(start_index),
		"A quick MMB tap should step rotate_pitch_fwd."
	)


func test_long_mmb_hold_does_not_rotate() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	controller._unhandled_input(_mmb_event(true))
	# Simulate a hold longer than camera_tuning.mmb_tap_max_duration by
	# rewinding the recorded press time instead of a real sleep.
	controller._mmb_press_time -= controller.camera_tuning.mmb_tap_max_duration + 1.0
	controller._unhandled_input(_mmb_event(false))

	assert_eq(
		controller._ghost.orientation_index,
		start_index,
		"A long MMB hold (camera orbit) must not also rotate the block."
	)


# --- Bontago-mv0.7 Part B regression pin -------------------------------------

func _fake_match_with_slots() -> FakeMatch:
	var fake: FakeMatch = FakeMatch.new()
	fake.slots_by_id[0] = PlayerSlot.new(0, 0, "P1", Color(0.9, 0.2, 0.2))
	fake.slots_by_id[1] = PlayerSlot.new(1, 1, "P2", Color(0.2, 0.4, 0.9))
	return fake


func _make_networked_controller(session: FakeNet, fake_match: FakeMatch) -> PlayerController:
	var scene: PackedScene = load("res://game/HotSeat.tscn")
	var hot_seat: HotSeat = autofree(scene.instantiate())
	add_child_autofree(hot_seat)
	var controller: PlayerController = hot_seat.controller()
	controller._match = fake_match
	controller.set_session_provider(session)
	return controller


## A host-local slot, hot_seat = false (real-time networked play), must be
## placeable from nothing but the feed-issued shape and Net.local_slot() --
## exactly what a genuine networked match does. Events.turn_changed is never
## emitted here at all (Match's own hot-seat mechanism), so a regression that
## makes the ghost's shape/tint or _acting_slot() depend on it again fails
## this test first, before it ever reaches a windowed repro.
func test_a_networked_hosts_own_slot_places_without_any_turn_changed() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	var controller: PlayerController = _make_networked_controller(FakeNet.host({1: 0}, [0]), fake_match)

	Events.feed_block_issued.emit(0, &"cube", &"")
	controller._place_ghost_block()

	assert_eq(fake_match.request_place_calls.size(), 1, "the ghost must be armed and the click must reach Match")
	assert_eq(
		fake_match.request_place_calls[0]["slot_id"], 0,
		"the host's own instance always acts for its own slot, not whoever Match's hot-seat names"
	)
