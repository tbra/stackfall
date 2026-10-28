extends GutTest
## Sudden-death goal latch (Classic): goal flags are claimed instantly, stay with
## the last claimer and the match is won when one team holds every latch. Driven
## through ClassicObjective with rasters from the real solver.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const NO_TEAM: int = -1
## A short hold so the pre-sudden-death hold test steps few ticks.
const TEST_HOLD: float = 2.0
const STEP: float = 0.1
const GOAL_LEFT: Vector2 = Vector2(-15.0, 0.0)
const GOAL_RIGHT: Vector2 = Vector2(15.0, 0.0)
const GOAL_TOP: Vector2 = Vector2(0.0, 15.0)
const CLAIM_RADIUS: float = 3.0
## How far past a home's edge a goal sits so only a claim radius reaches it.
const OFFSET_PAST_HOME: float = 1.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), _tuning.home_radius, team, slot if slot >= 0 else team, true, -1
	)


func _rasterize(circles: Array[InfluenceCircle]) -> void:
	_raster.fill_ownership(circles, _solver.solve(circles), true)
	_raster.adopt_fill(_raster, STEP, true, false)


func _objective(goals: Array[Vector2], teams: int = 3) -> ClassicObjective:
	var objective: ClassicObjective = ClassicObjective.new(PackedVector2Array(goals), TEST_HOLD)
	objective.reset(teams)
	return objective


## Rasterizes `circles` and runs one objective update on it.
func _step(objective: ClassicObjective, circles: Array[InfluenceCircle], ticks: int = 1) -> void:
	_rasterize(circles)
	for _i: int in range(ticks):
		objective.update(_raster, STEP)


## Rasterizes `circles` and starts sudden death on that board.
func _begin(objective: ClassicObjective, circles: Array[InfluenceCircle]) -> void:
	_rasterize(circles)
	objective.begin_sudden_death(_raster)


func _two_goal_split() -> Array[InfluenceCircle]:
	return [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle]


func _extra(objective: ClassicObjective) -> Dictionary:
	return objective.mode_state()["extra"] as Dictionary


# --- Before sudden death -----------------------------------------------------------

func test_before_sudden_death_the_hold_timer_still_decides() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT])
	var circles: Array[InfluenceCircle] = [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0)]
	_step(objective, circles, 19)
	assert_eq(objective.winner(), NO_TEAM, "1.9 s of a 2 s hold is not a win")
	assert_eq(objective.capturing_team(), 0)
	assert_gt(objective.capture_progress(), 0.9)
	_step(objective, circles, 1)
	assert_eq(objective.winner(), 0, "the full hold wins as before")


func test_classic_replicates_no_state_before_sudden_death() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT])
	assert_false(objective.replicates_state())
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0)] as Array[InfluenceCircle])
	assert_false(objective.replicates_state(), "capturing does not start replication")
	assert_eq(objective.latched_team(0), NO_TEAM, "no latch outside sudden death")


func test_sudden_death_turns_replication_on_and_reset_turns_it_off() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	assert_true(objective.replicates_state())
	objective.reset(3)
	assert_false(objective.replicates_state())
	assert_eq(objective.latched_team(0), NO_TEAM)
	assert_eq(objective.latched_team(1), NO_TEAM)


# --- Instant claim -----------------------------------------------------------------

func test_a_goal_held_at_the_start_is_latched_at_once() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	assert_eq(objective.latched_team(0), 0)
	assert_eq(objective.latched_team(1), 1)


func test_a_single_goal_held_at_the_start_wins_on_the_next_step_without_any_hold() -> void:
	var objective: ClassicObjective = _objective([Vector2.ZERO])
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 1)]
	_begin(objective, circles)
	_step(objective, circles)
	assert_eq(objective.winner(), 1, "no 2 s hold in sudden death")


