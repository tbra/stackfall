class_name SoakCheck
extends RefCounted
## Every pure soak invariant rule (SOAK_PLAN section 6.2). Each check takes observation objects
## built by the monitor and returns the violations found, empty when the state is sound. No
## scene tree, no autoload, no clock: the monitor owns time and rate limiting.

const SEVERITY_FAIL: StringName = &"fail"
const SEVERITY_WARN: StringName = &"warn"

const _MS_PER_S: float = 1000.0
const _SHARE_MIN: float = 0.0
const _SHARE_MAX: float = 1.0


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
	## Seconds this body has been below the kill plane; INF (no grace) unless the monitor tracks it.
	var below_for_s: float = INF


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
	bodies: Array[BodyObs],
	awake_blocks: int,
	total_blocks: int,
	kill_plane_y: float,
	is_host: bool,
	config: SoakConfig
) -> Array[Violation]:
	var found: Array[Violation] = []
	var floor_y: float = kill_plane_y + config.kill_plane_margin_m
	for body: BodyObs in bodies:
		if not (body.transform.origin.is_finite() and body.transform.basis.is_finite()):
			found.append(_violation(&"physics.non_finite", str(body.id), 0.0, 0.0))
		elif body.transform.origin.y < floor_y and (is_host or body.below_for_s >= config.client_kill_grace_s):
			found.append(_violation(
				&"physics.below_kill_plane", str(body.id), body.transform.origin.y, floor_y,
				"owner=%d" % body.owner_slot
			))
	if is_host and total_blocks >= config.awake_check_min_bodies:
		var fraction: float = float(awake_blocks) / float(total_blocks)
		if fraction > config.awake_fraction_max:
			found.append(_violation(
				&"physics.awake_fraction", "", fraction, config.awake_fraction_max,
				"awake=%d total=%d" % [awake_blocks, total_blocks]
			))
	return found


## Share range and sum, owned-cell recount, home flags, and the fresh re-solve.
static func territory(
	board: TerritoryObs, homes: Array[HomeObs], config: SoakConfig
) -> Array[Violation]:
	var found: Array[Violation] = []
	var sum: float = 0.0
	for team: int in board.shares.size():
		var share: float = board.shares[team]
		sum += share
		if not (share >= _SHARE_MIN and share <= _SHARE_MAX):
			found.append(_violation(&"territory.share_range", str(team), share, _SHARE_MAX))
	var sum_limit: float = _SHARE_MAX + config.share_sum_eps
	if sum > sum_limit:
		found.append(_violation(&"territory.share_range", "sum", sum, sum_limit))
	if board.in_disk_cells > 0:
		# DECISION: SOAK_PLAN 6.2 names no id for a size mismatch; it reports under
		# territory.owned_cells_recount with subject "size", value owned_cells.size(), limit shares.size().
		if board.shares.size() != board.owned_cells.size():
			found.append(_violation(
				&"territory.owned_cells_recount", "size", float(board.owned_cells.size()),
				float(board.shares.size())
			))
		for team: int in mini(board.shares.size(), board.owned_cells.size()):
			var counted: float = float(board.owned_cells[team]) / float(board.in_disk_cells)
			if absf(counted - board.shares[team]) > config.share_sum_eps:
				found.append(_violation(
					&"territory.owned_cells_recount", str(team), counted, board.shares[team]
				))
	for home: HomeObs in homes:
		if home.foreign_for_s > config.home_foreign_grace_s:
			found.append(_violation(
				&"territory.home_foreign", str(home.slot), home.foreign_for_s,
				config.home_foreign_grace_s, "team=%d" % home.team
			))
	if board.fresh_solve_checked and not board.fresh_solve_matches:
		found.append(_violation(&"territory.fresh_solve", "", 0.0, 0.0))
	return found


