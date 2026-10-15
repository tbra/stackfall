extends GutTest
## net/MatchNet.gd: authority, intents and replication (spec 2.6,
## docs/archive/M3a_PLAN.md P3). This is where M3a's "placements are never duplicated
## or lost" is won or lost, so these tests drive the **real** Match with a
## faked Net rather than a fake authority: every assertion below is about what
## actually happens to the block feed.
##
## There is no peer in a unit test, so MatchNet's rpc() calls are no-ops
## (_can_send() is false) and the host path — which is the one that decides
## anything — runs in full. The wire itself is P1's and the acceptance
## harness's business; what has to be proved here is that the host accepts
## exactly the intents it should and no others.

## MatchNet is an autoload with no class_name (it would collide with the
## singleton), and the integrator registers it only when the packages merge,
## so these tests instantiate the script directly.
const MatchNetScript := preload("res://net/MatchNet.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _net: MatchNetScript
var _fake_net: FakeNet

## DECISION: see test_match_flow.gd's own `_tiny_map` comment
## for the full story -- this file builds a real Field/Match world in every
## test's before_each exactly the same way, so it paid the same ~11 s
## round_medium.tres (45 m, ~6300 cells) collision build per test. 20 m, the
## same figure test_match_flow.gd settled on, via the same TinyMapMatchConfig
## seam (tests/support/) so Match's own geometry agrees with this file's
## Field.
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
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## MatchNet bound to the real Match and a scripted session. `peer_slots` maps
## peer id -> slot id; `local` lists the slots this instance's own input
## drives (slot 0 for a listen-server host).
func _make_net(peer_slots: Dictionary, local: Array[int], client_mode: bool = false) -> MatchNetScript:
	_fake_net = FakeNet.host(peer_slots, local) if not client_mode else FakeNet.client(local[0])
	_fake_net.slots_by_peer = peer_slots
	Match.set_net_provider(_fake_net)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	return node


func _config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults, so it must happen before any field is
	# set on `config` (test_match_flow.gd's own _tiny_map_config() doc comment
	# has the full story).
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = block_timer
	config.rng_seed = 4242
	return config


func _start_playing(player_count: int = 2, block_timer: float = 6.0) -> void:
	Match.start_match(_config(player_count, block_timer))
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


func _seed_held_gift(slot_id: int, special_id: StringName) -> void:
	Match._gifts.apply_replicated_claim(1, slot_id, special_id)
	Match._gifts.activate_next_special(slot_id)
	Match._feed._held_is_gift[slot_id] = true


## A world position right on `slot_id`'s own home flag, where a single block
## always validates.
func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 0.0, home.y))


func _block_count() -> int:
	return _blocks_root.get_child_count()


## spec 1.4 "[ORIGINAL target]" cadence: several tests below
## place more than once for the same slot with no frame between calls, the
## way this whole file's fixture (a unit test with no real peer, so every
## rpc() is a no-op) always has. Since a deliberate release now locks the
## slot until its fixed interval's boundary (Match._consume_and_refeed()), a
## second call in the same frame would be refused with REASON_NO_BLOCK before
## that boundary arrives. Match.debug_unlock_slot() is the test-only seam
## that resolves exactly `slot_id`'s lock immediately, the same thing
## Match._tick_feed()'s own boundary-crossing branch would do -- rather than
## ticking Match._process() for a block_timer's worth of frames, which would
## also run every OTHER slot's independent interval down by that much and
## risk an unrelated auto-drop in a test that isn't about auto-drop at all.
func _unlock_slot(slot_id: int) -> void:
	Match.debug_unlock_slot(slot_id)


# --- The host's local player never round-trips ------------------------------


func test_submit_place_on_the_host_reaches_match_in_the_same_frame() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	var before: int = _block_count()
	var reason: StringName = net.submit_place(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0)
	)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_block_count(), before + 1, "The host's own click must spawn inline, with no round trip.")
	assert_eq(net.intents_accepted(0), 1)
	assert_eq(net.intents_sent(0), 1)