func test_a_goal_claimed_after_sudden_death_began_latches_on_the_next_step() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, [_home(0.0, -15.0, 0)] as Array[InfluenceCircle])
	assert_eq(objective.latched_team(0), NO_TEAM, "nobody holds a goal yet")
	_step(objective, _two_goal_split())
	assert_eq(objective.latched_team(0), 0)
	assert_eq(objective.latched_team(1), 1)


func test_no_capture_ring_in_sudden_death() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	var circles: Array[InfluenceCircle] = [
		_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 0, 1), _home(0.0, -15.0, 1)
	]
	# The same board before sudden death shows a ring, so the quiet below is the mode.
	var normal: ClassicObjective = _objective([GOAL_LEFT])
	_step(normal, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0)] as Array[InfluenceCircle], 5)
	assert_gt(normal.capture_progress(), 0.0, "setup: the hold shows progress outside sudden death")

	_begin(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0), _home(0.0, -15.0, 1)] as Array[InfluenceCircle])
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle], 10)
	assert_almost_eq(objective.capture_progress(), 0.0, 0.0001)
	assert_eq(objective.capturing_team(), NO_TEAM)
	_step(objective, circles, 3)
	assert_eq(objective.winner(), 0, "setup: the win itself still lands")


# --- Persistence --------------------------------------------------------------------

func test_a_latch_survives_the_territory_leaving_the_goal() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_step(objective, [_home(0.0, -15.0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle], 3)
	assert_eq(objective.latched_team(0), 0, "team 0 keeps the flag with no territory on it")
	assert_eq(objective.latched_team(1), 1)
	assert_eq(objective.winner(), NO_TEAM)


func test_a_latch_survives_the_goal_being_contested() -> void:
	var objective: ClassicObjective = _objective([Vector2.ZERO, GOAL_RIGHT])
	_begin(objective, [_home(0.0, 0.0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle])
	var contested: Array[InfluenceCircle] = [
		_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1, 2), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)
	]
	_rasterize(contested)
	assert_true(_raster.is_contested(_grid.world_to_cell(Vector2.ZERO).x, _grid.world_to_cell(Vector2.ZERO).y),
		"setup: the goal cell is contested")
	objective.update(_raster, STEP)
	assert_eq(objective.latched_team(0), 0, "a contested cell holds for nobody, the latch stays")
	assert_eq(objective.winner(), NO_TEAM)


func test_a_latch_survives_the_goal_cell_becoming_a_hole() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_rasterize(_two_goal_split())
	var cell: Vector2i = _grid.world_to_cell(GOAL_LEFT)
	_raster.force_hole_cell(cell.x, cell.y, 0.0, true)
	assert_true(_raster.is_hole(cell.x, cell.y), "setup: the flag cell is a hole")
	objective.update(_raster, STEP)
	assert_eq(objective.latched_team(0), 0)
	assert_eq(objective.winner(), NO_TEAM)


# --- Reclaim and win ----------------------------------------------------------------

func test_another_teams_hold_reclaims_the_flag_instantly() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 2), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle])
	assert_eq(objective.latched_team(0), 2, "team 2 took the flag in one step")
	assert_eq(objective.latched_team(1), 1)
	assert_eq(objective.winner(), NO_TEAM)


func test_flags_split_across_teams_do_not_win() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_step(objective, _two_goal_split(), 30)
	assert_eq(objective.winner(), NO_TEAM, "no hold timer wins a split board either")


func test_one_team_holding_every_flag_wins_in_separate_towers() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	var two_towers: Array[InfluenceCircle] = [
		_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 0, 1)
	]
	assert_eq(_solver.solve(two_towers).group_count(), 2, "setup: two disconnected groups")
	_step(objective, two_towers)
	assert_eq(objective.winner(), 0, "the one-territory rule is not applied")


func test_the_win_completes_from_latches_after_the_territory_is_gone() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0), _home(0.0, -15.0, 1)] as Array[InfluenceCircle])
	assert_eq(objective.winner(), NO_TEAM, "setup: team 1 still has flag 1 latched")
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 0, 1)] as Array[InfluenceCircle])
	assert_eq(objective.winner(), 0)


