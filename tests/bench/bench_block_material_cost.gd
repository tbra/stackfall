extends Node3D
## Bontago-xtq.27 (M7 P2) benchmark: 300 blocks falling at once, built with
## BlockFactory's post-xtq.27 two-MeshInstance3D-per-block visual (the toon/
## cell-grid ShaderMaterial pass plus the inverted-hull outline pass sharing
## the same merged ArrayMesh -- see game/BlockFactory.gd's own DECISION
## comment). This is bench_rain.gd's exact spawn pattern, kept as a separate
## script so a regression in the *material/mesh-instance-count* cost this
## milestone added shows up on its own machine-readable line rather than
## being folded into (or confused with) bench_rain's pre-existing baseline.
## Run headless:
##   godot --headless --path . res://tests/bench/bench_block_material_cost.tscn
## Prints one machine-readable result line, then quits.
##
## Note: headless timing on any one machine is only a proxy for real in-game
## frame time (no rendering, no vsync, possibly different CPU contention), so
## treat the printed number as a relative regression check rather than an
## absolute guarantee of 120 fps in the shipped game.

const BLOCK_COUNT: int = 300
const RUN_SECONDS: float = 5.0
const TARGET_STEP_MS: float = 1000.0 / 120.0
const SPAWN_RADIUS: float = 20.0
const SPAWN_HEIGHT_MIN: float = 15.0
const SPAWN_HEIGHT_MAX: float = 40.0
const RNG_SEED: int = 1

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _budgets: BenchBudgets = preload("res://config/bench_budgets.tres")
var _tick: int = 0
var _total_ticks: int = 0
var _step_time_sum_ms: float = 0.0
var _step_time_max_ms: float = 0.0
var _elapsed_sim_seconds: float = 0.0
var _build_time_ms: float = 0.0
## Peak per-frame render counters seen over the run (Bontago-xtq.38): the
## bench has no floor, so the 300 blocks free-fall out of the camera's view
## within the RUN_SECONDS sim; sampling only at the end reads ~1 object.
## Each physics tick reads the last rendered frame's info and keeps the max.
var _max_draw_calls: int = 0
var _max_objects: int = 0


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))

	var field: Field = Field.new()
	add_child(field)

	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED

	var build_start_usec: int = Time.get_ticks_usec()
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
	_build_time_ms = float(Time.get_ticks_usec() - build_start_usec) / 1000.0

	# Bontago-xtq.38: add Camera3D and DirectionalLight3D for windowed render sampling.
	# Only add these when not running headless; headless runs skip render metrics anyway.
	if DisplayServer.get_name() != "headless":
		var field_center_y: float = (SPAWN_HEIGHT_MIN + SPAWN_HEIGHT_MAX) / 2.0

		var camera: Camera3D = Camera3D.new()
		var camera_distance: float = _budgets.bench_camera_distance
		var camera_height: float = _budgets.bench_camera_height
		camera.global_position = Vector3(camera_distance, field_center_y + camera_height, camera_distance)
		camera.look_at(Vector3(0.0, field_center_y, 0.0), Vector3.UP)
		add_child(camera)
		camera.make_current()

		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.global_rotation = Vector3(-PI / 4.0, -PI / 4.0, 0.0)
		add_child(light)

	print(
		"BENCH_BLOCK_MATERIAL_COST start blocks=%d duration_s=%.1f build_time_ms=%.3f" % [
			BLOCK_COUNT, RUN_SECONDS, _build_time_ms,
		]
	)


func _physics_process(delta: float) -> void:
	_tick += 1
	_elapsed_sim_seconds += delta
	var step_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_step_time_sum_ms += step_ms
	_step_time_max_ms = max(_step_time_max_ms, step_ms)
	_max_draw_calls = maxi(_max_draw_calls, RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	))
	_max_objects = maxi(_max_objects, RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
	))

	if _tick < _total_ticks:
		return

	var avg_step_ms: float = _step_time_sum_ms / float(_tick)
	var equivalent_fps: float = 1000.0 / avg_step_ms if avg_step_ms > 0.0 else 0.0
	var passed: bool = avg_step_ms <= TARGET_STEP_MS
	print(
		(
			"BENCH_BLOCK_MATERIAL_COST result=%s blocks=%d elapsed_sim_s=%.2f "
			+ "avg_physics_step_ms=%.4f max_physics_step_ms=%.4f equivalent_fps=%.1f "
			+ "target_step_ms=%.4f build_time_ms=%.3f note=headless_timing_is_a_proxy_only"
		) % [
			"PASS" if passed else "FAIL", BLOCK_COUNT, _elapsed_sim_seconds,
			avg_step_ms, _step_time_max_ms, equivalent_fps, TARGET_STEP_MS, _build_time_ms,
		]
	)

	var render_passed: bool = _report_render_metric()
	get_tree().quit(0 if (passed and render_passed) else 1)


## Bontago-xtq.38: the M7 outline pass doubles MeshInstance3D count per
## block (see game/BlockFactory.gd's DECISION comment), which nothing else
## here catches as a draw-call/object-count regression. Samples
## RenderingServer's per-frame render info (peak over the run, see
## _max_draw_calls) and compares it against config/bench_budgets.tres. Headless
## runs have no rendering backend, so RenderingServer.get_rendering_info() always
## reports 0 there;
## that case (and DisplayServer.get_name() == "headless") is reported as
## skipped rather than as a pass or a fail. Returns true when the check
## passed or was skipped, false only on a real (windowed) budget breach --
## the only case that should flip the process exit code.
func _report_render_metric() -> bool:
	var draw_calls: int = _max_draw_calls
	var objects: int = _max_objects
	var headless: bool = (
		DisplayServer.get_name() == "headless" or (draw_calls == 0 and objects == 0)
	)
	if headless:
		print("BENCH_BLOCK_MATERIAL_COST render metric skipped (headless)")
		return true

	var draw_calls_passed: bool = draw_calls <= _budgets.block_material_cost_draw_call_budget
	var objects_passed: bool = objects <= _budgets.block_material_cost_object_budget
	var render_passed: bool = draw_calls_passed and objects_passed
	print(
		(
			"BENCH_BLOCK_MATERIAL_COST render_result=%s draw_calls=%d "
			+ "draw_call_budget=%d objects=%d object_budget=%d"
		) % [
			"PASS" if render_passed else "FAIL",
			draw_calls, _budgets.block_material_cost_draw_call_budget,
			objects, _budgets.block_material_cost_object_budget,
		]
	)
	return render_passed
