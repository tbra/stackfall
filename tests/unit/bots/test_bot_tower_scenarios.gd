extends GutTest
## Field physics scenarios for the bot tower work.
## A scripted stack of real blocks settles on a real Field; a bot (zero aim noise) then places a held piece
## through the real send path (BotController._send_best_placement, as test_bot_disc_placement does). Each
## scenario asserts (a) the spawned cubes sit where the bot's spawn-frame model (BotStatics.OrientationInfo
## cubes at the pivot) said, (b) the piece rests on the support the cube probes found, (c) it settles within
## SETTLE_MAX_TICKS and (d) neither it nor the stack beneath it is knocked over or moved.

const BAR3_SHAPE: BlockShape = preload("res://config/blocks/bar3.tres")
const PLATE9_SHAPE: BlockShape = preload("res://config/blocks/plate9.tres")
const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const CUBE8_SHAPE: BlockShape = preload("res://config/blocks/cube8.tres")
const SLAB6_SHAPE: BlockShape = preload("res://config/blocks/slab6.tres")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")

const BOT_SLOT: int = 1
## Frames the scripted stack gets to come to rest before the bot acts.
const STACK_SETTLE_TICKS: int = 90
## Frames after the bot's placement within which the new block must come to rest (plan: <= ~300).
const SETTLE_MAX_TICKS: int = 180
## DECISION: consecutive quiet ticks that count as "settled" (Jolt sleep may lag the velocity gate).
const QUIET_TICKS: int = 5
## Spawn-frame model vs the real collision boxes, metres (pure geometry, identity rotation).
const MODEL_TOLERANCE_M: float = 0.02
## The new block rests on the probed support: its lowest point vs the support top, metres.
const REST_TOLERANCE_M: float = 0.1
## Settled block may drift this far (xz, metres) from where it spawned.
const MAX_DRIFT_M: float = 0.25
## Settled block may rotate this far (radians, about 6 degrees) from its spawn orientation.
const MAX_TILT_RAD: float = 0.1
## Stack blocks beneath may not move more than this (test_drop_displacement's creep bound).
const MAX_STACK_DRIFT_M: float = 0.05

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _saved_feed_config: BlockFeedConfig = null
var _stack: Array[Block] = []
var _stack_start: Array[Vector3] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_saved_feed_config = Match._block_feed_config
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_stack.clear()
	_stack_start.clear()


func after_each() -> void:
	Match._block_feed_config = _saved_feed_config
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## Starts a match whose bot slot holds `held` (the feed is pinned on a COPY of the shared config).
func _start_match_holding(held: BlockShape) -> void:
	var pinned: BlockFeedConfig = _saved_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [held]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.game_mode = MatchConfig.GameMode.REACH_THE_SKY
	config.ai_count = 1
	config.player_count = 2
	config.hot_seat = false
	config.sandbox = false
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	await wait_physics_frames(2)


func _make_bot() -> BotController:
	var bot: BotController = BotController.new()
	add_child_autofree(bot)
	bot.setup(BOT_SLOT, MatchConfig.AiDifficulty.HARD, _field, _registry)
	# The profile is the shared, cached tuning resource: mutate a copy only (gate leak).
	bot._profile = bot._profile.duplicate() as BotDifficultyProfile
	bot._profile.aim_noise_m = 0.0
	return bot


## Disk-local centre of the scripted stack: near the bot's home, inside its territory.
func _stack_centre() -> Vector2:
	var home: Vector2 = Match.slot(BOT_SLOT).home_position
	return home.move_toward(Vector2.ZERO, 3.0)


## Scripted stack block: `shape` with its pivot at `xz`, resting on the disc (the bot's own spawn pose).
func _add_stack_block(shape: BlockShape, xz: Vector2) -> Block:
	var block: Block = BlockFactory.build(shape, PHYSICS_TUNING)
	_blocks_root.add_child(block)
	var pose: Vector3 = BotController.spawn_pose(shape, 0, xz, _field.surface_y(), PHYSICS_TUNING)
	block.global_position = _field.world_from_disk_local(Vector2(pose.x, pose.z), pose.y)
	_stack.append(block)
	return block


