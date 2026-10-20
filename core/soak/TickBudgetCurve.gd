class_name TickBudgetCurve
extends RefCounted
## Physics-tick cost against tracked body count (SOAK_PLAN section 7.2): one fixed-bucket
## histogram per body-count band, so recording a tick is O(1) and a p99 needs no sample list.
## A tick belongs to a band when its body count is within `half_width_fraction` of the band
## centre. Pure: no scene tree.

## Cost, in milliseconds, above which a tick counts as over budget.
var budget_ms: float = 0.0

var _bands: PackedInt32Array = PackedInt32Array()


func _init(
	bands: PackedInt32Array,
	_half_width_fraction: float,
	over_budget_ms: float,
	_bucket_ms: float,
	_max_ms: float
) -> void:
	_bands = bands
	budget_ms = over_budget_ms


## Adds one physics tick that cost `tick_ms` while `bodies` blocks were tracked.
func record(_tick_ms: float, _bodies: int) -> void:
	pass


## Statistics of one band: {ticks: int, bodies_mean: int, p50_ms: float, p99_ms: float,
## max_ms: float, over: int}. A band that saw no tick has every value zero.
func band_stats(_band: int) -> Dictionary:
	return {}


## The band centres, in the order given at construction.
func bands() -> PackedInt32Array:
	return _bands
