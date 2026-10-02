extends GutTest
## Bontago-mp0.36: wind and Breeze gusts must reach a SETTLED tall tower. In real
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
const STORM_SECONDS: float = 20.0
const FIELD_RADIUS_M: float = 12.0
## The top moving this far sideways counts as toppled/leaning over.
const TOPPLE_M: float = 3.0
## Visible sway in steady storm wind.
const SWAY_M: float = 0.5
## A top block that fell off the field and was freed counts as this far.
const FREED_M: float = 99.0
const SHORT_LAYERS: int = 3
const SHORT_MAX_M: float = 0.1
const GUST_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6]
const GUST_TOPPLE_MIN: int = 5

var _field: Field = null
var _registry: BlockRegistry = null
var _manager: StableBlockManager = null
var _physics: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning


func _build(layers: int) -> Array[Block]:
	var map_def: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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
	_manager._tick(FREEZE_ADVANCE_S)


func _frozen_count() -> int:
	var count: int = 0
	for block: Block in _registry.all_blocks():
		if block.is_freeze_static():
			count += 1
	return count


func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _surface() -> float:
	return _field.surface_y()


## Max horizontal displacement of `top` while `step` runs for `seconds`.
func _measure(top: Block, seconds: float, step: Callable) -> float:
	var start: Vector3 = top.global_position
	var moved: float = 0.0
	for _i: int in range(int(seconds / DELTA)):
		step.call()
		await get_tree().physics_frame
		if not is_instance_valid(top):
			return FREED_M
		moved = maxf(moved, _horizontal(top.global_position, start))
	return moved


func _gust_sway(tower: Array[Block], seed_value: int, strength: float) -> float:
	var tuning: BreezeTuning = (load("res://config/breeze.tres") as BreezeTuning).duplicate() as BreezeTuning
	tuning.spawn_interval_s = 1.0e6
	var effect: BreezeEffect = BreezeEffect.new()
	effect.tuning = tuning
	effect.set_test_world(func() -> Array: return _registry.all_blocks(), _surface)
	effect.begin(seed_value)
	var center: Vector3 = tower[0].global_position
	var angle: float = float(seed_value) * 1.1
	var duration: float = tuning.duration_max_s
	effect.gusts().append({"id": 1, "x": center.x, "y": _surface() + GUST_HEIGHT_M, "z": center.z,
		"a": angle, "r": tuning.radius_max_m, "d": duration, "s": strength, "age": 0.0})
	return await _measure(tower[tower.size() - 1], duration + GUST_TAIL_S, func() -> void: effect.tick(DELTA))


func _storm_sway(tower: Array[Block], seconds: float) -> float:
	var effect: StormEffect = StormEffect.new()
	effect.tuning = load("res://config/weather/storm.tres") as StormTuning
	effect.set_seed(11)
	effect.set_test_world(func() -> Array: return _registry.all_blocks(), _surface)
	return await _measure(tower[tower.size() - 1], seconds, func() -> void: effect.tick(DELTA, 1.0))


func test_manager_freezes_the_settled_tower() -> void:
	_build(TOWER_LAYERS)
	await _settle_and_freeze()
	assert_eq(_frozen_count(), TOWER_LAYERS * TOWER_FOOTPRINT.size(), "settled tower is frozen static like in real play")


func test_gust_topples_settled_tall_tower() -> void:
	var toppled: int = 0
	var report: String = ""
	for seed_value: int in GUST_SEEDS:
		var tower: Array[Block] = _build(TOWER_LAYERS)
		await _settle_and_freeze()
		var moved: float = await _gust_sway(tower, seed_value, 1.0)
		report += " %.2f" % moved
		if moved > TOPPLE_M:
			toppled += 1
		for block: Block in _registry.all_blocks():
			block.free()
		_field.queue_free()
		await get_tree().process_frame
	gut.p("gust top displacement per seed (m):" + report)
	assert_gte(toppled, GUST_TOPPLE_MIN, "a strong gust topples a settled 30 m tower")


func test_storm_sways_settled_tall_tower() -> void:
	var tower: Array[Block] = _build(TOWER_LAYERS)
	await _settle_and_freeze()
	var moved: float = await _storm_sway(tower, STORM_SECONDS)
	gut.p("storm top displacement: %.2f m" % moved)
	assert_gt(moved, SWAY_M, "steady storm wind moves a settled 30 m tower")


func test_low_wide_stack_is_unmoved_by_storm() -> void:
	var tower: Array[Block] = _build(SHORT_LAYERS)
	await _settle_and_freeze()
	var moved: float = await _storm_sway(tower, STORM_SECONDS)
	assert_lt(moved, SHORT_MAX_M, "a low stack stays put")
