class_name BotModeGoal
extends RefCounted
## The per-mode goal context BotStrategy and BotController read.
## Pure data, built on the host from the active ModeObjective (see
## MatchTerritory.bot_mode_goal()) and handed to the bot through BotWorldView; null or a CLASSIC
## context means the ordinary classic behaviour.

## MatchConfig.GameMode of the match this context was built for.
var mode: int = MatchConfig.GameMode.CLASSIC

## Capture the Flag: every beacon (disk-local), whether the bot's own team
## currently holds it (parallel array, true = held by own team).
var beacon_positions: PackedVector2Array = PackedVector2Array()
var beacon_held_by_own: Array[bool] = []

## Reach the Sky: the bot's own tallest settled block's disk-local position and
## top height (meters above the disk). `has_tower` is false until one settles.
var has_tower: bool = false
var tower_origin: Vector2 = Vector2.ZERO

## Domination: sample points (disk-local) of the leading
## enemy team's territory, and whether the bot's own team already holds (or
## shares) the largest share. Empty / true means "just grow own territory".
var leader_points: PackedVector2Array = PackedVector2Array()
var own_team_leads: bool = true

## Elimination: true under HoleMode.OFF, where a home only falls when an enemy radius exceeds the
## home radius (else an overlap opens a hole). BotEvaluator reads it.
var no_overlap_mode: bool = false

## Classic with several goal flags: every goal flag and `target_goal_index`, the
## unheld goal nearest to the bot's home-connected component (-1 when every goal is already held).
## Only filled when the match has more than one goal.
var goal_positions: PackedVector2Array = PackedVector2Array()
var target_goal_index: int = -1


## True when the classic multi-goal scoring applies.
func is_multi_goal() -> bool:
	return mode == MatchConfig.GameMode.CLASSIC and goal_positions.size() > 1


## Index of the unheld goal nearest to the home-connected component (`component_points`); -1 when
## every goal is held or there are no goals. The anchor falls back to `fallback` when the component
## has no sample points.
static func next_goal_index(
	goal_positions_in: PackedVector2Array,
	held: Array[bool],
	component_points: PackedVector2Array,
	fallback: Vector2
) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i: int in range(goal_positions_in.size()):
		if i < held.size() and held[i]:
			continue
		var distance: float = INF
		for point: Vector2 in component_points:
			distance = minf(distance, point.distance_squared_to(goal_positions_in[i]))
		if component_points.is_empty():
			distance = fallback.distance_squared_to(goal_positions_in[i])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
