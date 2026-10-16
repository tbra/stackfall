extends GutTest
## Glue fusion: a FusedBody carrier against BlockRegistry (territory circles),
## the kill plane and HoleDissolver (one member dissolves, the rest stays, exactly
## one block_removed per member). Bodies are fused through GlueFusion directly.

const CUBE_SIDE_M: float = 1.2
const REST_HEIGHT_M: float = 0.62
const SETTLE_FRAMES: int = 90
const DISSOLVE_FRAMES: int = 90
const FUSE_SETTLE_FRAMES: int = 30
const CIRCLE_TOLERANCE: float = 0.001

var _physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _territory: TerritoryTuning = load("res://config/territory/territory_tuning.tres")
var _glue: GlueDropTuning = load("res://config/gifts/glue_drop_tuning.tres")
var _cube: BlockShape = load("res://config/blocks/cube.tres")

var _field: Field
var _registry: BlockRegistry
var _root: Node3D
var _map: MapDef
## instance id -> number of block_removed emissions seen.
var _removed_counts: Dictionary = {}


func before_each() -> void:
	_removed_counts = {}
	Events.block_removed.connect(_record_removed)
	_map = MapDef.new()
	_map.id = &"test_fused_territory"
	_map.field_radius = 6.0
	_map.cell_size = 1.0
	_map.disk_height = 1.0
	_map.territory_res = 32
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_root = autofree(Node3D.new())
	add_child_autofree(_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	_registry.set_host_authority(true)
	_registry.configure(_field, _map)


func after_each() -> void:
	if Events.block_removed.is_connected(_record_removed):
		Events.block_removed.disconnect(_record_removed)
	Match._net_provider = null


func _record_removed(block: RigidBody3D, _reason: String) -> void:
	var id: int = block.get_instance_id()
	_removed_counts[id] = int(_removed_counts.get(id, 0)) + 1


func _removed_count(id: int) -> int:
	return int(_removed_counts.get(id, 0))


func _slots() -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(2):
		slots.append(PlayerSlot.new(i, i, "P%d" % i, Color.WHITE, Vector2.ZERO))
	return slots


func _spawn(slot: int, local: Vector3) -> Block:
	var block: Block = BlockFactory.build(_cube, _physics, slot)
	_root.add_child(block)
	block.global_position = _field.to_global(local)
	Events.block_placed.emit(block, _cube.id)
	return block


func _pair_on_disc() -> Array[Block]:
	var a: Block = _spawn(0, Vector3(-CUBE_SIDE_M * 0.5, REST_HEIGHT_M, 0.0))
	var b: Block = _spawn(1, Vector3(CUBE_SIDE_M * 0.5, REST_HEIGHT_M, 0.0))
	return [a, b]


func _fuse(charged: Block, target: PhysicsBody3D) -> FusedBody:
	return GlueFusion.fuse(charged, target, _glue)


func _circles_by_slot() -> Dictionary:
	var by_slot: Dictionary = {}
	for circle: InfluenceCircle in _registry.influence_circles(_slots(), _territory, _map):
		by_slot[circle.slot_id] = circle
	return by_slot


func _wait_all_settled(max_frames: int) -> void:
	var frames: int = 0
	while frames < max_frames and not _registry.all_settled():
		await wait_physics_frames(1)
		frames += 1


func test_member_circles_equal_the_unfused_equivalents() -> void:
	var pair: Array[Block] = _pair_on_disc()
	await wait_physics_frames(SETTLE_FRAMES)
	await _wait_all_settled(SETTLE_FRAMES)
	var before: Dictionary = _circles_by_slot()
	assert_eq(before.size(), 2, "both unfused cubes own a circle")

	var carrier: FusedBody = _fuse(pair[0], pair[1])
	assert_not_null(carrier)
	await wait_physics_frames(FUSE_SETTLE_FRAMES)
	await _wait_all_settled(SETTLE_FRAMES)
	var after: Dictionary = _circles_by_slot()

	assert_eq(after.size(), 2, "a fused pair still yields one circle per member")
	for slot: int in [0, 1]:
		var was: InfluenceCircle = before[slot] as InfluenceCircle
		var now: InfluenceCircle = after.get(slot) as InfluenceCircle
		assert_not_null(now)
		if now == null:
			continue
		assert_almost_eq(now.center.x, was.center.x, CIRCLE_TOLERANCE, "slot %d centre x" % slot)
		assert_almost_eq(now.center.y, was.center.y, CIRCLE_TOLERANCE, "slot %d centre z" % slot)
		assert_almost_eq(now.radius, was.radius, CIRCLE_TOLERANCE, "slot %d radius" % slot)
		assert_almost_eq(now.top_height, was.top_height, CIRCLE_TOLERANCE, "slot %d top" % slot)
		assert_eq(now.team_id, was.team_id)
		assert_eq(now.body_id, pair[slot].get_instance_id(), "keyed by the member, not the carrier")


func test_kill_plane_removes_every_member_with_exactly_one_block_removed() -> void:
	var pair: Array[Block] = _pair_on_disc()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	var ids: Array[int] = [pair[0].get_instance_id(), pair[1].get_instance_id()]
	var carrier_id: int = carrier.get_instance_id()

	_field.remove_fallen_block(carrier)
	await wait_physics_frames(3)

	for id: int in ids:
		assert_eq(_removed_count(id), 1, "one block_removed per member")
	assert_eq(_removed_count(carrier_id), 0, "never emitted for the carrier")
	assert_eq(_registry.tracked_block_count(), 0)
	assert_false(is_instance_valid(carrier), "carrier freed")
	assert_false(is_instance_valid(pair[0]))


func test_a_hole_under_one_member_dissolves_only_it_and_wakes_the_rest() -> void:
	var grid: CellGrid = _field.grid()
	var cell: int = grid.cell_index(floori(float(grid.res) * 0.5), floori(float(grid.res) * 0.5))
	var low: Block = BlockFactory.build(_cube, _physics, 0)
	_root.add_child(low)
	low.global_position = _field.world_from_disk_local(grid.index_center(cell), REST_HEIGHT_M)
	Events.block_placed.emit(low, _cube.id)
	var high: Block = BlockFactory.build(_cube, _physics, 1)
	_root.add_child(high)
	high.global_position = _field.world_from_disk_local(grid.index_center(cell), REST_HEIGHT_M + CUBE_SIDE_M)
	Events.block_placed.emit(high, _cube.id)
	await wait_physics_frames(SETTLE_FRAMES)
	var carrier: FusedBody = _fuse(high, low)
	assert_not_null(carrier)
	await wait_physics_frames(FUSE_SETTLE_FRAMES)
	carrier.sleeping = true
	var low_id: int = low.get_instance_id()
	var high_id: int = high.get_instance_id()

	_field.set_hole_cells(PackedInt32Array([cell]), PackedInt32Array())
	await wait_physics_frames(2)
	assert_true(_registry.hole_dissolver().is_dissolving(low), "the member touching the hole dissolves")
	assert_false(_registry.hole_dissolver().is_dissolving(high), "the member above it does not")
	assert_false(_registry.hole_dissolver().is_dissolving(carrier), "the carrier itself is never a candidate")

	var frames: int = 0
	while frames < DISSOLVE_FRAMES and _removed_count(low_id) == 0:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(_removed_count(low_id), 1, "exactly one block_removed for the doomed member")
	assert_eq(_removed_count(high_id), 0, "the rest stays")
	assert_true(is_instance_valid(high))
	assert_true(_registry.is_tracked(high))
	assert_false(high.sleeping, "its column woke so it falls onto the void")
	assert_false(high.is_fused_member(), "a lone survivor collapses back to a plain block")


