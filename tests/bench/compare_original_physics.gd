extends Node3D
## Bounded physics measurement, not a pass/fail benchmark. Run separately with
## --mode=drop and --mode=stack; see docs/PHYSICS_COMPARISON.md.

const CUBE: BlockShape = preload("res://config/blocks/cube.tres")
const TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
const DURATION_S: float = 10.0
const STACK_COUNT: int = 3
const DEFAULT_STACK_INTERVAL_S: float = 2.0
const DEFAULT_DROP_HEIGHT_CUBES: float = 2.0

var _mode: String = "drop"
var _drop_height_cubes: float = DEFAULT_DROP_HEIGHT_CUBES
var _stack_interval_s: float = DEFAULT_STACK_INTERVAL_S
var _stack_gap_cubes: float = TUNING.hover_height / TUNING.cube_size
var _field: Field
var _blocks: Array[RigidBody3D] = []
var _tick: int = 0
var _duration_ticks: int = 0
var _release_y: float = 0.0
var _first_contact_tick: int = -1
var _first_asleep_tick: int = -1
var _rebound_peak_y: float = -INF
var _max_lateral_drift: float = 0.0
var _stack_observation_start_tick: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--drop-height-cubes="):
			_drop_height_cubes = arg.trim_prefix("--drop-height-cubes=").to_float()
		elif arg.begins_with("--stack-interval-s="):
			_stack_interval_s = arg.trim_prefix("--stack-interval-s=").to_float()
		elif arg.begins_with("--stack-gap-cubes="):
			_stack_gap_cubes = arg.trim_prefix("--stack-gap-cubes=").to_float()
	if _mode != "drop" and _mode != "stack":
		push_error("PHYSICS_COMPARE invalid mode: %s" % _mode)
		get_tree().quit(2)
		return
	if _drop_height_cubes <= 0.0:
		push_error("PHYSICS_COMPARE drop height must be positive")
		get_tree().quit(2)
		return
	if _stack_interval_s <= 0.0 or 2.0 * _stack_interval_s >= DURATION_S or _stack_gap_cubes <= 0.0:
		push_error("PHYSICS_COMPARE stack interval/gap out of range")
		get_tree().quit(2)
		return
	_duration_ticks = int(ceil(DURATION_S * Engine.physics_ticks_per_second))
	_field = Field.new()
	add_child(_field)
	var edge: float = TUNING.cube_size - TUNING.cube_margin
	var rest_origin_y: float = _field.surface_y() - TUNING.cube_margin * 0.5
	_stack_observation_start_tick = int(round(2.0 * _stack_interval_s * Engine.physics_ticks_per_second))
	_spawn_block(0, rest_origin_y, edge)
	_release_y = _blocks[0].global_position.y
	print("PHYSICS_COMPARE start mode=%s cubes=%d drop_height_cubes=%.3f tick_hz=%d" % [_mode, 1 if _mode == "drop" else STACK_COUNT, _drop_height_cubes, Engine.physics_ticks_per_second])


func _spawn_block(index: int, rest_origin_y: float, edge: float) -> void:
	var block: RigidBody3D = BlockFactory.build(CUBE, TUNING)
	add_child(block)
	var y: float = rest_origin_y + _drop_height_cubes * edge if _mode == "drop" else rest_origin_y + float(index) * edge + (_stack_gap_cubes * TUNING.cube_size if index > 0 else 0.0)
	block.global_position = Vector3(0.0, y, 0.0)
	_blocks.append(block)


func _physics_process(_delta: float) -> void:
	if _blocks.is_empty():
		return
	_tick += 1
	if _mode == "stack":
		var interval_ticks: int = int(round(_stack_interval_s * Engine.physics_ticks_per_second))
		if _tick == interval_ticks or _tick == _stack_observation_start_tick:
			var edge: float = TUNING.cube_size - TUNING.cube_margin
			_spawn_block(_blocks.size(), _field.surface_y() - TUNING.cube_margin * 0.5, edge)
	var all_valid: bool = true
	var all_asleep: bool = true
	for block: RigidBody3D in _blocks:
		if not is_instance_valid(block):
			all_valid = false
			break
		all_asleep = all_asleep and block.sleeping
	if not all_valid:
		print("PHYSICS_COMPARE result={\"error\":\"block_removed\",\"mode\":\"%s\"}" % _mode)
		get_tree().quit(1)
		return
	var top: RigidBody3D = _blocks.back()
	if _mode == "drop" or _tick >= _stack_observation_start_tick:
		_max_lateral_drift = maxf(_max_lateral_drift, Vector2(top.global_position.x, top.global_position.z).length())
	if all_asleep and _first_asleep_tick < 0 and (_mode == "drop" or _tick >= _stack_observation_start_tick):
		_first_asleep_tick = _tick
	if _mode == "drop":
		var body: RigidBody3D = _blocks[0]
		var rest_y: float = _field.surface_y() - TUNING.cube_margin * 0.5
		if _first_contact_tick < 0 and body.global_position.y <= rest_y + 0.035:
			_first_contact_tick = _tick
		if _first_contact_tick >= 0:
			_rebound_peak_y = maxf(_rebound_peak_y, body.global_position.y)
	if _tick < _duration_ticks:
		return
	var seconds_per_tick: float = 1.0 / float(Engine.physics_ticks_per_second)
	var result: Dictionary = {
		"mode": _mode,
		"duration_s": DURATION_S,
		"cube_edge_m": TUNING.cube_size - TUNING.cube_margin,
		"all_asleep": all_asleep,
		"first_asleep_s": -1.0 if _first_asleep_tick < 0 else (_first_asleep_tick - (_stack_observation_start_tick if _mode == "stack" else 0)) * seconds_per_tick,
		"max_lateral_drift_cubes": _max_lateral_drift / TUNING.cube_size,
		"top_final_y_cubes": (top.global_position.y - _field.surface_y()) / TUNING.cube_size,
	}
	if _mode == "drop":
		var rest_y: float = _field.surface_y() - TUNING.cube_margin * 0.5
		result["drop_height_cubes"] = _drop_height_cubes
		result["first_contact_s"] = -1.0 if _first_contact_tick < 0 else _first_contact_tick * seconds_per_tick
		result["rebound_height_cubes"] = 0.0 if _first_contact_tick < 0 else maxf(0.0, (_rebound_peak_y - rest_y) / TUNING.cube_size)
		result["rebound_to_drop_ratio"] = 0.0 if _first_contact_tick < 0 else maxf(0.0, (_rebound_peak_y - rest_y) / (_release_y - rest_y))
	else:
		result["stack_count"] = STACK_COUNT
		result["placement_gap_cubes"] = _stack_gap_cubes
		result["stack_interval_s"] = _stack_interval_s
	print("PHYSICS_COMPARE result=" + JSON.stringify(result))
	get_tree().quit(0)
