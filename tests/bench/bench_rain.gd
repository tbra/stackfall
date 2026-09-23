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
##
## Add --preset=<id> (Bontago-xtq.17 review fix SHOULD-FIX 2; id = a file stem
## under config/physics_presets/, e.g. "heavy_bouncy") to run this bench
## against one of ui/TuningPanel.gd's shipped presets instead of the default
## shipped config/physics_tuning.tres:
##   godot --headless --path . res://tests/bench/bench_rain.tscn -- --preset=heavy_damped

const BLOCK_COUNT: int = 300
const RUN_SECONDS: float = 5.0
const TARGET_STEP_MS: float = 1000.0 / 120.0
const SPAWN_RADIUS: float = 20.0
const SPAWN_HEIGHT_MIN: float = 15.0
const SPAWN_HEIGHT_MAX: float = 40.0
const RNG_SEED: int = 1
## --preset=<id>; absent (the default) uses the shipped config/physics_tuning.tres.
const PRESET_ARG_PREFIX: String = "--preset="
## Where --preset=<id> resolves `<id>.tres` from.
const PRESET_DIR: String = "res://config/physics_presets/"

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Which tuning source produced `_tuning`, for the printed result line --
## "shipped" (default) or the --preset= id.
var _preset_label: String = "shipped"
var _tick: int = 0
var _total_ticks: int = 0
var _step_time_sum_ms: float = 0.0
var _elapsed_sim_seconds: float = 0.0


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(PRESET_ARG_PREFIX):
			_apply_preset_arg(arg.substr(PRESET_ARG_PREFIX.length()))

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

	print("BENCH_RAIN start blocks=%d duration_s=%.1f preset=%s" % [BLOCK_COUNT, RUN_SECONDS, _preset_label])


## Loads `config/physics_presets/<id>.tres` and replaces `_tuning` with it,
## called from _ready() before any block is built -- mirrors bench_tower.gd's
## own _apply_preset_arg(). An id that doesn't resolve to a real preset .tres
## is reported and left on the shipped default rather than silently
## mis-running with a null tuning.
func _apply_preset_arg(preset_id: String) -> void:
	var path: String = PRESET_DIR + preset_id + ".tres"
	var preset: PhysicsTuning = ResourceLoader.load(path) as PhysicsTuning
	if preset == null:
		push_error("BENCH_RAIN --preset=%s did not resolve a PhysicsTuning at %s; using the shipped default." % [preset_id, path])
		return
	_tuning = preset
	_preset_label = preset_id


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
			+ "equivalent_fps=%.1f target_step_ms=%.4f preset=%s note=headless_timing_is_a_proxy_only"
		) % [
			"PASS" if passed else "FAIL", BLOCK_COUNT, _elapsed_sim_seconds,
			avg_step_ms, equivalent_fps, TARGET_STEP_MS, _preset_label,
		]
	)
	get_tree().quit(0 if passed else 1)
