extends Node
## Bontago-1pi.11.47 investigation bench (NOT in the GUT gate): does Jolt space
## history change when an identical 30-cube tower falls asleep?
##   godot --headless --path . --fixed-fps 60 res://tests/bench/bench_sleep_history.tscn -- --cond=fresh --trials=6
## --cond: fresh (new World3D per trial) | pristine (default space, tower only,
## freed between trials = reset path) | spawnrm (default space, spawn/free N
## bodies first) | settled (spawn N, drop, settle, free) | wind (impulses on a
## pile, then free) | all (every condition above, in that order).
## Prints one SLEEPHIST line per trial: cond, seed, sleep-onset s (after last
## placement), top y, total awake body-ticks, tick active count at 1/2/4 s.

const TOWER_HEIGHT: int = 30
const TICKS_BETWEEN: int = 30
const SETTLE_TICKS: int = 900
const POLLUTE_BODIES: int = 200
const POLLUTE_SETTLE_TICKS: int = 240
const CUBE_SHAPE: String = "res://config/blocks/cube.tres"

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _cond: String = "all"
var _trials: int = 6
var _mixed_shapes: Array[BlockShape] = []
var _use_field: bool = false
var _pollute_bodies: int = POLLUTE_BODIES


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cond="):
			_cond = arg.substr(7)
		elif arg == "--field":
			_use_field = true
		elif arg.begins_with("--pollute="):
			_pollute_bodies = int(arg.substr(10))
		elif arg.begins_with("--trials="):
			_trials = int(arg.substr(9))
	_mixed_shapes = BlockShape.load_all_shapes()
	var conds: Array[String] = ["fresh", "pristine", "spawnrm", "settled", "wind", "leftover"]
	if _cond != "all":
		conds = [_cond]
	for c: String in conds:
		for seed_i: int in range(_trials):
			await _trial(c, seed_i)
	get_tree().quit()


func _trial(cond: String, seed_i: int) -> void:
	var holder: Node3D = null
	var vp: SubViewport = null
	if cond == "fresh":
		vp = SubViewport.new()
		vp.world_3d = World3D.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		holder = Node3D.new()
		vp.add_child(holder)
	else:
		holder = Node3D.new()
		add_child(holder)
	var junk: Node3D = Node3D.new()
	holder.add_child(junk)
	if cond == "spawnrm" or cond == "settled" or cond == "wind" or cond == "leftover":
		await _pollute(cond, seed_i, junk)
	if _use_field:
		var field: Field = Field.new()
		field.map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
		field.map_def.field_radius = 6.0
		holder.add_child(field)
	else:
		var floor_body: StaticBody3D = StaticBody3D.new()
		var floor_shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(40.0, 1.0, 40.0)
		floor_shape.shape = box
		floor_body.add_child(floor_shape)
		holder.add_child(floor_body)
		floor_body.position = Vector3(0.0, -0.5, 0.0)

	var cube: BlockShape = load(CUBE_SHAPE) as BlockShape
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var blocks: Array[Block] = []
	var next_pos: Vector3 = Vector3(0.0, edge * 0.5, 0.0)
	var build_awake: int = 0
	for i: int in range(TOWER_HEIGHT):
		var b: Block = BlockFactory.build(cube, _tuning)
		b.net_id = 100000 + i
		holder.add_child(b)
		b.global_position = next_pos
		blocks.append(b)
		for _t: int in range(TICKS_BETWEEN):
			await get_tree().physics_frame
			for ab: Block in blocks:
				if not ab.sleeping:
					build_awake += 1
		next_pos = b.global_position + Vector3(0.0, edge, 0.0)
	var onset: int = -1
	var awake_sum: int = 0
	var at: Array[int] = [-1, -1, -1]
	for tick: int in range(SETTLE_TICKS):
		await get_tree().physics_frame
		var awake: int = 0
		for b: Block in blocks:
			if not b.sleeping:
				awake += 1
		awake_sum += awake
		if tick == 59:
			at[0] = awake
		elif tick == 119:
			at[1] = awake
		elif tick == 239:
			at[2] = awake
		if onset < 0 and awake == 0:
			onset = tick
	var onset_s: String = "never"
	if onset >= 0:
		onset_s = "%.2f" % (float(onset) / 60.0)
	print("SLEEPHIST cond=%s seed=%d onset_s=%s top_y=%.4f build_awake=%d awake_body_ticks=%d awake@1s=%d @2s=%d @4s=%d" % [
		cond, seed_i, onset_s, blocks[TOWER_HEIGHT - 1].global_position.y, build_awake, awake_sum, at[0], at[1], at[2]])
	# Tear down: free everything synchronously-ish, like a match reset in place.
	holder.queue_free()
	if vp != null:
		vp.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _pollute(cond: String, seed_i: int, junk: Node3D) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1000 + seed_i
	var floor_body: StaticBody3D = StaticBody3D.new()
	var fs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	fs.shape = box
	floor_body.add_child(fs)
	junk.add_child(floor_body)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var bodies: Array[Block] = []
	for i: int in range(_pollute_bodies):
		var shape: BlockShape = _mixed_shapes[rng.randi_range(0, _mixed_shapes.size() - 1)]
		var b: Block = BlockFactory.build(shape, _tuning)
		b.net_id = 500 + i
		junk.add_child(b)
		b.global_position = Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(1.0, 25.0), rng.randf_range(-12.0, 12.0))
		bodies.append(b)
	if cond == "spawnrm":
		await get_tree().physics_frame
	else:
		for t: int in range(POLLUTE_SETTLE_TICKS):
			await get_tree().physics_frame
			if cond == "wind" and t % 20 == 0:
				for b: Block in bodies:
					b.apply_central_impulse(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 0.5), rng.randf_range(-1.0, 1.0)) * b.mass)
	if cond == "leftover":
		# History: 200 sleeping bodies stay in the space (never removed).
		for b: Block in bodies:
			b.global_position += Vector3(30.0, 0.0, 0.0)
		await get_tree().physics_frame
		return
	for b: Block in bodies:
		b.free()
	floor_body.free()
	await get_tree().physics_frame
