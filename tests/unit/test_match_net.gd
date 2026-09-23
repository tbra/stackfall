extends GutTest
## net/MatchNet.gd: authority, intents and replication (spec 3.4,
## docs/M3a_PLAN.md P3). This is where M3a's "placements are never duplicated
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

## DECISION (Bontago-mv0.3): see test_match_flow.gd's own `_tiny_map` comment
## for the full story -- this file builds a real Field/Match world in every
## test's before_each exactly the same way, so it paid the same ~11 s
## round_medium.tres (45 m, ~6300 cells) collision build per test. 20 m, the
## same figure test_match_flow.gd settled on, via the same TinyMapMatchConfig
## seam (tests/unit/support/) so Match's own geometry agrees with this file's
## Field.
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


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)


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
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults, so it must happen before any field is
	# set on `config` (test_match_flow.gd's own _tiny_map_config() doc comment
	# has the full story).
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


## A world position right on `slot_id`'s own home flag, where a single block
## always validates.
func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 0.0, home.y))


func _block_count() -> int:
	return _blocks_root.get_child_count()


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): several tests below
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

	assert_eq(_block_count(), before, "A client must never spawn a block itself (spec 3.4).")
	assert_eq(net.intents_accepted(1), 0, "Only the host accepts.")
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK, "With no peer there is nowhere to send it.")
	assert_eq(
		net.intents_sent(1),
		0,
		"and nothing that never reached the wire is counted as sent, or the harness's client-to-host comparison would be meaningless"
	)


# --- Never duplicated, never lost -------------------------------------------


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): a release attempted
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


func test_the_same_intent_delivered_twice_spawns_one_block() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var seq: int = Match.feed_seq(0)
	var where: Vector3 = _home_world_position(0)

	var first: StringName = net.submit_place(0, where, 0, Quaternion.IDENTITY, false, seq)
	var second: StringName = net.submit_place(0, where, 0, Quaternion.IDENTITY, false, seq)

	assert_eq(first, PlacementRules.REASON_OK)
	assert_eq(second, PlacementRules.REASON_NO_BLOCK, "A replayed feed_seq must be a no-op.")
	assert_eq(_block_count(), 1, "One held block, one spawned block.")
	assert_eq(net.intents_accepted(0), 1)
	assert_eq(net.intents_refused(0), 1)


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


func test_feed_seq_advances_on_every_consumed_block() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var start: int = Match.feed_seq(0)

	for _i: int in range(3):
		net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0))
		_unlock_slot(0)

	assert_eq(Match.feed_seq(0), start + 3)
	assert_eq(_block_count(), 3)


func test_an_omitted_feed_seq_still_works_so_m2_call_sites_compile_unchanged() -> void:
	_make_net({1: 0}, [0])
	_start_playing()

	var reason: StringName = Match.request_place(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, false
	)

	assert_eq(reason, PlacementRules.REASON_OK)
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


func test_an_intent_from_a_peer_with_no_slot_is_ignored_entirely() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	net._handle_place_intent(99, 0, _home_world_position(0), 0, Quaternion.IDENTITY, Match.feed_seq(0))

	assert_eq(_block_count(), 0)
	assert_eq(net.intents_sent(0), 0)
	assert_eq(net.intents_sent(1), 0)


func test_a_remote_peers_own_intent_is_accepted() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	net._handle_place_intent(2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, Match.feed_seq(1))

	assert_eq(_block_count(), 1)
	assert_eq(net.intents_accepted(1), 1)
	assert_eq(net.intents_refused(1), 0)


func test_a_client_never_acts_on_an_intent_it_receives() -> void:
	var net: MatchNetScript = _make_net({}, [1], true)
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match.set_net_provider(_fake_net)

	net._handle_place_intent(1, 0, _home_world_position(0), 0, Quaternion.IDENTITY, 0)

	assert_eq(_block_count(), 0)


# --- The counters the acceptance harness asserts on -------------------------


