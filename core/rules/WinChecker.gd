class_name WinChecker
extends RefCounted
## The win condition (spec 2.3, 3.3).
##
## Spec 2.3: "A player or team wins when one connected territory contains
## every goal flag continuously for capture_hold = 3 s." Spec 3.3 says to
## check it against the raster, which is what this does: read the group index
## at each goal flag position; if every goal reads the *same* group index and
## that group is real, that group's team is capturing. "The same group", not
## "the same team", is what makes it one *connected* territory, so a team
## holding two goals with two separate towers does not win.
##
## The hold timer resets the moment the capture breaks, including when the
## capturing group changes identity between solves.
##
## Pure logic: no scene tree (CLAUDE.md).

const NO_TEAM: int = -1

var _goal_positions: PackedVector2Array = PackedVector2Array()
var _capture_hold: float = 3.0


func _init(
	goal_positions: PackedVector2Array = PackedVector2Array(), capture_hold: float = 3.0
) -> void:
	_goal_positions = goal_positions
	_capture_hold = maxf(capture_hold, 0.0)


func goal_positions() -> PackedVector2Array:
	return _goal_positions


func capture_hold() -> float:
	return _capture_hold


@warning_ignore_start("unused_parameter")
## Advances the capture timer by `delta` seconds against one raster. Called
## once per territory solve (spec 3.7: "Win check: runs every territory
## update"), so delta is 1 / TerritoryTuning.solve_hz.
func update(raster: TerritoryRaster, delta: float) -> void:
	pass


## Team currently holding every goal in one connected group, or NO_TEAM.
func capturing_team() -> int:
	return NO_TEAM


## How far through capture_hold the current capture is, 0..1. Drives the goal
## flag's radial progress ring (spec 2.3) and the HUD.
func capture_progress() -> float:
	return 0.0


## The winning team, or NO_TEAM until a capture completes. Latches: once a
## team wins, this keeps returning it until reset().
func winner() -> int:
	return NO_TEAM


## Replaces the goal flag layout, e.g. when a match starts.
func set_goal_positions(positions: PackedVector2Array) -> void:
	pass


## Clears the capture timer and the latched winner.
func reset() -> void:
	pass
@warning_ignore_restore("unused_parameter")
