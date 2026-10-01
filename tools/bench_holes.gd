extends Node3D
## Bontago-1pi.11.39 / .41: cost of disc holes at the default map (round_medium).
##   godot --headless --path . res://tools/bench_holes.tscn [-- --blocks=200]
## Since Bontago-1pi.11.41 holes never touch the disc collision; a hole change is
## Field applying the cell plus the host HoleDissolver's contact query. Prints
## HOLES_* lines: per-change cost (single/batch, open and close), disc rebuilds
## during hole changes (must be 0), how many sleeping bodies wake after a far
## hole and after a hole under one block (that block should dissolve, nothing
## else wake), and physics-process time with many holes. Measurement only.

const SINGLE_TOGGLES: int = 50
const BATCH_HOLES: int = 20
const MANY_HOLES: int = 150
const SETTLE_MAX_TICKS: int = 1800
const WATCH_TICKS: int = 12
## Long enough for the dissolve delay (0.35 s) plus slack.
const DISSOLVE_WATCH_TICKS: int = 45
const TIMING_TICKS: int = 120
const BLOCK_SPACING: float = 2.4
## Cells farther than this from the disc centre are clear of the block grid.
const FAR_RADIUS: float = 30.0
const FAR_LOCAL: Vector2 = Vector2(40.0, 0.0)

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _field: Field
var _registry: BlockRegistry
var _blocks: Array[RigidBody3D] = []
var _block_count: int = 200
var _removed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state: String = "settle"
var _tick: int = 0
var _watch_label: String = ""
var _watch_peak: int = 0
var _watch_before: int = 0
var _watch_ticks: int = WATCH_TICKS
var _watch_removed_before: int = 0
var _watch_series: PackedInt32Array = PackedInt32Array()
var _timing_sum: float = 0.0
var _timing_label: String = ""
var _steps: Array[Callable] = []
var _step_index: int = -1


func _ready() -> void:
	_rng.seed = 11039
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--blocks="):
			_block_count = arg.trim_prefix("--blocks=").to_int()
	_field = Field.new()
	add_child(_field)
	_registry = BlockRegistry.new()
	add_child(_registry)
	_registry.set_host_authority(true)
	_registry.configure(_field, _field.map_def)
	Events.block_removed.connect(_on_removed)
	print("HOLES_GRID res=%d in_disk_cells=%d cell_size=%.2f radius=%.1f disk_build_ms=%.3f" % [
		_field.grid().res, _field.cell_count(), _field.map_def.cell_size, _field.map_def.field_radius,
		float(_field._max_rebuild_usec) / 1000.0])
	_spawn_blocks()
	_state = "settle"


func _on_removed(_block: RigidBody3D, _reason: String) -> void:
	_removed += 1


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _far_cells(count: int) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	var all: PackedInt32Array = _field.grid().in_disk_cells()
	while cells.size() < count:
		var cell: int = all[_rng.randi_range(0, all.size() - 1)]
		if _field.grid().index_center(cell).length() > FAR_RADIUS and not cells.has(cell):
			cells.append(cell)
	return cells


## One hole change through the real path (set_hole_cells + one drain, which
## includes the dissolver's contact query), in ms.
func _timed_change(opened: PackedInt32Array, closed: PackedInt32Array) -> float:
	var t0: int = Time.get_ticks_usec()
	_field.set_hole_cells(opened, closed)
	_field._drain_toggles()
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _change_timings() -> void:
	var builds: int = _field.disk_mesh_build_count()
	var opens: Array[float] = []
	var closes: Array[float] = []
	for cell: int in _far_cells(SINGLE_TOGGLES):
		var one: PackedInt32Array = PackedInt32Array([cell])
		opens.append(_timed_change(one, PackedInt32Array()))
		closes.append(_timed_change(PackedInt32Array(), one))
	print("HOLES_CHANGE_SINGLE_MS n=%d open_median=%.4f open_max=%.4f close_median=%.4f close_max=%.4f" % [
		opens.size(), _median(opens), opens.max(), _median(closes), closes.max()])
	var batch: Array[float] = []
	for rep: int in range(10):
		var group: PackedInt32Array = _far_cells(BATCH_HOLES)
		batch.append(_timed_change(group, PackedInt32Array()))
		_timed_change(PackedInt32Array(), group)
	print("HOLES_CHANGE_BATCH%d_MS n=%d median=%.4f max=%.4f" % [BATCH_HOLES, batch.size(), _median(batch), batch.max()])
	print("HOLES_DISK_REBUILDS_DURING_CHANGES %d" % (_field.disk_mesh_build_count() - builds))


