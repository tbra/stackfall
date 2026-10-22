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
