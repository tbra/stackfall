extends GutTest
## A CartoonBlast hangs under the persistent Field; one still animating when the match scope
## resets must go with it instead of surviving into the next match.

const MAP_RADIUS_M: float = 6.0
const BOMB_ID: StringName = &"bomb"
const DROP_POINT: Vector3 = Vector3(1.0, 0.5, 1.0)

var _field: Field = null


func before_each() -> void:
	_field = autofree(Field.new())
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_blast_reset"
	map_def.field_radius = MAP_RADIUS_M
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field.map_def = map_def
	add_child_autofree(_field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(_field, registry, blocks_root)


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	MatchTestReset.clear_world()


func _blast_count() -> int:
	var count: int = 0
	for child: Node in _field.get_children():
		if child is CartoonBlast and not child.is_queued_for_deletion():
			count += 1
	return count


func test_blast_still_animating_is_freed_by_match_scope_reset() -> void:
	var presenter: GiftFxPresenter = autofree(GiftFxPresenter.new())
	add_child_autofree(presenter)
	presenter.on_special_triggered(-1, BOMB_ID, DROP_POINT, 0)
	assert_eq(_blast_count(), 1, "fixture: the bomb spawned a live blast")
	Events.match_scope_reset.emit()
	assert_eq(_blast_count(), 0, "the blast does not survive the reset")
