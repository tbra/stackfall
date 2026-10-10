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

## Bot V2 (Bontago-1t5.19): microseconds of one think-cycle a single physics frame
## may spend (BotThink.step budget).
@export var think_budget_us: int = 800
## Bot V2: static cap on the microseconds ALL bots together may spend thinking in one
## physics frame; bots over the cap wait for the next frame.
@export var think_frame_cap_us: int = 2500
## Bot V2: how many top proxy-scored sites get the measured (territory gain) evaluation
## (P3/P4; unused by the legacy-equivalent pipeline).
@export var eval_top_k: int = 8
## Bot V2: softmax temperature when picking among the top sites; small = argmax
## (P4; unused by the legacy-equivalent pipeline).
@export var pick_temperature: float = 0.5
## Bot V2: bit set of BotIntent.Kind values this tier may use (bit = enum value).
@export_flags("Race", "Anchor", "Finish", "Hold", "Defend", "Strike", "Siege", "Area") var intent_mask: int = 255
## Bot V2 (Bontago-1t5.23): the pick samples from this many of the best measured sites
## (1 = argmax; Easy 5, Normal 3, Hard 1).
@export var pick_pool: int = 1
## Bot V2: share (0..1) of the site budget that is uniform FILL; 0 keeps BotGenTuning's
## default mix (Easy plays half its sites at random).
@export var fill_share: float = 0.0
## Bot V2: extra metres added to BotStrategyTuning.threat_allowance_m, so a tier that
## looks ahead defends / strikes before an enemy circle actually reaches a base (Hard only).
@export var threat_lookahead_m: float = 0.0
