extends GutTest
## The host's glue coat sends (BLOCK_GLUED) through MatchEventMirror's broadcast seam.

var _broadcast: Array[Array] = []
var _tuning: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")
var _blocks_root: Node3D
var _linked: Array[Array] = []


func before_each() -> void:
	_broadcast.clear()
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)


func after_each() -> void:
	for pair: Array in _linked:
		if Events.is_connected(pair[0], pair[1]):
			Events.disconnect(pair[0], pair[1])
	_linked.clear()


func _mirror(host: bool) -> MatchEventMirror:
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return true
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(_peer_id: int, _method: StringName, _args: Array) -> bool: return true
	seams.broadcast = func(method: StringName, args: Array) -> void: _broadcast.append([method, args])
	var fake: FakeNet = FakeNet.host({}, [0]) if host else FakeNet.client(1)
	var mirror: MatchEventMirror = MatchEventMirror.new(seams)
	mirror.bind_ports(FakeSessionPort.new(fake), MatchHostPort.new(Match))
	return mirror


func _block(net_id: int) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, load("res://config/physics/physics_tuning.tres"), 1, Color.WHITE)
	_blocks_root.add_child(block)
	block.net_id = net_id
	return block


## The BLOCK_GLUED payloads sent, in order.
func _glued() -> Array:
	var found: Array = []
	for message: Array in _broadcast:
		assert_eq(message[0], &"net_match_event")
		var body: Array = message[1] as Array
		if StringName(body[0]) == MatchWireEvents.BLOCK_GLUED:
			found.append(body[1])
	return found


func _link(signal_name: StringName, handler: Callable) -> void:
	Events.connect(signal_name, handler)
	_linked.append([signal_name, handler])


func test_fuse_sends_glued_true_for_each_member() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	var a: Block = _block(301)
	var b: Block = _block(302)
	mirror.on_blocks_fused(null, [a, b])
	assert_eq(_glued(), [[301, true], [302, true]])
	assert_eq(mirror.glued_ids(), [301, 302])
	assert_true(HoneyCoat.is_coated(a))
	assert_true(HoneyCoat.is_coated(b))


func test_fuse_skips_members_without_a_wire_id() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_blocks_fused(null, [_block(Quantize.NET_ID_NONE), _block(303)])
	assert_eq(_glued(), [[303, true]])


func test_refuse_of_an_already_coated_member_sends_nothing_more() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	var a: Block = _block(304)
	mirror.on_blocks_fused(null, [a])
	mirror.on_blocks_fused(null, [a, _block(305)])
	assert_eq(_glued(), [[304, true], [305, true]])


func test_released_survivor_sends_glued_false() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	var a: Block = _block(311)
	var b: Block = _block(312)
	mirror.on_blocks_fused(null, [a, b])
	_broadcast.clear()
	mirror.on_fused_member_released(b)
	assert_eq(_glued(), [[312, false]])
	assert_eq(mirror.glued_ids(), [311])
	assert_false(HoneyCoat.is_coated(b))


func test_release_of_a_block_never_glued_sends_nothing() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_fused_member_released(_block(313))
	assert_eq(_glued(), [])


func test_forgotten_block_sends_no_uncoat() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_blocks_fused(null, [_block(321), _block(322)])
	mirror.forget_glued(321)
	_broadcast.clear()
	mirror.on_fused_member_released(_block(321))
	assert_eq(_glued(), [])
	assert_eq(mirror.glued_ids(), [322])


func test_charged_drop_sends_glued_true() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	var a: Block = _block(331)
	mirror.on_glue_drop_charged(a)
	assert_eq(_glued(), [[331, true]])
	assert_eq(mirror.glued_ids(), [331])
	assert_true(HoneyCoat.is_coated(a))


func test_charged_drop_then_fuse_does_not_resend_the_coat() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	var a: Block = _block(332)
	mirror.on_glue_drop_charged(a)
	mirror.on_blocks_fused(null, [a, _block(333)])
	assert_eq(_glued(), [[332, true], [333, true]])


func test_reset_glue_clears_the_set() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_glue_drop_charged(_block(341))
	mirror.on_blocks_fused(null, [_block(342)])
	mirror.reset_glue()
	assert_eq(mirror.glued_ids(), [])


func test_non_host_sends_nothing_and_tracks_nothing() -> void:
	var mirror: MatchEventMirror = _mirror(false)
	var a: Block = _block(351)
	mirror.on_blocks_fused(null, [a, _block(352)])
	mirror.on_glue_drop_charged(_block(353))
	mirror.on_fused_member_released(a)
	assert_eq(_broadcast.size(), 0)
	assert_eq(mirror.glued_ids(), [])
	assert_false(HoneyCoat.is_coated(a))


func test_real_fusion_and_collapse_send_the_coat_events() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	_link(&"blocks_fused", mirror.on_blocks_fused)
	_link(&"fused_member_released", mirror.on_fused_member_released)
	var a: Block = _block(361)
	var b: Block = _block(362)
	var carrier: FusedBody = GlueFusion.fuse(a, b, _tuning)
	assert_not_null(carrier)
	assert_eq(_glued(), [[361, true], [362, true]])
	carrier.remove_member(a, &"hole")
	await get_tree().process_frame
	assert_eq(_glued().slice(2), [[362, false]], "survivor uncoated, the removed member is not")
