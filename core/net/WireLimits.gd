class_name WireLimits
extends RefCounted
## Wire id, length and arity checks whose limits live in NetConfig. Stubs: the
## bodies arrive with the match-intent split.


## True when a special id received from the wire is within the configured length.
static func special_id_ok(id: StringName, config: NetConfig) -> bool:
	assert(false, "WireLimits.special_id_ok is a stub until M1")
	return false


## `reason` cut to the configured longest refusal reason.
static func reject_reason_clamped(reason: String, config: NetConfig) -> String:
	assert(false, "WireLimits.reject_reason_clamped is a stub until M1")
	return reason


## `seconds` clamped to the configured longest cat effect.
static func cat_duration_clamped(seconds: float, config: NetConfig) -> float:
	assert(false, "WireLimits.cat_duration_clamped is a stub until M1")
	return seconds


## True when `args` matches `shape` (a MatchWireEvents row): arity, then typeof per entry.
static func args_shape_ok(args: Array, shape: Array) -> bool:
	assert(false, "WireLimits.args_shape_ok is a stub until M1")
	return false
