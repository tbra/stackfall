extends GutTest
## BlockSpawner and HolePunch (Bontago-1pi.85.8) against a real started match.

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks = autofree(Node3D.new())
	add_child_autofree(_blocks)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _start(hole_mode: MatchConfig.HoleMode) -> void:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	config.hole_mode = hole_mode
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _origin() -> Vector3:
	return _field.world_from_disk_local(Match.slot(0).home_position, 5.0)


func _cube() -> BlockShape:
	return load("res://config/blocks/cube.tres") as BlockShape


func test_spawn_returns_block_without_bumping_blocks_placed() -> void:
	_start(MatchConfig.HoleMode.OFF)
	var before: int = Match._stats.blocks_placed(0)
	var block: Block = BlockSpawner.spawn(_cube(), _origin(), Basis.IDENTITY, 0, Vector3(0, 1, 0), 600)
	assert_not_null(block)
	assert_eq(block.owner_slot, 0)
	assert_eq(Match._stats.blocks_placed(0), before, "a projectile is not a placement")


func test_spawn_respects_cap() -> void:
	_start(MatchConfig.HoleMode.OFF)
	var cap: int = _blocks.get_child_count() + 1
	assert_not_null(BlockSpawner.spawn(_cube(), _origin(), Basis.IDENTITY, 0, Vector3.ZERO, cap))
	assert_null(BlockSpawner.spawn(_cube(), _origin(), Basis.IDENTITY, 0, Vector3.ZERO, cap), "cap reached")


func test_spawn_rejects_null_shape_and_non_finite() -> void:
	_start(MatchConfig.HoleMode.OFF)
	assert_null(BlockSpawner.spawn(null, _origin(), Basis.IDENTITY, 0, Vector3.ZERO, 600))
	assert_null(BlockSpawner.spawn(_cube(), Vector3(NAN, 0, 0), Basis.IDENTITY, 0, Vector3.ZERO, 600))


func test_punch_false_under_hole_mode_off() -> void:
	_start(MatchConfig.HoleMode.OFF)
	assert_false(HolePunch.punch(_field.world_from_disk_local(Match.slot(0).home_position, 0.0), 2.0, 2.0))


func test_punch_opens_hole_under_temporary() -> void:
	_start(MatchConfig.HoleMode.TEMPORARY)
	var home: Vector2 = Match.slot(0).home_position
	assert_true(HolePunch.punch(_field.world_from_disk_local(home, 0.0), 2.0, 2.0))
	var cell: Vector2i = Match.cell_grid().world_to_cell(home)
	assert_true(Match.raster().is_hole(cell.x, cell.y))


func test_punch_works_in_sudden_death() -> void:
	_start(MatchConfig.HoleMode.TEMPORARY)
	Match._lifecycle._state = Match.State.SUDDEN_DEATH
	var home: Vector2 = Match.slot(0).home_position
	assert_true(HolePunch.punch(_field.world_from_disk_local(home, 0.0), 2.0, 2.0))
	var cell: Vector2i = Match.cell_grid().world_to_cell(home)
	assert_true(Match.raster().is_hole(cell.x, cell.y), "Match.punch_special_hole accepts SUDDEN_DEATH")


func test_punch_false_after_match_end_and_bad_input() -> void:
	_start(MatchConfig.HoleMode.TEMPORARY)
	var world: Vector3 = _field.world_from_disk_local(Match.slot(0).home_position, 0.0)
	assert_false(HolePunch.punch(world, 0.0, 2.0))
	assert_false(HolePunch.punch(world, 2.0, 0.0))
	assert_false(HolePunch.punch(Vector3(INF, 0, 0), 2.0, 2.0))
	Match._finish_match(0)
	assert_false(HolePunch.punch(world, 2.0, 2.0))
