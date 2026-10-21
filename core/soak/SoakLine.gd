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


## SOAK_VIOLATION: one broken invariant at a sample.
static func violation(
	_v: SoakCheck.Violation, _role: StringName, _epoch: int, _wall_ms: int, _match_time: float
) -> String:
	return ""


## SOAK_SAMPLE: the per-epoch summary; `fields` are the keys after `role epoch wall_ms`.
static func sample(_role: StringName, _epoch: int, _wall_ms: int, _fields: Dictionary) -> String:
	return ""


## SOAK_BODY: one body of a dump.
static func body(
	_role: StringName,
	_epoch: int,
	_id: int,
	_position: Vector3,
	_rotation: Quaternion,
	_at_rest: bool
) -> String:
	return ""


## SOAK_FUZZ: one fuzz intent the client sent; `kind` is the SoakFuzzPlan.Kind name.
static func fuzz(_role: StringName, _seq: int, _kind: StringName, _slot: int) -> String:
	return ""


## SOAK_CURVE: one band of the tick-cost curve, from TickBudgetCurve.band_stats().
static func curve(_role: StringName, _band: int, _stats: Dictionary, _budget_ms: float) -> String:
	return ""


## SOAK_CONFIG: every SoakConfig field, so the offline report reads the tolerances of the run.
static func config_line(_role: StringName, _scenario: StringName, _config: SoakConfig) -> String:
	return ""


## SOAK_END: the run summary; `fields` are the keys after `role`.
static func end(_role: StringName, _fields: Dictionary) -> String:
	return ""