func test_counters_balance_across_a_mixed_run() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	# Slot 0 (the host's own player): two good placements and one replay.
	var seq0: int = Match.feed_seq(0)
	net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, seq0)
	net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, seq0)
	net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0))
	# Slot 1 (a remote peer): one good placement, one spoofed slot, one
	# attempted far off the disk, which Bontago-mv0.24 now simply refuses
	# (owner test 2026-09-22) instead of burning it (spec 2.2's older line for
	# a manual release) -- it counts as refused, not accepted, below.
	net._handle_place_intent(2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, Match.feed_seq(1))
	net._handle_place_intent(2, 0, _home_world_position(0), 0, Quaternion.IDENTITY, Match.feed_seq(0))
	net._handle_place_intent(2, 1, Vector3(0.0, 0.0, 0.0), 0, Quaternion.IDENTITY, Match.feed_seq(1))
	# And one auto-drop for the remote slot, from the host's timer.
	net.submit_cursor(1, _home_world_position(1), 0, Quaternion.IDENTITY)
	Events.feed_timer_expired.emit(1)

	for slot_id: int in [0, 1]:
		assert_eq(
			net.intents_accepted(slot_id) + net.intents_refused(slot_id),
			net.intents_sent(slot_id),
			"accepted + refused must equal sent for slot %d" % slot_id
		)
	var accepted: int = net.intents_accepted(0) + net.intents_accepted(1)
	var auto: int = net.auto_drops(0) + net.auto_drops(1)
	assert_eq(
		Match.blocks_spawned(),
		accepted + auto,
		"blocks_spawned must equal the accepted intents plus the auto-drops"
	)
	assert_eq(_block_count(), Match.blocks_spawned())


func test_no_net_id_is_ever_spawned_twice() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	var ids: Dictionary = {}
	for _i: int in range(5):
		net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0))
		_unlock_slot(0)
	for child: Node in _blocks_root.get_children():
		var block: Block = child as Block
		assert_false(ids.has(block.net_id), "net_id %d was handed out twice" % block.net_id)
		assert_gt(block.net_id, 0, "the host allocates from 1 upward")
		ids[block.net_id] = true

	assert_eq(net.replicated_block_count(), 5)
	assert_eq(net.duplicate_net_id_count(), 0)


func test_a_duplicate_spawn_announcement_is_counted_not_silently_dropped() -> void:
	var net: MatchNetScript = _make_net({1: 0}, [0])
	_start_playing()
	net.submit_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0))
	var block: Block = _blocks_root.get_child(0) as Block

	net.replicate_spawn(block, block.net_id)

	assert_eq(net.duplicate_net_id_count(), 1, "A repeated net_id is a hard failure, so it is visible.")
	assert_eq(net.replicated_block_count(), 1, "and it is not counted as a second body")


# --- Auto-drop never crosses the wire (spec 2.5, [ORIGINAL]) ----------------


func test_the_host_auto_drops_a_remote_slot_from_its_last_cursor() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var where: Vector3 = _home_world_position(1)
	net.submit_cursor(1, where, 0, Quaternion.IDENTITY)

	Events.feed_timer_expired.emit(1)

	assert_eq(_block_count(), 1, "The host drops for a remote slot itself; no round trip.")
	assert_eq(net.auto_drops(1), 1)
	assert_eq(net.intents_sent(1), 0, "An auto-drop is not an intent and is never sent.")
	var block: Block = _blocks_root.get_child(0) as Block
	assert_almost_eq(block.global_position.x, where.x, 1.5)
	assert_almost_eq(block.global_position.z, where.z, 1.5)


func test_the_host_leaves_its_own_slots_auto_drop_to_the_player_controller() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	Events.feed_timer_expired.emit(0)

	assert_eq(_block_count(), 0, "Slot 0 is local, so its own ghost drops it, exactly as in M2.")
	assert_eq(net.auto_drops(0), 0)


func test_a_slot_that_never_moved_its_cursor_still_auto_drops() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	Events.feed_timer_expired.emit(1)

	assert_eq(_block_count(), 1, "A peer that never moved drops on its own home flag, not at the origin.")
	assert_eq(net.auto_drops(1), 1)


func test_a_client_cannot_claim_an_auto_drop() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()

	# Off-disk, which a deliberate placement now simply refuses (Bontago-mv0.24,
	# owner test 2026-09-22, supersedes spec 2.2's older burn for this case) --
	# an auto-drop would have relocated to a valid point instead. Either way
	# the wire's auto_drop flag must not be read.
	var far_away: Vector3 = _field.to_global(Vector3(500.0, 0.0, 500.0))
	net._handle_place_intent(2, 1, far_away, 0, Quaternion.IDENTITY, Match.feed_seq(1))

	assert_eq(net.auto_drops(1), 0, "Only the host's own timer may grant the relocation privilege.")
	assert_eq(net.intents_accepted(1), 0, "A refused manual drop is not accepted.")
	assert_eq(net.intents_refused(1), 1)
	assert_eq(_block_count(), 0, "Nothing spawns for a refused manual drop.")


