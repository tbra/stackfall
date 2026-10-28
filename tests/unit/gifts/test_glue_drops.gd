extends GutTest
## Host-only Glue charges attach contact bonding to accepted future drops.

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _tuning: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.sandbox = true
	config.gifts_enabled = false
	config.rng_seed = 5251
	# Old gift rule (a claim replaces the next piece); the default after-next rule is in test_gift_queue_after_next.gd.
	config.experiments_enabled = true
	config.qol = QolExperiments.new()
	config.qol.gift_loads_next = true
	Match.start_match(config)
	for i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._feed.set_feed_timer_enabled(true)


func after_each() -> void:
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _bare_block(slot_id: int, position: Vector3) -> Block:
	var block: Block = Block.new()
	block.owner_slot = slot_id
	block.gravity_scale = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.4
	collision.shape = shape
	block.add_child(collision)
	_blocks_root.add_child(block)
	block.global_position = position
	return block


func _fused(a: Block, b: Block) -> bool:
	var carrier: RigidBody3D = a.fused_carrier()
	return carrier != null and carrier == b.fused_carrier()


func _carrier_of(block: Block) -> FusedBody:
	return block.fused_carrier() as FusedBody


func _home() -> Vector3:
	var point: Vector2 = Match.slot(0).home_position
	return _field.to_global(Vector3(point.x, 5.0, point.y))


func _place(auto_drop: bool = false, origin: Vector3 = Vector3.INF) -> StringName:
	var chosen: Vector3 = _home() if origin == Vector3.INF else origin
	return Match.request_place(0, chosen, 0, Quaternion.IDENTITY, auto_drop, Match.feed_seq(0))


func test_real_physics_contact_fuses() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var other: Block = _bare_block(1, Vector3(0.5, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, _tuning)
	for _i: int in range(4):
		await get_tree().physics_frame
	assert_true(_fused(a, other), "contact monitor fuses the real collision")


func test_gift_block_never_fuses() -> void:
	var gift: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	gift.gift_id = &"bomb"
	var b: Block = _bare_block(1, Vector3(1.0, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	b.add_child(glue)
	glue.bind(b, _tuning)
	assert_false(glue.try_bond(gift), "gift blocks never fuse")
	assert_null(b.fused_carrier())
	assert_null(gift.fused_carrier())


func test_contact_after_the_window_does_not_fuse() -> void:
	var tuning: GlueDropTuning = _tuning.duplicate() as GlueDropTuning
	tuning.fuse_window_s = 0.05
	var charged: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var near: Block = _bare_block(1, Vector3(0.7, 5.0, 0.0))
	var late: Block = _bare_block(1, Vector3(-5.0, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	charged.add_child(glue)
	glue.bind(charged, tuning)
	for _i: int in range(20):
		await get_tree().physics_frame
	assert_true(_fused(charged, near))
	late.global_position = Vector3(-0.7, 5.0, 0.0)
	for _i: int in range(8):
		await get_tree().physics_frame
	assert_false(_fused(charged, late), "a contact after fuse_window_s does not fuse")


func test_accepted_drop_spends_charge_but_locked_or_burned_drop_does_not() -> void:
	assert_true(Match.grant_glue_drops(0, 3))
	assert_eq(_place(), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 2)
	var first: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	assert_not_null(first)
	var binder: GlueDrops = null
	for child: Node in first.get_children():
		if child is GlueDrops:
			binder = child as GlueDrops
	assert_not_null(binder, "charged accepted block monitors contacts")
	assert_eq(_place(), PlacementRules.REASON_NO_BLOCK)
	assert_eq(Match.glue_drops_left(0), 2)
	TerritoryTestHelpers.blank_owned_territory(Match.raster(), Match.team_of(0))
	var far: Vector3 = _field.to_global(Vector3(5000.0, 5.0, 5000.0))
	assert_ne(_place(true, far), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 2)


func test_claimed_glue_refreshes_charges_and_is_never_held() -> void:
	# Glue is a modifier, so a claim grants 5 charges and the
	# next placed block is an ordinary piece that spends one.
	assert_true(Match.grant_glue_drops(0, 2))
	assert_true(Match.debug_queue_special(0, &"glue"))
	assert_eq(Match.glue_drops_left(0), 5)
	assert_eq(Match.held_special(0), &"")
	assert_eq(_place(), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 4)


func test_throw_does_not_spend_a_drop_charge() -> void:
	assert_true(Match.grant_glue_drops(0, 2))
	assert_true(Match.debug_queue_special(0, &"bomb"))
	assert_eq(_place(), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 1)
	assert_eq(Match.held_special(0), &"bomb")
	assert_eq(
		Match.request_throw(0, _home(), 0, Quaternion.IDENTITY, Vector3(2.0, 0.0, 0.0), Match.feed_seq(0)),
		PlacementRules.REASON_OK
	)
	assert_eq(Match.glue_drops_left(0), 1)


const BLAST_ZONE_Z: float = 2.0


func _real_block(shape_id: String, slot_id: int, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, slot_id)
	_blocks_root.add_child(block)
	block.global_position = at
	return block


## `b` rests on the disc, the charged `a` is stacked on top of it: only `b` touches the disc, so
## the fused pair must stay a free body (a's own shapes never touch the Field).
func _glued_pair(tuning: GlueDropTuning = null) -> Array[Block]:
	var rest_y: float = _field.surface_y() + 0.6
	var b: Block = _real_block("cube", 1, _field.to_global(Vector3(0.0, rest_y, 0.0)))
	var a: Block = _real_block("cube", 0, _field.to_global(Vector3(0.0, rest_y + 1.05, 0.0)))
	for _i: int in range(40):
		await get_tree().physics_frame
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, tuning if tuning != null else _tuning)
	assert_true(glue.try_bond(b) or _fused(a, b))
	return [a, b]


const WINDOW_SETTLE_FRAMES: int = 20
const MOVED_MIN_M: float = 0.02
func test_fused_pair_survives_a_two_metre_blast() -> void:
	var pair: Array[Block] = await _glued_pair()
	var center: Vector3 = pair[0].global_position + Vector3(-BLAST_ZONE_Z, 0.0, 0.0)
	var space: PhysicsDirectSpaceState3D = pair[0].get_world_3d().direct_space_state
	for _i: int in range(WINDOW_SETTLE_FRAMES):
		await get_tree().physics_frame
	assert_false(_carrier_of(pair[0]).is_disc_anchored(), "precondition: a free body, not pinned to the disc")
	var before: Vector3 = _carrier_of(pair[0]).global_position
	ExplosionFx.blast(space, center, ExplosionTuning.new(), [])
	for _i: int in range(30):
		await get_tree().physics_frame
	assert_true(_fused(pair[0], pair[1]), "blasts do not split a fused body")
	assert_gt(_carrier_of(pair[0]).global_position.distance_to(before), MOVED_MIN_M, "the blast moves the free body")


func test_charged_drop_on_a_disc_resting_block_is_not_disc_anchored() -> void:
	var pair: Array[Block] = await _glued_pair()
	for _i: int in range(WINDOW_SETTLE_FRAMES):
		await get_tree().physics_frame
	assert_true(_fused(pair[0], pair[1]))
	assert_false(_carrier_of(pair[0]).is_disc_anchored(), "the partner's disc contact must not anchor the group")
