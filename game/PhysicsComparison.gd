class_name PhysicsComparison
extends Node3D
## Controlled measurement on an existing Field. Bodies are outside Match's
## registry: they cannot award territory or consume the block bag.
signal finished(result: Dictionary)
const CUBE: BlockShape = preload("res://config/blocks/cube.tres")
const DURATION_S: float = 10.0
const STACK_COUNT: int = 3
var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var running: bool = false
var result: Dictionary = {}
var blocks: Array[RigidBody3D] = []
var _field: Field = null
var _mode: String = "drop"
var _height: float = 2.0
var _interval: float = 2.0
var _gap: float = 0.3
var _origin: Vector3 = Vector3.ZERO
var _tick: int = 0
var _contact_tick: int = -1
var _sleep_tick: int = -1
var _peak_y: float = -INF
var _drift: float = 0.0
var _release_y: float = 0.0
var _observation_tick: int = 0
var _snapshot: Dictionary = {}
var _trial_tuning: PhysicsTuning = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func start(field: Field, mode: String, height: float, interval: float, gap: float, origin: Vector3 = Vector3.ZERO) -> bool:
	if field == null or mode not in ["drop", "stack"] or height <= 0.0 or interval <= 0.0 or 2.0 * interval >= DURATION_S or gap <= 0.0:
		return false
	clear()
	_field = field
	_mode = mode
	_height = height
	_interval = interval
	_gap = gap
	_trial_tuning = tuning.duplicate() as PhysicsTuning
	_origin = Vector3(origin.x, field.surface_y() - _trial_tuning.cube_margin * 0.5, origin.z)
	_tick = 0
	_contact_tick = -1
	_sleep_tick = -1
	_peak_y = -INF
	_drift = 0.0
	_observation_tick = int(round(2.0 * interval * Engine.physics_ticks_per_second)) if mode == "stack" else 0
	result = {}
	_snapshot = {"gravity_multiplier": tuning.gravity_multiplier, "cube_mass": tuning.cube_mass, "block_bounce": tuning.block_bounce, "block_friction": tuning.block_friction, "linear_damp": tuning.block_linear_damp, "angular_damp": tuning.block_angular_damp, "rebound_damping": tuning.rebound_damping}
	_spawn(0)
	_release_y = blocks[0].global_position.y
	running = true
	return true

func clear() -> void:
	running = false
	for body: RigidBody3D in blocks:
		if is_instance_valid(body):
			body.freeze = true
			body.collision_layer = 0
			body.collision_mask = 0
			body.queue_free()
	blocks.clear()
	result = {}

func _spawn(index: int) -> void:
	var body: RigidBody3D = BlockFactory.build(CUBE, _trial_tuning, -1, Color(0.95, 0.55, 0.28))
	# Only these at-most-three measurement bodies pay contact-monitor costs.
	body.contact_monitor = true
	body.max_contacts_reported = 8
	add_child(body)
	body.remove_from_group(Block.TUNING_GROUP)
	var edge: float = _trial_tuning.cube_size - _trial_tuning.cube_margin
	var height: float = _height * edge if _mode == "drop" else float(index) * edge + (_gap * edge if index > 0 else 0.0)
	body.global_position = _origin + Vector3.UP * height
	blocks.append(body)

func _physics_process(_delta: float) -> void:
	if not running:
		return
	_tick += 1
	if _mode == "stack":
		var interval_ticks: int = maxi(1, int(round(_interval * Engine.physics_ticks_per_second)))
		if blocks.size() < STACK_COUNT and _tick >= interval_ticks * blocks.size():
			_spawn(blocks.size())
	var asleep: bool = true
	for body: RigidBody3D in blocks:
		if not is_instance_valid(body):
			_complete({"error": "trial body removed", "mode": _mode})
			return
		asleep = asleep and body.sleeping
	var top: RigidBody3D = blocks.back()
	if _tick >= _observation_tick:
		_drift = maxf(_drift, Vector2(top.global_position.x - _origin.x, top.global_position.z - _origin.z).length())
		if asleep and _sleep_tick < 0:
			_sleep_tick = _tick
	if _mode == "drop":
		if _contact_tick < 0 and not top.get_colliding_bodies().is_empty():
			_contact_tick = _tick
		if _contact_tick >= 0:
			_peak_y = maxf(_peak_y, top.global_position.y)
	if _tick < int(ceil(DURATION_S * Engine.physics_ticks_per_second)):
		return
	var seconds: float = 1.0 / float(Engine.physics_ticks_per_second)
	var measured: Dictionary = {
		"mode": _mode, "duration_s": DURATION_S, "cube_edge_m": _trial_tuning.cube_size - _trial_tuning.cube_margin,
		"all_asleep": asleep, "first_asleep_s": -1.0 if _sleep_tick < 0 else (_sleep_tick - _observation_tick) * seconds,
		"max_lateral_drift_cubes": _drift / (_trial_tuning.cube_size - _trial_tuning.cube_margin),
		"top_final_y_cubes": (top.global_position.y - _field.surface_y()) / (_trial_tuning.cube_size - _trial_tuning.cube_margin), "tuning": _snapshot,
	}
	if _mode == "drop":
		measured["drop_height_cubes"] = _height
		measured["first_contact_s"] = -1.0 if _contact_tick < 0 else _contact_tick * seconds
		measured["rebound_height_cubes"] = 0.0 if _contact_tick < 0 else maxf(0.0, (_peak_y - _origin.y) / (_trial_tuning.cube_size - _trial_tuning.cube_margin))
		measured["rebound_to_drop_ratio"] = 0.0 if _contact_tick < 0 else maxf(0.0, (_peak_y - _origin.y) / (_release_y - _origin.y))
	else:
		measured["stack_count"] = STACK_COUNT
		measured["placement_gap_cubes"] = _gap
		measured["stack_interval_s"] = _interval
	_complete(measured)

func _complete(measured: Dictionary) -> void:
	running = false
	result = measured
	finished.emit(result)

func elapsed_s() -> float:
	return float(_tick) / float(Engine.physics_ticks_per_second)
