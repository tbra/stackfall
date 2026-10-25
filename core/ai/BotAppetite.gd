class_name BotAppetite
extends RefCounted
## A bot's risk appetite (0 cautious .. 1 bold), drawn once per match. Interface stub: every method
## returns the pre-appetite behaviour (also what shipped() keeps for views built outside the controller).

const SHIPPED_TUNING: BotAppetiteTuning = preload("res://config/bots/bot_appetite_tuning.tres")

## 0 cautious .. 1 bold.
var value: float = 0.0
var _tuning: BotAppetiteTuning = SHIPPED_TUNING


func _init(p_value: float = 0.0, p_tuning: BotAppetiteTuning = null) -> void:
	value = p_value
	if p_tuning != null:
		_tuning = p_tuning


## Inert instance: every method returns the pre-appetite behaviour.
static func shipped() -> BotAppetite:
	return BotAppetite.new()


## Draws an appetite from `rng` within the profile's appetite_range.
static func draw(_rng: RandomNumberGenerator, _profile: BotDifficultyProfile, tuning: BotAppetiteTuning = null) -> BotAppetite:
	return BotAppetite.new(0.0, tuning)


## How many tall stack orientations to offer, given the mode's base count.
func tall_variants(mode: int, base: int) -> int:
	return base if mode == MatchConfig.GameMode.REACH_THE_SKY else 0


## True when tower tops that fail the stability check are skipped.
func skips_unsound_tops(mode: int) -> bool:
	return mode == MatchConfig.GameMode.REACH_THE_SKY


## Probability (0..1) that a site with stability `slack` topples.
func fall_probability(slack: float, _mode: int) -> float:
	return 0.0 if slack > 0.0 else 1.0


## Extra TIP risk of a candidate top `top_m` metres high; >= 0.
func height_risk(_top_m: float, _mode: int) -> float:
	return 0.0
