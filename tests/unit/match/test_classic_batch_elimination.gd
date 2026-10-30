extends "res://tests/unit/match/match_world_test.gd"
## Home losses that land in one batch (one territory step, one disconnect-grace tick) are judged
## together: the larger territory share among the teams that just went out wins, never the team
## whose slot happened to be eliminated last; a team that is still alive always beats them; a team
## lost in an earlier step never wins a later wipe-out. Driven through the real match flow
## (MatchLifecycle.eliminate_slots, the territory home triggers, Match._process disconnect grace).

const TUNING: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
const NET: NetConfig = preload("res://config/net/net_config.tres")
const NO_TEAM: int = ModeObjective.NO_TEAM
const PAD_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const PAD_PHYSICS: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
## Padding blocks ring the home at this fraction of the field radius, floating this many radii up.
const PAD_RINGS_RADII: Array[float] = [0.25, 0.8]
const PAD_HEIGHT_RADII: float = 2.0
const PAD_BLOCKS: int = 6
const HOLD_SLACK_S: float = 0.5

var _tuning: TerritoryTuning = TUNING
var _saved_hold: float
var _won: Array[int] = []
var _events: Array[String] = []
var _eliminated: Array[int] = []
var _results: Array[Dictionary] = []


func before_each() -> void:
	super.before_each()
	_saved_hold = TUNING.capture_hold
	_won.clear()
	_events.clear()
	_eliminated.clear()
	_results.clear()
	Events.match_won.connect(_on_won)
	Events.match_results_ready.connect(_on_results)
	Events.player_eliminated.connect(_on_eliminated)


func after_each() -> void:
	_tuning.capture_hold = _saved_hold
	Events.match_won.disconnect(_on_won)
	Events.match_results_ready.disconnect(_on_results)
	Events.player_eliminated.disconnect(_on_eliminated)
	super.after_each()


func _on_won(team: int) -> void:
	_won.append(team)
	_events.append("won")


func _on_results(payload: Dictionary) -> void:
	_results.append(payload)
	_events.append("results")


func _on_eliminated(slot_id: int, _team_id: int) -> void:
	_eliminated.append(slot_id)


func _start(players: int, mode: MatchConfig.GameMode = MatchConfig.GameMode.CLASSIC,
		teams: MatchConfig.TeamMode = MatchConfig.TeamMode.OFF,
		holes: MatchConfig.HoleMode = MatchConfig.HoleMode.TEMPORARY) -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = players
	config.team_mode = teams
	config.game_mode = mode
	config.hole_mode = holes
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.sudden_death = false
	config.match_timer_minutes = 0
	config.round_timer_minutes = 0
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")


## Repaints the live raster from every seat's home circle (so each team owns its home area) plus,
## per team in `bonus`, a connected circle that many metres wider, so that team's share is larger.
func _paint(bonus: Dictionary = {}) -> void:
	var circles: Array[InfluenceCircle] = []
	for slot_id: int in range(Match.slot_count()):
		var seat: PlayerSlot = Match.slot(slot_id)
		circles.append(InfluenceCircle.for_home(seat.home_position, seat.team_id, slot_id, TUNING))
		if bonus.has(seat.team_id):
			var extra: float = float(bonus[seat.team_id])
			circles.append(InfluenceCircle.new(seat.home_position, TUNING.home_radius + extra, seat.team_id, slot_id, false, 900 + slot_id))
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(circles, TerritorySolver.new(TUNING).solve(circles), false)
	raster.adopt_fill(raster, 1.0 / TUNING.solve_hz, false, false)


## Nobody owns anything: every share is exactly equal.
func _paint_nothing() -> void:
	var raster: TerritoryRaster = Match.raster()
	var none: Array[InfluenceCircle] = []
	raster.fill_ownership(none, TerritorySolver.new(TUNING).solve(none), false)
	raster.adopt_fill(raster, 1.0 / TUNING.solve_hz, false, false)


