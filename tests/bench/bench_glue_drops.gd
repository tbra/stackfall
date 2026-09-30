extends Node3D
## Bounded host-physics proxy for three charged blocks amid ordinary blocks.
## Run alone: godot --headless --path . res://tests/bench/bench_glue_drops.tscn

const BLOCK_COUNT: int = 100
const CHARGED_COUNT: int = 3
const RUN_SECONDS: float = 3.0

var _ticks: int = 0
var _total_ms: float = 0.0


func _ready() -> void:
	var charged_count: int = 0 if "--baseline" in OS.get_cmdline_user_args() else CHARGED_COUNT
	add_child(Field.new())
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var glue_tuning: GlueDropTuning = preload("res://config/glue_drop_tuning.tres")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260930
	for i: int in range(BLOCK_COUNT):
		var block: Block = BlockFactory.build(shapes[i % shapes.size()], physics_tuning) as Block
		add_child(block)
		block.global_position = Vector3(rng.randf_range(-4.0, 4.0), 3.0 + float(i) * 0.35, rng.randf_range(-4.0, 4.0))
		if i < charged_count:
			var glue: GlueDrops = GlueDrops.new()
			block.add_child(glue)
			glue.bind(block, glue_tuning)
	set_meta(&"charged_count", charged_count)
	print("BENCH_GLUE_DROPS start blocks=%d charged=%d duration_s=%.1f" % [BLOCK_COUNT, charged_count, RUN_SECONDS])


func _physics_process(_delta: float) -> void:
	_ticks += 1
	_total_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if _ticks < int(RUN_SECONDS * Engine.physics_ticks_per_second):
		return
	print("BENCH_GLUE_DROPS blocks=%d charged=%d avg_physics_step_ms=%.4f note=headless_proxy" % [BLOCK_COUNT, int(get_meta(&"charged_count")), _total_ms / float(_ticks)])
	get_tree().quit()
