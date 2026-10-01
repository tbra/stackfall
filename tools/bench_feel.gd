extends Node3D
## Bontago-1pi.11.19 feel proxies vs Jolt velocity_steps (run with an override.cfg value).
##   godot --headless --path . res://tools/bench_feel.tscn
## Prints BENCH_FEEL drop_rebound_m (cube dropped DROP_HEIGHT onto the disk: peak rise after
## first impact) and slide_m (cube released on a TILT_DEG slab: travel after SLIDE_SECONDS).
## Diagnostic only.

const DROP_HEIGHT: float = 3.0
const DROP_SECONDS: float = 4.0
const TILT_DEG: float = 40.0
const SLIDE_SECONDS: float = 3.0
const SLAB_SIZE: Vector3 = Vector3(40.0, 0.5, 10.0)
const SLAB_ORIGIN: Vector3 = Vector3(0.0, 60.0, 0.0)

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _drop: RigidBody3D = null
var _slide: RigidBody3D = null
var _tick: int = 0
var _impact_tick: int = -1
var _min_y: float = 1.0e9
var _rebound: float = 0.0
var _slide_start: Vector3 = Vector3.ZERO


func _ready() -> void:
	var field: Field = Field.new()
	add_child(field)
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	_drop = BlockFactory.build(cube, _tuning)
	add_child(_drop)
	_drop.global_position = Vector3(0.0, field.surface_y() + DROP_HEIGHT, 0.0)
	var slab: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = SLAB_SIZE
	col.shape = box
	slab.add_child(col)
	add_child(slab)
	slab.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(TILT_DEG)), SLAB_ORIGIN)
	_slide = BlockFactory.build(cube, _tuning)
	add_child(_slide)
	var up: Vector3 = slab.global_transform.basis.y
	_slide.global_transform = Transform3D(slab.global_transform.basis, SLAB_ORIGIN + up * (SLAB_SIZE.y * 0.5 + 0.05))
	_slide_start = _slide.global_position


func _physics_process(_delta: float) -> void:
	_tick += 1
	var hz: float = float(Engine.physics_ticks_per_second)
	var t: float = float(_tick) / hz
	if t < DROP_SECONDS and is_instance_valid(_drop):
		var y: float = _drop.global_position.y
		if _impact_tick < 0 and _drop.linear_velocity.y > 0.5:
			_impact_tick = _tick
			_min_y = y
		if _impact_tick >= 0:
			_min_y = minf(_min_y, y)
			_rebound = maxf(_rebound, y - _min_y)
	if t >= SLIDE_SECONDS and t >= DROP_SECONDS:
		print("BENCH_FEEL velocity_steps=%s drop_rebound_m=%.4f slide_m=%.3f" % [
			ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/velocity_steps"),
			_rebound, _slide.global_position.distance_to(_slide_start)])
		get_tree().quit()
