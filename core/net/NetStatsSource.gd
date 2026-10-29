class_name NetStatsSource
extends RefCounted
## Where the F3 panel gets its numbers. The base class is the null object: offline, all zero.


func read() -> NetStats:
	return NetStats.new()


func set_simulation(_lag_ms: float, _loss: float) -> void:
	pass