func test_submit_place_on_a_client_sends_without_touching_match() -> void:
	var net: MatchNetScript = _make_net({}, [1], true)
	# The client still built the world from the host's match start.
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match.set_net_provider(_fake_net)

	var before: int = _block_count()
	var reason: StringName = net.submit_place(
		1, _home_world_position(1), 0, Quaternion.IDENTITY, false, Match.feed_seq(1)
	)

	assert_eq(_block_count(), before, "A client must never spawn a block itself (spec 2.6).")
	assert_eq(net.intents_accepted(1), 0, "Only the host accepts.")
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK, "With no peer there is nowhere to send it.")
	assert_eq(
		net.intents_sent(1),
		0,
		"and nothing that never reached the wire is counted as sent, or the harness's client-to-host comparison would be meaningless"
	)


# --- Never duplicated, never lost -------------------------------------------


## spec 1.4 "[ORIGINAL target]" cadence: a release attempted
## while release-locked, over the wire, counts exactly like any other refused
## intent -- MatchNet._consumed_a_block() already treats REASON_NO_BLOCK as
## "nothing spent" (autoload/Match.gd's DECISION on reusing that reason), so
## it is refused, not silently dropped, and the invariant the acceptance
## harness checks (accepted + refused == sent) still holds.
func test_a_locked_release_over_the_wire_is_refused_not_dropped() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var where: Vector3 = _home_world_position(0)
	net.submit_place(0, where, 0, Quaternion.IDENTITY, false, Match.feed_seq(0))
	assert_true(Match.is_release_locked(0), "fixture: slot 0 is now locked")

	var reason: StringName = net.submit_place(0, where, 0, Quaternion.IDENTITY, false, Match.feed_seq(0))

	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(net.intents_accepted(0), 1)
	assert_eq(net.intents_refused(0), 1)
	assert_eq(net.intents_sent(0), 2)
	assert_eq(_block_count(), 1)


func test_a_stale_feed_seq_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var stale: int = Match.feed_seq(0)

	net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, stale)
	# Two more blocks have been issued in the meantime as far as this sender
	# knows; it still quotes the sequence it saw before its first click.
	var reason: StringName = net.submit_place(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, false, stale
	)

	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_block_count(), 1)


# --- A peer may only act for its own slot -----------------------------------


func test_an_intent_for_someone_elses_slot_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	# Peer 2 holds slot 1 but claims slot 0.
	net._handle_place_intent(2, 0, _home_world_position(0), 0, Quaternion.IDENTITY, Match.feed_seq(0))

	assert_eq(_block_count(), 0, "Nothing may be placed for a slot the sender does not hold.")
	assert_eq(net.intents_accepted(0), 0, "intents_accepted must not move.")
	assert_eq(net.intents_accepted(1), 0)
	assert_eq(net.intents_refused(1), 1, "The refusal is counted against the sender's own slot.")
	assert_eq(net.intents_sent(1), 1)


func test_a_client_never_acts_on_an_intent_it_receives() -> void:
	var net: MatchNetScript = _make_net({}, [1], true)
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match.set_net_provider(_fake_net)

	net._handle_place_intent(1, 0, _home_world_position(0), 0, Quaternion.IDENTITY, 0)

	assert_eq(_block_count(), 0)


# --- The counters the acceptance harness asserts on -------------------------


# --- Auto-drop never crosses the wire (spec 1.4, [ORIGINAL]) ----------------


# --- Clients decide nothing (spec 2.6) --------------------------------------


