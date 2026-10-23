extends GutTest
## wind and Breeze gusts must reach a SETTLED tall tower. In real
## play a tower sleeps and, 20 s later, StableBlockManager freezes it STATIC; the
## wind effects used to skip frozen blocks, so nothing ever moved a settled
## stack. This builds a ~30 m 2x2 tower through the registry placement path,
## lets it fall asleep, freezes it with the real manager and then blows on it.

const DELTA: float = 1.0 / 60.0
const TOWER_LAYERS: int = 30
const TOWER_FOOTPRINT: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]
const TOWER_GAP_M: float = 0.03
const SETTLE_TICKS: int = 240
const FREEZE_ADVANCE_S: float = 25.0
const GUST_HEIGHT_M: float = 24.0
const GUST_TAIL_S: float = 3.0
const FIELD_RADIUS_M: float = 12.0
## The top moving this far sideways counts as toppled/leaning over.
const TOPPLE_M: float = 3.0
## A top block that fell off the field and was freed counts as this far.
const FREED_M: float = 99.0
const GUST_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6]
const GUST_TOPPLE_MIN: int = 5
const STRONG_GUST_RADIUS_M: float = 12.0
const STRONG_GUST_DURATION_S: float = 5.0

var _field: Field = null
var _registry: BlockRegistry = null
var _manager: StableBlockManager = null
var _physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning


func _build(layers: int) -> Array[Block]:
	var map_def: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map_def.field_radius = FIELD_RADIUS_M
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	_registry.configure(_field, map_def)
	_manager = autofree(StableBlockManager.new())
	_manager.tuning = _physics
	add_child_autofree(_manager)
	_manager.setup(_registry)
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var edge: float = _physics.cube_size - _physics.cube_margin
	var column: Array[Block] = []
	for i: int in range(layers):
		for cell: Vector2 in TOWER_FOOTPRINT:
			var block: Block = BlockFactory.build(shape, _physics, 0)
			_field.add_child(block)
			block.position = Vector3(cell.x * (edge + TOWER_GAP_M), edge * 0.5 + edge * float(i), cell.y * (edge + TOWER_GAP_M))
			Events.block_placed.emit(block, shape.id)
			if cell == TOWER_FOOTPRINT[0]:
				column.append(block)
	return column


## Lets the tower land, puts every body to sleep (what Jolt does within a second
## or two) and lets the real manager freeze it static (20 s asleep).
func _settle_and_freeze() -> void:
	for _i: int in range(SETTLE_TICKS):
		await get_tree().physics_frame
	for block: Block in _registry.all_blocks():
		block.linear_velocity = Vector3.ZERO
		block.angular_velocity = Vector3.ZERO
		block.sleeping = true
	_manager._physics_process(FREEZE_ADVANCE_S)


func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _surface() -> float:
	return _field.surface_y()


## Max horizontal displacement of `top` while `step` runs for `seconds`. The
## displacement only ever grows as a running maximum, so a caller asserting
## "moved more than X" passes `stop_above = X` and the run ends the first tick it
## is exceeded (same verdict, no waiting out the rest of the
## gust/storm). Tests asserting "stays below X" leave it at INF and run in full.
func _measure(top: Block, seconds: float, step: Callable, stop_above: float = INF) -> float:
	var start: Vector3 = top.global_position
	var moved: float = 0.0
	for _i: int in range(int(seconds / DELTA)):
		step.call()
		await get_tree().physics_frame
		if not is_instance_valid(top):
			return FREED_M
		moved = maxf(moved, _horizontal(top.global_position, start))
		if moved > stop_above:
			break
	return moved


func _gust_sway(tower: Array[Block], seed_value: int, strength: float, stop_above: float = INF) -> float:
	var tuning: BreezeTuning = (load("res://config/breeze/breeze.tres") as BreezeTuning).duplicate() as BreezeTuning
	tuning.spawn_interval_s = 1.0e6
	# Capability test: an explicitly strong gust (the pre-1pi.76 defaults), not the
	# shipped small, short gust (r 4-6 m, 1.5-2.5 s), which topples only some towers.
	tuning.radius_max_m = STRONG_GUST_RADIUS_M
	tuning.duration_max_s = STRONG_GUST_DURATION_S
	var effect: BreezeEffect = BreezeEffect.new()
	effect.tuning = tuning
	effect.bind(WeatherTestHost.wind_context(self, func() -> Array: return _registry.all_blocks(), _surface))
	effect.begin(seed_value)
	var center: Vector3 = tower[0].global_position
	var angle: float = float(seed_value) * 1.1
	var duration: float = tuning.duration_max_s
	effect.gusts().append({"id": 1, "x": center.x, "y": _surface() + GUST_HEIGHT_M, "z": center.z,
		"a": angle, "r": tuning.radius_max_m, "d": duration, "s": strength, "age": 0.0})
	return await _measure(tower[tower.size() - 1], duration + GUST_TAIL_S, func() -> void: effect.tick(DELTA), stop_above)


