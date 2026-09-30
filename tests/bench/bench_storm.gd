extends Node3D
## Bontago-22y.4: wind cost on a 300-block moving pile. Run twice, alone:
##   godot --headless --path . res://tests/bench/bench_storm.tscn
##   godot --headless --path . res://tests/bench/bench_storm.tscn -- wind
## Prints avg physics step ms and the effect's own per-tick cost. Headless
## timing is a proxy only.

const BLOCK_COUNT: int = 300
const RUN_SECONDS: float = 12.0
const SPAWN_RADIUS: float = 7.0
const SPAWN_HEIGHT_MIN: float = 1.0
const SPAWN_HEIGHT_MAX: float = 30.0
const RNG_SEED: int = 1
const WARMUP_TICKS: int = 60

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _wind: StormEffect = null
var _blocks: Array[Block] = []
var _tick: int = 0
var _total_ticks: int = 0
var _step_sum_ms: float = 0.0
var _effect_sum_us: int = 0
var _samples: int = 0
var _pushed_sum: int = 0
var _use_wind: bool = false


func _ready() -> void:
	_use_wind = OS.get_cmdline_user_args().has("wind")
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))
	var field: Field = Field.new()
	add_child(field)
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	for _i: int in range(BLOCK_COUNT):
		var shape: BlockShape = shapes[rng.randi_range(0, shapes.size() - 1)]
		var block: Block = BlockFactory.build(shape, _tuning)
		add_child(block)
		var radius: float = rng.randf_range(0.0, SPAWN_RADIUS)
		var angle: float = rng.randf_range(0.0, TAU)
		block.global_position = Vector3(cos(angle) * radius, rng.randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX), sin(angle) * radius)
		_blocks.append(block)
	_wind = StormEffect.new()
	_wind.tuning = load("res://config/weather/storm.tres") as WeatherTuning
	_wind.set_seed(1)
	_wind.set_test_world(func() -> Array: return _blocks, func() -> float: return 0.0)


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick > WARMUP_TICKS:
		_step_sum_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_samples += 1
	if _use_wind:
		var start_us: int = Time.get_ticks_usec()
		_wind.tick(delta, 1.0)
		if _tick > WARMUP_TICKS:
			_effect_sum_us += Time.get_ticks_usec() - start_us
			_pushed_sum += _wind.last_pushed
	if _tick < _total_ticks:
		return
	var alive: int = 0
	var asleep: int = 0
	for block: Block in _blocks:
		if is_instance_valid(block):
			alive += 1
			asleep += 1 if block.sleeping else 0
	print("BENCH_WIND wind=%s blocks=%d alive=%d asleep=%d avg_physics_step_ms=%.4f effect_tick_us=%.1f avg_pushed=%.1f" % [
		_use_wind, BLOCK_COUNT, alive, asleep, _step_sum_ms / float(maxi(_samples, 1)),
		float(_effect_sum_us) / float(maxi(_samples, 1)), float(_pushed_sum) / float(maxi(_samples, 1)),
	])
	get_tree().quit()