func test_three_goals_partial_then_complete() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_TOP, GOAL_RIGHT])
	var partial: Array[InfluenceCircle] = [
		_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_TOP.x, GOAL_TOP.y, 0, 1), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)
	]
	_begin(objective, partial)
	assert_eq(objective.latched_team(0), 0)
	assert_eq(objective.latched_team(1), 0)
	assert_eq(objective.latched_team(2), 1)
	_step(objective, partial, 5)
	assert_eq(objective.winner(), NO_TEAM, "two of three flags is not enough")
	var complete: Array[InfluenceCircle] = [
		_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_TOP.x, GOAL_TOP.y, 0, 1), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 0, 2)
	]
	_step(objective, complete)
	assert_eq(objective.winner(), 0)


func test_free_for_all_latches_are_per_team() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT], 4)
	var board: Array[InfluenceCircle] = [_home(GOAL_LEFT.x, GOAL_LEFT.y, 2), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 3)]
	_begin(objective, board)
	assert_eq(objective.latched_team(0), 2)
	assert_eq(objective.latched_team(1), 3)
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 3, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 3, 1)] as Array[InfluenceCircle])
	assert_eq(objective.winner(), 3)


func test_the_win_is_not_revoked_when_the_board_changes() -> void:
	var objective: ClassicObjective = _objective([Vector2.ZERO])
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_begin(objective, circles)
	_step(objective, circles)
	_step(objective, [_home(0.0, 0.0, 1)] as Array[InfluenceCircle], 3)
	assert_eq(objective.winner(), 0, "a decided match stays decided")


# --- Claim radius ---------------------------------------------------------------------

func test_the_claim_radius_is_honoured_when_latching() -> void:
	var far_goal: Vector2 = Vector2(_tuning.home_radius + OFFSET_PAST_HOME, 0.0)
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	var strict: ClassicObjective = _objective([far_goal, GOAL_LEFT])
	_begin(strict, circles)
	assert_eq(strict.latched_team(0), NO_TEAM, "the flag cell itself is outside the home")
	var generous: ClassicObjective = _objective([far_goal, GOAL_LEFT])
	generous.set_claim_radius(CLAIM_RADIUS)
	_begin(generous, circles)
	assert_eq(generous.latched_team(0), 0, "cells within the radius claim the flag")


# --- Eliminations ---------------------------------------------------------------------

func test_an_eliminated_teams_latches_are_released() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	objective.consume_state_dirty()
	var result: int = objective.resolve_eliminations(
		PackedInt32Array([0]), PackedInt32Array([1, 2]), PackedFloat32Array([0.0, 0.5, 0.5])
	)
	assert_eq(result, NO_TEAM, "two teams are still alive")
	assert_eq(objective.latched_team(0), NO_TEAM, "team 0 is out, its flag is free")
	assert_eq(objective.latched_team(1), 1, "survivors keep theirs")
	assert_true(objective.consume_state_dirty(), "the release is published")
	assert_eq(_extra(objective).get("l0"), NO_TEAM, "and visible in the mode state")


func test_an_eliminated_team_does_not_block_others_from_winning() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	objective.resolve_eliminations(
		PackedInt32Array([0]), PackedInt32Array([1, 2]), PackedFloat32Array([0.0, 0.5, 0.5])
	)
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 1, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1, 1)] as Array[InfluenceCircle])
	assert_eq(objective.winner(), 1)


func test_resolve_eliminations_without_a_release_changes_nothing() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	objective.consume_state_dirty()
	objective.resolve_eliminations(
		PackedInt32Array([2]), PackedInt32Array([0, 1]), PackedFloat32Array([0.5, 0.5, 0.0])
	)
	assert_eq(objective.latched_team(0), 0)
	assert_eq(objective.latched_team(1), 1)
	assert_false(objective.consume_state_dirty(), "nothing released, nothing to publish")


