extends GutTest
## end-to-end centre-of-mass picks on a real Field.
## The V2 bot's real think (BotController._begin_thinking -> BotThink phases STACK/PROBE/RANK/MEASURE/PICK,
## zero aim noise, pick_pool 1) chooses among two hand-built sites on a scripted tower, once with the
## BotStack snapshot (BotStackProbe.build) and once with view.stack = null; the choice is then sent through
## the real _send_best_placement and the tower is simulated.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const CUBE8_SHAPE: BlockShape = preload("res://config/blocks/cube8.tres")
const PLATE9_SHAPE: BlockShape = preload("res://config/blocks/plate9.tres")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")

const BOT_SLOT: int = 1
const STACK_SETTLE_TICKS: int = 120
## Plan test 1: the column holds for 3 s of physics at 60 Hz.
const SETTLE_TICKS: int = 180
## Plan: "every column block moved less than 0.1 m".
const MAX_COLUMN_MOVE_M: float = 0.1
const COLUMN_CUBES: int = 4
## Plate lean (+x, m), the cube8 sites' x offsets from the tower centre and their z offset magnitude (m).
const LEAN_M: float = 0.3
const COUNTER_DX_M: float = -0.2
const OVERHANG_DX_M: float = 0.8
const SITE_DZ_M: float = 0.5

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
	config.sandbox = false
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	await wait_physics_frames(2)


## A bot on copies of the shared profile (zero aim noise, argmax pick).
func _make_bot() -> BotController:
	var bot: BotController = BotController.new()
	add_child_autofree(bot)
	bot.setup(BOT_SLOT, MatchConfig.AiDifficulty.HARD, _field, _registry)
	bot._profile = bot._profile.duplicate() as BotDifficultyProfile
	bot._profile.aim_noise_m = 0.0
	bot._profile.pick_pool = 1
	return bot


func _tower_centre() -> Vector2:
	var home: Vector2 = Match.slot(BOT_SLOT).home_position
	return home.move_toward(Vector2.ZERO, 3.0)


## Spawn-frame centre of mass of `shape` (identity orientation) relative to its pivot, disk xz metres.
func _com_offset(shape: BlockShape) -> Vector2:
	return BotStatics.orientation_info(shape, 0).com * PHYSICS_TUNING.cube_size


## Scripted tower block whose centre of mass sits over `com_xz`, resting `level` cubes above the disc.
func _add_block(shape: BlockShape, com_xz: Vector2, level: int) -> Block:
	var block: Block = BlockFactory.build(shape, PHYSICS_TUNING, BOT_SLOT)
	_blocks_root.add_child(block)
	var support_y: float = _field.surface_y() + float(level) * PHYSICS_TUNING.cube_size
	var pose: Vector3 = BotController.spawn_pose(shape, 0, com_xz - _com_offset(shape), support_y, PHYSICS_TUNING)
	block.global_position = _field.world_from_disk_local(Vector2(pose.x, pose.z), pose.y)
	Events.block_placed.emit(block, shape.id)
	_stack.append(block)
	return block


func _settle_stack() -> void:
	await wait_physics_frames(STACK_SETTLE_TICKS)
	_stack_start.clear()
	for block: Block in _stack:
		_stack_start.append(block.global_position)


func _site(view: BotWorldView, shape: BlockShape, com_xz: Vector2) -> BotCandidate:
	var info: BotStatics.OrientationInfo = BotStatics.orientation_info(shape, 0)
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = com_xz - info.com * PHYSICS_TUNING.cube_size
	candidate.orientation_index = 0
	candidate.site_kind = BotCandidateGen.SITE_STACK
	candidate.shape_height = info.height
	candidate.footprint_cells = BotStatics.footprint_cells_of(view.held, info, candidate.origin, view.cube_size, view.grid)
	return candidate


## Runs the bot's real think over exactly `com_targets` (in this order: ties go to the first): the generated
## sites are swapped for them once FILL is done, then STACK/PROBE/RANK/MEASURE/PICK run as in a match.
## `with_stack` false leaves view.stack null. Returns the bot; `bot._think.revalidate()` is the pick.
func _think_over(shape: BlockShape, com_targets: Array[Vector2], with_stack: bool, tower_centre: Vector2) -> BotController:
	var bot: BotController = _make_bot()
	bot._begin_thinking(Match)
	var view: BotWorldView = bot._special_view
	view.stack = null
	if with_stack:
		view.stack = BotStackProbe.build(
			_registry, _field, PackedVector2Array([tower_centre]), BotEvaluator.stack_tuning, view.cube_size,
			func(slot: int) -> int: return int(Match.team_of(slot))
		)
	var think: BotThink = bot._think
	# STACK now runs before PLAN, so the generated sites are swapped once FILL is over (PROBE next).
	while think._phase < BotThink.Phase.PROBE:
		think.step(0, bot._probe)
	think._candidates.clear()
	for target: Vector2 in com_targets:
		think._candidates.append(_site(view, shape, target))
	bot._probe_space = _field.direct_space()
	think.complete(bot._probe)
	bot._probe_space = null
	return bot


