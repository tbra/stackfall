extends GutTest
## Paintball activation: the body keeps only the glob; a slingshot copy releases and fades.

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks = autofree(Node3D.new())
	add_child_autofree(_blocks)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.gifts_enabled = false
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _glob_block() -> Block:
	var block: Block = Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres"),
		_field.world_from_disk_local(Match.slot(0).home_position, 5.0),
		Basis.IDENTITY, 0, Vector3.ZERO, null, null
	)
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	BlockFactory.apply_gift_visual(block, shape, Match._physics_tuning, &"paintball")
	return block


func _visible_names(visual: Node) -> Array[String]:
	var names: Array[String] = []
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).visible:
			names.append(mesh.name)
	return names


func test_fade_progress_holds_then_fades() -> void:
	assert_eq(PaintballSling.fade_progress(0.3, 0.5, 0.2, 0.4), 0.0)
	assert_eq(PaintballSling.fade_progress(0.7, 0.5, 0.2, 0.4), 0.0)
	assert_almost_eq(PaintballSling.fade_progress(0.9, 0.5, 0.2, 0.4), 0.5, 0.0001)
	assert_eq(PaintballSling.fade_progress(5.0, 0.5, 0.2, 0.4), 1.0)
	assert_eq(PaintballSling.fade_progress(0.8, 0.5, 0.2, 0.0), 1.0)


func test_body_shows_only_the_glob() -> void:
	var block: Block = _glob_block()
	var visual: Node = block.get_node(NodePath(String(BlockFactory.GIFT_VISUAL_NODE)))
	var names: Array[String] = _visible_names(visual)
	assert_false(names.is_empty())
	for n: String in names:
		assert_true(n.begins_with("Blob"), "only glob meshes visible, got %s" % n)


func test_sling_copy_spawns_without_glob_and_expires() -> void:
	var block: Block = _glob_block()
	var sling: PaintballSling = null
	for node: Node in _field.find_children("PaintballSling", "PaintballSling", true, false):
		sling = node as PaintballSling
	if sling == null:
		for node: Node in _blocks.find_children("PaintballSling", "PaintballSling", true, false):
			sling = node as PaintballSling
	assert_not_null(sling, "a sling copy is left at the launch point")
	if sling == null:
		return
	assert_true(sling.global_position.is_equal_approx(block.global_position))
	var names: Array[String] = _visible_names(sling)
	assert_true(names.has("Handle"))
	for n: String in names:
		assert_false(n.begins_with("Blob"), "glob stays on the projectile only")
	for _i: int in range(240):
		sling._process(1.0 / 60.0)
		if sling.is_queued_for_deletion():
			break
	assert_true(sling.is_queued_for_deletion(), "sling fades out and despawns")


func _block(slot_id: int, offset: Vector3) -> Block:
	return Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres"),
		_field.world_from_disk_local(Match.slot(slot_id).home_position, 5.0) + offset,
		Basis.IDENTITY, slot_id, Vector3.ZERO, null, null
	)
