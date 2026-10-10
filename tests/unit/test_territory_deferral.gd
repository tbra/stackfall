extends GutTest
## Bontago-1pi.11.8: while a block is unsettled MatchTerritory defers solves up
## to TerritoryTuning.solve_defer_max_s; the forced solve must then apply the
## whole skipped time to the win checker exactly once (no loss, no double count),
## matching a run with deferral disabled.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


class _TimeSpyChecker:
	extends WinChecker
	var total: float = 0.0
	var updates: int = 0

	func update(raster: TerritoryRaster, delta: float) -> void:
		total += delta
		updates += 1
		super.update(raster, delta)


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_match() -> void:
	Match.abort_match()
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = true
	config.hole_mode = MatchConfig.HoleMode.OFF
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._territory._solve_accum = 0.0


func _add_awake_block() -> void:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	var entry: BlockRegistry._Entry = BlockRegistry._Entry.new()
	entry.block = block
	entry.is_settled = false
	_registry._entries[block.get_instance_id()] = entry
	_registry.mark_territory_dirty()


## Feeds `total_s` of time in `tick_s` slices with one awake block and returns
## [time seen by the win checker, time still in the accumulator, spy].
func _run(cap: float, total_s: float, tick_s: float) -> Array:
	_start_match()
	Match._territory_tuning.solve_defer_max_s = cap
	var spy: _TimeSpyChecker = _TimeSpyChecker.new(Match._territory._goal_positions, 100.0)
	Match._territory._win_checker = spy
	_add_awake_block()
	var fed: float = 0.0
	while fed < total_s - 0.00001:
		Match._territory._tick_territory(tick_s)
		fed += tick_s
	return [spy.total, Match._territory._solve_accum, spy]


func test_forced_solve_applies_deferred_time_exactly_once() -> void:
	var saved: float = Match._territory_tuning.solve_defer_max_s
	var cap: float = saved
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	var tick_s: float = 0.01
	# Just under the cap: everything deferred, nothing applied yet.
	var under: Array = _run(cap, cap - tick_s * 1.5, tick_s)
	assert_almost_eq(under[0] as float, 0.0, 0.00001, "No time applied while deferring.")
	# Past the cap: the forced solve accounts for all fed time except the sub-step remainder.
	var total_s: float = cap + tick_s * 3.0
	var deferred: Array = _run(cap, total_s, tick_s)
	var immediate: Array = _run(0.0, total_s, tick_s)
	Match._territory_tuning.solve_defer_max_s = saved
	var fed: float = ceilf((total_s - 0.00001) / tick_s) * tick_s
	assert_gt(deferred[0] as float, 0.0, "The cap forced a solve.")
	assert_almost_eq((deferred[0] as float) + (deferred[1] as float), fed, 0.0001, "Applied + pending equals fed: no loss, no double count.")
	assert_almost_eq((immediate[0] as float) + (immediate[1] as float), fed, 0.0001)
	assert_almost_eq(deferred[0] as float, immediate[0] as float, step + 0.0001, "Same applied time as deferral off, within one solve step.")
	assert_lt(deferred[1] as float, step + 0.0001, "Only a sub-step remainder stays pending.")


## Bontago-1pi.11.14: real host Match. Clean ticks skip the solve and leave the
## raster bytes untouched (so replicate_territory() would send nothing), and the
## next real solve's changed cells, sent as a diff, bring a mirror level again.
func test_clean_skips_send_nothing_then_a_real_solve_reaches_the_mirror() -> void:
	_start_match()
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	Match._territory._tick_territory(step)
	Match._territory._tick_territory(step)
	var raster: TerritoryRaster = Match._territory.raster()
	var mirror: TerritoryRaster = TerritoryRaster.new(raster.grid(), Match._territory_tuning)
	mirror.apply_replicated_state(raster.owner_bytes(), raster.state_bytes())
	var sent_owners: PackedByteArray = raster.owner_bytes().duplicate()
	var sent_states: PackedByteArray = raster.state_bytes().duplicate()

	var skips: int = Match._territory.clean_skip_count()
	var solves: int = Match._territory.solve_step_count()
	for _i: int in range(6):
		Match._territory._tick_territory(step)
	assert_eq(Match._territory.solve_step_count(), solves, "fixture: the board is clean.")
	assert_gt(Match._territory.clean_skip_count(), skips)
	assert_eq(raster.owner_bytes(), sent_owners, "Clean ticks leave nothing to replicate.")
	assert_eq(raster.state_bytes(), sent_states)

	# A settled block next to a home adds influence: a real solve changes cells.
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, load("res://config/physics_tuning.tres") as PhysicsTuning, 0)
	_field.add_child(block)
	block.freeze = true
	var home: Vector2 = Match.slot(0).home_position
	# DECISION: 8 m (was 9) so the cube circle still overlaps the home circle at the 40-degree cone (6 + 1.5 + h*tan(40) > 8).
	var spot: Vector2 = home - home.normalized() * 8.0  # toward the centre, outside the home circle
	block.global_position = _field.to_global(Vector3(spot.x, 0.5, spot.y))
	Events.block_placed.emit(block, shape.id)
	_registry._entries[block.get_instance_id()].is_settled = true
	Match._territory._tick_territory(step)
	Match._territory._tick_territory(step)
	assert_gt(Match._territory.solve_step_count(), solves, "The dirty board solved.")

	var owners: PackedByteArray = raster.owner_bytes()
	var states: PackedByteArray = raster.state_bytes()
	var changed: PackedInt32Array = PackedInt32Array()
	var picked_owners: PackedByteArray = PackedByteArray()
	var picked_states: PackedByteArray = PackedByteArray()
	for index: int in range(owners.size()):
		if owners[index] != sent_owners[index] or states[index] != sent_states[index]:
			changed.append(index)
			picked_owners.append(owners[index])
			picked_states.append(states[index])
	assert_gt(changed.size(), 0, "The real solve changed the raster.")
	mirror.apply_replicated_diff(changed, picked_owners, picked_states)
	assert_eq(mirror.owner_bytes(), owners)
	assert_eq(mirror.state_bytes(), states)
