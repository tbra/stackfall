extends GutTest
## Bontago-1pi.18.1: QoL experiments A (timer pause, block backlog, goal radius).
## Every toggle defaults OFF; each is exercised on and off against the real Match.

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
	# The topple-scan test seam lives on the Match autoload's feed and outlives the
	# test that set it; clear it so a later test does not start already paused.
	Match._feed._qol_moving_counts_source = Callable()
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(qol: QolExperiments) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
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


func _home(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


# --- defaults and serialization -----------------------------------------------

func test_every_toggle_defaults_off_and_default_config_is_unchanged() -> void:
	var qol: QolExperiments = load("res://config/qol_experiments.tres") as QolExperiments
	assert_false(qol.timer_pause_enabled)
	assert_false(qol.backlog_enabled)
	assert_false(qol.goal_radius_enabled)
	assert_eq(qol.effective_backlog_max(), 0)
	assert_eq(qol.effective_goal_radius(4.0), 4.0)
	assert_null(MatchConfig.new().qol)
	assert_false(MatchConfig.new().to_dict().has("qol"), "no qol key unless a snapshot exists")


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


func test_host_snapshots_shared_resource_at_match_start() -> void:
	_start(null)
	assert_not_null(Match.config.qol, "host snapshot exists")
	assert_false(Match.config.qol.backlog_enabled)
	assert_false(Match.config.qol == load("res://config/qol_experiments.tres"), "a copy, not the shared instance")


# --- Q0 interface stub: pause_max_s, any_enabled, active_ids, with_toggles --------

func test_pause_max_s_defaults_and_round_trips() -> void:
	var qol: QolExperiments = QolExperiments.new()
	assert_eq(qol.pause_max_s, 10.0)
	assert_true(qol.to_dict().has("pause_max_s"))
	qol.pause_max_s = 25.0
	var wire: Dictionary = bytes_to_var(var_to_bytes(qol.to_dict())) as Dictionary
	assert_eq(QolExperiments.from_dict(wire).pause_max_s, 25.0)
	var config: MatchConfig = MatchConfig.new()
	config.qol = qol
	var back: MatchConfig = MatchConfig.from_dict(bytes_to_var(var_to_bytes(config.to_dict())) as Dictionary)
	assert_eq(back.qol.pause_max_s, 25.0, "carried inside the MatchConfig snapshot")


func test_pause_max_s_missing_wrong_typed_or_non_finite_keeps_the_default() -> void:
	assert_eq(QolExperiments.from_dict({}).pause_max_s, 10.0, "older snapshot without the key")
	assert_eq(QolExperiments.from_dict({"pause_max_s": "soon"}).pause_max_s, 10.0)
	assert_eq(QolExperiments.from_dict({"pause_max_s": NAN}).pause_max_s, 10.0)
	assert_eq(QolExperiments.from_dict({"pause_max_s": INF}).pause_max_s, 10.0)
	assert_eq(QolExperiments.from_dict({"pause_max_s": null}).pause_max_s, 10.0)
	assert_eq(QolExperiments.from_dict({"pause_max_s": 12}).pause_max_s, 12.0, "an int is a number")


func test_pause_max_s_is_clamped_to_one_to_sixty() -> void:
	assert_eq(QolExperiments.from_dict({"pause_max_s": 0.0}).pause_max_s, 1.0)
	assert_eq(QolExperiments.from_dict({"pause_max_s": -5.0}).pause_max_s, 1.0)
	assert_eq(QolExperiments.from_dict({"pause_max_s": 900.0}).pause_max_s, 60.0)
	var qol: QolExperiments = QolExperiments.new()
	qol.pause_max_s = NAN
	qol.sanitize()
	assert_eq(qol.pause_max_s, 10.0, "sanitize() repairs a non-finite value to the default")
	qol.pause_max_s = 0.25
	qol.sanitize()
	assert_eq(qol.pause_max_s, 1.0)


func test_any_enabled_and_active_ids_follow_the_four_toggles_in_fixed_order() -> void:
	var qol: QolExperiments = QolExperiments.new()
	assert_false(qol.any_enabled())
	assert_eq(qol.active_ids(), PackedStringArray())
	qol.gift_slot_enabled = true
	assert_true(qol.any_enabled())
	assert_eq(qol.active_ids(), PackedStringArray(["gift_slot"]))
	qol.timer_pause_enabled = true
	qol.goal_radius_enabled = true
	assert_eq(qol.active_ids(), PackedStringArray(["timer_pause", "goal_radius", "gift_slot"]), "fixed order, not set order")
	qol.backlog_enabled = true
	assert_eq(qol.active_ids(), PackedStringArray(["timer_pause", "backlog", "goal_radius", "gift_slot"]))
	assert_eq(String(QolExperiments.ID_TIMER_PAUSE), "timer_pause")
	assert_eq(String(QolExperiments.ID_BACKLOG), "backlog")
	assert_eq(String(QolExperiments.ID_GOAL_RADIUS), "goal_radius")
	assert_eq(String(QolExperiments.ID_GIFT_SLOT), "gift_slot")


func test_other_parameters_do_not_count_as_enabled() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.pause_event_s = 9.0
	qol.backlog_max = 3
	qol.goal_radius_multiplier = 3.0
	qol.timer_pause_on_special = false
	assert_false(qol.any_enabled(), "only the four enable flags decide")
	var shared: QolExperiments = load("res://config/qol_experiments.tres") as QolExperiments
	assert_false(shared.any_enabled(), "the shipped shared resource has every toggle off")
	assert_eq(shared.active_ids().size(), 0)


func test_with_toggles_copies_parameters_and_sets_only_the_four_flags() -> void:
	var base: QolExperiments = QolExperiments.new()
	base.timer_pause_enabled = true
	base.pause_event_s = 7.5
	base.pause_max_s = 20.0
	base.backlog_max = 3
	base.goal_radius_multiplier = 3.0
	base.gift_slot_capacity = 2
	base.timer_pause_on_special = false
	var out: QolExperiments = QolExperiments.with_toggles(base, false, true, true, false)
	assert_false(out == base, "a distinct copy")
	assert_false(out.timer_pause_enabled, "flag taken from the argument, not the base")
	assert_true(out.backlog_enabled)
	assert_true(out.goal_radius_enabled)
	assert_false(out.gift_slot_enabled)
	assert_eq(out.pause_event_s, 7.5)
	assert_eq(out.pause_max_s, 20.0)
	assert_eq(out.backlog_max, 3)
	assert_eq(out.goal_radius_multiplier, 3.0)
	assert_eq(out.gift_slot_capacity, 2)
	assert_false(out.timer_pause_on_special, "non-flag booleans are kept")
	assert_true(base.timer_pause_enabled, "base is not modified")
	assert_false(base.backlog_enabled)
	assert_eq(out.active_ids(), PackedStringArray(["backlog", "goal_radius"]))


func test_with_toggles_accepts_a_null_base_and_all_on() -> void:
	var out: QolExperiments = QolExperiments.with_toggles(null, true, true, true, true)
	assert_eq(out.active_ids().size(), 4)
	assert_eq(out.pause_max_s, 10.0, "defaults when no base is given")
	var all_off: QolExperiments = QolExperiments.with_toggles(out, false, false, false, false)
	assert_false(all_off.any_enabled())
	assert_true(out.any_enabled(), "the source copy stays untouched")


# --- 1: timer pause -----------------------------------------------------------

func test_timer_pause_rule_special_and_topple() -> void:
	var qol: QolExperiments = QolExperiments.new()
	var rule: TimerPause = TimerPause.new(qol, 2)
	rule.note_special()
	rule.update(0.1, PackedInt32Array([99, 99]))
	assert_false(rule.is_paused(0), "toggle off: never paused")
	qol.timer_pause_enabled = true
	rule = TimerPause.new(qol, 2)
	rule.update(0.1, PackedInt32Array([0, qol.topple_moving_blocks_min]))
	assert_false(rule.is_paused(0))
	assert_true(rule.is_paused(1), "slot 1 has enough fast blocks")
	rule.update(qol.pause_tail_s + 0.5, PackedInt32Array([0, 0]))
	assert_false(rule.is_paused(1), "tail elapsed")
	rule.note_special()
	assert_true(rule.is_paused(0) and rule.is_paused(1), "special pauses everyone")
	rule.update(qol.pause_event_s + 0.1, PackedInt32Array())
	assert_false(rule.is_paused(0))


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


func test_timer_not_paused_with_toggle_off() -> void:
	_start(QolExperiments.new())
	assert_null(Match._feed._timer_pause)
	var before: float = Match.feed_time_left(0)
	for _i: int in range(60):
		Match._process(1.0 / 60.0)
	assert_false(Match.qol_timer_paused(0))
	assert_lt(Match.feed_time_left(0), before - 0.9)


func test_special_event_pauses_timers_when_on() -> void:
	var on: QolExperiments = QolExperiments.new()
	on.timer_pause_enabled = true
	_start(on)
	Match._feed.note_special_triggered()
	assert_true(Match.qol_timer_paused(0) and Match.qol_timer_paused(1))


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

func test_off_expiry_still_fires_the_forced_drop() -> void:
	var expired: Array[int] = []
	var collect: Callable = func(slot_id: int) -> void: expired.append(slot_id)
	Events.feed_timer_expired.connect(collect)
	_start(QolExperiments.new())
	_interval()
	Events.feed_timer_expired.disconnect(collect)
	assert_true(expired.has(0))
	assert_eq(Match.qol_backlog_count(0), 0)


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


func test_placing_takes_from_the_backlog_first() -> void:
	var on: QolExperiments = QolExperiments.new()
	on.backlog_enabled = true
	_start(on)
	var first: BlockShape = Match.held_shape(0)
	_interval()
	assert_eq(Match.qol_backlog_count(0), 1)
	assert_eq(Match.request_place(0, _home(0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	assert_eq(Match.qol_backlog_count(0), 0, "queue consumed")
	assert_eq(Match.held_shape(0), first, "the queued block came back before any bag draw")


# --- 3: goal radius -----------------------------------------------------------

func test_goal_radius_toggle_leaves_no_build_disc_and_scales_claim_radius() -> void:
	var base: float = (load("res://config/territory_tuning.tres") as TerritoryTuning).goal_zone_radius
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
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres") as TerritoryTuning
	var grid: CellGrid = CellGrid.new(20.0, 1.0)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(tuning.home_radius + 2.0, 0.0), tuning.home_radius, 0, 0, true, -1)
	]
	raster.update(circles, TerritorySolver.new(tuning).solve(circles), 0.1, true, false)
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


func test_claim_radius_tie_between_teams_is_unclaimed() -> void:
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres") as TerritoryTuning
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(20.0, 1.0), tuning)
	var d: float = tuning.home_radius + 2.0
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(d, 0.0), tuning.home_radius, 0, 0, true, -1),
		InfluenceCircle.new(Vector2(-d, 0.0), tuning.home_radius, 1, 1, true, -1),
	]
	raster.update(circles, TerritorySolver.new(tuning).solve(circles), 0.1, true, false)
	assert_eq(WinChecker.goal_holder(raster, Vector2.ZERO, 4.0), WinChecker.NO_TEAM, "symmetric split: no majority")


