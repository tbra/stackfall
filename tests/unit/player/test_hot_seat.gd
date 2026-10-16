extends GutTest
## Hot-seat is strict alternation — only the
## active slot's controls do anything, and the turn passes on
## Events.turn_changed. HotSeat.tscn is a self-contained controller + ghost +
## HUD subtree; this drives it the way Main will once the integrator wires it
## in.


func _make_hot_seat() -> HotSeat:
	var scene: PackedScene = load("res://game/main/HotSeat.tscn")
	var hot_seat: HotSeat = autofree(scene.instantiate())
	add_child_autofree(hot_seat)
	return hot_seat


func test_turn_changed_switches_the_active_slot() -> void:
	var hot_seat: HotSeat = _make_hot_seat()

	Events.turn_changed.emit(1)

	assert_eq(hot_seat.controller()._active_slot, 1)
	assert_eq(hot_seat.hud()._active_slot, 1)


func test_only_the_active_slots_press_reaches_request_place() -> void:
	var hot_seat: HotSeat = _make_hot_seat()
	var fake_match: FakeMatch = FakeMatch.new()
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	fake_match.held_shapes[0] = cube
	fake_match.held_shapes[1] = cube
	hot_seat.controller()._match = fake_match
	hot_seat.ghost().set_shape(cube)

	# Slot 0's turn: a press should reach Match.
	Events.turn_changed.emit(0)
	hot_seat.controller()._place_ghost_block()
	assert_eq(fake_match.request_place_calls.size(), 1)
	assert_eq(fake_match.request_place_calls[0]["slot_id"], 0)

	# Now it's slot 1's turn; the same controller (one mouse) now acts for it.
	Events.turn_changed.emit(1)
	hot_seat.controller()._place_ghost_block()
	assert_eq(fake_match.request_place_calls.size(), 2)
	assert_eq(fake_match.request_place_calls[1]["slot_id"], 1)


func test_eliminated_slot_cannot_place() -> void:
	var hot_seat: HotSeat = _make_hot_seat()
	var fake_match: FakeMatch = FakeMatch.new()
	var eliminated_slot: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	eliminated_slot.home_flag_alive = false
	fake_match.slots_by_id[0] = eliminated_slot
	fake_match.held_shapes[0] = load("res://config/blocks/cube.tres")
	hot_seat.controller()._match = fake_match
	hot_seat.ghost().set_shape(fake_match.held_shapes[0])

	Events.turn_changed.emit(0)
	hot_seat.controller()._place_ghost_block()

	assert_eq(fake_match.request_place_calls.size(), 0, "An eliminated slot must not feed or place (owner decision 3).")


func test_eliminated_slot_does_not_auto_drop() -> void:
	var hot_seat: HotSeat = _make_hot_seat()
	var fake_match: FakeMatch = FakeMatch.new()
	var eliminated_slot: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	eliminated_slot.home_flag_alive = false
	fake_match.slots_by_id[0] = eliminated_slot
	hot_seat.controller()._match = fake_match
	hot_seat.controller()._active_slot = 0

	Events.feed_timer_expired.emit(0)

	assert_eq(fake_match.request_place_calls.size(), 0)
