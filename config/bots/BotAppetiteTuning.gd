class_name BotAppetiteTuning
extends Resource
## Tunables of BotAppetite (a bot's per-match risk appetite for tall and leaning towers).

## Game modes where appetite applies (bit = MatchConfig.GameMode value); the Reach the Sky bit is
## ignored because BotAppetite keeps that mode's shipped height objective. Default: every other mode.
@export_flags("Classic", "Capture the Flag", "Elimination", "Reach the Sky", "Domination") var appetite_modes: int = 23
## A covered-mode bot with appetite below this skips tower tops that fail the stability check.
@export var unsound_top_skip_below: float = 0.5
## Fall probability of a barely unsound site (slack 0) for the boldest bot.
@export var unsound_fall_floor: float = 0.3
## Depth of unsoundness (metres of negative slack) at which a site is certain to fall.
@export var unsound_band_m: float = 0.15
## Candidate top height (metres) above which the height risk starts.
@export var height_risk_start_m: float = 3.0
## Metres above the start over which the height risk ramps to its maximum.
@export var height_risk_span_m: float = 12.0
## Height risk (TIP units) of the highest tops for a fully cautious bot.
@export var height_risk_max: float = 4.0
## Share (0..1) of the height risk a fully bold bot does not pay.
@export var height_risk_relief: float = 0.75


## True when appetite applies in `mode`.
func covers(mode: int) -> bool:
	return ((appetite_modes >> mode) & 1) == 1
