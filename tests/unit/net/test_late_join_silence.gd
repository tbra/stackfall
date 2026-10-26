extends GutTest
## a client joining mid-match must hear the world being rebuilt
## as silence. The host's world replay restores state through the same Events a
## live match emits (block_placed per body, player_eliminated per dead slot,
## gift_flight_spawned per falling crate), and Sfx used to answer every one with
## its drop / breakage / gift sound, so the joiner heard the match history in one
## burst. net/MatchNet.gd now marks the replay (the net_match_start that carries
## the replay id, up to the matching net_replay_end) with
## Events.world_replay_changed, and Sfx mutes its one-shot feedback in that span.
##
## The fixture follows tests/unit/net/test_late_join.gd: host world on the real Match,
## the replay built by MatchWorldReplay, then Match turns client and the rows are applied
## in order -- the calls the RPC layer makes. The real Sfx autoload hears every Event; its
## silence is observed through its AudioStreamPlayer children (SfxChildren), with a live drop
## as the positive control that Sfx is listening.

const MatchNetScript := preload("res://net/MatchNet.gd")
const SHORT_TIMEOUT_S: float = 0.3

var _blocks_root: Node3D
var _field: Field
var _probe_drops: int = 0
var _registry: BlockRegistry


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SfxChildren.stop_all()


func after_each() -> void:
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Events.world_replay_changed.emit(false)
	SfxChildren.stop_all()
	await get_tree().process_frame


# --- Fixtures -----------------------------------------------------------------

func _build_world() -> void:
	var map: MapDef = MapDef.base().scaled(0.75)
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


func _config(player_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = player_count
	config.ai_count = 0
	config.team_mode = MatchConfig.TeamMode.OFF
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.game_mode = MatchConfig.GameMode.ELIMINATION
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


## True when a live drop by the local human's own seat sounds now (Sfx is listening and not silenced).
func _live_drop_sounds() -> bool:
	SfxChildren.stop_all()
	var own_drop: BlockBody = BlockBody.new()
	own_drop.owner_slot = 0
	add_child_autofree(own_drop)
	_probe_drops += 1
	Events.block_placed.emit(own_drop, &"cube")
	var sounded: bool = SfxChildren.any_playing()
	SfxChildren.stop_all()
	return sounded


## The host side of a mid-match join: a world with bodies, an eliminated slot and a
## crate still falling, then the joiner's replay as MatchWorldReplay builds it. Leaves
## Match built and running on the host side; call _become_client() before applying it.
func _build_host_replay(joiner_peer: int = 3, joiner_slot: int = 3) -> Array[Array]:
	_build_world()
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	Match._net_provider = host_session
	var seams: MatchWorldReplay.Seams = WorldReplaySeams.make(
		func(_peer_id: int, _method: StringName, _args: Array) -> bool: return true,
		func() -> float: return 0.0
	)
	var replay: MatchWorldReplay = MatchWorldReplay.new(FakeSessionPort.new(host_session), MatchHostPort.new(Match), preload("res://config/net/net_config.tres"), seams)
	_start_playing(_config(4))
	assert_eq(Match.request_place(0, _home(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0)), PlacementRules.REASON_OK)
	assert_eq(Match.request_place(1, _home(1), 0, Quaternion.IDENTITY, false, Match.feed_seq(1)), PlacementRules.REASON_OK)
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	Match._territory.flush_pending()
	assert_eq(Match.registry().all_blocks().size(), 2, "fixture placed two bodies")
	Match._lifecycle.eliminate_slots(PackedInt32Array([2]))
	Match._lifecycle._check_last_team_standing()
	assert_eq(Match.state(), Match.State.PLAYING, "three teams remain, the match runs on")
	Match._gifts._spawn_crate_at(Vector2(2.0, 1.0))
	assert_eq(Match.gift_states().size(), 1, "one crate is in flight")
	host_session.slots_by_peer[joiner_peer] = joiner_slot
	replay.on_peer_joined(joiner_peer, joiner_slot, "Latey")
	return replay.build_replay(joiner_peer, joiner_slot)


func _become_client(slot_id: int) -> MatchNetScript:
	var client_net: MatchNetScript = _make_net(FakeNet.client(slot_id))
	Events.net_mode_changed.emit(Net.Mode.CLIENT)
	return client_net


func _apply(client_net: MatchNetScript, row: Array) -> void:
	client_net.callv(StringName(row[0]), row[1] as Array)


## The marker the host's sender follows the rows with, unless the rows already close with it.
func _finish(client_net: MatchNetScript, rows: Array[Array]) -> void:
	if rows.is_empty():
		return
	if StringName(rows[rows.size() - 1][0]) != &"net_replay_end":
		client_net.net_replay_end(int((rows[0][1] as Array)[2]))


# --- The replay is silent --------------------------------------------------------

func test_the_replay_rebuilds_the_world_without_a_single_sound() -> void:
	var capture: Array[Array] = _build_host_replay()
	assert_gt(capture.size(), 1, "the replay has rows")
	if capture.size() <= 1:
		return
	var client_net: MatchNetScript = _become_client(3)

	# Positive control: the very handlers the replay triggers do sound when the
	# silence is not on, so the silence below is not a fixture artefact.
	assert_true(_live_drop_sounds(), "a live drop sounds")
	Events.player_eliminated.emit(1, 1)
	assert_true(SfxChildren.any_playing(), "a live elimination sounds")
	SfxChildren.stop_all()

	watch_signals(Events)
	_probe_drops = 0
	_apply(client_net, capture[0])
	assert_eq(StringName(capture[0][0]), &"net_match_start")
	assert_false(_live_drop_sounds(), "the replay's opening message turns the silence on")
	for index: int in range(1, capture.size()):
		_apply(client_net, capture[index])
		assert_false(SfxChildren.any_playing(), "message %d (%s) made a sound" % [index, capture[index][0]])
	_finish(client_net, capture)

	# The world was still restored through the same events a live match emits.
	assert_eq(get_signal_emit_count(Events, "block_placed") - _probe_drops, 2, "both bodies rebuilt through block_placed")
	assert_gte(get_signal_emit_count(Events, "player_eliminated"), 1, "the dead slot replayed")
	assert_eq(get_signal_emit_count(Events, "gift_flight_spawned"), 1, "the falling crate replayed")
	assert_eq(Match.registry().all_blocks().size(), 2, "both bodies exist on the joiner")
	assert_false(Match.slot(2).home_flag_alive, "the eliminated slot is out on the joiner")
	assert_false(SfxChildren.any_playing(), "no jingle, drop or breakage sounded for the whole replay")

	# The silence is exactly the replay: on at the start, off at net_replay_end.
	assert_true(_live_drop_sounds(), "net_replay_end lifted it")
	assert_eq(get_signal_emit_count(Events, "world_replay_changed"), 2)
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 0), [true])
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 1), [false])


