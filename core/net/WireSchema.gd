class_name WireSchema
extends RefCounted
## One receive guard for flat network dictionaries (Bontago-fca.36.6). Pure
## statics: no nodes, no engine state, so every net validates through the same
## code and the same unit tests.
##
## A schema maps each key to a field spec built with int_field(), number_field(),
## string_field() or int_array_field(). sanitize() accepts a payload only when it
## is a Dictionary with EXACTLY the schema's keys, every value has the spec's
## type, every number is finite and inside the spec's limits. The result holds
## normalised values (int -> int, number -> float, string -> String,
## int array -> PackedInt32Array); anything else returns {} (reject). Cross-field
## rules stay with the caller, which runs them on the sanitized result.
##
## Numbers accept int or float (never bool/String); ints accept only TYPE_INT.
## Limits are inclusive unless a `gt` (strictly greater than) is given.

enum Kind { INT, NUMBER, STRING, INT_ARRAY }

## Full 64-bit range: an int field without explicit limits.
const INT_MIN: int = -9223372036854775807 - 1
const INT_MAX: int = 9223372036854775807


static func int_field(min_value: int = INT_MIN, max_value: int = INT_MAX) -> Dictionary:
	return {"kind": Kind.INT, "min": float(min_value), "max": float(max_value), "imin": min_value, "imax": max_value}


static func number_field(min_value: float = -INF, max_value: float = INF, greater_than: float = -INF) -> Dictionary:
	return {"kind": Kind.NUMBER, "min": min_value, "max": max_value, "gt": greater_than}


## String or StringName; `max_length` caps the character count.
static func string_field(max_length: int) -> Dictionary:
	return {"kind": Kind.STRING, "max_len": max_length}


## PackedInt32Array capped at `max_size` elements.
static func int_array_field(max_size: int) -> Dictionary:
	return {"kind": Kind.INT_ARRAY, "max_size": max_size}


## The sanitized copy of `payload`, or {} when it does not match `schema` exactly.
static func sanitize(payload: Variant, schema: Dictionary) -> Dictionary:
	if not (payload is Dictionary):
		return {}
	var data: Dictionary = payload
	if data.size() != schema.size():
		return {}
	var out: Dictionary = {}
	for key: Variant in schema:
		if not data.has(key):
			return {}
		var value: Variant = _check(data[key], schema[key] as Dictionary)
		if typeof(value) == TYPE_NIL:
			return {}
		out[key] = value
	return out


## The normalised value or null when `value` violates `spec`.
static func _check(value: Variant, spec: Dictionary) -> Variant:
	var kind: int = int(spec["kind"])
	var value_type: int = typeof(value)
	if kind == Kind.INT:
		if value_type != TYPE_INT:
			return null
		var whole: int = value
		if whole < int(spec["imin"]) or whole > int(spec["imax"]):
			return null
		return whole
	if kind == Kind.NUMBER:
		if value_type != TYPE_INT and value_type != TYPE_FLOAT:
			return null
		var number: float = float(value)
		if not is_finite(number):
			return null
		if number < float(spec["min"]) or number > float(spec["max"]) or number <= float(spec["gt"]):
			return null
		return number
	if kind == Kind.STRING:
		if value_type != TYPE_STRING and value_type != TYPE_STRING_NAME:
			return null
		var text: String = String(value)
		if text.length() > int(spec["max_len"]):
			return null
		return text
	if kind == Kind.INT_ARRAY:
		if value_type != TYPE_PACKED_INT32_ARRAY:
			return null
		var array: PackedInt32Array = value
		if array.size() > int(spec["max_size"]):
			return null
		return array
	return null
