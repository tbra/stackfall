class_name BotThinkCostReport
extends RefCounted
## Bontago-1t5.62: one window of Hard-bot think cost records (a slot's, or every bot's). Aggregates
## BotThink.stats_record() plus the controller's snapshot / frame timings into mean / p50 / p95 / max per
## phase, the PROBE split, the work outside BotThink, the think latency and the per-frame bot time, and
## renders `BOT_THINK_COST ...` lines plus a short human table. Pure: no scene tree. `capacity` > 0 keeps a
## rolling window (the live overlay); 0 keeps everything (the headless report).

const TAG: String = "BOT_THINK_COST"
const PHASE_COUNT: int = BotThink.Phase.DONE
const PHASE_NAMES: PackedStringArray = ["STACK", "PLAN", "SITES", "FILL", "PROBE", "RANK", "MEASURE", "PICK"]
const PERCENT: float = 100.0
const US_PER_MS: float = 1000.0
const SHIPPED_TUNING: BotThinkCostTuning = preload("res://config/bot_think_cost.tres")

var tuning: BotThinkCostTuning = SHIPPED_TUNING
var scenario: String = ""
var capacity: int = 0

var _records: Array[Dictionary] = []
var _frame_us: PackedInt64Array = PackedInt64Array()
## Ring write positions once a window is full (no array slicing per frame).
var _record_head: int = 0
var _frame_head: int = 0


func _init(label: String = "", window_thinks: int = 0) -> void:
	scenario = label
	capacity = window_thinks


func think_count() -> int:
	return _records.size()


func frame_count() -> int:
	return _frame_us.size()


## True once at least one think is recorded ("no data" otherwise, e.g. on a client).
func has_data() -> bool:
	return not _records.is_empty()


## One finished think. Keys: phase_us / phase_units (PackedInt64Array per Phase), total_us, probe_call_us,
## probe_calls (BotThink.stats_record()), plus the controller's build_us, apply_us, other_us (its
## per-tick work outside BotThink while THINKING), ticks and latency_us.
func add_think(record: Dictionary) -> void:
	if capacity > 0 and _records.size() >= capacity:
		_records[_record_head] = record
		_record_head = (_record_head + 1) % capacity
	else:
		_records.append(record)


## One bot's whole physics tick (every state), in microseconds.
func add_frame(us: int) -> void:
	var frame_cap: int = capacity * maxi(tuning.frames_per_think, 1)
	if capacity > 0 and _frame_us.size() >= frame_cap:
		_frame_us[_frame_head] = us
		_frame_head = (_frame_head + 1) % frame_cap
	else:
		_frame_us.append(us)


func clear() -> void:
	_records.clear()
	_frame_us = PackedInt64Array()
	_record_head = 0
	_frame_head = 0


## Column of a scalar key over the records.
func _column(key: String) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for record: Dictionary in _records:
		out.append(int(record.get(key, 0)))
	return out


