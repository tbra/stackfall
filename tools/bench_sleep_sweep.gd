extends Node3D
## Bontago-1pi.11.13: time for a dropped block / a stack of N cubes to sleep.
##   godot --headless --path . res://tools/bench_sleep_sweep.tscn -- --height=10 --drop=1.0
## Prints the tick time (s) every block is asleep, plus the sleep_velocity_threshold in force.

const MAX_SECONDS: float = 30.0

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[RigidBody3D] = []
var _tick: int = 0
var _height: int = 1
var _drop: float = 0.0
## --coast=v: one gravity-free block drifting at v m/s; proves the threshold reaches Jolt.
var _coast: float = -1.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--height="):
			_height = arg.trim_prefix("--height=").to_int()
		elif arg.begins_with("--coast="):
			_coast = arg.trim_prefix("--coast=").to_float()
		elif arg.begins_with("--drop="):
			_drop = arg.trim_prefix("--drop=").to_float()
	var field: Field = Field.new()
	add_child(field)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var start_y: float = field.surface_y() - _tuning.cube_margin * 0.5 + _drop
	for i: int in range(_height):
		var block: RigidBody3D = BlockFactory.build(cube_shape, _tuning)
		add_child(block)
		block.global_position = Vector3(0.5, start_y + edge * float(i), 0.0)
		_blocks.append(block)
		if _coast >= 0.0:
			block.gravity_scale = 0.0
			block.linear_damp = 0.0
			block.global_position.y += 5.0
			block.linear_velocity = Vector3(_coast, 0.0, 0.0)


func _physics_process(_delta: float) -> void:
	_tick += 1
	var awake: int = 0
	for block: RigidBody3D in _blocks:
		if not block.sleeping:
			awake += 1
	var t: float = float(_tick) / float(Engine.physics_ticks_per_second)
	if awake == 0 or t >= MAX_SECONDS:
		print("SLEEP_SWEEP height=%d drop=%.2f thr=%s asleep=%s at_s=%.2f awake=%d" % [
			_height, _drop, str(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/sleep_velocity_threshold", 0.03)),
			awake == 0, t, awake])
		get_tree().quit()
