extends GutTest
## Glue activation and per-slot future-drop charge state.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	Match.start_match(_config())


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	return config


func _block(slot_id: int, position: Vector3) -> Block:
	var block: Block = Block.new()
	block.owner_slot = slot_id
	block.gravity_scale = 0.0
	block.mass = 1.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	block.add_child(collision)
	_blocks_root.add_child(block)
	block.global_position = position
	return block


func test_impact_activates_charges_without_bonding_or_spending_one() -> void:
	var block: Block = _block(0, Vector3.ZERO)
	_block(0, Vector3(1.0, 0.0, 0.0))
	var effect: GlueEffect = GlueEffect.new()
	var def: SpecialDef = SpecialDef.new()
	def.id = &"glue"
	def.effect = effect
	def.arm_delay = 0.0
	def.arm_impulse = 1.0
	def.fuse_timeout_s = 10.0
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	block.linear_velocity = Vector3(5.0, 0.0, 0.0)
	behavior.bind(block, def, null)
	behavior.advance(0.01)
	block.linear_velocity = Vector3.ZERO
	behavior.advance(0.01)
	assert_true(behavior.is_triggered(), "armed impact activates Glue")
	assert_eq(Match.glue_drops_left(0), 3, "activation block does not spend a charge")
	for child: Node in block.get_children():
		assert_false(child is GlueJoint, "activation no longer forms radius bonds")


func test_charges_are_per_slot_refresh_and_exhaust() -> void:
	assert_true(Match.grant_glue_drops(0, 3))
	assert_eq(Match.glue_drops_left(1), 0)
	assert_true(Match.consume_glue_drop(0))
	assert_eq(Match.glue_drops_left(0), 2)
	assert_true(Match.grant_glue_drops(0, 3), "another activation refreshes")
	assert_eq(Match.glue_drops_left(0), 3)
	assert_true(Match.grant_glue_drops(1, 2))
	for _i: int in range(3):
		assert_true(Match.consume_glue_drop(0))
	assert_false(Match.consume_glue_drop(0), "exhausted charge cannot be consumed")
	assert_eq(Match.glue_drops_left(1), 2, "other slot remains independent")


func test_mutation_is_host_only_and_slot_bounds_checked() -> void:
	assert_false(Match.grant_glue_drops(-1, 3))
	assert_false(Match.grant_glue_drops(2, 3))
	assert_false(Match.grant_glue_drops(0, 0))
	assert_false(Match.consume_glue_drop(2))
	assert_true(Match.grant_glue_drops(0, 3))
	Match.set_net_provider(FakeNet.client(0))
	assert_false(Match.grant_glue_drops(0, 4))
	assert_false(Match.consume_glue_drop(0))
	assert_eq(Match.glue_drops_left(0), 3)


func test_match_reset_clears_charges() -> void:
	assert_true(Match.grant_glue_drops(0, 3))
	Match.abort_match()
	Match.start_match(_config())
	assert_eq(Match.glue_drops_left(0), 0)


func test_glue_resource_has_three_drop_default() -> void:
	var def: SpecialDef = load("res://config/specials/glue.tres") as SpecialDef
	assert_eq(def.id, &"glue")
	assert_true(def.effect is GlueEffect)
	assert_eq((def.effect as GlueEffect).drop_charges, 3)


## GlueJoint remains the contact/break helper for the later placement package.
func _make_stress_joint() -> Array[Node]:
	var body_a: RigidBody3D = RigidBody3D.new()
	var body_b: RigidBody3D = RigidBody3D.new()
	_blocks_root.add_child(body_a)
	_blocks_root.add_child(body_b)
	var inner: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	var wrapper: GlueJoint = GlueJoint.new()
	wrapper.add_child(inner)
	_blocks_root.add_child(wrapper)
	wrapper.bind(inner, body_a, body_b, 40.0)
	return [wrapper, inner]


func test_glue_joint_breaks_above_threshold() -> void:
	var nodes: Array[Node] = _make_stress_joint()
	var wrapper: GlueJoint = nodes[0] as GlueJoint
	var inner: Generic6DOFJoint3D = nodes[1] as Generic6DOFJoint3D
	wrapper.apply_stress_sample(41.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(wrapper))
	assert_false(is_instance_valid(inner))


func test_glue_joint_keeps_below_threshold() -> void:
	var nodes: Array[Node] = _make_stress_joint()
	var wrapper: GlueJoint = nodes[0] as GlueJoint
	var inner: Generic6DOFJoint3D = nodes[1] as Generic6DOFJoint3D
	wrapper.apply_stress_sample(39.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(wrapper))
	assert_true(is_instance_valid(inner))