func test_cursor_for_slot_reports_the_pose_and_its_age() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	net.submit_cursor(1, Vector3(3.0, 1.0, -2.0), 7, Quaternion(Vector3.UP, 0.5))

	var cursor: Dictionary = net.cursor_for_slot(1)
	assert_eq(cursor["origin"], Vector3(3.0, 1.0, -2.0))
	assert_eq(cursor["orientation_index"], 7)
	assert_true(cursor.has("age"))
	assert_true(net.cursor_for_slot(5).is_empty(), "An unknown slot has no cursor.")


# --- Clients decide nothing (spec 3.4) --------------------------------------


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


func test_a_clients_registry_offers_no_influence_circles() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)

	_registry.set_host_authority(false)
	var circles: Array[InfluenceCircle] = _registry.influence_circles(
		[Match.slot(0), Match.slot(1)], load("res://config/territory_tuning.tres"), Match.config.map_def()
	)

	assert_eq(circles.size(), 0, "Every body on a client is frozen, so none of them may claim territory.")


func test_a_client_refuses_a_local_request_place() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match.set_net_provider(FakeNet.client(1))

	var reason: StringName = Match.request_place(
		1, _home_world_position(1), 0, Quaternion.IDENTITY, false
	)

	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_block_count(), 0)


func test_a_clients_registry_allocates_no_net_ids() -> void:
	_registry.set_host_authority(false)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, load("res://config/physics_tuning.tres"), 0))
	add_child_autofree(block)

	Events.block_placed.emit(block, shape.id)

	assert_eq(block.net_id, -1, "Only the host allocates; the client binds the host's id.")
	_registry.bind_net_id(block, 77)
	assert_eq(block.net_id, 77)
	assert_eq(_registry.block_for_net_id(77), block)


# --- Disconnects (docs/M3a_PLAN.md question 2) ------------------------------


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
	var grace: float = load("res://config/net_config.tres").disconnect_grace
	for _i: int in range(int(grace * 60.0) + 10):
		Match._process(1.0 / 60.0)

	assert_false(Match.slot(1).home_flag_alive, "The slot is eliminated exactly as a lost home flag does it.")
	assert_signal_emitted(Events, "player_eliminated")
	assert_eq(Match.disconnect_grace_left(1), -1.0)


func test_an_eliminated_slots_towers_lose_their_influence() -> void:
	_make_net({1: 0, 2: 1}, [0])
	_start_playing(2, 6.0)
	Match.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false)
	watch_signals(Events)

	Match.on_peer_left(1)
	var grace: float = load("res://config/net_config.tres").disconnect_grace
	for _i: int in range(int(grace * 60.0) + 10):
		Match._process(1.0 / 60.0)

	# Its home circle is gone, so nothing it owns is anchored any more
	# (spec 2.2's connectivity rule), and the match is over with one team left.
	assert_false(Match.slot(1).home_flag_alive)
	assert_eq(Match.state(), Match.State.END, "One player left standing ends the match.")
	assert_signal_emitted_with_parameters(Events, "match_won", [Match.slot(0).team_id])


func test_a_peer_that_comes_back_inside_the_grace_keeps_playing() -> void:
	_make_net({1: 0, 2: 1}, [0])
	_start_playing(2, 6.0)

	Match.on_peer_left(1)
	for _i: int in range(120):
		Match._process(1.0 / 60.0)
	Match.on_peer_rejoined(1)
	var grace: float = load("res://config/net_config.tres").disconnect_grace
	for _i: int in range(int(grace * 60.0) + 10):
		Match._process(1.0 / 60.0)

	assert_true(Match.slot(1).home_flag_alive, "It came back, so it is never eliminated.")
	assert_eq(Match.disconnect_grace_left(1), -1.0)


func test_on_peer_left_is_ignored_on_a_client() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	Match.set_net_provider(FakeNet.client(1))

	Match.on_peer_left(0)

	assert_eq(Match.disconnect_grace_left(0), -1.0, "Only the host decides what a disconnect means.")


func test_an_intent_from_a_departed_peer_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match.on_peer_left(1)
	# P1 drops the peer from the registry as it goes.
	_fake_net.slots_by_peer.erase(2)

	net._handle_place_intent(2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, Match.feed_seq(1))

	assert_eq(_block_count(), 0, "An intent already in flight when its sender vanished is dropped.")


# --- Allocator exhaustion never reaches the wire (Bontago-mv0.1.7) ----------
#
# game/BlockRegistry.gd refuses to allocate past Quantize.NET_ID_MAX and
# leaves the block with net_id == -1; the body still lives and simulates on
# the host, but nothing about it may go out over replicate_spawn(), or a
# client would build a phantom copy no despawn could ever address (spec 3.4:
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


