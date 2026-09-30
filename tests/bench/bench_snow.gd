extends Node3D
## Bontago-22y.6 benchmark: physics cost of snow on a 300-block pile. Drops
## 300 blocks (bench_rain's spawn), lets them settle, then measures the
## average and worst physics step for a baseline window without snow and a
## window with snow growing to full depth (fast growth so every level, the
## disc and the rebuild/re-sleep path are exercised inside the window).
##   godot --headless --path . --fixed-fps 60 res://tests/bench/bench_snow.tscn
## Prints one BENCH_SNOW line, then quits. Headless timing is a proxy only.

const BLOCK_COUNT: int = 300
const SETTLE_SECONDS: float = 8.0
const BASELINE_SECONDS: float = 4.0
const SNOW_SECONDS: float = 8.0
const TARGET_STEP_MS: float = 1000.0 / 120.0
const SPAWN_RADIUS: float = 20.0
const SPAWN_HEIGHT_MIN: float = 15.0
const SPAWN_HEIGHT_MAX: float = 40.0
const RNG_SEED: int = 1
const SNOW_SEED: int = 7
## Fast growth so all depth levels land inside the measured window.
const BENCH_SECONDS_PER_LEVEL: float = 1.0

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _field: Field = null
var _blocks: Array[Block] = []
var _effect: SnowEffect = null
var _tick: int = 0
var _phase: int = 0
var _phase_ticks: int = 0
var _sum_ms: Array[float] = [0.0, 0.0]
var _max_ms: Array[float] = [0.0, 0.0]
var _count: Array[int] = [0, 0]
var _awake_sum: Array[int] = [0, 0]
var _effect_ms_sum: float = 0.0
var _label: String = ""
var _hold: bool = false
var _last_tick_ms: float = 0.0
var _prev_us: int = 0
var _hold_sum: float = 0.0
var _hold_n: int = 0
var _effect_ms_max: float = 0.0


func _ready() -> void:
	_field = Field.new()
	add_child(_field)
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	for i: int in range(BLOCK_COUNT):
		var shape: BlockShape = shapes[rng.randi_range(0, shapes.size() - 1)]
		var block: Block = BlockFactory.build(shape, _tuning)
		block.net_id = i + 1
		add_child(block)
		var radius: float = rng.randf_range(0.0, SPAWN_RADIUS)
		var angle: float = rng.randf_range(0.0, TAU)
		block.global_position = Vector3(cos(angle) * radius, rng.randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX), sin(angle) * radius)
		_blocks.append(block)
	print("BENCH_SNOW start blocks=%d" % BLOCK_COUNT)


func _physics_process(delta: float) -> void:
	_tick += 1
	if _prev_us == 0:
		_prev_us = Time.get_ticks_usec()
	_phase_ticks += 1
	var ticks_per_s: float = float(Engine.physics_ticks_per_second)
	if _phase == 0:
		if _phase_ticks >= int(SETTLE_SECONDS * ticks_per_s):
			_next_phase()
		return
	var awake: int = 0
	for block: Block in _blocks:
		if is_instance_valid(block) and not block.sleeping:
			awake += 1
	if _effect != null and not _hold:
		var t0: int = Time.get_ticks_usec()
		_effect.tick(delta, 1.0)
		var tick_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		_effect_ms_sum += tick_ms
		_effect_ms_max = maxf(_effect_ms_max, tick_ms)
		_last_tick_ms = tick_ms
	var slot: int = _phase - 1
	# Wall time since the previous physics callback: one whole engine frame
	# (physics step + scripts). Run with --fixed-fps 60 so frames are not
	# paced; Performance.TIME_PHYSICS_PROCESS is only sampled about once a
	# second and aliases with the once-per-level rebuild.
	var now_us: int = Time.get_ticks_usec()
	var ms: float = float(now_us - _prev_us) / 1000.0
	_prev_us = now_us
	if slot == 1 and OS.get_cmdline_user_args().has("--trace"):
		print("TRACE f=%d ms=%.2f tick=%.2f awake=%d work=%d built=%d tracked=%d" % [_phase_ticks, ms, _last_tick_ms, awake, _effect.pending_work(), _effect.builder().patches_built, _effect.tracked_block_count()])
	_sum_ms[slot] += ms
	_max_ms[slot] = maxf(_max_ms[slot], ms)
	_count[slot] += 1
	_awake_sum[slot] += awake
	var window: float = BASELINE_SECONDS if _phase == 1 else SNOW_SECONDS
	if _phase == 2 and _phase_ticks >= int(window * ticks_per_s) and not _hold and OS.get_cmdline_user_args().has("--hold"):
		_hold = true
		_phase_ticks = 0
		return
	if _hold:
		_hold_sum += ms
		_hold_n += 1
		if _phase_ticks >= int(BASELINE_SECONDS * ticks_per_s):
			print("BENCH_SNOW hold_avg_ms=%.4f awake=%d" % [_hold_sum / float(_hold_n), awake])
			_hold = false
			_next_phase()
		return
	if _phase_ticks >= int(window * ticks_per_s):
		_next_phase()


