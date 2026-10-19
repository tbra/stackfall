class_name WireLimits
extends RefCounted
## Wire id, length and arity checks whose limits live in NetConfig. Pure: no scene tree, no
## autoloads. A value that fails here is dropped by the caller, never trusted or repaired.

const ASCII_UPPER_FIRST: int = 65
const ASCII_UPPER_LAST: int = 90
const ASCII_LOWER_FIRST: int = 97
const ASCII_LOWER_LAST: int = 122
const ASCII_DIGIT_FIRST: int = 48
const ASCII_DIGIT_LAST: int = 57
const ASCII_UNDERSCORE: int = 95


## True when a special id received from the wire is shaped like one of ours: non-empty, at most
## `config.special_id_max_length` characters, and only [A-Za-z0-9_]. A plain character scan, as no
## RegEx is used elsewhere in the codebase and the id is short.
static func special_id_ok(id: StringName, config: NetConfig) -> bool:
	var text: String = String(id)
	if text.is_empty() or text.length() > config.special_id_max_length:
		return false
	for i: int in range(text.length()):
		var c: int = text.unicode_at(i)
		var is_upper: bool = c >= ASCII_UPPER_FIRST and c <= ASCII_UPPER_LAST
		var is_lower: bool = c >= ASCII_LOWER_FIRST and c <= ASCII_LOWER_LAST
		var is_digit: bool = c >= ASCII_DIGIT_FIRST and c <= ASCII_DIGIT_LAST
		if not (is_upper or is_lower or is_digit or c == ASCII_UNDERSCORE):
			return false
	return true


## `reason` cut to the configured longest refusal reason.
static func reject_reason_clamped(reason: String, config: NetConfig) -> String:
	return reason.left(config.reject_reason_max_length)


## `seconds` clamped to `[0, config.cat_duration_max_s]`. A non-finite value comes back as 0.0, which
## every caller already refuses (a cat effect must last longer than zero).
static func cat_duration_clamped(seconds: float, config: NetConfig) -> float:
	if not is_finite(seconds):
		return 0.0
	return clampf(seconds, 0.0, config.cat_duration_max_s)


## True when `args` matches `shape` (a MatchWireEvents row, one Variant.Type per argument): the
## same arity, then a matching typeof per entry. Two leniencies mirror what the applier already
## accepted: an int satisfies TYPE_FLOAT, and String and StringName satisfy each other. TYPE_NIL
## in a row means "any type".
static func args_shape_ok(args: Array, shape: Array) -> bool:
	if args.size() != shape.size():
		return false
	for i: int in range(shape.size()):
		var want: int = int(shape[i])
		if want == TYPE_NIL:
			continue
		var got: int = typeof(args[i])
		if got == want:
			continue
		if want == TYPE_FLOAT and got == TYPE_INT:
			continue
		if (want == TYPE_STRING and got == TYPE_STRING_NAME) or (want == TYPE_STRING_NAME and got == TYPE_STRING):
			continue
		return false
	return true
