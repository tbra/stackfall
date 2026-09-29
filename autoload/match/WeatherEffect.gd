class_name WeatherEffect
extends RefCounted
## Host-side physics hook a weather implements (Bontago-22y.10). Wind, Rain
## and Snow packages subclass this and name the script in their
## config/weather/*.tres `effect_script`. Clients never run one: they only
## present.
##
## Contract:
## - apply(intensity) is called whenever the ramped intensity 0..1 changes
##   (including the first call of an event) so an effect can set state that
##   scales with intensity (e.g. friction).
## - tick(delta, intensity) runs every physics frame while the event is live
##   (e.g. wind impulses).
## - restore() MUST return all physics the effect touched to its baseline. It
##   is called when the event ends, the match ends or aborts, and when the
##   host tears the session down, and it must be safe to call twice and after
##   the world's nodes were freed.

var match_ref: MatchAutoload = null
var tuning: WeatherTuning = null


func bind(match_owner: MatchAutoload, weather_tuning: WeatherTuning) -> void:
	match_ref = match_owner
	tuning = weather_tuning


func apply(_intensity: float) -> void:
	pass


func tick(_delta: float, _intensity: float) -> void:
	pass


func restore() -> void:
	pass
