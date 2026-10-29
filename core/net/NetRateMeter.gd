class_name NetRateMeter
extends RefCounted
## Turns a cumulative counter into a per-second rate over a sliding window.

var _window_s: float = 0.0


func _init(window_s: float) -> void:
	_window_s = window_s


## A total that goes down (new match) restarts the window.
func sample(_cumulative_total: int, _now_s: float) -> void:
	pass


## 0.0 until two samples span the window's start.
func per_second() -> float:
	return 0.0
