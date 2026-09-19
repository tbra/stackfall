extends GutTest
## The host's validation of what arrives over the wire (spec 3.4: "The host
## checks every intent before acting on it"). These are the regression cases
## for three review findings against net/MatchNet.gd's remote boundary
## (Beads Bontago-mv0.1.4, .5, .6):
##
##   .4  a remote intent quoting a negative feed_seq slipped past Match's
##       "-1 means don't check" local sentinel and so past replay protection;
##   .5  a remote orientation index was handed straight to
##       BlockOrientations.get_basis(), which indexes a 24-entry array (-1
##       silently aliased entry 23; anything past the ends was a host-side
##       script error), on both the intent path and the cursor -> auto-drop path;
##   .6  a remote origin / free quaternion reached Match with no finite or
##       unit check, and request_place() preserved the supplied Y while
##       territory only validates X/Z.
##
## As in test_match_net.gd, these drive the **real** Match through MatchNet
## with a faked Net, so every assertion is about what actually happened to
## the block feed: a refused intent must leave the block count, the slot's
## feed_seq and intents_accepted untouched, and must be counted as refused so
## the debug overlay shows it.

const MatchNetScript := preload("res://net/MatchNet.gd")

## The peer ids _make_net() hands out: peer 1 is the listen-server host on
## slot 0, peer 2 a remote client on slot 1.
const HOST_PEER: int = 1
const REMOTE_PEER: int = 2
const REMOTE_SLOT: int = 1

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _net: MatchNetScript
var _fake_net: FakeNet
var _net_config: NetConfig = preload("res://config/net_config.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_field = autofree(Field.new())
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
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)


## A listen-server host (peer 1, slot 0) with one remote client (peer 2,
## slot 1), bound to the real Match. Same shape as test_match_net.gd's.
func _make_host_net() -> MatchNetScript:
	var peer_slots: Dictionary = {HOST_PEER: 0, REMOTE_PEER: REMOTE_SLOT}
	_fake_net = FakeNet.host(peer_slots, [0])
	_fake_net.slots_by_peer = peer_slots
	Match.set_net_provider(_fake_net)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	return node


func _config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = block_timer
	config.rng_seed = 4242
	return config


func _start_playing() -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


## A world position right on `slot_id`'s own home flag, where a single block
## always validates. `height` is the world Y the block's origin is asked for.
func _home_world_position(slot_id: int, height: float = 0.0) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, height, home.y))


func _block_count() -> int:
	return _blocks_root.get_child_count()


## The remote client (peer 2) sends an intent for its own slot.
func _remote_place(
	net: MatchNetScript, origin: Vector3, orientation_index: int, free_quat: Quaternion, feed_seq: int
) -> void:
	net._handle_place_intent(REMOTE_PEER, REMOTE_SLOT, origin, orientation_index, free_quat, feed_seq)


## The remote client (peer 2) sends a cursor update for its own slot, through
## the same host-side handler net_update_cursor() runs.
func _remote_cursor(net: MatchNetScript, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, origin, orientation_index, free_quat)


## Everything a refused remote intent must leave alone, plus the refusal
## itself being visible in the counters.
func _assert_nothing_was_spent(
	net: MatchNetScript, seq_before: int, blocks_before: int, refused_before: int, what: String
) -> void:
	assert_eq(_block_count(), blocks_before, "%s: no block may be spawned" % what)
	assert_eq(Match.feed_seq(REMOTE_SLOT), seq_before, "%s: the held block must not be consumed" % what)
	assert_eq(net.intents_accepted(REMOTE_SLOT), 0, "%s: nothing was accepted" % what)
	assert_eq(net.intents_refused(REMOTE_SLOT), refused_before + 1, "%s: the refusal is counted" % what)
	assert_eq(
		net.intents_accepted(REMOTE_SLOT) + net.intents_refused(REMOTE_SLOT),
		net.intents_sent(REMOTE_SLOT),
		"%s: accepted + refused must still equal sent" % what
	)


