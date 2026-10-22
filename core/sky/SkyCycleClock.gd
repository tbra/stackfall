class_name SkyCycleClock
extends RefCounted
## The day/night cycle clock, pure: phase = fposmod(clock / length + offset, 1), or a locked
## phase that ignores the clock. The shared clock is passed in on every call (nothing here reads
## a peer-local clock), so host and clients agree. Lock/unlock and a length edit never jump the
## time of day.

## Lowest cycle length (s) the clock accepts; guards the division.
const MIN_LENGTH_S: float = 1.0

var _active: bool = false
var _length_s: float = MIN_LENGTH_S
var _offset: float = 0.0
var _clock_s: float = 0.0
var _locked_phase: float = -1.0


## Starts the cycle as of shared clock `clock_s`. `lock_phase` >= 0 freezes it at that phase;
## `start_phase` is the phase a running cycle shows at `clock_s` (the caller resolves the default).
func start(clock_s: float, length_s: float, lock_phase: float, start_phase: float) -> void:
	_active = true
	_length_s = maxf(length_s, MIN_LENGTH_S)
	_locked_phase = fposmod(lock_phase, 1.0) if lock_phase >= 0.0 else -1.0
	# DECISION: the offset puts `start_phase` at the start clock, so every peer opens
	# identically and the shared clock alone carries them forward.
	_offset = start_phase - clock_s / _length_s
	_clock_s = clock_s


## The phase (0..1, 0 = dawn, 0.25 = noon) at shared clock `clock_s` under the length and offset
## in force; the locked phase while locked.
func phase_at(clock_s: float) -> float:
	if _locked_phase >= 0.0:
		return _locked_phase
	return fposmod(clock_s / _length_s + _offset, 1.0)


## Records the latest shared clock and folds in a length edit, then returns the phase. A length
## change keeps the phase at `clock_s` (no jump); only the rate changes afterwards.
func advance(clock_s: float, length_s: float) -> float:
	_clock_s = clock_s
	var length: float = maxf(length_s, MIN_LENGTH_S)
	if not is_equal_approx(length, _length_s):
		if _locked_phase >= 0.0:
			# Locked: the phase is fixed and the unlock re-bases the offset.
			_length_s = length
		else:
			var phase: float = phase_at(_clock_s)
			_length_s = length
			_offset = phase - _clock_s / length
	return phase_at(clock_s)


## Locks at `phase` (wrapped into 0..1) or, for `phase` < 0, unlocks so the cycle runs on from
## the locked phase at the last clock seen. No-op before start().
func set_locked(phase: float) -> void:
	if not _active:
		return
	if phase < 0.0:
		if _locked_phase < 0.0:
			return
		var held: float = _locked_phase
		_locked_phase = -1.0
		_offset = held - _clock_s / _length_s
		return
	_locked_phase = fposmod(phase, 1.0)


## The locked phase, or -1 while running or not started.
func locked_phase() -> float:
	return _locked_phase if _active else -1.0


func is_active() -> bool:
	return _active


## Integer cycle count of the running cycle; a locked sky is night 0.
func night_index() -> int:
	if _locked_phase >= 0.0:
		return 0
	return int(floori(_clock_s / _length_s + _offset))