func test_a_client_ignores_a_spawn_whose_net_id_the_wire_cannot_carry() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)

	for bad_id: int in [-1, 0, Quantize.NET_ID_MAX + 1]:
		net.net_block_spawned(bad_id, &"cube", 1, Vector3(2.0, 3.0, 4.0), Quaternion.IDENTITY)

	assert_eq(
		_block_count(), 0,
		"A hostile or buggy host naming an id the wire cannot carry must build no phantom body."
	)
	assert_eq(net.replicated_block_count(), 0)


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


func test_a_diff_payload_with_a_ragged_body_decodes_to_nothing() -> void:
	var ragged: PackedByteArray = PackedByteArray([MatchNetScript.RASTER_VERSION, 0, 5, 0, 0, 0, 1, 2, 3, 4, 5])
	assert_true(MatchNetScript.decode_raster_payload(ragged, false).is_empty())


# --- Bontago-cmc.5: the replicated circle list ------------------------------


func test_encode_circles_matches_the_hosts_render_arrays() -> void:
	Match.set_net_provider(FakeNet.host({1: 0}, [0]))
	_start_playing()
	var net: MatchNetScript = _make_net({1: 0}, [0])

	var payload: PackedByteArray = net._encode_circles()
	var decoded: Dictionary = CircleWire.decode(
		payload, Match.circle_wire_xz_bound(), Match.circle_wire_radius_max()
	)

	assert_false(decoded.is_empty())
	var expected_xs: PackedFloat32Array = Match.circle_render_arrays()["xs"]
	assert_gt(expected_xs.size(), 0, "The players' home circles should already be live.")
	assert_eq(decoded["xs"].size(), expected_xs.size())
	assert_eq(decoded["teams"].size(), expected_xs.size())


func test_a_replicated_territory_packet_carries_the_circle_list_to_the_client() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var host_net: MatchNetScript = _make_net({}, [0])
	var circle_payload: PackedByteArray = host_net._encode_circles()
	var raster: TerritoryRaster = Match.raster()
	var raster_payload: PackedByteArray = host_net._encode_raster_full(
		raster.owner_bytes(), raster.state_bytes()
	)
	var expected_count: int = (Match.circle_render_arrays()["xs"] as PackedFloat32Array).size()
	assert_gt(expected_count, 0, "fixture should have live circles to carry over")

	var client_net: MatchNetScript = _make_net({}, [1], true)
	client_net.net_territory(
		raster_payload, true, PackedFloat32Array([0.5, 0.5]), -1, 0.0, circle_payload
	)

	assert_eq(
		Match.field().overlay().circle_count(),
		expected_count,
		"net_territory()'s circle_payload must reach the client's overlay."
	)


func test_a_missing_circle_payload_leaves_the_overlay_alone() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var host_net: MatchNetScript = _make_net({}, [0])
	var raster: TerritoryRaster = Match.raster()
	var raster_payload: PackedByteArray = host_net._encode_raster_full(
		raster.owner_bytes(), raster.state_bytes()
	)
	# Prime the overlay with a known circle count first, exactly as a
	# previous packet would have.
	Match.field().overlay().set_circles(
		PackedFloat32Array([1.0]), PackedFloat32Array([1.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), false
	)

	var client_net: MatchNetScript = _make_net({}, [1], true)
	# The 5-arg call an older build (or this file's own pre-cmc.5 tests) would
	# make: no circle_payload at all.
	client_net.net_territory(raster_payload, true, PackedFloat32Array([0.5, 0.5]), -1, 0.0)

	assert_eq(
		Match.field().overlay().circle_count(), 1,
		"An empty circle_payload must not clear a previously-applied circle list."
	)


# --- Replicated spawns and despawns on a client -----------------------------


func test_a_client_builds_a_frozen_body_bound_to_the_hosts_net_id() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_block_spawned(31, &"cube", 1, Vector3(2.0, 3.0, 4.0), Quaternion.IDENTITY)

	assert_eq(_block_count(), 1)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_eq(block.net_id, 31, "The host's id, not one the client invented.")
	assert_true(block.freeze, "Spec 3.4: a client freezes every synced body.")
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_KINEMATIC)
	assert_almost_eq(block.global_position.y, 3.0, 0.001)
	assert_signal_emitted(Events, "block_replicated")
	assert_eq(net.replicated_block_count(), 1)


func test_a_repeated_spawn_for_a_known_net_id_builds_nothing_extra() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	net.net_block_spawned(31, &"cube", 1, Vector3(2.0, 3.0, 4.0), Quaternion.IDENTITY)

	net.net_block_spawned(31, &"cube", 1, Vector3(9.0, 9.0, 9.0), Quaternion.IDENTITY)

	assert_eq(_block_count(), 1, "One net_id is one body, however often the host announces it.")


