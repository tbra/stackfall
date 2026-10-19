extends GutTest
## SnowClientRenderer builds a client's snow caps from a sanitized state dictionary
## alone: no session, no Match, no peer. SnowNet only validates and hands over.

const NET_ID: int = 71
const OTHER_NET_ID: int = 72
const FIELD_RADIUS_M: float = 6.0
const BIG_BUDGET: int = 1000
const SEED_VALUE: int = 99
const COVER_LEVEL: int = 2
const PATCH_LEVEL: int = 3

var _snow: SnowTuning = null
var _physics: PhysicsTuning = null
var _field: Field = null
var _registry: BlockRegistry = null
var _renderer: SnowClientRenderer = null


func before_each() -> void:
	_physics = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	_snow = (load("res://config/weather/snow.tres") as SnowTuning).duplicate() as SnowTuning
	_field = Field.new()
	_field.map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_field.map_def.field_radius = FIELD_RADIUS_M
	add_child_autofree(_field)
	_registry = BlockRegistry.new()
	_renderer = SnowClientRenderer.new(_snow, _field_source, _registry_source)


func after_each() -> void:
	_registry.free()


func _field_source() -> Field:
	return _field


func _registry_source() -> BlockRegistry:
	return _registry


func _block(net_id: int) -> Block:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	block.freeze = true
	add_child_autofree(block)
	_registry.bind_net_id(block, net_id)
	return block


## A sanitized state naming `net_ids` plus (when >= 0) one disc cell.
func _state(net_ids: Array[int], disc_cell: int, cover: int = COVER_LEVEL) -> Dictionary:
	var b: PackedInt32Array = PackedInt32Array()
	for net_id: int in net_ids:
		SnowGeometry.append_block_record(b, net_id, SnowGeometry.AXIS_UP, PackedInt32Array([0]), PackedInt32Array([PATCH_LEVEL]))
	var d: PackedInt32Array = PackedInt32Array()
	if disc_cell >= 0:
		d.append_array(PackedInt32Array([disc_cell, COVER_LEVEL]))
	var data: Dictionary = SnowGeometry.sanitize_state(SnowGeometry.make_state(SEED_VALUE, cover, b, d), _snow, _field.grid().cell_count() - 1)
	assert_false(data.is_empty(), "fixture state is well formed")
	return data


func _cap(block: Node) -> Node:
	var cap: Node = block.get_node_or_null(NodePath(String(SnowCaps.CAP_NAME)))
	return cap.get_node_or_null(NodePath(String(SnowCaps.CAP_MESH_NAME))) if cap != null else null


func test_apply_then_step_draws_block_and_disc_caps_without_colliders() -> void:
	var block: Block = _block(NET_ID)
	_renderer.apply(_state([NET_ID], _field.grid().in_disk_cells()[0]))
	assert_null(_cap(block), "drawing is amortised over frames")
	_renderer.step(BIG_BUDGET)
	assert_not_null(_cap(block), "cap drawn on the block")
	assert_eq(SnowCaps.lump_colliders(block).size(), 0, "no collider")
	assert_true(SnowCaps.disc_bodies(_field).is_empty(), "no disc collider body")
	var cover: SnowDiscCover = _field.get_node_or_null(NodePath(String(SnowCaps.DISC_COVER_NAME))) as SnowDiscCover
	assert_not_null(cover, "disc cover drawn")
	assert_eq(cover.level(), COVER_LEVEL)


func test_unresolved_block_is_drawn_once_it_exists() -> void:
	_renderer.apply(_state([NET_ID], -1))
	assert_true(_renderer.is_unresolved(), "the block is not bound yet")
	var block: Block = _block(NET_ID)
	_renderer.render()
	assert_false(_renderer.is_unresolved())
	_renderer.step(BIG_BUDGET)
	assert_not_null(_cap(block))


func test_a_block_dropped_from_the_state_loses_its_cap() -> void:
	var kept: Block = _block(NET_ID)
	var dropped: Block = _block(OTHER_NET_ID)
	_renderer.apply(_state([NET_ID, OTHER_NET_ID], -1))
	_renderer.step(BIG_BUDGET)
	assert_not_null(_cap(dropped))
	_renderer.apply(_state([NET_ID], -1))
	_renderer.step(BIG_BUDGET)
	assert_null(_cap(dropped), "no longer listed")
	assert_not_null(_cap(kept))


func test_clear_removes_every_cap_and_forgets_the_state() -> void:
	var block: Block = _block(NET_ID)
	_renderer.apply(_state([NET_ID], _field.grid().in_disk_cells()[0]))
	_renderer.step(BIG_BUDGET)
	_renderer.clear()
	_renderer.step(BIG_BUDGET)
	_renderer.render()
	assert_null(_cap(block), "a cleared renderer forgot the state and redraws nothing")
	assert_null(_cap(block))
	assert_null(_field.get_node_or_null(NodePath(String(SnowCaps.DISC_COVER_NAME))), "the cover is gone")


func test_missing_world_does_not_crash() -> void:
	var blind: SnowClientRenderer = SnowClientRenderer.new(_snow, Callable(), Callable())
	blind.apply(_state([NET_ID], -1))
	assert_true(blind.is_unresolved(), "no registry, nothing resolves")
	blind.step(BIG_BUDGET)
	blind.clear()
	blind.render()
	assert_false(blind.is_unresolved(), "clear forgot the state")
