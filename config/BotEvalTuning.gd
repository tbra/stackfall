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
