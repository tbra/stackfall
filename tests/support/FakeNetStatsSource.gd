class_name FakeNetStatsSource
extends NetStatsSource
## Test double: set `stats` and read the `set_simulation` call log.

var stats: NetStats = NetStats.new()
var simulation_calls: Array[Vector2] = []  # (lag_ms, loss) per call


func read() -> NetStats:
	return stats


func set_simulation(lag_ms: float, loss: float) -> void:
	simulation_calls.append(Vector2(lag_ms, loss))
