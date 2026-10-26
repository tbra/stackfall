extends GutTest
## SpawnClearance (game/player/SpawnClearance.gd): the held ghost's clearance machine, driven only
## through its public verbs. The ghost is a real GhostPreview; the placed-body query is a scripted
## Callable that reports a body for as long as the ghost's hover offset is below `_need`, which is
## how a stack of that height looks to the real overlap query at each trial pose.

const CUBE_PATH: String = "res://config/blocks/cube.tres"
## Slack above the exact need: the margin (0.02) plus the bisection resolution (step / 2^steps).
const MARGIN_SLACK: float = 0.03
const SURFACE_POINT: Vector3 = Vector3(3.0, 2.0, 1.0)

var _ghost: GhostPreview
var _tuning: GhostTuning
var _physics: PhysicsTuning
var _body: RigidBody3D
var _clearance: SpawnClearance
## The hover offset the scripted stack needs before the ghost is clear of it.
var _need: float = 0.0
var _ceiling: float = 100.0


func before_each() -> void:
	_need = 0.0
	_ceiling = 100.0
	_physics = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	_tuning = (load("res://config/blocks/tuning/ghost_tuning.tres") as GhostTuning).duplicate() as GhostTuning
	_tuning.spawn_clearance_enabled = true
	_tuning.spawn_clearance_step = 0.25
	_tuning.spawn_clearance_bisect_steps = 8
	_tuning.spawn_clearance = 0.02
	_tuning.spawn_clearance_max_raise = 4.0
	_tuning.spawn_clearance_decay_speed = 2.0
	_tuning.spawn_clearance_settle_timeout_s = 2.5
	_ghost = autofree(GhostPreview.new())
	add_child_autofree(_ghost)
	_ghost.set_shape(load(CUBE_PATH) as BlockShape)
	_body = autofree(RigidBody3D.new())
	_clearance = _make_clearance(_ghost)
	_clearance.set_surface(Vector3.ZERO, Vector3.UP)
	_ghost.update_placement(Vector3.ZERO, Vector3.UP)


func _make_clearance(ghost: GhostPreview) -> SpawnClearance:
	return SpawnClearance.new(
		ghost, Callable(self, "_overlaps"), null, _tuning, _physics, Callable(self, "_hover_ceiling")
	)


func _overlaps() -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	if _ghost.manual_hover_offset < _need:
		bodies.append(_body)
	return bodies


func _hover_ceiling() -> float:
	return _ceiling


## A spawn that resolves at once (no settle wait).
func _spawn_now(delta: float = 0.0) -> void:
	_clearance.begin_pending()
	_clearance.step(delta, false)


func _assert_offset_clears(need: float, message: String) -> void:
	assert_between(_ghost.manual_hover_offset, need, need + MARGIN_SLACK, message)


# --- post-placement raise ---------------------------------------------------------------------


func test_nothing_pending_never_raises() -> void:
	_need = 3.0
	_clearance.step(0.1, false)
	_clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "a ghost nobody asked to clear stays at the player's hover")


func test_spawn_raises_ghost_just_clear_of_the_stack() -> void:
	_need = 3.0
	_spawn_now()
	_assert_offset_clears(3.0, "raised by the minimal amount that clears, plus the small margin")


func test_spawn_is_a_noop_when_already_clear() -> void:
	_ghost.manual_hover_offset = 0.7
	_need = 0.0
	_spawn_now()
	assert_eq(_ghost.manual_hover_offset, 0.7, "the player's own hover is left exactly alone")


func test_spawn_raise_is_measured_from_the_players_own_hover() -> void:
	_ghost.manual_hover_offset = 0.5
	_need = 3.0
	_spawn_now()
	_assert_offset_clears(3.0, "the ghost ends clear of the stack")


func test_spawn_resolves_once_then_stays_put() -> void:
	_need = 3.0
	_spawn_now()
	var raised: float = _ghost.manual_hover_offset
	_need = 6.0
	_clearance.step(0.0, false)
	assert_eq(_ghost.manual_hover_offset, raised, "the pending spawn already resolved; a taller stack later is not re-raised")