func _slots(ids: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(ids)


func _home_index(slot_id: int) -> int:
	var coords: Vector2i = Match.cell_grid().world_to_cell(Match.slot(slot_id).home_position)
	return Match.cell_grid().cell_index(coords.x, coords.y)


## The real home-loss trigger of the hole modes: rivals' blocks cover these homes until the contest
## ages into a hole under each (Elimination: until the claim hold completes too).
func _open_homes(ids: Array[int]) -> void:
	await TerritoryStage.lose_homes(ids, _blocks_root)


## `count` extra frozen blocks of `team`'s first seat floating around its home, so its territory
## (and so its share once the homes are contested) is the larger one.
func _pad(team: int, count: int) -> void:
	var seat: int = 0
	while Match.team_of(seat) != team:
		seat += 1
	var radius: float = Match.config.map_def().field_radius
	for ring: float in PAD_RINGS_RADII:
		for i: int in range(count):
			var angle: float = TAU * float(i) / float(count)
			var at: Vector2 = Match.slot(seat).home_position + Vector2.from_angle(angle) * ring * radius
			_float_block(seat, at, radius)


func _float_block(seat: int, at: Vector2, radius: float) -> void:
	var block: Block = BlockFactory.build(PAD_SHAPE, PAD_PHYSICS, seat)
	block.position = Match.field().to_global(Vector3(at.x, PAD_HEIGHT_RADII * radius, at.y))
	_blocks_root.add_child(block)
	block.freeze = true
	Events.block_placed.emit(block, PAD_SHAPE.id)


func _share(team: int) -> float:
	return Match.territory_share(team)


# --- Two teams, both homes lost in one batch ------------------------------------

func test_larger_share_wins_when_both_homes_are_lost_in_one_batch() -> void:
	_start(2)
	_paint({0: 6.0})
	assert_gt(_share(0), _share(1), "fixture: team 0 holds more territory")

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [0] as Array[int], "team 0 wins on share although slot 1 was eliminated last")


func test_larger_share_wins_when_it_belongs_to_the_higher_team_id() -> void:
	_start(2)
	_paint({1: 6.0})
	assert_gt(_share(1), _share(0))

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(_won, [1] as Array[int])


func test_the_order_of_the_batch_does_not_pick_the_winner() -> void:
	_start(2)
	_paint({0: 6.0})

	Match._lifecycle.eliminate_slots(_slots([1, 0]))

	assert_eq(_won, [0] as Array[int], "the share decides, not which slot was listed last")


func test_home_trigger_with_two_homes_opened_at_once_ends_with_the_larger_share() -> void:
	# The real hole-mode trigger, for both directions of share.
	_start(2)
	_pad(0, PAD_BLOCKS)
	await _open_homes([0, 1])
	assert_gt(_share(0), _share(1), "the staged contest left team 0 the larger share")
	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [0] as Array[int], "never the slot-order winner (team 1)")


func test_home_trigger_with_two_homes_opened_at_once_larger_share_second_team() -> void:
	_start(2)
	_pad(1, PAD_BLOCKS)
	await _open_homes([0, 1])
	assert_gt(_share(1), _share(0), "the staged contest left team 1 the larger share")
	assert_eq(_won, [1] as Array[int])


func test_equal_shares_go_to_the_lowest_team_id() -> void:
	_start(2)
	_paint_nothing()
	assert_eq(_share(0), _share(1), "fixture: an exact tie")

	Match._lifecycle.eliminate_slots(_slots([1, 0]))

	assert_eq(_won, [0] as Array[int])


func test_the_match_is_announced_once_with_one_winner() -> void:
	_start(2)
	_paint({1: 6.0})

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(_won.size(), 1, "one match_won for the whole batch")
	assert_eq(_results.size(), 1, "one results payload for the whole batch")
	if _results.is_empty():
		return
	assert_eq(int(_results[0][ResultsPayload.KEY_WINNER_ID]), 1)


func test_match_won_comes_before_match_results_ready() -> void:
	_start(2)
	_paint({0: 6.0})

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(_events, ["won", "results"] as Array[String])


