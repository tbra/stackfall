extends Node3D
## P4 parity recipe: a scripted, tick-indexed run of the block/field/physics stack whose recorded
## state must not change across the P4 refactor. A STANDALONE Field + BlockRegistry +
## StableBlockManager on the base map, wired as production does, with no Match: Match's territory
## solves finish on a worker thread and would make hole changes load-timed.
##
## Record a run (the committed reference comes from an unmodified main):
##   godot --headless --fixed-fps 60 --path . res://tests/bench/bench_p4_parity.tscn -- --out=run.json [--rng-seed=N]
## Compare two recordings (exit 1 on any difference above --tol, default 0):
##   godot --headless --path . res://tests/bench/bench_p4_parity.tscn -- --compare=a.json,b.json [--tol=0.0001]

const OUT_ARG: String = "--out="
const COMPARE_ARG: String = "--compare="
const TOL_ARG: String = "--tol="
const SEED_ARG: String = "--rng-seed="
const DEFAULT_SEED: int = 20261022
const CUBE_PATH: String = "res://config/blocks/cube.tres"

const BLOCK_COUNT: int = 40
const COLUMN_COUNT: int = 8
## Columns sit on a ring this far (m) from the disc centre.
const RING_RADIUS_M: float = 8.0
## Each block starts this far (m) above the one below it.
const DROP_GAP_M: float = 0.05
const DROP_TICK_SPACING: int = 10
const MAX_YAW_RAD: float = 0.2
const OWNER_SLOT_COUNT: int = 4

const FUSE_TICK: int = 600
const TILT_TICK: int = 900
const TILT_MAGNITUDE: float = 0.15
const HOLE_TICK: int = 1200
const HOLE_COLUMN: int = 1
## Half-width, in cells, of the square of cells opened under the hole column.
const HOLE_CELL_RADIUS: int = 1
const KILL_TICK: int = 1500
const KILL_COLUMN: int = 2
## The pushed block is moved this far (m) beyond the rim, at disc height.
const KILL_OUTSIDE_M: float = 3.0
const END_TICK: int = 2400
const RECORD_EVERY: int = 30
const ROUND_STEP: float = 0.0001
## Block indices GlueFusion joins at FUSE_TICK (same column, adjacent levels); the lower is anchored.
const FUSE_LOWER: int = 0
const FUSE_UPPER: int = COLUMN_COUNT

var _tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _field: Field = null
var _registry: BlockRegistry = null
var _manager: StableBlockManager = null
var _blocks_root: Node3D = null
var _blocks: Array[Block] = []
var _index_of: Dictionary = {}
var _yaws: PackedFloat32Array = PackedFloat32Array()
var _shape: BlockShape = null
var _tick: int = 0
var _out_path: String = ""
var _record: Dictionary = {}
var _removed: Array = []
var _dissolving: Array = []


func _ready() -> void:
	var compare: String = ""
	var tol: float = 0.0
	var rng_seed: int = DEFAULT_SEED
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out_path = arg.substr(OUT_ARG.length())
		elif arg.begins_with(COMPARE_ARG):
			compare = arg.substr(COMPARE_ARG.length())
		elif arg.begins_with(TOL_ARG):
			tol = arg.substr(TOL_ARG.length()).to_float()
		elif arg.begins_with(SEED_ARG):
			rng_seed = arg.substr(SEED_ARG.length()).to_int()
	if not compare.is_empty():
		get_tree().quit(_compare(compare, tol))
		set_physics_process(false)
		return
	seed(rng_seed)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i: int in range(BLOCK_COUNT):
		_yaws.append(rng.randf_range(-MAX_YAW_RAD, MAX_YAW_RAD))
	_shape = load(CUBE_PATH) as BlockShape
	_build_world()
	Events.block_removed.connect(_on_block_removed)
	Events.block_dissolve_started.connect(_on_dissolve_started)