func test_a_latch_win_in_the_same_step_beats_an_elimination_wipe_out() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 0, 1)] as Array[InfluenceCircle])
	assert_eq(objective.winner(), 0, "setup: team 0 latched every flag")
	var result: int = objective.resolve_eliminations(
		PackedInt32Array([1, 2]), PackedInt32Array([0, 1]), PackedFloat32Array([0.4, 0.4, 0.2])
	)
	assert_eq(result, 0, "the latched winner still wins that step")


# --- Mode state and dirty marking --------------------------------------------------------

func test_begin_marks_state_dirty_and_publishes_the_latches() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	objective.consume_state_dirty()
	_begin(objective, _two_goal_split())
	assert_true(objective.consume_state_dirty())
	var extra: Dictionary = _extra(objective)
	assert_eq(BeaconTimerText.latched_in_state(objective.mode_state(), 0), 0)
	assert_eq(extra.get("l1"), 1)
	assert_lte(extra.size(), 6, "a handful of keys")


func test_a_claim_after_the_start_marks_state_dirty() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, [_home(0.0, -15.0, 0)] as Array[InfluenceCircle])
	objective.consume_state_dirty()
	_step(objective, _two_goal_split())
	assert_true(objective.consume_state_dirty(), "a new latch must reach the clients")
	assert_eq(_extra(objective).get("l0"), 0)


func test_a_flip_marks_state_dirty() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	objective.consume_state_dirty()
	_step(objective, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 2), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle])
	assert_true(objective.consume_state_dirty())
	assert_eq(_extra(objective).get("l0"), 2)


func test_an_unchanged_board_does_not_keep_the_state_dirty() -> void:
	var objective: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(objective, _two_goal_split())
	_step(objective, _two_goal_split())
	objective.consume_state_dirty()
	_step(objective, _two_goal_split(), 5)
	assert_false(objective.consume_state_dirty(), "no latch changed, nothing to republish")


func test_client_mirrors_the_latches_for_display_only() -> void:
	var host: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(host, _two_goal_split())
	_step(host, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 2), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 1)] as Array[InfluenceCircle])
	var client: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	client.apply_mode_state(host.mode_state())
	assert_eq(client.latched_team(0), 2)
	assert_eq(client.latched_team(1), 1)
	assert_eq(client.winner(), NO_TEAM)


func test_applying_a_winning_state_never_sets_the_clients_winner() -> void:
	var host: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(host, _two_goal_split())
	_step(host, [_home(GOAL_LEFT.x, GOAL_LEFT.y, 0, 0), _home(GOAL_RIGHT.x, GOAL_RIGHT.y, 0, 1)] as Array[InfluenceCircle])
	assert_eq(host.winner(), 0, "setup: the host has a winner")
	var client: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	client.apply_mode_state(host.mode_state())
	assert_eq(client.latched_team(0), 0)
	assert_eq(client.latched_team(1), 0)
	assert_eq(client.winner(), NO_TEAM, "only the host decides")
	assert_eq(client.capture_progress(), 0.0)


func test_latched_in_state_reads_missing_keys_as_no_team() -> void:
	assert_eq(BeaconTimerText.latched_in_state({}, 0), NO_TEAM)
	assert_eq(BeaconTimerText.latched_in_state({"extra": {"l1": 2}}, 1), 2)
	assert_eq(BeaconTimerText.latched_in_state({"extra": {"l1": 2}}, 0), NO_TEAM)


func test_a_cleared_latch_travels_as_no_team() -> void:
	var host: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	_begin(host, _two_goal_split())
	var client: ClassicObjective = _objective([GOAL_LEFT, GOAL_RIGHT])
	client.apply_mode_state(host.mode_state())
	host.resolve_eliminations(PackedInt32Array([0]), PackedInt32Array([1, 2]), PackedFloat32Array([0.0, 0.5, 0.5]))
	client.apply_mode_state(host.mode_state())
	assert_eq(client.latched_team(0), NO_TEAM, "the release reaches the mirror")
	assert_eq(client.latched_team(1), 1)
