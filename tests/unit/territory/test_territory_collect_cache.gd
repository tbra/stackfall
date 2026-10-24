extends GutTest
## BlockRegistry's per-block geometry cache must return
## exactly what the uncached path returns.

const STEPS: int = 200
const START_BLOCKS: int = 12
const SLOT_COUNT: int = 4

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")
var _map_def: MapDef
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_each() -> void:
	_map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map_def.field_radius = 20.0
	_rng.seed = 2211


func _slots() -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(SLOT_COUNT):
		slots.append(PlayerSlot.new(i, i % 2, "P%d" % i, Color.WHITE, Vector2.ZERO))
	return slots


func _shapes() -> Array[BlockShape]:
	var shapes: Array[BlockShape] = [
		load("res://config/blocks/cube.tres") as BlockShape,
		load("res://config/blocks/L3.tres") as BlockShape,
		load("res://config/blocks/T4.tres") as BlockShape,
		load("res://config/blocks/slab6.tres") as BlockShape,
	]
	return shapes


func _make_rig() -> Array:
	var field: Field = autofree(Field.new())
	field.map_def = _map_def
	add_child_autofree(field)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.configure(field, _map_def)
	return [field, registry]


func _spawn(registry: BlockRegistry, field: Field, shapes: Array[BlockShape]) -> Block:
	var shape: BlockShape = shapes[_rng.randi() % shapes.size()]
	var block: Block = BlockFactory.build(shape, _tuning, _rng.randi() % SLOT_COUNT)
	block.freeze = true
	field.add_child(block)
	block.global_transform = Transform3D(
		Basis(Vector3.UP, _rng.randf_range(0.0, TAU)),
		Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(0.0, 4.0), _rng.randf_range(-12.0, 12.0))
	)
	Events.block_placed.emit(block, shape.id)
	_settle(registry)
	return block


## One production tick whose delta alone spans the settle time: every frozen
## block placed so far reads settled.
func _settle(registry: BlockRegistry) -> void:
	registry._physics_process(_tuning.sleep_settle_time + 1.0)


## A fresh registry fed the same blocks: it has never cached anything, so what it
## answers is the uncached truth. Every other listener is taken off the bus while
## the blocks are announced again, so `cached` keeps its cache and nothing else
## sees a second placement.
func _fresh_registry_with(field: Field, blocks: Array[Block]) -> BlockRegistry:
	var detached: Array = Events.block_placed.get_connections()
	for connection: Dictionary in detached:
		Events.block_placed.disconnect(connection["callable"] as Callable)
	var fresh: BlockRegistry = BlockRegistry.new()
	add_child(fresh)
	fresh.configure(field, _map_def)
	for block: Block in blocks:
		Events.block_placed.emit(block, &"")
	for connection: Dictionary in detached:
		Events.block_placed.connect(connection["callable"] as Callable, int(connection["flags"]))
	_settle(fresh)
	return fresh


func _same(a: InfluenceCircle, b: InfluenceCircle) -> bool:
	return (
		a.center == b.center and a.radius == b.radius and a.team_id == b.team_id
		and a.slot_id == b.slot_id and a.body_id == b.body_id and a.is_home == b.is_home
	)


func _assert_equal(
	registry: BlockRegistry, field: Field, blocks: Array[Block], slots: Array[PlayerSlot], label: String
) -> bool:
	var cached: Array[InfluenceCircle] = registry.influence_circles(slots, _territory_tuning, _map_def)
	var cached_again: Array[InfluenceCircle] = registry.influence_circles(slots, _territory_tuning, _map_def)
	var torque_cached: PackedVector3Array = registry.settled_torque_samples()
	var height_cached: float = registry.max_height_for_slot(1)
	var fresh: BlockRegistry = _fresh_registry_with(field, blocks)
	var oracle: Array[InfluenceCircle] = fresh.influence_circles(slots, _territory_tuning, _map_def)
	var torque_oracle: PackedVector3Array = fresh.settled_torque_samples()
	var height_oracle: float = fresh.max_height_for_slot(1)
	fresh.free()
	if cached.size() != oracle.size() or cached_again.size() != oracle.size():
		fail_test("%s: size differs" % label)
		return false
	for i: int in range(oracle.size()):
		if not _same(cached[i], oracle[i]) or not _same(cached_again[i], oracle[i]):
			fail_test("%s: circle %d differs" % [label, i])
			return false
	if torque_cached != torque_oracle or height_cached != height_oracle:
		fail_test("%s: torque or height differs" % label)
		return false
	return true


func test_cached_circles_equal_uncached_over_random_board_changes() -> void:
	var rig: Array = _make_rig()
	var field: Field = rig[0]
	var registry: BlockRegistry = rig[1]
	var slots: Array[PlayerSlot] = _slots()
	var shapes: Array[BlockShape] = _shapes()
	var blocks: Array[Block] = []
	for i: int in range(START_BLOCKS):
		blocks.append(_spawn(registry, field, shapes))
	for step: int in range(STEPS):
		var action: int = _rng.randi() % 7
		var pick: int = _rng.randi() % blocks.size()
		match action:
			0:
				blocks.append(_spawn(registry, field, shapes))
			1:
				if blocks.size() > 2:
					var victim: Block = blocks[pick]
					blocks.remove_at(pick)
					Events.block_removed.emit(victim, "test")
					victim.queue_free()
			2:
				blocks[pick].global_position += Vector3(
					_rng.randf_range(-0.0005, 0.0005), 0.0, _rng.randf_range(-0.0005, 0.0005)
				)
			3:
				blocks[pick].global_position += Vector3(
					_rng.randf_range(-3.0, 3.0), _rng.randf_range(0.0, 2.0), _rng.randf_range(-3.0, 3.0)
				)
			4:
				blocks[pick].rotate(
					Vector3(_rng.randf() + 0.1, _rng.randf(), _rng.randf()).normalized(),
					_rng.randf_range(-1.0, 1.0)
				)
			5:
				registry.convert_owner(blocks[pick], _rng.randi() % SLOT_COUNT, Color.WHITE)
			6:
				field.rotation = Vector3(_rng.randf_range(-0.1, 0.1), 0.0, _rng.randf_range(-0.1, 0.1))
				field.position.y = _rng.randf_range(-0.2, 0.2)
		if not _assert_equal(registry, field, blocks, slots, "step %d action %d" % [step, action]):
			return
	pass_test("200 random steps matched")