# --- late join ----------------------------------------------------------------

func test_late_join_replay_carries_qol_feed_state_only_when_set() -> void:
	var fake: FakeNet = FakeNet.host({}, [0, 1])
	Match.set_net_provider(fake)
	var net: Node = (load("res://net/MatchNet.gd") as GDScript).new() as Node
	net.set_process(false)
	add_child_autofree(net)
	net.call("set_providers", fake, Match)
	var on: QolExperiments = QolExperiments.new()
	on.backlog_enabled = true
	_start(on)
	var quiet: Array = _qol_replay_events(net)
	assert_eq(quiet.size(), 0, "nothing queued: nothing replayed")
	_interval()
	assert_eq(Match.qol_backlog_count(0), 1)
	var events: Array = _qol_replay_events(net)
	assert_true(events.has([0, 1, false]) or events.has([1, 1, false]), "slot with a queued block replays its backlog")
	Match.abort_match()
	Match.set_net_provider(null)


func _qol_replay_events(net: Node) -> Array:
	var out: Array = []
	for message: Array in net.call("build_world_replay"):
		if message[0] != &"net_match_event":
			continue
		var args: Array = message[1]
		if args.size() >= 2 and args[0] == net.get("EVENT_QOL_FEED"):
			out.append(args[1])
	return out


