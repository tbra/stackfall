class_name ClearanceRaise
extends RefCounted
## The shared "lift a pose straight up until it is clear" search the host (MatchPlacement) and the
## client ghost (PlayerController) both run, so the two can never drift.
##
## Pure logic: no scene tree. The caller supplies its own physics query as a Callable.

## Returned when no raise up to the cap clears the pose.
const NOT_CLEARED: float = -1.0
## Numeric guards, not tunables: floor for a configured step; slack on the cap comparison.
const MIN_STEP: float = 0.001
const CAP_EPSILON: float = 0.0001


## `overlaps(raise: float) -> bool` is the caller's own physics query at `raise` metres above the pose.
## Returns the smallest raise > 0 that clears it (linear step, then `bisect_steps` bisections, plus
## `margin`, never above `cap`), or NOT_CLEARED when no raise up to `cap` clears. The first query is
## at `step`; the caller keeps its own zero-raise check. Caller policy (cap, refuse vs auto-drop)
## stays at the call sites.
static func first_clear_raise(overlaps: Callable, step: float, cap: float, bisect_steps: int, margin: float) -> float:
	push_error("not implemented")
	return NOT_CLEARED