# --- .4  Negative remote feed_seq must not bypass replay protection ----------


func test_a_remote_intent_with_the_local_minus_one_sentinel_is_refused() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)

	_remote_place(net, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)

	_assert_nothing_was_spent(net, seq, 0, 0, "feed_seq -1 from the wire")


func test_every_negative_remote_feed_seq_is_refused() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var refused: int = 0

	for bad_seq: int in [-2, -7, -(1 << 40)]:
		_remote_place(net, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, bad_seq)
		_assert_nothing_was_spent(net, seq, 0, refused, "feed_seq %d from the wire" % bad_seq)
		refused += 1


func test_a_replayed_remote_intent_places_exactly_one_block() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var where: Vector3 = _home_world_position(REMOTE_SLOT)

	_remote_place(net, where, 0, Quaternion.IDENTITY, seq)
	_remote_place(net, where, 0, Quaternion.IDENTITY, seq)

	assert_eq(_block_count(), 1, "One held block, one spawned block, however often the intent arrives.")
	assert_eq(net.intents_accepted(REMOTE_SLOT), 1)
	assert_eq(net.intents_refused(REMOTE_SLOT), 1)
	assert_eq(Match.feed_seq(REMOTE_SLOT), seq + 1)


func test_after_a_refused_negative_seq_a_valid_seq_places_one_and_the_timer_still_auto_drops() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var where: Vector3 = _home_world_position(REMOTE_SLOT)

	_remote_place(net, where, 0, Quaternion.IDENTITY, -1)
	assert_eq(_block_count(), 0)
	_remote_place(net, where, 0, Quaternion.IDENTITY, Match.feed_seq(REMOTE_SLOT))
	assert_eq(_block_count(), 1, "A real sequence still places exactly one block.")
	assert_eq(net.intents_accepted(REMOTE_SLOT), 1)

	# The host's own timer path quotes Match.feed_seq() itself and must be
	# untouched by the wire-side rule.
	_remote_cursor(net, where, 0, Quaternion.IDENTITY)
	Events.feed_timer_expired.emit(REMOTE_SLOT)

	assert_eq(_block_count(), 2, "The host still auto-drops for the remote slot from its cursor.")
	assert_eq(net.auto_drops(REMOTE_SLOT), 1)
	assert_eq(
		Match.blocks_spawned(),
		net.intents_accepted(REMOTE_SLOT) + net.auto_drops(REMOTE_SLOT),
		"blocks_spawned must equal accepted intents plus auto-drops"
	)


func test_the_omitted_feed_seq_sentinel_still_works_for_trusted_local_callers() -> void:
	_make_host_net()
	_start_playing()

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OK, "M2 call sites omit feed_seq and must keep working.")
	assert_eq(_block_count(), 1)


# --- .5  Orientation index must be inside BlockOrientations' table ----------


func test_out_of_range_remote_orientations_are_refused_without_spending_a_block() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var refused: int = 0

	# -1 is the sneaky one: GDScript arrays accept negative indices, so
	# without a check it silently aliases entry 23 and places. -25 and 24 are
	# one past each end; 1 << 40 is what a 64-bit int on the wire allows.
	for bad_index: int in [-1, -25, BlockOrientations.ORIENTATION_COUNT, 1 << 40]:
		_remote_place(net, _home_world_position(REMOTE_SLOT), bad_index, Quaternion.IDENTITY, seq)
		_assert_nothing_was_spent(net, seq, 0, refused, "orientation %d from the wire" % bad_index)
		refused += 1


func test_every_valid_orientation_index_is_still_accepted_from_the_wire() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	for index: int in range(BlockOrientations.ORIENTATION_COUNT):
		_remote_place(net, _home_world_position(REMOTE_SLOT), index, Quaternion.IDENTITY, Match.feed_seq(REMOTE_SLOT))

	assert_eq(net.intents_accepted(REMOTE_SLOT), BlockOrientations.ORIENTATION_COUNT, "All 24 rotations place.")
	assert_eq(net.intents_refused(REMOTE_SLOT), 0)
	assert_eq(_block_count(), BlockOrientations.ORIENTATION_COUNT)


