extends "res://tests/unit/match/match_world_test.gd"
## (1pi.133 = A) and 1pi.135: a held throwable gift is thrown
## along the player's last known aim at timer expiry, exactly like a manual release; bots pick
## release points for the map's throw range. Fixture family of test_gift_throw.gd.

const MatchNetScript := preload("res://net/MatchNet.gd")
const REMOTE_PEER: int = 2
const REMOTE_SLOT: int = 1
const AIM: Vector3 = Vector3(1.0, 0.2, 0.0)

var _net: MatchNetScript


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _make_def(id: StringName, mode: GiftThrow.Mode) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.throwable = mode == GiftThrow.Mode.THROW
	def.aimed_launch = mode == GiftThrow.Mode.AIMED
	def.arm_delay = 999.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	if mode == GiftThrow.Mode.AIMED:
		def.effect = RocketEffect.new()
	return def


func _start_with(id: StringName, mode: GiftThrow.Mode, slot_id: int = 0) -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	_hold(id, mode, slot_id)


func _hold(id: StringName, mode: GiftThrow.Mode, slot_id: int = 0) -> void:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = id
	Match._feed._held_is_gift[slot_id] = true
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[id] = _make_def(id, mode)


func _expire(slot_id: int = 0, origin: Vector3 = Vector3.INF) -> StringName:
	var where: Vector3 = _home_world_position(slot_id) if origin == Vector3.INF else origin
	return Match.request_place(slot_id, where, 0, Quaternion.IDENTITY, true, Match.feed_seq(slot_id))


func _tuning() -> SpecialTuning:
	return Match._placement._special_tuning


func _scaled_throw(aim: Vector3) -> Vector3:
	return GiftAim.throw_velocity(aim, _tuning(), GiftAim.range_scale(_tiny_map.field_radius, _tuning()))


# --- host: expiry == manual release -----------------------------------------------

func test_expiry_throws_a_held_throwable_gift_along_the_last_aim() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var seq: int = Match.feed_seq(0)
	Match.note_aim(0, AIM)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(_scaled_throw(AIM)), "%s" % block.linear_velocity)
	assert_eq(Match.feed_seq(0), seq + 1, "the held gift was consumed exactly once")
	assert_eq(_blocks_root.get_child_count(), 1)


# --- fallbacks --------------------------------------------------------------------

func test_a_non_throwable_special_follows_its_manual_release_path() -> void:
	_start_with(&"gift_anvil", GiftThrow.Mode.NONE)
	Match.note_aim(0, AIM)
	var seq: int = Match.feed_seq(0)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_eq(block.linear_velocity, Vector3.ZERO, "dropped in place, never thrown")
	assert_eq(Match.feed_seq(0), seq + 1)


func test_a_stale_feed_seq_expiry_is_refused_before_any_throw() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	Match.note_aim(0, AIM)
	var stale: int = Match.feed_seq(0) + 5
	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, true, stale)
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_blocks_root.get_child_count(), 0)


# --- wire: remote client's held gift at expiry --------------------------------------

func _make_host_net() -> MatchNetScript:
	var peer_slots: Dictionary = {1: 0, REMOTE_PEER: REMOTE_SLOT}
	var fake: FakeNet = FakeNet.host(peer_slots, [0])
	fake.slots_by_peer = peer_slots
	Match.set_net_provider(fake)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(fake, Match)
	_net = node
	return node


func test_a_remote_clients_held_gift_is_thrown_at_expiry_from_its_cursor_aim() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW, REMOTE_SLOT)
	var where: Vector3 = _home_world_position(REMOTE_SLOT)
	net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, where, 0, Quaternion.IDENTITY, AIM)
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	net._on_feed_timer_expired(REMOTE_SLOT)
	assert_eq(Match.feed_seq(REMOTE_SLOT), seq + 1)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(_scaled_throw(AIM)), "thrown, not dropped")


func test_a_hostile_cursor_aim_is_not_trusted_and_the_expiry_still_drops() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW, REMOTE_SLOT)
	var where: Vector3 = _home_world_position(REMOTE_SLOT)
	net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, where, 0, Quaternion.IDENTITY, Vector3(INF, 0.0, 9999.0))
	net._on_feed_timer_expired(REMOTE_SLOT)
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq((_blocks_root.get_child(0) as Block).linear_velocity, Vector3.ZERO)


func test_another_peers_cursor_cannot_set_this_slots_aim() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW, REMOTE_SLOT)
	net._handle_cursor_update(REMOTE_PEER, 0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM)
	assert_eq(Match.noted_aim(0), Vector3.ZERO, "slot/peer mismatch is dropped before the aim is read")


# --- 1pi.135: clamp and bot range -----------------------------------------------------
