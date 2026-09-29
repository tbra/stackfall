class_name WeatherScheduleTuning
extends Resource
## Host schedule numbers for weather events (Bontago-22y.10, owner decision
## Bontago-22y.14: weather is a random EVENT, calm most of the time, one
## weather at a time). Loaded as config/weather_schedule.tres.
##
## Timeline per match: initial calm -> [ramp-in, hold, ramp-out] event ->
## calm gap -> event -> ... Ramp lengths and the hold range are per weather
## (WeatherTuning); the calm numbers are global and live here.

## Calm seconds before the first event of a match.
@export var first_delay_s: float = 45.0
## Calm gap between one event finishing its ramp-out and the next starting,
## drawn uniformly from this range by the host's seeded schedule.
@export var gap_min_s: float = 60.0
@export var gap_max_s: float = 150.0
## Changing mode: do not draw the type that just ended (when another type
## exists).
@export var avoid_repeat_type: bool = true
## A presented intensity change smaller than this is not re-announced.
@export var intensity_epsilon: float = 0.001
## Longest a wire time may claim; anything above is malformed.
@export var wire_max_time_s: float = 3600.0
