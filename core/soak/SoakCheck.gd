class_name SoakCheck
extends RefCounted
## Every pure soak invariant rule (SOAK_PLAN section 6.2). Each check takes observation objects
## built by the monitor and returns the violations found, empty when the state is sound. No
## scene tree, no autoload, no clock: the monitor owns time and rate limiting.

const SEVERITY_FAIL: StringName = &"fail"
const SEVERITY_WARN: StringName = &"warn"


## One broken invariant. `invariant` is the id from the plan (`physics.below_kill_plane`),
## `subject` what broke (a body id, a slot, a team) and `value` / `limit` the measured number and
## the bound it crossed.
class Violation:
	extends RefCounted
	var invariant: StringName = &""
	var severity: StringName = SEVERITY_FAIL
	var subject: String = ""
	var value: float = 0.0
	var limit: float = 0.0
	var detail: String = ""


## One tracked block as the registry reports it.
class BodyObs:
	extends RefCounted
	var id: int = 0
	var transform: Transform3D = Transform3D.IDENTITY
	var owner_slot: int = -1


## The territory board as read from the live raster.
class TerritoryObs:
	extends RefCounted
	## Share of in-disk cells per team, indexed by team.
	var shares: PackedFloat32Array = PackedFloat32Array()
	## Owned cells per team counted from the raster's owner bytes, indexed by team.
	var owned_cells: PackedInt32Array = PackedInt32Array()
	var in_disk_cells: int = 0
	## True when the uncached re-solve was run this sample (host, clean board).
	var fresh_solve_checked: bool = false
	var fresh_solve_matches: bool = true


## One living home flag and how long its cell has belonged to another team.
class HomeObs:
	extends RefCounted
	var slot: int = -1
	var team: int = -1
	var foreign_for_s: float = 0.0


## One non-bot slot's intent counters now and at the previous sample.
class IntentObs:
	extends RefCounted
	var slot: int = -1
	var sent: int = 0
	var accepted: int = 0
	var refused: int = 0
	var auto_drops: int = 0
	var blocks_placed: int = 0
	var prev_sent: int = 0
	var prev_accepted: int = 0
	var prev_refused: int = 0


## Below the kill plane, non-finite poses, and (host) the awake fraction.
static func physics(
	_bodies: Array[BodyObs],
	_awake_blocks: int,
	_total_blocks: int,
	_kill_plane_y: float,
	_is_host: bool,
	_config: SoakConfig
) -> Array[Violation]:
	return []


## Share range and sum, owned-cell recount, home flags, and the fresh re-solve.
static func territory(
	_board: TerritoryObs, _homes: Array[HomeObs], _config: SoakConfig
) -> Array[Violation]:
	return []


## Spawn identity, counter identity, and (when `fuzz_slot` >= 0) no accepted fuzz intent.
static func authority(
	_slots: Array[IntentObs], _fuzz_slot: int, _config: SoakConfig
) -> Array[Violation]:
	return []


## Tick p99 per band (`role` names the invariant: host or client), sim rate, snapshot bytes per
## second and the monitor's own sample cost.
static func budget(
	_role: StringName,
	_curve: TickBudgetCurve,
	_sim_rate: float,
	_physics_hz: int,
	_snapshot_bps: float,
	_monitor_us: int,
	_config: SoakConfig
) -> Array[Violation]:
	return []


## End-of-run memory per body and orphan nodes.
static func memory(
	_mem_start_mb: float,
	_mem_end_mb: float,
	_bodies_start: int,
	_bodies_end: int,
	_orphan_nodes: int,
	_config: SoakConfig
) -> Array[Violation]:
	return []
