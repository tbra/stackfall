extends GutTest
## GiftFxPresenter and GiftBlink (Bontago-1pi.85.8): dispatch by def id, once,
## ignoring unknown ids and non-finite positions; Match owns the live instance.

const TEST_ID: StringName = &"test_gift_fx_id"

var _presenter: GiftFxPresenter
var _calls: Array = []


func before_each() -> void:
	_calls.clear()
	_presenter = GiftFxPresenter.new()
	add_child_autofree(_presenter)
	_presenter.register(TEST_ID, _spy)


func _spy(block: Block, def: SpecialDef, position: Vector3) -> void:
	_calls.append([block, def, position])


func test_dispatches_registered_id_once_with_position() -> void:
	_presenter.connect_events()
	_presenter.connect_events()
	Events.special_triggered.emit(-1, TEST_ID, Vector3(1, 2, 3), 0)
	assert_eq(_calls.size(), 1, "one subscription, one call")
	assert_eq(_calls[0][2], Vector3(1, 2, 3))
	assert_null(_calls[0][0], "unknown net id gives a null block")


func test_unknown_id_and_non_finite_position_ignored() -> void:
	Events.special_triggered.emit(-1, &"no_such_gift", Vector3.ZERO, 0)
	Events.special_triggered.emit(-1, TEST_ID, Vector3(INF, 0, 0), 0)
	Events.special_triggered.emit(-1, TEST_ID, Vector3(0, NAN, 0), 0)
	assert_eq(_calls.size(), 0)


func test_unregister_stops_dispatch() -> void:
	_presenter.unregister(TEST_ID)
	Events.special_triggered.emit(-1, TEST_ID, Vector3.ZERO, 0)
	assert_eq(_calls.size(), 0)


func test_default_handlers_registered_and_match_owns_one() -> void:
	assert_true(_presenter.has_handler(GiftFxPresenter.PAINTBALL_ID))
	assert_true(_presenter.has_handler(GiftFxPresenter.BLACK_HOLE_ID))
	assert_not_null(Match._gift_fx)
	assert_true(Match._gift_fx.is_inside_tree())


func test_black_hole_handler_adds_visual_under_blocks_parent() -> void:
	var blocks: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks)
	Match.register_world(null, null, blocks)
	Events.special_triggered.emit(-1, GiftFxPresenter.BLACK_HOLE_ID, Vector3(1, 2, 3), 0)
	var found: bool = false
	for child: Node in blocks.get_children():
		if child is BlackHoleVisual:
			found = true
	assert_true(found)
	MatchTestReset.clear_world()


func test_blink_pure_helpers_and_driver() -> void:
	assert_almost_eq(GiftBlink.period_at(0.0, 0.25, 3.0), 0.25, 0.0001)
	assert_almost_eq(GiftBlink.period_at(3.0, 0.25, 3.0), 0.25 * GiftBlink.DEFAULT_TUNING.end_period_ratio, 0.0001)
	assert_almost_eq(GiftBlink.intensity_at(0.0), 0.0, 0.0001)
	assert_almost_eq(GiftBlink.intensity_at(0.5), 1.0, 0.0001)
	var block: Block = autofree(Block.new())
	var visual: Node3D = Node3D.new()
	visual.name = BlockFactory.GIFT_VISUAL_NODE
	var mesh: MeshInstance3D = MeshInstance3D.new()
	visual.add_child(mesh)
	block.add_child(visual)
	add_child_autofree(block)
	GiftBlink.apply(block, 0.25, 1.0)
	var driver: Node = block.get_node(NodePath(String(GiftBlink.DRIVER_NAME)))
	assert_not_null(mesh.material_overlay, "overlay installed")
	driver.call("_process", 0.5)
	assert_not_null(mesh.material_overlay)
	driver.call("_process", 0.6)
	assert_null(mesh.material_overlay, "overlay removed when the blink ends")
	GiftBlink.apply(null, 0.25, 1.0)