func test_a_client_runs_no_solve_no_feed_tick_and_no_win_check() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing(2, 6.0)
	var timer_before: float = Match.feed_time_left(0)
	var seq_before: int = Match.feed_seq(0)
	watch_signals(Events)

	Match.set_net_provider(FakeNet.client(1))
	for _i: int in range(120):
		Match._process(1.0 / 60.0)

	assert_signal_not_emitted(Events, "feed_timer_expired", "A client never expires a timer.")
	assert_signal_not_emitted(Events, "territory_updated", "A client never solves territory.")
	assert_signal_not_emitted(Events, "match_won", "A client never decides the win.")
	assert_eq(Match.feed_seq(0), seq_before, "and it issues no blocks of its own")
	assert_lt(
		Match.feed_time_left(0),
		timer_before,
		"but the HUD's timer still counts down for display"
	)


# --- Disconnects (docs/archive/M3a_PLAN.md question 2) ------------------------------


func test_disconnect_grace_stops_the_feed_but_keeps_the_slot_alive() -> void:
	_make_net({1: 0, 2: 1}, [0])
	_start_playing(2, 6.0)
	var before: float = Match.feed_time_left(1)

	Match.on_peer_left(1)
	for _i: int in range(60):
		Match._process(1.0 / 60.0)

	assert_true(Match.slot(1).home_flag_alive, "Inside the grace period the slot is still in the match.")
	assert_almost_eq(Match.feed_time_left(1), before, 0.001, "and its feed timer is stopped")
	assert_lt(Match.feed_time_left(0), before, "while everyone else keeps playing")


func test_disconnect_grace_expiry_eliminates_the_slot() -> void:
	_make_net({1: 0, 2: 1, 3: 2}, [0])
	_start_playing(3, 6.0)
	watch_signals(Events)

	Match.on_peer_left(1)
	var grace: float = load("res://config/net/net_config.tres").disconnect_grace
	for _i: int in range(int(grace * 60.0) + 10):
		Match._process(1.0 / 60.0)

	assert_false(Match.slot(1).home_flag_alive, "The slot is eliminated exactly as a lost home flag does it.")
	assert_signal_emitted(Events, "player_eliminated")
	assert_eq(Match.disconnect_grace_left(1), -1.0)


func test_a_peer_that_comes_back_inside_the_grace_keeps_playing() -> void:
	_make_net({1: 0, 2: 1}, [0])
	_start_playing(2, 6.0)

	Match.on_peer_left(1)
	for _i: int in range(120):
		Match._process(1.0 / 60.0)
	Match.on_peer_rejoined(1)
	var grace: float = load("res://config/net/net_config.tres").disconnect_grace
	for _i: int in range(int(grace * 60.0) + 10):
		Match._process(1.0 / 60.0)

	assert_true(Match.slot(1).home_flag_alive, "It came back, so it is never eliminated.")
	assert_eq(Match.disconnect_grace_left(1), -1.0)


func test_an_intent_from_a_departed_peer_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match.on_peer_left(1)
	# P1 drops the peer from the registry as it goes.
	_fake_net.slots_by_peer.erase(2)

	net._handle_place_intent(2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, Match.feed_seq(1))

	assert_eq(_block_count(), 0, "An intent already in flight when its sender vanished is dropped.")


# --- Allocator exhaustion never reaches the wire ----------
#
# game/blocks/BlockRegistry.gd refuses to allocate past Quantize.NET_ID_MAX and
# leaves the block with net_id == -1; the body still lives and simulates on
# the host, but nothing about it may go out over replicate_spawn(), or a
# client would build a phantom copy no despawn could ever address (spec 2.6:
# the body "stays host-only"). A unit test has no live peer, so _can_send()
# is already false and cannot by itself prove replicate_spawn() never handed
# the rpc a bad id; invalid_spawn_refusal_count() is the seam that does.


