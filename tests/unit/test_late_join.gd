extends GutTest
## Bontago-8or.11 (spec 3.4 "Late join / reconnect", docs/M8_PLAN.md P6):
## mid-match admission, the ordered world replay, the replay-ack intent gate
## and reconnect inside the disconnect grace.
##
## Two halves, because one process has one Match singleton and one Events
## bus (a second in-process Match would see every block_placed/spawn the
## first one emits):
## - the replay itself runs host-then-client on the real Match: MatchNet's
##   capture seam records the exact ordered rpc_id() messages, the host world
##   is snapshotted, then Match turns client and the messages are applied in
##   order to a client-mode MatchNet -- the same calls the RPC layer makes;
## - admission (open seat / spectator / refusal / reconnect) runs over real
##   ENet between independent Net nodes, test_net_session.gd's pattern.

const MatchNetScript := preload("res://net/MatchNet.gd")
const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _map: MapDef
var _nets: Array[MatchNetScript] = []
var _sessions: Array[Variant] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_nets.clear()
	_sessions.clear()


func after_each() -> void:
	for net: MatchNetScript in _nets:
		if net != null and is_instance_valid(net):
			net.set_providers(null, null)
	_nets.clear()
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	for session: Variant in _sessions:
		if session != null and is_instance_valid(session):
			session.leave()
	_sessions.clear()
	# Net._reject_peer() closes a refused connection two frames later.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Fixtures -----------------------------------------------------------------

