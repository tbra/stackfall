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
	config.hot_seat = false
	config.sandbox = true
	config.gifts_enabled = false
	config.rng_seed = 5251
	# Old gift rule (a claim replaces the next piece); the after-next trial is in test_gift_queue_after_next.gd.
	config.qol = QolExperiments.new()
	config.qol.gift_queue_after_next = false
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


func test_fusing_uses_contact_targets_and_deduplicates_both_directions() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var b: Block = _bare_block(1, Vector3(1.0, 5.0, 0.0))
	var glue_a: GlueDrops = GlueDrops.new()
	a.add_child(glue_a)
	glue_a.bind(a, _tuning)
	assert_true(a.contact_monitor)
	assert_gte(a.max_contacts_reported, _tuning.max_contacts_reported)
	assert_true(glue_a.try_bond(b), "a contacted enemy block can be fused")
	assert_true(_fused(a, b))
	assert_false(glue_a.try_bond(b), "same contact cannot fuse twice")
	var glue_b: GlueDrops = GlueDrops.new()
	b.add_child(glue_b)
	glue_b.bind(b, _tuning)
	assert_false(glue_b.try_bond(a), "reverse charged contact shares the existing pair")
	assert_true(glue_a.try_bond(_field), "the disc is a valid physics-body partner")
	assert_false(glue_a.try_bond(_field))
	assert_true(_carrier_of(a).is_disc_anchored(), "fusing with the disc anchors the group")
	assert_eq(_carrier_of(a), _carrier_of(b), "still one body")
	var unrelated: Node3D = Node3D.new()
	assert_false(glue_a.try_bond(unrelated), "unrelated nodes cannot bond")
	unrelated.free()


