class_name SoakMonitor
extends Node
## Debug-only observer for the end-to-end soak gate (SOAK_PLAN section 3.1). It samples game
## state through public APIs on wall-aligned epochs, times every physics tick into a
## TickBudgetCurve, collects SoakCheck violations and writes the SOAK_* lines. It only reads:
## no gameplay write, no RPC, no signal emitted.
##
## Main creates it when `--soak` is on the command line in debug mode and sets `config`, `role`
## and `sampler` before add_child.

const _CLI_FUZZ: String = "soak-fuzz"
const _SCENARIO_LOAD: StringName = &"load"
const _SCENARIO_AUTHORITY: StringName = &"authority"
const _MS_PER_S: float = 1000.0
const _US_PER_S: float = 1000000.0

## Every tolerance and interval.
var config: SoakConfig = null
## Which process this is: &"host" or &"client".
var role: StringName = &""
## The shared per-window metrics (static memory, object and orphan counts).
var sampler: PerfSampler = null

var _violations: Array[SoakCheck.Violation] = []
var _observer: SoakObserver = null
var _curve: TickBudgetCurve = null
var _fuzz_run: bool = false
var _tracked_bodies: int = 0
var _last_epoch: int = -1
var _samples: int = 0
# Seconds-clock reading when the match first played, -1 before.
var _play_start_s: float = -1.0
var _quitting: bool = false
var _prev_wall_s: float = -1.0
var _prev_physics_frames: int = 0
var _prev_bytes: int = 0
var _prev_monitor_us: int = 0
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
	_fuzz_run = OS.get_cmdline_user_args().has("--" + _CLI_FUZZ)
	var scenario: StringName = _SCENARIO_AUTHORITY if _fuzz_run else _SCENARIO_LOAD
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
	if (
		role == &"client" and not _quitting and _play_start_s >= 0.0
		and _now_s() - _play_start_s >= config.duration_s
	):
		_quitting = true
		_quit_cleanly()


func _exit_tree() -> void:
	if _observer == null:
		return
	var wall_ms: int = int(Time.get_unix_time_from_system() * _MS_PER_S)
	for band: int in _curve.bands():
		print(SoakLine.curve(role, band, _curve.band_stats(band), _curve.budget_ms))
	var final_checks: Array[SoakCheck.Violation] = SoakCheck.memory(
		maxf(_mem_start_mb, 0.0), _mem_end_mb, _bodies_start, _bodies_end, _orphans_end, config
	)
	_record(final_checks, _last_epoch, wall_ms)
	print(SoakLine.end(role, {
		"samples": _samples, "violations": violations().size(), "sim_rate": _sim_rate,
		"mem_start_mb": maxf(_mem_start_mb, 0.0), "mem_end_mb": _mem_end_mb,
		"bodies_start": _bodies_start, "bodies_end": _bodies_end,
	}))


## One sample: reads the state, runs the checks, records the violations and returns the new
## ones. The schedule calls the same method.
func sample_now() -> Array[SoakCheck.Violation]:
	var started_us: int = Time.get_ticks_usec()
	var wall_s: float = Time.get_unix_time_from_system()
	var epoch: int = floori(wall_s / config.sample_interval_s)
	var wall_ms: int = int(wall_s * _MS_PER_S)
	var now_s: float = _now_s()
	var is_host: bool = role == &"host"
	if _play_start_s < 0.0 and Match.state() == Match.State.PLAYING:
		_play_start_s = now_s
	var checking: bool = _play_start_s < 0.0 or now_s - _play_start_s >= config.warmup_s
	var dump: bool = _samples % config.body_dump_every_samples == 0
	var fresh: bool = is_host and _samples % config.fresh_solve_every_samples == 0

	var bodies: Array[SoakCheck.BodyObs] = _observer.bodies()
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
			var fuzz_slot: int = _observer.fuzz_slot() if _fuzz_run else -1
			found.append_array(SoakCheck.authority(_observer.intents(), fuzz_slot, config))
		if _prev_wall_s >= 0.0:
			found.append_array(SoakCheck.budget(
				role, _curve, _sim_rate, Engine.physics_ticks_per_second, bps, _prev_monitor_us,
				config
			))
		if _mem_start_mb < 0.0:
			_mem_start_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / _BYTES_PER_MB
			_bodies_start = bodies.size()
	_mem_end_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / _BYTES_PER_MB
	_bodies_end = bodies.size()
	_orphans_end = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	_prev_wall_s = wall_s
	_prev_physics_frames = frames
	_prev_bytes = bytes_total
	_last_epoch = epoch
	_samples += 1
	_record(found, epoch, wall_ms)
	var fields: Dictionary = _observer.sample_fields(bodies.size(), board)
	fields["mt"] = now_s - _play_start_s if _play_start_s >= 0.0 else 0.0
	fields["tick_p99_ms"] = _worst_p99_ms()
	_prev_monitor_us = Time.get_ticks_usec() - started_us
	fields["mon_us"] = _prev_monitor_us
	print(SoakLine.sample(role, epoch, wall_ms, fields))
	if dump:
		for line: String in _observer.body_lines(role, epoch):
			print(line)
	return found


## Every violation recorded so far; SOAK_END reports their count.
func violations() -> Array[SoakCheck.Violation]:
	return _violations


func _record(found: Array[SoakCheck.Violation], epoch: int, wall_ms: int) -> void:
	var match_time: float = _now_s() - _play_start_s if _play_start_s >= 0.0 else 0.0
	for violation: SoakCheck.Violation in found:
		_violations.append(violation)
		print(SoakLine.violation(violation, role, epoch, wall_ms, match_time))


func _worst_p99_ms() -> float:
	var worst: float = 0.0
	for band: int in _curve.bands():
		worst = maxf(worst, float(_curve.band_stats(band)["p99_ms"]))
	return worst


func _now_s() -> float:
	return float(Time.get_ticks_usec()) / _US_PER_S


## The clean quit the host's --seconds timer uses.
func _quit_cleanly() -> void:
	await Sfx.drain_for_quit()
	QuitFlag.mark()
	get_tree().quit(0)
