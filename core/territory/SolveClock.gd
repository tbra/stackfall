class_name SolveClock
extends RefCounted
## The territory solve clock: accumulates elapsed time, floors it into whole
## solve steps, and decides when a solve defers (plan TERRITORY_READS 1.2).
##
## Interface stub: signatures only, no caller and no behaviour yet. Pure logic:
## no scene tree (CLAUDE.md).


## Credits elapsed seconds to the accumulator.
func add(_seconds: float) -> void:
	pass


## Seconds accumulated and not yet taken.
func accumulated() -> float:
	return 0.0


## Whole solve steps of `step_s` the accumulator holds.
func due_steps(_step_s: float) -> int:
	return 0


## Takes `steps` steps (the accumulator never goes below zero), remembers the
## accumulator it saw as waited_s() and returns the time taken.
func take(_steps: int, _step_s: float) -> float:
	return 0.0


## True while the solve should wait: false when `cap_s` <= 0 or the accumulator
## reached the cap, otherwise true unless every body is settled.
func should_defer(_cap_s: float, _all_settled: bool) -> bool:
	return false


## The accumulator seen by the last take().
func waited_s() -> float:
	return 0.0


## Zeroes waited_s() only.
func clear_waited() -> void:
	pass


## Zeroes the accumulator and waited_s().
func clear() -> void:
	pass
