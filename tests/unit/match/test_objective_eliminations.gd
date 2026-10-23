extends GutTest
## The objective hooks that judge a batch of home losses (resolve_eliminations) and the results
## flag (reports_mode_results): last team standing, the zero-survivor tiebreak among the batch's
## own teams only, and Elimination's unchanged shared win.

const NO_TEAM: int = ModeObjective.NO_TEAM


## A base objective whose capture has already latched `team` this step.
class _Latched:
	extends ModeObjective

	func latch(team: int) -> void:
		_declare_winner(team)


func _latched(team: int, team_count: int = 3) -> _Latched:
	var objective: _Latched = _Latched.new()
	objective.reset(team_count)
	objective.latch(team)
	return objective


func _base(team_count: int = 3) -> ModeObjective:
	var objective: ModeObjective = ModeObjective.new()
	objective.reset(team_count)
	return objective


func _ints(values: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(values)


func _floats(values: Array[float]) -> PackedFloat32Array:
	return PackedFloat32Array(values)


func _elimination(slot_teams: Array[int], team_count: int) -> EliminationObjective:
	var objective: EliminationObjective = EliminationObjective.new(PackedInt32Array(slot_teams))
	objective.reset(team_count)
	return objective


# --- Base rule: one alive, none alive, several alive, empty batch ---------------

func test_one_alive_team_wins_whatever_the_shares() -> void:
	var winner: int = _base().resolve_eliminations(_ints([0, 1]), _ints([2]), _floats([0.6, 0.3, 0.01]))
	assert_eq(winner, 2, "the only team with a living home wins even with the smallest share")


func test_one_alive_team_wins_for_an_empty_batch() -> void:
	var winner: int = _base().resolve_eliminations(_ints([]), _ints([1]), _floats([0.1, 0.1, 0.1]))
	assert_eq(winner, 1)


func test_several_alive_teams_decide_nothing() -> void:
	var winner: int = _base().resolve_eliminations(_ints([2]), _ints([0, 1]), _floats([0.2, 0.7, 0.9]))
	assert_eq(winner, NO_TEAM)


func test_empty_batch_with_several_alive_decides_nothing() -> void:
	var winner: int = _base().resolve_eliminations(_ints([]), _ints([0, 1, 2]), _floats([0.3, 0.3, 0.3]))
	assert_eq(winner, NO_TEAM)


func test_empty_batch_with_nobody_alive_decides_nothing() -> void:
	var winner: int = _base().resolve_eliminations(_ints([]), _ints([]), _floats([0.3, 0.3, 0.3]))
	assert_eq(winner, NO_TEAM, "nothing was lost in this batch, so nobody can win it")


func test_nobody_alive_goes_to_the_largest_share_in_the_batch() -> void:
	var winner: int = _base().resolve_eliminations(_ints([0, 1]), _ints([]), _floats([0.2, 0.5, 0.0]))
	assert_eq(winner, 1)
	winner = _base().resolve_eliminations(_ints([0, 1]), _ints([]), _floats([0.5, 0.2, 0.0]))
	assert_eq(winner, 0, "the larger share wins whichever team id (or slot order) it has")


func test_nobody_alive_ignores_a_larger_share_of_a_team_outside_the_batch() -> void:
	# Team 0 went out in an earlier step and kept the biggest share; it must not win now.
	var winner: int = _base().resolve_eliminations(_ints([1, 2]), _ints([]), _floats([0.8, 0.1, 0.2]))
	assert_eq(winner, 2)


func test_nobody_alive_tie_goes_to_the_lowest_team_id() -> void:
	var winner: int = _base().resolve_eliminations(_ints([1, 2]), _ints([]), _floats([0.0, 0.4, 0.4]))
	assert_eq(winner, 1)


func test_tie_does_not_depend_on_the_batch_order() -> void:
	var winner: int = _base().resolve_eliminations(_ints([2, 1]), _ints([]), _floats([0.0, 0.4, 0.4]))
	assert_eq(winner, 1, "lowest team id, not the first listed")
	winner = _base().resolve_eliminations(_ints([2, 0, 1]), _ints([]), _floats([0.25, 0.25, 0.25]))
	assert_eq(winner, 0)


func test_three_teams_all_lost_together_pick_the_largest_of_the_three() -> void:
	var winner: int = _base().resolve_eliminations(_ints([0, 1, 2]), _ints([]), _floats([0.1, 0.2, 0.3]))
	assert_eq(winner, 2)


func test_a_single_team_in_the_batch_wins_with_nobody_alive() -> void:
	var winner: int = _base().resolve_eliminations(_ints([1]), _ints([]), _floats([0.0, 0.0, 0.0]))
	assert_eq(winner, 1)


func test_resolving_does_not_latch_a_winner_on_the_base_objective() -> void:
	var objective: ModeObjective = _base()
	objective.resolve_eliminations(_ints([0]), _ints([1]), _floats([0.0, 0.0, 0.0]))
	assert_eq(objective.winner(), NO_TEAM, "MatchLifecycle finishes the match; the hook only answers")


# --- Per mode ---------------------------------------------------------------------

func _created(mode: MatchConfig.GameMode) -> ModeObjective:
	return ModeObjective.create(mode, PackedVector2Array([Vector2.ZERO]), 1.0, 3, 1.0, 1.0, PackedInt32Array([0, 1, 2]))


func test_non_elimination_modes_use_the_last_team_standing_rule() -> void:
	for mode: MatchConfig.GameMode in [
		MatchConfig.GameMode.CLASSIC, MatchConfig.GameMode.CAPTURE_THE_FLAG,
		MatchConfig.GameMode.REACH_THE_SKY, MatchConfig.GameMode.DOMINATION,
	]:
		var objective: ModeObjective = _created(mode)
		assert_eq(objective.resolve_eliminations(_ints([2]), _ints([0]), _floats([0.0, 0.0, 0.0])), 0, "one alive wins in mode %d" % mode)
		assert_eq(objective.resolve_eliminations(_ints([0, 1]), _ints([]), _floats([0.1, 0.4, 0.0])), 1, "none alive: batch share in mode %d" % mode)
		assert_eq(objective.resolve_eliminations(_ints([0]), _ints([1, 2]), _floats([0.1, 0.4, 0.0])), NO_TEAM, "several alive in mode %d" % mode)


func test_classic_reports_no_mode_results_and_the_others_do() -> void:
	assert_false(_created(MatchConfig.GameMode.CLASSIC).reports_mode_results())
	for mode: MatchConfig.GameMode in [
		MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.GameMode.ELIMINATION,
		MatchConfig.GameMode.REACH_THE_SKY, MatchConfig.GameMode.DOMINATION,
	]:
		assert_true(_created(mode).reports_mode_results(), "mode %d carries mode results fields" % mode)


func test_base_objective_reports_mode_results_by_default() -> void:
	assert_true(ModeObjective.new().reports_mode_results())


# --- Elimination: resolve_eliminations is resolve ------------------------------------

func test_elimination_hook_wins_for_the_last_team_standing() -> void:
	var objective: EliminationObjective = _elimination([0, 1, 2], 3)
	objective.slot_eliminated(1)
	objective.slot_eliminated(0)
	var winner: int = objective.resolve_eliminations(_ints([1, 0]), _ints([2]), _floats([0.9, 0.9, 0.0]))
	assert_eq(winner, 2)
	assert_eq(objective.winner(), 2, "the objective latches its own win, as resolve() does")


func test_elimination_hook_answers_the_same_as_resolve() -> void:
	var shares: PackedFloat32Array = _floats([0.2, 0.5])
	var via_resolve: EliminationObjective = _elimination([0, 1], 2)
	var via_hook: EliminationObjective = _elimination([0, 1], 2)
	for objective: EliminationObjective in [via_resolve, via_hook]:
		objective.slot_eliminated(0)
		objective.slot_eliminated(1)
	assert_eq(via_hook.resolve_eliminations(_ints([]), _ints([]), shares), via_resolve.resolve(shares))
	assert_eq(via_hook.winner(), via_resolve.winner())
	assert_eq(via_hook.winner(), 1)
	assert_eq(via_hook.results_fields(), via_resolve.results_fields())


func test_elimination_hook_ignores_the_caller_arrays_and_uses_its_own_batch() -> void:
	var objective: EliminationObjective = _elimination([0, 1, 2], 3)
	objective.slot_eliminated(2)
	# The caller claims team 0 and 1 are both alive; the objective knows team 2 is the only loss.
	var winner: int = objective.resolve_eliminations(_ints([0, 1]), _ints([0, 1]), _floats([0.4, 0.4, 0.9]))
	assert_eq(winner, NO_TEAM, "two teams still hold living players")
	assert_eq(objective.winner(), NO_TEAM)


func test_elimination_hook_keeps_the_shared_win_within_the_tie_epsilon() -> void:
	var objective: EliminationObjective = _elimination([0, 1], 2)
	objective.slot_eliminated(0)
	objective.slot_eliminated(1)
	var close: float = 0.5 + EliminationObjective.TIE_EPSILON * 0.5
	var winner: int = objective.resolve_eliminations(_ints([]), _ints([]), _floats([0.5, close]))
	assert_eq(winner, 0, "the lowest of the sharing teams is the nominal winner")
	assert_eq(objective.results_fields()["winners"], "0,1", "both teams share the win")


func test_elimination_hook_does_not_share_beyond_the_tie_epsilon() -> void:
	var objective: EliminationObjective = _elimination([0, 1], 2)
	objective.slot_eliminated(0)
	objective.slot_eliminated(1)
	var apart: float = 0.5 + EliminationObjective.TIE_EPSILON * 3.0
	var winner: int = objective.resolve_eliminations(_ints([]), _ints([]), _floats([0.5, apart]))
	assert_eq(winner, 1)
	assert_eq(objective.results_fields()["winners"], "1")


func test_elimination_hook_without_news_decides_nothing() -> void:
	var objective: EliminationObjective = _elimination([0, 1], 2)
	assert_eq(objective.resolve_eliminations(_ints([]), _ints([0, 1]), _floats([0.5, 0.5])), NO_TEAM)
	objective.slot_eliminated(0)
	assert_eq(objective.resolve_eliminations(_ints([0]), _ints([1]), _floats([0.5, 0.5])), 1)
	assert_eq(objective.resolve_eliminations(_ints([]), _ints([1]), _floats([0.5, 0.5])), 1, "the decided win stays")


func test_elimination_hook_judges_only_teams_lost_in_the_batch() -> void:
	var objective: EliminationObjective = _elimination([0, 1, 2], 3)
	objective.slot_eliminated(0)
	assert_eq(objective.resolve_eliminations(_ints([0]), _ints([1, 2]), _floats([0.9, 0.1, 0.2])), NO_TEAM)
	objective.slot_eliminated(1)
	objective.slot_eliminated(2)
	var winner: int = objective.resolve_eliminations(_ints([1, 2]), _ints([]), _floats([0.9, 0.1, 0.2]))
	assert_eq(winner, 2, "team 0's earlier loss and big share do not count")


# --- A capture and eliminations in the same step: the capture latched first -----------

func test_latched_capture_wins_when_the_wipe_out_leaves_nobody_alive() -> void:
	var objective: _Latched = _latched(1)
	var winner: int = objective.resolve_eliminations(_ints([0, 2]), _ints([]), _floats([0.9, 0.0, 0.1]))
	assert_eq(winner, 1, "the capturing team wins although it is not in the batch and has the smallest share")


func test_latched_capture_wins_over_the_share_of_a_batch_team() -> void:
	var objective: _Latched = _latched(2)
	var winner: int = objective.resolve_eliminations(_ints([0, 1]), _ints([]), _floats([0.6, 0.3, 0.0]))
	assert_eq(winner, 2)


func test_one_team_left_standing_beats_the_latched_capture() -> void:
	var objective: _Latched = _latched(0)
	var winner: int = objective.resolve_eliminations(_ints([1, 2]), _ints([2]), _floats([0.1, 0.1, 0.1]))
	assert_eq(winner, 2, "if the eliminations leave one team standing it wins")


func test_latched_capture_wins_when_several_teams_are_alive() -> void:
	var objective: _Latched = _latched(1)
	var winner: int = objective.resolve_eliminations(_ints([2]), _ints([0, 1]), _floats([0.1, 0.1, 0.1]))
	assert_eq(winner, 1, "otherwise the capturing team wins")


func test_nobody_alive_picks_the_larger_share_even_when_it_comes_first_in_a_descending_batch() -> void:
	var winner: int = _base().resolve_eliminations(_ints([2, 0]), _ints([]), _floats([0.1, 0.0, 0.5]))
	assert_eq(winner, 2, "a lower id does not beat a larger share")


func test_nobody_alive_with_a_smaller_lower_id_in_the_batch_keeps_the_larger_share() -> void:
	var winner: int = _base().resolve_eliminations(_ints([1, 0]), _ints([]), _floats([0.1, 0.5]))
	assert_eq(winner, 1)


func test_round_timer_end_without_scores_goes_to_the_lowest_team_id() -> void:
	assert_eq(_base(3).on_round_timer_end(), 0, "equal scores: the lowest id wins")


func test_nobody_alive_counts_a_batch_team_without_a_share_as_zero() -> void:
	var winner: int = _base().resolve_eliminations(_ints([0, 3]), _ints([]), _floats([0.2, 0.3, 0.1]))
	assert_eq(winner, 0, "team 3 has no share entry: it counts 0 and loses")
	var only_unknown: int = _base().resolve_eliminations(_ints([3]), _ints([]), _floats([0.2, 0.3, 0.1]))
	assert_eq(only_unknown, 3, "a lone batch team wins even with no share entry")
