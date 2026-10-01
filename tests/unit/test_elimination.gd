extends GutTest
## Elimination (Bontago-22y.8, owner decision Bontago-fim): the existing home
## triggers decide who is out, classic all-goal victory is off, the last team
## standing wins, a same-batch wipe-out goes to the larger territory share (ties
## share the win) and the optional round timer ranks survivors by share.
## Objective tests are pure; the match tests drive the real Match autoload like
## test_capture_flag.gd.

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
	Match.set_net_provider(null)
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

func test_objective_is_timed_replicated_and_starts_with_everyone_alive() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	assert_true(objective.is_timed())
	assert_true(objective.replicates_state())
	assert_eq(objective.mode_id(), MatchConfig.GameMode.ELIMINATION)
	assert_eq(objective.scores(), PackedFloat32Array([1.0, 1.0, 1.0]))
	assert_eq(objective.winner(), ModeObjective.NO_TEAM)
	objective.update(null, 1.0)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM, "the classic all-goal hold never ends it")


func test_ffa_last_player_standing_wins() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(1)
	assert_eq(objective.resolve(_shares([0.3, 0.0, 0.3])), ModeObjective.NO_TEAM, "two still stand")
	objective.slot_eliminated(0)
	assert_eq(objective.resolve(_shares([0.0, 0.0, 0.5])), 2)
	assert_eq(objective.winners(), PackedInt32Array([2]))
	assert_eq(objective.elimination_order(), PackedInt32Array([1, 0]))


func test_a_team_is_out_only_when_all_its_players_are() -> void:
	var objective: EliminationObjective = _objective([0, 1, 0, 1], 2)
	assert_eq(objective.scores(), PackedFloat32Array([2.0, 2.0]))
	objective.slot_eliminated(0)
	assert_eq(objective.resolve(_shares([0.2, 0.3])), ModeObjective.NO_TEAM, "teammate keeps the team alive")
	assert_eq(objective.surviving_teams(), PackedInt32Array([0, 1]))
	objective.slot_eliminated(2)
	assert_eq(objective.resolve(_shares([0.0, 0.5])), 1)


func test_simultaneous_loss_that_leaves_someone_lets_the_survivor_win() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(0)
	objective.slot_eliminated(1)
	assert_eq(objective.resolve(_shares([0.9, 0.9, 0.1])), 2, "the survivor wins whatever the leavers' shares were")


func test_simultaneous_loss_that_leaves_nobody_goes_to_the_larger_share() -> void:
	var objective: EliminationObjective = _objective([0, 1], 2)
	objective.slot_eliminated(0)
	objective.slot_eliminated(1)
	assert_eq(objective.resolve(_shares([0.2, 0.35])), 1)
	assert_eq(objective.winners(), PackedInt32Array([1]))


func test_simultaneous_loss_with_equal_shares_is_a_shared_win() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(1)
	objective.slot_eliminated(0)
	objective.slot_eliminated(2)
	var first: int = objective.resolve(_shares([0.25, 0.1, 0.25]))
	assert_eq(first, 0)
	assert_eq(objective.winners(), PackedInt32Array([0, 2]))
	assert_eq(objective.results_fields()["winners"], "0,2")


func test_only_teams_that_went_out_in_the_same_batch_compete() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(0)
	assert_eq(objective.resolve(_shares([0.9, 0.1, 0.1])), ModeObjective.NO_TEAM)
	objective.slot_eliminated(1)
	objective.slot_eliminated(2)
	assert_eq(objective.resolve(_shares([0.9, 0.1, 0.3])), 2, "slot 0 went out earlier and cannot win on its old share")


func test_timer_expiry_ranks_survivors_by_share() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(2)
	objective.resolve(_shares([0.2, 0.3, 0.6]))
	assert_eq(objective.on_round_timer_end(), 1, "the eliminated team's big share does not count")
	assert_eq(objective.winners(), PackedInt32Array([1]))


func test_timer_expiry_with_equal_shares_is_a_shared_win() -> void:
	var objective: EliminationObjective = _objective([0, 1, 2], 3)
	objective.slot_eliminated(2)
	objective.resolve(_shares([0.3, 0.3, 0.0]))
	objective.on_round_timer_end()
	assert_eq(objective.winners(), PackedInt32Array([0, 1]))
	assert_eq(objective.results_fields()["order"], "2")


func test_elimination_is_idempotent_and_ignores_unknown_slots() -> void:
	var objective: EliminationObjective = _objective([0, 1], 2)
	objective.slot_eliminated(0)
	objective.slot_eliminated(0)
	objective.slot_eliminated(7)
	objective.slot_eliminated(-1)
	assert_eq(objective.scores(), PackedFloat32Array([0.0, 1.0]))
	assert_eq(objective.elimination_order(), PackedInt32Array([0]))


func test_state_round_trips_through_the_client_mirror() -> void:
	var host: EliminationObjective = _objective([0, 1, 0, 1], 2)
	host.slot_eliminated(2)
	var wire: Dictionary = ModeObjective.validate_state(host.mode_state())
	assert_false(wire.is_empty(), "the state passes strict wire validation")
	var client: EliminationObjective = _objective([0, 1, 0, 1], 2)
	client.apply_mode_state(wire)
	assert_eq(client.scores(), PackedFloat32Array([1.0, 2.0]))
	assert_true(client.is_slot_out(2))
	assert_false(client.is_slot_out(0))
	assert_eq(client.winner(), ModeObjective.NO_TEAM, "a client never decides")