func test_real_physics_contact_fuses() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var other: Block = _bare_block(1, Vector3(0.5, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, _tuning)
	for _i: int in range(4):
		await get_tree().physics_frame
	assert_true(_fused(a, other), "contact monitor fuses the real collision")


func test_real_disc_contact_fuses() -> void:
	var block: Block = _bare_block(0, _field.to_global(Vector3(0.0, 0.2, 0.0)))
	var glue: GlueDrops = GlueDrops.new()
	block.add_child(glue)
	glue.bind(block, _tuning)
	for _i: int in range(4):
		await get_tree().physics_frame
	var carrier: FusedBody = _carrier_of(block)
	assert_not_null(carrier, "the disc collider must be reported as a contact")
	if carrier != null:
		assert_true(carrier.is_disc_anchored())


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


func test_charged_block_landing_on_a_base_fuses() -> void:
	var rest_y: float = _field.surface_y() + 0.6
	var base: Block = _real_block("cube", 1, _field.to_global(Vector3(0.0, rest_y, 0.0)))
	for _i: int in range(40):
		await get_tree().physics_frame
	var dropped: Block = _real_block("cube", 0, base.global_position + Vector3(0.0, 2.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	dropped.add_child(glue)
	glue.bind(dropped, _tuning)
	for _i: int in range(90):
		await get_tree().physics_frame
	assert_true(_fused(dropped, base), "a charged drop fuses with what it lands on")


func test_charged_block_bridging_two_blocks_fuses_all_three() -> void:
	var charged: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var left: Block = _bare_block(1, Vector3(-0.7, 5.0, 0.0))
	var right: Block = _bare_block(1, Vector3(0.7, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	charged.add_child(glue)
	glue.bind(charged, _tuning)
	for _i: int in range(8):
		await get_tree().physics_frame
	assert_not_null(charged.fused_carrier())
	assert_true(_fused(charged, left), "left neighbour fused")
	assert_true(_fused(charged, right), "right neighbour fused")
	for _i: int in range(20):
		await get_tree().physics_frame
	assert_false(is_instance_valid(glue), "binder frees itself after the window")


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


func test_gift_placement_does_not_spend_or_attach_the_glue_charge() -> void:
	# MatchPlacement: a delivered gift block takes no charge (OQ1: gift blocks never fuse).
	assert_true(Match.grant_glue_drops(0, 2))
	assert_true(Match.debug_queue_special(0, &"bomb"))
	Match._gifts.activate_next_special(0)
	assert_eq(Match.held_special(0), &"bomb")
	assert_eq(_place(), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 2, "a gift placement keeps the glue charge")
	var placed: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	for child: Node in placed.get_children():
		assert_false(child is GlueDrops, "a gift block is never glue-charged")


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


func test_valid_relocated_auto_drop_spends_a_charge() -> void:
	assert_true(Match.grant_glue_drops(0, 2))
	var far: Vector3 = _field.to_global(Vector3(5000.0, 5.0, 5000.0))
	assert_eq(_place(true, far), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 1)
	var placed: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	assert_not_null(placed)
	var has_binder: bool = false
	for child: Node in placed.get_children():
		has_binder = has_binder or child is GlueDrops
	assert_true(has_binder)


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


func test_elimination_clears_the_slots_glue_charges_and_publishes() -> void:
	# an eliminated slot keeps no stale charges.
	assert_true(Match.grant_glue_drops(0, 3))
	assert_true(Match.grant_glue_drops(1, 4))
	var seen: Array = []
	var on_change: Callable = func(slot_id: int, charges: int, _rev: int) -> void: seen.append([slot_id, charges])
	Events.glue_charges_changed.connect(on_change)
	Events.player_eliminated.emit(0, Match.team_of(0))
	Events.glue_charges_changed.disconnect(on_change)
	assert_eq(Match.glue_drops_left(0), 0)
	assert_eq(Match.glue_drops_left(1), 4)
	assert_eq(seen, [[0, 0]])


# --- bonds that hold ---

const TILT_CYCLE_S: float = 10.0
const TILT_FLIP_S: float = 2.0
const TILT_KICK: float = 0.35
const DROP_AT_S: float = 4.0
## Drop height above the pair. The glue shock threshold (4 m/s per tick) is tuned to an L4 landing
## speed sqrt(2 * g * h); the base gravity went 1.4 -> 1.75 (x1.25), so the former 3.0 m
## becomes 3.0 * 1.4 / 1.75 = 2.4 m to keep the same impact speed. Real placements release from
## hover height (0.3 m), far gentler than this stress case.
const DROP_HEIGHT_M: float = 2.4
const MAX_DRIFT_M: float = 0.5
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


func _pair_gap(a: Block, b: Block) -> float:
	return (b.global_position - a.global_position).length()


func test_fused_pair_survives_tilt_cycle_and_a_drop_onto_it() -> void:
	var pair: Array[Block] = await _glued_pair()
	var a: Block = pair[0]
	var b: Block = pair[1]
	var rest_gap: float = _pair_gap(a, b)
	_field.set_tilt_enabled(true)
	var dropped: bool = false
	var frames: int = int(TILT_CYCLE_S * 60.0)
	for i: int in range(frames):
		var t: float = float(i) / 60.0
		if i % int(TILT_FLIP_S * 60.0) == 0:
			var sign_dir: float = 1.0 if (i / int(TILT_FLIP_S * 60.0)) % 2 == 0 else -1.0
			_field.apply_tilt_impulse(Vector2(sign_dir, 0.0), TILT_KICK)
		if not dropped and t >= DROP_AT_S:
			dropped = true
			var mid: Vector3 = (a.global_position + b.global_position) * 0.5
			_real_block("L4", 1, mid + Vector3(0.0, DROP_HEIGHT_M, 0.0))
		await get_tree().physics_frame
	assert_true(_fused(a, b), "fusion must survive a 10 s tilt cycle and a placement drop")
	assert_lt(absf(_pair_gap(a, b) - rest_gap), MAX_DRIFT_M, "pair must not drift apart")


const SIDE_KICK_IMPULSE: float = 10.0
const WINDOW_SETTLE_FRAMES: int = 20
const MOVED_MIN_M: float = 0.02
## Gap between the base and its side neighbour (they touch); the charged block overhangs the other side.
const NEIGHBOUR_X_M: float = 1.0
const OVERHANG_X_M: float = -0.3
const KICK_SETTLE_FRAMES: int = 60


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


func test_fused_pair_survives_a_sideways_kick() -> void:
	var pair: Array[Block] = await _glued_pair()
	for _i: int in range(WINDOW_SETTLE_FRAMES):
		await get_tree().physics_frame
	assert_false(_carrier_of(pair[0]).is_disc_anchored(), "precondition: a free body, not pinned to the disc")
	var before: Vector3 = _carrier_of(pair[0]).global_position
	_carrier_of(pair[0]).apply_central_impulse(Vector3(0.0, 0.0, SIDE_KICK_IMPULSE))
	for _i: int in range(KICK_SETTLE_FRAMES):
		await get_tree().physics_frame
	assert_true(_fused(pair[0], pair[1]), "a fused body is rigid")
	assert_gt(_carrier_of(pair[0]).global_position.distance_to(before), MOVED_MIN_M, "the kick moves the free body")


const GUST_ACCEL_MPS2: float = 5.0
const GUST_FRAMES: int = 180
const GUST_FIELD_MARGIN: float = 1.0


func test_fused_pair_survives_a_sustained_wind_gust() -> void:
	var pair: Array[Block] = await _glued_pair()
	var carrier: FusedBody = _carrier_of(pair[0])
	for _i: int in range(WINDOW_SETTLE_FRAMES):
		await get_tree().physics_frame
	assert_false(carrier.is_disc_anchored(), "precondition: a free body, not pinned to the disc")
	for _i: int in range(GUST_FRAMES):
		carrier.apply_central_force(Vector3(0.0, 0.0, GUST_ACCEL_MPS2 * GUST_FIELD_MARGIN * carrier.mass))
		await get_tree().physics_frame
	assert_true(_fused(pair[0], pair[1]), "a sustained gust cannot split a fused body")


func test_charged_drop_on_a_disc_resting_block_is_not_disc_anchored() -> void:
	var pair: Array[Block] = await _glued_pair()
	for _i: int in range(WINDOW_SETTLE_FRAMES):
		await get_tree().physics_frame
	assert_true(_fused(pair[0], pair[1]))
	assert_false(_carrier_of(pair[0]).is_disc_anchored(), "the partner's disc contact must not anchor the group")


func test_charged_drop_does_not_fuse_the_base_neighbour() -> void:
	var rest_y: float = _field.surface_y() + 0.6
	var base: Block = _real_block("cube", 1, _field.to_global(Vector3(0.0, rest_y, 0.0)))
	var side: Block = _real_block("cube", 1, _field.to_global(Vector3(NEIGHBOUR_X_M, rest_y, 0.0)))
	for _i: int in range(40):
		await get_tree().physics_frame
	var charged: Block = _real_block("cube", 0, _field.to_global(Vector3(OVERHANG_X_M, rest_y + 1.05, 0.0)))
	var glue: GlueDrops = GlueDrops.new()
	charged.add_child(glue)
	glue.bind(charged, _tuning)
	for _i: int in range(WINDOW_SETTLE_FRAMES * 3):
		await get_tree().physics_frame
	assert_true(_fused(charged, base), "the block it landed on is fused")
	assert_false(_fused(charged, side), "a neighbour of the base is not touched by the charged block")
	assert_false(_carrier_of(charged).is_disc_anchored(), "the base's disc contact does not anchor the group")


func _bean_def() -> SpecialDef:
	return load("res://config/gifts/specials/jumping_bean.tres") as SpecialDef


func test_bean_hop_needs_no_joint_release() -> void:
	var bean: Block = _bare_block(0, _field.to_global(Vector3(0.0, 0.2, 0.0)))
	bean.gravity_scale = 1.0
	var effect: JumpingBeanEffect = (_bean_def().effect as JumpingBeanEffect)
	effect._kick(bean)
	await get_tree().process_frame
	assert_gt(bean.linear_velocity.y, 1.0, "the bean actually leaves the ground")


func test_jumping_bean_drop_keeps_the_glue_charge() -> void:
	assert_true(Match.grant_glue_drops(0, 3))
	assert_true(Match.debug_queue_special(0, &"jumping_bean"))
	Match._gifts.activate_next_special(0)
	assert_eq(Match.held_special(0), &"jumping_bean")
	assert_eq(_place(), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 3, "a bean takes no glue charge")
	var placed: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	for child: Node in placed.get_children():
		assert_false(child is GlueDrops, "the bean is never glue-fused")
