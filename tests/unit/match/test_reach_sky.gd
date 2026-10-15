extends GutTest
## Reach the Sky (Bontago-22y.9): monotonic settled-height records, team aggregation, ties, timer and early win.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _tiny_map: MapDef
var _field: Field
var _registry: BlockRegistry
var _blocks_root: Node3D
var _net: MatchNetScript


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## slot_teams: team of each slot, e.g. [0, 1, 0, 1] = two teams of two.
func _objective(slot_teams: Array[int], teams: int, sum_members: bool = false, interval: float = 0.0) -> ReachSkyObjective:
	var objective: ReachSkyObjective = ReachSkyObjective.new(PackedInt32Array(slot_teams), sum_members, interval)
	objective.reset(teams)
	return objective


# --- Block height (registry sampling) -------------------------------------------------

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
	_registry.configure(_field, _tiny_map)
	Match.register_world(_field, _registry, _blocks_root)


func _place(shape_path: String, slot: int, at: Vector3) -> Block:
	var shape: BlockShape = load(shape_path)
	var block: Block = BlockFactory.build(shape, _tuning, slot)
	block.freeze = true
	_field.add_child(block)
	block.global_position = at
	Events.block_placed.emit(block, shape.id)
	return block


func test_a_multi_cube_block_reports_its_full_height_when_it_settles() -> void:
	_setup_world()
	_place("res://config/blocks/cube.tres", 0, Vector3(-4.0, 1.0, 0.0))
	var pillar: Block = _place("res://config/blocks/pillar.tres", 1, Vector3(4.0, 1.0, 0.0))
	var heard: Dictionary = {}
	_registry.block_settled.connect(func(slot: int, height: float) -> void: heard[slot] = height)
	_registry._physics_process(_tuning.sleep_settle_time + 0.1)
	assert_true(heard.has(0) and heard.has(1), "both blocks announce once they settle")
	assert_almost_eq(float(heard[1]), _registry.top_height_for_block(pillar), 0.0001, "same measure as the HUD tower")
	assert_almost_eq(float(heard[0]), _registry.max_height_for_slot(0), 0.0001)
	assert_gt(float(heard[1]), float(heard[0]), "a multi-cube block reaches higher than one cube from the same centre height")


func test_a_block_balanced_for_an_instant_does_not_count() -> void:
	_setup_world()
	var block: Block = _place("res://config/blocks/cube.tres", 0, Vector3(0.0, 1.0, 0.0))
	var heard: Array[float] = []
	_registry.block_settled.connect(func(_slot: int, height: float) -> void: heard.append(height))
	var objective: ReachSkyObjective = _objective([0] as Array[int], 1)
	_registry.block_settled.connect(objective.record_height)
	# Still for less than the settle time: nothing is announced...
	_registry._physics_process(_tuning.sleep_settle_time * 0.5)
	assert_eq(heard.size(), 0)
	# ...and one fast frame resets the accumulator, so it must start over.
	block.freeze = false
	block.linear_velocity = Vector3.DOWN * (_tuning.sleep_linear_threshold + 1.0)
	_registry._physics_process(_tuning.sleep_settle_time * 0.9)
	assert_eq(heard.size(), 0)
	assert_eq(objective.team_score(0), 0.0, "an unsettled block leaves the record alone")
	block.linear_velocity = Vector3.ZERO
	block.angular_velocity = Vector3.ZERO
	_registry._physics_process(_tuning.sleep_settle_time + 0.1)
	assert_eq(heard.size(), 1)
	assert_gt(objective.team_score(0), 0.0)


# --- Records ---------------------------------------------------------------------------

func test_ffa_highest_record_wins_at_the_timer() -> void:
	var objective: ReachSkyObjective = _objective([0, 1, 2] as Array[int], 3)
	objective.record_height(0, 3.0)
	objective.record_height(2, 8.0)
	objective.record_height(1, 5.0)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM, "classic all-goal victory is disabled")
	assert_eq(objective.on_round_timer_end(), 2)
	assert_eq(objective.results_fields()["winners"], "2")
	assert_true(objective.is_timed())
	assert_eq(objective.mode_id(), MatchConfig.GameMode.REACH_THE_SKY)


