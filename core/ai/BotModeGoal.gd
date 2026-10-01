class_name BotModeGoal
extends RefCounted
## Bontago-1t5.3 phase A: the per-mode goal context BotPlacementScorer reads.
## Pure data, built on the host from the active ModeObjective (see
## MatchTerritory.bot_mode_goal()) and handed to the scorer; null or a CLASSIC
## context means "score exactly as before" (classic bot behaviour is unchanged).

## MatchConfig.GameMode of the match this context was built for.
var mode: int = MatchConfig.GameMode.CLASSIC

## Capture the Flag: every beacon (disk-local), whether the bot's own team
## currently holds it (parallel array, true = held by own team), and the
## points a held beacon scores per second (the scoring-rate weight).
var beacon_positions: PackedVector2Array = PackedVector2Array()
var beacon_held_by_own: Array[bool] = []
var beacon_score_rate: float = 1.0

## Reach the Sky: the bot's own tallest settled block's disk-local position and
## top height (meters above the disk). `has_tower` is false until one settles.
var has_tower: bool = false
var tower_origin: Vector2 = Vector2.ZERO
var tower_height: float = 0.0

## Elimination (phase B): living opponent homes (disk-local) with their team's
## territory share (parallel array; larger = stronger), and the bot's own home.
var enemy_home_positions: PackedVector2Array = PackedVector2Array()
var enemy_home_shares: PackedFloat32Array = PackedFloat32Array()
var has_own_home: bool = false
var own_home_position: Vector2 = Vector2.ZERO
## Bontago-1t5.4: true under HoleMode.OFF, where a home only falls when an enemy
## radius at the home point exceeds `home_radius` (else an overlap opens a hole).
var no_overlap_mode: bool = false
var home_radius: float = 0.0


## Bontago-1t5.1 (Classic with several goal flags): every goal flag, whether it
## sits in the bot's own home-connected component (parallel array), that
## component's group id (-1 when the bot's home has none) and sample points of
## its cells (disk-local). `target_goal_index` is the unheld goal nearest to the
## component (-1 when every goal is already held). Only filled when the match
## has more than one goal; a single goal keeps the legacy nearest-goal scoring.
var goal_positions: PackedVector2Array = PackedVector2Array()
var goal_in_home_group: Array[bool] = []
var home_group: int = -1
var component_points: PackedVector2Array = PackedVector2Array()
var target_goal_index: int = -1


## True when the classic multi-goal scoring applies.
func is_multi_goal() -> bool:
	return mode == MatchConfig.GameMode.CLASSIC and goal_positions.size() > 1


func is_neutral() -> bool:
	return mode == MatchConfig.GameMode.CLASSIC and not is_multi_goal()
