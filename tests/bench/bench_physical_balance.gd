extends Node3D
## M6 B5 (spec 2.1/2.7) benchmark: a moderately tall, off-center tower resting
## on the disk under tilt_mode PHYSICAL_BALANCE, whose own settled weight must
## drive Field's kinematic-torque approximation (config/TiltTuning.gd's
## physical_balance_torque_gain) toward a steady lean without ever toppling
## the stack that produced it. Spec 2.1 flags PHYSICAL_BALANCE's "feasibility
## still to be benchmarked" -- this is that benchmark. Run headless:
##   godot --headless --path . res://tests/bench/bench_physical_balance.tscn
##
## Same --trace=N / --offset=x,z args as tests/bench/bench_tower.gd (same
## flags, same meaning); --offset defaults to DEFAULT_OFFSET here (not the
## disk's centre) because a load sitting on-centre produces no torque at all
## and would make this benchmark meaningless:
##   godot --headless --path . res://tests/bench/bench_physical_balance.tscn -- --trace=30

const TOWER_HEIGHT: int = 15
const RUN_SECONDS: float = 40.0
## Same pass bar bench_tower.gd uses for a genuine collapse/lean-away: the top
## block shouldn't wander more than this over the whole run. Unlike
## bench_tower's straight-down drop, this tower's own tilt-induced lean is
## exactly the failure mode PHYSICAL_BALANCE risks, so this bound is this
## benchmark's actual feasibility check, not just a collapse guard.
const MAX_TOP_DRIFT: float = 2.0
const TRACE_ARG_PREFIX: String = "--trace="
const OFFSET_ARG_PREFIX: String = "--offset="
## Default --offset: off-centre on purpose (see header) so the tower's own
## weight has a lever arm and actually produces torque.
const DEFAULT_OFFSET: Vector2 = Vector2(4.0, 0.0)

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[RigidBody3D] = []
var _field: Field
var _registry: BlockRegistry
var _tick: int = 0
var _total_ticks: int = 0
var _top_start_position: Vector3 = Vector3.ZERO
var _max_top_drift: float = 0.0
var _max_tilt_deg: float = 0.0
var _trace_every: int = 0
var _offset: Vector2 = DEFAULT_OFFSET
var _first_all_asleep_tick: int = -1
## Sum of Performance.TIME_PHYSICS_PROCESS (msec) sampled once per tick, so
## the printed result line reports this benchmark's own average physics cost
## rather than requiring a separate profiler run.
var _physics_ms_total: float = 0.0


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TRACE_ARG_PREFIX):
			_trace_every = arg.substr(TRACE_ARG_PREFIX.length()).to_int()
		if arg.begins_with(OFFSET_ARG_PREFIX):
			_offset = _parse_offset(arg.substr(OFFSET_ARG_PREFIX.length()))

	_field = Field.new()
	add_child(_field)

	_registry = BlockRegistry.new()
	add_child(_registry)
	_registry.configure(_field, _field.map_def)

	# Same wiring MatchLifecycle._apply_tilt_mode() does for
	# MatchConfig.TiltMode.PHYSICAL_BALANCE -- this benchmark exercises the
	# real Field/BlockRegistry pairing, not a stand-in.
	_field.set_registry(_registry)
	_field.set_physical_balance_enabled(true)
	_field.set_tilt_enabled(true)

	# Same bottom-face-on-disk-surface maths as bench_tower.gd (Bontago-r2v,
	# Bontago-ddz) -- see that file's _ready() for why this isn't just
	# start_y = field.surface_y().
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var start_y: float = _field.surface_y() - _tuning.cube_margin * 0.5
	for i: int in range(TOWER_HEIGHT):
		var block: Block = BlockFactory.build(cube_shape, _tuning, 0)
		_field.add_child(block)
		block.global_position = Vector3(_offset.x, start_y + edge * float(i), _offset.y)
		_blocks.append(block)
		# BlockRegistry only tracks a block once it hears Events.block_placed
		# (game/BlockRegistry.gd's own doc: "Listens to Events.block_placed...
		# instead of walking the scene tree"), same as every other placement
		# path (MatchPlacement.gd, tests/unit/test_field_tilt.gd's fixtures).
		Events.block_placed.emit(block, cube_shape.id)

	_top_start_position = _blocks[TOWER_HEIGHT - 1].global_position
	print(
		"BENCH_PHYSICAL_BALANCE start blocks=%d duration_s=%.1f offset=%.3f,%.3f"
		% [TOWER_HEIGHT, RUN_SECONDS, _offset.x, _offset.y]
	)


## Parses "x,z" (metres) from an --offset= value; malformed input falls back
## to DEFAULT_OFFSET rather than crashing the benchmark (same as bench_tower.gd).
func _parse_offset(value: String) -> Vector2:
	var parts: PackedStringArray = value.split(",")
	if parts.size() != 2:
		return DEFAULT_OFFSET
	return Vector2(parts[0].to_float(), parts[1].to_float())


