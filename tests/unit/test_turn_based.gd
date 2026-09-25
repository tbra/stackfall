extends GutTest
## Spec 2.7 "Turn-based [NEW]" and docs/M6_PLAN.md's B4: config.turn_based
## replaces hot-seat's instant hand-off with a settle-wait -- the next
## player's turn starts once every placed block has settled (game/
## BlockRegistry.gd's all_settled(), spec 2.2's own settled rule) or after
## TerritoryTuning.turn_based_max_settle_s, whichever comes first.
##
## Fixture mirrors test_sudden_death.gd's own before_each exactly
## (TinyMapMatchConfig over a manually-registered Field/BlockRegistry, no
## full Main scene). Settling itself is driven by BlockRegistry's own real
## _physics_process() (test_block_registry.gd's own convention: freeze the
## body, then await real physics frames until settled_time crosses
## PhysicsTuning.sleep_settle_time) in lockstep with manual Match._process()
## calls that carry _tick_turn_based() (mirrors test_only_the_active_slot_
## timer_runs_in_hot_seat()'s own 1/60 s per iteration convention).

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


func _turn_based_config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = false
	config.turn_based = true
	config.block_timer = 6.0
	config.rng_seed = 12345
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


## Ticks one real physics frame (advances BlockRegistry's own settle timers)
## and one matching Match._process() call (advances _tick_turn_based()'s
## countdown by the same 1/60 s), the same pairing the file header explains.
func _tick_one_physics_and_match_frame() -> void:
	await get_tree().physics_frame
	Match._process(1.0 / Engine.physics_ticks_per_second)


func test_placement_does_not_advance_the_turn_immediately() -> void:
	Match.start_match(_turn_based_config(2))
	_run_countdown()
	assert_eq(Match.active_slot(), 0)

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_OK)

	assert_eq(Match.active_slot(), 0,
		"turn_based must not hand the turn over immediately like hot_seat -- it waits for the settle-wait")


func test_advance_turn_fires_once_all_settled_turns_true() -> void:
	Match.start_match(_turn_based_config(2))
	_run_countdown()

	Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the placement spawned exactly one block")
	var spawned: Block = _blocks_root.get_child(0) as Block
	spawned.freeze = true  # settle it deterministically, same convention as test_block_registry.gd

	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ticks: int = int(ceil(tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	var max_wait_ticks: int = int(ceil(Match._territory_tuning.turn_based_max_settle_s * Engine.physics_ticks_per_second))
	assert_lt(ticks, max_wait_ticks,
		"fixture: the block must settle well before the safety cap, or this test can't tell settling from timeout")

	for _i: int in range(ticks):
		await _tick_one_physics_and_match_frame()

	assert_eq(Match.active_slot(), 1,
		"the turn advances once every placed block has settled, before the safety cap runs out")


func test_a_never_settling_block_advances_at_exactly_the_safety_cap() -> void:
	Match.start_match(_turn_based_config(2))
	_run_countdown()

	Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the placement spawned exactly one block")
	var spawned: Block = _blocks_root.get_child(0) as Block
	spawned.linear_velocity = Vector3(10.0, 0.0, 0.0)  # far above sleep_linear_threshold: never settles

	var cap: float = Match._territory_tuning.turn_based_max_settle_s
	var frames_just_under: int = int(cap * Engine.physics_ticks_per_second) - 1
	for _i: int in range(frames_just_under):
		await _tick_one_physics_and_match_frame()
		spawned.linear_velocity = Vector3(10.0, 0.0, 0.0)  # keep re-forcing motion every frame
	assert_eq(Match.active_slot(), 0, "the safety cap has not run out yet")

	for _i: int in range(5):
		await _tick_one_physics_and_match_frame()
		spawned.linear_velocity = Vector3(10.0, 0.0, 0.0)

	assert_eq(Match.active_slot(), 1,
		"spec 2.7: a block that never settles still hands the turn over after turn_based_max_settle_s")


func test_request_place_rejects_the_slot_whose_turn_it_isnt_under_turn_based() -> void:
	Match.start_match(_turn_based_config(2))
	_run_countdown()
	assert_eq(Match.active_slot(), 0)

	var reason: StringName = Match.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_NOT_YOUR_TURN)
	assert_eq(_blocks_root.get_child_count(), 0, "A not-your-turn request must not spawn anything under turn_based either.")


# --- stackfall-reviewer findings (Bontago-keo.10, MatchFeed.gd review fix) --
# autoload/match/MatchFeed.gd's _tick_feed()/_consume_and_refeed() used to gate
# only on config.hot_seat, so turn_based fell into the concurrent "every slot
# ticks" branch instead of hot-seat's single-active-slot one.

func test_eliminated_active_slot_advances_the_turn_before_it_ever_places() -> void:
	# Free-for-all (TeamMode.OFF, this fixture's default): three players, three
	# teams, mirrors test_sudden_death.gd's own
	# test_elimination_during_sudden_death_finishes_the_match_immediately --
	# eliminating one of three leaves two teams alive, so the match itself
	# keeps running and _tick_turn_based() has somewhere to advance the turn
	# to.
	Match.start_match(_turn_based_config(3))
	_run_countdown()
	assert_eq(Match.active_slot(), 0)

	# The active slot loses its home flag before ever placing a block this
	# turn -- no settle-wait has been armed (MatchLifecycle's
	# _turn_settle_wait_left is still -1.0), so before this fix nothing in
	# _tick_turn_based() (which only acts once a wait is running) or
	# _tick_feed() (which used to tick every slot's timer under turn_based,
	# never checking whose turn it was) ever called advance_turn(): the match
	# deadlocked on a slot that can never place again.
	Match._lifecycle._eliminate_slot(0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: one of three eliminated must not end the match")

	Match._process(1.0 / 60.0)

	assert_eq(Match.active_slot(), 1,
		"an active slot eliminated before it places must hand the turn to the next live slot, not deadlock")


func test_only_the_active_slots_timer_runs_under_turn_based() -> void:
	# Mirrors test_match_flow.gd's own
	# test_only_the_active_slot_timer_runs_in_hot_seat() -- turn_based shares
	# hot-seat's single-active-slot feed branch (this package's fix), not the
	# concurrent "every slot ticks" branch spec 2.4's free-for-all uses.
	Match.start_match(_turn_based_config(2))
	_run_countdown()
	assert_eq(Match.active_slot(), 0)

	var full: float = Match.feed_time_left(0)
	for _i: int in range(60):  # 1 second at 60 Hz
		Match._process(1.0 / 60.0)

	assert_lt(Match.feed_time_left(0), full, "The active slot's timer should have ticked down.")
	assert_almost_eq(Match.feed_time_left(1), 6.0, 0.001, "The inactive slot's timer must not move under turn_based either.")