func test_spawn_raise_is_capped_by_max_raise() -> void:
	_need = 10.0
	_spawn_now()
	assert_almost_eq(_ghost.manual_hover_offset, _tuning.spawn_clearance_max_raise, 0.0001)


func test_spawn_raise_is_capped_by_hover_ceiling() -> void:
	_need = 10.0
	_ceiling = 2.0
	_spawn_now()
	assert_almost_eq(_ghost.manual_hover_offset, 2.0, 0.0001, "never above the ceiling the network band allows")


func test_spawn_with_ceiling_below_current_offset_does_not_raise_or_lower() -> void:
	_ghost.manual_hover_offset = 1.0
	_need = 10.0
	_ceiling = 0.5
	_spawn_now()
	assert_eq(_ghost.manual_hover_offset, 1.0)


func test_spawn_disabled_in_tuning_never_raises() -> void:
	_tuning.spawn_clearance_enabled = false
	_need = 3.0
	_spawn_now()
	assert_eq(_ghost.manual_hover_offset, 0.0)


func test_spawn_disabled_still_ends_the_pending_spawn() -> void:
	_tuning.spawn_clearance_enabled = false
	_need = 3.0
	_spawn_now()
	_tuning.spawn_clearance_enabled = true
	_clearance.step(0.0, false)
	assert_eq(_ghost.manual_hover_offset, 0.0, "a skipped spawn does not stay armed")


func test_spawn_without_a_shape_does_not_raise() -> void:
	var bare: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(bare)
	var clearance: SpawnClearance = _make_clearance(bare)
	_need = 3.0
	clearance.begin_pending()
	clearance.step(0.0, false)
	assert_eq(bare.manual_hover_offset, 0.0)


func test_spawn_poses_from_the_surface_it_was_given() -> void:
	_clearance.set_surface(SURFACE_POINT, Vector3.UP)
	_ghost.update_placement(SURFACE_POINT, Vector3.UP)
	var top: float = 2.0
	_need = top - _physics.hover_height
	_spawn_now()
	assert_between(_ghost.height_above_surface(), top, top + MARGIN_SLACK, "lowest point ends at or above the stack top over that surface")
	assert_almost_eq(_ghost.global_position.x, SURFACE_POINT.x, 0.01, "the ghost stays over the surface point")


func test_next_spawn_takes_the_previous_raise_back_first() -> void:
	_need = 3.0
	_spawn_now()
	_need = 0.0
	_spawn_now()
	assert_almost_eq(_ghost.manual_hover_offset, 0.0, 0.0001, "no raise carries over to a spawn that needs none")


func test_raises_never_compound_across_drops() -> void:
	_need = 3.0
	_spawn_now()
	_need = 1.0
	_spawn_now()
	_assert_offset_clears(1.0, "the second spawn starts from the player's hover, not from the first raise")


func test_previous_raise_is_taken_back_while_the_next_spawn_still_waits() -> void:
	_need = 3.0
	_spawn_now()
	_clearance.begin_pending()
	_clearance.step(0.1, true)
	assert_almost_eq(_ghost.manual_hover_offset, 0.0, 0.0001)


func test_cancel_pending_stops_waiting() -> void:
	_need = 3.0
	_clearance.begin_pending()
	_clearance.cancel_pending()
	_clearance.step(0.0, false)
	assert_eq(_ghost.manual_hover_offset, 0.0)


func test_feed_after_cancel_does_not_revive_the_spawn() -> void:
	_need = 3.0
	_clearance.begin_pending()
	_clearance.cancel_pending()
	_clearance.mark_fed()
	_clearance.step(0.0, false)
	assert_eq(_ghost.manual_hover_offset, 0.0)


func test_feed_without_a_pending_spawn_is_ignored() -> void:
	_need = 3.0
	_clearance.mark_fed()
	_clearance.step(0.0, false)
	assert_eq(_ghost.manual_hover_offset, 0.0)


func test_new_begin_pending_restarts_the_settle_wait() -> void:
	_need = 3.0
	_body.sleeping = true
	_clearance.begin_pending()
	_clearance.step(2.0, true)
	_clearance.begin_pending()
	_clearance.step(2.0, true)
	assert_almost_eq(_ghost.manual_hover_offset, 0.0, 0.0001, "2s + 2s across two requests is not one 4s wait")


