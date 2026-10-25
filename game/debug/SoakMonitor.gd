class_name SoakMonitor
extends Node
## Debug-only observer for the end-to-end soak gate (SOAK_PLAN section 3.1). It samples game
## state through public APIs on wall-aligned epochs, times every physics tick into a
## TickBudgetCurve, collects SoakCheck violations and writes the SOAK_* lines. It only reads:
## no gameplay write, no RPC, no signal emitted.
##
## Main creates it when `--soak` is on the command line in debug mode and sets `config`, `role`
## and `sampler` before add_child. The launcher names the scenario with `--soak-scenario=<name>`
## on both processes; the SOAK_CONFIG line carries it (load when absent).

const _CLI_SCENARIO_PREFIX: String = "--soak-scenario="
const _SCENARIO_LOAD: StringName = &"load"
const _MS_PER_S: float = 1000.0
const _US_PER_S: float = 1000000.0

## Every tolerance and interval.
var config: SoakConfig = null
## Which process this is: &"host" or &"client".
var role: StringName = &""
## The shared per-window metrics (static memory, object and orphan counts).
var sampler: PerfSampler = null

var _violations: Array[SoakCheck.Violation] = []
# "invariant|subject" -> the epoch it was last recorded in (one record per epoch).
var _last_recorded_epoch: Dictionary = {}
var _observer: SoakObserver = null
var _curve: TickBudgetCurve = null
var _tracked_bodies: int = 0
var _last_epoch: int = -1
var _samples: int = 0
# Seconds-clock reading when the match first played, -1 before.
var _play_start_s: float = -1.0
var _quitting: bool = false
# True once Net was a client after play start; the session ending then quits the client.
var _seen_client: bool = false
var _prev_wall_s: float = -1.0
var _prev_physics_frames: int = 0
var _prev_bytes: int = 0
var _prev_monitor_us: int = 0
var _prev_monitor_bodies: int = 0
# Body id -> seconds-clock reading when it was first seen below the kill plane (client only).
var _below_since: Dictionary = {}
var _mem_start_mb: float = -1.0
var _mem_end_mb: float = 0.0
var _bodies_start: int = 0
var _bodies_end: int = 0
var _orphans_end: int = 0
var _sim_rate: float = 0.0


func _ready() -> void:
	_observer = SoakObserver.new(sampler)
	var budget_ms: float = config.tick_budget_fraction * _MS_PER_S / float(Engine.physics_ticks_per_second)
	_curve = TickBudgetCurve.new(
		config.curve_bands, config.curve_band_half_width_fraction, budget_ms,
		config.curve_bucket_ms, config.curve_max_ms
	)
	var scenario: StringName = _SCENARIO_LOAD
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(_CLI_SCENARIO_PREFIX):
			scenario = StringName(arg.trim_prefix(_CLI_SCENARIO_PREFIX))
	print(SoakLine.config_line(role, scenario, config))


func _physics_process(_delta: float) -> void:
	var registry: BlockRegistry = Match.registry() as BlockRegistry
	_tracked_bodies = registry.tracked_block_count() if registry != null else 0
	_curve.record(
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * _MS_PER_S, _tracked_bodies
	)
	var epoch: int = floori(Time.get_unix_time_from_system() / config.sample_interval_s)
	if epoch != _last_epoch:
		sample_now()
	if role == &"client" and _play_start_s >= 0.0 and Net.is_client():
		_seen_client = true
	if role == &"client" and not _quitting and _play_start_s >= 0.0 and (
		_now_s() - _play_start_s >= config.duration_s or (_seen_client and not Net.is_client())
	):
		_quitting = true
		Sfx.quit_tree()  # marks QuitFlag, drains audio, then quits


func _exit_tree() -> void:
	if _observer == null:
		return
	var wall_ms: int = int(Time.get_unix_time_from_system() * _MS_PER_S)
	for band: int in _curve.bands():
		print(SoakLine.curve(role, band, _curve.band_stats(band), _curve.budget_ms))
	# A run that ended inside warm-up never latched a baseline: nothing to compare against.
	if _mem_start_mb >= 0.0:
		_record(SoakCheck.memory(
			_mem_start_mb, _mem_end_mb, _bodies_start, _bodies_end, _orphans_end, config
		), _last_epoch, wall_ms)
	print(SoakLine.end(role, {
		"samples": _samples, "violations": violations().size(), "sim_rate": _sim_rate,
		"mem_start_mb": maxf(_mem_start_mb, 0.0), "mem_end_mb": _mem_end_mb,
		"bodies_start": _bodies_start, "bodies_end": _bodies_end,
	}))


