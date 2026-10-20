extends GutTest
## The host's validation of what arrives over the wire (spec 2.6: "The host
## checks every intent before acting on it"). These are the regression cases
## for three review findings against the host's remote boundary
## (MatchIntentGateway):
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
## These drive the **real** Match through a real MatchIntentGateway (a FakeNet
## session and spy Seams), so every assertion is about what actually happened to
## the block feed: a refused intent must leave the block count and the slot's
## feed_seq untouched, and must be counted as refused (accepted + refused ==
## sent) so the debug overlay shows it.

## The peer ids the fake session hands out: peer 1 is the listen-server host on
## slot 0, peer 2 a remote client on slot 1.
const HOST_PEER: int = 1
const REMOTE_PEER: int = 2
const REMOTE_SLOT: int = 1
const FLOOD_FACTOR: int = 3
const FLOOD_TIME_S: float = 5.0
const GOOD_ORIENTATION: int = 3
const TIGHT_BURST: int = 2

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _fake_net: FakeNet
var _gateway: MatchIntentGateway
var _counters: NetCounters
var _net_config: NetConfig = preload("res://config/net/net_config.tres")
var _now_s: float = 0.0
## What the gateway pushed out through its Seams, and what reached the ghost.
var _replies: Array[Array] = []
var _broadcasts: int = 0
var _stored_cursors: Array[Dictionary] = []
var _ghost_updates: int = 0

## DECISION: see test_match_flow.gd's own `_tiny_map` comment.
## Same real Field/Match world built fresh in every one of this file's
## tests' before_each, same ~11 s round_medium.tres (45 m, ~6300 cells)
## collision build paid for nothing every time; same TinyMapMatchConfig seam.
var _tiny_map: MapDef


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
	if Events.remote_cursor_updated.is_connected(_on_ghost_update):
		Events.remote_cursor_updated.disconnect(_on_ghost_update)
	_gateway = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _on_ghost_update(_slot: int, _origin: Vector3, _index: int, _quat: Quaternion) -> void:
	_ghost_updates += 1


## A listen-server host (peer 1, slot 0) with one remote client (peer 2, slot 1), bound to the real
## Match through the gateway's real constructor.
func _make_gateway(config: NetConfig = _net_config) -> MatchIntentGateway:
	_fake_net = FakeNet.host({HOST_PEER: 0, REMOTE_PEER: REMOTE_SLOT}, [0])
	_counters = NetCounters.new()
	_now_s = 0.0
	_replies.clear()
	_broadcasts = 0
	_stored_cursors.clear()
	_ghost_updates = 0
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return true
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
		_replies.append([peer_id, method, args])
		return true
	seams.broadcast = func(_method: StringName, _args: Array) -> void: _broadcasts += 1
	seams.now_s = func() -> float: return _now_s
	seams.is_replay_pending = func(_peer_id: int) -> bool: return false
	seams.store_cursor = func(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
		_stored_cursors.append({
			"slot_id": slot_id, "origin": origin, "orientation_index": orientation_index, "free_quat": free_quat,
		})
	_gateway = MatchIntentGateway.new(_fake_net, Match, config, _counters, seams)
	assert_true(_gateway.is_valid(), "fixture: the gateway bound the fake session and the real Match")
	Events.remote_cursor_updated.connect(_on_ghost_update)
	return _gateway


func _config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first -- see test_match_flow.gd's own _tiny_map_config() doc
	# comment for why order matters here.
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
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
func _remote_place(origin: Vector3, orientation_index: int, free_quat: Quaternion, feed_seq: int) -> void:
	_gateway.handle_place(REMOTE_PEER, REMOTE_SLOT, origin, orientation_index, free_quat, feed_seq)


## The remote client (peer 2) sends a cursor update for its own slot.
func _remote_cursor(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	_gateway.handle_cursor(REMOTE_PEER, REMOTE_SLOT, origin, orientation_index, free_quat)


## Everything a refused remote intent must leave alone, plus the refusal
## itself being visible in the per-slot identity (accepted + refused == sent).
func _assert_nothing_was_spent(seq_before: int, refused_before: int, what: String) -> void:
	assert_eq(_block_count(), 0, "%s: no block may be spawned" % what)
	assert_eq(Match.feed_seq(REMOTE_SLOT), seq_before, "%s: the held block must not be consumed" % what)
	assert_eq(_counters.accepted_count(REMOTE_SLOT), 0, "%s: nothing was accepted" % what)
	assert_eq(_counters.refused_count(REMOTE_SLOT), refused_before + 1, "%s: the refusal is counted" % what)
	assert_eq(
		_counters.accepted_count(REMOTE_SLOT) + _counters.refused_count(REMOTE_SLOT),
		_counters.sent_count(REMOTE_SLOT),
		"%s: accepted + refused must still equal sent" % what
	)


# --- .4  Negative remote feed_seq must not bypass replay protection ----------


func test_a_remote_intent_with_the_local_minus_one_sentinel_is_refused() -> void:
	_make_gateway()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)

	_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)

	_assert_nothing_was_spent(seq, 0, "feed_seq -1 from the wire")