func test_a_cursor_with_an_out_of_range_orientation_is_dropped_and_auto_drop_still_lands() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var where: Vector3 = _home_world_position(REMOTE_SLOT)
	_remote_cursor(net, where, 3, Quaternion.IDENTITY)

	for bad_index: int in [-1, -25, BlockOrientations.ORIENTATION_COUNT, 1 << 40]:
		_remote_cursor(net, where, bad_index, Quaternion.IDENTITY)

	var cursor: Dictionary = net.cursor_for_slot(REMOTE_SLOT)
	assert_eq(cursor["orientation_index"], 3, "The last well-formed cursor is what the host keeps.")
	assert_eq(net.cursors_refused(REMOTE_SLOT), 4, "Every dropped cursor is counted for the overlay.")

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	assert_eq(_block_count(), 1, "The timer path never sees the malformed pose and still drops.")
	assert_eq(net.auto_drops(REMOTE_SLOT), 1)


func test_a_slot_whose_only_cursors_were_malformed_still_auto_drops_from_its_home() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	_remote_cursor(net, _home_world_position(REMOTE_SLOT), BlockOrientations.ORIENTATION_COUNT, Quaternion.IDENTITY)
	assert_true(net.cursor_for_slot(REMOTE_SLOT).is_empty(), "A malformed first cursor is not stored at all.")

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	assert_eq(_block_count(), 1, "With no stored cursor the host drops on the slot's home flag, as before.")
	assert_eq(net.auto_drops(REMOTE_SLOT), 1)


# --- .6  Origin, free quaternion and height ----------------------------------


func test_non_finite_remote_origins_are_refused() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var home: Vector3 = _home_world_position(REMOTE_SLOT)
	var refused: int = 0

	for bad_origin: Vector3 in [
		Vector3(NAN, home.y, home.z),
		Vector3(home.x, INF, home.z),
		Vector3(home.x, home.y, -INF),
		Vector3(NAN, NAN, NAN),
	]:
		_remote_place(net, bad_origin, 0, Quaternion.IDENTITY, seq)
		_assert_nothing_was_spent(net, seq, 0, refused, "origin %s from the wire" % bad_origin)
		refused += 1


func test_malformed_remote_quaternions_are_refused() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var refused: int = 0

	for bad_quat: Quaternion in [
		Quaternion(NAN, 0.0, 0.0, 1.0),
		Quaternion(0.0, 0.0, 0.0, 0.0),
		Quaternion(0.0, 0.0, 0.0, 2.0),
		Quaternion(1.0, 1.0, 1.0, 1.0),
		Quaternion(INF, 0.0, 0.0, 0.0),
	]:
		_remote_place(net, _home_world_position(REMOTE_SLOT), 0, bad_quat, seq)
		_assert_nothing_was_spent(net, seq, 0, refused, "quaternion %s from the wire" % bad_quat)
		refused += 1


func test_a_unit_free_rotation_from_the_wire_still_places() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	_remote_place(
		net, _home_world_position(REMOTE_SLOT), 5, Quaternion(Vector3.UP, 0.7).normalized(), Match.feed_seq(REMOTE_SLOT)
	)

	assert_eq(net.intents_accepted(REMOTE_SLOT), 1)
	assert_eq(_block_count(), 1)


func test_remote_heights_outside_the_replicable_band_are_refused() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var refused: int = 0

	# NetConfig.pos_min_y / pos_max_y bound the volume snapshots quantize
	# positions into; a body outside it could not be replicated to anyone.
	for bad_height: float in [
		_net_config.pos_max_y + 1.0,
		1.0e9,
		_net_config.pos_min_y - 1.0,
		-1.0e9,
	]:
		_remote_place(net, _home_world_position(REMOTE_SLOT, bad_height), 0, Quaternion.IDENTITY, seq)
		_assert_nothing_was_spent(net, seq, 0, refused, "height %f from the wire" % bad_height)
		refused += 1