func test_a_despawn_for_an_unknown_net_id_is_a_safe_no_op() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)

	net.net_block_despawned(4242, "kill_plane")

	assert_eq(_block_count(), 0)


func test_a_replicated_despawn_removes_the_body() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	net.net_block_spawned(31, &"cube", 1, Vector3.ZERO, Quaternion.IDENTITY)
	watch_signals(Events)

	net.net_block_despawned(31, "kill_plane")

	assert_signal_emitted(Events, "block_removed")
	assert_eq(net.replicated_block_count(), 0)


# --- Bontago-mv0.1.13: start_match()'s own transient states are not --------
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


## Mirrors the bug's second scenario: a host restart from PLAYING/END (with a
## client connected) used to replicate the transient LOBBY plus LOADING/
## COUNTDOWN as separate EVENT_STATE_CHANGED RPCs interleaved with
## net_match_start, racing the client's own start. Reaches END the same way
## test_an_eliminated_slots_towers_lose_their_influence does (disconnect-grace
## elimination), then restarts on the same host_net a real restart would use.
func test_host_restart_from_end_replicates_no_transient_states_and_exactly_one_start() -> void:
	Match.set_net_provider(FakeNet.host({1: 0, 2: 1}, [0]))
	var host_net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing(2, 6.0)
	Match.on_peer_left(1)
	var grace: float = load("res://config/net_config.tres").disconnect_grace
	for _i: int in range(int(grace * 60.0) + 10):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.END, "fixture must reach END before the restart")

	host_net.replicated_state_changes.clear()
	host_net.match_starts_replicated = 0
	watch_signals(Events)

	Match.start_match(_config())

	assert_eq(
		host_net.replicated_state_changes, [],
		"the restart's own END->LOBBY->LOADING->COUNTDOWN must not replicate a second time"
	)
	assert_eq(host_net.match_starts_replicated, 1, "exactly one start for the restart")
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	# A real client's own net_match_start-triggered start_match() call would
	# produce exactly these same three transitions (END->LOBBY, LOBBY->
	# LOADING, LOADING->COUNTDOWN) and, since replicated_state_changes is
	# empty above, nothing else can arrive afterward to re-emit on top of it.
	assert_eq(get_signal_emit_count(Events, "match_state_changed"), 3)


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


## Bontago-mv0.10 follow-up: an early release does not restart the interval
## (spec 2.4), so the event that replicates it must carry the host's real
## remaining time and lock state rather than let apply_replicated_feed()
## assume a fresh config.block_timer -- otherwise a client's HUD ring jumps
## back to full for a piece it cannot yet release, and the client's own
## ghost never shows the locked tint net/PlayerController.gd's
## _update_ghost_tint() is capable of drawing.
func test_a_replicated_feed_event_with_interval_and_lock_sets_them_instead_of_resetting() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing(2, 6.0)
	for _i: int in range(60):
		Match._process(1.0 / 60.0)
	var net: MatchNetScript = _make_net({}, [1], true)

	net.net_match_event(MatchNetScript.EVENT_FEED_ISSUED, [1, &"cube", &"domino", 9, 4.25, true])

	assert_almost_eq(
		Match.feed_time_left(1), 4.25, 0.001,
		"the real remaining interval, not a reset to config.block_timer."
	)
	assert_true(Match.is_release_locked(1), "and the lock state.")


## An older sender (or this file's own test above) that only ever quotes the
## first four EVENT_FEED_ISSUED fields must keep working exactly as before --
## apply_replicated_feed()'s host_feed_time_left/host_is_locked default to
## "not sent" (-1.0 / false) so a short args array falls back to the
## pre-existing full-reset, unlocked behavior instead of misreading garbage.
func test_a_replicated_feed_event_without_the_new_fields_still_resets_the_timer() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing(2, 6.0)
	var net: MatchNetScript = _make_net({}, [1], true)

	net.net_match_event(MatchNetScript.EVENT_FEED_ISSUED, [1, &"cube", &"domino", 9])

	assert_almost_eq(
		Match.feed_time_left(1), 6.0, 0.001,
		"a short args array keeps the full-reset fallback."
	)
	assert_false(Match.is_release_locked(1))


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


func test_a_replicated_turn_is_mirrored_verbatim_in_hot_seat() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	Match.start_match(_hot_seat_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_TURN_CHANGED, [0])

	assert_signal_emitted_with_parameters(Events, "turn_changed", [0])


