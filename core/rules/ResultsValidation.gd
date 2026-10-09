class_name ResultsValidation
extends RefCounted
## Pure wire validators for the two replicated match payloads (autoload
## decoupling S2a, STARTUP_COMPILE_PLAN B0a): the results payload and the mode
## state. net/MatchNet.gd and autoload/match/MatchStats.gd call these instead
## of naming MatchStats/ModeObjective, whose scripts pull in the objective
## subclasses. The old entry points (MatchStats.validate_results_payload,
## ModeObjective.validate_state and its clean_* helpers) stay as one-line
## forwards. The results schema itself is still owned by ResultsPayload.

const MAX_WIRE_KEYS: int = 16
const MAX_WIRE_STRING: int = 64


## Strictly re-types a results wire payload, or {} when malformed.
static func validate_results_payload(raw: Variant) -> Dictionary:
	return ResultsPayload.validate(raw)


## Strictly re-types a replicated mode state, or {} when malformed: mode_id
## must be a known GameMode, scores a bounded array of finite numbers,
## round_left a finite non-negative number, extra a scalar-only dictionary.
static func validate_mode_state(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	var mode: Variant = data.get("mode_id")
	if not (mode is int or mode is float) or not is_known_mode(int(mode)):
		return {}
	var scores: Array = clean_scores(data.get("scores"))
	if scores.size() == 1 and scores[0] == null:
		return {}
	var round_left: Variant = data.get("round_left", 0.0)
	if not (round_left is int or round_left is float) or not is_finite(float(round_left)) or float(round_left) < 0.0:
		return {}
	var extra: Variant = clean_scalars(data.get("extra", {}))
	if extra == null:
		return {}
	return {"mode_id": int(mode), "scores": scores, "extra": extra, "round_left": float(round_left)}


static func is_known_mode(mode: int) -> bool:
	return mode >= MatchConfig.GameMode.CLASSIC and mode <= MatchConfig.GameMode.DOMINATION


## Array of floats, or [null] as the malformed sentinel.
static func clean_scores(raw: Variant) -> Array:
	if not (raw is Array) or (raw as Array).size() > MatchConfig.PLAYER_COUNT_MAX:
		return [null]
	var out: Array = []
	for value: Variant in (raw as Array):
		if not (value is int or value is float) or not is_finite(float(value)):
			return [null]
		out.append(float(value))
	return out


## A copy of `raw` when it is a small dictionary of String keys mapped to
## int/float(finite)/bool/short String; null otherwise.
static func clean_scalars(raw: Variant) -> Variant:
	if not (raw is Dictionary) or (raw as Dictionary).size() > MAX_WIRE_KEYS:
		return null
	var out: Dictionary = {}
	for key: Variant in (raw as Dictionary):
		var value: Variant = (raw as Dictionary)[key]
		if not (key is String) or (key as String).length() > MAX_WIRE_STRING:
			return null
		if value is float:
			if not is_finite(value as float):
				return null
		elif value is String:
			if (value as String).length() > MAX_WIRE_STRING:
				return null
		elif not (value is int or value is bool):
			return null
		out[key] = value
	return out