func test_classic_results_carry_no_mode_block() -> void:
	_start(2)
	_paint({0: 6.0})

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(_results.size(), 1, "a results payload was built")
	if _results.is_empty():
		return
	assert_false(_results[0].has(ResultsPayload.KEY_MODE), "the classic payload is unchanged")


func test_every_slot_of_the_batch_is_announced_in_id_order() -> void:
	_start(3)
	_paint()

	Match._lifecycle.eliminate_slots(_slots([0, 2]))

	assert_eq(_eliminated, [0, 2] as Array[int])
	assert_false(Match.slot(0).home_flag_alive)
	assert_false(Match.slot(2).home_flag_alive)
	assert_true(Match.slot(1).home_flag_alive)


func test_home_trigger_announces_each_lost_slot_in_id_order() -> void:
	_start(3)
	await _open_homes([2, 0])
	assert_eq(_eliminated, [0, 2] as Array[int])


# --- Three teams ---------------------------------------------------------------

func test_a_surviving_team_wins_when_two_others_are_lost_together() -> void:
	_start(3)
	_paint({0: 6.0, 1: 4.0})
	assert_lt(_share(2), _share(0), "fixture: the survivor has the smallest share")

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(_won, [2] as Array[int], "the team still standing wins whatever the shares")


func test_home_trigger_with_two_of_three_homes_lost_ends_with_the_third() -> void:
	_start(3)
	_pad(0, PAD_BLOCKS)
	await _open_homes([0, 1])
	assert_eq(_won, [2] as Array[int])


func test_one_of_three_lost_decides_nothing() -> void:
	_start(3)
	_paint({0: 6.0})

	Match._lifecycle.eliminate_slots(_slots([0]))

	assert_eq(Match.state(), Match.State.PLAYING)
	assert_true(_won.is_empty())


func test_an_empty_batch_judges_but_decides_nothing_with_several_teams_alive() -> void:
	_start(3)
	_paint()

	Match._lifecycle.eliminate_slots(PackedInt32Array())

	assert_eq(Match.state(), Match.State.PLAYING)
	assert_true(_won.is_empty())
	assert_true(_eliminated.is_empty())


func test_a_team_lost_in_an_earlier_step_never_wins_a_later_wipe_out() -> void:
	_start(3)
	_paint({0: 8.0, 1: 4.0})
	Match._lifecycle.eliminate_slots(_slots([0]))
	assert_eq(Match.state(), Match.State.PLAYING)
	# Team 0 keeps the largest share on the board; it is already out.
	_paint({0: 8.0, 1: 4.0})
	assert_gt(_share(0), _share(1))
	assert_gt(_share(1), _share(2))

	Match._lifecycle.eliminate_slots(_slots([1, 2]))

	assert_eq(_won, [1] as Array[int], "the larger share of the teams lost now, not team 0's")


func test_a_team_lost_earlier_does_not_win_the_tie_either() -> void:
	_start(3)
	_paint()
	Match._lifecycle.eliminate_slots(_slots([0]))
	_paint_nothing()

	Match._lifecycle.eliminate_slots(_slots([1, 2]))

	assert_eq(_won, [1] as Array[int], "lowest id among the teams of this batch")


func test_teams_mode_a_team_goes_out_only_when_its_last_slot_does() -> void:
	_start(4, MatchConfig.GameMode.CLASSIC, MatchConfig.TeamMode.TEAMS_2)
	_paint()
	var team_of_zero: int = Match.team_of(0)

	Match._lifecycle.eliminate_slots(_slots([0]))
	assert_eq(Match.state(), Match.State.PLAYING, "its teammate still holds a home")
	var teammate: int = -1
	for slot_id: int in range(1, 4):
		if Match.team_of(slot_id) == team_of_zero:
			teammate = slot_id
	assert_ne(teammate, -1, "fixture: slot 0 has a teammate")
	Match._lifecycle.eliminate_slots(_slots([teammate]))

	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [1 - team_of_zero] as Array[int])


