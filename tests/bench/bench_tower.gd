extends Node3D
## Spec 3.5 benchmark: a 40-block tower that must stay standing for 60 s with
## no jitter. Run headless:
##   godot --headless --path . res://tests/bench/bench_tower.tscn
## Prints one machine-readable result line, then quits.
##
## When it fails, add --trace=N to also print the tower's state every N
## physics ticks, which is how the shape of a failure (a slow lean, a sudden
## pop, a stack that rings and never sleeps) is told apart:
##   godot --headless --path . res://tests/bench/bench_tower.tscn -- --trace=30
##
## Add --offset=x,z (metres, default 0,0) to shift the whole tower sideways
## before it drops, e.g. to straddle a cell seam:
##   godot --headless --path . res://tests/bench/bench_tower.tscn -- --offset=0.5,0

const TOWER_HEIGHT: int = 40
const RUN_SECONDS: float = 60.0
## Same pass bar test_tower_placement.gd uses for the 30-block acceptance
## check: the top block shouldn't wander more than this over the whole run.
const MAX_TOP_DRIFT: float = 2.0
## --trace=<ticks>; 0 (the default) prints only the result line.
const TRACE_ARG_PREFIX: String = "--trace="
## --offset=<x>,<z>; 0,0 (the default) drops the tower at the field's centre.
const OFFSET_ARG_PREFIX: String = "--offset="
## Default --offset when the arg is absent.
const DEFAULT_OFFSET: Vector2 = Vector2.ZERO

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[RigidBody3D] = []
var _tick: int = 0
var _total_ticks: int = 0
var _top_start_position: Vector3 = Vector3.ZERO
var _max_top_drift: float = 0.0
var _trace_every: int = 0
var _offset: Vector2 = DEFAULT_OFFSET
var _first_all_asleep_tick: int = -1


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TRACE_ARG_PREFIX):
			_trace_every = arg.substr(TRACE_ARG_PREFIX.length()).to_int()
		if arg.begins_with(OFFSET_ARG_PREFIX):
			_offset = _parse_offset(arg.substr(OFFSET_ARG_PREFIX.length()))

	var field: Field = Field.new()
	add_child(field)

	# Bontago-r2v: BlockFactory.build()'s body origin is the shape's
	# bottom-face centre (commit 955d7d1), so block i's bottom face -- not its
	# centre -- must sit at the disk's own top surface (Field.surface_y(),
	# not assumed to be 0.0) plus edge * i; that is what makes the whole
	# tower start resting exactly on the disk and on each other instead of
	# floating edge * 0.5 m up and dropping.
	#
	# The origin is the bottom of the *nominal* cube_size cell, but the
	# collision box is cube_size - cube_margin across and centred in that cell,
	# so its bottom face sits cube_margin / 2 above the origin. Rest the
	# collision box, not the origin, on the disk: with the origin on the disk
	# the whole tower fell 1 cm on tick one, and that landing impulse (not the
	# disk surface) is what made the result flip between PASS and collapse
	# across otherwise identical runs (Bontago-ddz).
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var start_y: float = field.surface_y() - _tuning.cube_margin * 0.5
	for i: int in range(TOWER_HEIGHT):
		var block: RigidBody3D = BlockFactory.build(cube_shape, _tuning)
		add_child(block)
		block.global_position = Vector3(_offset.x, start_y + edge * float(i), _offset.y)
		_blocks.append(block)

	_top_start_position = _blocks[TOWER_HEIGHT - 1].global_position
	print(
		"BENCH_TOWER start blocks=%d duration_s=%.1f offset=%.3f,%.3f"
		% [TOWER_HEIGHT, RUN_SECONDS, _offset.x, _offset.y]
	)


## Parses "x,z" (metres) from an --offset= value; malformed input falls back
## to DEFAULT_OFFSET rather than crashing the benchmark.
func _parse_offset(value: String) -> Vector2:
	var parts: PackedStringArray = value.split(",")
	if parts.size() != 2:
		return DEFAULT_OFFSET
	return Vector2(parts[0].to_float(), parts[1].to_float())


func _physics_process(_delta: float) -> void:
	_tick += 1

	var top: RigidBody3D = _blocks[TOWER_HEIGHT - 1]
	# DECISION (Bontago-r2v): a genuine collapse can carry a block past
	# tuning.kill_plane_y, which Field._on_kill_plane_body_entered() frees;
	# without this guard the next line's global_position read throws a
	# script error every remaining tick and the bench never reaches its own
	# result= line. Report it as the FAIL it is instead of erroring forever.
	if not is_instance_valid(top):
		_report_collapse()
		return
	var drift: float = top.global_position.distance_to(_top_start_position)
	_max_top_drift = maxf(_max_top_drift, drift)

	var awake: int = _awake_count()
	if _first_all_asleep_tick < 0 and awake == 0:
		_first_all_asleep_tick = _tick
	if _trace_every > 0 and _tick % _trace_every == 0:
		_print_trace(top, awake)

	if _tick < _total_ticks:
		return

	var all_asleep: bool = awake == 0
	var passed: bool = all_asleep and _max_top_drift < MAX_TOP_DRIFT
	_report_result(passed, all_asleep)
	get_tree().quit(0 if passed else 1)


## The block that started this run's drift measurement no longer exists --
## it crossed tuning.kill_plane_y and Field freed it -- so this is always a
## FAIL, reported with whatever drift/sleep state was last observed rather
## than the still-running values _physics_process would otherwise compute.
func _report_collapse() -> void:
	_report_result(false, false)
	get_tree().quit(1)


func _report_result(passed: bool, all_asleep: bool) -> void:
	print(
		(
			"BENCH_TOWER result=%s blocks=%d duration_s=%.1f max_top_drift_m=%.5f "
			+ "all_asleep=%s asleep_at_s=%s offset=%.3f,%.3f"
		) % [
			"PASS" if passed else "FAIL", TOWER_HEIGHT, RUN_SECONDS, _max_top_drift, all_asleep,
			_seconds_label(_first_all_asleep_tick), _offset.x, _offset.y,
		]
	)


func _awake_count() -> int:
	var awake: int = 0
	for block: RigidBody3D in _blocks:
		# A block below the top of the stack can also cross the kill plane
		# during a collapse; count it as awake (never asleep) rather than
		# reading a freed object.
		if not is_instance_valid(block) or not block.sleeping:
			awake += 1
	return awake


## One line of tower state: how far the top has wandered sideways (lean) as
## opposed to settling straight down, and the fastest block anywhere in the
## stack, which is what Jolt's sleep threshold actually looks at.
func _print_trace(top: RigidBody3D, awake: int) -> void:
	var lean: float = Vector2(top.global_position.x, top.global_position.z).length()
	var fastest: float = 0.0
	for block: RigidBody3D in _blocks:
		if is_instance_valid(block):
			fastest = maxf(fastest, block.linear_velocity.length())
	print(
		"BENCH_TOWER trace t=%6.2f awake=%3d top_y=%9.5f lean_m=%9.5f fastest_m_per_s=%8.5f" % [
			float(_tick) / float(Engine.physics_ticks_per_second),
			awake, top.global_position.y, lean, fastest,
		]
	)


func _seconds_label(tick: int) -> String:
	if tick < 0:
		return "never"
	return "%.2f" % (float(tick) / float(Engine.physics_ticks_per_second))
