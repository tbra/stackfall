class_name BotEvalTuning
extends Resource
## Bot V2 evaluator tunables (docs/BOT_AI_REDESIGN.md 2.3 step 6):
## the numbers core/ai/BotEvaluator.gd reads. Loaded as config/bots/bot_eval_tuning.tres.

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
## HAZARD look-ahead: one enemy placement can grow an enemy circle over a
## base lying within InfluenceCircle.radius_for_height(this top height) of the circle's edge
## (a fresh piece set at the edge of the enemy land, or a stack raised by about this much).
## Bases closer than that are graded towards a certain dissolve.
@export var hazard_lookahead_height_m: float = 6.0
## Weather: extra TIP risk of a placement under wind, added to the placement's
## TIP term as wind_tip_weight * weather intensity * WindField.height_factor(top height).
## 0 disables it; calm weather is unaffected whatever the value.
@export var wind_tip_weight: float = 1.0
## Weather: extra TIP risk of a placement in an active Breeze gust, added as
## breeze_tip_weight * gust power * BreezeField.falloff(distance to the gust centre) *
## WindField.height_factor(top height). A gust is local and brief next to a Storm, so below
## wind_tip_weight. 0 disables the gust term; no live gust adds exactly 0.
@export var breeze_tip_weight: float = 0.5
## A gust sphere is stretched downwind of its centre by this fraction (0 = the host's symmetric
## sphere): the push carries loose pieces and the wake along the heading, so a site downwind of the
## centre is graded as closer to the gust than an upwind site at the same distance.
@export var breeze_lee_gain: float = 0.5
## Wind direction (Storm base heading, gust heading): the wind term grows by up to this fraction
## when the piece sits within rim_margin_m of the live disc edge measured along the wind (a shove
## downwind then takes it over the rim); an upwind or central placement is not changed. 0 disables.
@export var wind_rim_gain: float = 1.0
## Rim / shrink: a footprint whose farthest cell lies within this many metres
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

## Airborne gifts and enemy specials in flight. A falling gift joins the bot's gift
## list at its landing point only when it lands within this many seconds (earlier ones are too
## uncertain to pre-position for; the landing is fixed so this is just a planning horizon).
@export var air_gift_horizon_s: float = 6.0
## A special in flight counts as incoming only above this speed (m/s); slower bodies are resting.
@export var incoming_min_speed_mps: float = 1.0
## HAZARD-axis weight of a site inside an incoming enemy special's impact zone (1 at the impact
## point, falling linearly to 0 at radius + incoming_margin_m). 0 disables the term.
@export var incoming_special_weight: float = 1.0
## Impact radius (m) assumed for an incoming special whose effect radius is unknown.
@export var incoming_default_radius_m: float = 3.0
## Safety margin added to an incoming special's impact radius when grading a site.
@export var incoming_margin_m: float = 1.0

## TIP-axis penalty of a site whose placement is not stable under the two centre-of-mass rules:
## its piece or a tower level below it would topple (BotStability slack <= 0).
@export var topple_penalty: float = 10.0

## Height gained (Reach the Sky only): REACH-axis bonus per metre the placed piece's top
## rises above the own tallest block (0 when it does not raise the tower), so a bar stands up when the
## statics allow. 0 disables it (and the next term).
@export var height_gain_weight: float = 1.0
## REACH-axis bonus per cube in the piece's top layer (the landing area left for the next piece), up to
## height_top_area_cap cubes: a piece stood on end where nothing can land on it scores lower.
@export var height_top_area_weight: float = 0.3
@export var height_top_area_cap: float = 4.0
