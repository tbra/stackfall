class_name TimerPause
extends RefCounted
## Pure rule for QoL experiment 1 (Bontago-1pi.18.1): when a slot's block timer
## should be frozen. Two causes: a special triggered (pauses everyone for
## pause_event_s) and a big topple (a slot with at least topple_moving_blocks_min
## own blocks above topple_speed_threshold_mps, plus pause_tail_s afterwards).
## No scene-tree access: the caller feeds in per-slot moving-block counts.
##
## Stall guard (Bontago-1pi.18.4, QoL Q0): a cause that keeps refreshing itself
## (specials chaining up to max_chain_depth, a long avalanche) must not freeze a
## slot's cadence forever. Once a slot has been continuously RAW-paused for
## QolExperiments.pause_max_s it latches "exhausted": is_paused() reports false
## (the block timer runs) until the raw cause has fully cleared for that slot,
## then the slot re-arms and the next cause pauses it again for a fresh window.
## Deterministic and per slot; it advances only inside update(), so the host
## tick (MatchFeed._tick_qol_pause) drives it with no consumer change.

var _qol: QolExperiments = null
var _slot_left: PackedFloat32Array = PackedFloat32Array()
var _global_left: float = 0.0
## Seconds each slot has been continuously raw-paused (reset when the cause clears).
var _paused_for: PackedFloat32Array = PackedFloat32Array()
## Per-slot latch: 1 once _paused_for reached the cap, until the raw cause clears.
var _exhausted: PackedByteArray = PackedByteArray()


func _init(qol: QolExperiments, slot_count: int) -> void:
	_qol = qol
	var count: int = maxi(slot_count, 0)
	_slot_left.resize(count)
	_paused_for.resize(count)
	_exhausted.resize(count)


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
	var cap_s: float = _qol.effective_pause_max_s()
	for i: int in range(_slot_left.size()):
		_slot_left[i] = maxf(_slot_left[i] - delta, 0.0)
		if i < moving_counts.size() and moving_counts[i] >= _qol.topple_moving_blocks_min:
			_slot_left[i] = maxf(_slot_left[i], maxf(_qol.pause_tail_s, _qol.topple_scan_interval_s))
		if _raw_paused(i):
			_paused_for[i] += delta
			if _paused_for[i] >= cap_s:
				_exhausted[i] = 1
		else:
			# DECISION: the cause must be fully gone (global and own-slot) at an
			# update before the slot re-arms; a refresh that keeps the raw cause
			# alive across updates stays exhausted.
			_paused_for[i] = 0.0
			_exhausted[i] = 0


## True while the slot's timer should be frozen (false once its stall guard latched).
func is_paused(slot_id: int) -> bool:
	if not enabled() or slot_id < 0 or slot_id >= _slot_left.size():
		return false
	return _raw_paused(slot_id) and _exhausted[slot_id] == 0


## True while the slot's guard is latched: a raw cause is active but ignored.
func is_exhausted(slot_id: int) -> bool:
	if not enabled() or slot_id < 0 or slot_id >= _exhausted.size():
		return false
	return _exhausted[slot_id] != 0


## The un-guarded cause: a special event or a topple tail is still running.
func _raw_paused(slot_id: int) -> bool:
	return _global_left > 0.0 or _slot_left[slot_id] > 0.0
