class_name BotDifficultyProfile
extends Resource
## Spec 2.9 "Difficulty: candidate count sampled, aiming error, reaction
## delay, defensive-specials use." One instance per MatchConfig.AiDifficulty
## value; BotTuning.profile_for() picks the right one for a given bot.

## How many placement candidates a think-tick samples (spec 2.9's 40-120
## range).
@export var candidate_count: int = 60
## Time-slicing budget: how many candidates BotController scores per frame,
## so an 8-bot match never stalls a single frame scoring all of them at once
## (spec 2.9 "for multiple bots it spreads its thinking across several
## frames").
@export var candidates_per_frame: int = 8
## Footprint-corner raycasts BotController fires per candidate to judge
## landing stability.
@export var stability_raycast_count: int = 4
## Random aiming error, in meters, applied to a candidate's chosen origin
## before it is committed as the actual drop point.
@export var aim_noise_m: float = 0.3
## Seconds of delay after a block/special is issued before the bot starts
## thinking about where to place it.
@export var reaction_delay_s: float = 0.6
## Whether this difficulty ever throws a special defensively (hole-filling,
## leveling its own territory).
@export var uses_defensive_specials: bool = false
## Whether this difficulty ever throws a special offensively (targeting an
## opponent's territory).
@export var uses_offensive_specials: bool = false
