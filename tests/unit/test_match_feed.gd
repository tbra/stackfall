extends GutTest
## Bontago-2lr: autoload/match/MatchFeed.gd's _consume_and_refeed() only reset
## _feed_expired/_feed_time_left/_release_locked on the host's own forced
## auto_drop. If a slot's interval expired (Events.feed_timer_expired fired,
## spec 2.4's "[ORIGINAL target]" cadence) and nothing answered it with that
## forced release before the slot's owner placed voluntarily instead, the
## voluntary placement itself never cleared the latch: _tick_feed() skips a
## slot for as long as _feed_expired stays true, so the slot's timer never
## counted down again and its next voluntary release found itself
## is_release_locked() with no boundary left to ever unlock it -- refused
## with REASON_NO_BLOCK forever. In the shipped game a listener always
## answers unconditionally (game/PlayerController.gd's and net/MatchNet.gd's
## own _on_feed_timer_expired()), so this fixture reproduces the gap the same
## way tests/unit/test_match_flow.gd does elsewhere: driving Match directly,
## with nothing connected to Events.feed_timer_expired to auto-drop for it.
##
## Fixture setup mirrors test_match_flow.gd's own before_each/after_each and
## _free_for_all_config()/_run_countdown()/_home_world_position() helpers
## (duplicated rather than shared -- GDScript test scripts don't inherit each
## other's private helpers) so this file stays self-contained and does not
## grow test_match_flow.gd's own ~40-test runtime.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _tiny_map_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	return config


func _free_for_all_config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = block_timer
	config.rng_seed = 98765
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _advance_one_interval(block_timer: float) -> void:
	for _i: int in range(int(ceil(block_timer * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func test_a_voluntary_placement_after_unanswered_expiry_unlatches_the_slot() -> void:
	var block_timer: float = MatchConfig.BLOCK_TIMER_MIN
	# Bontago-mv0.10's own precedent (test_match_flow.gd's
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
		"Bontago-2lr: a full interval later, the slot must be able to place again, not latched shut."
	)
	assert_eq(_blocks_root.get_child_count(), 2, "Both accepted placements spawned exactly one block each.")


func test_boundary_crossing_does_not_auto_release_a_piece_already_released_early() -> void:
	# Regression guard: the fix above must not touch the normal auto_drop
	# cadence (spec 2.4 "[ORIGINAL target]") -- an early release stays
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
		"Crossing the boundary for a slot that already released early must not force anything (spec 2.4)."
	)
	assert_false(Match.is_release_locked(0), "The boundary unlocked the prepared piece.")
	assert_almost_eq(
		Match.feed_time_left(0), block_timer, 0.05,
		"and started a fresh interval for it."
	)

	var second: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(second, PlacementRules.REASON_OK, "The now-unlocked piece may be released.")
	assert_eq(_blocks_root.get_child_count(), 2)