func _hot_seat_config() -> MatchConfig:
	var config: MatchConfig = _config()
	config.hot_seat = true
	return config


## Bontago-mv0.24 (owner test 2026-09-22): a relocated auto-drop's landing
## point mirrors to a client exactly like a rejection does -- decode side
## first (this test), matching test_a_replicated_elimination_is_applied_to_
## the_slot's own shape for EVENT_PLAYER_ELIMINATED below.
func test_a_replicated_relocation_re_emits_on_the_client() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_PLACEMENT_RELOCATED, [1, Vector2(3.0, -2.0)])

	assert_signal_emitted_with_parameters(Events, "placement_relocated", [1, Vector2(3.0, -2.0)])


func test_a_replicated_elimination_is_applied_to_the_slot() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)

	net.net_match_event(MatchNetScript.EVENT_PLAYER_ELIMINATED, [0, 0])

	assert_false(Match.slot(0).home_flag_alive)


func test_a_replicated_state_change_is_idempotent() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_STATE_CHANGED, [Match.State.PLAYING])

	assert_signal_not_emitted(
		Events, "match_state_changed", "A state the client already reached must not be re-emitted."
	)


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


# --- M4 P2b: EVENT_GIFT_CLAIMED's third argument (Orchestrator amendment 1) -

## Bontago-csc: the drawn special id must reach a client's Events.gift_claimed
## re-emit and its own queue verbatim, the same "the mirror holds exactly
## what the host sent" contract test_a_replicated_territory_packet... above
## proves for the raster.
func test_a_replicated_gift_claim_carries_all_three_args_to_the_client() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	# M4 P2c-ii tightens the wire check to roster membership; this checkout's
	# res://config/specials/ is empty (P3-P5 not landed), so the test fakes a
	# roster entry rather than writing a real .tres this package does not own.
	net.set_special_roster_for_test([&"jumping_bean"])
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [3, 1, &"jumping_bean"])

	assert_signal_emitted_with_parameters(Events, "gift_claimed", [3, 1, &"jumping_bean"])
	assert_eq(Match.held_special(1), &"jumping_bean", "a client's queue after replication must match the host's drawn id")


## net/MatchNet.gd's _special_id_wire_ok(): empty, over-length (40 chars) and
## non-[A-Za-z0-9_] (a space) payloads are all dropped -- mirrors
## test_gift_claim.gd's test_gift_wire_rejects_malformed_payloads for
## EVENT_GIFT_SPAWNED's own position check.
func test_a_malformed_special_id_is_dropped_not_applied() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [4, 1, &""])
	assert_signal_not_emitted(Events, "gift_claimed", "an empty special_id must be dropped")
	assert_eq(Match.held_special(1), &"", "and never queued")

	var too_long: String = "a".repeat(40)
	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [5, 1, StringName(too_long)])
	assert_signal_not_emitted(Events, "gift_claimed", "a 40-character special_id must be dropped")
	assert_eq(Match.held_special(1), &"")

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [6, 1, &"has space"])
	assert_signal_not_emitted(Events, "gift_claimed", "a special_id with a space must be dropped")
	assert_eq(Match.held_special(1), &"")


## Two claims replicate in order; the client's FIFO after both matches the
## host's claim order exactly.
func test_a_clients_queue_after_replication_matches_the_hosts_claim_order() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	# See test_a_replicated_gift_claim_carries_all_three_args_to_the_client's
	# own comment on why this fakes a roster.
	net.set_special_roster_for_test([&"special_a", &"special_b"])

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [10, 1, &"special_a"])
	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [11, 1, &"special_b"])

	assert_eq(Match.pending_special_count(1), 2)
	assert_eq(Match.pop_pending_special(1), &"special_a")
	assert_eq(Match.pop_pending_special(1), &"special_b")


## M4 P2c-ii: gift_claimed's roster-membership tightening (orchestrator
## amendment 1's "P2c tightens it to roster membership"). res://config/
## specials/ is empty in this checkout (P3-P5 not landed), so only
## MatchGifts.PENDING_SPECIAL_ID -- the default drawer's placeholder -- may
## ever pass without a faked roster.
func test_an_unknown_special_id_is_dropped_but_the_placeholder_passes() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [7, 1, &"totally_unknown"])
	assert_signal_not_emitted(
		Events, "gift_claimed", "an id that is neither the placeholder nor in the roster must be dropped"
	)
	assert_eq(Match.held_special(1), &"")

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [8, 1, MatchGifts.PENDING_SPECIAL_ID])
	assert_signal_emitted_with_parameters(
		Events, "gift_claimed", [8, 1, MatchGifts.PENDING_SPECIAL_ID]
	)
	assert_eq(Match.held_special(1), MatchGifts.PENDING_SPECIAL_ID)