## Bontago-1pi.18.3: bot beacon_held_by_own (and the diagnostics) use the capture radius.
## Returns beacon_held_by_own[0] for team 0 with a home whose edge stops short of
## the flag cell but reaches inside the claim radius.
func _bot_beacon_held(enabled: bool) -> bool:
	var qol: QolExperiments = QolExperiments.new()
	qol.goal_radius_enabled = enabled
	qol.goal_radius_multiplier = 4.0
	var config: MatchConfig = _config(qol)
	config.game_mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	var tuning: TerritoryTuning = Match._territory_tuning
	var beacons: PackedVector2Array = PlayerSlot.goal_positions_for(Match.config.effective_goal_flag_count(), Match.config.map_def())
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(60.0, 1.0), tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(beacons[0] + Vector2(tuning.home_radius + 2.0, 0.0), tuning.home_radius, 0, 0, true, -1)
	]
	raster.update(circles, TerritorySolver.new(tuning).solve(circles), 0.1, true, false)
	var cell: Vector2i = raster.grid().world_to_cell(beacons[0])
	assert_eq(raster.team_at(cell.x, cell.y), -1, "fixture: flag cell not owned")
	Match._territory._raster = raster
	var goal: BotModeGoal = Match.bot_mode_goal(0)
	var held: bool = goal != null and goal.beacon_held_by_own.size() > 0 and goal.beacon_held_by_own[0]
	Match.abort_match()
	return held


