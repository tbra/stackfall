class_name BotDifficultyProfile
extends Resource
## Spec 2.9 "Difficulty: candidate count sampled, aiming error, reaction
## delay, defensive-specials use." One instance per MatchConfig.AiDifficulty
## value; BotTuning.profile_for() picks the right one for a given bot.

## How many placement candidates a think-tick samples (spec 2.9's 40-120
## range).
@export var candidate_count: int = 60
## With candidate_count, sets the think's decision deadline (generation_ticks): the think is spread
## over ceil(candidate_count / candidates_per_frame) physics ticks (spec 2.9 "for multiple bots it
## spreads its thinking across several frames").
@export var candidates_per_frame: int = 8
## Cube probes per site (stability and support), capped at the footprint.
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
## physics frame; a bot over the cap still does its share of the work left before its
## decision deadline, but no work ahead of it (Bontago-1t5.37).
@export var think_frame_cap_us: int = 2500
## Bot V2 (Bontago-1t5.37): a think is decided generation_ticks after the release boundary; the work
## left is spread over the ticks left and the deadline tick finishes it. The schedule plans to be done this many
## ticks before the deadline; they stay in reserve for a think costlier than estimated (a
## smaller worst tick, at the price of a higher mean per tick). 0 = spread up to the deadline.
@export var think_reserve_frames: int = 1
## Bot V2: how many top proxy-scored sites get the measured (territory gain) evaluation
## (P3/P4).
@export var eval_top_k: int = 8
## Bot V2: softmax temperature when picking among the top sites; small = argmax
## (P4).
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
## Bot V2 (Bontago-1t5.25): multiplier on BotStrategyTuning.gift_claim_value (0 = ignores gifts).
@export var gift_claim_scale: float = 1.0


## Physics ticks a think may take for this profile: ceil(candidate_count / candidates_per_frame), at
## most `max_ticks` (BotTuning.max_generation_frames). Bontago-1t5.37: the V2 decision deadline.
func generation_ticks(max_ticks: int) -> int:
	var per_tick: int = maxi(candidates_per_frame, 1)
	var ticks: int = ceili(float(maxi(candidate_count, 0)) / float(per_tick))
	return clampi(ticks, 1, maxi(max_ticks, 1))