## One sample: reads the state, runs the checks and records the violations. The schedule calls
## the same method.
func sample_now() -> void:
	var started_us: int = Time.get_ticks_usec()
	var wall_s: float = Time.get_unix_time_from_system()
	var epoch: int = floori(wall_s / config.sample_interval_s)
	var wall_ms: int = int(wall_s * _MS_PER_S)
	var now_s: float = _now_s()
	var is_host: bool = role == &"host"
	if _play_start_s < 0.0 and Match.state() == Match.State.PLAYING:
		_play_start_s = now_s
	var playing: bool = _play_start_s >= 0.0 and Match.state() == Match.State.PLAYING
	var checking: bool = _play_start_s >= 0.0 and now_s - _play_start_s >= config.warmup_s
	var dump: bool = posmod(epoch, config.body_dump_every_samples) == 0
	var fresh: bool = is_host and _samples % config.fresh_solve_every_samples == 0

	var bodies: Array[SoakCheck.BodyObs] = _observer.bodies()
	if not is_host:
		_track_below_plane(bodies, now_s)
	var board: SoakCheck.TerritoryObs = _observer.territory(fresh and checking)
	var bytes_total: int = SnapshotSync.snapshot_bytes_total()
	var frames: int = Engine.get_physics_frames()
	var span_s: float = wall_s - _prev_wall_s
	if _prev_wall_s >= 0.0 and span_s > 0.0:
		_sim_rate = float(frames - _prev_physics_frames) / span_s
	var bps: float = float(bytes_total - _prev_bytes) / span_s if _prev_wall_s >= 0.0 and span_s > 0.0 else 0.0

	var found: Array[SoakCheck.Violation] = []
	if checking:
		found.append_array(SoakCheck.physics(
			bodies, _observer.awake_blocks(), bodies.size(), _observer.kill_plane_y(), is_host,
			config
		))
		found.append_array(SoakCheck.territory(board, _observer.homes(now_s), config))
		if is_host:
			found.append_array(SoakCheck.authority(
				_observer.intents(), _observer.fuzz_slot(), config
			))
		if _prev_wall_s >= 0.0:
			found.append_array(SoakCheck.budget(
				role, _curve, _sim_rate, Engine.physics_ticks_per_second, bps, _prev_monitor_us,
				config, _prev_monitor_bodies
			))
		if _mem_start_mb < 0.0:
			_mem_start_mb = SoakObserver.static_mem_mb()
			_bodies_start = bodies.size()
	if playing:
		_mem_end_mb = SoakObserver.static_mem_mb()
		_bodies_end = bodies.size()
		_orphans_end = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	_prev_wall_s = wall_s
	_prev_physics_frames = frames
	_prev_bytes = bytes_total
	_last_epoch = epoch
	_samples += 1
	var fields: Dictionary = _observer.sample_fields(bodies.size(), board)
	fields["mt"] = now_s - _play_start_s if _play_start_s >= 0.0 else 0.0
	fields["tick_p99_ms"] = _worst_p99_ms()
	# The overhead budget covers the walk and checks, not log writes: a disk stall blocks
	# both peers' prints in the same second and is not the monitor's cost.
	_prev_monitor_us = Time.get_ticks_usec() - started_us
	_prev_monitor_bodies = bodies.size()
	_record(found, epoch, wall_ms)
	fields["mon_us"] = _prev_monitor_us
	print(SoakLine.sample(role, epoch, wall_ms, fields))
	if dump:
		for line: String in _observer.body_lines(role, epoch):
			print(line)


# DECISION: only the time below the plane is graced, not whether the body is at rest: a client
# body held at its last snapshot is not moving either, so rest cannot tell it from a stuck one.
func _track_below_plane(bodies: Array[SoakCheck.BodyObs], now_s: float) -> void:
	var floor_y: float = _observer.kill_plane_y() - config.kill_plane_margin_m
	var still_below: Dictionary = {}
	for body: SoakCheck.BodyObs in bodies:
		if body.transform.origin.y < floor_y:
			still_below[body.id] = _below_since.get(body.id, now_s)
			body.below_for_s = now_s - float(still_below[body.id])
	_below_since = still_below


## Every violation recorded so far; SOAK_END reports their count.
func violations() -> Array[SoakCheck.Violation]:
	return _violations


## Records and prints each (invariant, subject) at most once per epoch.
func _record(found: Array[SoakCheck.Violation], epoch: int, wall_ms: int) -> void:
	var match_time: float = _now_s() - _play_start_s if _play_start_s >= 0.0 else 0.0
	for violation: SoakCheck.Violation in found:
		var key: String = "%s|%s" % [violation.invariant, violation.subject]
		if _last_recorded_epoch.get(key, -1) == epoch:
			continue
		_last_recorded_epoch[key] = epoch
		_violations.append(violation)
		print(SoakLine.violation(violation, role, epoch, wall_ms, match_time))


func _worst_p99_ms() -> float:
	var worst: float = 0.0
	for band: int in _curve.bands():
		worst = maxf(worst, float(_curve.band_stats(band)["p99_ms"]))
	return worst


func _now_s() -> float:
	return float(Time.get_ticks_usec()) / _US_PER_S