## A real (faked) roster member must pass even though it is not the
## placeholder -- proves _known_special_ids() is actually consulted, not just
## the placeholder special-case.
func test_a_faked_roster_member_special_id_passes_the_tightened_check() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	net.set_special_roster_for_test([&"volcano"])
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [9, 1, &"volcano"])

	assert_signal_emitted_with_parameters(Events, "gift_claimed", [9, 1, &"volcano"])
	assert_eq(Match.held_special(1), &"volcano")


# --- M4 P2c-ii: request_throw over the wire ---------------------------------


func test_submit_throw_on_the_host_spawns_and_launches_the_block_inline() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match._gifts.apply_replicated_claim(1, 0, MatchGifts.PENDING_SPECIAL_ID)
	var velocity: Vector3 = Vector3(3.0, 0.0, 4.0)

	var before: int = _block_count()
	var reason: StringName = net.submit_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, velocity, Match.feed_seq(0)
	)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_block_count(), before + 1, "The host's own throw must spawn inline, with no round trip.")
	assert_eq(net.intents_accepted(0), 1)
	assert_eq(net.intents_sent(0), 1)
	var block: Block = _blocks_root.get_child(_block_count() - 1) as Block
	assert_eq(
		block.linear_velocity, velocity,
		"under throw_max_speed the host's clamp is a no-op, so the velocity passes through untouched"
	)


func test_a_throw_intent_for_someone_elses_slot_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match._gifts.apply_replicated_claim(1, 0, MatchGifts.PENDING_SPECIAL_ID)

	# Peer 2 holds slot 1 but claims slot 0, exactly like the matching
	# placement test above.
	net._handle_throw_intent(
		2, 0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0), Match.feed_seq(0)
	)

	assert_eq(_block_count(), 0, "Nothing may be thrown for a slot the sender does not hold.")
	assert_eq(net.intents_accepted(0), 0)
	assert_eq(net.intents_refused(1), 1, "The refusal is counted against the sender's own slot.")
	assert_eq(net.intents_sent(1), 1)


func test_a_throw_intent_with_a_non_finite_velocity_is_dropped() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match._gifts.apply_replicated_claim(1, 0, MatchGifts.PENDING_SPECIAL_ID)

	net._handle_throw_intent(
		1, 0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(NAN, 0.0, 0.0), Match.feed_seq(0)
	)

	assert_eq(_block_count(), 0, "A non-finite velocity must never reach Match.request_throw().")
	assert_eq(net.intents_refused(0), 1)
	assert_eq(
		Match.held_special(0), MatchGifts.PENDING_SPECIAL_ID,
		"the pending special is still held, not spent, by a refused throw"
	)


func test_a_remote_peers_own_throw_intent_is_accepted_with_velocity_untouched() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match._gifts.apply_replicated_claim(1, 1, MatchGifts.PENDING_SPECIAL_ID)
	var velocity: Vector3 = Vector3(2.0, 0.0, -1.0)

	net._handle_throw_intent(
		2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, velocity, Match.feed_seq(1)
	)

	assert_eq(_block_count(), 1)
	assert_eq(net.intents_accepted(1), 1)
	assert_eq(net.intents_refused(1), 0)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_eq(
		block.linear_velocity, velocity,
		"under throw_max_speed, MatchPlacement.request_throw() must not alter it"
	)


## Review NIT: a remote throw intent quoting the -1 "don't check" sentinel
## must be refused at the wire boundary -- _handle_throw_intent()'s own
## `feed_seq < 0` branch, exactly the one _handle_place_intent() takes (see
## that function's own matching comment on why -1 is a trusted-local-caller-
## only courtesy that must never arrive from the wire).
func test_a_negative_feed_seq_on_a_throw_intent_is_refused_at_the_wire_like_place() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	Match._gifts.apply_replicated_claim(1, 1, MatchGifts.PENDING_SPECIAL_ID)

	net._handle_throw_intent(
		2, 1, _home_world_position(1), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0), -1
	)

	assert_eq(_block_count(), 0, "A negative feed_seq from the wire must be refused, not treated as 'don't check'.")
	assert_eq(net.intents_refused(1), 1)
	assert_eq(Match.held_special(1), MatchGifts.PENDING_SPECIAL_ID, "nothing was consumed by the refusal")


