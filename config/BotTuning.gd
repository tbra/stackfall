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
