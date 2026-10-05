extends GutTest
## Reach the Sky (Bontago-22y.9, owner decision Bontago-0tn): each player's
## record is the settled top of their own block, monotonic, aggregated per team
## as best-member or sum, ties to the first to reach it, highest record wins at
## the round timer. Objective tests are pure; registry, lifecycle, lobby and
## replication tests go through the real nodes like test_capture_flag.gd.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
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


## slot_teams: team of each slot, e.g. [0, 1, 0, 1] = two teams of two.
func _objective(slot_teams: Array[int], teams: int, sum_members: bool = false, interval: float = 0.0) -> ReachSkyObjective:
	var objective: ReachSkyObjective = ReachSkyObjective.new(PackedInt32Array(slot_teams), sum_members, interval)
	objective.reset(teams)
	return objective


# --- Block height (registry sampling) -------------------------------------------------

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

func test_the_record_never_drops_after_a_collapse() -> void:
	var objective: ReachSkyObjective = _objective([0, 1] as Array[int], 2)
	objective.record_height(0, 6.0)
	objective.record_height(0, 2.5)  # the tower fell and a block settled low
	assert_almost_eq(objective.record_of_slot(0), 6.0, 0.0001)
	assert_almost_eq(objective.team_score(0), 6.0, 0.0001)
	objective.record_height(0, 7.0)
	assert_almost_eq(objective.team_score(0), 7.0, 0.0001)


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


func test_nobody_building_anything_is_a_shared_result() -> void:
	var objective: ReachSkyObjective = _objective([0, 1] as Array[int], 2)
	assert_eq(objective.results_fields()["winners"], "0,1")


func test_team_best_member_mode() -> void:
	# Slots 0,2 are team 0; slots 1,3 are team 1.
	var objective: ReachSkyObjective = _objective([0, 1, 0, 1] as Array[int], 2, false)
	objective.record_height(0, 4.0)
	objective.record_height(2, 3.0)
	objective.record_height(1, 5.0)
	assert_almost_eq(objective.team_score(0), 4.0, 0.0001, "best member, not sum")
	assert_eq(objective.on_round_timer_end(), 1)


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


func test_team_tie_in_sum_mode_goes_to_the_team_that_completed_it_first() -> void:
	var objective: ReachSkyObjective = _objective([0, 1, 0, 1] as Array[int], 2, true)
	objective.record_height(0, 3.0)
	objective.record_height(1, 4.0)
	objective.record_height(1, 6.0)  # team 1 reaches 6 first
	objective.record_height(2, 3.0)  # team 0 reaches 6 afterwards
	assert_eq(objective.on_round_timer_end(), 1)


func test_replication_is_throttled_but_prompt_after_a_quiet_spell_and_at_the_end() -> void:
	var objective: ReachSkyObjective = _objective([0, 1] as Array[int], 2, false, 1.0)
	objective.consume_state_dirty()
	objective.record_height(0, 2.0)
	assert_true(objective.consume_state_dirty(), "first change after reset goes out at once")
	objective.record_height(1, 3.0)
	assert_false(objective.consume_state_dirty(), "a second change inside the interval waits")
	objective.update(null, 0.5)
	assert_false(objective.consume_state_dirty())
	objective.update(null, 0.6)
	assert_true(objective.consume_state_dirty(), "published once the interval passes")
	objective.update(null, 5.0)
	assert_false(objective.consume_state_dirty(), "no change, no traffic")
	objective.on_round_timer_end()
	assert_true(objective.consume_state_dirty(), "the final state is always sent")


func test_client_mirror_restores_scores_and_records() -> void:
	var host: ReachSkyObjective = _objective([0, 1, 0, 1] as Array[int], 2, true)
	host.record_height(0, 4.0)
	host.record_height(3, 2.0)
	var client: ReachSkyObjective = _objective([0, 1, 0, 1] as Array[int], 2, false)
	client.apply_mode_state(ModeObjective.validate_state(host.mode_state()))
	assert_almost_eq(client.team_score(0), 4.0, 0.0001)
	assert_almost_eq(client.record_of_slot(3), 2.0, 0.0001)
	assert_true(client.sums_members())
	assert_eq(client.winner(), ModeObjective.NO_TEAM)


func test_factory_builds_reach_the_sky_and_it_is_selectable() -> void:
	assert_true(MatchConfig.is_game_mode_selectable(MatchConfig.GameMode.REACH_THE_SKY))
	var objective: ModeObjective = ModeObjective.create(
		MatchConfig.GameMode.REACH_THE_SKY, PackedVector2Array(), 3.0, 2, 1.0, 1.0, PackedInt32Array([0, 1]), true
	)
	assert_true(objective is ReachSkyObjective)
	assert_true((objective as ReachSkyObjective).sums_members())


# --- Config and Lobby ------------------------------------------------------------------