func test_every_negative_remote_feed_seq_is_refused() -> void:
	_make_gateway()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var refused: int = 0

	for bad_seq: int in [-2, -7, -(1 << 40)]:
		_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, bad_seq)
		_assert_nothing_was_spent(seq, refused, "feed_seq %d from the wire" % bad_seq)
		refused += 1


func test_a_replayed_remote_intent_places_exactly_one_block() -> void:
	_make_gateway()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var where: Vector3 = _home_world_position(REMOTE_SLOT)

	_remote_place(where, 0, Quaternion.IDENTITY, seq)
	_remote_place(where, 0, Quaternion.IDENTITY, seq)

	assert_eq(_block_count(), 1, "One held block, one spawned block, however often the intent arrives.")
	assert_eq(_counters.accepted_count(REMOTE_SLOT), 1)
	assert_eq(_counters.refused_count(REMOTE_SLOT), 1)
	assert_eq(Match.feed_seq(REMOTE_SLOT), seq + 1)


# --- .5  Orientation index must be inside BlockOrientations' table ----------


func test_out_of_range_remote_orientations_are_refused_without_spending_a_block() -> void:
	_make_gateway()
	_start_playing()
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	var refused: int = 0

	# -1 is the sneaky one: GDScript arrays accept negative indices, so
	# without a check it silently aliases entry 23 and places. -25 and 24 are
	# one past each end; 1 << 40 is what a 64-bit int on the wire allows.
	for bad_index: int in [-1, -25, BlockOrientations.ORIENTATION_COUNT, 1 << 40]:
		_remote_place(_home_world_position(REMOTE_SLOT), bad_index, Quaternion.IDENTITY, seq)
		_assert_nothing_was_spent(seq, refused, "orientation %d from the wire" % bad_index)
		refused += 1


func test_a_cursor_with_an_out_of_range_orientation_is_dropped_and_auto_drop_still_lands() -> void:
	_make_gateway()
	_start_playing()
	var where: Vector3 = _home_world_position(REMOTE_SLOT)
	_remote_cursor(where, GOOD_ORIENTATION, Quaternion.IDENTITY)

	for bad_index: int in [-1, -25, BlockOrientations.ORIENTATION_COUNT, 1 << 40]:
		_remote_cursor(where, bad_index, Quaternion.IDENTITY)

	assert_eq(_stored_cursors.size(), 1, "Only the well-formed cursor is kept.")
	assert_eq(_stored_cursors[0]["orientation_index"], GOOD_ORIENTATION, "The last well-formed cursor is what the host keeps.")
	assert_eq(_ghost_updates, 1, "A malformed cursor never reaches the remote ghost.")
	assert_eq(_broadcasts, 1, "Nor is it rebroadcast.")
	assert_eq(_replies.size(), 0, "A dropped cursor is not answered.")

	var kept: Dictionary = _stored_cursors[0]
	var reason: StringName = _gateway.apply_place(
		REMOTE_SLOT,
		kept["origin"] as Vector3,
		kept["orientation_index"] as int,
		kept["free_quat"] as Quaternion,
		true,
		Match.feed_seq(REMOTE_SLOT)
	)

	assert_eq(reason, PlacementRules.REASON_OK, "The timer path drops from the kept pose.")
	assert_eq(_block_count(), 1, "The timer path never sees the malformed pose and still drops.")
	assert_eq(_counters.accepted_count(REMOTE_SLOT), 0, "the timer drop is not an accepted intent")


# --- .6  Origin, free quaternion and height ----------------------------------


func test_non_finite_remote_origins_are_refused() -> void:
	_make_gateway()
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
		_remote_place(bad_origin, 0, Quaternion.IDENTITY, seq)
		_assert_nothing_was_spent(seq, refused, "origin %s from the wire" % bad_origin)
		refused += 1


func test_malformed_remote_quaternions_are_refused() -> void:
	_make_gateway()
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
		_remote_place(_home_world_position(REMOTE_SLOT), 0, bad_quat, seq)
		_assert_nothing_was_spent(seq, refused, "quaternion %s from the wire" % bad_quat)
		refused += 1


func test_remote_heights_outside_the_replicable_band_are_refused() -> void:
	_make_gateway()
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
		_remote_place(_home_world_position(REMOTE_SLOT, bad_height), 0, Quaternion.IDENTITY, seq)
		_assert_nothing_was_spent(seq, refused, "height %f from the wire" % bad_height)
		refused += 1