# --- settle wait ------------------------------------------------------------------------------


func test_waits_for_the_feed_before_resolving() -> void:
	_need = 3.0
	_body.sleeping = true
	_clearance.begin_pending()
	_clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "the next piece has not been issued yet")
	_clearance.mark_fed()
	_clearance.step(0.1, true)
	_assert_offset_clears(3.0, "fed and the overlapped block is asleep: raise now")


func test_waits_while_the_overlapped_block_is_still_moving() -> void:
	_need = 3.0
	_body.sleeping = false
	_clearance.begin_pending()
	_clearance.mark_fed()
	_clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "a falling block is not counted")
	_body.sleeping = true
	_clearance.step(0.1, true)
	_assert_offset_clears(3.0, "raised once the block came to rest inside the ghost")


func test_block_that_falls_clear_never_raises_the_ghost() -> void:
	_need = 3.0
	_body.sleeping = false
	_clearance.begin_pending()
	_clearance.mark_fed()
	_clearance.step(0.1, true)
	_need = 0.0
	_clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0)
	_need = 3.0
	_body.sleeping = true
	_clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "the spawn is over; a later block does not raise it")


func test_settle_wait_gives_up_after_the_timeout() -> void:
	_need = 3.0
	_body.sleeping = false
	_clearance.begin_pending()
	_clearance.mark_fed()
	_clearance.step(_tuning.spawn_clearance_settle_timeout_s - 0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "still inside the timeout")
	_clearance.step(0.2, true)
	_assert_offset_clears(3.0, "after the timeout the block counts even though it never rested")


func test_timeout_elapses_even_if_the_feed_never_arrives() -> void:
	_need = 3.0
	_body.sleeping = true
	_clearance.begin_pending()
	_clearance.step(_tuning.spawn_clearance_settle_timeout_s + 0.1, true)
	_assert_offset_clears(3.0, "a lost feed does not leave the ghost inside the stack forever")


func test_frozen_block_counts_as_settled_once_its_pose_stops_moving() -> void:
	var block: Block = autofree(Block.new())
	block.freeze = true
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	add_child_autofree(block)
	block.global_position = Vector3(0.0, 5.0, 0.0)
	var bodies: Array[RigidBody3D] = [block]
	var clearance: SpawnClearance = SpawnClearance.new(
		_ghost, func() -> Array[RigidBody3D]: return bodies if _ghost.manual_hover_offset < _need else [] as Array[RigidBody3D],
		null, _tuning, _physics, Callable(self, "_hover_ceiling")
	)
	_need = 3.0
	clearance.begin_pending()
	clearance.mark_fed()
	clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "the first sample of a frozen block is not settled")
	block.global_position += Vector3(0.0, 5.0, 0.0)
	await get_tree().process_frame
	clearance.step(0.1, true)
	assert_eq(_ghost.manual_hover_offset, 0.0, "a frozen block that moved 5 m in a step is still travelling")
	await get_tree().process_frame
	clearance.step(0.1, true)
	_assert_offset_clears(3.0, "a frozen block that held its pose is settled")


# --- decay and absorb -------------------------------------------------------------------------


func test_raise_decays_at_the_configured_speed_once_clear() -> void:
	_need = 3.0
	_spawn_now()
	var raised: float = _ghost.manual_hover_offset
	_need = 0.0
	_clearance.step(0.1, false)
	assert_almost_eq(_ghost.manual_hover_offset, raised - 0.2, 0.0001, "speed 2 m/s over 0.1 s")


func test_decay_never_goes_below_the_players_own_hover() -> void:
	_ghost.manual_hover_offset = 0.5
	_need = 3.0
	_spawn_now()
	_need = 0.0
	_clearance.step(1.0, false)
	_clearance.step(1.0, false)
	assert_almost_eq(_ghost.manual_hover_offset, 0.5, 0.0001, "only the clearance share decays")


