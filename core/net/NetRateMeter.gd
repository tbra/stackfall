class_name NetRateMeter
extends RefCounted
## Turns a cumulative counter into a per-second rate over a sliding window.

var _window_s: float = 0.0
## [time_s, total] rows, oldest first. Only the newest row at or before the window's start is kept
## as the anchor, so the list stays about one window long.
var _rows: Array[Vector2] = []


func _init(window_s: float) -> void:
	_window_s = window_s


## A total that goes down (new match) restarts the window; a sample from an earlier time is ignored.
func sample(cumulative_total: int, now_s: float) -> void:
	if not _rows.is_empty():
		var newest: Vector2 = _rows[_rows.size() - 1]
		if now_s < newest.x:
			return
		if float(cumulative_total) < newest.y:
			_rows.clear()
	_rows.append(Vector2(now_s, float(cumulative_total)))
	while _rows.size() > 2 and _rows[1].x <= now_s - _window_s:
		_rows.remove_at(0)


## 0.0 until two samples span the window's start.
func per_second() -> float:
	if _rows.size() < 2:
		return 0.0
	var newest: Vector2 = _rows[_rows.size() - 1]
	var anchor: Vector2 = _rows[0]
	var span_s: float = newest.x - anchor.x
	if span_s < _window_s or span_s <= 0.0:
		return 0.0
	return (newest.y - anchor.y) / span_s
