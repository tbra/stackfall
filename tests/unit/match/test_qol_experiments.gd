extends "res://tests/unit/match/match_world_test.gd"
## QoL experiments A (timer pause, block backlog, goal radius).
## Every toggle defaults OFF; each is exercised on and off against the real Match.

func after_each() -> void:
	# The topple-scan test seam lives on the Match autoload's feed and outlives the
	# test that set it; clear it so a later test does not start already paused.
	Match._feed._qol_moving_counts_source = Callable()
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(qol: QolExperiments) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	config.rng_seed = 5150
	config.qol = qol
	return config


func _start(qol: QolExperiments) -> void:
	Match.start_match(_config(qol))
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING)


func _interval() -> void:
	for _i: int in range(int(ceil(MatchConfig.BLOCK_TIMER_MIN * 60.0)) + 2):
		Match._process(1.0 / 60.0)


# --- defaults and serialization -----------------------------------------------

func test_qol_round_trips_through_match_config_dict() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.backlog_enabled = true
	qol.backlog_max = 3
	qol.goal_radius_enabled = true
	qol.goal_radius_multiplier = 2.5
	var config: MatchConfig = MatchConfig.new()
	config.qol = qol
	var wire: Dictionary = bytes_to_var(var_to_bytes(config.to_dict())) as Dictionary
	var back: MatchConfig = MatchConfig.from_dict(wire)
	assert_true(back.qol.backlog_enabled)
	assert_eq(back.qol.backlog_max, 3)
	assert_true(back.qol.goal_radius_enabled)
	assert_eq(back.qol.goal_radius_multiplier, 2.5)
	assert_false(back.qol.timer_pause_enabled)


# --- 1: timer pause -----------------------------------------------------------

func test_timer_freezes_during_topple_when_on_and_runs_when_off() -> void:
	var on: QolExperiments = QolExperiments.new()
	on.timer_pause_enabled = true
	_start(on)
	var min_moving: int = on.topple_moving_blocks_min
	Match._feed._qol_moving_counts_source = func() -> PackedInt32Array:
		return PackedInt32Array([min_moving, 0])
	Match._feed._qol_scan_left = 0.0
	var before: float = Match.feed_time_left(0)
	for _i: int in range(60):
		Match._process(1.0 / 60.0)
	assert_true(Match.qol_timer_paused(0))
	assert_false(Match.qol_timer_paused(1))
	assert_almost_eq(Match.feed_time_left(0), before, 0.05, "slot 0 frozen")
	assert_lt(Match.feed_time_left(1), before - 0.9, "slot 1 kept counting")


func test_stall_guard_runs_a_capped_pause_through_the_real_feed() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.timer_pause_enabled = true
	qol.pause_event_s = 30.0
	qol.pause_max_s = 1.0
	_start(qol)
	var changes: Array = []
	var collect: Callable = func(slot_id: int, backlog: int, paused: bool) -> void:
		changes.append([slot_id, backlog, paused])
	Events.qol_feed_changed.connect(collect)
	Match._feed.note_special_triggered()
	assert_true(Match.qol_timer_paused(0))
	var frozen_at: float = Match.feed_time_left(0)
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	assert_true(Match.qol_timer_paused(0), "inside the cap the timer is frozen")
	assert_almost_eq(Match.feed_time_left(0), frozen_at, 0.05)
	for _i: int in range(42):
		Match._process(1.0 / 60.0)
	assert_false(Match.qol_timer_paused(0), "past pause_max_s the guard lets the timer run")
	var running_from: float = Match.feed_time_left(0)
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	Events.qol_feed_changed.disconnect(collect)
	assert_lt(Match.feed_time_left(0), running_from - 0.4, "the block timer counts down again")
	assert_true(changes.has([0, 0, true]), "pause start announced")
	assert_true(changes.has([0, 0, false]), "guard exhaustion announced as unpaused")


# --- 2: backlog ---------------------------------------------------------------

func test_backlog_queues_until_full_then_forces() -> void:
	var on: QolExperiments = QolExperiments.new()
	on.backlog_enabled = true
	on.backlog_max = 2
	var expired: Array[int] = []
	var collect: Callable = func(slot_id: int) -> void: expired.append(slot_id)
	Events.feed_timer_expired.connect(collect)
	_start(on)
	var first: BlockShape = Match.held_shape(0)
	var seq: int = Match.feed_seq(0)
	_interval()
	assert_false(expired.has(0), "queued, not forced")
	assert_eq(Match.qol_backlog_count(0), 1)
	assert_gt(Match.feed_seq(0), seq, "old intents for the queued block are stale")
	assert_ne(Match.held_shape(0), first)
	_interval()
	assert_eq(Match.qol_backlog_count(0), 2)
	assert_false(expired.has(0))
	_interval()
	Events.feed_timer_expired.disconnect(collect)
	assert_true(expired.has(0), "backlog full: forced drop")
	assert_eq(Match.qol_backlog_count(0), 2)


# --- 3: goal radius -----------------------------------------------------------