func test_remote_heights_inside_the_band_still_place_at_the_requested_height() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var physics: PhysicsTuning = load("res://config/physics_tuning.tres")
	var heights: Array[float] = [physics.hover_height, _net_config.pos_max_y, _net_config.pos_min_y]

	for height: float in heights:
		_remote_place(net, _home_world_position(REMOTE_SLOT, height), 0, Quaternion.IDENTITY, Match.feed_seq(REMOTE_SLOT))

	assert_eq(net.intents_accepted(REMOTE_SLOT), heights.size(), "The normal hover and both band edges place.")
	assert_eq(net.intents_refused(REMOTE_SLOT), 0)
	assert_eq(_block_count(), heights.size())
	for i: int in range(heights.size()):
		var block: Block = _blocks_root.get_child(i) as Block
		assert_almost_eq(
			block.global_position.y, heights[i], 0.001, "request_place keeps the requested height (block %d)" % i
		)


func test_malformed_cursor_poses_are_dropped_and_the_last_good_cursor_survives() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	var good: Vector3 = _home_world_position(REMOTE_SLOT)
	_remote_cursor(net, good, 0, Quaternion.IDENTITY)
	watch_signals(Events)

	_remote_cursor(net, Vector3(NAN, 0.0, 0.0), 0, Quaternion.IDENTITY)
	_remote_cursor(net, Vector3(0.0, INF, 0.0), 0, Quaternion.IDENTITY)
	_remote_cursor(net, good, 0, Quaternion(0.0, 0.0, 0.0, 0.0))
	_remote_cursor(net, good, 0, Quaternion(0.0, 0.0, 0.0, 3.0))
	_remote_cursor(net, _home_world_position(REMOTE_SLOT, 1.0e9), 0, Quaternion.IDENTITY)
	_remote_cursor(net, _home_world_position(REMOTE_SLOT, _net_config.pos_min_y - 1.0), 0, Quaternion.IDENTITY)

	var cursor: Dictionary = net.cursor_for_slot(REMOTE_SLOT)
	assert_eq(cursor["origin"], good, "Only the well-formed cursor is stored.")
	assert_eq(net.cursors_refused(REMOTE_SLOT), 6)
	assert_signal_not_emitted(
		Events, "remote_cursor_updated", "A malformed cursor is never re-emitted (or rebroadcast) to anyone."
	)

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	assert_eq(_block_count(), 1, "Auto-drop fires from the last good cursor.")
	var block: Block = _blocks_root.get_child(0) as Block
	assert_almost_eq(block.global_position.x, good.x, 1.5)
	assert_almost_eq(block.global_position.z, good.z, 1.5)


func test_a_well_formed_remote_cursor_is_stored_and_re_emitted() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	watch_signals(Events)
	var where: Vector3 = _home_world_position(REMOTE_SLOT, 2.0)
	var quat: Quaternion = Quaternion(Vector3.RIGHT, 0.4).normalized()

	_remote_cursor(net, where, 7, quat)

	assert_signal_emitted_with_parameters(Events, "remote_cursor_updated", [REMOTE_SLOT, where, 7, quat])
	var cursor: Dictionary = net.cursor_for_slot(REMOTE_SLOT)
	assert_eq(cursor["origin"], where)
	assert_eq(cursor["orientation_index"], 7)
	assert_eq(net.cursors_refused(REMOTE_SLOT), 0)


func test_a_cursor_for_someone_elses_slot_is_still_ignored() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	# Peer 2 holds slot 1 but claims slot 0; and a peer with no slot at all.
	net._handle_cursor_update(REMOTE_PEER, 0, _home_world_position(0), 0, Quaternion.IDENTITY)
	net._handle_cursor_update(99, REMOTE_SLOT, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY)

	assert_true(net.cursor_for_slot(0).is_empty())
	assert_true(net.cursor_for_slot(REMOTE_SLOT).is_empty())
