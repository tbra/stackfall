class_name SoakLine
extends RefCounted
## The only place a soak log line is formatted (SOAK_PLAN section 7.1); the golden examples are
## tests/unit/soak/fixtures/soak_lines.txt and tools/ parses the same text.
##
## A line is a tag, then space-separated `key=value` tokens with no space inside a value (a
## space in free text becomes `_`). `role` is the first key, except SOAK_VIOLATION, which leads
## with `inv`. A value may itself contain `=` (`detail=owner=3`), so a parser splits each token
## on its first `=`. Values: ints plain, floats `%.4f`, bools 0 or 1, a Vector3 `x,y,z`, a
## Quaternion `x,y,z,w`, an array `a;b;c`, a Dictionary `k:v;k:v` in key order. The keys after
## `role epoch wall_ms` in SOAK_SAMPLE, and after `role` in SOAK_END, are sorted. SOAK_CONFIG
## lists every SoakConfig field in declaration order under its own name.


const _TAG_VIOLATION: String = "SOAK_VIOLATION"
const _TAG_SAMPLE: String = "SOAK_SAMPLE"
const _TAG_BODY: String = "SOAK_BODY"
const _TAG_FUZZ: String = "SOAK_FUZZ"
const _TAG_CURVE: String = "SOAK_CURVE"
const _TAG_CONFIG: String = "SOAK_CONFIG"
const _TAG_END: String = "SOAK_END"
const _FLOAT: String = "%.4f"
const _LIST_SEP: String = ";"
const _PAIR_SEP: String = ":"
const _COMPONENT_SEP: String = ","
const _WHITESPACE: PackedStringArray = [" ", "	", "
", ""]


## SOAK_VIOLATION: one broken invariant at a sample.
static func violation(
	v: SoakCheck.Violation, role: StringName, epoch: int, wall_ms: int, match_time: float
) -> String:
	return _line(_TAG_VIOLATION, [
		["inv", v.invariant], ["role", role], ["epoch", epoch], ["wall_ms", wall_ms],
		["mt", match_time], ["sev", v.severity], ["subject", v.subject], ["value", v.value],
		["limit", v.limit], ["detail", v.detail],
	])


## SOAK_SAMPLE: the per-epoch summary; `fields` are the keys after `role epoch wall_ms`.
static func sample(role: StringName, epoch: int, wall_ms: int, fields: Dictionary) -> String:
	return _line(_TAG_SAMPLE, [["role", role], ["epoch", epoch], ["wall_ms", wall_ms]]
		+ _sorted_pairs(fields))


## SOAK_BODY: one body of a dump.
static func body(
	role: StringName,
	epoch: int,
	id: int,
	position: Vector3,
	rotation: Quaternion,
	at_rest: bool
) -> String:
	return _line(_TAG_BODY, [
		["role", role], ["epoch", epoch], ["id", id], ["p", position], ["q", rotation],
		["rest", at_rest],
	])


## SOAK_FUZZ: one fuzz intent the client sent; `kind` is the SoakFuzzPlan.Kind name.
static func fuzz(role: StringName, seq: int, kind: StringName, slot: int) -> String:
	return _line(_TAG_FUZZ, [["role", role], ["seq", seq], ["kind", kind], ["slot", slot]])


## SOAK_CURVE: one band of the tick-cost curve, from TickBudgetCurve.band_stats().
static func curve(role: StringName, band: int, stats: Dictionary, budget_ms: float) -> String:
	return _line(_TAG_CURVE, [
		["role", role], ["band", band], ["bodies_mean", stats["bodies_mean"]],
		["ticks", stats["ticks"]], ["p50_ms", stats["p50_ms"]], ["p99_ms", stats["p99_ms"]],
		["max_ms", stats["max_ms"]], ["budget_ms", budget_ms], ["over", stats["over"]],
	])


## SOAK_CONFIG: every SoakConfig field, so the offline report reads the tolerances of the run.
static func config_line(role: StringName, scenario: StringName, config: SoakConfig) -> String:
	var pairs: Array = [["role", role], ["scenario", scenario]]
	for property: Dictionary in config.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var field: String = property["name"]
			pairs.append([field, config.get(field)])
	return _line(_TAG_CONFIG, pairs)


## SOAK_END: the run summary; `fields` are the keys after `role`.
static func end(role: StringName, fields: Dictionary) -> String:
	return _line(_TAG_END, [["role", role]] + _sorted_pairs(fields))


static func _sorted_pairs(fields: Dictionary) -> Array:
	var keys: Array = fields.keys()
	keys.sort()
	var pairs: Array = []
	for key: Variant in keys:
		pairs.append([key, fields[key]])
	return pairs


static func _line(tag: String, pairs: Array) -> String:
	var tokens: PackedStringArray = [tag]
	for pair: Array in pairs:
		tokens.append("%s=%s" % [pair[0], _value(pair[1])])
	return " ".join(tokens)


## One value as text with no whitespace in it (section 7.1 value rules).
static func _value(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "1" if v else "0"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return _FLOAT % v
		TYPE_VECTOR3:
			var p: Vector3 = v
			return _COMPONENT_SEP.join([_FLOAT % p.x, _FLOAT % p.y, _FLOAT % p.z])
		TYPE_QUATERNION:
			var q: Quaternion = v
			return _COMPONENT_SEP.join([_FLOAT % q.x, _FLOAT % q.y, _FLOAT % q.z, _FLOAT % q.w])
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			keys.sort()
			var pairs: PackedStringArray = []
			for key: Variant in keys:
				pairs.append(_value(key) + _PAIR_SEP + _value(d[key]))
			return _LIST_SEP.join(pairs)
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, 		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var items: PackedStringArray = []
			for item: Variant in v:
				items.append(_value(item))
			return _LIST_SEP.join(items)
		_:
			var text: String = str(v)
			for white: String in _WHITESPACE:
				text = text.replace(white, "_")
			return text
