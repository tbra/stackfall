class_name ClassicObjective
extends ModeObjective
## The classic objective: one connected territory holding every goal flag for
## capture_hold seconds (spec 2.3). A thin wrapper over WinChecker, which keeps
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


func replicates_state() -> bool:
	return false


func reset(team_count: int) -> void:
	super.reset(team_count)
	if _checker != null:
		_checker.reset()


func update(raster: TerritoryRaster, delta: float) -> void:
	_checker.update(raster, delta)


func winner() -> int:
	return _checker.winner() if _checker != null else NO_TEAM


func capturing_team() -> int:
	return _checker.capturing_team() if _checker != null else NO_TEAM


func capture_progress() -> float:
	return _checker.capture_progress() if _checker != null else 0.0