## Spawn identity, counter identity, and (when `fuzz_slot` >= 0) no accepted fuzz intent.
static func authority(
	slots: Array[IntentObs], fuzz_slot: int, _config: SoakConfig
) -> Array[Violation]:
	var found: Array[Violation] = []
	for obs: IntentObs in slots:
		var subject: String = str(obs.slot)
		var spawned: int = obs.accepted + obs.auto_drops
		if obs.blocks_placed != spawned:
			found.append(_violation(
				&"authority.spawn_identity", subject, float(obs.blocks_placed), float(spawned)
			))
		if obs.accepted + obs.refused > obs.sent:
			found.append(_violation(
				&"authority.counter_identity", subject, float(obs.accepted + obs.refused),
				float(obs.sent), "accepted+refused>sent"
			))
		for pair: Array in [
			["sent", obs.sent, obs.prev_sent],
			["accepted", obs.accepted, obs.prev_accepted],
			["refused", obs.refused, obs.prev_refused],
		]:
			if int(pair[1]) < int(pair[2]):
				found.append(_violation(
					&"authority.counter_identity", subject, float(pair[1]), float(pair[2]),
					"%s_decreased" % pair[0]
				))
		if fuzz_slot >= 0 and obs.slot == fuzz_slot and obs.accepted > 0:
			found.append(_violation(&"authority.fuzz_accepted", subject, float(obs.accepted), 0.0))
	return found


## Tick p99 per band (`role` names the invariant: host or client), sim rate, snapshot bytes per
## second and the monitor's own sample cost, against a base plus an allowance per body it walked.
static func budget(
	role: StringName,
	curve: TickBudgetCurve,
	sim_rate: float,
	physics_hz: int,
	snapshot_bps: float,
	monitor_us: int,
	config: SoakConfig,
	monitor_bodies: int = 0
) -> Array[Violation]:
	var found: Array[Violation] = []
	var tick_limit_ms: float = config.tick_budget_fraction * _MS_PER_S / float(physics_hz)
	for band: int in curve.bands():
		var stats: Dictionary = curve.band_stats(band)
		var p99_ms: float = stats["p99_ms"]
		if int(stats["ticks"]) >= config.curve_min_ticks and p99_ms > tick_limit_ms:
			found.append(_violation(
				StringName("budget.%s_tick_p99" % role), str(band), p99_ms, tick_limit_ms
			))
	var rate_limit: float = config.sim_rate_min * float(physics_hz)
	if sim_rate < rate_limit:
		found.append(_violation(&"budget.sim_rate", "", sim_rate, rate_limit))
	if role == &"host" and snapshot_bps > config.snapshot_bps_max:
		found.append(_violation(&"budget.snapshot_bps", "", snapshot_bps, config.snapshot_bps_max))
	var monitor_limit_us: int = (
		config.monitor_overhead_us_max + config.monitor_overhead_us_per_body * monitor_bodies
	)
	if monitor_us > monitor_limit_us:
		found.append(_violation(
			&"budget.monitor_overhead", "", float(monitor_us), float(monitor_limit_us)
		))
	return found


## End-of-run memory per body and orphan nodes.
static func memory(
	mem_start_mb: float,
	mem_end_mb: float,
	bodies_start: int,
	bodies_end: int,
	orphan_nodes: int,
	config: SoakConfig
) -> Array[Violation]:
	var found: Array[Violation] = []
	var grown: int = bodies_end - bodies_start
	if grown > 0:
		var per_body_mb: float = (mem_end_mb - mem_start_mb) / float(grown)
		if per_body_mb > config.mem_per_body_max_mb:
			found.append(_violation(
				&"budget.memory_per_body", "", per_body_mb, config.mem_per_body_max_mb
			))
	if orphan_nodes > config.orphan_nodes_max:
		found.append(_violation(
			&"budget.orphan_nodes", "", float(orphan_nodes), float(config.orphan_nodes_max)
		))
	return found


static func _violation(
	invariant: StringName, subject: String, value: float, limit: float, detail: String = ""
) -> Violation:
	var v: Violation = Violation.new()
	v.invariant = invariant
	v.subject = subject
	v.value = value
	v.limit = limit
	v.detail = detail
	return v