func test_bot_beacon_held_follows_claim_radius_toggle() -> void:
	assert_false(_bot_beacon_held(false), "OFF: flag cell only")
	assert_true(_bot_beacon_held(true), "ON: radius majority counts")


# --- Toggle B: gift slot (Bontago-1pi.18.2) -----------------------------------

func _slot_qol(enabled: bool, capacity: int = 1) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new()
	qol.gift_slot_enabled = enabled
	qol.gift_slot_capacity = capacity
	return qol


func test_gift_slot_defaults_off_and_round_trips() -> void:
	var qol: QolExperiments = load("res://config/qol_experiments.tres") as QolExperiments
	assert_false(qol.gift_slot_enabled)
	assert_eq(qol.effective_gift_slot_capacity(), 0)
	var back: QolExperiments = QolExperiments.from_dict(_slot_qol(true, 2).to_dict())
	assert_true(back.gift_slot_enabled)
	assert_eq(back.effective_gift_slot_capacity(), 2)
	assert_eq(QolExperiments.from_dict(_slot_qol(true, 99).to_dict()).gift_slot_capacity, QolExperiments.GIFT_SLOT_CAPACITY_CEILING)


func test_gift_slot_off_queues_the_gift_as_before() -> void:
	_start(_slot_qol(false))
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_eq(Match.next_special(0), &"anvil")
	assert_eq(Match.gift_slot_head(0), &"")
	assert_false(Match.request_use_gift_slot(0), "nothing to use with the toggle off")


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


