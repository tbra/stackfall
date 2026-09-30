extends Node3D
## Paired headless physics proxy: 300 falling blocks, then 300 plus one
## default Stackfall rain (12 more). Run each variant alone.

const BASE_BODIES: int = 300
const RAIN_BODIES: int = 12
const RUN_SECONDS: float = 5.0

var _ticks: int = 0
var _total_ms: float = 0.0
var _extra: int = 0


func _ready() -> void:
	_extra = RAIN_BODIES if "--stackfall" in OS.get_cmdline_user_args() else 0
	add_child(Field.new())
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var shape: BlockShape = preload("res://config/blocks/cube.tres")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260930
	for i: int in range(BASE_BODIES + _extra):
		var block: Block = BlockFactory.build(shape, tuning)
		add_child(block)
		var radius: float = rng.randf_range(0.0, 20.0)
		var angle: float = rng.randf_range(0.0, TAU)
		block.global_position = Vector3(cos(angle) * radius, rng.randf_range(15.0, 40.0), sin(angle) * radius)
	print("BENCH_STACKFALL_PHYSICS start bodies=%d" % (BASE_BODIES + _extra))


func _physics_process(_delta: float) -> void:
	_ticks += 1
	_total_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if _ticks < int(RUN_SECONDS * Engine.physics_ticks_per_second):
		return
	print("BENCH_STACKFALL_PHYSICS bodies=%d avg_physics_step_ms=%.4f note=headless_proxy" % [BASE_BODIES + _extra, _total_ms / float(_ticks)])
	get_tree().quit()