## Production wiring, minus Match: registry as host authority, configured against the field.
func _build_world() -> void:
	var map: MapDef = MapDef.base()
	_field = Field.new()
	_field.map_def = map
	add_child(_field)
	_field.set_tilt_enabled(true)
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	_registry = BlockRegistry.new()
	add_child(_registry)
	_registry.set_host_authority(true)
	_registry.configure(_field, map)
	_registry.reset()
	_field.set_registry(_registry)
	_manager = StableBlockManager.new()
	add_child(_manager)
	_manager.setup(_registry)


func _physics_process(_delta: float) -> void:
	if _tick < BLOCK_COUNT * DROP_TICK_SPACING and _tick % DROP_TICK_SPACING == 0:
		_drop(_tick / DROP_TICK_SPACING)
	match _tick:
		FUSE_TICK:
			_fuse()
		TILT_TICK:
			_field.apply_tilt_impulse(Vector2.RIGHT, TILT_MAGNITUDE)
		HOLE_TICK:
			_open_hole()
		KILL_TICK:
			_push_over_kill_plane()
	if _tick % RECORD_EVERY == 0:
		_sample()
	if _tick >= END_TICK:
		set_physics_process(false)
		_finish()
		return
	_tick += 1


func _column_position(column: int) -> Vector2:
	var angle: float = TAU * float(column) / float(COLUMN_COUNT)
	return Vector2(cos(angle), sin(angle)) * RING_RADIUS_M


func _drop(index: int) -> void:
	var column: int = index % COLUMN_COUNT
	var level: int = index / COLUMN_COUNT
	var slot: int = index % OWNER_SLOT_COUNT
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var spot: Vector2 = _column_position(column)
	var y: float = _field.surface_y() - _tuning.cube_margin * 0.5 + (edge + DROP_GAP_M) * float(level)
	var block: Block = BlockFactory.build(_shape, _tuning, slot, Color.WHITE)
	_blocks_root.add_child(block)
	block.global_transform = Transform3D(Basis(Vector3.UP, _yaws[index]), Vector3(spot.x, y, spot.y))
	Events.block_placed.emit(block, _shape.id)
	_blocks.append(block)
	_index_of[block.get_instance_id()] = index


func _fuse() -> void:
	var lower: Block = _blocks[FUSE_LOWER]
	var upper: Block = _blocks[FUSE_UPPER]
	if is_instance_valid(lower) and is_instance_valid(upper):
		GlueFusion.fuse(upper, lower, null)
		GlueFusion.fuse(lower, _field, null)


func _open_hole() -> void:
	var grid: CellGrid = _field.grid()
	var centre: Vector2i = grid.world_to_cell(_column_position(HOLE_COLUMN))
	var opened: PackedInt32Array = PackedInt32Array()
	for dy: int in range(-HOLE_CELL_RADIUS, HOLE_CELL_RADIUS + 1):
		for dx: int in range(-HOLE_CELL_RADIUS, HOLE_CELL_RADIUS + 1):
			if grid.in_bounds(centre.x + dx, centre.y + dy):
				opened.append(grid.cell_index(centre.x + dx, centre.y + dy))
	Events.hole_cells_changed.emit(opened, PackedInt32Array())


## Moves the top block of KILL_COLUMN outside the rim so it falls to the kill plane.
func _push_over_kill_plane() -> void:
	var top_level: int = (BLOCK_COUNT - 1 - KILL_COLUMN) / COLUMN_COUNT
	var block: Block = _blocks[top_level * COLUMN_COUNT + KILL_COLUMN]
	if not is_instance_valid(block):
		return
	_manager.wake_for_external_force(block)
	block.global_position = Vector3(_field.map_def.field_radius + KILL_OUTSIDE_M, _field.surface_y(), 0.0)


func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	_removed.append("%d|%d|%s" % [_tick, _index_of.get(block.get_instance_id(), -1), reason])