func test_a_spawn_refused_by_the_allocator_never_reaches_the_wire() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	_registry.debug_set_next_net_id(Quantize.NET_ID_MAX)
	var where: Vector3 = _home_world_position(0)

	var first: StringName = net.submit_place(0, where, 0, Quaternion.IDENTITY, false, Match.feed_seq(0))
	_unlock_slot(0)
	var second: StringName = net.submit_place(0, where, 1, Quaternion.IDENTITY, false, Match.feed_seq(0))

	assert_eq(first, PlacementRules.REASON_OK, "the last representable id still places")
	assert_eq(second, PlacementRules.REASON_OK, "a rejected allocation is not a rule violation; the block still spawns")
	assert_push_error("net_id space exhausted")
	assert_eq(_block_count(), 2)
	assert_eq((_blocks_root.get_child(0) as Block).net_id, Quantize.NET_ID_MAX)
	assert_eq((_blocks_root.get_child(1) as Block).net_id, -1, "the second body keeps living, host-only, with no id")
	assert_eq(
		net.invalid_spawn_refusal_count(), 1,
		"replicate_spawn() must refuse the id-less body instead of hitting the wire"
	)
	assert_eq(net.replicated_block_count(), 1, "only the valid spawn is ever counted as replicated")


# --- The territory payload --------------------------------------------------


func test_a_full_raster_payload_round_trips() -> void:
	var net: MatchNetScript = _make_net({1: 0}, [0])
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()
	for i: int in range(500):
		owners.append(i % 4)
		states.append(i % 3)

	var payload: PackedByteArray = net._encode_raster_full(owners, states)
	var decoded: Dictionary = MatchNetScript.decode_raster_payload(payload, true)

	assert_eq(decoded["owners"], owners)
	assert_eq(decoded["states"], states)
	assert_eq(decoded["cells"].size(), 0, "A full payload names every cell implicitly.")


func test_a_diff_payload_round_trips() -> void:
	var net: MatchNetScript = _make_net({1: 0}, [0])
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()
	owners.resize(100)
	states.resize(100)
	owners[7] = 2
	states[7] = TerritoryRaster.STATE_HOLE
	owners[90] = 3
	states[90] = TerritoryRaster.STATE_CONTESTED

	var payload: PackedByteArray = net._encode_raster_diff(
		PackedInt32Array([7, 90]), owners, states
	)
	var decoded: Dictionary = MatchNetScript.decode_raster_payload(payload, false)

	assert_eq(decoded["cells"], PackedInt32Array([7, 90]))
	assert_eq(decoded["owners"], PackedByteArray([2, 3]))
	assert_eq(
		decoded["states"],
		PackedByteArray([TerritoryRaster.STATE_HOLE, TerritoryRaster.STATE_CONTESTED])
	)


func test_a_truncated_or_foreign_territory_payload_decodes_to_nothing() -> void:
	assert_true(MatchNetScript.decode_raster_payload(PackedByteArray(), true).is_empty())
	assert_true(MatchNetScript.decode_raster_payload(PackedByteArray([9, 9, 9]), false).is_empty())
	var foreign: PackedByteArray = PackedByteArray([200, 0, 4, 0, 0, 0, 1, 2, 3, 4])
	assert_true(
		MatchNetScript.decode_raster_payload(foreign, true).is_empty(),
		"A payload from another packet version must be dropped, not misread."
	)


# --- the replicated circle list ------------------------------


# --- Replicated spawns and despawns on a client -----------------------------


# --- start_match()'s own transient states are not --------
# --- replicated a second time ------------------------------------------------
#
# Before the fix, _on_match_state_changed() replicated every state change,
# including the LOBBY/LOADING/COUNTDOWN start_match() produces internally --
# already fully reproduced on a client by net_match_start's own inline
# start_match() call. replicated_state_changes/match_starts_replicated are
# test-only instrumentation (see net/MatchNet.gd): _can_send() is already
# false in every test in this file with no live peer, so it alone cannot
# prove a redundant event was suppressed rather than merely handed to a
# no-op rpc().


func test_start_match_from_lobby_does_not_replicate_its_own_transient_states() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	var host_net: MatchNetScript = _make_net({}, [0, 1])
	watch_signals(Events)

	Match.start_match(_config())

	assert_eq(
		host_net.replicated_state_changes, [],
		"LOBBY->LOADING->COUNTDOWN inside start_match() must not be replicated a second time -- only net_match_start carries the start"
	)
	assert_eq(host_net.match_starts_replicated, 1)
	assert_eq(
		get_signal_emit_count(Events, "match_state_changed"), 2,
		"exactly the real LOBBY->LOADING and LOADING->COUNTDOWN transitions, the same two a client's own net_match_start-triggered start_match() call produces"
	)