func test_goal_radius_toggle_leaves_no_build_disc_and_scales_claim_radius() -> void:
	var base: float = (load("res://config/territory/territory_tuning.tres") as TerritoryTuning).goal_zone_radius
	_start(QolExperiments.new())
	assert_eq(Match._territory._goal_radii[0], base)
	assert_eq(Match._territory._claim_radius(), 0.0, "OFF: flag cell only")
	Match.abort_match()
	var on: QolExperiments = QolExperiments.new()
	on.goal_radius_enabled = true
	on.goal_radius_multiplier = 2.0
	_start(on)
	assert_eq(Match._territory._goal_radii[0], base, "no-build disc and drawn circle unchanged")
	assert_almost_eq(Match._territory._claim_radius(), base * 2.0, 0.001)


## Team 0 home whose edge stops short of the flag cell but reaches inside the claim radius.
func _claim_fixture() -> Array:
	var tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres") as TerritoryTuning
	var grid: CellGrid = CellGrid.new(20.0, 1.0)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(tuning.home_radius + 2.0, 0.0), tuning.home_radius, 0, 0, true, -1)
	]
	raster.fill_ownership(circles, TerritorySolver.new(tuning).solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
	return [raster, tuning]


func test_claim_radius_captures_when_territory_reaches_radius_not_flag_cell() -> void:
	var fixture: Array = _claim_fixture()
	var raster: TerritoryRaster = fixture[0]
	var cell: Vector2i = raster.grid().world_to_cell(Vector2.ZERO)
	assert_eq(raster.team_at(cell.x, cell.y), -1, "fixture: flag cell itself is not owned")
	assert_eq(WinChecker.goal_holder(raster, Vector2.ZERO), WinChecker.NO_TEAM, "OFF (radius 0) does not claim")
	assert_eq(WinChecker.goal_holder(raster, Vector2.ZERO, 4.0), 0, "ON claims via the radius")
	var off: WinChecker = WinChecker.new(PackedVector2Array([Vector2.ZERO]), 0.2)
	var on: WinChecker = WinChecker.new(PackedVector2Array([Vector2.ZERO]), 0.2)
	on.set_claim_radius(4.0)
	for i: int in range(5):
		off.update(raster, 0.1)
		on.update(raster, 0.1)
	assert_eq(off.winner(), WinChecker.NO_TEAM)
	assert_eq(on.winner(), 0)


# --- late join ----------------------------------------------------------------

func test_late_join_replay_carries_qol_feed_state_only_when_set() -> void:
	var fake: FakeNet = FakeNet.host({}, [0, 1])
	Match._net_provider = fake
	var replay: MatchWorldReplay = MatchWorldReplay.new(
		fake, Match, preload("res://config/net/net_config.tres"),
		WorldReplaySeams.make(func(_peer: int, _method: StringName, _args: Array) -> bool: return true, func() -> float: return 0.0)
	)
	var on: QolExperiments = QolExperiments.new()
	on.backlog_enabled = true
	_start(on)
	var quiet: Array = _qol_replay_events(replay)
	assert_eq(quiet.size(), 0, "nothing queued: nothing replayed")
	_interval()
	assert_eq(Match.qol_backlog_count(0), 1)
	var events: Array = _qol_replay_events(replay)
	assert_true(events.has([0, 1, false]) or events.has([1, 1, false]), "slot with a queued block replays its backlog")
	Match.abort_match()
	Match._net_provider = null


func _qol_replay_events(replay: MatchWorldReplay) -> Array:
	var out: Array = []
	for message: Array in replay.build_replay(2, 1):
		if message[0] != &"net_match_event":
			continue
		var args: Array = message[1]
		if args.size() >= 2 and args[0] == MatchWireEvents.QOL_FEED:
			out.append(args[1])
	return out


# --- Toggle B: gift slot -----------------------------------

func _slot_qol(enabled: bool, capacity: int = 1) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new()
	qol.gift_slot_enabled = enabled
	qol.gift_slot_capacity = capacity
	return qol


func test_gift_slot_on_holds_the_gift_without_touching_the_queue_or_block() -> void:
	_start(_slot_qol(true))
	var held_before: BlockShape = Match.held_shape(0)
	var next_before: BlockShape = Match.next_shape(0)
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_eq(Match.gift_slot_head(0), &"anvil")
	assert_eq(Match.next_special(0), &"")
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.held_shape(0), held_before)
	assert_eq(Match.next_shape(0), next_before, "the next block is untouched")


func test_gift_slot_use_makes_the_gift_the_held_piece_and_keeps_the_timer() -> void:
	_start(_slot_qol(true))
	Match._gifts._queue_claimed_special(0, &"anvil")
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	var left_before: float = Match.feed_time_left(0)
	var seq_before: int = Match.feed_seq(0)
	assert_true(Match.request_use_gift_slot(0))
	assert_eq(Match.held_special(0), &"anvil")
	assert_true(Match._feed.is_held_gift(0))
	assert_eq(Match.gift_slot_head(0), &"")
	assert_eq(Match.feed_time_left(0), left_before, "no timer restart")
	assert_gt(Match.feed_seq(0), seq_before)
	assert_false(Match.request_use_gift_slot(0), "slot is empty now")