func _next_phase() -> void:
	_phase += 1
	_phase_ticks = 0
	if _phase == 1 and OS.get_cmdline_user_args().has("--stable-freeze"):
		# What game/StableBlockManager does in a real match after
		# PhysicsTuning.stable_freeze_delay_s asleep (snow comes later).
		var frozen: int = 0
		for block: Block in _blocks:
			if is_instance_valid(block) and block.sleeping:
				block.request_freeze_static(Block.FREEZE_REASON_STABLE)
				frozen += 1
		print("BENCH_SNOW stable_frozen=%d" % frozen)
	if _phase == 2:
		var snow: SnowTuning = (load("res://config/weather/snow.tres") as SnowTuning).duplicate() as SnowTuning
		snow.seconds_per_level = BENCH_SECONDS_PER_LEVEL
		# Diagnostics: --no-disc / --no-blocks / --no-resleep isolate a cost.
		var args: PackedStringArray = OS.get_cmdline_user_args()
		if args.has("--no-disc"):
			snow.max_disc_patches = 0
		if args.has("--no-blocks"):
			snow.max_block_patches = 0
		if args.has("--no-resleep"):
			snow.restore_sleep_after_rebuild = false
		_label = " ".join(args)
		_effect = SnowEffect.new()
		_effect.bind(null, snow)
		_effect.set_world(_field, func() -> Array[Block]: return _blocks)
		_effect.set_seed(SNOW_SEED)
	elif _phase == 3:
		var base_avg: float = _sum_ms[0] / maxf(float(_count[0]), 1.0)
		var snow_avg: float = _sum_ms[1] / maxf(float(_count[1]), 1.0)
		print(("BENCH_SNOW result=%s blocks=%d baseline_avg_ms=%.4f baseline_max_ms=%.4f baseline_avg_awake=%.1f "
			+ "snow_avg_ms=%.4f snow_max_ms=%.4f snow_avg_awake=%.1f effect_tick_avg_ms=%.4f effect_tick_max_ms=%.4f colliders=%d block_patches=%d patches_built=%d commits=%d queries=%d target_step_ms=%.4f args=%s")
			% ["PASS" if snow_avg <= TARGET_STEP_MS else "FAIL", BLOCK_COUNT, base_avg, _max_ms[0],
			float(_awake_sum[0]) / maxf(float(_count[0]), 1.0), snow_avg, _max_ms[1],
			float(_awake_sum[1]) / maxf(float(_count[1]), 1.0), _effect_ms_sum / maxf(float(_count[1]), 1.0), _effect_ms_max, _effect.collider_count(),
			_effect.active_block_patches(), _effect.builder().patches_built, _effect.builder().commits, _effect.queries_run, TARGET_STEP_MS, _label])
		_effect.restore()
		get_tree().quit(0 if snow_avg <= TARGET_STEP_MS else 1)