func test_gift_slot_full_replaces_the_old_gift() -> void:
	_start(_slot_qol(true, 1))
	Match._gifts._queue_claimed_special(0, &"anvil")
	Match._gifts._queue_claimed_special(0, &"bomb")
	assert_eq(Match.gift_slot_count(0), 1)
	assert_eq(Match.gift_slot_head(0), &"bomb")


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


func test_gift_slot_use_is_refused_while_a_gift_is_in_hand_or_for_a_bad_slot() -> void:
	_start(_slot_qol(true, 2))
	Match._gifts._queue_claimed_special(0, &"anvil")
	Match._gifts._queue_claimed_special(0, &"bomb")
	assert_true(Match.request_use_gift_slot(0))
	assert_false(Match.request_use_gift_slot(0), "first gift still in hand")
	assert_eq(Match.gift_slot_count(0), 1, "refusal keeps the slotted gift")
	assert_false(Match.request_use_gift_slot(-1))
	assert_false(Match.request_use_gift_slot(99))
	assert_false(Match.request_use_gift_slot(1), "slot 1 has nothing")


func test_gift_slot_use_is_refused_for_an_off_turn_seat_in_turn_based() -> void:
	var config: MatchConfig = _config(_slot_qol(true))
	config.turn_based = true
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING)
	var on_turn: int = Match.active_slot()
	var off_turn: int = 1 - on_turn
	Match._gifts._queue_claimed_special(on_turn, &"anvil")
	Match._gifts._queue_claimed_special(off_turn, &"bomb")
	assert_false(Match.request_use_gift_slot(off_turn), "off-turn seat is rejected")
	assert_eq(Match.gift_slot_head(off_turn), &"bomb", "rejection keeps the slotted gift")
	assert_true(Match.request_use_gift_slot(on_turn), "on-turn seat is accepted")


func test_gift_slot_activation_guarantees_a_minimum_window() -> void:
	var qol: QolExperiments = _slot_qol(true)
	qol.gift_slot_min_window_s = 2.0
	_start(qol)
	Match._gifts._queue_claimed_special(0, &"anvil")
	for _i: int in range(int(ceil((MatchConfig.BLOCK_TIMER_MIN - 0.5) * 60.0))):
		Match._process(1.0 / 60.0)
	assert_lt(Match.feed_time_left(0), 1.0, "timer nearly out before activation")
	assert_true(Match.request_use_gift_slot(0))
	assert_almost_eq(Match.feed_time_left(0), 2.0, 0.001, "window raised to the minimum")
	assert_eq(QolExperiments.from_dict(qol.to_dict()).gift_slot_min_window_s, 2.0)


func test_gift_slot_replicates_to_a_client_mirror() -> void:
	_start(_slot_qol(true))
	var seen: Array = []
	var on_change: Callable = func(slot_id: int, contents: Array, activated: StringName, carrier: StringName) -> void:
		seen.append([slot_id, contents, activated, carrier])
	Events.gift_slot_changed.connect(on_change)
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_true(Match.request_use_gift_slot(0))
	Events.gift_slot_changed.disconnect(on_change)
	assert_eq(seen.size(), 2)
	assert_eq(seen[0][1], [&"anvil"])
	assert_eq(seen[1][1], [])
	assert_eq(seen[1][2], &"anvil")
	assert_ne(seen[1][3], &"")
	Match.apply_replicated_gift_slot(1, seen[0][1], &"", &"")
	assert_eq(Match.gift_slot_head(1), &"anvil", "mirror applies slot contents")
	Match.apply_replicated_gift_slot(1, seen[1][1], seen[1][2], seen[1][3])
	assert_eq(Match.gift_slot_head(1), &"")
	assert_eq(Match.next_special(1), &"anvil", "activation queues the carrier before the feed event")
