class_name BotTuning
extends Resource
## Bot AI tunables (spec 2.9): one BotDifficultyProfile per
## MatchConfig.AiDifficulty value, plus the scoring weights and risk radii
## shared across every difficulty. Loaded once as config/bot_tuning.tres.

@export var easy: BotDifficultyProfile
@export var normal: BotDifficultyProfile
@export var hard: BotDifficultyProfile

## Placement-candidate scoring weights (spec 2.9's candidate score formula;
## core/ai/BotPlacementScorer.gd applies these).
@export var weight_height: float = 1.0
@export var weight_goal_progress: float = 1.5
@export var weight_stability: float = 2.0
@export var weight_risk: float = 1.0
## Meters within an enemy's territory a candidate counts as risky.
@export var risk_enemy_territory_radius_m: float = 4.0
## Meters within an active special's blast/effect radius a candidate counts
## as risky.
@export var risk_active_special_radius_m: float = 5.0
## Per-bot phase offset so N bots' think-ticks don't all land on one frame
## (spec 2.9: "for multiple bots it spreads its thinking across several
## frames").
@export var think_phase_jitter_s: float = 0.4

## Bontago-d5c (M5 P1, append-only per docs/M5_PLAN.md's "if you need a new
## numeric... add it as an @export on BotTuning, append-only"): a hard safety
## bound on how many physics frames BotController's GENERATING state may run
## for one think-cycle, in case territory sampling keeps missing (e.g. a
## slot's whole territory is momentarily empty/contested) and the natural
## ceiling of profile.candidate_count / profile.candidates_per_frame is never
## reached by successful samples alone.
@export var max_generation_frames: int = 40
## How many random points inside the field disk BotController samples,
## per candidate, before giving up and falling back to the slot's own home
## position (see BotController._sample_territory_point()).
@export var max_territory_sample_attempts: int = 12

## Bontago-d5c.2 (review fix, append-only per docs/M5_PLAN.md's "if you need
## a new numeric... add it as an @export on BotTuning, append-only"): seconds
## BotController._apply_rejection_backoff() holds a bot in IDLE after
## request_place()/request_throw() comes back with anything but
## PlacementRules.REASON_OK, so a rejected placement (e.g. another block
## landed on the sampled spot between GENERATING and ACTING) doesn't spend
## every following physics frame re-generating and re-sending the identical
## rejected request.
@export var rejection_backoff_s: float = 0.5


## Returns the profile for `difficulty`; NORMAL (and any out-of-range value)
## falls back to `normal` rather than failing, so a stale/corrupt wire value
## never leaves a bot with a null profile.
func profile_for(difficulty: MatchConfig.AiDifficulty) -> BotDifficultyProfile:
	match difficulty:
		MatchConfig.AiDifficulty.EASY:
			return easy
		MatchConfig.AiDifficulty.HARD:
			return hard
		_:
			return normal