func test_decay_stops_where_lowering_would_overlap_again() -> void:
	_need = 3.0
	_spawn_now()
	_need = 1.0
	for _i: int in range(20):
		_clearance.step(0.1, false)
	assert_between(_ghost.manual_hover_offset, 1.0, 1.0 + 0.2, "settles just above the remaining stack")
	var held: float = _ghost.manual_hover_offset
	_clearance.step(0.1, false)
	assert_eq(_ghost.manual_hover_offset, held, "and stays there")


func test_no_decay_while_the_stack_still_blocks() -> void:
	_need = 3.0
	_spawn_now()
	var raised: float = _ghost.manual_hover_offset
	for _i: int in range(5):
		_clearance.step(0.1, false)
	assert_eq(_ghost.manual_hover_offset, raised)


func test_zero_delta_does_not_decay() -> void:
	_need = 3.0
	_spawn_now()
	var raised: float = _ghost.manual_hover_offset
	_need = 0.0
	_clearance.step(0.0, false)
	assert_eq(_ghost.manual_hover_offset, raised)


func test_absorb_hands_the_raise_to_the_player() -> void:
	_need = 3.0
	_spawn_now()
	var raised: float = _ghost.manual_hover_offset
	_clearance.absorb()
	_need = 0.0
	_clearance.step(1.0, false)
	assert_eq(_ghost.manual_hover_offset, raised, "an absorbed raise does not decay")


func test_absorbed_raise_survives_the_next_spawn() -> void:
	_need = 3.0
	_spawn_now()
	var raised: float = _ghost.manual_hover_offset
	_clearance.absorb()
	_need = 0.0
	_spawn_now()
	assert_eq(_ghost.manual_hover_offset, raised, "the next spawn does not take the player's hover back")


func test_absorb_with_nothing_raised_is_harmless() -> void:
	_ghost.manual_hover_offset = 0.4
	_clearance.absorb()
	assert_eq(_ghost.manual_hover_offset, 0.4)


# --- release lift and undo --------------------------------------------------------------------


func test_release_lift_clears_the_stack() -> void:
	_need = 3.0
	_clearance.lift_for_release()
	_assert_offset_clears(3.0, "lifted just clear")


func test_release_lift_is_a_noop_when_clear() -> void:
	_ghost.manual_hover_offset = 0.4
	_clearance.lift_for_release()
	assert_eq(_ghost.manual_hover_offset, 0.4)


func test_release_lift_counts_unsettled_blocks() -> void:
	_need = 3.0
	_body.sleeping = false
	_clearance.lift_for_release()
	_assert_offset_clears(3.0, "the lift protects the real spawn, so a moving block counts")


func test_release_lift_is_not_limited_by_max_raise() -> void:
	_need = 10.0
	_clearance.lift_for_release()
	_assert_offset_clears(10.0, "a tower taller than max_raise is still cleared")


func test_release_lift_is_limited_by_the_hover_ceiling() -> void:
	_need = 10.0
	_ceiling = 6.0
	_clearance.lift_for_release()
	assert_almost_eq(_ghost.manual_hover_offset, 6.0, 0.0001)


func test_release_lift_does_not_depend_on_a_pending_spawn() -> void:
	_need = 3.0
	_clearance.begin_pending()
	_clearance.lift_for_release()
	_assert_offset_clears(3.0, "lifts even while the spawn is still waiting")


func test_release_lift_disabled_in_tuning_does_nothing() -> void:
	_tuning.spawn_clearance_enabled = false
	_need = 3.0
	_clearance.lift_for_release()
	assert_eq(_ghost.manual_hover_offset, 0.0)


func test_undo_takes_the_release_lift_back_off() -> void:
	_ghost.manual_hover_offset = 0.5
	_need = 3.0
	_clearance.lift_for_release()
	_clearance.undo_release_lift()
	assert_almost_eq(_ghost.manual_hover_offset, 0.5, 0.0001, "back to the player's own hover")


func test_undo_keeps_the_spawn_raise() -> void:
	_need = 2.0
	_spawn_now()
	var spawn_raise: float = _ghost.manual_hover_offset
	_need = 5.0
	_clearance.lift_for_release()
	_clearance.undo_release_lift()
	assert_almost_eq(_ghost.manual_hover_offset, spawn_raise, 0.0001, "only the release share is removed")


