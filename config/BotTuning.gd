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

## Bontago-1t5.2: furthest a landed gift may be from the nearest sampled
## placement candidate (m) for the bot to aim its piece at it to claim it.
@export var gift_claim_reach_m: float = 8.0
## Bontago-1t5.2: reaction delay (s) for a piece carrying a held special.
@export var gift_use_delay_s: float = 0.25


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

## Bontago-d5c.8 (M5 P3b-ii, append-only per docs/M5_PLAN.md's "if you need a
## new numeric... add it as an @export on BotTuning, append-only"): how close
## (meters) a game/BotController.gd._fire_stability_raycasts() corner ray's
## own hit height must land to that candidate's own `support_height` to count
## as "in contact" for BotCandidate.corner_support_hits -- a small slack
## rather than an exact float match, since a footprint corner one cube over
## from the origin's own support raycast can legitimately sit on the same
## flat surface without both raycasts reporting bit-identical heights.
@export var stability_contact_tolerance_m: float = 0.15

## Bontago-1t5.3 phase A (append-only): mode-aware scoring weights read by
## core/ai/BotPlacementScorer.gd through a BotModeGoal. All are inert in Classic.
## Capture the Flag: pull towards the nearest beacon the team does not hold
## (multiplied by the beacon score rate), same distance-minus-future-radius
## metric as goal progress.
@export var weight_ctf_extend: float = 1.0
## Capture the Flag: bonus for a connected placement near an already-held
## beacon (scaled by the score rate), fading to 0 at the radius below.
@export var weight_ctf_reinforce: float = 1.0
@export var ctf_reinforce_radius_m: float = 6.0
## Reach the Sky: reward for the candidate's total top height (support + shape).
@export var weight_sky_top: float = 1.5
## Reach the Sky: reward for contact fraction (0..1, off-centre scaled), the
## anti-overhang term, on top of the ordinary stability weight.
@export var weight_sky_stability: float = 4.0
## Reach the Sky: per-meter penalty for sitting farther from the bot's own
## tallest tower than the reach below.
@export var weight_sky_tower_distance: float = 1.0
@export var sky_tower_reach_m: float = 2.0

## Bontago-1t5.3 phase B (append-only): Elimination weights, inert elsewhere.
## Pull towards the best living enemy home (goal-progress metric: distance minus
## the candidate's future influence radius).
@export var weight_elim_attack: float = 1.5
## Distance inflation per unit of the enemy team's territory share (0..1): a
## larger value steers the bot to weaker enemies over nearer strong ones.
@export var elim_weak_target_bias: float = 1.0
## Bonus for building up influence near the bot's own home, fading to 0 at the radius.
@export var weight_elim_defend: float = 2.0
@export var elim_defend_radius_m: float = 5.0
## Defend multiplier added per enemy circle centre within the threat radius of home.
@export var weight_elim_threat: float = 1.0
@export var elim_threat_radius_m: float = 8.0
## Bontago-1t5.4: flat bonus (in attack-metric meters) for a candidate whose
## future circle covers an enemy home beyond the flip margin (the elimination
## condition), plus a diminishing gain per meter of overshoot capped below.
@export var elim_achieve_bonus_m: float = 6.0
@export var elim_overshoot_gain: float = 0.25
@export var elim_overshoot_cap_m: float = 2.0
## Bontago-1t5.4 part 2 (approach/reach): weight of the approach term, which pays
## for each meter a candidate's influence frontier (distance to the target home
## minus its future radius) sits closer than the bot's own home does, scaled by
## (1 + elim_approach_reach_gain * future radius) so taller (bigger-influence)
## placements extend further.
@export var weight_elim_approach: float = 1.5
@export var elim_approach_reach_gain: float = 0.5
## Future radius (m) beyond which a taller placement earns no extra reach multiplier.
@export var elim_approach_reach_cap_m: float = 3.0
## Approach fades by 1 / (1 + this * enemy circles near own home): defend wins when threatened.
@export var elim_approach_threat_damp: float = 8.0
## Fraction of Elimination candidates sampled along the own-home -> target line
## (skewed to the far end, so the frontier) instead of uniformly in the disk,
## and the random lateral jitter (m) applied to those samples.
@export_range(0.0, 1.0) var elim_frontier_sample_fraction: float = 0.6
@export var elim_frontier_jitter_m: float = 3.0
## OFF mode defend: extra defend weight scaled by how much of the home radius the
## candidate's own circle covers at the home point (0..1).
@export var elim_off_defend_gain: float = 2.0

## Bontago-1t5.1 (append-only): Classic with several goal flags. Penalty for a
## candidate outside the bot's home-connected component (it cannot help the
## all-goals-in-one-component win), a bonus (fading to 0 at the radius) for
## reinforcing a goal the component already holds, and the radius itself.
@export var weight_goal_disconnected: float = 6.0
@export var weight_goal_hold_reinforce: float = 3.0
@export var goal_hold_reinforce_radius_m: float = 5.0

## Bontago-8or.27 (append-only): Black hole heuristic. Pull radius comes from the
## Black hole SpecialDef (Bontago-8or.28). Cap on block samples fed to the
## planner, score per
## enemy block caught, extra score per metre of that block's height, penalty per
## own block caught, and the least net score worth spending the special on.
@export var black_hole_max_samples: int = 96
@export var black_hole_enemy_weight: float = 1.0
@export var black_hole_enemy_height_weight: float = 0.5
@export var black_hole_own_penalty: float = 1.5
@export var black_hole_min_net_score: float = 1.0

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
