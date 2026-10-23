extends GutTest
## LocalPlayer.tscn is the self-contained controller + ghost + HUD subtree for
## the one slot this machine drives. Every placement still goes through
## Match.request_place().


func _make_local_player() -> LocalPlayer:
	var scene: PackedScene = load("res://game/main/LocalPlayer.tscn")
	var local_player: LocalPlayer = autofree(scene.instantiate())
	add_child_autofree(local_player)
	return local_player


func test_bind_local_slot_sets_the_acting_slot_and_hud_slot() -> void:
	var local_player: LocalPlayer = _make_local_player()

	local_player.bind_local_slot(3)

	assert_eq(local_player.controller()._active_slot, 3)
	assert_eq((local_player.get_node("HUDLayer") as HUD)._active_slot, 3)


func test_bind_local_slot_seeds_the_home_position() -> void:
	var local_player: LocalPlayer = _make_local_player()

	local_player.bind_local_slot(2)

	assert_eq(local_player.controller()._cursor, Match.default_ghost_origin(2))


func test_accessors_expose_the_subtree_nodes() -> void:
	var local_player: LocalPlayer = _make_local_player()

	assert_eq(local_player.controller(), local_player.get_node("PlayerController"))
	assert_eq(local_player.ghost(), local_player.get_node("GhostPreview"))
	assert_eq(local_player.hud(), local_player.get_node("HUDLayer"))


func test_placement_goes_through_request_place_for_the_bound_slot() -> void:
	var local_player: LocalPlayer = _make_local_player()
	var fake_match: FakeMatch = FakeMatch.new()
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	fake_match.held_shapes[1] = cube
	local_player.controller()._match = fake_match
	local_player.ghost().set_shape(cube)
	local_player.controller().set_acting_slot(1)

	local_player.controller()._place_ghost_block()

	assert_eq(fake_match.request_place_calls.size(), 1)
	assert_eq(fake_match.request_place_calls[0]["slot_id"], 1)


func _bind_with_slot(home_flag_alive: bool) -> Array:
	var local_player: LocalPlayer = _make_local_player()
	var fake_match: FakeMatch = FakeMatch.new()
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	var bound: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	bound.home_flag_alive = home_flag_alive
	fake_match.slots_by_id[0] = bound
	fake_match.held_shapes[0] = cube
	local_player.controller()._match = fake_match
	local_player.ghost().set_shape(cube)
	local_player.bind_local_slot(0)
	return [local_player, fake_match]


func _press_place(local_player: LocalPlayer) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ghost_place"
	press.pressed = true
	local_player.controller()._unhandled_input(press)


func test_living_bound_slot_press_sends_request_place() -> void:
	var parts: Array = _bind_with_slot(true)

	_press_place(parts[0] as LocalPlayer)

	assert_eq((parts[1] as FakeMatch).request_place_calls.size(), 1)


func test_eliminated_bound_slot_press_sends_no_request_place() -> void:
	var parts: Array = _bind_with_slot(false)

	_press_place(parts[0] as LocalPlayer)

	assert_eq((parts[1] as FakeMatch).request_place_calls.size(), 0, "An eliminated slot must not place.")


func test_living_bound_slot_feed_timer_expiry_auto_drops() -> void:
	var parts: Array = _bind_with_slot(true)

	Events.feed_timer_expired.emit(0)

	assert_eq((parts[1] as FakeMatch).request_place_calls.size(), 1)


func test_eliminated_bound_slot_feed_timer_expiry_sends_no_request_place() -> void:
	var parts: Array = _bind_with_slot(false)

	Events.feed_timer_expired.emit(0)

	assert_eq((parts[1] as FakeMatch).request_place_calls.size(), 0, "An eliminated slot must not auto-drop.")