func test_undo_twice_removes_the_lift_once() -> void:
	_need = 2.0
	_spawn_now()
	var spawn_raise: float = _ghost.manual_hover_offset
	_need = 5.0
	_clearance.lift_for_release()
	_clearance.undo_release_lift()
	_clearance.undo_release_lift()
	assert_almost_eq(_ghost.manual_hover_offset, spawn_raise, 0.0001)


func test_undo_without_a_lift_does_nothing() -> void:
	_ghost.manual_hover_offset = 0.6
	_clearance.undo_release_lift()
	assert_eq(_ghost.manual_hover_offset, 0.6)


func test_undo_after_a_noop_lift_does_nothing() -> void:
	_ghost.manual_hover_offset = 0.6
	_need = 0.0
	_clearance.lift_for_release()
	_clearance.undo_release_lift()
	assert_eq(_ghost.manual_hover_offset, 0.6)


# --- home spawn raise -------------------------------------------------------------------------


func test_seed_home_raises_to_the_clear_height() -> void:
	_clearance.seed_home(2.0)
	var expected: float = 2.0 - _physics.hover_height
	assert_almost_eq(_ghost.manual_hover_offset, expected, 0.0001, "hover plus offset lands on the absolute clear height")


func test_seed_home_counts_the_players_existing_offset() -> void:
	_ghost.manual_hover_offset = 0.5
	_clearance.seed_home(2.0)
	assert_almost_eq(_ghost.manual_hover_offset, 2.0 - _physics.hover_height, 0.0001)


func test_seed_home_is_a_noop_when_hover_already_clears() -> void:
	_ghost.manual_hover_offset = 3.0
	_clearance.seed_home(2.0)
	assert_eq(_ghost.manual_hover_offset, 3.0)


func test_seed_home_at_exactly_the_base_hover_is_a_noop() -> void:
	_clearance.seed_home(_physics.hover_height)
	assert_eq(_ghost.manual_hover_offset, 0.0)


func test_seed_home_replaces_the_earlier_home_raise() -> void:
	_clearance.seed_home(2.0)
	_clearance.seed_home(1.0)
	var expected: float = 1.0 - _physics.hover_height
	assert_almost_eq(_ghost.manual_hover_offset, expected, 0.0001, "the second seed is not added to the first")


func test_seed_home_replaced_by_a_lower_clear_height_than_hover_drops_the_raise() -> void:
	_clearance.seed_home(2.0)
	_clearance.seed_home(_physics.hover_height)
	assert_almost_eq(_ghost.manual_hover_offset, 0.0, 0.0001)


func test_home_raise_does_not_decay() -> void:
	_clearance.seed_home(2.0)
	var seeded: float = _ghost.manual_hover_offset
	_clearance.step(1.0, false)
	assert_eq(_ghost.manual_hover_offset, seeded, "it only goes at the next spawn or when the player takes over")


func test_next_spawn_drops_the_home_raise() -> void:
	_clearance.seed_home(2.0)
	_need = 0.0
	_spawn_now()
	assert_almost_eq(_ghost.manual_hover_offset, 0.0, 0.0001, "later pieces hover exactly as before")


func test_absorb_makes_the_home_raise_the_players() -> void:
	_clearance.seed_home(2.0)
	var seeded: float = _ghost.manual_hover_offset
	_clearance.absorb()
	_spawn_now()
	assert_eq(_ghost.manual_hover_offset, seeded, "an absorbed home raise is not taken back at the next spawn")


func test_release_lift_stacks_on_the_home_raise_and_undo_keeps_the_home_raise() -> void:
	_clearance.seed_home(2.0)
	var home: float = _ghost.manual_hover_offset
	_need = home + 1.5
	_clearance.lift_for_release()
	assert_gt(_ghost.manual_hover_offset, home + 1.5 - 0.0001, "the release lift clears the stack above the home raise")
	_clearance.undo_release_lift()
	assert_almost_eq(_ghost.manual_hover_offset, home, 0.0001, "undo removes only the release share, the home raise stays")
