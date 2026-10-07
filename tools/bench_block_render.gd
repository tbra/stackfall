extends Node3D
## Windowed GPU-cost probe for the block toon + outline materials
## (Bontago-adt.2): 300 frozen blocks in view, reports the average GPU render
## time (RenderingServer.viewport_get_measured_render_time_gpu) and CPU frame
## time over a fixed number of frames. Run off-screen:
##   godot --path . --position 10000,10000 tools/bench_block_render.tscn
## Optional user args after `--`:
##   --legacy=1   swap in user://legacy_block_*.gdshader (the
##                pre-rework shaders, extracted with `git show`) for a
##                before/after comparison.
##   --far=1      double the camera distance (many-blocks-at-distance case).
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts).

const BLOCK_COUNT: int = 300
const GRID_COLUMNS: int = 20
const GRID_SPACING_M: float = 3.0
const WARMUP_FRAMES: int = 30
const MEASURE_FRAMES: int = 180
const CAMERA_DISTANCE_M: float = 40.0
const CAMERA_HEIGHT_M: float = 35.0
const LEGACY_CELL_SHADER: String = "user://legacy_block_cell_grid.gdshader"
const LEGACY_OUTLINE_SHADER: String = "user://legacy_block_outline.gdshader"

var _frame: int = 0
var _gpu_sum_ms: float = 0.0
var _cpu_sum_ms: float = 0.0
var _label: String = "new"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var legacy: bool = args.has("--legacy=1")
	var far: bool = args.has("--far=1")
	_label = "legacy" if legacy else "new"
	if far:
		_label += "_far"
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	var legacy_cell: ShaderMaterial = null
	var legacy_outline: ShaderMaterial = null
	if legacy:
		legacy_cell = ShaderMaterial.new()
		legacy_cell.shader = load(LEGACY_CELL_SHADER)
		legacy_outline = ShaderMaterial.new()
		legacy_outline.shader = load(LEGACY_OUTLINE_SHADER)
	for i: int in range(BLOCK_COUNT):
		var shape: BlockShape = shapes[rng.randi_range(0, shapes.size() - 1)]
		var color: Color = colors[i % colors.size()]
		var block: Block = BlockFactory.build(shape, tuning, i % colors.size(), color)
		block.freeze = true
		add_child(block)
		var col: int = i % GRID_COLUMNS
		var row: int = i / GRID_COLUMNS
		block.global_position = Vector3(
			(float(col) - GRID_COLUMNS * 0.5) * GRID_SPACING_M, 0.0,
			(float(row) - 7.0) * GRID_SPACING_M
		)
		if legacy:
			for child: Node in block.get_children():
				var mesh_instance: MeshInstance3D = child as MeshInstance3D
				if mesh_instance == null:
					continue
				if mesh_instance.name == &"BlockMesh":
					var mat: ShaderMaterial = legacy_cell.duplicate() as ShaderMaterial
					mat.set_shader_parameter(&"albedo_color", color)
					mat.next_pass = legacy_outline
					mesh_instance.material_override = mat

	var distance_scale: float = 2.0 if far else 1.0
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(
		0.0, CAMERA_HEIGHT_M * distance_scale, CAMERA_DISTANCE_M * distance_scale
	)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation = Vector3(-PI / 4.0, -PI / 4.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return
	_gpu_sum_ms += RenderingServer.viewport_get_measured_render_time_gpu(
		get_viewport().get_viewport_rid()
	)
	_cpu_sum_ms += delta * 1000.0
	if _frame < WARMUP_FRAMES + MEASURE_FRAMES:
		return
	print("BENCH_BLOCK_RENDER label=%s blocks=%d avg_gpu_ms=%.3f avg_frame_ms=%.3f" % [
		_label, BLOCK_COUNT, _gpu_sum_ms / float(MEASURE_FRAMES), _cpu_sum_ms / float(MEASURE_FRAMES)
	])
	get_tree().quit()