## The tower: four single cubes (levels 1-4) under a 3x3 plate (level 5) whose centre leans LEAN_M to +x, so the
## plate's own centre of mass sits 0.2 m inside the 1x1 column's edge. A cube8 on top is the 6th level.
## DECISION: plan test 1 asks for a 6-level column with an offset T4 at level 3. A T4 (8 mass) cannot push this
## column's load centre past its support, and a unit-cube column with a plate keeps the geometry exactly
## analysable, so the offset block is the plate at level 5; the contrast the plan asks for is the same
## (an off-centre top loads the column's centre of mass past its support, the centred one does not).
func _column(c: Vector2) -> void:
	for level: int in range(COLUMN_CUBES):
		_add_block(CUBE_SHAPE, c, level)
	_add_block(PLATE9_SHAPE, c + Vector2(LEAN_M, 0.0), COLUMN_CUBES)


## Held cube8 over the plate. COUNTER: its mass pulls the load back over the column (cube centres on plate
## cells). OVERHANG: its mass hangs on the leaning side (all four cube columns still on plate cells), which
## puts the load's centre of mass just past the column's edge. z = +-0.5 puts cube centres on the cell centres.
func _counter_site(c: Vector2) -> Vector2:
	return c + Vector2(COUNTER_DX_M, -SITE_DZ_M)


func _overhang_site(c: Vector2) -> Vector2:
	return c + Vector2(OVERHANG_DX_M, SITE_DZ_M)


## The tower, a settled scene and the real think over [overhang, counter] (the lean side listed first).
func _setup_and_think(with_stack: bool) -> BotController:
	await _start_match_holding(CUBE8_SHAPE)
	var c: Vector2 = _tower_centre()
	_column(c)
	await _settle_stack()
	var sites: Array[Vector2] = [_overhang_site(c), _counter_site(c)]
	return _think_over(CUBE8_SHAPE, sites, with_stack, c)


func _picked_origin(bot: BotController) -> Vector2:
	return bot._think.revalidate().origin


func _site_origin(site: Vector2) -> Vector2:
	return site - _com_offset(CUBE8_SHAPE)


## Sends the bot's pick through the real host path and simulates `ticks`; returns the spawned block.
func _send_pick(bot: BotController) -> Block:
	bot._candidates = bot._think.candidates()
	var before: int = _registry.all_blocks().size()
	var reason: StringName = bot._send_best_placement()
	assert_eq(reason, PlacementRules.REASON_OK, "the host accepts the bot's placement")
	var blocks: Array[Block] = _registry.all_blocks()
	assert_eq(blocks.size(), before + 1, "one block spawned")
	return blocks[blocks.size() - 1] if blocks.size() > before else null


func _max_column_move() -> float:
	var worst: float = 0.0
	for i: int in range(_stack.size()):
		worst = maxf(worst, _stack[i].global_position.distance_to(_stack_start[i]))
	return worst


## (1) End to end: on the tower's single top support the real think picks the site over the column's
## centre of mass, not the overhanging one, once BotStack is built; without it the overhang ranks on top.
func test_think_picks_the_centred_site_with_the_stack_and_the_overhang_without() -> void:
	var aware: BotController = await _setup_and_think(true)
	var c: Vector2 = _tower_centre()
	var candidates: Array[BotCandidate] = aware._think.candidates()
	assert_eq(candidates.size(), 2)
	var overhang: BotCandidate = candidates[0]
	var counter: BotCandidate = candidates[1]
	assert_gt(counter.stability_slack, 0.0, "the centred site keeps the combined centre of mass inside the column")
	assert_lte(overhang.stability_slack, 0.0, "the overhanging site pushes the load past the column")
	assert_lt(BotEvaluator.stability_risk(counter), BotEvaluator.stability_risk(overhang))
	assert_true(_picked_origin(aware).is_equal_approx(_site_origin(_counter_site(c))), "the stack-aware bot picks the centred site")
	for cand: BotCandidate in candidates:
		assert_eq(cand.support_bodies.size(), cand.probe_points.size())
	var blind: BotController = _think_over(CUBE8_SHAPE, [_overhang_site(c), _counter_site(c)] as Array[Vector2], false, c)
	for cand: BotCandidate in blind._think.candidates():
		assert_false(is_inf(cand.stability_slack), "no stack: the probe-only fallback still judges the piece")
		assert_gt(cand.stability_slack, 0.0, "the piece's own centre of mass is over its own contact patch")
		assert_eq(BotEvaluator.stability_risk(cand), 0.0)
	assert_true(_picked_origin(blind).is_equal_approx(_site_origin(_overhang_site(c))), "without the stack the overhang wins on reach and area")


## (2) Plan test 1 (physics): the stack-aware pick leaves the six-level column standing for 3 s.
func test_stack_aware_pick_keeps_the_column_standing_for_three_seconds() -> void:
	var aware: BotController = await _setup_and_think(true)
	var block: Block = _send_pick(aware)
	await wait_physics_frames(SETTLE_TICKS)
	assert_lt(_max_column_move(), MAX_COLUMN_MOVE_M, "no column block moved")
	if block != null:
		assert_gt(_field.to_local(block.global_position).y, _field.surface_y() + float(COLUMN_CUBES) * PHYSICS_TUNING.cube_size, "the piece rests on top")
