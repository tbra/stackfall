class_name BotScoreTerms
extends RefCounted
## Bontago-1t5.11 (BT1, docs/BOT_TRAINING_SOAK_PLAN.md section 1): the unweighted
## components of BotPlacementScorer.score(), so any linear weight vector can be
## re-scored offline. Pure data.
##
## weighted() replays score()'s own arithmetic: `height` is the raw
## support_height, `goal` the raw goal-progress metric (smaller is better, so it
## enters negated), `stability` and `risk` the raw factor values, and `mode` the
## already-weighted additive mode/multi-goal term (0.0 for Classic), which has
## its own BotTuning weights and is therefore not rescaled here.

var height: float = 0.0
var goal: float = 0.0
var stability: float = 0.0
var risk: float = 0.0
var mode: float = 0.0


func weighted(tuning: BotTuning) -> float:
	var base: float = (
		tuning.weight_height * height
		- tuning.weight_goal_progress * goal
		+ tuning.weight_stability * stability
		- tuning.weight_risk * risk
	)
	return base + mode


## [height, goal, stability, risk, mode], the order of schema v1's `terms`.
func to_array() -> PackedFloat32Array:
	return PackedFloat32Array([height, goal, stability, risk, mode])