# --- The client's read model ------------------------------------------------


func test_a_replicated_feed_event_sets_the_held_shape_and_resets_the_timer() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing(2, 6.0)
	var net: MatchNetScript = _make_net({}, [1], true)
	for _i: int in range(60):
		Match._process(1.0 / 60.0)
	assert_lt(Match.feed_time_left(1), 6.0)

	net.net_match_event(MatchNetScript.EVENT_FEED_ISSUED, [1, &"cube", &"domino", 9])

	assert_eq(Match.held_shape(1).id, &"cube")
	assert_almost_eq(Match.feed_time_left(1), 6.0, 0.001, "The host's feed is the client's clock.")
	assert_eq(
		Match.feed_seq(1), 9, "The client takes the host's sequence verbatim; it cannot count its own."
	)


func test_a_replicated_turn_points_a_client_at_its_own_slot() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	# The host emits turn_changed(0) for its own player when play begins.
	net.net_match_event(MatchNetScript.EVENT_TURN_CHANGED, [0])

	# Outside hot-seat the signal points at the controls that are live on this
	# instance, not at whoever the host named.
	assert_signal_emitted_with_parameters(Events, "turn_changed", [1])
	assert_eq(Match.active_slot(), 1)


func test_a_replicated_territory_packet_drives_the_mirror_and_the_hole_signal() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	var raster: TerritoryRaster = Match.raster()
	var cell_count: int = raster.grid().cell_count()
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()
	owners.resize(cell_count)
	states.resize(cell_count)
	var target: int = raster.grid().cell_index(raster.grid().res / 2, raster.grid().res / 2)
	owners[target] = 2
	states[target] = TerritoryRaster.STATE_HOLE
	var payload: PackedByteArray = net._encode_raster_full(owners, states)
	watch_signals(Events)

	net.net_territory(payload, true, PackedFloat32Array([0.25, 0.5]), 1, 0.4)

	assert_true(Match.raster().is_hole_index(target), "The mirror holds exactly what the host sent.")
	assert_signal_emitted(Events, "hole_cells_changed")
	assert_signal_emitted(Events, "territory_replicated")
	assert_signal_emitted_with_parameters(Events, "goal_capture_progress", [1, 0.4])


# --- a decaying home claim reaches clients on a static board ---

func test_malformed_capture_progress_is_rejected() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var host_net: MatchNetScript = _make_net({}, [0])
	var raster: TerritoryRaster = Match.raster()
	var empty: PackedByteArray = host_net._encode_raster_diff(
		PackedInt32Array(), raster.owner_bytes(), raster.state_bytes()
	)
	var client_net: MatchNetScript = _make_net({}, [1], true)
	var shares: PackedFloat32Array = PackedFloat32Array([0.5, 0.5])
	watch_signals(Events)
	client_net.net_territory(empty, false, shares, 1, NAN)
	client_net.net_territory(empty, false, shares, 1, INF)
	client_net.net_territory(empty, false, shares, 1, 1.5)
	client_net.net_territory(empty, false, shares, 1, -0.1)
	client_net.net_territory(empty, false, shares, 9, 0.5)
	client_net.net_territory(empty, false, shares, -2, 0.5)
	assert_signal_not_emitted(Events, "goal_capture_progress")
	client_net.net_territory(empty, false, shares, 1, 0.5)
	assert_signal_emitted_with_parameters(Events, "goal_capture_progress", [1, 0.5])


# --- M4 P2b: EVENT_GIFT_CLAIMED's third argument (Orchestrator amendment 1) -

