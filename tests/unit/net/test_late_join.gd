extends GutTest
## spec 2.6 "Late join / reconnect":
## mid-match admission, the ordered world replay, the replay-ack intent gate
## and reconnect inside the disconnect grace.
##
## Two halves, because one process has one Match singleton and one Events
## bus (a second in-process Match would see every block_placed/spawn the
## first one emits):
## - the replay itself runs host-then-client on the real Match: MatchWorldReplay
##   builds the exact ordered rows the host sends, the host world is
##   snapshotted, then Match turns client and the rows are applied in
##   order to a client-mode MatchNet -- the same calls the RPC layer makes;
## - admission (open seat / spectator / refusal / reconnect) runs over real
##   ENet between independent Net nodes, test_net_session.gd's pattern.

const MatchNetScript := preload("res://net/MatchNet.gd")
const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _map: MapDef
var _sessions: Array[Variant] = []
var _now_s: float = 0.0
var _sent: Array[Array] = []
var _stored_cursors: Array[int] = []
var _net_config: NetConfig = preload("res://config/net/net_config.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_sessions.clear()
	_sent.clear()
	_stored_cursors.clear()


func after_each() -> void:
	Match._net_provider = null
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
	Match._net_provider = session
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(FakeSessionPort.new(session), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	return node


func _config(player_count: int, mode: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = player_count
	config.ai_count = 0
	config.team_mode = MatchConfig.TeamMode.OFF
	config.block_timer = 6.0
	config.rng_seed = 4242
	# Old gift rule (a claim replaces the next piece); the after-next trial is in test_gift_queue_after_next.gd.
	config.qol = QolExperiments.new()
	config.qol.gift_queue_after_next = false
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


func _methods(rows: Array[Array]) -> Array[StringName]:
	var methods: Array[StringName] = []
	for row: Array in rows:
		methods.append(StringName(row[0]))
	return methods


## The host side of a mid-match join: MatchWorldReplay over the real Match and `session`, with a
## spy send seam and a clock the test owns.
func _make_replay(session: FakeNet) -> MatchWorldReplay:
	Match._net_provider = session
	_now_s = 0.0
	_sent.clear()
	var seams: MatchWorldReplay.Seams = WorldReplaySeams.make(
		func(peer_id: int, method: StringName, args: Array) -> bool:
			_sent.append([peer_id, method, args])
			return true,
		func() -> float: return _now_s
	)
	return MatchWorldReplay.new(FakeSessionPort.new(session), MatchHostPort.new(Match), _net_config, seams)


## The intent gateway the host binds, with the replay gate wired to `replay` the way MatchNet wires it.
func _make_gateway(session: FakeNet, replay: MatchWorldReplay, counters: NetCounters) -> MatchIntentGateway:
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return false
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(_peer: int, _method: StringName, _args: Array) -> bool: return true
	seams.broadcast = func(_method: StringName, _args: Array) -> void: pass
	seams.now_s = func() -> float: return _now_s
	seams.is_replay_pending = replay.is_pending
	seams.store_cursor = func(slot_id: int, _origin: Vector3, _index: int, _quat: Quaternion) -> void:
		_stored_cursors.append(slot_id)
	return MatchIntentGateway.new(FakeSessionPort.new(session), MatchHostPort.new(Match), _net_config, counters, seams)


## The replay id carried by a replay's opening net_match_start.
func _replay_id_of(rows: Array[Array]) -> int:
	assert_false(rows.is_empty(), "the replay has rows")
	if rows.is_empty():
		return -1
	var args: Array = rows[0][1]
	return int(args[2]) if args.size() > 2 else -1


## Applies a replay to a client-mode MatchNet row by row, the calls the RPC layer makes, and ends
## it with the marker the host's sender follows the rows with (the rows may already close with it).
func _apply_replay(client_net: MatchNetScript, rows: Array[Array]) -> void:
	if rows.is_empty():
		return
	for row: Array in rows:
		client_net.callv(StringName(row[0]), row[1] as Array)
	if StringName(rows[rows.size() - 1][0]) != &"net_replay_end":
		client_net.net_replay_end(_replay_id_of(rows))


func _become_client(slot_id: int) -> MatchNetScript:
	var client_net: MatchNetScript = _make_net(FakeNet.client(slot_id))
	Events.net_mode_changed.emit(Net.Mode.CLIENT)
	return client_net


# --- The replay: the joiner's world matches the host's ---------------------------

func test_the_joiners_world_matches_the_host_after_the_replay() -> void:
	_build_world(MapDef.base().scaled(0.75))
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var replay: MatchWorldReplay = _make_replay(host_session)
	_start_playing(_config(4, MatchConfig.GameMode.ELIMINATION))

	# A world worth replaying: two blocks (one Paintball-converted), slot 2
	# eliminated, a queued gift for the open seat, glue, a falling and a
	# landed crate, a solved raster and a running round clock.
	assert_eq(Match.request_place(0, _home(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0)), PlacementRules.REASON_OK)
	assert_eq(Match.request_place(1, _home(1), 0, Quaternion.IDENTITY, false, Match.feed_seq(1)), PlacementRules.REASON_OK)
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	Match._territory.flush_pending()
	var blocks_before: Dictionary = _live_blocks()
	assert_eq(blocks_before.size(), 2, "fixture placed two blocks")
	var converted: Block = blocks_before[blocks_before.keys().min()] as Block
	assert_true(_registry.convert_owner(converted, 1, Color.BLUE), "fixture converts one block")
	Match._lifecycle.eliminate_slots(PackedInt32Array([2]))
	Match._lifecycle._check_last_team_standing()
	assert_eq(Match.state(), Match.State.PLAYING, "three teams remain, the match runs on")
	Match._gifts._queue_claimed_special(3, MatchGifts.PENDING_SPECIAL_ID)
	assert_true(Match._gifts.grant_glue_drops(1, 3))
	Match._gifts._spawn_crate_at(Vector2(2.0, 1.0))
	Match._gifts._spawn_crate_at(Vector2(-3.0, 2.0))
	(Match._gifts._crates[1] as Dictionary)["phase"] = MatchGifts.LANDED

	# The new joiner takes the lowest open human seat: 2 is eliminated, 3 is free.
	host_session.slots_by_peer[3] = 3
	replay.on_peer_joined(3, 3, "Latey")
	assert_true(replay.is_pending(3), "the joiner owes an ack")

	# What the host holds at replay time, read in the same frame.
	var expected_blocks: Dictionary = {}
	var host_blocks: Dictionary = _live_blocks()
	for net_id: int in host_blocks.keys():
		var block: Block = host_blocks[net_id] as Block
		expected_blocks[net_id] = [
			block.global_position, block.global_basis.get_rotation_quaternion(), block.owner_slot, block.shape_id,
		]
	var expected_mode: Dictionary = Match.mode_state_snapshot()
	var expected_timer: float = Match.match_timer_left()
	var expected_gifts: Array[Dictionary] = Match.gift_states()
	assert_gt(expected_timer, 0.0, "the round clock is running")
	assert_false(expected_mode.is_empty(), "elimination replicates its state")
	var rows: Array[Array] = replay.build_replay(3, 3)
	assert_gt(rows.size(), 3, "the replay has rows")
	if rows.size() <= 3:
		return

	# The wire order: config + roster first, then every body, then the raster,
	# then derived state; the end marker, if the rows carry it, is last of all.
	var methods: Array[StringName] = _methods(rows)
	assert_eq(methods[0], &"net_match_start", "the replay opens with config + roster")
	assert_eq(methods.count(&"net_block_spawned"), 2, "one spawn per body")
	assert_eq(methods[1], &"net_block_spawned", "bodies right after the config")
	if methods.has(&"net_replay_end"):
		assert_eq(methods[methods.size() - 1], &"net_replay_end", "the end marker is last")
	for sent: Array in _sent:
		assert_eq(int(sent[0]), 3, "everything the host sends is addressed to the joiner alone")
	var spawn_args: Array = rows[1][1]
	assert_eq(spawn_args.size(), 6, "the replay spawn uses replicate_spawn's six-argument wire shape")
	assert_gt(_replay_id_of(rows), 0, "the opening message marks the replay with its id")

	# The joiner: Match becomes a client and the replay is applied in order.
	var client_net: MatchNetScript = _become_client(3)
	watch_signals(Events)
	_apply_replay(client_net, rows)

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
	var mode: Dictionary = Match.mode_state_snapshot()
	assert_eq(mode.get("scores"), expected_mode.get("scores"), "mode scores match")
	assert_eq(mode.get("extra"), expected_mode.get("extra"), "mode extra state matches")
	assert_almost_eq(Match.match_timer_left(), expected_timer, 0.0001, "the round clock matches")
	assert_false(Match.slot(2).home_flag_alive, "the eliminated slot is out on the joiner too")
	assert_true(Match.slot(3).home_flag_alive)
	assert_eq(Match.glue_drops_left(1), 3, "glue charges replayed")
	var gifts: Array[Dictionary] = Match.gift_states()
	assert_eq(gifts.size(), expected_gifts.size(), "every crate replayed")
	for i: int in range(mini(gifts.size(), expected_gifts.size())):
		assert_eq(gifts[i]["id"], expected_gifts[i]["id"])
		assert_eq(gifts[i]["phase"], expected_gifts[i]["phase"], "falling stays falling, landed stays landed")
	# The joiner acknowledged: the replay span is closed, so live broadcasts apply again.
	var span_changes: int = get_signal_emit_count(Events, "world_replay_changed")
	assert_eq(get_signal_parameters(Events, "world_replay_changed", span_changes - 1), [false], "the replay span ended")
	client_net.net_block_spawned(900, &"cube", 1, Vector3(1.0, 3.0, 1.0), Quaternion.IDENTITY)
	assert_not_null(Match.registry().block_for_net_id(900), "live broadcasts apply on top of the replayed world")


func test_a_client_drops_gameplay_broadcasts_until_its_replay_starts() -> void:
	_build_world(MapDef.base().scaled(0.75))
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	_make_net(host_session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	var client_net: MatchNetScript = _become_client(1)
	watch_signals(Events)

	client_net.net_block_spawned(31, &"cube", 1, Vector3(2.0, 3.0, 4.0), Quaternion.IDENTITY)
	client_net.net_match_event(MatchNetScript.EVENT_STATE_CHANGED, [Match.State.END])

	assert_null(Match.registry().block_for_net_id(31), "a spawn broadcast before the replay is not applied")
	assert_signal_not_emitted(Events, "match_state_changed", "nor is a state change")


func test_an_unacked_replay_times_out_and_drops_the_peer() -> void:
	_build_world(MapDef.base().scaled(0.75))
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var replay: MatchWorldReplay = _make_replay(session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	_now_s = 100.0
	replay.on_peer_joined(2, 1, "Latey")
	assert_true(replay.is_pending(2))
	replay.tick_timeouts(_now_s + _net_config.replay_ack_timeout * 0.5)
	assert_true(replay.is_pending(2), "still waiting inside the timeout")
	assert_eq(session.kick_peer_calls.size(), 0)
	replay.tick_timeouts(_now_s + _net_config.replay_ack_timeout)
	assert_false(replay.is_pending(2), "the gate no longer holds a dead peer")
	assert_eq(session.kick_peer_calls.size(), 1)
	if session.kick_peer_calls.size() == 1:
		assert_eq(int(session.kick_peer_calls[0]["peer_id"]), 2)
	replay.tick_timeouts(_now_s + _net_config.replay_ack_timeout * 3.0)
	assert_eq(session.kick_peer_calls.size(), 1, "kicked once, not on every later tick")


func test_an_acked_replay_is_never_timed_out() -> void:
	_build_world(MapDef.base().scaled(0.75))
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var replay: MatchWorldReplay = _make_replay(session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	replay.on_peer_joined(2, 1, "Latey")
	replay.handle_replay_ack(2, _replay_id_of(replay.build_replay(2, 1)))
	assert_false(replay.is_pending(2))
	replay.tick_timeouts(_now_s + _net_config.replay_ack_timeout * 10.0)
	assert_eq(session.kick_peer_calls.size(), 0, "an acknowledged peer is not kicked")


func test_a_peer_that_left_mid_replay_is_forgotten_by_the_timeout() -> void:
	_build_world(MapDef.base().scaled(0.75))
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var replay: MatchWorldReplay = _make_replay(session)
	_start_playing(_config(2, MatchConfig.GameMode.CLASSIC))
	replay.on_peer_joined(2, 1, "Latey")
	replay.on_peer_left(2)
	assert_false(replay.is_pending(2), "a peer that left owes nothing")
	replay.tick_timeouts(_now_s + _net_config.replay_ack_timeout * 10.0)
	assert_eq(session.kick_peer_calls.size(), 0, "and is not kicked after it is gone")


func test_nobody_owes_a_replay_in_the_lobby() -> void:
	var session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var replay: MatchWorldReplay = _make_replay(session)
	replay.on_peer_joined(2, 1, "Early")
	assert_false(replay.is_pending(2), "the lobby's match start carries the world: no replay")


# --- The intent gate ------------------------------------------------------------

func test_intents_before_the_replay_ack_are_refused() -> void:
	_build_world(MapDef.base().scaled(0.75))
	var session: FakeNet = FakeNet.host({1: 0, 2: 1, 3: 2}, [0])
	var replay: MatchWorldReplay = _make_replay(session)
	var counters: NetCounters = NetCounters.new()
	var gateway: MatchIntentGateway = _make_gateway(session, replay, counters)
	_start_playing(_config(3, MatchConfig.GameMode.CLASSIC))
	replay.on_peer_joined(3, 2, "Latey")
	var replay_id: int = _replay_id_of(replay.build_replay(3, 2))
	var blocks_before: int = _live_blocks().size()

	gateway.handle_place(3, 2, _home(2), 0, Quaternion.IDENTITY, Match.feed_seq(2))
	gateway.handle_throw(3, 2, _home(2), 0, Quaternion.IDENTITY, Vector3.UP, Match.feed_seq(2))
	gateway.handle_cursor(3, 2, _home(2), 0, Quaternion.IDENTITY)
	assert_eq(_live_blocks().size(), blocks_before, "nothing spawns for an unreplayed peer")
	assert_eq(counters.refused_count(2), 2, "counted as refusals, so sent == accepted + refused")
	assert_eq(counters.sent_count(2), 2)
	assert_false(_stored_cursors.has(2), "its cursor is not stored for auto-drop")

	replay.handle_replay_ack(3, replay_id + 1)
	assert_true(replay.is_pending(3), "a forged or stale ack is ignored")
	replay.handle_replay_ack(2, replay_id)
	assert_true(replay.is_pending(3), "another peer cannot ack for it")
	replay.handle_replay_ack(3, replay_id)
	assert_false(replay.is_pending(3), "the right ack lifts the gate")

	gateway.handle_place(3, 2, _home(2), 0, Quaternion.IDENTITY, Match.feed_seq(2))
	assert_eq(_live_blocks().size(), blocks_before + 1, "after the ack its intent is acted on")
	gateway.handle_cursor(3, 2, _home(2), 0, Quaternion.IDENTITY)
	assert_true(_stored_cursors.has(2), "and its cursor is stored again")


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
