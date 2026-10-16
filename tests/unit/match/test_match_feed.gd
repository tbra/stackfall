extends "res://tests/unit/match/match_world_test.gd"
## a voluntary placement after an unanswered feed-timer expiry must clear the
## expired latch (spec 1.4), and an early release must not be force-released at the boundary.

func _free_for_all_config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = block_timer
	config.rng_seed = 98765
	return config


func _advance_one_interval(block_timer: float) -> void:
	for _i: int in range(int(ceil(block_timer * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func test_a_voluntary_placement_after_unanswered_expiry_unlatches_the_slot() -> void:
	var block_timer: float = MatchConfig.BLOCK_TIMER_MIN
	# 's own precedent (test_match_flow.gd's
	# test_an_untouched_piece_auto_drops_at_the_interval_boundary): a manual
	# collect array, not assert_signal_emitted_with_parameters, because two
	# slots run concurrently outside hot-seat and both may expire at the same
	# boundary -- assert_signal_emitted_with_parameters only ever checks the
	# LAST emission (and GUT 9.6.1's signal_watcher chokes rebuilding a diff
	# across more than one differently-shaped emission of the same signal).
	var expired: Array[int] = []
	var collect: Callable = func(slot_id: int) -> void: expired.append(slot_id)
	Events.feed_timer_expired.connect(collect)
	Match.start_match(_free_for_all_config(2, block_timer))
	_run_countdown()

	# Nothing answers this: no PlayerController/MatchNet is connected in this
	# fixture, exactly the "nobody answers feed_timer_expired" case the bug
	# report names.
	_advance_one_interval(block_timer)
	Events.feed_timer_expired.disconnect(collect)
	assert_true(expired.has(0), "fixture: slot 0's interval expired with its piece still unspent")
	assert_false(Match.is_release_locked(0), "fixture: unspent at expiry, so no lock yet (see MatchFeed._tick_feed())")

	var second: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(
		second, PlacementRules.REASON_OK,
		"The owner's own voluntary placement, arriving after the unanswered expiry, must still be accepted."
	)

	# A full interval later: under the bug, _feed_expired never cleared, so
	# _tick_feed() skipped this slot forever, _release_locked from the
	# placement above (the concurrent branch's early-release arm) never
	# unlocked, and this call returned REASON_NO_BLOCK forever.
	_advance_one_interval(block_timer)

	var third: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(
		third, PlacementRules.REASON_OK,
		"a full interval later, the slot must be able to place again, not latched shut."
	)
	assert_eq(_blocks_root.get_child_count(), 2, "Both accepted placements spawned exactly one block each.")


func test_boundary_crossing_does_not_auto_release_a_piece_already_released_early() -> void:
	# Regression guard: the fix above must not touch the normal auto_drop
	# cadence (spec 1.4 "[ORIGINAL target]") -- an early release stays
	# release-locked until the interval boundary, and crossing that boundary
	# must not force-release (auto-drop) a prepared piece merely because the
	# previous one was placed early.
	var block_timer: float = MatchConfig.BLOCK_TIMER_MIN
	var expired: Array[int] = []
	var collect: Callable = func(slot_id: int) -> void: expired.append(slot_id)
	Events.feed_timer_expired.connect(collect)
	Match.start_match(_free_for_all_config(2, block_timer))
	_run_countdown()

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_OK, "fixture: an early release before the boundary")
	assert_true(Match.is_release_locked(0), "fixture: the prepared next piece is locked")

	_advance_one_interval(block_timer)
	Events.feed_timer_expired.disconnect(collect)

	assert_false(
		expired.has(0),
		"Crossing the boundary for a slot that already released early must not force anything (spec 1.4)."
	)
	assert_false(Match.is_release_locked(0), "The boundary unlocked the prepared piece.")
	assert_almost_eq(
		Match.feed_time_left(0), block_timer, 0.05,
		"and started a fresh interval for it."
	)

	var second: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(second, PlacementRules.REASON_OK, "The now-unlocked piece may be released.")
	assert_eq(_blocks_root.get_child_count(), 2)
