extends GutTest
## Capture the Flag: beacons are the
## goal flags; each held beacon scores per elapsed second, the highest score at
## the round timer wins, a tie is shared. Raster-level tests use the real solver
## like test_win_checker.gd; the lifecycle and replication tests go through Match.

const MatchNetScript := preload("res://net/MatchNet.gd")
const MAP_RADIUS: float = 20.0
const RATE: float = 2.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null
var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _fake_net: FakeNet
var _net: MatchNetScript


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, 1.0)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func after_each() -> void:
	_net = null
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), _tuning.home_radius, team, slot if slot >= 0 else team, true, -1)


func _block(x: float, z: float, r: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), r, team, team, false, 1)


func _rasterize(circles: Array[InfluenceCircle]) -> void:
	_raster.fill_ownership(circles, _solver.solve(circles), true)
	_raster.adopt_fill(_raster, 0.1, true, false)


func _objective(goals: Array[Vector2], teams: int = 2) -> CaptureFlagObjective:
	var objective: CaptureFlagObjective = CaptureFlagObjective.new(PackedVector2Array(goals), RATE)
	objective.reset(teams)
	return objective


func _run(objective: CaptureFlagObjective, circles: Array[InfluenceCircle], seconds: float, step: float = 0.1) -> void:
	_rasterize(circles)
	for _i: int in range(int(round(seconds / step))):
		objective.update(_raster, step)


# --- Objective shape -----------------------------------------------------------

# --- Beacons ---------------------------------------------------------------------

func test_extra_state_carries_held_counts_and_round_trips_to_a_client() -> void:
	var host: CaptureFlagObjective = _objective([Vector2.ZERO])
	_run(host, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 0.1)
	var extra: Dictionary = host.extra_state()
	assert_eq(extra["beacons"], 1)
	assert_eq(extra["held_0"], 1)
	assert_eq(extra["held_1"], 0)
	var client: CaptureFlagObjective = _objective([Vector2.ZERO])
	client.apply_mode_state(host.mode_state())
	assert_eq(client.extra_state()["held_0"], 1)
	assert_eq(client.extra_state()["held_1"], 0)


func test_one_beacon_scores_immediately_at_the_rate() -> void:
	var objective: CaptureFlagObjective = _objective([Vector2.ZERO])
	_run(objective, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 0.1)
	assert_almost_eq(objective.scores()[0], RATE * 0.1, 0.0001, "no hold delay")
	_run(objective, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 4.9)
	assert_almost_eq(objective.scores()[0], RATE * 5.0, 0.001)
	assert_almost_eq(objective.scores()[1], 0.0, 0.0001)


# --- Loss and reclaim -------------------------------------------------------------

func test_loss_stops_scoring_and_reclaim_resumes_it_keeping_the_total() -> void:
	var objective: CaptureFlagObjective = _objective([Vector2.ZERO])
	_run(objective, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 3.0)
	_run(objective, [_home(15.0, 15.0, 0)] as Array[InfluenceCircle], 4.0)
	assert_almost_eq(objective.scores()[0], RATE * 3.0, 0.001, "score is kept while the beacon is lost")
	_run(objective, [_home(0.0, 0.0, 1)] as Array[InfluenceCircle], 2.0)
	assert_almost_eq(objective.scores()[1], RATE * 2.0, 0.001, "a rival takes it over")
	_run(objective, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 1.0)
	assert_almost_eq(objective.scores()[0], RATE * 4.0, 0.001, "reclaim resumes from the kept total")


# --- Path to a living home ----------------------------------------------------------

func test_a_beacon_in_a_block_circle_cut_off_from_home_does_not_score() -> void:
	var goal: Vector2 = Vector2(15.0, 15.0)
	var objective: CaptureFlagObjective = _objective([goal])
	_run(objective, [_home(0.0, 0.0, 0), _block(15.0, 15.0, 3.0, 0)] as Array[InfluenceCircle], 5.0)
	assert_almost_eq(objective.scores()[0], 0.0, 0.0001, "an island of blocks has no path home")


# --- Frame-rate independence ----------------------------------------------------------

# --- Timer end ----------------------------------------------------------------------------

func test_highest_score_wins_at_timer_end() -> void:
	var objective: CaptureFlagObjective = _objective([Vector2.ZERO], 3)
	_run(objective, [_home(0.0, 0.0, 2)] as Array[InfluenceCircle], 3.0)
	assert_eq(objective.on_round_timer_end(), 2)
	assert_eq(objective.results_fields()["winners"], "2")


func test_a_tie_is_a_shared_win() -> void:
	var goals: Array[Vector2] = [Vector2(-15.0, 0.0), Vector2(15.0, 0.0)]
	var objective: CaptureFlagObjective = _objective(goals, 3)
	_run(objective, [_home(-15.0, 0.0, 0), _home(15.0, 0.0, 1)] as Array[InfluenceCircle], 4.0, 1.0 / 60.0)
	assert_eq(objective.on_round_timer_end(), 0, "lowest tied team carries winner_id")
	assert_eq(objective.results_fields()["winners"], "0,1", "both tied teams share the win")
	var text: String = ResultsScreen.shared_winners_text({"winner_kind": MatchStats.WINNER_KIND_TEAM, "mode": objective.results_fields()})
	assert_eq(text, "Teams 1 & 2 share the win!")


# --- Match integration and replication --------------------------------------------------

func _setup_world() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _ctf_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 99
	config.sudden_death = false
	config.game_mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	config.round_timer_minutes = 2
	return config


func _tick(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds / step))):
		Match._process(step)


func test_a_ctf_match_uses_the_objective_and_the_round_timer_decides() -> void:
	_setup_world()
	var config: MatchConfig = _ctf_config()
	assert_eq(MatchConfig.from_dict(config.to_dict()).game_mode, MatchConfig.GameMode.CAPTURE_THE_FLAG, "mode survives the wire")
	Match.start_match(config)
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var objective: ModeObjective = Match._territory._objective
	assert_true(objective is CaptureFlagObjective)
	assert_almost_eq(Match._lifecycle.match_timer_left(), 120.0, 0.5)
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	Match._lifecycle._match_timer_left = 0.02
	_tick(0.2)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(results.size(), 1)
	var mode: Dictionary = results[0]["mode"]
	assert_eq(mode["mode_id"], MatchConfig.GameMode.CAPTURE_THE_FLAG)
	assert_eq((mode["scores"] as Array).size(), 2)
	assert_true(mode.has("winners"))


func test_client_mirrors_host_scores_for_display_only() -> void:
	_setup_world()
	Match.start_match(_ctf_config())
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var objective: ModeObjective = Match._territory._objective
	_fake_net = FakeNet.client(1)
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.bind_ports(SessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match))
	_net = node
	var wire: Dictionary = {
		"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [7.5, 2.0],
		"extra": {"beacons": 3, "held_0": 2, "held_1": 1}, "round_left": 61.0,
	}
	var shown: Array[Dictionary] = []
	Events.mode_state_changed.connect(func(s: Dictionary) -> void: shown.append(s))
	node.net_match_event(MatchNetScript.EVENT_MODE_STATE, [wire])
	assert_almost_eq(objective.scores()[0], 7.5, 0.0001)
	assert_almost_eq(objective.scores()[1], 2.0, 0.0001)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM, "a client never decides the outcome")
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(shown.size(), 1)
	assert_eq(HUD.mode_score_text(shown[0]), "1: 7.5  2: 2.0")

