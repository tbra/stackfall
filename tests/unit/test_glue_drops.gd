extends GutTest
## Host-only Glue charges attach contact bonding to accepted future drops.

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _tuning: GlueDropTuning = preload("res://config/glue_drop_tuning.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.sandbox = true
	config.gifts_enabled = false
	config.rng_seed = 5251
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


func _bonds(block: Block) -> Array[GlueJoint]:
	var result: Array[GlueJoint] = []
	for child: Node in block.get_children():
		if child is GlueJoint:
			result.append(child as GlueJoint)
	return result


func _home() -> Vector3:
	var point: Vector2 = Match.slot(0).home_position
	return _field.to_global(Vector3(point.x, 5.0, point.y))


func _place(auto_drop: bool = false, origin: Vector3 = Vector3.INF) -> StringName:
	var chosen: Vector3 = _home() if origin == Vector3.INF else origin
	return Match.request_place(0, chosen, 0, Quaternion.IDENTITY, auto_drop, Match.feed_seq(0))


func test_bonding_uses_contact_targets_and_deduplicates_both_directions() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var b: Block = _bare_block(1, Vector3(1.0, 5.0, 0.0))
	var glue_a: GlueDrops = GlueDrops.new()
	a.add_child(glue_a)
	glue_a.bind(a, _tuning)
	assert_true(a.contact_monitor)
	assert_gte(a.max_contacts_reported, _tuning.max_contacts_reported)
	assert_true(glue_a.try_bond(b), "a contacted enemy block can be fused")
	assert_eq(_bonds(a).size(), 1)
	assert_false(glue_a.try_bond(b), "same contact cannot create a second joint")
	var glue_b: GlueDrops = GlueDrops.new()
	b.add_child(glue_b)
	glue_b.bind(b, _tuning)
	assert_false(glue_b.try_bond(a), "reverse charged contact shares the existing pair")
	assert_true(glue_a.try_bond(_field), "the disc is a valid physics-body partner")
	assert_false(glue_a.try_bond(_field))
	assert_eq(_bonds(a).size(), 2)
	var unrelated: Node3D = Node3D.new()
	assert_false(glue_a.try_bond(unrelated), "unrelated nodes cannot bond")
	unrelated.free()


func test_real_physics_contact_forms_a_bond() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	_bare_block(1, Vector3(0.5, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, _tuning)
	for _i: int in range(4):
		await get_tree().physics_frame
	assert_eq(_bonds(a).size(), 1, "contact monitor bonds the real collision")


func test_real_disc_contact_forms_a_bond() -> void:
	var block: Block = _bare_block(0, _field.to_global(Vector3(0.0, 0.2, 0.0)))
	var glue: GlueDrops = GlueDrops.new()
	block.add_child(glue)
	glue.bind(block, _tuning)
	for _i: int in range(4):
		await get_tree().physics_frame
	var bonds: Array[GlueJoint] = _bonds(block)
	assert_eq(bonds.size(), 1, "the disc collider must be reported as a contact")
	if not bonds.is_empty():
		assert_true(bonds[0].bodies_match(block, _field))


func test_joint_constrains_a_falling_partner() -> void:
	var anchor: Block = _bare_block(0, Vector3(10.0, 10.0, 0.0))
	anchor.freeze = true
	var partner: Block = _bare_block(1, Vector3(10.0, 10.6, 0.0))
	partner.gravity_scale = 1.0
	var free_block: Block = _bare_block(1, Vector3(13.0, 10.6, 0.0))
	free_block.gravity_scale = 1.0
	var tuning: GlueDropTuning = _tuning.duplicate() as GlueDropTuning
	tuning.break_force = 10000.0
	var glue: GlueDrops = GlueDrops.new()
	anchor.add_child(glue)
	glue.bind(anchor, tuning)
	assert_true(glue.try_bond(partner))
	for _i: int in range(45):
		await get_tree().physics_frame
	assert_lt(partner.global_position.distance_to(anchor.global_position), 1.5)
	assert_gt(anchor.global_position.y - free_block.global_position.y, 1.0)


func test_bond_cleans_up_when_partner_despawns() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var b: Block = _bare_block(1, Vector3(1.0, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, _tuning)
	assert_true(glue.try_bond(b))
	var joint: GlueJoint = _bonds(a)[0]
	b.free()
	joint.advance(0.1)
	await get_tree().process_frame
	assert_false(is_instance_valid(joint))


func test_bond_breaks_above_tuned_stress() -> void:
	var a: Block = _bare_block(0, Vector3(0.0, 5.0, 0.0))
	var b: Block = _bare_block(1, Vector3(1.0, 5.0, 0.0))
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, _tuning)
	assert_true(glue.try_bond(b))
	var joint: GlueJoint = _bonds(a)[0]
	joint.apply_stress_sample(_tuning.break_force + 1.0)
	await get_tree().process_frame
	assert_false(is_instance_valid(joint))


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
	# Bontago-sen.3: Glue is a modifier, so a claim grants 5 charges and the
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
	assert_true(Match.debug_queue_special(0, &"anvil"))
	assert_eq(_place(), PlacementRules.REASON_OK)
	assert_eq(Match.glue_drops_left(0), 1)
	assert_eq(Match.held_special(0), &"anvil")
	assert_eq(
		Match.request_throw(0, _home(), 0, Quaternion.IDENTITY, Vector3(0.0, 2.0, 0.0), Match.feed_seq(0)),
		PlacementRules.REASON_OK
	)
	assert_eq(Match.glue_drops_left(0), 1)


func test_elimination_clears_the_slots_glue_charges_and_publishes() -> void:
	# Bontago-sen.8: an eliminated slot keeps no stale charges.
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


# --- Bontago-1pi.85.13: bonds that hold (docs/GIFT_EFFECTS_PLAN.md section 5 F) ---

const TILT_CYCLE_S: float = 10.0
const TILT_FLIP_S: float = 2.0
const TILT_KICK: float = 0.35
const DROP_AT_S: float = 4.0
const MAX_DRIFT_M: float = 0.5
const BLAST_ZONE_Z: float = 2.0


func _real_block(shape_id: String, slot_id: int, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
	var physics: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, slot_id)
	_blocks_root.add_child(block)
	block.global_position = at
	return block


func _glued_pair() -> Array[Block]:
	var rest_y: float = _field.surface_y() + 0.6
	var a: Block = _real_block("cube", 0, _field.to_global(Vector3(0.0, rest_y, 0.0)))
	var b: Block = _real_block("cube", 1, _field.to_global(Vector3(1.0, rest_y, 0.0)))
	for _i: int in range(40):
		await get_tree().physics_frame
	var glue: GlueDrops = GlueDrops.new()
	a.add_child(glue)
	glue.bind(a, _tuning)
	assert_true(glue.try_bond(b))
	return [a, b]


func _pair_gap(a: Block, b: Block) -> float:
	return (b.global_position - a.global_position).length()


func test_glued_pair_survives_tilt_cycle_and_a_drop_onto_it() -> void:
	var pair: Array[Block] = await _glued_pair()
	var a: Block = pair[0]
	var b: Block = pair[1]
	var rest_gap: float = _pair_gap(a, b)
	var bond: GlueJoint = _bonds(a)[0]
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
			_real_block("L4", 1, mid + Vector3(0.0, 3.0, 0.0))
		await get_tree().physics_frame
	assert_true(is_instance_valid(bond), "bond must survive a 10 s tilt cycle and a placement drop")
	assert_lt(absf(_pair_gap(a, b) - rest_gap), MAX_DRIFT_M, "pair must not drift apart")


func test_glued_pair_breaks_under_a_two_metre_blast() -> void:
	var pair: Array[Block] = await _glued_pair()
	var a: Block = pair[0]
	var b: Block = pair[1]
	var bond: GlueJoint = _bonds(a)[0]
	var center: Vector3 = a.global_position + Vector3(-BLAST_ZONE_Z, 0.0, 0.0)
	var blast: ExplosionTuning = ExplosionTuning.new()
	var space: PhysicsDirectSpaceState3D = a.get_world_3d().direct_space_state
	ExplosionFx.blast(space, center, blast, [])
	for _i: int in range(30):
		await get_tree().physics_frame
	assert_false(is_instance_valid(bond), "a 2 m bomb blast must break the glue bond")