## Column of one phase of the per-phase arrays ("phase_us" / "phase_units").
func _phase_column(key: String, phase: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for record: Dictionary in _records:
		var values: PackedInt64Array = record.get(key, PackedInt64Array()) as PackedInt64Array
		out.append(values[phase] if phase < values.size() else 0)
	return out


static func _sum(values: PackedInt64Array) -> int:
	var total: int = 0
	for v: int in values:
		total += v
	return total


static func _mean(values: PackedInt64Array) -> float:
	return float(_sum(values)) / float(values.size()) if values.size() > 0 else 0.0


static func _max(values: PackedInt64Array) -> int:
	var best: int = 0
	for v: int in values:
		best = maxi(best, v)
	return best


## Nearest-rank percentile (`fraction` of 0..1).
static func percentile(values: PackedInt64Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	var rank: int = clampi(ceili(fraction * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return float(sorted[rank])


## Per-phase numbers: {name, total_us, mean_us, p50_us, p95_us, max_us, units, us_per_unit, share_pct}
## (units = work units per think; share = percent of the summed phase time).
func phase_stats(phase: int) -> Dictionary:
	var grand: int = 0
	for i: int in range(PHASE_COUNT):
		grand += _sum(_phase_column("phase_us", i))
	var us: PackedInt64Array = _phase_column("phase_us", phase)
	var units: PackedInt64Array = _phase_column("phase_units", phase)
	var total: int = _sum(us)
	var units_total: int = _sum(units)
	return {
		"name": PHASE_NAMES[phase],
		"total_us": total,
		"mean_us": _mean(us),
		"p50_us": percentile(us, tuning.median_fraction),
		"p95_us": percentile(us, tuning.high_fraction),
		"max_us": float(_max(us)),
		"units": _mean(units),
		"us_per_unit": float(total) / float(units_total) if units_total > 0 else 0.0,
		"share_pct": PERCENT * float(total) / float(grand) if grand > 0 else 0.0,
	}


## PROBE split: {call_mean_us (physics queries in the caller's callables), call_p95_us, rest_mean_us
## (statics, tip risk, load margin), calls_per_think, call_share_of_probe_pct}.
func probe_split() -> Dictionary:
	var call_us: PackedInt64Array = _column("probe_call_us")
	var call_mean: float = _mean(call_us)
	var probe_mean: float = phase_stats(BotThink.Phase.PROBE)["mean_us"] as float
	return {
		"call_mean_us": call_mean,
		"call_p95_us": percentile(call_us, tuning.high_fraction),
		"rest_mean_us": maxf(probe_mean - call_mean, 0.0),
		"calls_per_think": _mean(_column("probe_calls")),
		"call_share_of_probe_pct": PERCENT * call_mean / probe_mean if probe_mean > 0.0 else 0.0,
	}


## Work outside BotThink: {build_mean_us, build_p95_us (BotWorldView.build), apply_mean_us (weather / stack
## / specials snapshot parts), other_tick_mean_us (the bot's other per-tick work while THINKING, per think),
## think_step_mean_us (BotThink step / complete wall time per think)}.
func outside_stats() -> Dictionary:
	var build: PackedInt64Array = _column("build_us")
	return {
		"build_mean_us": _mean(build),
		"build_p95_us": percentile(build, tuning.high_fraction),
		"apply_mean_us": _mean(_column("apply_us")),
		"other_tick_mean_us": _mean(_column("other_us")),
		"think_step_mean_us": _mean(_column("total_us")),
	}


## Latency: {ticks_mean, ticks_p95, ticks_max, wall_ms_mean, wall_ms_p95, wall_ms_max} (piece received to decision).
func latency_stats() -> Dictionary:
	var ticks: PackedInt64Array = _column("ticks")
	var wall: PackedInt64Array = _column("latency_us")
	return {
		"ticks_mean": _mean(ticks),
		"ticks_p95": percentile(ticks, tuning.high_fraction),
		"ticks_max": float(_max(ticks)),
		"wall_ms_mean": _mean(wall) / US_PER_MS,
		"wall_ms_p95": percentile(wall, tuning.high_fraction) / US_PER_MS,
		"wall_ms_max": float(_max(wall)) / US_PER_MS,
	}


## Per bot frame: {mean_ms, p99_ms, max_ms}.
func frame_stats() -> Dictionary:
	return {
		"mean_ms": _mean(_frame_us) / US_PER_MS,
		"p99_ms": percentile(_frame_us, tuning.tail_fraction) / US_PER_MS,
		"max_ms": float(_max(_frame_us)) / US_PER_MS,
	}


## Phase indices sorted by total time, most expensive first.
func ranking() -> PackedInt32Array:
	var totals: Array[int] = []
	var order: Array[int] = []
	for i: int in range(PHASE_COUNT):
		totals.append(_sum(_phase_column("phase_us", i)))
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return totals[a] > totals[b])
	return PackedInt32Array(order)


func render_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var tag: String = "%s scenario=%s" % [TAG, scenario]
	lines.append("%s summary thinks=%d frames=%d" % [tag, think_count(), frame_count()])
	for i: int in range(PHASE_COUNT):
		var s: Dictionary = phase_stats(i)
		lines.append("%s phase=%s mean_us=%.1f p50_us=%.1f p95_us=%.1f max_us=%.0f units=%.2f us_per_unit=%.2f share_pct=%.2f" % [
			tag, s["name"], s["mean_us"], s["p50_us"], s["p95_us"], s["max_us"], s["units"], s["us_per_unit"], s["share_pct"],
		])
	var p: Dictionary = probe_split()
	lines.append("%s probe_split call_mean_us=%.1f call_p95_us=%.1f rest_mean_us=%.1f calls_per_think=%.2f call_share_of_probe_pct=%.2f" % [
		tag, p["call_mean_us"], p["call_p95_us"], p["rest_mean_us"], p["calls_per_think"], p["call_share_of_probe_pct"],
	])
	var o: Dictionary = outside_stats()
	lines.append("%s outside build_mean_us=%.1f build_p95_us=%.1f apply_mean_us=%.1f other_tick_mean_us_per_think=%.1f think_step_mean_us=%.1f" % [
		tag, o["build_mean_us"], o["build_p95_us"], o["apply_mean_us"], o["other_tick_mean_us"], o["think_step_mean_us"],
	])
	var l: Dictionary = latency_stats()
	lines.append("%s latency ticks_mean=%.2f ticks_p95=%.1f ticks_max=%.0f wall_ms_mean=%.2f wall_ms_p95=%.2f wall_ms_max=%.2f" % [
		tag, l["ticks_mean"], l["ticks_p95"], l["ticks_max"], l["wall_ms_mean"], l["wall_ms_p95"], l["wall_ms_max"],
	])
	var f: Dictionary = frame_stats()
	lines.append("%s frame bot_ms_mean=%.4f bot_ms_p99=%.4f bot_ms_max=%.4f" % [tag, f["mean_ms"], f["p99_ms"], f["max_ms"]])
	lines.append(ranking_line())
	return lines


func ranking_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for phase: int in ranking():
		parts.append("%s=%.1f%%" % [PHASE_NAMES[phase], phase_stats(phase)["share_pct"] as float])
	return "%s scenario=%s ranking %s" % [TAG, scenario, ">".join(parts)]


## A short human table (every line starts with a space, so it cannot match the machine tag).
func render_table() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(" [%s] %d thinks   phase     mean_us   p50_us   p95_us   max_us    units  us/unit  share%%" % [scenario, think_count()])
	for i: int in range(PHASE_COUNT):
		var s: Dictionary = phase_stats(i)
		lines.append(" %-8s %10.1f %8.1f %8.1f %8.0f %8.2f %8.2f %6.1f" % [
			s["name"], s["mean_us"], s["p50_us"], s["p95_us"], s["max_us"], s["units"], s["us_per_unit"], s["share_pct"],
		])
	return lines