## A well-formed but far-off-disk manual release used to burn the block from an
## origin clamped inside the kill plane. Now a manual release outside the
## player's territory is refused instead: nothing spawns, the piece stays
## held, feed_seq does not move, and the client can retry. The burn clamp is
## still exercised for auto-drops in tests/unit/match/test_match_flow.gd.
func test_a_far_off_disk_remote_intent_is_refused_and_keeps_the_piece() -> void:
	_make_gateway()
	_start_playing()
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var far_origins: Array[Vector3] = [
		_field.to_global(Vector3(1.0e6, physics.hover_height, 0.0)),
		_field.to_global(Vector3(0.0, physics.hover_height, -1.0e6)),
	]
	var rejections: Array[int] = []
	var on_rejected: Callable = func(slot_id: int, _reason: StringName) -> void:
		rejections.append(slot_id)
	Events.placement_rejected.connect(on_rejected)

	var seq_before: int = Match.feed_seq(REMOTE_SLOT)
	var held_before: BlockShape = Match.held_shape(REMOTE_SLOT)
	for i: int in range(far_origins.size()):
		_remote_place(far_origins[i], 0, Quaternion.IDENTITY, Match.feed_seq(REMOTE_SLOT))
		assert_eq(_counters.accepted_count(REMOTE_SLOT), 0, "A far-off-disk release is refused, not consumed.")
		assert_eq(_block_count(), 0, "Nothing spawns for a refused release.")
		assert_eq(Match.feed_seq(REMOTE_SLOT), seq_before, "A refusal never advances the cadence.")
		assert_eq(Match.held_shape(REMOTE_SLOT), held_before, "The refused piece stays in hand.")

	Events.placement_rejected.disconnect(on_rejected)
	assert_eq(rejections.size(), far_origins.size(), "Each refused release reports placement_rejected once.")
	assert_eq(rejections.count(REMOTE_SLOT), far_origins.size(), "The rejection names the releasing slot.")


# --- the counter identity ---------------------------------------------------------------------


func test_a_refused_remote_intent_is_tallied_against_the_senders_slot() -> void:
	_make_gateway()
	_start_playing()
	_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -5)
	assert_eq(_counters.sent_count(REMOTE_SLOT), 1)
	assert_eq(_counters.refused_count(REMOTE_SLOT), 1)
	assert_eq(_counters.accepted_count(REMOTE_SLOT), 0)


# --- per-peer intent flood limits (MatchIntentGateway) -----------------------------------------


func test_a_flood_of_refused_placements_are_answered_only_up_to_the_burst() -> void:
	_make_gateway()
	_start_playing()
	var burst: int = _net_config.flood_place_burst
	_now_s = FLOOD_TIME_S
	for _i: int in range(FLOOD_FACTOR * burst):
		_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)
	assert_eq(_replies.size(), burst, "no reply for a flooded intent")
	assert_eq(_counters.sent_count(REMOTE_SLOT), burst, "a flooded intent is not even counted as sent")
	assert_eq(_block_count(), 0)
	assert_eq(_broadcasts, 0, "a dropped intent is not rebroadcast")
	assert_eq(_fake_net.kick_peer_calls.size(), 0, "a flooder is dropped, never kicked")


func test_a_single_normal_refusal_is_still_answered_once() -> void:
	_make_gateway()
	_start_playing()
	_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)
	assert_eq(_replies.size(), 1)
	assert_eq(_replies[0][0], REMOTE_PEER)
	assert_eq(_replies[0][1], &"net_match_event")
	assert_eq(_replies[0][2], [MatchWireEvents.PLACEMENT_REJECTED, [REMOTE_SLOT, PlacementRules.REASON_NO_BLOCK]])


func test_a_flood_of_remote_cursors_updates_the_ghost_only_up_to_the_burst() -> void:
	_make_gateway()
	_start_playing()
	var burst: int = _net_config.flood_cursor_burst
	_now_s = FLOOD_TIME_S
	for _i: int in range(FLOOD_FACTOR * burst):
		_remote_cursor(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY)
	assert_eq(_ghost_updates, burst, "only what the bucket let through reaches the ghost")
	assert_eq(_stored_cursors.size(), burst, "and only that is kept for the auto-drop")
	assert_eq(_broadcasts, burst, "and only that is rebroadcast")


func test_a_peer_leaving_gives_a_rejoin_full_buckets() -> void:
	_make_gateway()
	_start_playing()
	var burst: int = _net_config.flood_place_burst
	_now_s = FLOOD_TIME_S
	for _i: int in range(2 * burst):
		_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)
	assert_eq(_replies.size(), burst, "fixture: the bucket is drained")
	_gateway.forget_peer(REMOTE_PEER)
	for _i: int in range(burst):
		_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)
	assert_eq(_replies.size(), 2 * burst, "a full bucket again")


func test_the_net_config_a_gateway_is_built_with_sets_its_limits() -> void:
	var tight: NetConfig = _net_config.duplicate() as NetConfig
	tight.flood_place_burst = TIGHT_BURST
	_make_gateway(tight)
	_start_playing()
	_now_s = FLOOD_TIME_S
	for _i: int in range(2 * TIGHT_BURST + 2):
		_remote_place(_home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)
	assert_eq(_replies.size(), TIGHT_BURST, "the burst of the config it was built with applies")