func _physics_process(_delta: float) -> void:
	_tick += 1
	_physics_ms_total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)

	var top: RigidBody3D = _blocks[TOWER_HEIGHT - 1]
	# Same kill-plane guard as bench_tower.gd's _physics_process(): a genuine
	# collapse/tip-over can carry a block past tuning.kill_plane_y, which
	# Field frees; report that as the FAIL it is instead of erroring forever.
	if not is_instance_valid(top):
		_report_collapse()
		return
	var drift: float = top.global_position.distance_to(_top_start_position)
	_max_top_drift = maxf(_max_top_drift, drift)
	_max_tilt_deg = maxf(_max_tilt_deg, rad_to_deg(_field.tilt_vector().length()))

	var awake: int = _awake_count()
	if _first_all_asleep_tick < 0 and awake == 0:
		_first_all_asleep_tick = _tick
	if _trace_every > 0 and _tick % _trace_every == 0:
		_print_trace(top, awake)

	if _tick < _total_ticks:
		return

	var all_asleep: bool = awake == 0
	# DECISION (tests/bench/bench_physical_balance.gd, Bontago-keo.11, orchestrator
	# 2026-09-25): the pass bar is the plan's feasibility check (docs/M6_PLAN.md
	# B5: the off-centre tower must not lean away/collapse) plus the game's own
	# settled notion (every block below PhysicsTuning.sleep_linear_threshold,
	# what BlockRegistry.is_settled uses), NOT Jolt's `sleeping` flag. Measured:
	# with the disk converged (1.12 deg, transform no longer rewritten) the 15
	# blocks still creep on the slope at ~1 mm/s, right at Jolt's sleep-sphere
	# bound (sleep_velocity_threshold 0.03 m/s * 1/60 s = 0.5 mm per 0.5 s), so
	# `sleeping` never flips while the stack is, for every rule the game has,
	# at rest. all_asleep/asleep_at_s stay in the result line as information.
	var passed: bool = _all_game_settled() and _max_top_drift < MAX_TOP_DRIFT
	_report_result(passed, all_asleep)
	get_tree().quit(0 if passed else 1)


## Same reasoning as bench_tower.gd's _report_collapse(): the block that
## started this run's drift measurement no longer exists, so this is always
## a FAIL, reported with whatever state was last observed.
func _report_collapse() -> void:
	_report_result(false, false)
	get_tree().quit(1)


func _report_result(passed: bool, all_asleep: bool) -> void:
	var avg_physics_ms: float = 0.0
	if _tick > 0:
		avg_physics_ms = _physics_ms_total / float(_tick)
	print(
		(
			"BENCH_PHYSICAL_BALANCE result=%s blocks=%d duration_s=%.1f max_top_drift_m=%.5f "
			+ "final_tilt_deg=%.4f max_tilt_deg=%.4f avg_physics_ms=%.4f all_asleep=%s "
			+ "asleep_at_s=%s offset=%.3f,%.3f"
		) % [
			"PASS" if passed else "FAIL", TOWER_HEIGHT, RUN_SECONDS, _max_top_drift,
			rad_to_deg(_field.tilt_vector().length()), _max_tilt_deg, avg_physics_ms, all_asleep,
			_seconds_label(_first_all_asleep_tick), _offset.x, _offset.y,
		]
	)


## True when every block is below the game's settled speed thresholds
## (PhysicsTuning.sleep_linear_threshold / sleep_angular_threshold).
func _all_game_settled() -> bool:
	for block: RigidBody3D in _blocks:
		if not is_instance_valid(block):
			return false
		if block.linear_velocity.length() >= _tuning.sleep_linear_threshold:
			return false
		if block.angular_velocity.length() >= _tuning.sleep_angular_threshold:
			return false
	return true


func _awake_count() -> int:
	var awake: int = 0
	for block: RigidBody3D in _blocks:
		if not is_instance_valid(block) or not block.sleeping:
			awake += 1
	return awake


## One line of tower state: lean plus the field's own current tilt (degrees),
## which is what PHYSICAL_BALANCE adds on top of bench_tower.gd's own trace.
func _print_trace(top: RigidBody3D, awake: int) -> void:
	var lean: float = Vector2(top.global_position.x, top.global_position.z).length()
	var fastest: float = 0.0
	for block: RigidBody3D in _blocks:
		if is_instance_valid(block):
			fastest = maxf(fastest, block.linear_velocity.length())
	print(
		(
			"BENCH_PHYSICAL_BALANCE trace t=%6.2f awake=%3d top_y=%9.5f lean_m=%9.5f "
			+ "fastest_m_per_s=%8.5f tilt_deg=%7.4f"
		) % [
			float(_tick) / float(Engine.physics_ticks_per_second),
			awake, top.global_position.y, lean, fastest, rad_to_deg(_field.tilt_vector().length()),
		]
	)


func _seconds_label(tick: int) -> String:
	if tick < 0:
		return "never"
	return "%.2f" % (float(tick) / float(Engine.physics_ticks_per_second))