func test_gust_topples_settled_tall_tower() -> void:
	var toppled: int = 0
	var report: String = ""
	for seed_value: int in GUST_SEEDS:
		var tower: Array[Block] = _build(TOWER_LAYERS)
		await _settle_and_freeze()
		var moved: float = await _gust_sway(tower, seed_value, 1.0, TOPPLE_M)
		report += " %.2f" % moved
		if moved > TOPPLE_M:
			toppled += 1
		for block: Block in _registry.all_blocks():
			block.free()
		_field.queue_free()
		await get_tree().process_frame
		if toppled >= GUST_TOPPLE_MIN:
			break  # the assertion below is already satisfied; later seeds cannot undo it
	gut.p("gust top displacement per seed (m):" + report)
	assert_gte(toppled, GUST_TOPPLE_MIN, "a strong gust topples a settled 30 m tower")


const WIND_TICKS: int = 12
const SUBMERGE_M: float = 5.0
const REFREEZE_LAYERS: int = 6


func _raised_surface() -> float:
	return _surface() - SUBMERGE_M


func _wind_tuning(max_wakes: int) -> StormTuning:
	var tuning: StormTuning = (load("res://config/weather/storm.tres") as StormTuning).duplicate() as StormTuning
	tuning.threshold_height_m = 0.5
	tuning.cap_height_m = 1.0
	tuning.wake_accel = 0.1
	tuning.sleeper_stride_ticks = 1
	tuning.max_wakes_per_tick = max_wakes
	return tuning


func _wind_effect(tuning: StormTuning) -> StormEffect:
	var effect: StormEffect = StormEffect.new()
	var context: FakeMatchContext = WeatherTestHost.wind_context(self, func() -> Array: return _registry.all_blocks(), _raised_surface)
	context.has_weather_value = true
	context.weather_seed_value = 11
	effect.bind(context, tuning)
	return effect


## Builds blocks at the given integer cells, through the placement path.
func _build_cells(cells: Array[Vector3i]) -> Dictionary:
	var map_def: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map_def.field_radius = FIELD_RADIUS_M
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	_registry.configure(_field, map_def)
	_manager = autofree(StableBlockManager.new())
	_manager.tuning = _physics
	add_child_autofree(_manager)
	_manager.setup(_registry)
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var edge: float = _physics.cube_size - _physics.cube_margin
	var pitch: float = edge + TOWER_GAP_M
	var by_cell: Dictionary = {}
	for cell: Vector3i in cells:
		var block: Block = BlockFactory.build(shape, _physics, 0)
		_field.add_child(block)
		block.position = Vector3(float(cell.x) * pitch, edge * 0.5 + edge * float(cell.y), float(cell.z) * pitch)
		Events.block_placed.emit(block, shape.id)
		by_cell[cell] = block
	return by_cell


func test_wind_woken_block_refreezes_after_wind_stops() -> void:
	var cells: Array[Vector3i] = []
	for i: int in range(REFREEZE_LAYERS):
		cells.append(Vector3i(0, i, 0))
	var by_cell: Dictionary = _build_cells(cells)
	await _settle_and_freeze()
	var effect: StormEffect = _wind_effect(_wind_tuning(1))
	var woken: int = 0
	for _i: int in range(WIND_TICKS):
		effect.tick(DELTA, 1.0)
		woken += effect.last_woken
		await get_tree().physics_frame
	assert_gt(woken, 0, "the storm woke at least one frozen block")
	var unfrozen: Array[Block] = []
	for block: Block in _registry.all_blocks():
		if not block.is_freeze_static():
			unfrozen.append(block)
	assert_gt(unfrozen.size(), 0, "woken blocks are no longer frozen")
	# The wind stops and the woken blocks fall asleep again before the next scan.
	for block: Block in unfrozen:
		block.linear_velocity = Vector3.ZERO
		block.angular_velocity = Vector3.ZERO
		block.sleeping = true
	_manager._physics_process(_physics.stable_freeze_delay_s + _physics.stable_freeze_scan_interval_s)
	for block: Block in unfrozen:
		assert_true(block.is_freeze_static(), "a woken block that settled re-froze within the normal delay")
	assert_eq(by_cell.size(), REFREEZE_LAYERS)