func test_factory_selectable_and_timer_off_is_elimination_only() -> void:
	var objective: ModeObjective = ModeObjective.create(
		MatchConfig.GameMode.ELIMINATION, PackedVector2Array(), 1.0, 2, 1.0, 1.0, PackedInt32Array([0, 1])
	)
	assert_true(objective is EliminationObjective)
	assert_true(MatchConfig.is_game_mode_selectable(MatchConfig.GameMode.ELIMINATION))
	var config: MatchConfig = MatchConfig.new()
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.round_timer_minutes = 0
	config.sanitize()
	assert_eq(config.round_timer_minutes, 0)
	assert_eq(MatchConfig.from_dict(config.to_dict()).round_timer_minutes, 0)
	for other: int in [MatchConfig.GameMode.CLASSIC, MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.GameMode.REACH_THE_SKY]:
		assert_eq(MatchConfig.from_dict({"game_mode": other, "round_timer_minutes": 0}).round_timer_minutes,
			MatchConfig.ROUND_TIMER_MIN_MINUTES, "other modes still need a timer to end")


func test_hud_and_results_text() -> void:
	var state: Dictionary = {"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [2.0, 0.0, 1.0], "round_left": 65.0}
	assert_eq(HUD.mode_score_text(state), "1: 2 alive  2: out  3: alive   1:05")
	var results: Dictionary = {
		"winner_id": 2, "winner_kind": MatchStats.WINNER_KIND_SLOT,
		"mode": {"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [0.0, 0.0, 1.0], "winners": "2", "order": "1,0"},
	}
	var text: String = ResultsScreen.mode_outcome_text(results)
	assert_string_contains(text, "Player 3: alive")
	assert_string_contains(text, "Player 1: out")
	assert_string_contains(text, "Out, first to last: Player 2, 1")
	assert_eq(ResultsScreen.shared_winners_text(results), "")


# --- Match integration -----------------------------------------------------------------

func _setup_world() -> void:
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


func _config(players: int, teams: MatchConfig.TeamMode = MatchConfig.TeamMode.OFF,
		mode: MatchConfig.GameMode = MatchConfig.GameMode.ELIMINATION, minutes: int = 0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func _lose_homes(slots: Array[int]) -> void:
	var opened: PackedInt32Array = PackedInt32Array()
	for slot: int in slots:
		opened.append(_home_cell(slot))
	Match._check_home_flags(opened)


func test_ffa_match_runs_on_until_one_player_is_left() -> void:
	_start(3)
	assert_true(Match._territory._objective is EliminationObjective)
	assert_eq(Match._lifecycle.match_timer_left(), 0.0, "round timer off arms nothing")
	var won: Array[int] = []
	Events.match_won.connect(func(t: int) -> void: won.append(t))
	_lose_homes([1])
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_false(Match.slot(1).home_flag_alive)
	_tick(120.0)
	assert_eq(Match.state(), Match.State.PLAYING, "no timer: it never times out")
	_lose_homes([0])
	assert_eq(Match.state(), Match.State.END)
	assert_eq(won, [2] as Array[int])


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


func test_simultaneous_home_loss_that_leaves_one_player() -> void:
	_start(3)
	var won: Array[int] = []
	Events.match_won.connect(func(t: int) -> void: won.append(t))
	_lose_homes([0, 1])
	assert_eq(Match.state(), Match.State.END)
	assert_eq(won, [2] as Array[int], "the survivor wins even though the first loss was processed first")


func test_simultaneous_home_loss_that_leaves_nobody_still_names_a_winner() -> void:
	_start(2)
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	_lose_homes([0, 1])
	assert_eq(Match.state(), Match.State.END, "both out in one tick must not leave a dead match running")
	assert_eq(results.size(), 1)
	var mode: Dictionary = results[0]["mode"]
	assert_eq(mode["mode_id"], MatchConfig.GameMode.ELIMINATION)
	assert_false(String(mode["winners"]).is_empty())
	assert_eq(String(mode["order"]).split(",").size(), 2)


func test_round_timer_expiry_ranks_the_survivors() -> void:
	_start(3, MatchConfig.TeamMode.OFF, MatchConfig.GameMode.ELIMINATION, 2)
	assert_almost_eq(Match._lifecycle.match_timer_left(), 120.0, 0.5)
	_lose_homes([2])
	var results: Array[Dictionary] = []
	Events.match_results_ready.connect(func(r: Dictionary) -> void: results.append(r))
	Match._lifecycle._match_timer_left = 0.02
	_tick(0.2)
	assert_eq(Match.state(), Match.State.END)
	var winners: PackedStringArray = String((results[0]["mode"] as Dictionary)["winners"]).split(",")
	assert_false(winners.has("2"), "the eliminated player cannot win on the timer")
	assert_eq((results[0]["mode"] as Dictionary)["order"], "2")


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
	Match.set_net_provider(_fake_net)
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
	Match.set_net_provider(_fake_net)
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


func test_classic_elimination_and_last_team_standing_are_unchanged() -> void:
	_start(3, MatchConfig.TeamMode.OFF, MatchConfig.GameMode.CLASSIC, 1)
	assert_true(Match._territory._objective is ClassicObjective)
	_lose_homes([0, 1])
	assert_false(Match.slot(0).home_flag_alive)
	assert_eq(Match.state(), Match.State.END, "classic still ends at the last team standing")
	assert_eq(Match._territory.winner_team(), -1, "classic reports its winner through match_won, not an objective latch")
