class_name ClassicObjective
extends ModeObjective
## The classic objective: one connected territory holding every goal flag for
## capture_hold seconds (spec 1.5). A thin wrapper over WinChecker, which keeps
## all the logic; winner(), capture ring and hold behave exactly as before.
## Untimed: the match timer keeps its sudden-death meaning.

var _checker: WinChecker = null


func _init(goal_positions: PackedVector2Array = PackedVector2Array(), capture_hold: float = 3.0) -> void:
	_checker = WinChecker.new(goal_positions, capture_hold)


## The wrapped checker. MatchTerritory.set_checker() swaps it (tests and bench
## tools replace the checker in place).
func checker() -> WinChecker:
	return _checker


func set_checker(checker_ref: WinChecker) -> void:
	_checker = checker_ref


func mode_id() -> int:
	return MatchConfig.GameMode.CLASSIC


## DECISION: Classic replicates mode state only while sudden death is active, so its
## wire stays unchanged before then (the latched goals ride `extra`).
func replicates_state() -> bool:
	return _checker != null and _checker.is_sudden_death()


## Classic's results payload carries no mode fields.
func reports_mode_results() -> bool:
	return false


func reset(team_count: int) -> void:
	super.reset(team_count)
	if _checker != null:
		_checker.reset()


func update(raster: TerritoryRaster, delta: float) -> void:
	var before: PackedInt32Array = _latches()
	_checker.update(raster, delta)
	_mark_dirty_if_latches_changed(before)


func set_claim_radius(radius: float) -> void:
	if _checker != null:
		_checker.set_claim_radius(radius)


func winner() -> int:
	return _checker.winner() if _checker != null else NO_TEAM


func capturing_team() -> int:
	return _checker.capturing_team() if _checker != null else NO_TEAM


func capture_progress() -> float:
	return _checker.capture_progress() if _checker != null else 0.0


func begin_sudden_death(raster: TerritoryRaster) -> void:
	if _checker != null:
		_checker.begin_sudden_death(raster)
		_state_dirty = true


func latched_team(goal_index: int) -> int:
	return _checker.latched_team(goal_index) if _checker != null else NO_TEAM


## DECISION: an eliminated team's latches are released here (alive_teams is already
## passed), then the base rule runs, so a latch win in the same step still wins.
func resolve_eliminations(
	batch_teams: PackedInt32Array, alive_teams: PackedInt32Array, shares: PackedFloat32Array
) -> int:
	if _checker != null:
		var before: PackedInt32Array = _latches()
		_checker.release_teams_not_in(alive_teams)
		_mark_dirty_if_latches_changed(before)
	return super.resolve_eliminations(batch_teams, alive_teams, shares)


## {"sd": 1, "l0": team, ...} during sudden death (-1 = unclaimed), else {}.
func extra_state() -> Dictionary:
	var state: Dictionary = {}
	if _checker == null or not _checker.is_sudden_death():
		return state
	state["sd"] = 1
	for i: int in range(_checker.goal_positions().size()):
		state[BeaconTimerText.LATCH_KEY_PREFIX + str(i)] = _checker.latched_team(i)
	return state


## Client mirror: display only, never touches the winner.
func apply_extra_state(data: Dictionary) -> void:
	if _checker == null:
		return
	var teams: PackedInt32Array = PackedInt32Array()
	for i: int in range(_checker.goal_positions().size()):
		teams.append(int(data.get(BeaconTimerText.LATCH_KEY_PREFIX + str(i), NO_TEAM)))
	_checker.set_latched(teams)


func _latches() -> PackedInt32Array:
	var teams: PackedInt32Array = PackedInt32Array()
	if _checker == null:
		return teams
	for i: int in range(_checker.goal_positions().size()):
		teams.append(_checker.latched_team(i))
	return teams


func _mark_dirty_if_latches_changed(before: PackedInt32Array) -> void:
	if _latches() != before:
		_state_dirty = true
