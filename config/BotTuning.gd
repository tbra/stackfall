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


## P3 (Bontago-d5c.4, append-only per docs/M5_PLAN.md's "if you need a new
## numeric... add it as an @export on BotTuning, append-only"): core/ai/
## BotSpecialPlanner.gd's Bomb heuristic (a thrown special) needs its own
## pre-clamp launch-speed and loft tunables -- the planner is never handed a
## SpecialTuning instance, so it cannot read SpecialTuning.throw_max_speed/
## throw_loft_ratio directly.

## Bomb/DaBomb pre-clamp launch speed BotSpecialPlanner._ballistic_velocity()
## picks, in m/s. Deliberately well under SpecialTuning.throw_max_speed's own
## default (25.0 m/s) so the host's request_throw() clamp is never the actual
## limiting factor for a bot's own throw -- a value at or above throw_max_speed
## would just get silently clamped down there anyway.
@export var special_throw_speed_mps: float = 16.0
## Vertical component of that same pre-clamp velocity, as a plain ratio
## against the horizontal (ground-plane) component, before normalising to
## special_throw_speed_mps -- the bot's own analogue of SpecialTuning.
## throw_loft_ratio's "1.0 lofts at 45 degrees" convention for a human throw's
## drag gesture, kept as a separate tunable since the planner is pure core/
## code with no SpecialTuning reference.
@export var special_throw_loft_ratio: float = 0.6

## Bontago-d5c.9 (M5 P3b-i, append-only): core/ai/BotPlacementScorer.gd's
## stability factor multiplies the supported-cell contact count by this
## factor when a candidate's own centre-of-mass estimate (BotCandidate.origin)
## falls outside its footprint's bounds -- an off-balance placement still
## scores something, just less than a well-centred one.
@export var stability_off_centre_factor: float = 0.5
## Flat bonus core/ai/BotPlacementScorer.gd's stability factor adds when a
## candidate rests on the bot's own already-placed stack
## (BotCandidate.on_top_of_own_stack).
@export var stability_stack_bonus: float = 1.0

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
