class_name TickBudgetCurve
extends RefCounted
## Physics-tick cost against tracked body count (SOAK_PLAN section 7.2): one fixed-bucket
## histogram per body-count band, so recording a tick is O(1) and a p99 needs no sample list.
## A tick belongs to a band when its body count is within `half_width_fraction` of the band
## centre. Pure: no scene tree.

## Quantile ranks reported by band_stats().
const _P50: float = 0.5
const _P99: float = 0.99

## Cost, in milliseconds, above which a tick counts as over budget.
var budget_ms: float = 0.0

var _bands: PackedInt32Array = PackedInt32Array()
var _half_width_fraction: float = 0.0
var _bucket_ms: float = 0.0
var _bucket_count: int = 1
# Per band, in `_bands` order: the histogram and the running totals.
var _histograms: Array[PackedInt32Array] = []
var _ticks: PackedInt32Array = PackedInt32Array()
var _over: PackedInt32Array = PackedInt32Array()
var _body_sums: PackedInt64Array = PackedInt64Array()
var _peak_ms: PackedFloat64Array = PackedFloat64Array()


## `bucket_ms` is the histogram resolution and `max_ms` the cost from which every tick lands in the
## last bucket, so a histogram holds ceil(max_ms / bucket_ms) buckets.
func _init(
	bands: PackedInt32Array,
	half_width_fraction: float,
	over_budget_ms: float,
	bucket_ms: float,
	max_ms: float
) -> void:
	_bands = bands
	_half_width_fraction = half_width_fraction
	budget_ms = over_budget_ms
	_bucket_ms = bucket_ms
	_bucket_count = maxi(ceili(max_ms / bucket_ms), 1)
	for _band: int in bands:
		var histogram: PackedInt32Array = PackedInt32Array()
		histogram.resize(_bucket_count)
		_histograms.append(histogram)
	_ticks.resize(bands.size())
	_over.resize(bands.size())
	_body_sums.resize(bands.size())
	_peak_ms.resize(bands.size())


## Adds one physics tick that cost `tick_ms` while `bodies` blocks were tracked. A tick counts in
## every band whose centre is within `half_width_fraction` of `bodies` (inclusive).
func record(tick_ms: float, bodies: int) -> void:
	var bucket: int = clampi(int(tick_ms / _bucket_ms), 0, _bucket_count - 1)
	for index: int in _bands.size():
		var centre: float = float(_bands[index])
		if absf(float(bodies) - centre) > _half_width_fraction * centre:
			continue
		_histograms[index][bucket] += 1
		_ticks[index] += 1
		_body_sums[index] += bodies
		_peak_ms[index] = maxf(_peak_ms[index], tick_ms)
		if tick_ms > budget_ms:
			_over[index] += 1


## Statistics of one band: {ticks: int, bodies_mean: int, p50_ms: float, p99_ms: float,
## max_ms: float, over: int}. A band that saw no tick has every value zero. A percentile is the
## upper edge of the bucket holding that rank, capped at the largest tick seen, so it never
## under-reports against a budget and a constant cost reads back exactly.
func band_stats(band: int) -> Dictionary:
	var stats: Dictionary = {
		"ticks": 0, "bodies_mean": 0, "p50_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0, "over": 0,
	}
	var index: int = _bands.find(band)
	if index < 0 or _ticks[index] == 0:
		return stats
	var ticks: int = _ticks[index]
	stats["ticks"] = ticks
	stats["bodies_mean"] = roundi(float(_body_sums[index]) / float(ticks))
	stats["max_ms"] = _peak_ms[index]
	stats["over"] = _over[index]
	stats["p50_ms"] = _percentile(index, _P50)
	stats["p99_ms"] = _percentile(index, _P99)
	return stats


## The band centres, in the order given at construction.
func bands() -> PackedInt32Array:
	return _bands


func _percentile(index: int, quantile: float) -> float:
	var rank: int = maxi(ceili(quantile * float(_ticks[index])), 1)
	var histogram: PackedInt32Array = _histograms[index]
	var seen: int = 0
	for bucket: int in _bucket_count:
		seen += histogram[bucket]
		if seen >= rank:
			return minf(float(bucket + 1) * _bucket_ms, _peak_ms[index])
	return _peak_ms[index]
