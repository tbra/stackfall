extends GutTest
## real Jolt evidence for the upright-or-flat decision. A bar stands centred on a sound top
## (a 1x1 cube column or a 2x2 block), settles, then the next piece lands on it with the bots' aim error.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const CUBE8_SHAPE: BlockShape = preload("res://config/blocks/cube8.tres")
const BAR3_SHAPE: BlockShape = preload("res://config/blocks/bar3.tres")
const BAR4_SHAPE: BlockShape = preload("res://config/blocks/bar4.tres")
const BAR5_SHAPE: BlockShape = preload("res://config/blocks/bar5.tres")
const PILLAR_SHAPE: BlockShape = preload("res://config/blocks/pillar.tres")
const PLATE9_SHAPE: BlockShape = preload("res://config/blocks/plate9.tres")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")

## One-body tops: a 1x1x3 pillar, a 2x2x2 block, a 3x3x1 plate.
const TOP_SHAPES: Dictionary = {"pillar": PILLAR_SHAPE, "2x2": CUBE8_SHAPE, "plate9": PLATE9_SHAPE}
## Frames the scripted stack and the upright bar get to come to rest.
const SETTLE_TICKS: int = 60
## Frames the next piece gets to land and the stack to react.
const LAND_TICKS: int = 90
## A bar still "stands" while its up axis is within this angle of the field's up axis (radians, ~9 degrees).
const STAND_MAX_TILT_RAD: float = 0.16
## ... and has not slid off its column by more than this (metres).
const STAND_MAX_DRIFT_M: float = 0.3
## Lift above the support when the next piece is dropped (metres).
## Seeds per case and the RNG seed of the aim offsets.
const SEEDS: int = 6
const AIM_SEED: int = 7
const DROP_LIFT_M: float = 0.02
## Frames the column or 2x2 block settles before the bar is placed.
const PRE_SETTLE_TICKS: int = 45

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _map: MapDef
var _spawned: Array[Block] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_spawned.clear()


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _upright_index(shape: BlockShape) -> int:
	var best: BotStatics.OrientationInfo = null
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape):
		if best == null or info.height > best.height or (info.height == best.height and info.self_margin > best.self_margin):
			best = info
	return best.index


func _flat_index(shape: BlockShape) -> int:
	var best: BotStatics.OrientationInfo = null
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape):
		if best == null or info.height < best.height or (info.height == best.height and info.self_margin > best.self_margin):
			best = info
	return best.index


func _spawn(shape: BlockShape, orientation: int, xz: Vector2, support_y: float) -> Block:
	var block: Block = BlockFactory.build(shape, PHYSICS_TUNING)
	_blocks_root.add_child(block)
	var pose: Vector3 = BotController.spawn_pose(shape, orientation, xz, support_y, PHYSICS_TUNING)
	block.global_basis = BlockOrientations.get_basis(orientation)
	block.global_position = _field.world_from_disk_local(Vector2(pose.x, pose.z), pose.y)
	_spawned.append(block)
	return block


## Pivot height above the support the spawn pose uses for `shape` upright-0 (pose.y with support 0).
func _spawn_lift(shape: BlockShape) -> float:
	return BotController.spawn_pose(shape, 0, Vector2.ZERO, 0.0, PHYSICS_TUNING).y


func _free_spawned() -> void:
	for block: Block in _spawned:
		if is_instance_valid(block):
			block.free()
	_spawned.clear()


## Angle between the bar's long (local x) axis and the field's up axis, folded to 0..pi/2.
func _tilt(block: Block) -> float:
	var angle: float = block.global_basis.x.normalized().angle_to(_field.global_basis.y.normalized())
	return minf(angle, PI - angle)


## One case: a `top` ("colN" loose cubes or a TOP_SHAPES body) under an upright `bar`, then `next` dropped
## with its pivot `aim` metres off the bar's axis. Returns the readings.
func _run_case(top: String, bar: BlockShape, next: BlockShape, aim: Vector2) -> Dictionary:
	var cube: float = PHYSICS_TUNING.cube_size
	var base: float = _field.surface_y()
	var xz: Vector2 = Vector2.ZERO
	var top_y: float = base
	if top.begins_with("col"):
		var count: int = int(top.substr(3))
		for level: int in range(count):
			_spawn(CUBE_SHAPE, 0, xz, base + float(level) * cube)
		await wait_physics_frames(PRE_SETTLE_TICKS)
		top_y = _field.to_local(_spawned[count - 1].global_position).y - _spawn_lift(CUBE_SHAPE) + cube
	else:
		var block_shape: BlockShape = TOP_SHAPES[top]
		var rows: float = float(BotStatics.orientation_info(block_shape, 0).height)
		var body: Block = _spawn(block_shape, 0, xz, base)
		await wait_physics_frames(PRE_SETTLE_TICKS)
		top_y = _field.to_local(body.global_position).y - _spawn_lift(block_shape) + rows * cube
	var stand: Block = _spawn(bar, _upright_index(bar), xz, top_y + DROP_LIFT_M)
	await wait_physics_frames(SETTLE_TICKS)
	var out: Dictionary = {}
	out["settle_tilt"] = _tilt(stand)
	var start: Vector3 = _field.to_local(stand.global_position)
	out["settle_drift"] = Vector2(start.x, start.z).distance_to(xz)
	var bar_top: float = _field.to_local(stand.global_position).y + float(bar.cells.size()) * cube
	var piece: Block = _spawn(next, _flat_index(next), xz + aim, bar_top + DROP_LIFT_M)
	await wait_physics_frames(LAND_TICKS)
	var end: Vector3 = _field.to_local(stand.global_position)
	out["land_tilt"] = _tilt(stand)
	out["land_drift"] = Vector2(end.x, end.z).distance_to(xz)
	out["standing"] = out["settle_tilt"] < STAND_MAX_TILT_RAD and out["settle_drift"] < STAND_MAX_DRIFT_M
	out["survived"] = out["land_tilt"] < STAND_MAX_TILT_RAD and out["land_drift"] < STAND_MAX_DRIFT_M
	out["piece_up"] = _field.to_local(piece.global_position).y > top_y
	_free_spawned()
	return out


func _aim(rng: RandomNumberGenerator, noise: float) -> Vector2:
	var angle: float = rng.randf() * TAU
	var radius: float = rng.randf() * noise
	return Vector2(cos(angle), sin(angle)) * radius


func _count(top: String, bar: BlockShape, next: BlockShape, noise: float) -> Vector2i:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = AIM_SEED
	var stood: int = 0
	var kept: int = 0
	for _i: int in range(SEEDS):
		var r: Dictionary = await _run_case(top, bar, next, _aim(rng, noise))
		stood += 1 if r["standing"] else 0
		kept += 1 if (r["survived"] and r["piece_up"]) else 0
	return Vector2i(stood, kept)


## Evidence (6 seeds, Hard 0.05 m and Normal 0.25 m aim error; full table in the bead):
## every upright bar stands on a sound wide top, whatever its height.
func test_upright_bars_stand_on_a_wide_sound_top_whatever_their_height() -> void:
	for top: String in ["2x2", "plate9"]:
		for bar: BlockShape in [BAR3_SHAPE, BAR4_SHAPE, BAR5_SHAPE]:
			var result: Vector2i = await _count(top, bar, CUBE_SHAPE, 0.05)
			assert_eq(result.x, SEEDS, "%s on %s stands after settling" % [bar.id, top])
