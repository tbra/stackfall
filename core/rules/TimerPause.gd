class_name TimerPause
extends RefCounted
## Pure rule for QoL experiment 1 (Bontago-1pi.18.1): when a slot's block timer
## should be frozen. Two causes: a special triggered (pauses everyone for
## pause_event_s) and a big topple (a slot with at least topple_moving_blocks_min
## own blocks above topple_speed_threshold_mps, plus pause_tail_s afterwards).
## No scene-tree access: the caller feeds in per-slot moving-block counts.

var _qol: QolExperiments = null
var _slot_left: PackedFloat32Array = PackedFloat32Array()
var _global_left: float = 0.0


func _init(qol: QolExperiments, slot_count: int) -> void:
	_qol = qol
	_slot_left.resize(maxi(slot_count, 0))


func enabled() -> bool:
	return _qol != null and _qol.timer_pause_enabled


## A special triggered somewhere on the field.
func note_special() -> void:
	if enabled() and _qol.timer_pause_on_special:
		_global_left = maxf(_global_left, _qol.pause_event_s)


## `moving_counts[i]` = slot i's own blocks currently above the speed threshold.
## Pass an empty array on frames with no scan (timers still decay).
func update(delta: float, moving_counts: PackedInt32Array) -> void:
	if not enabled():
		return
	_global_left = maxf(_global_left - delta, 0.0)
	for i: int in range(_slot_left.size()):
		_slot_left[i] = maxf(_slot_left[i] - delta, 0.0)
		if i < moving_counts.size() and moving_counts[i] >= _qol.topple_moving_blocks_min:
			_slot_left[i] = maxf(_slot_left[i], maxf(_qol.pause_tail_s, _qol.topple_scan_interval_s))


func is_paused(slot_id: int) -> bool:
	if not enabled() or slot_id < 0 or slot_id >= _slot_left.size():
		return false
	return _global_left > 0.0 or _slot_left[slot_id] > 0.0
