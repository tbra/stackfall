extends GutTest
## A client's Bomb blink: a dropped bomb blinks from its replicated spawn as before; a thrown one
## stops at the host's "thrown" event and starts at the host's "landed" event
## (MatchWireEvents.SPECIAL_LAUNCH_STATE), driven through the client's net_match_event entry point.

const MatchNetScript := preload("res://net/MatchNet.gd")
const LOCAL_SLOT: int = 1
const THROWN_NET_ID: int = 41
const DROPPED_NET_ID: int = 42

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _net: MatchNetScript


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map_def.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map_def)
	config.player_count = 2
	Match.start_match(config)
	_net = MatchNetScript.new()
	_net.set_process(false)
	add_child_autofree(_net)
	Match._net_provider = FakeNet.client(LOCAL_SLOT)
	_net.bind_ports(FakeSessionPort.new(Match._net_provider), MatchHostPort.new(Match), MatchReplicaPort.new(Match))


func after_each() -> void:
	_net = null
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()


## A frozen replica bomb the way ClientBlockMirror builds it (blink starts at its spawn).
func _replica_bomb(net_id: int) -> Block:
	var shape: BlockShape = BlockShape.load_all_shapes()[0]
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(shape, tuning, 0)
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	block.freeze = true
	_blocks_root.add_child(block)
	BlockFactory.apply_gift_visual(block, shape, tuning, &"bomb")
	_registry.bind_net_id(block, net_id)
	return block


func _blinking(block: Block) -> bool:
	return block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))) != null


func test_thrown_bomb_blink_stops_at_the_throw_and_starts_at_the_landing() -> void:
	var block: Block = _replica_bomb(THROWN_NET_ID)
	_net.net_match_event(MatchWireEvents.SPECIAL_LAUNCH_STATE, [THROWN_NET_ID, false])
	await get_tree().process_frame
	assert_false(_blinking(block), "no blink in flight")
	_net.net_match_event(MatchWireEvents.SPECIAL_LAUNCH_STATE, [THROWN_NET_ID, true])
	assert_true(_blinking(block), "the blink starts at the replicated landing")


func test_dropped_bomb_blink_is_unchanged() -> void:
	var block: Block = _replica_bomb(DROPPED_NET_ID)
	await get_tree().process_frame
	assert_true(_blinking(block), "a dropped bomb blinks from its spawn")


func test_launch_state_for_an_unknown_block_is_refused() -> void:
	watch_signals(Events)
	_net.net_match_event(MatchWireEvents.SPECIAL_LAUNCH_STATE, [999, true])
	assert_signal_not_emitted(Events, "special_launch_state")
