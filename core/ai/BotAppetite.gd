class_name BotAppetite
extends RefCounted
## A bot's risk appetite (0 cautious .. 1 bold), drawn once per match. Applies in the modes the tuning
## covers; Reach the Sky and uncovered modes keep the pre-appetite behaviour, as does shipped().

const SHIPPED_TUNING: BotAppetiteTuning = preload("res://config/bots/bot_appetite_tuning.tres")

## 0 cautious .. 1 bold.
var value: float = 0.0
var _tuning: BotAppetiteTuning = SHIPPED_TUNING
var _inert: bool = false


func _init(p_value: float = 0.0, p_tuning: BotAppetiteTuning = null) -> void:
	value = p_value
	if p_tuning != null:
		_tuning = p_tuning


## Inert instance: every method returns the pre-appetite behaviour.
static func shipped() -> BotAppetite:
	var inert: BotAppetite = BotAppetite.new()
	inert._inert = true
	return inert


## Draws an appetite from `rng` within the profile's appetite_range.
## DECISION: uniform in the range (no bias toward either end), exactly one RNG call.
static func draw(rng: RandomNumberGenerator, profile: BotDifficultyProfile, tuning: BotAppetiteTuning = null) -> BotAppetite:
	var appetite_range: Vector2 = profile.appetite_range
	return BotAppetite.new(clampf(rng.randf_range(appetite_range.x, appetite_range.y), 0.0, 1.0), tuning)


## How many tall stack orientations to offer, given the mode's base count.
## DECISION: roundi rounds half up, so appetite 0.25 with a base of 2 already offers one.
func tall_variants(mode: int, base: int) -> int:
	if _is_sky(mode):
		return base
	return roundi(base * value) if _applies(mode) else 0


## True when tower tops that fail the stability check are skipped.
func skips_unsound_tops(mode: int) -> bool:
	if _is_sky(mode):
		return true
	return _applies(mode) and value < _tuning.unsound_top_skip_below


## Probability (0..1) that a site with stability `slack` topples.
func fall_probability(slack: float, mode: int) -> float:
	if slack > 0.0:
		return 0.0
	if not _applies(mode):
		return 1.0
	var depth: float = clampf(-slack / _tuning.unsound_band_m, 0.0, 1.0)
	return 1.0 - (1.0 - _tuning.unsound_fall_floor) * value * (1.0 - depth)


## Extra TIP risk of a candidate top `top_m` metres high; >= 0.
func height_risk(top_m: float, mode: int) -> float:
	if not _applies(mode):
		return 0.0
	var h_frac: float = clampf((top_m - _tuning.height_risk_start_m) / _tuning.height_risk_span_m, 0.0, 1.0)
	return _tuning.height_risk_max * h_frac * (1.0 - _tuning.height_risk_relief * value)


## DECISION: Reach the Sky ignores appetite (its objective is height), whatever the tuning flags say.
func _is_sky(mode: int) -> bool:
	return mode == MatchConfig.GameMode.REACH_THE_SKY


## True when appetite shapes behaviour in `mode`: a drawn appetite, not Sky, and the mode is covered.
func _applies(mode: int) -> bool:
	return not _inert and not _is_sky(mode) and _tuning.covers(mode)