func _settle_stack() -> void:
	await wait_physics_frames(STACK_SETTLE_TICKS)
	_stack_start.clear()
	for block: Block in _stack:
		_stack_start.append(block.global_position)


## Drives the real send path with ONE hand-built candidate (origin = pivot). Returns the spawned block.
func _place_via_bot(origin: Vector2, orientation_index: int) -> Block:
	var bot: BotController = _make_bot()
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	candidate.orientation_index = orientation_index
	candidate.support_height = float(bot._raycast_support_height(origin).get("height", 0.0))
	bot._candidates = [candidate] as Array[BotCandidate]
	var before: int = _registry.all_blocks().size()
	var reason: StringName = bot._send_best_placement(origin)
	assert_eq(reason, PlacementRules.REASON_OK, "the host accepts the bot's placement")
	var blocks: Array[Block] = _registry.all_blocks()
	assert_eq(blocks.size(), before + 1, "one block spawned")
	return blocks[blocks.size() - 1] if blocks.size() > before else null


func _cube_centres_local(block: Block) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var local: Vector3 = _field.to_local(block.global_transform * collision.position)
		points.append(Vector2(local.x, local.z))
	return points


func _lowest_point_local_y(block: Block) -> float:
	var low: float = INF
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var half: Vector3 = (collision.shape as BoxShape3D).size * 0.5
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]:
					low = minf(low, _field.to_local(block.global_transform * (collision.transform * Vector3(x, y, z))).y)
	return low


## The spawn-frame model's cube centres (disk xz) for `shape` in `orientation_index` with its pivot at `origin`.
func _modelled_cubes(shape: BlockShape, orientation_index: int, origin: Vector2) -> PackedVector2Array:
	var info: BotStatics.OrientationInfo = BotStatics.orientation_info(shape, orientation_index)
	var points: PackedVector2Array = PackedVector2Array()
	for offset: Vector2 in info.cubes:
		points.append(origin + offset * PHYSICS_TUNING.cube_size)
	return points


func _assert_cubes_match_model(block: Block, modelled: PackedVector2Array) -> void:
	var actual: PackedVector2Array = _cube_centres_local(block)
	assert_eq(actual.size(), modelled.size(), "same cube count as the model")
	for expected: Vector2 in modelled:
		var nearest: float = INF
		for point: Vector2 in actual:
			nearest = minf(nearest, point.distance_to(expected))
		assert_lt(nearest, MODEL_TOLERANCE_M, "a spawned cube sits at the modelled %s" % expected)


func _is_quiet(block: Block) -> bool:
	return block.sleeping or (
		block.linear_velocity.length() < PHYSICS_TUNING.sleep_linear_threshold
		and block.angular_velocity.length() < PHYSICS_TUNING.sleep_angular_threshold
	)


## Returns the tick count it took to settle (SETTLE_MAX_TICKS + 1 when it never did).
func _run_until_settled(block: Block) -> int:
	var quiet: int = 0
	for tick: int in range(SETTLE_MAX_TICKS):
		await wait_physics_frames(1)
		quiet = quiet + 1 if _is_quiet(block) else 0
		if quiet >= QUIET_TICKS:
			return tick + 1
	return SETTLE_MAX_TICKS + 1


## The shared acceptance of every scenario once the bot has placed `block`.
func _assert_lands_and_stays(
	block: Block, shape: BlockShape, orientation_index: int, origin: Vector2, support_top_y: float
) -> void:
	assert_not_null(block)
	if block == null:
		return
	_assert_cubes_match_model(block, _modelled_cubes(shape, orientation_index, origin))
	assert_almost_eq(_lowest_point_local_y(block), support_top_y, REST_TOLERANCE_M, "spawned resting on the probed support")
	var spawn_local: Vector3 = _field.to_local(block.global_position)
	var spawn_basis: Basis = block.global_basis
	var ticks: int = await _run_until_settled(block)
	assert_lte(ticks, SETTLE_MAX_TICKS, "the block settles within %d ticks" % SETTLE_MAX_TICKS)
	var rest: Vector3 = _field.to_local(block.global_position)
	assert_lt(Vector2(rest.x, rest.z).distance_to(Vector2(spawn_local.x, spawn_local.z)), MAX_DRIFT_M, "the block did not slide off")
	assert_gt(_lowest_point_local_y(block), support_top_y - REST_TOLERANCE_M, "the block did not sink or fall")
	var turned: float = (block.global_basis * spawn_basis.inverse()).get_rotation_quaternion().get_angle()
	assert_lt(turned, MAX_TILT_RAD, "the block did not topple")
	for i: int in range(_stack.size()):
		assert_lt(_stack[i].global_position.distance_to(_stack_start[i]), MAX_STACK_DRIFT_M, "stack block %d was not disturbed" % i)