# --- A capture latched in the same step as a wipe-out -------------------------------

## A capture hold of one and a half solve steps (set before the match starts: the objective takes it then).
func _short_hold() -> void:
	_tuning.capture_hold = 1.5 / TUNING.solve_hz


## Team `team` holds every goal with all but one solve step of the hold done (needs _short_hold before
## _start): the next solve step latches its capture, so a home lost in that step is judged with it.
func _almost_captured(team: int) -> void:
	await TerritoryStage.hold_goals(team, _blocks_root)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the hold has not completed yet")


func test_a_capture_beats_the_share_rule_in_a_same_step_wipe_out() -> void:
	_short_hold()
	_start(2, MatchConfig.GameMode.CLASSIC, MatchConfig.TeamMode.OFF, MatchConfig.HoleMode.OFF)
	_pad(0, PAD_BLOCKS * 2)
	await _almost_captured(1)
	assert_gt(_share(0), _share(1), "fixture: the share rule would pick team 0")
	await _open_homes([0, 1])
	assert_eq(_won, [1] as Array[int], "the capturing team wins, not the larger share")


func test_the_team_left_standing_beats_a_capture_in_the_same_step() -> void:
	_short_hold()
	_start(3, MatchConfig.GameMode.CLASSIC, MatchConfig.TeamMode.OFF, MatchConfig.HoleMode.OFF)
	await _almost_captured(0)
	await _open_homes([0, 1])
	assert_eq(_won, [2] as Array[int])


func test_a_capture_with_teams_still_alive_wins_after_an_empty_batch() -> void:
	_short_hold()
	_start(3, MatchConfig.GameMode.CLASSIC, MatchConfig.TeamMode.OFF, MatchConfig.HoleMode.OFF)
	await _almost_captured(1)
	await _open_homes([2])
	assert_eq(_won, [1] as Array[int], "no team stands alone, so the capturing team wins")


# --- Eliminated-by survives batching ---------------------------------------------

func test_each_slot_of_a_batch_keeps_its_own_attacker() -> void:
	_start(4)
	_paint()

	Match._lifecycle.eliminate_slots(_slots([0, 1]), {0: 2, 1: 3})

	assert_eq(Match.eliminated_by(0), 2)
	assert_eq(Match.eliminated_by(1), 3)
	assert_eq(Match.eliminated_by(2), -1, "a slot that is still alive has none")


func test_a_slot_without_an_attacker_entry_reports_none() -> void:
	_start(4)
	_paint()

	Match._lifecycle.eliminate_slots(_slots([0, 1]), {1: 3})

	assert_eq(Match.eliminated_by(0), -1)
	assert_eq(Match.eliminated_by(1), 3)


func test_an_attacker_of_minus_one_means_none() -> void:
	_start(4)
	_paint()

	Match._lifecycle.eliminate_slots(_slots([0]), {0: -1})

	assert_eq(Match.eliminated_by(0), -1)


# --- Disconnect grace -------------------------------------------------------------

func _expire_graces() -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(NET.disconnect_grace / step)) + 2):
		Match._process(step)


func test_two_graces_expiring_together_end_with_the_larger_share() -> void:
	_start(2)
	_paint({0: 6.0})
	assert_gt(_share(0), _share(1))
	Match.on_peer_left(0)
	Match.on_peer_left(1)

	_expire_graces()

	assert_eq(Match.state(), Match.State.END)
	assert_false(Match.slot(0).home_flag_alive)
	assert_false(Match.slot(1).home_flag_alive)
	assert_eq(_won, [0] as Array[int], "not the peer whose slot id came last")


func test_two_graces_expiring_together_second_team_larger() -> void:
	_start(2)
	_paint({1: 6.0})
	Match.on_peer_left(0)
	Match.on_peer_left(1)

	_expire_graces()

	assert_eq(_won, [1] as Array[int])


