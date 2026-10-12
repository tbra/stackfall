class_name BotEvalTuning
extends Resource
## Bot V2 evaluator tunables (docs/BOT_AI_REDESIGN.md 2.3 step 6, Bontago-1t5.22):
## the numbers core/ai/BotEvaluator.gd reads. Loaded as config/bot_eval_tuning.tres.

## Sunflower samples of the future influence circle read against the raster
## for the measured AREA and WASTE terms (the plan's 64-sample probe, 297 us).
@export var area_samples: int = 64
## AREA is reported in units of this many square metres.
@export var area_unit_m2: float = 10.0
## An enemy circle's base counts as covered when it lies within the new circle
## radius plus this many metres (the plan's "r + 0.5 m"; HoleDissolver dissolves
## discs touching an applied hole).
@export var kill_margin_m: float = 0.5
## KILL value, in "circles lost" units, of covering a living enemy home flag.
@export var kill_home_value: float = 20.0
## KILL value of covering a goal cell an enemy team currently holds.
@export var kill_goal_value: float = 10.0
## An own placement is exposed to an enemy circle when its base lies within the
## enemy radius plus this allowance.
@export var exposure_allowance_m: float = 1.0
## EXPOSURE saturates at this many threatening circles.
@export var exposure_cap: int = 4
## HAZARD look-ahead (Bontago-1t5.32): one enemy placement can grow an enemy circle over a
## base lying within InfluenceCircle.radius_for_height(this top height) of the circle's edge
## (a fresh piece set at the edge of the enemy land, or a stack raised by about this much).
## Bases closer than that are graded towards a certain dissolve.
@export var hazard_lookahead_height_m: float = 6.0
## Weather (Bontago-1t5.41): extra TIP risk of a placement under wind, added to the candidate's
## own tip_risk as wind_tip_weight * weather intensity * WindField.height_factor(top height).
## 0 disables it; calm weather is unaffected whatever the value.
@export var wind_tip_weight: float = 1.0
## Rim / shrink (Bontago-1t5.42): a footprint whose farthest cell lies within this many metres
## of the live disc edge is graded 0..1 as fall-off risk (0 at this distance, 1 at the edge).
@export var rim_margin_m: float = 3.0
## TIP-axis weight of that rim grade.
@export var rim_weight: float = 1.0
## Extra TIP-axis penalty when any footprint cell lies beyond the live radius (it would fall).
@export var rim_outside_penalty: float = 10.0
## Once a sudden-death shrink is active: TIP-axis bias, times the shrunk fraction
## (1 - live / original radius), towards the surviving centre (origin distance / live radius).
@export var shrink_centre_weight: float = 0.5
## A shrink counts as active only when the live radius is below the original by more than this.
@export var shrink_epsilon_m: float = 0.01
