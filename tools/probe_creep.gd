extends Node3D
## Bontago-1pi.11.17 diagnosis probe: a TOWER_HEIGHT tower on a statically leaned Field.
##   godot --headless --path . res://tools/probe_creep.tscn -- --tilt=0.55 --x=1 [--bf= --df= --bounce= --rebound= --ldamp= --adamp= --gscale=]
## Jolt project settings are varied by tools/probe_creep_sweep.sh via override.cfg.
## Prints one PROBE_CREEP line: creep speeds (mm/s) and sleep state. Bench-only; changes no defaults.

const TOWER_HEIGHT: int = 15
var _run_s: float = 40.0
const SAMPLE_A_S: float = 5.0
const MM: float = 1000.0

var _tuning: PhysicsTuning
var _field: Field
var _blocks: Array[RigidBody3D] = []
var _tick: int = 0
var _tilt_deg: float = 0.55
var _x: float = 1.0
var _disk_friction: float = -1.0
var _label: String = ""
var _ramp_s: float = 0.0
var _trace: bool = false
var _balance: bool = false
var _unsync_s: float = -1.0
var _sync_ramp: bool = false
var _registry: BlockRegistry
var _last_xform: Transform3D
var _last_move_s: float = 0.0
var _first_asleep_s: float = -1.0
var _pos_a: Vector3 = Vector3.ZERO
var _speed_sum: float = 0.0
var _speed_n: int = 0
var _speed_win_start: float = 30.0


func _ready() -> void:
	_tuning = (load("res://config/physics_tuning.tres") as PhysicsTuning).duplicate() as PhysicsTuning
	for arg: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		var v: float = kv[1].to_float()
		match kv[0]:
			"tilt": _tilt_deg = v
			"x": _x = v
			"bf": _tuning.block_friction = v
			"df": _disk_friction = v
			"bounce": _tuning.block_bounce = v
			"rebound": _tuning.rebound_damping = v
			"ldamp": _tuning.block_linear_damp = v
			"adamp": _tuning.block_angular_damp = v
			"gscale": _tuning.gravity_multiplier = v
			"run": _run_s = v; _speed_win_start = v - 10.0
			"balance": _balance = v > 0.0
			"unsync": _unsync_s = v
			"sync": _sync_ramp = v > 0.0
			"ramp": _ramp_s = v
			"trace": _trace = v > 0.0
			"label": _label = kv[1]
	_field = Field.new()
	add_child(_field)
	if _disk_friction >= 0.0:
		(_field.physics_material_override as PhysicsMaterial).friction = _disk_friction
	if _balance:
		_registry = BlockRegistry.new()
		add_child(_registry)
		_registry.configure(_field, _field.map_def)
		_field.set_registry(_registry)
		_field.set_physical_balance_enabled(true)
		_field.set_tilt_enabled(true)
	else:
		_field.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(_tilt_deg)), _field.transform.origin)
	if _sync_ramp:
		_field.sync_to_physics = true
	if _ramp_s > 0.0:
		_field.transform = Transform3D(Basis.IDENTITY, _field.transform.origin)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var start_y: float = _field.surface_y() - _tuning.cube_margin * 0.5
	for i: int in range(TOWER_HEIGHT):
		var block: Block = BlockFactory.build(cube_shape, _tuning, 0)
		_field.add_child(block)
		# Field-local placement so the tower starts square to the leaned surface.
		block.position = Vector3(_x, start_y + edge * float(i), 0.0) - _field.position
		_blocks.append(block)
		if _balance:
			Events.block_placed.emit(block, cube_shape.id)


func _physics_process(_delta: float) -> void:
	_tick += 1
	var t: float = float(_tick) / float(Engine.physics_ticks_per_second)
	var top: RigidBody3D = _blocks[TOWER_HEIGHT - 1]
	if _ramp_s > 0.0 and t <= _ramp_s + 1.0 / 60.0:
		var deg: float = _tilt_deg * minf(t / _ramp_s, 1.0)
		_field.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(deg)), _field.transform.origin)
	if _trace and _tick % 600 == 0:
		var fastest: float = 0.0
		for b2: RigidBody3D in _blocks:
			fastest = maxf(fastest, b2.linear_velocity.length())
		print("TRACE t=%.0f fastest_mm_s=%.2f top_local=%s" % [t, fastest * MM, str(_field.to_local(top.global_position))])
	var awake: int = 0
	for b: RigidBody3D in _blocks:
		if not b.sleeping:
			awake += 1
	if _unsync_s >= 0.0 and t >= _unsync_s and _field.sync_to_physics:
		_field.sync_to_physics = false
	if _field.transform != _last_xform:
		_last_xform = _field.transform
		_last_move_s = t
	if awake == 0 and _first_asleep_s < 0.0:
		_first_asleep_s = t
	if absf(t - SAMPLE_A_S) < 0.5 / 60.0:
		_pos_a = _field.to_local(top.global_position)
	if t >= _speed_win_start:
		var fastest_now: float = 0.0
		for b3: RigidBody3D in _blocks:
			fastest_now = maxf(fastest_now, b3.linear_velocity.length())
		_speed_sum += fastest_now
		_speed_n += 1
	if t >= _run_s:
		var pos_b: Vector3 = _field.to_local(top.global_position)
		var drift_mm_s: float = (pos_b - _pos_a).length() * MM / (_run_s - SAMPLE_A_S)
		var bottom_v: float = _blocks[0].linear_velocity.length() * MM
		print("PROBE_CREEP %s tilt=%.2f x=%.1f top_drift_mm_s(5-end)=%.2f fastest_block_mm_s(avg last10s)=%.2f bottom_v_mm_s=%.2f awake=%d first_all_asleep_s=%.2f last_disc_write_s=%.1f tilt_deg=%.4f" % [
			_label, _tilt_deg, _x, drift_mm_s, _speed_sum / float(maxi(_speed_n, 1)) * MM, bottom_v, awake, _first_asleep_s, _last_move_s, rad_to_deg(_field.tilt_vector().length())])
		get_tree().quit()