func test_two_graces_of_three_expiring_together_leave_the_third_the_winner() -> void:
	_start(3)
	_paint({0: 6.0, 1: 4.0})
	Match.on_peer_left(0)
	Match.on_peer_left(1)

	_expire_graces()

	assert_eq(_won, [2] as Array[int])
	assert_eq(_eliminated, [0, 1] as Array[int], "announced in slot id order")


func test_a_single_grace_expiry_in_a_two_player_match_hands_the_win_over() -> void:
	_start(2)
	Match.on_peer_left(1)

	_expire_graces()

	assert_eq(_won, [0] as Array[int])
	assert_eq(_eliminated, [1] as Array[int])


# --- Elimination mode keeps its own outcome ----------------------------------------

func _lose_homes_by_claim(ids: Array[int]) -> void:
	await TerritoryStage.lose_homes(ids, _blocks_root)


func test_elimination_two_claims_completing_together_end_with_the_larger_share() -> void:
	_start(2, MatchConfig.GameMode.ELIMINATION)
	_pad(1, PAD_BLOCKS)
	await _lose_homes_by_claim([0, 1])

	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [1] as Array[int])
	assert_eq(_eliminated, [0, 1] as Array[int])
	assert_eq(_events, ["won", "results"] as Array[String])


func test_elimination_equal_shares_are_a_shared_win() -> void:
	_start(2, MatchConfig.GameMode.ELIMINATION, MatchConfig.TeamMode.OFF, MatchConfig.HoleMode.OFF)
	TerritoryStage.tick_solve()
	_paint_nothing()
	assert_eq(_share(0), _share(1), "fixture: an exact tie")
	TerritoryStage.tick(TUNING.capture_hold + HOLD_SLACK_S)

	assert_eq(_won, [0] as Array[int], "the lowest team id is announced")
	assert_eq(_results.size(), 1, "a results payload was built")
	if _results.is_empty():
		return
	var mode: Dictionary = _results[0][ResultsPayload.KEY_MODE] as Dictionary
	assert_eq(mode["winners"], "0,1", "both teams share the win")
	assert_eq(mode["order"], "0,1")


func test_elimination_third_team_alive_wins_over_two_lost_together() -> void:
	_start(3, MatchConfig.GameMode.ELIMINATION)
	await _lose_homes_by_claim([0, 1])

	assert_eq(_won, [2] as Array[int])
	assert_eq(_results.size(), 1, "a results payload was built")
	if _results.is_empty():
		return
	var mode: Dictionary = _results[0][ResultsPayload.KEY_MODE] as Dictionary
	assert_eq(mode["winners"], "2")


func test_elimination_a_claim_short_of_the_hold_time_eliminates_nobody() -> void:
	_start(2, MatchConfig.GameMode.ELIMINATION, MatchConfig.TeamMode.OFF, MatchConfig.HoleMode.OFF)
	TerritoryStage.tick_solve()
	_paint_nothing()
	TerritoryStage.tick(TUNING.capture_hold * 0.5)

	assert_true(Match.slot(0).home_flag_alive)
	assert_true(Match.slot(1).home_flag_alive)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_true(_eliminated.is_empty())
	TerritoryStage.tick(TUNING.capture_hold * 0.5 + HOLD_SLACK_S)
	assert_eq(_eliminated, [0, 1] as Array[int], "fixture: the claim was running and completes with the rest of the hold")


func test_elimination_batch_through_eliminate_slots_keeps_attackers() -> void:
	_start(4, MatchConfig.GameMode.ELIMINATION)
	_paint()

	Match._lifecycle.eliminate_slots(_slots([0, 1]), {0: 2, 1: 3})

	assert_eq(Match.eliminated_by(0), 2)
	assert_eq(Match.eliminated_by(1), 3)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(_eliminated, [0, 1] as Array[int])


func test_elimination_batch_through_eliminate_slots_wins_on_share() -> void:
	_start(2, MatchConfig.GameMode.ELIMINATION)
	_paint({0: 6.0})

	Match._lifecycle.eliminate_slots(_slots([0, 1]))

	assert_eq(_won, [0] as Array[int])
