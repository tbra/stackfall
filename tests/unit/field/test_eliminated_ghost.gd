extends GutTest
## Bontago-1pi.198: an eliminated local player's held ghost is hidden at once
## (host and ENet client both read the replicated PlayerSlot.home_flag_alive and
## Events.player_eliminated); other slots are unaffected and a new match
## shows the ghost again.


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	# Leave the Match autoload idle: a match left in COUNTDOWN makes every later
	# PlayerController ignore input (Bontago-fca.101: sharded gate failures in test_playercontroller_gamepad).
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start(player_count: int = 2) -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = player_count
	config.hot_seat = false
	config.rng_seed = 13579
	Match.start_match(config)


func _controller_for(slot_id: int) -> Array:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_acting_slot(slot_id)
	return [controller, ghost]


func test_eliminated_slot_hides_ghost_within_one_frame() -> void:
	_start()
	var pair: Array = _controller_for(0)
	var controller: PlayerController = pair[0]
	var ghost: GhostPreview = pair[1]
	controller._process(0.016)
	assert_true(ghost.visible, "fixture: alive slot shows its ghost.")
	Match.slot(0).home_flag_alive = false
	controller._process(0.016)
	assert_false(ghost.visible)


func test_new_match_shows_ghost_again() -> void:
	_start()
	var pair: Array = _controller_for(0)
	var controller: PlayerController = pair[0]
	var ghost: GhostPreview = pair[1]
	Match.slot(0).home_flag_alive = false
	controller._process(0.016)
	assert_false(ghost.visible)
	Match.abort_match()
	_start()
	controller._process(0.016)
	assert_true(ghost.visible)