func _on_dissolve_started(block: RigidBody3D, _net_id: int, duration_s: float) -> void:
	_dissolving.append("%d|%d|%s" % [_tick, _index_of.get(block.get_instance_id(), -1), _r(duration_s)])


func _r(value: float) -> float:
	return snappedf(value, ROUND_STEP) + 0.0


func _sample() -> void:
	var prefix: String = "t%04d." % _tick
	for i: int in range(_blocks.size()):
		var key: String = "%sb%02d." % [prefix, i]
		var block: Block = _blocks[i]
		if not is_instance_valid(block):
			_record[key + "gone"] = 1
			continue
		var xf: Transform3D = block.global_transform
		_record[key + "owner"] = block.owner_slot
		_record[key + "px"] = _r(xf.origin.x)
		_record[key + "py"] = _r(xf.origin.y)
		_record[key + "pz"] = _r(xf.origin.z)
		var axes: Array[Vector3] = [xf.basis.x, xf.basis.y, xf.basis.z]
		for a: int in range(axes.size()):
			_record["%sbx%d" % [key, a]] = _r(axes[a].x)
			_record["%sby%d" % [key, a]] = _r(axes[a].y)
			_record["%sbz%d" % [key, a]] = _r(axes[a].z)
		_record[key + "sleeping"] = int(block.sleeping)
		_record[key + "freeze"] = int(block.is_freeze_static())
	_record[prefix + "revision"] = _registry.territory_revision()
	_record[prefix + "tilt_x"] = _r(_field.tilt_vector().x)
	_record[prefix + "tilt_y"] = _r(_field.tilt_vector().y)
	_record[prefix + "holes"] = _field.applied_hole_count()


func _finish() -> void:
	_record["events.removed"] = _removed
	_record["events.dissolve_started"] = _dissolving
	var text: String = JSON.stringify(_record, "\t", true)
	if not _out_path.is_empty():
		var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			push_error("bench_p4_parity: cannot write %s" % _out_path)
			get_tree().quit(1)
			return
		file.store_string(text)
		file.close()
	print("BENCH_P4_PARITY sha256=%s ticks=%d removed=%d dissolved=%d" % [text.sha256_text(), END_TICK, _removed.size(), _dissolving.size()])
	get_tree().quit(0)


## Prints the per-field maximum difference and returns the exit code (1 on any difference above `tol`).
func _compare(arg: String, tol: float) -> int:
	var parts: PackedStringArray = arg.split(",")
	if parts.size() != 2:
		push_error("bench_p4_parity: --compare needs a.json,b.json")
		return 1
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(parts[0]))
	var b: Variant = JSON.parse_string(FileAccess.get_file_as_string(parts[1]))
	if not (a is Dictionary and b is Dictionary):
		push_error("bench_p4_parity: unreadable recording")
		return 1
	var left: Dictionary = a as Dictionary
	var right: Dictionary = b as Dictionary
	var tolerances: Dictionary = {"": tol} if tol > 0.0 else {}
	var differing: PackedStringArray = MatchFingerprint.diff(left, right, tolerances)
	var worst: Dictionary = {}
	for line: String in differing:
		var key: String = line.get_slice(": ", 0)
		var field: String = key.get_slice(".", key.get_slice_count(".") - 1)
		var current: float = worst.get(field, 0.0)
		var numeric: bool = left.has(key) and right.has(key) and (left[key] is float or left[key] is int) and (right[key] is float or right[key] is int)
		worst[field] = maxf(current, absf(float(left[key]) - float(right[key]))) if numeric else INF
	var fields: Array = worst.keys()
	fields.sort()
	for field: String in fields:
		print("BENCH_P4_PARITY field=%s max_diff=%s" % [field, worst[field]])
	print("BENCH_P4_PARITY compare keys=%d differing=%d tol=%s" % [left.size(), differing.size(), tol])
	return 1 if not differing.is_empty() else 0