# --- The marker ----------------------------------------------------------------------

# --- A replay that never completes must not mute the match -------------------------

func test_leaving_the_session_mid_replay_lifts_the_silence() -> void:
	var capture: Array[Array] = _build_host_replay()
	assert_false(capture.is_empty(), "the replay has rows")
	if capture.is_empty():
		return
	var client_net: MatchNetScript = _become_client(3)
	_apply(client_net, capture[0])
	assert_false(_live_drop_sounds(), "fixture: the replay is muting")
	watch_signals(Events)
	Events.net_mode_changed.emit(Net.Mode.OFFLINE)
	assert_true(_live_drop_sounds(), "Sfx hears the end too")
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 0), [false])


func test_a_replay_that_outlives_the_ack_timeout_stops_muting() -> void:
	var capture: Array[Array] = _build_host_replay()
	assert_false(capture.is_empty(), "the replay has rows")
	if capture.is_empty():
		return
	var client_net: MatchNetScript = _become_client(3)
	var short_timeout: NetConfig = client_net.config.duplicate() as NetConfig
	short_timeout.replay_ack_timeout = SHORT_TIMEOUT_S
	client_net.config = short_timeout
	client_net.set_process(true)
	_apply(client_net, capture[0])
	await get_tree().process_frame
	assert_false(_live_drop_sounds(), "still inside the timeout")
	# The client reads the wall clock, so wait on it rather than on the engine's frame time.
	var waited_from_ms: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - waited_from_ms) / 1000.0 < SHORT_TIMEOUT_S * 2.0:
		await get_tree().process_frame
	assert_true(_live_drop_sounds(), "the host would have dropped this peer by now")


func _rebind(client_net: MatchNetScript) -> void:
	assert_true(client_net.bind_ports(FakeSessionPort.new(FakeNet.client(3)), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))


## The client's world gate and replay span survive a config assignment and a bind_ports rebind:
## a rebind neither mutes nor un-mutes, and emits no world_replay_changed of its own.
func test_a_config_set_and_a_rebind_keep_the_replay_gate_state() -> void:
	var capture: Array[Array] = _build_host_replay()
	assert_false(capture.is_empty(), "the replay has rows")
	if capture.is_empty():
		return
	var client_net: MatchNetScript = _become_client(3)
	client_net.config = client_net.config.duplicate() as NetConfig
	_rebind(client_net)
	watch_signals(Events)
	_apply(client_net, capture[0])
	assert_eq(get_signal_emit_count(Events, "world_replay_changed"), 1)
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 0), [true])

	# Mid-replay: a rebind and a config set add no emit and do not lift the mute.
	_rebind(client_net)
	client_net.config = client_net.config.duplicate() as NetConfig
	assert_eq(get_signal_emit_count(Events, "world_replay_changed"), 1, "a rebind mid-replay emits nothing")
	_finish(client_net, capture)
	assert_eq(get_signal_emit_count(Events, "world_replay_changed"), 2, "the end still closes the span")
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 1), [false])


func test_a_client_that_never_saw_a_match_start_still_awaits_after_config_and_rebind() -> void:
	var capture: Array[Array] = _build_host_replay()
	assert_false(capture.is_empty(), "the replay has rows")
	if capture.is_empty():
		return
	var client_net: MatchNetScript = _become_client(3)
	client_net.config = client_net.config.duplicate() as NetConfig
	_rebind(client_net)
	# The gate is shut: a live match event is dropped rather than applied.
	watch_signals(Events)
	client_net.net_match_event(MatchWireEvents.PLAYER_ELIMINATED, [1, 1, 1])
	assert_eq(get_signal_emit_count(Events, "player_eliminated"), 0, "still awaiting the world")
	# Positive control: the same event is applied once the match start has opened the gate.
	_apply(client_net, capture[0])
	var before: int = get_signal_emit_count(Events, "player_eliminated")
	client_net.net_match_event(MatchWireEvents.PLAYER_ELIMINATED, [1, 1, 1])
	assert_eq(get_signal_emit_count(Events, "player_eliminated"), before + 1, "the gate opened at the match start")


# --- Impacts are not part of the replay -----------------------------------------
