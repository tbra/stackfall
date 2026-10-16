extends GutTest
## Elimination mode: home loss decides who is out, the last team standing wins, a same-batch
## wipe-out goes to the larger territory share, plus its replication and bot/claim behaviour.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _tiny_map: MapDef
var _field: Field
var _registry: BlockRegistry
var _blocks_root: Node3D
var _fake_net: FakeNet
var _net: MatchNetScript


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _objective(slot_teams: Array[int], teams: int) -> EliminationObjective:
	var objective: EliminationObjective = EliminationObjective.new(PackedInt32Array(slot_teams))
	objective.reset(teams)
	return objective


func _shares(values: Array[float]) -> PackedFloat32Array:
	return PackedFloat32Array(values)


# --- Pure objective ---------------------------------------------------------------------

func test_ffa_last_player_standing_wins() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(1)
	assert_eq(objective.resolve(_shares([0.3, 0.0, 0.3])), ModeObjective.NO_TEAM, "two still stand")
	objective.slot_eliminated(0)
	assert_eq(objective.resolve(_shares([0.0, 0.0, 0.5])), 2)
	assert_eq(objective.results_fields()["winners"], "2")


func test_a_team_is_out_only_when_all_its_players_are() -> void:
	var objective: EliminationObjective = _objective([0, 1, 0, 1], 2)
	assert_eq(objective.scores(), PackedFloat32Array([2.0, 2.0]))
	objective.slot_eliminated(0)
	assert_eq(objective.resolve(_shares([0.2, 0.3])), ModeObjective.NO_TEAM, "teammate keeps the team alive")
	assert_eq(objective.surviving_teams(), PackedInt32Array([0, 1]))
	objective.slot_eliminated(2)
	assert_eq(objective.resolve(_shares([0.0, 0.5])), 1)


func test_simultaneous_loss_that_leaves_nobody_goes_to_the_larger_share() -> void:
	var objective: EliminationObjective = _objective([0, 1], 2)
	objective.slot_eliminated(0)
	objective.slot_eliminated(1)
	assert_eq(objective.resolve(_shares([0.2, 0.35])), 1)
	assert_eq(objective.results_fields()["winners"], "1")


func test_timer_expiry_ranks_survivors_by_share() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(2)
	objective.resolve(_shares([0.2, 0.3, 0.6]))
	assert_eq(objective.on_round_timer_end(), 1, "the eliminated team's big share does not count")
	assert_eq(objective.results_fields()["winners"], "1")


# --- Match integration -----------------------------------------------------------------

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


func _config(players: int, teams: MatchConfig.TeamMode = MatchConfig.TeamMode.OFF,
		mode: MatchConfig.GameMode = MatchConfig.GameMode.ELIMINATION, minutes: int = 0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = players
	config.team_mode = teams
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 99
	config.sudden_death = false
	config.game_mode = mode
	config.round_timer_minutes = minutes
	return config


func _tick(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds / step))):
		Match._process(step)


func _start(players: int, teams: MatchConfig.TeamMode = MatchConfig.TeamMode.OFF,
		mode: MatchConfig.GameMode = MatchConfig.GameMode.ELIMINATION, minutes: int = 0) -> void:
	_setup_world()
	Match.start_match(_config(players, teams, mode, minutes))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)


## The cell under a slot's home flag: opening it is the existing hole trigger.
func _home_cell(slot: int) -> int:
	var coords: Vector2i = Match.cell_grid().world_to_cell(Match.slot(slot).home_position)
	return Match.cell_grid().cell_index(coords.x, coords.y)


## in Elimination a home is knocked out only after the claim
## time, so this opens the holes and lets the whole claim time pass in one step.
func _lose_homes(slots: Array[int]) -> void:
	var opened: PackedInt32Array = PackedInt32Array()
	for slot: int in slots:
		opened.append(_home_cell(slot))
	if Match._territory._objective is EliminationObjective:
		_open_holes(slots)
		Match._territory._tick_home_claims(Match._territory_tuning.capture_hold)
		return
	Match._territory._check_home_flags(opened)


func _open_holes(slots: Array[int], permanent: bool = true) -> void:
	var grid: CellGrid = Match.cell_grid()
	for slot: int in slots:
		var coords: Vector2i = grid.world_to_cell(Match.slot(slot).home_position)
		Match._territory._raster.force_hole_cell(coords.x, coords.y, 1.0, permanent)


func test_all_goal_hold_does_not_win_in_elimination() -> void:
	_start(2)
	assert_null(Match._territory._win_checker)
	_tick(30.0)
	assert_eq(Match.state(), Match.State.PLAYING)


