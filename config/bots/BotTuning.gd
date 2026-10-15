class_name BotTuning
extends Resource
## Bot AI tunables (spec 1.8): one BotDifficultyProfile per
## MatchConfig.AiDifficulty value, plus the timing, special and
## stability tunables shared across every difficulty. Loaded once as config/bots/bot_tuning.tres.

@export var easy: BotDifficultyProfile
@export var normal: BotDifficultyProfile
@export var hard: BotDifficultyProfile

## Per-bot phase offset so N bots' think-ticks don't all land on one frame
## (spec 1.8: "for multiple bots it spreads its thinking across several
## frames").
@export var think_phase_jitter_s: float = 0.4

## Hard bound on the physics ticks one think-cycle may run (BotController THINKING state), and the
## ceiling of a tier's decision deadline (BotDifficultyProfile.generation_ticks).
@export var max_generation_frames: int = 40
## review fix, append-only per docs/archive/M5_PLAN.md's "if you need
## a new numeric... add it as an @export on BotTuning, append-only": seconds
## BotController._apply_rejection_backoff() holds a bot in IDLE after
## request_place()/request_throw() comes back with anything but
## PlacementRules.REASON_OK, so a rejected placement (e.g. another block
## landed on the chosen spot between THINKING and ACTING) doesn't spend
## every following physics frame re-thinking and re-sending the identical
## rejected request.
@export var rejection_backoff_s: float = 0.5

## Reaction delay (s) for a piece carrying a held special.
@export var gift_use_delay_s: float = 0.25

## P3 (append-only per docs/archive/M5_PLAN.md's "if you need a new
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

## M5 P3b-ii, append-only per docs/archive/M5_PLAN.md's "if you need a
## new numeric... add it as an @export on BotTuning, append-only": how close
## (meters) a BotThink cube probe's
## own hit height must land to that candidate's own `support_height` to count
## as "in contact" for BotCandidate.corner_support_hits -- a small slack
## rather than an exact float match, since a footprint corner one cube over
## from the origin's own support raycast can legitimately sit on the same
## flat surface without both raycasts reporting bit-identical heights.
@export var stability_contact_tolerance_m: float = 0.15

## Domination: how many leader territory sample points the host hands BotModeGoal.leader_points.
@export var dom_leader_sample_cap: int = 48


## Black hole (BotSpecialPlanner.plan_v2): penalty per own circle the pull radius
## would drag in, and the least net score worth spending the special on.
@export var black_hole_own_penalty: float = 1.5
@export var black_hole_min_net_score: float = 1.0

## Bot V2 specials (BotSpecialPlanner.plan_v2). Reach: how far (m) beyond own
## land an offensive target may sit. Min downstream: fewest circles a joint must cut off to be
## worth an area special. Height tiebreak: score per metre of tower height. Throw tolerance: how
## far (m) the nearest own release point may be from the host's fixed throw range. Paintball min
## height: shortest enemy stack worth converting. Threat gap: edge distance (m) under which an
## own tower counts as threatened for Freeze/Glue.
@export var special_v2_reach_m: float = 6.0
@export var special_v2_min_downstream: int = 2
@export var special_v2_height_tiebreak: float = 0.1
@export var special_v2_throw_tolerance_m: float = 3.0
@export var special_v2_paintball_min_height_m: float = 1.0
@export var special_v2_threat_gap_m: float = 6.0
## Slack (m) added to a placed special's effect radius when snapping it to own land.
@export var special_v2_effect_margin_m: float = 1.0

## once a bot's plan is ready it holds the piece for a seeded random delay in
## [release_delay_min_s, release_delay_max_s] seconds before releasing, so bots no longer all
## drop on the same tick. The hold is always cut short so the release lands at least
## release_safety_margin_s before the block timer expires (the host's forced auto-drop).
@export var release_delay_min_s: float = 0.0
@export var release_delay_max_s: float = 1.5
@export var release_safety_margin_s: float = 0.5

## short block timers. The reaction delay and the V2 think deadline are clamped so the
## plan is ready timer_plan_margin_s before the host's auto-drop and the bot keeps at least
## timer_min_think_s of think time (the reaction delay never eats it). Normal timers are unaffected.
@export var timer_plan_margin_s: float = 0.5
@export var timer_min_think_s: float = 0.1

## Returns the profile for `difficulty`; NORMAL (and any out-of-range value) falls back to `normal`
## rather than failing, so a stale/corrupt wire value never leaves a bot with a null profile.
func profile_for(difficulty: MatchConfig.AiDifficulty) -> BotDifficultyProfile:
	match difficulty:
		MatchConfig.AiDifficulty.EASY:
			return easy
		MatchConfig.AiDifficulty.HARD:
			return hard
		_:
			return normal