## A real Field/registry/blocks root registered with Match. `map` is a real
## preset (not TinyMapMatchConfig's seam) whenever the test replays
## net_match_start, because the client decodes a plain MatchConfig from the
## wire and must build the very same raster the host has.
func _build_world(map: MapDef) -> void:
	_map = map
	_field = Field.new()
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = Node3D.new()
	add_child_autofree(_blocks_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _make_net(session: FakeNet) -> MatchNetScript:
	Match.set_net_provider(session)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(session, Match)
	_nets.append(node)
	return node


func _config(player_count: int, mode: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.map_variant = MatchConfig.MapVariant.ROUND
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = player_count
	config.ai_count = 0
	config.team_mode = MatchConfig.TeamMode.OFF
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.game_mode = mode
	config.round_timer_minutes = 5
	config.allow_mid_match_join = true
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


func _home(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 0.0, home.y))


func _live_blocks() -> Dictionary:
	var by_id: Dictionary = {}
	for block: Block in Match.registry().all_blocks():
		if block.is_queued_for_deletion():
			continue
		by_id[block.net_id] = block
	return by_id


func _methods(capture: Array[Array]) -> Array[StringName]:
	var methods: Array[StringName] = []
	for entry: Array in capture:
		methods.append(StringName(entry[1]))
	return methods


# --- The replay: the joiner's world matches the host's ---------------------------

func test_the_joiners_world_matches_the_host_after_the_replay() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var host_net: MatchNetScript = _make_net(host_session)
	_start_playing(_config(4, MatchConfig.GameMode.ELIMINATION))

	# A world worth replaying: two blocks (one Paintball-converted), slot 2
	# eliminated, a queued gift for the open seat, glue, a falling and a
	# landed crate, a solved raster and a running round clock.
	assert_eq(host_net.submit_place(0, _home(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0)), PlacementRules.REASON_OK)
	host_net._handle_place_intent(2, 1, _home(1), 0, Quaternion.IDENTITY, Match.feed_seq(1))
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	Match._territory.flush_pending()
	var blocks_before: Dictionary = _live_blocks()
	assert_eq(blocks_before.size(), 2, "fixture placed two blocks")
	var converted: Block = blocks_before[blocks_before.keys().min()] as Block
	assert_true(_registry.convert_owner(converted, 1, Color.BLUE), "fixture converts one block")
	Match._lifecycle._eliminate_slot(2)
	Match._lifecycle._check_last_team_standing()
	assert_eq(Match.state(), Match.State.PLAYING, "three teams remain, the match runs on")
	Match._gifts._queue_claimed_special(3, MatchGifts.PENDING_SPECIAL_ID)
	assert_true(Match._gifts.grant_glue_drops(1, 3))
	Match._gifts._spawn_crate_at(Vector2(2.0, 1.0))
	Match._gifts._spawn_crate_at(Vector2(-3.0, 2.0))
	(Match._gifts._crates[1] as Dictionary)["phase"] = MatchGifts.LANDED

	# The new joiner takes the lowest open human seat: 2 is eliminated, 3 is free.
	assert_eq(host_net.pick_open_seat(), 3)
	host_session.slots_by_peer[3] = 3

	host_net.capture_replay = true
	host_net._on_net_peer_joined(3, 3, "Latey")
	assert_true(host_net.replay_pending_for(3), "the joiner owes an ack")

	# What the host holds at replay time, read in the same frame: the bodies
	# keep simulating once a frame passes, the rest only moves with
	# Match._process (off in this fixture).
	var expected_blocks: Dictionary = {}
	var host_blocks: Dictionary = _live_blocks()
	for net_id: int in host_blocks.keys():
		var block: Block = host_blocks[net_id] as Block
		expected_blocks[net_id] = [
			block.global_position, block.global_basis.get_rotation_quaternion(), block.owner_slot, block.shape_id,
		]
	var expected_owners: PackedByteArray = Match.raster().owner_bytes().duplicate()
	var expected_states: PackedByteArray = Match.raster().state_bytes().duplicate()
	var expected_mode: Dictionary = Match.mode_state_snapshot()
	var expected_timer: float = Match.match_timer_left()
	var expected_seq: int = Match.feed_seq(3)
	var expected_held: StringName = Match.held_shape(3).id
	var expected_gifts: Array[Dictionary] = Match.gift_states()
	assert_lt(expected_owners.count(0), expected_owners.size(), "the host raster owns cells")
	assert_gt(expected_timer, 0.0, "the round clock is running")
	assert_false(expected_mode.is_empty(), "elimination replicates its state")
	await get_tree().process_frame

	# The wire order: config + roster first, then every body, then the raster,
	# then derived state, and the end marker last of all.
	var capture: Array[Array] = host_net.replay_capture.duplicate()
	var methods: Array[StringName] = _methods(capture)
	assert_eq(methods[0], &"net_match_start", "the replay opens with config + roster")
	assert_eq(methods.count(&"net_block_spawned"), 2, "one spawn per body")
	assert_eq(methods[1], &"net_block_spawned", "bodies right after the config")
	assert_eq(methods[3], &"net_territory", "then one territory keyframe")
	assert_eq(methods[methods.size() - 1], &"net_replay_end", "the end marker is last")
	for entry: Array in capture:
		assert_eq(int(entry[0]), 3, "every message is addressed to the joiner alone")
	var spawn_args: Array = capture[1][2]
	assert_eq(spawn_args.size(), 6, "the replay spawn uses replicate_spawn's six-argument wire shape")

	# The joiner: Match becomes a client and the replay is applied in order.
	host_net.queue_free()
	await get_tree().process_frame
	var client_session: FakeNet = FakeNet.client(3)
	var client_net: MatchNetScript = _make_net(client_session)
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	for entry: Array in capture:
		client_net.callv(StringName(entry[1]), entry[2] as Array)

	assert_eq(Match.state(), Match.State.PLAYING, "the joiner is in the host's state")
	var client_blocks: Dictionary = _live_blocks()
	assert_eq(client_blocks.size(), expected_blocks.size(), "same body count")
	for net_id: int in expected_blocks.keys():
		var block: Block = client_blocks.get(net_id) as Block
		assert_not_null(block, "body %d replayed" % net_id)
		if block == null:
			continue
		var want: Array = expected_blocks[net_id]
		assert_lt(block.global_position.distance_to(want[0] as Vector3), 0.001, "position of %d" % net_id)
		assert_lt(block.global_basis.get_rotation_quaternion().angle_to(want[1] as Quaternion), 0.001, "rotation of %d" % net_id)
		assert_eq(block.owner_slot, int(want[2]), "current owner of %d" % net_id)
		assert_eq(block.shape_id, StringName(want[3]))
		assert_true(block.freeze, "a client body is kinematic")
	assert_eq(Match.raster().owner_bytes(), expected_owners, "territory owner bytes match")
	assert_eq(Match.raster().state_bytes(), expected_states, "territory state bytes match")
	var mode: Dictionary = Match.mode_state_snapshot()
	assert_eq(mode.get("scores"), expected_mode.get("scores"), "mode scores match")
	assert_eq(mode.get("extra"), expected_mode.get("extra"), "mode extra state matches")
	assert_almost_eq(Match.match_timer_left(), expected_timer, 0.0001, "the round clock matches")
	assert_false(Match.slot(2).home_flag_alive, "the eliminated slot is out on the joiner too")
	assert_true(Match.slot(3).home_flag_alive)
	assert_eq(Match.feed_seq(3), expected_seq, "the joiner quotes the host's feed sequence")
	assert_eq(Match.held_shape(3).id, expected_held, "and holds the host's piece")
	assert_eq(Match.next_special(3), MatchGifts.PENDING_SPECIAL_ID, "its queued gift survived")
	assert_eq(Match.glue_drops_left(1), 3, "glue charges replayed")
	var gifts: Array[Dictionary] = Match.gift_states()
	assert_eq(gifts.size(), expected_gifts.size(), "every crate replayed")
	for i: int in range(mini(gifts.size(), expected_gifts.size())):
		assert_eq(gifts[i]["id"], expected_gifts[i]["id"])
		assert_eq(gifts[i]["phase"], expected_gifts[i]["phase"], "falling stays falling, landed stays landed")
	assert_eq(client_net.last_replay_acknowledged, int(capture[capture.size() - 1][2][0]), "the joiner acknowledged its replay")


func test_a_client_drops_gameplay_broadcasts_until_its_replay_starts() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	_make_net(host_session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	var client_net: MatchNetScript = _make_net(FakeNet.client(1))
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	watch_signals(Events)

	client_net.net_block_spawned(31, &"cube", 1, Vector3(2.0, 3.0, 4.0), Quaternion.IDENTITY)
	client_net.net_match_event(MatchNetScript.EVENT_STATE_CHANGED, [Match.State.END])

	assert_null(Match.registry().block_for_net_id(31), "a spawn broadcast before the replay is not applied")
	assert_signal_not_emitted(Events, "match_state_changed", "nor is a state change")
	assert_eq(client_net.last_replay_acknowledged, 0)


func _frozen_fixture_block(net_id: int) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, load("res://config/physics_tuning.tres"), 0, Match.slot(0).color)
	_blocks_root.add_child(block)
	Events.block_placed.emit(block, shape.id)
	_registry.bind_net_id(block, net_id)
	return block


func test_a_frozen_overlay_replays_after_the_blocks_and_before_the_end() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var host_net: MatchNetScript = _make_net(host_session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	var iced: Block = _frozen_fixture_block(201)
	var plain: Block = _frozen_fixture_block(202)
	iced.set_frozen_visual(true)
	host_net.capture_replay = true
	host_net._on_net_peer_joined(2, 1, "Latey")
	await get_tree().process_frame
	var capture: Array[Array] = host_net.replay_capture.duplicate()
	var last_spawn: int = -1
	var frozen_at: int = -1
	var frozen_count: int = 0
	for i: int in range(capture.size()):
		var method: StringName = StringName(capture[i][1])
		if method == &"net_block_spawned":
			last_spawn = i
		elif method == &"net_match_event" and StringName((capture[i][2] as Array)[0]) == MatchNetScript.EVENT_BLOCK_FROZEN:
			frozen_at = i
			frozen_count += 1
			assert_eq((capture[i][2] as Array)[1], [201, true])
	assert_eq(frozen_count, 1, "only the iced body replays an overlay")
	assert_gt(frozen_at, last_spawn, "after every spawn")
	assert_lt(frozen_at, capture.size() - 1, "before net_replay_end")
	assert_eq(StringName(capture[capture.size() - 1][1]), &"net_replay_end")
	assert_false(plain.is_frozen_visual())

	# The joiner ends up with the overlay.
	host_net.queue_free()
	await get_tree().process_frame
	var client_net: MatchNetScript = _make_net(FakeNet.client(2))
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	for entry: Array in capture:
		client_net.callv(StringName(entry[1]), entry[2] as Array)
	var joined_block: Block = Match.registry().block_for_net_id(201)
	assert_not_null(joined_block)
	if joined_block != null:
		assert_true(joined_block.is_frozen_visual(), "the icy overlay reached the late joiner")


func test_replay_size_for_three_hundred_blocks() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var host_net: MatchNetScript = _make_net(FakeNet.host({1: 0, 2: 1}, [0]))
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	for i: int in range(300):
		_frozen_fixture_block(1000 + i)
	var largest: int = 0
	var total: int = 0
	for message: Array in host_net.build_world_replay():
		var size: int = var_to_bytes(message[1]).size()
		total += size
		largest = maxi(largest, size)
	gut.p("replay for 300 blocks: %d bytes total, largest single message %d bytes" % [total, largest])
	assert_lt(largest, 20000, "no single replay message is large enough to need chunking")
	assert_lt(total, 100000, "the whole replay stays well under 100 KB")


func test_an_unacked_replay_times_out_and_drops_the_peer() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var net: MatchNetScript = _make_net(session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	net.capture_replay = true
	net._on_net_peer_joined(2, 1, "Latey")
	assert_true(net.replay_pending_for(2))
	net._tick_replay_timeouts(net.config.replay_ack_timeout * 0.5)
	assert_true(net.replay_pending_for(2), "still waiting inside the timeout")
	assert_eq(session.kick_peer_calls.size(), 0)
	net._tick_replay_timeouts(net.config.replay_ack_timeout)
	assert_false(net.replay_pending_for(2), "the gate no longer holds a dead peer")
	assert_eq(net.replays_timed_out, 1)
	assert_eq(session.kick_peer_calls.size(), 1)
	assert_eq(int(session.kick_peer_calls[0]["peer_id"]), 2)


func test_an_acked_replay_does_not_time_out() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var net: MatchNetScript = _make_net(session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	net.capture_replay = true
	net._on_net_peer_joined(2, 1, "Latey")
	await get_tree().process_frame
	var replay_id: int = int((net.replay_capture[net.replay_capture.size() - 1][2] as Array)[0])
	net._handle_replay_ack(2, replay_id)
	net._tick_replay_timeouts(net.config.replay_ack_timeout * 10.0)
	assert_eq(net.replays_timed_out, 0)
	assert_eq(session.kick_peer_calls.size(), 0)


func test_weather_traffic_before_the_world_is_gated() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var net: MatchNetScript = _make_net(FakeNet.client(1))
	net._on_net_mode_changed(Net.Mode.CLIENT)
	var weather_net: WeatherNet = net._weather_net
	assert_true(weather_net._is_awaiting_world(), "awaiting the world")
	var refused_before: int = weather_net.states_refused
	weather_net.net_weather_state({})
	assert_eq(weather_net.states_refused, refused_before + 1)
	var snow_net: SnowNet = weather_net.get_node("SnowNet") as SnowNet
	var snow_refused: int = snow_net.states_refused
	snow_net.net_snow_state({})
	assert_eq(snow_net.states_refused, snow_refused + 1)
	net.net_match_start(_config(2, MatchConfig.GameMode.CLASSIC).to_dict(), [])
	assert_false(weather_net._is_awaiting_world(), "open once net_match_start landed")


func test_rejoin_token_is_scoped_to_its_host_and_cleared_on_leave() -> void:
	var client: Variant = _make_side("TokenNet")
	client._rejoin_token = "abc"
	client._rejoin_scope = "enet:127.0.0.1:5000"
	client._join_scope = "enet:127.0.0.1:5000"
	assert_eq(client.quoted_rejoin_token(), "abc", "the issuing host sees it")
	client._join_scope = "enet:127.0.0.1:6000"
	assert_eq(client.quoted_rejoin_token(), "", "another host never does")
	client._join_scope = "enet:10.0.0.2:5000"
	assert_eq(client.quoted_rejoin_token(), "", "nor another address")
	client.leave(false)
	assert_eq(client.rejoin_token(), "abc", "a connection loss keeps it")
	client.leave()
	assert_eq(client.rejoin_token(), "", "a deliberate leave forgets it")
	assert_eq(client._rejoin_scope, "")


# --- The intent gate ------------------------------------------------------------

func test_intents_before_the_replay_ack_are_refused() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var session: FakeNet = FakeNet.host({1: 0, 2: 1, 3: 2}, [0])
	var net: MatchNetScript = _make_net(session)
	_start_playing(_config(3, MatchConfig.GameMode.CLASSIC))
	net.capture_replay = true
	net._on_net_peer_joined(3, 2, "Latey")
	await get_tree().process_frame
	var end_marker: Array = net.replay_capture[net.replay_capture.size() - 1]
	assert_eq(StringName(end_marker[1]), &"net_replay_end")
	var replay_id: int = int((end_marker[2] as Array)[0])
	var blocks_before: int = _live_blocks().size()

	net._handle_place_intent(3, 2, _home(2), 0, Quaternion.IDENTITY, Match.feed_seq(2))
	net._handle_throw_intent(3, 2, _home(2), 0, Quaternion.IDENTITY, Vector3.UP, Match.feed_seq(2))
	net._handle_cursor_update(3, 2, _home(2), 0, Quaternion.IDENTITY)
	assert_eq(_live_blocks().size(), blocks_before, "nothing spawns for an unreplayed peer")
	assert_eq(net.intents_refused_before_replay_ack, 2)
	assert_eq(net.intents_refused(2), 2, "counted as refusals, so sent == accepted + refused")
	assert_true(net.cursor_for_slot(2).is_empty(), "its cursor is not stored for auto-drop")

	net._handle_replay_ack(3, replay_id + 1)
	assert_true(net.replay_pending_for(3), "a forged or stale ack is ignored")
	net._handle_replay_ack(2, replay_id)
	assert_true(net.replay_pending_for(3), "another peer cannot ack for it")
	net._handle_replay_ack(3, replay_id)
	assert_false(net.replay_pending_for(3), "the right ack lifts the gate")
	assert_eq(net.replays_acknowledged, 1)

	net._handle_place_intent(3, 2, _home(2), 0, Quaternion.IDENTITY, Match.feed_seq(2))
	assert_eq(_live_blocks().size(), blocks_before + 1, "after the ack its intent is acted on")


func test_a_peer_that_leaves_mid_replay_owes_no_ack() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var net: MatchNetScript = _make_net(FakeNet.host({1: 0, 2: 1}, [0]))
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	net.capture_replay = true
	net._on_net_peer_joined(2, 1, "Latey")
	net._on_net_peer_left(2, 1, Net.LeaveReason.TIMEOUT)
	await get_tree().process_frame
	assert_false(net.replay_pending_for(2))
	assert_false(_methods(net.replay_capture).has(&"net_replay_end"), "no end marker for a departed peer")


# --- Seats -------------------------------------------------------------------------

func test_no_free_seat_means_spectator_and_a_reserved_seat_is_not_free() -> void:
	_build_world(load("res://config/maps/round_small.tres") as MapDef)
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var net: MatchNetScript = _make_net(session)
	_start_playing(_config(3, MatchConfig.GameMode.CLASSIC))
	assert_eq(net.pick_open_seat(), 2, "slot 2 has no peer")

	Match.on_peer_left(2)
	assert_eq(net.pick_open_seat(), -1, "a slot inside its grace is reserved for its owner")
	assert_true(net.seat_reclaimable(2), "but its owner may reclaim it")
	assert_false(net.seat_reclaimable(1), "a connected slot is not reclaimable")

	session.slots_by_peer[3] = 2
	Match.on_peer_rejoined(2)
	assert_eq(net.pick_open_seat(), -1, "every human seat taken: the joiner spectates")

	Match.abort_match()
	assert_eq(net.pick_open_seat(), -1, "no seat outside a live match")
	assert_false(net.seat_reclaimable(2))


func test_allow_mid_match_join_round_trips_and_rejects_a_non_bool() -> void:
	var config: MatchConfig = MatchConfig.new()
	assert_false(config.allow_mid_match_join, "off by default")
	config.allow_mid_match_join = true
	assert_true(MatchConfig.from_dict(config.to_dict()).allow_mid_match_join)
	var data: Dictionary = config.to_dict()
	data["allow_mid_match_join"] = "false"
	assert_false(MatchConfig.from_dict(data).allow_mid_match_join, "a String is not a bool")


# --- Admission over ENet -----------------------------------------------------------

func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	_sessions.append(node)
	return node


func _wait_until(condition: Callable, frames: int = 200) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## A host with one seated client in slot 1, then the match starts.
func _host_with_client(seat: Callable, reclaimable: Callable) -> Array[Variant]:
	var host: Variant = _make_side("HostNet")
	var client: Variant = _make_side("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	# Loopback only and never advertised; accepting is switched back on by hand.
	assert_eq(host.host_game(port, "Hostie", false), OK)
	host.set_accepting_joins(true)
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var joined: bool = await _wait_until(func() -> bool: return client.local_slot() == 1)
	assert_true(joined, "the lobby fills normally first")
	host.set_seat_policy(seat, reclaimable)
	host.set_match_in_progress(true)
	return [host, client, port]


func test_allow_mid_match_join_false_refuses_a_new_joiner() -> void:
	var sides: Array[Variant] = await _host_with_client(func() -> int: return 2, func(_s: int) -> bool: return true)
	var host: Variant = sides[0]
	host.set_accepting_joins(false)
	var late: Variant = _make_side("LateNet")
	watch_signals(Events)
	assert_eq(late.join_game("127.0.0.1", int(sides[2]), "Latey"), OK)
	var refused: bool = await _wait_until(func() -> bool: return get_signal_emit_count(Events, "net_join_failed") > 0)
	assert_true(refused)
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.MATCH_IN_PROGRESS)
	assert_eq(host.peer_ids().size(), 2, "nobody new was seated")


func test_a_mid_match_joiner_takes_the_open_seat() -> void:
	var sides: Array[Variant] = await _host_with_client(func() -> int: return 2, func(_s: int) -> bool: return false)
	var host: Variant = sides[0]
	host.set_accepting_joins(true)
	var late: Variant = _make_side("LateNet")
	assert_eq(late.join_game("127.0.0.1", int(sides[2]), "Latey"), OK)
	var seated: bool = await _wait_until(func() -> bool: return late.local_slot() == 2)
	assert_true(seated, "the joiner is told its seat")
	assert_eq(host.slot_of_peer(late.local_peer_id()), 2)
	assert_ne(late.rejoin_token(), "", "and holds a rejoin token")


func test_a_mid_match_joiner_with_no_free_seat_spectates() -> void:
	var sides: Array[Variant] = await _host_with_client(func() -> int: return -1, func(_s: int) -> bool: return false)
	var host: Variant = sides[0]
	host.set_accepting_joins(true)
	var late: Variant = _make_side("LateNet")
	watch_signals(Events)
	assert_eq(late.join_game("127.0.0.1", int(sides[2]), "Latey"), OK)
	var seated: bool = await _wait_until(func() -> bool: return late.local_slot() == -1 and host.peer_ids().size() == 3)
	assert_true(seated, "the joiner is seated as a spectator")
	assert_eq(host.slot_of_peer(late.local_peer_id()), -1)
	assert_eq(host.peer_of_slot(-1), -1, "a spectator holds no seat")
	assert_false(late.is_local_slot(-1), "and no slot is its own")
	host.set_match_in_progress(false)
	var reseated: bool = await _wait_until(func() -> bool: return late.local_slot() >= 2)
	assert_true(reseated, "back in the lobby it gets a real slot for the next match")


func test_reconnect_within_grace_restores_the_slot() -> void:
	var reclaim_ok: Array[bool] = [true]
	var sides: Array[Variant] = await _host_with_client(
		func() -> int: return -1, func(_s: int) -> bool: return reclaim_ok[0]
	)
	var host: Variant = sides[0]
	var client: Variant = sides[1]
	var port: int = int(sides[2])
	host.set_accepting_joins(false)
	var token: String = client.rejoin_token()
	assert_ne(token, "")
	var old_id: int = client.local_peer_id()

	client.leave(false)
	var gone: bool = await _wait_until(func() -> bool: return host.peer_ids().size() == 1)
	assert_true(gone, "the host saw the drop")
	assert_eq(client.rejoin_token(), token, "the token survives a connection loss")

	# A stranger cannot have it: mid-match joins are off here.
	var stranger: Variant = _make_side("StrangerNet")
	watch_signals(Events)
	assert_eq(stranger.join_game("127.0.0.1", port, "Strangey"), OK)
	var refused: bool = await _wait_until(func() -> bool: return get_signal_emit_count(Events, "net_join_failed") > 0)
	assert_true(refused, "a new peer is refused while mid-match joins are off")

	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var back: bool = await _wait_until(func() -> bool: return client.mode() == Net.Mode.CLIENT and client.local_slot() == 1)
	assert_true(back, "the returning player has its slot back")
	assert_ne(client.local_peer_id(), old_id, "under a new transport id")
	assert_eq(host.slot_of_peer(client.local_peer_id()), 1)
	assert_eq(client.rejoin_token(), token, "with the same token for a second drop")

	# Past the grace the reservation is worthless.
	client.leave(false)
	await _wait_until(func() -> bool: return host.peer_ids().size() == 1)
	reclaim_ok[0] = false
	var failures_before: int = get_signal_emit_count(Events, "net_join_failed")
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var refused_late: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_join_failed") > failures_before
	)
	assert_true(refused_late, "after the grace it is just a new joiner, refused here")
