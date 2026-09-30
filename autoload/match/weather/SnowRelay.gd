class_name SnowRelay
extends RefCounted
## Hand-off from the host's SnowEffect to net/SnowNet.gd (Bontago-22y.6).
##
## DECISION (autoload/match/weather/SnowRelay.gd): a tiny process-wide relay
## instead of a new Events signal, so the shared autoload/Events.gd (edited by
## several parallel packages) gains nothing. The effect is a RefCounted owned
## by MatchWeather and SnowNet is a node under MatchNet; neither can reach the
## other without a node path, and this keeps the direction one-way (effect ->
## relay -> net).

signal state_published(state: Dictionary)

static var hub: SnowRelay = null

## The most recent state published (for a late joiner); {} when none.
var last_state: Dictionary = {}


static func instance() -> SnowRelay:
	if hub == null:
		hub = SnowRelay.new()
	return hub


func publish(state: Dictionary) -> void:
	last_state = state
	state_published.emit(state)


## True when `state` carries no snow at all.
static func is_empty_state(state: Dictionary) -> bool:
	if state.is_empty():
		return true
	var b: Variant = state.get("b")
	var d: Variant = state.get("d")
	return (b is PackedInt32Array and (b as PackedInt32Array).is_empty()) \
		and (d is PackedInt32Array and (d as PackedInt32Array).is_empty()) and int(state.get("c", 0)) == 0
