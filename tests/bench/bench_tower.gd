extends Node3D
## Spec 3.5 benchmark: a 40-block tower that must stay standing for 60 s with
## no jitter. Run headless:
##   godot --headless --path . res://tests/bench/bench_tower.tscn
## Prints one machine-readable result line, then quits.

const TOWER_HEIGHT: int = 40
const RUN_SECONDS: float = 60.0
## Same pass bar test_tower_placement.gd uses for the 30-block acceptance
## check: the top block shouldn't wander more than this over the whole run.
const MAX_TOP_DRIFT: float = 2.0

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[RigidBody3D] = []
var _tick: int = 0
var _total_ticks: int = 0
var _top_start_position: Vector3 = Vector3.ZERO
var _max_top_drift: float = 0.0


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))

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

	if _tick < _total_ticks:
		return

	var all_asleep: bool = true
	for block: RigidBody3D in _blocks:
		if not block.sleeping:
			all_asleep = false

	var passed: bool = all_asleep and _max_top_drift < MAX_TOP_DRIFT
	print(
		"BENCH_TOWER result=%s blocks=%d duration_s=%.1f max_top_drift_m=%.5f all_asleep=%s" % [
			"PASS" if passed else "FAIL", TOWER_HEIGHT, RUN_SECONDS, _max_top_drift, all_asleep,
		]
	)
	get_tree().quit(0 if passed else 1)