func test_a_tie_goes_to_whoever_reached_it_first() -> void:
	var objective: ReachSkyObjective = _objective([0, 1] as Array[int], 2)
	objective.record_height(1, 5.0)
	objective.record_height(0, 5.0)
	assert_eq(objective.on_round_timer_end(), 1)
	assert_eq(objective.results_fields()["winners"], "1", "a single winner, not shared")
	# A later, higher record by the other team overtakes outright.
	objective.record_height(0, 5.5)
	assert_eq(objective.on_round_timer_end(), 0)


func test_team_sum_mode() -> void:
	var objective: ReachSkyObjective = _objective([0, 1, 0, 1] as Array[int], 2, true)
	objective.record_height(0, 4.0)
	objective.record_height(2, 3.0)
	objective.record_height(1, 5.0)
	assert_almost_eq(objective.team_score(0), 7.0, 0.0001)
	assert_almost_eq(objective.team_score(1), 5.0, 0.0001)
	assert_eq(objective.on_round_timer_end(), 0)
	objective.record_height(2, 1.0)  # lower than that member's record: no change
	assert_almost_eq(objective.team_score(0), 7.0, 0.0001)
	objective.record_height(2, 3.5)
	assert_almost_eq(objective.team_score(0), 7.5, 0.0001)


# --- First to the target (Bontago-1pi.166) ---------------------------------------------

func _target_m() -> float:
	return (load("res://config/net/net_config.tres") as NetConfig).build_height_target_m


func test_first_team_to_settle_at_the_target_wins_at_once() -> void:
	var objective: ReachSkyObjective = ReachSkyObjective.new(PackedInt32Array([0, 1]), false, 0.0, _target_m())
	objective.reset(2)
	objective.record_height(1, _target_m() - 0.5)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM, "just under the target does not win")
	objective.record_height(0, _target_m() + 0.2)
	assert_eq(objective.winner(), 0)
	objective.record_height(1, _target_m() + 5.0)
	assert_eq(objective.winner(), 0, "the latched winner stays the first team")
	assert_eq(objective.results_fields()["winners"], "0")


# --- Config and Lobby ------------------------------------------------------------------

# --- Match integration, timer winner, replication -----------------------------------------

func _sky_config(teams_two: bool, sum: bool) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 4 if teams_two else 2
	config.team_mode = MatchConfig.TeamMode.TEAMS_2 if teams_two else MatchConfig.TeamMode.OFF
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 99
	config.sudden_death = false
	config.game_mode = MatchConfig.GameMode.REACH_THE_SKY
	config.round_timer_minutes = 2
	config.sky_team_sum = sum
	return config


func _tick(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds / step))):
		Match._process(step)


func test_a_sky_match_records_settled_heights_and_the_timer_decides() -> void:
	_setup_world()
	Match.start_match(_sky_config(true, true))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var objective: ModeObjective = Match._territory._objective
	assert_true(objective is ReachSkyObjective)
	_registry.block_settled.emit(0, 5.0)  # team 0
	_registry.block_settled.emit(2, 4.0)  # team 0
	_registry.block_settled.emit(1, 8.0)  # team 1
	assert_almost_eq(objective.team_score(0), 9.0, 0.0001)
	assert_almost_eq(objective.team_score(1), 8.0, 0.0001)
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	Match._lifecycle._match_timer_left = 0.02
	_tick(0.2)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(results.size(), 1)
	var mode: Dictionary = results[0]["mode"]
	assert_eq(mode["mode_id"], MatchConfig.GameMode.REACH_THE_SKY)
	assert_eq(mode["winners"], "0")
	assert_eq(int(results[0]["winner_id"]), 0)
	assert_eq(ResultsScreen.mode_outcome_text(results[0]), "Team 1: 9.0 m, Team 2: 8.0 m")

