extends Node3D
## Spec 3.5 benchmark: 300 blocks falling at once, which must hold >= 120 fps
## on a mid-range PC (<= 8.3 ms average physics step). Run headless:
##   godot --headless --path . res://tests/bench/bench_rain.tscn
## Prints one machine-readable result line, then quits.
##
## Note: headless timing on any one machine is only a proxy for real
## in-game frame time (no rendering, no vsync, possibly different CPU
## contention), so treat the printed number as a relative regression check
## rather than an absolute guarantee of 120 fps in the shipped game.

const BLOCK_COUNT: int = 300
const RUN_SECONDS: float = 5.0
const TARGET_STEP_MS: float = 1000.0 / 120.0
const SPAWN_RADIUS: float = 20.0
const SPAWN_HEIGHT_MIN: float = 15.0
const SPAWN_HEIGHT_MAX: float = 40.0
const RNG_SEED: int = 1

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _tick: int = 0
var _total_ticks: int = 0
var _step_time_sum_ms: float = 0.0
var _elapsed_sim_seconds: float = 0.0


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))

	var field: Field = Field.new()
	add_child(field)

	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	for _i: int in range(BLOCK_COUNT):
		var shape: BlockShape = shapes[rng.randi_range(0, shapes.size() - 1)]
		var block: RigidBody3D = BlockFactory.build(shape, _tuning)
		add_child(block)
		var radius: float = rng.randf_range(0.0, SPAWN_RADIUS)
		var angle: float = rng.randf_range(0.0, TAU)
		block.global_position = Vector3(
			cos(angle) * radius,
			rng.randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX),
			sin(angle) * radius,
		)

	print("BENCH_RAIN start blocks=%d duration_s=%.1f" % [BLOCK_COUNT, RUN_SECONDS])


func _physics_process(delta: float) -> void:
	_tick += 1
	_elapsed_sim_seconds += delta
	_step_time_sum_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	if _tick < _total_ticks:
		return

	var avg_step_ms: float = _step_time_sum_ms / float(_tick)
	var equivalent_fps: float = 1000.0 / avg_step_ms if avg_step_ms > 0.0 else 0.0
	var passed: bool = avg_step_ms <= TARGET_STEP_MS
	print(
		(
			"BENCH_RAIN result=%s blocks=%d elapsed_sim_s=%.2f avg_physics_step_ms=%.4f "
			+ "equivalent_fps=%.1f target_step_ms=%.4f note=headless_timing_is_a_proxy_only"
		) % [
			"PASS" if passed else "FAIL", BLOCK_COUNT, _elapsed_sim_seconds,
			avg_step_ms, equivalent_fps, TARGET_STEP_MS,
		]
	)
	get_tree().quit(0 if passed else 1)
