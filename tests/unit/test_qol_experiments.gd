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
