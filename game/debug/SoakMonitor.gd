class_name SoakMonitor
extends Node
## Debug-only observer for the end-to-end soak gate (SOAK_PLAN section 3.1). It samples game
## state through public APIs on wall-aligned epochs, times every physics tick into a
## TickBudgetCurve, collects SoakCheck violations and writes the SOAK_* lines. It only reads:
## no gameplay write, no RPC, no signal emitted.
##
## Main creates it when `--soak` is on the command line in debug mode and sets `config`, `role`
## and `sampler` before add_child.

## Every tolerance and interval.
var config: SoakConfig = null
## Which process this is: &"host" or &"client".
var role: StringName = &""
## The shared per-window metrics (static memory, object and orphan counts).
var sampler: PerfSampler = null

var _violations: Array[SoakCheck.Violation] = []


## One sample: reads the state, runs the checks, records the violations and returns the new
## ones. The schedule calls the same method.
func sample_now() -> Array[SoakCheck.Violation]:
	return []


## Every violation recorded so far; SOAK_END reports their count.
func violations() -> Array[SoakCheck.Violation]:
	return _violations
