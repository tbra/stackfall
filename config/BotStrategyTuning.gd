class_name BotStrategyTuning
extends Resource
## Bot V2 strategy tunables (docs/BOT_AI_REDESIGN.md 2.3 step 3, Bontago-1t5.23): the
## thresholds and intent weight vectors core/ai/BotStrategy.gd reads. Shipped values live
## in config/bot_strategy_tuning.tres. Distances are metres.

@export_group("Thresholds")
## DEFEND: an own circle is worth defending when losing it cuts at least this many circles.
@export var defend_downstream_min: int = 3
## STRIKE: an enemy circle is worth cutting when it carries at least this many circles.
@export var strike_downstream_min: int = 3
## A circle is threatened when an enemy circle's radius plus this allowance reaches its base.
## BotDifficultyProfile.threat_lookahead_m is added on top for tiers that look ahead.
@export var threat_allowance_m: float = 1.0
## STRIKE: one placement can cover an enemy base when it lies within this distance of
## the own land's edge.
@export var strike_reach_m: float = 4.0
## STRIKE: extra value (in circles) of an enemy circle whose reach covers a goal.
@export var strike_goal_bonus: float = 4.0
## FINISH: the gap to the target (distance to the own land's edge) at which the bot builds
## the capture tower instead of racing.
@export var finish_gap_m: float = 6.0
## ANCHOR: the tip stack is "low" below this top height.
@export var anchor_min_height_m: float = 4.0
## ANCHOR: an enemy circle within this distance (edge to edge) of the tip contests it.
@export var contest_lookahead_m: float = 8.0
## ANCHOR: every Nth own placement is an anchor piece whatever the situation (0 = never).
@export var anchor_rhythm: int = 4
## RACE and ANCHOR hold for at least this many own placements before the other may replace
## them (HOLD, DEFEND, STRIKE, FINISH pre-empt immediately).
@export var intent_min_hold_pieces: int = 3
## Elimination: target homes whose distances differ by less than this tie; the tie breaks
## to the clockwise neighbour so a ring of bots does not pile on one home.
@export var elim_tie_epsilon_m: float = 0.5

@export_group("Gifts")
## Gift claim (Bontago-1t5.25): score bonus per landed, unclaimed gift a site's new circle
## would cover. Added on top of the intent score (REACH is metres, so 4 = "worth a 4 m detour").
@export var gift_claim_value: float = 4.0
## A gift counts as covered only when it lies this far inside the new circle's radius.
@export var gift_claim_margin_m: float = 0.5

@export_group("Intent weights")
## Per-intent weight vectors, indexed by BotIntent.Term:
## REACH, AREA, KILL, EXPOSURE, TIP, WASTE (the last three are penalties).
@export var weights_race: PackedFloat32Array = PackedFloat32Array([1.0, 0.1, 0.2, 0.3, 2.0, 0.4])
@export var weights_anchor: PackedFloat32Array = PackedFloat32Array([1.0, 0.2, 0.2, 0.2, 3.0, 0.0])
@export var weights_finish: PackedFloat32Array = PackedFloat32Array([1.5, 0.05, 0.3, 0.2, 3.0, 0.0])
@export var weights_hold: PackedFloat32Array = PackedFloat32Array([1.0, 0.05, 0.8, 0.5, 3.0, 0.0])
@export var weights_defend: PackedFloat32Array = PackedFloat32Array([0.3, 0.1, 1.5, 1.0, 2.0, 0.2])
@export var weights_strike: PackedFloat32Array = PackedFloat32Array([0.3, 0.1, 2.0, 0.3, 2.0, 0.2])
@export var weights_siege: PackedFloat32Array = PackedFloat32Array([1.2, 0.1, 0.8, 0.3, 2.5, 0.3])
@export var weights_area: PackedFloat32Array = PackedFloat32Array([0.3, 1.0, 0.5, 0.4, 2.0, 0.8])


## The weight vector of `kind`.
func weights_for(kind: int) -> PackedFloat32Array:
	match kind:
		BotIntent.Kind.ANCHOR:
			return weights_anchor
		BotIntent.Kind.FINISH:
			return weights_finish
		BotIntent.Kind.HOLD:
			return weights_hold
		BotIntent.Kind.DEFEND:
			return weights_defend
		BotIntent.Kind.STRIKE:
			return weights_strike
		BotIntent.Kind.SIEGE:
			return weights_siege
		BotIntent.Kind.AREA:
			return weights_area
	return weights_race