func _spawn_blocks() -> void:
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	var y: float = _field.surface_y() + 0.05
	var per_row: int = int(ceil(sqrt(float(_block_count))))
	var origin: float = -float(per_row - 1) * BLOCK_SPACING * 0.5
	for i: int in range(_block_count):
		var block: Block = BlockFactory.build(cube, _tuning)
		add_child(block)
		block.global_position = Vector3(
			origin + float(i % per_row) * BLOCK_SPACING, y, origin + float(i / per_row) * BLOCK_SPACING)
		Events.block_placed.emit(block, cube.id)
		_blocks.append(block)


func _live() -> Array[RigidBody3D]:
	var live: Array[RigidBody3D] = []
	for block: RigidBody3D in _blocks:
		if is_instance_valid(block) and not block.is_queued_for_deletion():
			live.append(block)
	return live


func _awake() -> int:
	var count: int = 0
	for block: RigidBody3D in _live():
		if not block.sleeping and not block.freeze:
			count += 1
	return count


func _begin_watch(label: String, ticks: int = WATCH_TICKS) -> void:
	_watch_label = label
	_watch_peak = 0
	_watch_ticks = ticks
	_watch_removed_before = _removed
	_watch_series = PackedInt32Array()
	_tick = 0
	_state = "watch"


func _physics_process(_delta: float) -> void:
	_tick += 1
	match _state:
		"settle":
			if _awake() == 0 or _tick >= SETTLE_MAX_TICKS:
				print("HOLES_SETTLED blocks=%d awake=%d ticks=%d" % [_live().size(), _awake(), _tick])
				_run_next()
		"resettle":
			if _awake() == 0 or _tick >= SETTLE_MAX_TICKS:
				_run_next()
		"watch":
			var awake: int = _awake()
			_watch_series.append(awake)
			_watch_peak = maxi(_watch_peak, awake)
			if _tick >= _watch_ticks:
				print("HOLES_WAKE %s awake_before=%d peak_after=%d removed=%d dissolves_started=%d series=%s" % [
					_watch_label, _watch_before, _watch_peak, _removed - _watch_removed_before,
					_registry.hole_dissolver().dissolves_started, str(_watch_series)])
				_run_next()
		"timing":
			_timing_sum += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
			if _tick >= TIMING_TICKS:
				print("HOLES_TICK_COST %s physics_process_avg_ms=%.4f active_bodies=%d" % [
					_timing_label, _timing_sum / float(TIMING_TICKS),
					int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])
				_run_next()


func _run_next() -> void:
	if _steps.is_empty():
		_steps = [
			_step_changes, _step_far_real, _resettle, _step_near_real, _resettle,
			_step_timing_a, _step_timing_b, _step_done,
		]
	_step_index += 1
	_steps[_step_index].call()


func _resettle() -> void:
	_tick = 0
	_state = "resettle"


func _cell_at(local: Vector2) -> int:
	var c: Vector2i = _field.grid().world_to_cell(local)
	return _field.grid().cell_index(c.x, c.y)


func _step_changes() -> void:
	_change_timings()
	_watch_before = _awake()
	_begin_watch("after_change_timings")


## The real path: set_hole_cells, drained by Field's own next physics frame.
func _step_far_real() -> void:
	_watch_before = _awake()
	_field.set_hole_cells(PackedInt32Array([_cell_at(FAR_LOCAL)]), PackedInt32Array())
	_begin_watch("far_hole_real_path")


## A hole under one block: that block should dissolve; nothing else wakes.
func _step_near_real() -> void:
	_field.set_hole_cells(PackedInt32Array(), PackedInt32Array([_cell_at(FAR_LOCAL)]))
	var live: Array[RigidBody3D] = _live()
	var block: RigidBody3D = live[live.size() / 2]
	var cell: int = _cell_at(_field.disk_local_from_world(block.global_position))
	_watch_before = _awake()
	_field.set_hole_cells(PackedInt32Array([cell]), PackedInt32Array())
	_begin_watch("under_block_real_path", DISSOLVE_WATCH_TICKS)


func _step_timing_a() -> void:
	_timing_label = "few_holes_settled"
	_timing_sum = 0.0
	_tick = 0
	_state = "timing"


func _step_timing_b() -> void:
	var cells: PackedInt32Array = PackedInt32Array()
	for cell: int in _field.grid().in_disk_cells():
		if _field.grid().index_center(cell).length() > 36.0 and cells.size() < MANY_HOLES and (cell % 7) == 0:
			cells.append(cell)
	_field.set_hole_cells(cells, PackedInt32Array())
	while _field.pending_toggle_count() > 0:
		_field._drain_toggles()
	_timing_label = "holes=%d_settled" % _field.applied_hole_count()
	_timing_sum = 0.0
	_tick = 0
	_state = "timing"


func _step_done() -> void:
	print("HOLES_DONE awake_end=%d live=%d removed_total=%d disk_builds_total=%d" % [
		_awake(), _live().size(), _removed, _field.disk_mesh_build_count()])
	get_tree().quit()
