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

const TOWER_HEIGHT: int = 40
const RUN_SECONDS: float = 60.0
## Same pass bar test_tower_placement.gd uses for the 30-block acceptance
## check: the top block shouldn't wander more than this over the whole run.
const MAX_TOP_DRIFT: float = 2.0
## --trace=<ticks>; 0 (the default) prints only the result line.
const TRACE_ARG_PREFIX: String = "--trace="

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[RigidBody3D] = []
var _tick: int = 0
var _total_ticks: int = 0
var _top_start_position: Vector3 = Vector3.ZERO
var _max_top_drift: float = 0.0
var _trace_every: int = 0
var _first_all_asleep_tick: int = -1


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TRACE_ARG_PREFIX):
			_trace_every = arg.substr(TRACE_ARG_PREFIX.length()).to_int()

	var field: Field = Field.new()
	add_child(field)

	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	for i: int in range(TOWER_HEIGHT):
		var block: RigidBody3D = BlockFactory.build(cube_shape, _tuning)
		add_child(block)
		block.global_position = Vector3(0.0, edge * 0.5 + edge * float(i), 0.0)
		_blocks.append(block)

	_top_start_position = _blocks[TOWER_HEIGHT - 1].global_position
	print("BENCH_TOWER start blocks=%d duration_s=%.1f" % [TOWER_HEIGHT, RUN_SECONDS])


func _physics_process(_delta: float) -> void:
	_tick += 1

	var top: RigidBody3D = _blocks[TOWER_HEIGHT - 1]
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
	print(
		(
			"BENCH_TOWER result=%s blocks=%d duration_s=%.1f max_top_drift_m=%.5f "
			+ "all_asleep=%s asleep_at_s=%s"
		) % [
			"PASS" if passed else "FAIL", TOWER_HEIGHT, RUN_SECONDS, _max_top_drift, all_asleep,
			_seconds_label(_first_all_asleep_tick),
		]
	)
	get_tree().quit(0 if passed else 1)


func _awake_count() -> int:
	var awake: int = 0
	for block: RigidBody3D in _blocks:
		if not block.sleeping:
			awake += 1
	return awake


## One line of tower state: how far the top has wandered sideways (lean) as
## opposed to settling straight down, and the fastest block anywhere in the
## stack, which is what Jolt's sleep threshold actually looks at.
func _print_trace(top: RigidBody3D, awake: int) -> void:
	var lean: float = Vector2(top.global_position.x, top.global_position.z).length()
	var fastest: float = 0.0
	for block: RigidBody3D in _blocks:
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