## net/MatchNet.gd's _special_id_wire_ok(): empty, over-length (40 chars) and
## non-[A-Za-z0-9_] (a space) payloads are all dropped -- mirrors
## test_gift_claim.gd's test_gift_wire_rejects_malformed_payloads for
## EVENT_GIFT_SPAWNED's own position check.
func test_a_malformed_special_id_is_dropped_not_applied() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [4, 1, &"", &"cube"])
	assert_signal_not_emitted(Events, "gift_claimed", "an empty special_id must be dropped")
	assert_eq(Match.held_special(1), &"", "and never queued")

	var too_long: String = "a".repeat(40)
	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [5, 1, StringName(too_long), &"cube"])
	assert_signal_not_emitted(Events, "gift_claimed", "a 40-character special_id must be dropped")
	assert_eq(Match.held_special(1), &"")

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [6, 1, &"has space", &"cube"])
	assert_signal_not_emitted(Events, "gift_claimed", "a special_id with a space must be dropped")
	assert_eq(Match.held_special(1), &"")


# --- M4 P2c-ii: request_throw over the wire ---------------------------------


func test_a_throw_intent_for_someone_elses_slot_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	_seed_held_gift(0, MatchGifts.PENDING_SPECIAL_ID)

	# Peer 2 holds slot 1 but claims slot 0, exactly like the matching
	# placement test above.
	net._handle_throw_intent(
		2, 0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0), Match.feed_seq(0)
	)

	assert_eq(_block_count(), 0, "Nothing may be thrown for a slot the sender does not hold.")
	assert_eq(net.intents_accepted(0), 0)
	assert_eq(net.intents_refused(1), 1, "The refusal is counted against the sender's own slot.")
	assert_eq(net.intents_sent(1), 1)


## Review NIT: a remote throw intent quoting the -1 "don't check" sentinel
## must be refused at the wire boundary -- _handle_throw_intent()'s own
## `feed_seq < 0` branch, exactly the one _handle_place_intent() takes (see
## that function's own matching comment on why -1 is a trusted-local-caller-
## only courtesy that must never arrive from the wire).
func test_a_negative_feed_seq_on_a_throw_intent_is_refused_at_the_wire_like_place() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	_seed_held_gift(1, MatchGifts.PENDING_SPECIAL_ID)

	net._handle_throw_intent(
		2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0), -1
	)

	assert_eq(_block_count(), 0, "A negative feed_seq from the wire must be refused, not treated as 'don't check'.")
	assert_eq(net.intents_refused(1), 1)
	assert_eq(Match.held_special(1), MatchGifts.PENDING_SPECIAL_ID, "nothing was consumed by the refusal")


# --- M4 P2c-ii: EVENT_SPECIAL_TRIGGERED replication -------------------------


func test_a_malformed_special_trigger_is_dropped_not_applied() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [-1, &"volcano", Vector3.ZERO, 0])
	assert_signal_not_emitted(Events, "special_triggered", "a negative net_id must be dropped")

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"has space", Vector3.ZERO, 0])
	assert_signal_not_emitted(Events, "special_triggered", "a malformed def_id must be dropped")

	net.net_match_event(
		MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano", Vector3(NAN, 0.0, 0.0), 0]
	)
	assert_signal_not_emitted(Events, "special_triggered", "a non-finite position must be dropped")

	var over_cap: int = int((load("res://config/gifts/special_tuning.tres") as SpecialTuning).max_chain_depth) + 1
	net.net_match_event(
		MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano", Vector3.ZERO, over_cap]
	)
	assert_signal_not_emitted(Events, "special_triggered", "chain_depth over the cap must be dropped")

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano", Vector3.ZERO, -1])
	assert_signal_not_emitted(Events, "special_triggered", "a negative chain_depth must be dropped")


# --- EVENT_SPECIAL_CONSUMED replication ---------------------


