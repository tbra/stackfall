extends GutTest
## the block-release cue (Sfx EVENT_DROP, Events.block_placed) sounds only for a
## block the local human seat dropped. The host sees every slot's placement (bots, remote clients)
## and a client sees every replicated spawn; none of those may play the local player's cue.

var _tiny_map: MapDef
var _loopback: LoopbackSession


func before_each() -> void:
	_loopback = LoopbackSession.new(self)
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 4
	config.ai_count = 2
	Match.start_match(config)


func after_each() -> void:
	await _loopback.end()
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _block(slot: int) -> BlockBody:
	var body: BlockBody = BlockBody.new()
	body.owner_slot = slot
	add_child_autofree(body)
	return body


## True when dropping `block` sounds a cue through the ordinary block_placed signal.
func _drop_sounds(block: BlockBody) -> bool:
	SfxChildren.stop_all()
	Events.block_placed.emit(block, &"shape")
	var sounded: bool = SfxChildren.any_playing()
	SfxChildren.stop_all()
	return sounded


func test_host_hears_only_its_own_drop_not_bots_or_clients() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "", false), OK)
	assert_true(_drop_sounds(_block(0)), "the host's own seat")
	assert_false(_drop_sounds(_block(1)), "a remote client's seat")
	assert_false(_drop_sounds(_block(2)), "a bot seat")
	assert_false(_drop_sounds(_block(3)), "a bot seat")


func test_client_hears_only_its_own_drop() -> void:
	assert_true(await _loopback.join_net_as_client(), "fixture: the Net autoload is a seated client")
	assert_eq(Net.local_slot(), 1)
	assert_true(_drop_sounds(_block(1)), "the client's own seat")
	assert_false(_drop_sounds(_block(0)), "the host's seat")
	assert_false(_drop_sounds(_block(2)), "a bot seat replicated from the host")
	# a null body cannot go through the typed block_placed signal, so only the unowned body is covered
	assert_false(_drop_sounds(_block(-1)), "an unowned body")
