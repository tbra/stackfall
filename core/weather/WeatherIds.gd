class_name WeatherIds
extends RefCounted
## The one owner of the weather event ids the code branches on (Bontago-fca.36.6).
## They match the `id` of each config/weather/*.tres definition.
# DECISION: a const holder in core/weather, not WeatherCeilingTuning.storm_id: the
# ids are identity, not tunables, and net/ + autoload/ code must read them without
# loading a tuning resource. The tuning's exported ids default to these consts.

const RAIN: StringName = &"rain"
const SNOW: StringName = &"snow"
const STORM: StringName = &"storm"