func test_glue_charge_mirror_accepts_only_new_valid_absolute_updates() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)
	net.net_match_event(MatchNetScript.EVENT_GLUE_CHARGES, [1, 3, 1])
	assert_eq(Match.glue_drops_left(1), 3)
	assert_eq(Match.glue_revision(1), 1)
	assert_eq(get_signal_emit_count(Events, "glue_charges_changed"), 1)
	net.net_match_event(MatchNetScript.EVENT_GLUE_CHARGES, [1, 2, 1])
	net.net_match_event(MatchNetScript.EVENT_GLUE_CHARGES, [1, 2, 0])
	assert_eq(Match.glue_drops_left(1), 3, "duplicate or stale revisions cannot restore charges")
	net.net_match_event(MatchNetScript.EVENT_GLUE_CHARGES, [1, 0, 2])
	assert_eq(Match.glue_drops_left(1), 0)
	assert_eq(get_signal_emit_count(Events, "glue_charges_changed"), 2)
	for payload: Array in [[1], [1, "3", 3], [1, 101, 3], [99, 2, 3], [1, 2, -1]]:
		net.net_match_event(MatchNetScript.EVENT_GLUE_CHARGES, payload)
	assert_eq(Match.glue_drops_left(1), 0)
	assert_eq(get_signal_emit_count(Events, "glue_charges_changed"), 2)


## DECISION (net/MatchNet.gd): the host must never apply this
## event to its own authoritative queue -- see net_match_event's own
## EVENT_SPECIAL_CONSUMED case comment. `net` here is a HOST-mode MatchNet
## (unlike every test above, which uses client_mode = true), simulating a
## stale duplicate or a spoofed direct call the host itself receives.
func test_host_ignores_a_spoofed_special_consumed_event() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var slot_id: int = 1
	Match._gifts._ensure_capacity(slot_id)
	(Match._gifts._pending_queues[slot_id] as Array).append(&"test_special")
	assert_eq(Match.pending_special_count(slot_id), 1, "setup")
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_CONSUMED, [slot_id, &"test_special"])

	assert_signal_not_emitted(Events, "special_consumed", "the host must never apply this event to itself")
	assert_eq(Match.pending_special_count(slot_id), 1, "a spoofed event must never pop the host's own queue")


func _gift_client_fixture() -> MatchNetScript:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match._gifts.reset()
	return _make_net({}, [1], true)


func test_gift_flight_interpolates_but_waits_for_authoritative_landing() -> void:
	var net: MatchNetScript = _gift_client_fixture()
	var origin: Vector3 = Vector3(0, 10, 0)
	var landing: Vector3 = Vector3(0, 1, 0)
	net.net_match_event(MatchNetScript.EVENT_GIFT_FLIGHT, [101, origin, landing])
	var node: GiftCrate = Match._gifts._crates[101]["node"]
	Match._physics_process(0.5)
	assert_lt(node.global_position.y, origin.y)
	assert_gt(node.global_position.y, landing.y)
	var elapsed: float = Match.gift_state(101)["elapsed"]
	net.net_match_event(MatchNetScript.EVENT_GIFT_FLIGHT, [101, origin, landing])
	net.net_match_event(MatchNetScript.EVENT_GIFT_SPAWNED, [101, Vector2.ZERO])
	assert_eq(Match.gift_state(101)["elapsed"], elapsed, "duplicate must not rewind")
	assert_same(Match._gifts._crates[101]["node"], node, "legacy event reuses the visual")
	Match._physics_process(100.0)
	assert_eq(node.global_position, landing)
	assert_eq(Match.gift_state(101)["phase"], MatchGifts.FALLING)
	assert_eq(Match.pending_special_count(0), 0, "interpolation cannot claim")
	net.net_match_event(MatchNetScript.EVENT_GIFT_LANDED, [101, landing])
	assert_eq(Match.gift_state(101)["phase"], MatchGifts.LANDED)
	Match._physics_process(100.0)
	assert_false(Match.gift_state(101).is_empty(), "client cannot expire")
	net.net_match_event(MatchNetScript.EVENT_GIFT_FLIGHT, [101, origin, landing])
	assert_eq(Match.gift_state(101)["phase"], MatchGifts.LANDED)