func test_teams_match_ends_when_a_whole_team_is_gone() -> void:
	_start(4, MatchConfig.TeamMode.TEAMS_2)
	_lose_homes([0])
	assert_eq(Match.state(), Match.State.PLAYING, "slot 2 still holds team 0 up")
	_lose_homes([2])
	assert_eq(Match.state(), Match.State.END)
	assert_eq(Match._territory.winner_team(), 1)


func test_disconnect_grace_elimination_goes_through_the_objective() -> void:
	_start(2)
	Match._lifecycle._disconnect_grace_left[1] = 0.01
	Match._lifecycle._tick_disconnect_grace(0.1)
	assert_false(Match.slot(1).home_flag_alive)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(Match._territory.winner_team(), 0)


func test_reconnecting_keeps_the_eliminated_and_alive_state() -> void:
	_start(3)
	_lose_homes([1])
	Match._lifecycle.on_peer_rejoined(1)
	Match._lifecycle.on_peer_rejoined(0)
	assert_false(Match.slot(1).home_flag_alive, "a rejoin never revives an eliminated slot")
	assert_true(Match.slot(0).home_flag_alive)
	var snapshot: Dictionary = Match.mode_state_snapshot()
	assert_eq(snapshot["mode_id"], MatchConfig.GameMode.ELIMINATION)
	assert_eq(int((snapshot["extra"] as Dictionary)["out_mask"]), 2)
	# A (re)joining client mirrors the same state from the snapshot.
	Match.abort_match()
	_setup_world()
	_fake_net = FakeNet.client(0)
	Match._net_provider = _fake_net
	Match.start_match(_config(3))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	node.net_match_event(MatchNetScript.EVENT_MODE_STATE, [snapshot])
	assert_false(Match.slot(1).home_flag_alive)
	assert_true(Match.slot(0).home_flag_alive)
	assert_true(Match.slot(2).home_flag_alive)
	assert_ne(Match.state(), Match.State.END, "display only: no outcome from the mirror")


func test_client_mirrors_host_state_for_display_only() -> void:
	_start(3)
	_fake_net = FakeNet.client(1)
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	var wire: Dictionary = {
		"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [1.0, 0.0, 1.0],
		"extra": {"out_mask": 2}, "round_left": 0.0,
	}
	var shown: Array[Dictionary] = []
	Events.mode_state_changed.connect(func(s: Dictionary) -> void: shown.append(s))
	node.net_match_event(MatchNetScript.EVENT_MODE_STATE, [wire])
	var objective: ModeObjective = Match._territory._objective
	assert_eq(objective.team_score(1), 0.0)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM)
	assert_false(Match.slot(1).home_flag_alive)
	assert_ne(Match.state(), Match.State.END)
	assert_eq(HUD.mode_score_text(shown[0]), "1: alive  2: out  3: alive")


# --- Claim time --------------------------------------------------------

func test_claim_progress_resets_on_loss_and_completes_at_claim_time() -> void:
	var objective: EliminationObjective = EliminationObjective.new(PackedInt32Array([0, 1]), 10.0)
	objective.reset(2)
	var pressure: Dictionary = {1: 0}
	assert_eq(objective.step_claims(pressure, 4.0).size(), 0)
	assert_almost_eq(objective.capture_progress(), 0.4, 0.001)
	assert_eq(objective.capturing_team(), 0)
	assert_eq(objective.step_claims({}, 1.0).size(), 0, "control lost")
	assert_eq(objective.capture_progress(), 0.0, "progress resets like a goal claim")
	assert_eq(objective.capturing_team(), ModeObjective.NO_TEAM)
	objective.step_claims(pressure, 6.0)
	assert_eq(objective.step_claims({1: 1}, 5.0).size(), 0, "a different attacker restarts the claim")
	assert_almost_eq(objective.capture_progress(), 0.5, 0.001)
	var done: PackedInt32Array = objective.step_claims({1: 1}, 5.0)
	assert_eq(done, PackedInt32Array([1]), "knocked out exactly at the claim time")
	assert_eq(objective.eliminator_team(1), 1)
	assert_eq(objective.capture_progress(), 0.0)


func test_eliminated_player_holds_nothing_and_cannot_drop() -> void:
	_start(3)
	assert_not_null(Match.held_shape(1))
	assert_not_null(Match.next_shape(1))
	_lose_homes([1])
	assert_null(Match.held_shape(1), "held block cleared")
	assert_null(Match.next_shape(1), "next block cleared")
	assert_eq(Match.eliminated_by(1), -1, "no single attacker for a hole: fallback text")
	assert_ne(Match._placement._intent_gate(1, -1, MatchPlacement.IntentKind.PLACE), &"", "cannot drop")