func test_team_aggregation_round_trips_through_the_config() -> void:
	var config: MatchConfig = MatchConfig.new()
	assert_false(config.sky_team_sum, "default is best member")
	config.game_mode = MatchConfig.GameMode.REACH_THE_SKY
	config.sky_team_sum = true
	var copy: MatchConfig = MatchConfig.from_dict(config.to_dict())
	assert_eq(copy.game_mode, MatchConfig.GameMode.REACH_THE_SKY)
	assert_true(copy.sky_team_sum)
	# The host re-types whatever arrives over the wire.
	assert_false(MatchConfig.from_dict({"sky_team_sum": 0}).sky_team_sum)
	assert_true(MatchConfig.from_dict({"sky_team_sum": 1}).sky_team_sum)


func _make_lobby(is_host: bool) -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_lobby_toggle_is_visible_only_for_reach_the_sky_and_round_trips() -> void:
	var host: Lobby = _make_lobby(true)
	var mode: OptionButton = host.get_node("%GameModeOption")
	var toggle: CheckButton = host.get_node("%SkyTeamSumCheck")
	var column: Control = host.get_node("%SkyTeamCol")
	assert_false(column.visible, "hidden for classic")
	mode.select(MatchConfig.GameMode.CAPTURE_THE_FLAG)
	mode.item_selected.emit(MatchConfig.GameMode.CAPTURE_THE_FLAG)
	assert_false(column.visible, "hidden for other modes")
	mode.select(MatchConfig.GameMode.REACH_THE_SKY)
	mode.item_selected.emit(MatchConfig.GameMode.REACH_THE_SKY)
	assert_true(column.visible)
	assert_false(toggle.disabled)
	toggle.button_pressed = true
	var calls: Array[Dictionary] = (host.net_provider as FakeNet).set_lobby_data_calls
	var published: Dictionary = calls[-1]
	assert_eq(published["game_mode"], MatchConfig.GameMode.REACH_THE_SKY)
	assert_true(published["sky_team_sum"])
	var client: Lobby = _make_lobby(false)
	client._apply_data(published)
	assert_true((client.get_node("%SkyTeamSumCheck") as CheckButton).button_pressed)
	assert_true((client.get_node("%SkyTeamCol") as Control).visible)
	assert_true((client.get_node("%SkyTeamSumCheck") as CheckButton).disabled, "a client cannot edit it")
	assert_eq((client.net_provider as FakeNet).set_lobby_data_calls.size(), 0)


# --- Match integration, timer winner, replication -----------------------------------------

func _sky_config(teams_two: bool, sum: bool) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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
	assert_true((objective as ReachSkyObjective).sums_members(), "lobby toggle reaches the objective")
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


func test_client_mirrors_host_records_for_display_only() -> void:
	_setup_world()
	Match.start_match(_sky_config(false, false))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var objective: ModeObjective = Match._territory._objective
	_fake_net = FakeNet.client(1)
	Match.set_net_provider(_fake_net)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	var wire: Dictionary = {
		"mode_id": MatchConfig.GameMode.REACH_THE_SKY, "scores": [7.5, 2.0],
		"extra": {"sum": false, "rec_0": 7.5, "rec_1": 2.0}, "round_left": 61.0,
	}
	var shown: Array[Dictionary] = []
	Events.mode_state_changed.connect(func(s: Dictionary) -> void: shown.append(s))
	node.net_match_event(MatchNetScript.EVENT_MODE_STATE, [wire])
	assert_almost_eq(objective.team_score(0), 7.5, 0.0001)
	assert_almost_eq((objective as ReachSkyObjective).record_of_slot(1), 2.0, 0.0001)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM, "a client never decides the outcome")
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(shown.size(), 1)
	assert_eq(HUD.mode_score_text(shown[0]), "1: 7.5 m  2: 2.0 m   1:01")


## Bontago-1t5.3: the bot goal reports the owner's tallest settled block, none before one settles.
func test_bot_mode_goal_reports_the_tallest_settled_tower() -> void:
	_setup_world()
	Match.start_match(_sky_config(false, false))
	_tick(Match.COUNTDOWN_SECONDS + 0.1)
	var goal: BotModeGoal = Match.bot_mode_goal(0)
	assert_eq(goal.mode, MatchConfig.GameMode.REACH_THE_SKY)
	assert_false(goal.has_tower)
	_place("res://config/blocks/cube.tres", 0, Vector3(4.0, 0.5, 2.0))
	var ticks: int = int(ceil(_tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(ticks):
		await get_tree().physics_frame
	goal = Match.bot_mode_goal(0)
	assert_true(goal.has_tower)
	assert_almost_eq(goal.tower_origin.x, 4.0, 0.1)
	assert_gt(goal.tower_height, 0.0)
	assert_false(Match.bot_mode_goal(1).has_tower)