## (4) A plate straddling a tall block (two columns of it) and a short one (one column, a cube lower).
func test_plate_straddling_blocks_of_different_heights_rests_on_the_tall_one() -> void:
	await _start_match_holding(PLATE9_SHAPE)
	var centre: Vector2 = _stack_centre()
	_add_stack_block(CUBE8_SHAPE, centre + Vector2(-1.0, 0.0))
	_add_stack_block(SLAB6_SHAPE, centre + Vector2(1.0, 0.0))
	await _settle_stack()
	var tall_top_y: float = _field.surface_y() + 2.0 * PHYSICS_TUNING.cube_size
	var origin: Vector2 = centre + Vector2(-0.5, 0.0)
	var block: Block = _place_via_bot(origin, 0)
	await _assert_lands_and_stays(block, PLATE9_SHAPE, 0, origin, tall_top_y)


## a pile of really tilted blocks beside a real column. The snapshot of real bodies must read
## the pile as unsound (debris) and the column's top as the only sound top, and a new base search over it
## must keep clear of the pile.
const PILE_TILT_RAD: float = 0.6
const PILE_BLOCKS: int = 3
const COLUMN_BLOCKS: int = 2
const PILE_GAP_M: float = 4.0
## Cube pivots sit at the bottom face: lift the scripted column a hair off the disc.
const COLUMN_LIFT_M: float = 0.02


func test_real_snapshot_reads_a_tilted_pile_as_debris_and_the_column_as_the_sound_top() -> void:
	await _start_match_holding(CUBE_SHAPE)
	var centre: Vector2 = _stack_centre()
	var column_xz: Vector2 = centre + Vector2(0.0, -PILE_GAP_M)
	for level: int in range(COLUMN_BLOCKS):
		var block: Block = BlockFactory.build(CUBE_SHAPE, PHYSICS_TUNING, BOT_SLOT)
		_blocks_root.add_child(block)
		block.global_position = _field.world_from_disk_local(
			column_xz, _field.surface_y() + float(level) * PHYSICS_TUNING.cube_size + COLUMN_LIFT_M
		)
		block.freeze = true
		Events.block_placed.emit(block, CUBE_SHAPE.id)
		_stack.append(block)
	for i: int in range(PILE_BLOCKS):
		var leaning: Block = BlockFactory.build(BAR3_SHAPE, PHYSICS_TUNING, BOT_SLOT)
		_blocks_root.add_child(leaning)
		leaning.global_position = _field.world_from_disk_local(
			centre + Vector2(float(i) * 1.5, 0.0), _field.surface_y() + 1.5 * PHYSICS_TUNING.cube_size
		)
		leaning.rotate_z(PILE_TILT_RAD)
		leaning.freeze = true
		Events.block_placed.emit(leaning, BAR3_SHAPE.id)
		_stack.append(leaning)
	await wait_physics_frames(2)
	var team: int = int(Match.team_of(BOT_SLOT))
	var stack: BotStack = BotStackProbe.build(
		_registry, _field, PackedVector2Array([centre, column_xz]), BotEvaluator.stack_tuning,
		PHYSICS_TUNING.cube_size, func(_slot: int) -> int: return team
	)
	assert_not_null(stack)
	if stack == null:
		return
	while not stack.analyse_step(stack.body_count(), BotEvaluator.stack_tuning):
		pass
	assert_eq(stack.body_count(), COLUMN_BLOCKS + PILE_BLOCKS)
	var tops: PackedInt32Array = stack.sound_tops(team)
	assert_eq(tops.size(), 1, "one sound top: the column's")
	if tops.size() == 1:
		assert_lt(stack.com_xz(tops[0]).distance_to(column_xz), 0.1)