## Review NIT: once a real (non-negative) feed_seq is stale -- the host has
## moved the slot on since the sender last saw it -- request_throw() refuses
## it itself (MatchPlacement.request_throw()'s own feed_seq check, which runs
## before its held_special() check), the same branch request_place() takes
## for a stale place. Mirrors test_a_stale_feed_seq_is_refused() above.
func test_a_stale_feed_seq_on_a_throw_intent_is_refused() -> void:
	var net: MatchNetScript = _make_net({1: 0, 2: 1}, [0])
	_start_playing()
	var stale: int = Match.feed_seq(0)
	Match._gifts.apply_replicated_claim(1, 0, MatchGifts.PENDING_SPECIAL_ID)

	net.submit_throw(0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0), stale)
	# The feed has moved on (the throw above consumed it); the sender still
	# quotes the sequence it saw before that first throw.
	var reason: StringName = net.submit_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0), stale
	)

	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_block_count(), 1)


# --- M4 P2c-ii: EVENT_SPECIAL_TRIGGERED replication -------------------------


func test_a_replicated_special_trigger_reemits_with_all_four_args() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(
		MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano", Vector3(1.0, 2.0, 3.0), 2]
	)

	assert_signal_emitted_with_parameters(
		Events, "special_triggered", [31, &"volcano", Vector3(1.0, 2.0, 3.0), 2]
	)


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

	var over_cap: int = int((load("res://config/special_tuning.tres") as SpecialTuning).max_chain_depth) + 1
	net.net_match_event(
		MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano", Vector3.ZERO, over_cap]
	)
	assert_signal_not_emitted(Events, "special_triggered", "chain_depth over the cap must be dropped")

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano", Vector3.ZERO, -1])
	assert_signal_not_emitted(Events, "special_triggered", "a negative chain_depth must be dropped")


## Review fix (Should #1): a short args array (an older or malformed sender,
## missing position/chain_depth) must be dropped before net_match_event ever
## reads past args[1] -- mirrors EVENT_GIFT_CLAIMED's own args.size() guard
## and, without this check, would have read args[2]/args[3] out of bounds.
func test_a_short_special_trigger_args_array_is_dropped_not_applied() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [31, &"volcano"])

	assert_signal_not_emitted(
		Events, "special_triggered", "a short args array must be dropped, not read past its end"
	)


# --- Bontago-1en.21: EVENT_SPECIAL_CONSUMED replication ---------------------

## The bug this package fixes: a client's own pending_special_count() must
## shrink in step with the host's real pop, not just grow at claim time. See
## MatchGifts.apply_replicated_special_consumed()'s own doc comment for the
## mirror mismatch handling this dispatch relies on.
func test_a_replicated_special_consumed_decrements_the_clients_pending_count_and_reemits() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	Match._gifts.apply_replicated_claim(20, 1, MatchGifts.PENDING_SPECIAL_ID)
	assert_eq(Match.pending_special_count(1), 1, "setup: the client's mirror queue must hold the claimed special")
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_CONSUMED, [1, MatchGifts.PENDING_SPECIAL_ID])

	assert_eq(Match.pending_special_count(1), 0, "the mirror must shrink in step with the host's own pop")
	assert_signal_emitted_with_parameters(Events, "special_consumed", [1, MatchGifts.PENDING_SPECIAL_ID])


## Mirrors EVENT_GIFT_CLAIMED's/EVENT_SPECIAL_TRIGGERED's own malformed-payload
## tests: an out-of-range slot_id, a malformed special_id shape, and a short
## args array must all be dropped without ever touching the mirror queue.
func test_a_malformed_special_consumed_is_dropped_not_applied() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_playing()
	var net: MatchNetScript = _make_net({}, [1], true)
	Match._gifts.apply_replicated_claim(21, 1, MatchGifts.PENDING_SPECIAL_ID)
	assert_eq(Match.pending_special_count(1), 1, "setup")
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_CONSUMED, [999999999, MatchGifts.PENDING_SPECIAL_ID])
	assert_signal_not_emitted(Events, "special_consumed", "an out-of-range slot_id must be dropped")
	assert_eq(Match.pending_special_count(1), 1, "and the mirror must be untouched")

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_CONSUMED, [1, &"has space"])
	assert_signal_not_emitted(Events, "special_consumed", "a malformed special_id must be dropped")
	assert_eq(Match.pending_special_count(1), 1)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_CONSUMED, [1])
	assert_signal_not_emitted(
		Events, "special_consumed", "a short args array must be dropped, not read past its end"
	)
	assert_eq(Match.pending_special_count(1), 1)


## DECISION (net/MatchNet.gd, Bontago-1en.21): the host must never apply this
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
