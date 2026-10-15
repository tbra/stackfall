extends GutTest
## Bontago-1t5.51 (owner playtest: "when bots place blocks directly on the disc they fall straight
## through"). Drives BotController._send_best_placement() against the real Match/Field/physics and
## asserts the spawned block comes to rest on the disc top, for both a bare-disc column and a
## candidate whose support probe falls back (no hit).

const PILLAR_SHAPE: BlockShape = preload("res://config/blocks/pillar.tres")
const SETTLE_TICKS: int = 90
const REST_TOLERANCE_M: float = 0.3
const BOT_SLOT: int = 1

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _saved_feed_config: BlockFeedConfig = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_saved_feed_config = Match._block_feed_config
	var pinned: BlockFeedConfig = _saved_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [PILLAR_SHAPE]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
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


func after_each() -> void:
	Match._block_feed_config = _saved_feed_config
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_reach_the_sky() -> void:
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
	bot.set_brain(BotController.Brain.LEGACY)
	return bot


## Disk-local point near slot BOT_SLOT's home, clear of every other body.
func _bot_target() -> Vector2:
	var home: Vector2 = Match.slot(BOT_SLOT).home_position
	return home.move_toward(Vector2.ZERO, 3.0)


func _place_via_bot(origin: Vector2, orientation_index: int = 0) -> Block:
	var bot: BotController = _make_bot()
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	candidate.orientation_index = orientation_index
	var hit: Dictionary = bot._raycast_support_height(origin)
	candidate.support_height = float(hit.get("height", 0.0))
	bot._candidates = [candidate] as Array[BotCandidate]
	# The profile is the shared, cached shipped tuning resource: mutate a copy, never the
	# original, or the zeroed aim noise leaks into later scripts (test_bot_tuning, gate 2026-10-14).
	bot._profile = bot._profile.duplicate() as BotDifficultyProfile
	bot._profile.aim_noise_m = 0.0
	var before: int = _registry.all_blocks().size()
	var reason: StringName = bot._send_best_placement()
	assert_eq(reason, PlacementRules.REASON_OK, "the host accepts the bot's placement")
	var blocks: Array[Block] = _registry.all_blocks()
	assert_eq(blocks.size(), before + 1, "one block spawned")
	return blocks[blocks.size() - 1] if blocks.size() > before else null


## The orientation the bot actually prefers: BotPlacementScorer's flattest one (a lying pillar),
## whose lowest point is far below the pillar's upright bottom-centre pivot.
func _flat_orientation() -> int:
	var flat: Array[int] = BotPlacementScorer.flattest_orientations(PILLAR_SHAPE, 1)
	return flat[0]


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


func test_bot_upright_block_on_bare_disc_rests_on_the_disc_top() -> void:
	await _start_reach_the_sky()
	var block: Block = _place_via_bot(_bot_target(), 0)
	assert_not_null(block)
	if block == null:
		return
	await wait_physics_frames(SETTLE_TICKS)
	assert_gt(_lowest_point_local_y(block), _field.surface_y() - REST_TOLERANCE_M, "upright block did not sink")


func test_bot_flat_block_spawns_above_the_disc_not_inside_it() -> void:
	await _start_reach_the_sky()
	var block: Block = _place_via_bot(_bot_target(), _flat_orientation())
	assert_not_null(block)
	if block == null:
		return
	# Right after spawn (before any physics tick) no part of the block may be below the disc top.
	assert_gt(_lowest_point_local_y(block), _field.surface_y() - REST_TOLERANCE_M, "flat block spawned inside the disc")
	await wait_physics_frames(SETTLE_TICKS)
	assert_gt(_lowest_point_local_y(block), _field.surface_y() - REST_TOLERANCE_M, "flat block fell through the disc")
	assert_lt(_field.to_local(block.global_position).y, _field.surface_y() + 1.0, "and rests on the disc top")


## Human behaviour unchanged: literal offsets for the 3-cell pillar (margin 0.02 -> half box 0.49),
## hand-derived from the pre-refactor GhostPreview formula (lowest rotated collision corner relative to
## the unrotated bottom-centre pivot): upright +0.01, lying flat (either axis) -0.49, upside down -2.99.
func _orientation_where(predicate: Callable) -> int:
	for index: int in range(BlockOrientations.ORIENTATION_COUNT):
		if bool(predicate.call(BlockOrientations.get_basis(index))):
			return index
	return -1


func test_rotated_bottom_offset_matches_the_pre_refactor_ghost_values() -> void:
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var ghost: GhostPreview = GhostPreview.new()
	add_child_autofree(ghost)
	ghost.set_shape(PILLAR_SHAPE)
	var cases: Dictionary = {
		0: 0.01,
		_orientation_where(func(b: Basis) -> bool: return absf(b.x.y) > 0.99): -0.49,
		_orientation_where(func(b: Basis) -> bool: return absf(b.z.y) > 0.99): -0.49,
		_orientation_where(func(b: Basis) -> bool: return b.y.y < -0.99): -2.99,
	}
	for index: int in cases:
		assert_gte(index, 0, "a matching orientation exists")
		var expected: float = float(cases[index])
		var basis: Basis = BlockOrientations.get_basis(index)
		assert_almost_eq(PILLAR_SHAPE.rotated_bottom_offset(basis, physics.cube_size, physics.cube_margin), expected, 0.0001, "helper, orientation %d" % index)
		ghost.set_orientation_index(index)
		assert_almost_eq(ghost._rotated_bottom_offset(), expected, 0.0001, "ghost, orientation %d" % index)
