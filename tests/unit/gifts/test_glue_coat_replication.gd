extends GutTest
## placed glued blocks wear the honey coat on host and clients.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _net: MatchNetScript
var _tiny_map: MapDef
var _tuning: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _make_net(client_mode: bool) -> MatchNetScript:
	var fake: FakeNet = FakeNet.client(1) if client_mode else FakeNet.host({}, [0, 1])
	Match._net_provider = fake
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(fake, Match)
	_net = node
	return node


func _start_playing() -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _block(net_id: int) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, load("res://config/physics/physics_tuning.tres"), 1, Match.slot(1).color)
	_blocks_root.add_child(block)
	Events.block_placed.emit(block, shape.id)
	_registry.bind_net_id(block, net_id)
	return block


## Fuses `a` (charged) with `b` through the real GlueFusion path.
func _glue(a: Block, b: Block) -> FusedBody:
	return GlueFusion.fuse(a, b, _tuning)


func _glued_events(messages: Array[Array]) -> Array:
	var found: Array = []
	for message: Array in messages:
		if message[0] == &"net_match_event" and StringName((message[1] as Array)[0]) == MatchNetScript.EVENT_BLOCK_GLUED:
			found.append((message[1] as Array)[1])
	return found


func test_host_coats_fused_pair_and_uncoats_the_survivor_when_a_member_is_removed() -> void:
	var net: MatchNetScript = _make_net(false)
	_start_playing()
	var a: Block = _block(201)
	var b: Block = _block(202)
	var carrier: FusedBody = _glue(a, b)
	assert_not_null(carrier)
	assert_true(HoneyCoat.is_coated(a))
	assert_true(HoneyCoat.is_coated(b))
	assert_eq(int(net.counters.replicated_event_counts.get(MatchNetScript.EVENT_BLOCK_GLUED, 0)), 2)
	var coat_mesh: MeshInstance3D = a.get_node("BlockMesh").get_node(HoneyCoat.COAT_NODE_NAME) as MeshInstance3D
	assert_not_null(coat_mesh.material_override)
	carrier.remove_member(a, &"hole")
	await get_tree().process_frame
	assert_false(HoneyCoat.is_coated(b), "survivor collapsed to a lone block -> coat removed")
	assert_eq(int(net.counters.replicated_event_counts.get(MatchNetScript.EVENT_BLOCK_GLUED, 0)), 3)
	assert_true(net._fused_ids.is_empty())


func test_client_mirror_applies_event_late_join_replay_and_removal() -> void:
	var host: MatchNetScript = _make_net(false)
	_start_playing()
	var a: Block = _block(231)
	var b: Block = _block(232)
	var bond: FusedBody = _glue(a, b)
	var replay: Array[Array] = host.build_world_replay()
	assert_eq(_glued_events(replay), [[231, true], [232, true]], "late joiners are told the current glued set")
	host.set_providers(null, null)
	host.free()
	# Client view of the same blocks: bare coat state, then the replayed events.
	HoneyCoat.set_coated(a, false)
	HoneyCoat.set_coated(b, false)
	var client: MatchNetScript = _make_net(true)
	for payload: Array in _glued_events(replay):
		client.net_match_event(MatchNetScript.EVENT_BLOCK_GLUED, payload)
	assert_true(HoneyCoat.is_coated(a))
	assert_true(HoneyCoat.is_coated(b))
	for bad: Array in [[999, true], [231], [231, 1], [-1, true]]:
		client.net_match_event(MatchNetScript.EVENT_BLOCK_GLUED, bad)
	client.net_match_event(MatchNetScript.EVENT_BLOCK_GLUED, [231, false])
	assert_false(HoneyCoat.is_coated(a))
	assert_true(HoneyCoat.is_coated(b))
	assert_not_null(bond)


## a charged drop is coated at spawn (before any bond), replicated,
## and replayed to late joiners; it uncoats only once a bond it formed ends.
func test_charged_drop_is_coated_at_spawn_and_replayed_to_late_joiners() -> void:
	var host: MatchNetScript = _make_net(false)
	_start_playing()
	var a: Block = _block(251)
	var drops: GlueDrops = GlueDrops.new()
	a.add_child(drops)
	drops.bind(a, _tuning)
	Events.glue_drop_charged.emit(a)
	assert_true(HoneyCoat.is_coated(a), "coated while still falling, no bond yet")
	assert_eq(int(host.counters.replicated_event_counts.get(MatchNetScript.EVENT_BLOCK_GLUED, 0)), 1)
	assert_eq(_glued_events(host.build_world_replay()), [[251, true]])
	var b: Block = _block(252)
	assert_true(drops.try_bond(b))
	assert_true(HoneyCoat.is_coated(a))
	assert_eq(_glued_events(host.build_world_replay()), [[251, true], [252, true]])
	var carrier: FusedBody = a.fused_carrier() as FusedBody
	carrier.remove_member(b, &"hole")
	await get_tree().process_frame
	assert_false(HoneyCoat.is_coated(a), "group ended -> survivor coat removed")
	assert_eq(_glued_events(host.build_world_replay()), [])
