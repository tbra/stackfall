extends GutTest
## LocalPlayer.tscn is the self-contained controller + ghost + HUD subtree for
## the one slot this machine drives. Every placement still goes through the match's
## submit_place intent (the installed MatchContext), never a Block built here.

const CUBE: BlockShape = preload("res://config/blocks/cube.tres")

var _context: FakeMatchContext = null
var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()
	_context = FakeMatchContext.new()
	MatchContext.install(_context)


func after_each() -> void:
	MatchContext.install(_previous_context)


func _make_local_player() -> LocalPlayer:
	var scene: PackedScene = load("res://game/main/LocalPlayer.tscn")
	var local_player: LocalPlayer = autofree(scene.instantiate())
	add_child_autofree(local_player)
	return local_player


func _press_place(local_player: LocalPlayer) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ghost_place"
	press.pressed = true
	local_player.controller()._unhandled_input(press)


func test_bind_local_slot_sets_the_acting_slot_and_hud_slot() -> void:
	var local_player: LocalPlayer = _make_local_player()
	local_player.ghost().set_shape(CUBE)

	local_player.bind_local_slot(3)
	_press_place(local_player)

	assert_eq(_context.submit_place_calls.size(), 1)
	assert_eq(_context.submit_place_calls[0]["slot_id"], 3, "the controller acts for the bound slot")
	assert_eq((local_player.get_node("HUDLayer") as HUD)._active_slot, 3)


func test_bind_local_slot_seeds_the_home_position() -> void:
	var home: Vector3 = Vector3(6.0, 0.0, -5.0)
	_context.default_ghost_origin_by_slot[2] = home
	var local_player: LocalPlayer = _make_local_player()
	local_player.ghost().set_shape(CUBE)

	local_player.bind_local_slot(2)
	local_player.controller().spawn_camera_anchor()  # places the ghost at the seeded cursor

	var at: Vector3 = local_player.ghost().global_position
	assert_almost_eq(at.x, home.x, 0.01, "the first ghost sits at this slot's home flag")
	assert_almost_eq(at.z, home.z, 0.01)


func test_accessors_expose_the_subtree_nodes() -> void:
	var local_player: LocalPlayer = _make_local_player()

	assert_eq(local_player.controller(), local_player.get_node("PlayerController"))
	assert_eq(local_player.ghost(), local_player.get_node("GhostPreview"))
	assert_eq(local_player.hud(), local_player.get_node("HUDLayer"))


func test_placement_goes_through_submit_place_for_the_bound_slot() -> void:
	var local_player: LocalPlayer = _make_local_player()
	_context.held_shape_by_slot[1] = CUBE
	local_player.ghost().set_shape(CUBE)
	local_player.controller().set_acting_slot(1)

	_press_place(local_player)

	assert_eq(_context.submit_place_calls.size(), 1)
	assert_eq(_context.submit_place_calls[0]["slot_id"], 1)


func _bind_with_slot(home_flag_alive: bool) -> LocalPlayer:
	var local_player: LocalPlayer = _make_local_player()
	var bound: PlayerSlot = PlayerSlot.new(0, 0, "P1", Color.RED)
	bound.home_flag_alive = home_flag_alive
	_context.slot_by_id[0] = bound
	_context.held_shape_by_slot[0] = CUBE
	local_player.ghost().set_shape(CUBE)
	local_player.bind_local_slot(0)
	return local_player


func test_living_bound_slot_press_sends_submit_place() -> void:
	_press_place(_bind_with_slot(true))

	assert_eq(_context.submit_place_calls.size(), 1)


func test_eliminated_bound_slot_press_sends_no_submit_place() -> void:
	_press_place(_bind_with_slot(false))

	assert_eq(_context.submit_place_calls.size(), 0, "An eliminated slot must not place.")


func test_living_bound_slot_feed_timer_expiry_auto_drops() -> void:
	_bind_with_slot(true)

	Events.feed_timer_expired.emit(0)

	assert_eq(_context.submit_place_calls.size(), 1)
	assert_true(_context.submit_place_calls[0]["auto_drop"])


func test_eliminated_bound_slot_feed_timer_expiry_sends_no_submit_place() -> void:
	_bind_with_slot(false)

	Events.feed_timer_expired.emit(0)

	assert_eq(_context.submit_place_calls.size(), 0, "An eliminated slot must not auto-drop.")
