class_name PerfProbe
extends RefCounted
## Bontago-470.8: additive microsecond probes for the F1 detailed overlay and
## the perf CSV. Wrap an existing call:
##   var t: int = PerfProbe.start()
##   thing.tick(delta)
##   PerfProbe.stop(&"weather", t)
## start() returns 0 (and stop() returns immediately) unless debug mode
## enabled probing (DebugMode), so the cost for players is one static read and
## one integer compare per site. game/PerfSampler.gd drains the totals.

static var enabled: bool = false

static var _usec: Dictionary[StringName, int] = {}
static var _calls: Dictionary[StringName, int] = {}
static var _peak: Dictionary[StringName, int] = {}


static func start() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func stop(key: StringName, started: int) -> void:
	if started == 0:
		return
	var elapsed: int = Time.get_ticks_usec() - started
	_usec[key] = int(_usec.get(key, 0)) + elapsed
	_calls[key] = int(_calls.get(key, 0)) + 1
	if elapsed > int(_peak.get(key, 0)):
		_peak[key] = elapsed


## Returns {key: {"usec": total, "calls": n, "peak_usec": worst single call}}
## since the previous drain, and resets the accumulators.
static func drain() -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in _usec.keys():
		result[key] = {
			"usec": int(_usec[key]),
			"calls": int(_calls.get(key, 0)),
			"peak_usec": int(_peak.get(key, 0)),
		}
	_usec.clear()
	_calls.clear()
	_peak.clear()
	return result
