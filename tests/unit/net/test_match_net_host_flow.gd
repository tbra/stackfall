extends GutTest
## MatchNet's host-side flow and the client's start handling, seen only through what a caller
## sees: the RPC surface (net_*), the Events bus, _process(delta) and the host's public
## replicate_* entry points.
##
## Host half: the Net/MatchNet autoloads host a real ENet loopback session and a recording
## client MatchNet (the production RPC surface, overridden to log) sits across the wire, so the
## assertions are about what actually leaves the host: the match start once per match, the
## loading announcement ahead of it, the impact batch and its peers, and the cat / score / raster
## ticks at their configured rates. Client half: a client-mode MatchNet over a faked session.

const MatchNetScript := preload("res://net/MatchNet.gd")

const HOST_PEER_ID: int = 1
const EPSILON_S: float = 0.002
const RECEIVE_WAIT_S: float = 10.0
const SETTLE_FRAMES: int = 8
const SENTINEL_EVENT: StringName = &"host_flow_sentinel"
const WIRE_POSITION_TOLERANCE_M: float = 0.05
const IMPACT_SPEED: float = 7.5
const IMPACT_AT: Vector3 = Vector3(3.0, 1.5, -2.0)
const CAT_RANGE_M: float = 3.0
const CURSOR_HEIGHT_M: float = 3.0
const CURSOR_OFFSET_M: float = 2.0
const CURSOR_TOLERANCE_M: float = 0.5
const REPLAY_ID: int = 7

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _loopback: LoopbackSession
var _client_net: Node
var _recorder: Recorder
var _fake_net: FakeNet


## The client's MatchNet: the production RPC surface, but every call this test cares about is
## logged as [name, args] instead of applied, so the test sees exactly the messages that arrive.
class Recorder:
	extends "res://net/MatchNet.gd"

	var log: Array[Array] = []

	func _ready() -> void:
		set_process(false)

	func count(call_name: StringName) -> int:
		var total: int = 0
		for entry: Array in log:
			if entry[0] == call_name:
				total += 1
		return total

	func event_count(event: StringName) -> int:
		var total: int = 0
		for entry: Array in log:
			if entry[0] == &"net_match_event" and (entry[1] as Array)[0] == event:
				total += 1
		return total

	func index_of(call_name: StringName) -> int:
		for i: int in range(log.size()):
			if log[i][0] == call_name:
				return i
		return -1

	@rpc("authority", "call_remote", "reliable")
	func net_match_loading() -> void:
		log.append([&"net_match_loading", []])

	@rpc("authority", "call_remote", "reliable")
	func net_match_start(config_data: Dictionary, roster: Array, replay_id: int = 0) -> void:
		log.append([&"net_match_start", [config_data, roster, replay_id]])

	@rpc("authority", "call_remote", "reliable")
	func net_match_event(event: StringName, args: Array) -> void:
		log.append([&"net_match_event", [event, args]])

	@rpc("authority", "call_remote", "reliable")
	func net_block_spawned(
		net_id: int,
		shape_id: StringName,
		owner_slot: int,
		origin: Vector3,
		rotation: Quaternion,
		gift_id: StringName = &""
	) -> void:
		log.append([&"net_block_spawned", [net_id, shape_id, owner_slot, origin, rotation, gift_id]])

	@rpc("authority", "call_remote", "reliable")
	func net_block_despawned(net_id: int, reason: String) -> void:
		log.append([&"net_block_despawned", [net_id, reason]])

	@rpc("authority", "call_remote", "reliable")
	func net_territory(payload: PackedByteArray) -> void:
		log.append([&"net_territory", [payload]])

	@rpc("authority", "call_remote", "reliable")
	func net_replay_end(replay_id: int) -> void:
		log.append([&"net_replay_end", [replay_id]])

	@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
	func net_block_impacts(packet: PackedByteArray) -> void:
		log.append([&"net_block_impacts", [packet]])

	@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
	func net_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
		log.append([&"net_cat_state", [id, position, velocity, point, remaining]])

	@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
	func net_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
		log.append([&"net_cursor", [slot_id, origin, orientation_index, free_quat]])


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_client_net = null
	_recorder = null
	_loopback = null


func after_each() -> void:
	if _loopback != null:
		await _loopback.end()
	_loopback = null
	MatchNet.set_process(true)
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Events.net_mode_changed.emit(Net.Mode.OFFLINE)


# --- Fixtures -----------------------------------------------------------------

func _build_world() -> void:
	_field = Field.new()
	_field.map_def = MapDef.base().scaled(0.75)
	add_child_autofree(_field)
	_blocks_root = Node3D.new()
	add_child_autofree(_blocks_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = player_count
	config.ai_count = 0
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = false
	config.allow_mid_match_join = true
	return config


func _reach_playing() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")


## The real host (the Net and MatchNet autoloads) with one recording client seated in slot 1.
## The autoload's own _process is off so the test owns every tick.
func _host_with_client() -> bool:
	_build_world()
	Net.leave()
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie", false), OK, "fixture: hosting")
	MatchNet.set_process(false)
	Match.set_replicator(MatchNet)
	_loopback = LoopbackSession.new(self)
	_client_net = await _loopback.join_remote_client("Clienty", false)
	assert_not_null(_client_net, "fixture: the remote client is seated")
	if _client_net == null:
		return false
	_recorder = Recorder.new()
	_recorder.name = "MatchNet"
	_client_net.get_parent().add_child(_recorder)
	assert_true(_recorder.bind_ports(
		SessionPort.new(_client_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	# A mid-match join also sends the weather state, so the client needs the weather relay nodes.
	_recorder.late_activate()
	var weather: WeatherNet = _recorder.get("_weather_net") as WeatherNet
	assert_true(weather.bind(SessionPort.new(_client_net), MatchHostPort.new(Match)))
	assert_true((weather.get_node("SnowNet") as SnowNet).bind(SessionPort.new(_client_net), MatchHostPort.new(Match)))
	assert_true((weather.get_node("BreezeNet") as BreezeNet).bind(SessionPort.new(_client_net), MatchHostPort.new(Match)))
	return true


## Waits until everything the host has sent so far on the reliable channel has arrived (the
## sentinel follows it), then a few frames more for the unreliable channel.
func _settle() -> void:
	MatchNet.replicate_match_event(SENTINEL_EVENT, [])
	var arrived: bool = await wait_until(
		func() -> bool: return _recorder.event_count(SENTINEL_EVENT) > 0, RECEIVE_WAIT_S)
	assert_true(arrived, "fixture: the client received what the host sent")
	await wait_frames(SETTLE_FRAMES)


func _forget_what_arrived() -> void:
	await _settle()
	_recorder.log.clear()


func _host_playing_and_quiet() -> bool:
	if not await _host_with_client():
		return false
	MatchNet._process(10.0) # the send accumulators outlive a test: start this one from zero
	Match.start_match(_config())
	_reach_playing()
	await _forget_what_arrived()
	return true


# --- Match start: once per match, ahead of it the loading announcement -------------

func test_the_loading_announcement_reaches_the_client_before_the_match_start() -> void:
	if not await _host_with_client():
		return
	MatchNet.replicate_match_loading()
	Match.start_match(_config())
	await _settle()

	assert_eq(_recorder.count(&"net_match_loading"), 1, "one loading announcement")
	assert_eq(_recorder.count(&"net_match_start"), 1, "one match start")
	assert_lt(
		_recorder.index_of(&"net_match_loading"), _recorder.index_of(&"net_match_start"),
		"the overlay is raised before the world build the start triggers")


func test_the_match_start_goes_out_once_per_match_however_often_it_is_asked_for() -> void:
	if not await _host_with_client():
		return
	var config: MatchConfig = _config()
	Match.start_match(config)
	MatchNet.replicate_match_start(Match.config)
	MatchNet.replicate_match_start(Match.config)
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 1, "an explicit repeat inside one match sends nothing")
	var start_args: Array = _recorder.log[_recorder.index_of(&"net_match_start")][1]
	assert_eq(start_args[2], 0, "the broadcast start carries no replay id")

	Match.abort_match()
	Match.start_match(_config())
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 2, "the next match announces itself again")


func test_a_restart_without_passing_through_the_lobby_announces_the_new_match() -> void:
	if not await _host_with_client():
		return
	Match.start_match(_config())
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 1)

	Match.start_match(_config())
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 2, "play again: the second match is announced too")


func test_back_in_the_lobby_an_explicit_start_announcement_is_accepted_again() -> void:
	if not await _host_with_client():
		return
	var config: MatchConfig = _config()
	Match.start_match(config)
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 1)

	Match.abort_match()
	MatchNet.replicate_match_start(config)
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 2, "the lobby's own announcement for the next match is not swallowed")


func test_a_start_with_no_config_sends_nothing_and_does_not_spend_the_match_start() -> void:
	if not await _host_with_client():
		return
	MatchNet.replicate_match_start(null)
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 0, "nothing to announce")

	Match.start_match(_config())
	await _settle()
	assert_eq(_recorder.count(&"net_match_start"), 1, "the real start still goes out")


# --- Impacts: batch cadence, who hears them, how a client plays them ---------------

func _decoded_impacts() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for entry: Array in _recorder.log:
		if entry[0] == &"net_block_impacts":
			events.append_array(ImpactWire.decode(
				(entry[1] as Array)[0] as PackedByteArray, MatchNet.config.impact_speed_max,
				MatchNet.config.pos_min_y, MatchNet.config.pos_max_y))
	return events


func test_host_impacts_go_out_as_one_batch_per_interval() -> void:
	if not await _host_playing_and_quiet():
		return
	var interval: float = 1.0 / MatchNet.config.impact_batch_hz
	Events.block_impacted_at.emit(IMPACT_SPEED, IMPACT_AT)

	MatchNet._process(interval - EPSILON_S)
	await _settle()
	assert_eq(_recorder.count(&"net_block_impacts"), 0, "the interval has not elapsed")

	MatchNet._process(2.0 * EPSILON_S)
	await wait_until(func() -> bool: return _recorder.count(&"net_block_impacts") > 0, RECEIVE_WAIT_S)
	await _settle()
	assert_eq(_recorder.count(&"net_block_impacts"), 1, "one batch")
	var events: Array[Dictionary] = _decoded_impacts()
	assert_eq(events.size(), 1, "carrying the one impact")
	if events.size() == 1:
		assert_almost_eq(float(events[0][ImpactWire.KEY_SPEED]), IMPACT_SPEED, ImpactWire.SPEED_QUANTUM * 2.0)
		assert_lt((events[0][ImpactWire.KEY_POSITION] as Vector3).distance_to(IMPACT_AT), WIRE_POSITION_TOLERANCE_M)

	MatchNet._process(interval)
	await _settle()
	assert_eq(_recorder.count(&"net_block_impacts"), 1, "a sent impact is not sent again")


func test_a_peer_still_loading_its_replay_hears_no_impacts_until_it_acknowledges() -> void:
	if not await _host_playing_and_quiet():
		return
	var interval: float = 1.0 / MatchNet.config.impact_batch_hz
	# The peer is (re)seated mid-match: the host owes it the whole world and waits for its ack.
	Events.net_peer_joined.emit(_client_net.local_peer_id(), _client_net.local_slot(), "Clienty")
	await _settle()
	assert_gt(_recorder.count(&"net_match_start"), 0, "fixture: the replay was sent")
	assert_gt(_recorder.count(&"net_replay_end"), 0, "fixture: and closed with its end marker")
	var replay_id: int = int((_recorder.log[_recorder.index_of(&"net_replay_end")][1] as Array)[0])
	_recorder.log.clear()

	Events.block_impacted_at.emit(IMPACT_SPEED, IMPACT_AT)
	MatchNet._process(interval + EPSILON_S)
	await _settle()
	assert_eq(_recorder.count(&"net_block_impacts"), 0, "no impacts into a world the peer has not acknowledged")

	_recorder.rpc_id(HOST_PEER_ID, &"net_replay_ack", replay_id)
	await wait_frames(SETTLE_FRAMES)
	await _forget_what_arrived()
	Events.block_impacted_at.emit(IMPACT_SPEED, IMPACT_AT)
	MatchNet._process(interval + EPSILON_S)
	var heard: bool = await wait_until(
		func() -> bool: return _recorder.count(&"net_block_impacts") > 0, RECEIVE_WAIT_S)
	assert_true(heard, "once acknowledged the peer hears impacts again")


# --- Cat, score and raster ticks ---------------------------------------------------

func test_the_cat_state_goes_out_at_the_cursor_rate_and_only_while_a_cat_runs() -> void:
	if not await _host_playing_and_quiet():
		return
	var period: float = 1.0 / MatchNet.config.cursor_hz
	MatchNet._process(period * 3.0)
	await _settle()
	assert_eq(_recorder.count(&"net_cat_state"), 0, "no cat, no cat state")

	var effect: CatEffect = CatEffect.new()
	effect.target_range_m = CAT_RANGE_M
	var origin: Vector3 = _field.world_from_disk_local(Match.slot(1).home_position, 1.0)
	assert_true(Match.start_cat(1, origin, effect), "fixture: a cat is running")
	Match.active_cat().set_physics_process(false)
	await _forget_what_arrived()

	MatchNet._process(period - EPSILON_S)
	await _settle()
	assert_eq(_recorder.count(&"net_cat_state"), 0, "a period has not elapsed")
	MatchNet._process(2.0 * EPSILON_S)
	await wait_until(func() -> bool: return _recorder.count(&"net_cat_state") > 0, RECEIVE_WAIT_S)
	await _settle()
	assert_eq(_recorder.count(&"net_cat_state"), 1, "one cat state per period")


func test_the_live_scoreboard_goes_out_at_the_scoreboard_rate_and_only_while_the_round_is_live() -> void:
	if not await _host_with_client():
		return
	Match.start_match(_config())
	var period: float = 1.0 / MatchNet.config.scoreboard_hz
	assert_ne(Match.state(), Match.State.PLAYING, "fixture: still in the countdown")
	await _forget_what_arrived()
	MatchNet._process(period * 3.0)
	await _settle()
	assert_eq(_recorder.event_count(MatchWireEvents.LIVE_SCORES), 0, "no scoreboard before the round is live")

	_reach_playing()
	MatchNet._process(period * 3.0) # the accumulators outlive a test: start this one from zero
	await _forget_what_arrived()
	MatchNet._process(period - EPSILON_S)
	await _settle()
	assert_eq(_recorder.event_count(MatchWireEvents.LIVE_SCORES), 0, "a period has not elapsed")
	MatchNet._process(2.0 * EPSILON_S)
	await _settle()
	assert_eq(_recorder.event_count(MatchWireEvents.LIVE_SCORES), 1, "one scoreboard per period")


func test_the_raster_goes_out_at_the_diff_rate_and_is_not_repeated_while_nothing_changes() -> void:
	if not await _host_playing_and_quiet():
		return
	var step: float = 1.0 / MatchNet.config.raster_diff_hz
	MatchNet._process(step - EPSILON_S)
	await _settle()
	assert_eq(_recorder.count(&"net_territory"), 0, "a diff step has not elapsed")

	MatchNet._process(2.0 * EPSILON_S)
	await _settle()
	assert_eq(_recorder.count(&"net_territory"), 1, "the first diff is the full keyframe")

	MatchNet._process(step)
	await _settle()
	assert_eq(_recorder.count(&"net_territory"), 1, "nothing changed, nothing sent")


# --- Auto-drop: the stored cursor, the local seat, a new match forgets -------------

func _send_cursor_from_client(origin: Vector3) -> void:
	_recorder.submit_cursor(_client_net.local_slot(), origin, 0, Quaternion.IDENTITY)
	var stored: bool = await wait_until(
		func() -> bool: return not MatchNet.cursor_for_slot(_client_net.local_slot()).is_empty(), RECEIVE_WAIT_S)
	assert_true(stored, "fixture: the host stored the client's ghost pose")


func test_the_auto_drop_falls_from_the_last_cursor_the_seat_sent() -> void:
	if not await _host_playing_and_quiet():
		return
	var slot: int = _client_net.local_slot()
	var home: Vector2 = Match.slot(slot).home_position
	var sent_from_local: Vector2 = home - home.normalized() * CURSOR_OFFSET_M
	var sent_from: Vector3 = _field.world_from_disk_local(sent_from_local, CURSOR_HEIGHT_M)
	await _send_cursor_from_client(sent_from)
	assert_eq(_blocks_root.get_child_count(), 0, "fixture: nothing dropped yet")

	Events.feed_timer_expired.emit(slot)

	assert_eq(_blocks_root.get_child_count(), 1, "the host dropped the seat's held piece for it")
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	var landed: Vector2 = _field.disk_local_from_world(block.global_position)
	assert_lt(landed.distance_to(sent_from_local), CURSOR_TOLERANCE_M,
		"over the cursor the seat last sent, not over its home flag")
	assert_gt(landed.distance_to(home), CURSOR_OFFSET_M * 0.5, "which is not where a seat with no cursor drops")
	assert_eq(MatchNet.counters.accepted_count(slot), 0, "an auto-drop is not an accepted intent")


func test_a_new_match_forgets_every_stored_cursor() -> void:
	if not await _host_playing_and_quiet():
		return
	await _send_cursor_from_client(_field.world_from_disk_local(Match.slot(_client_net.local_slot()).home_position, 1.0))

	Match.abort_match()
	Match.start_match(_config())

	assert_true(MatchNet.cursor_for_slot(_client_net.local_slot()).is_empty(), "the old match's pose is gone")


# --- Client half: faked session -----------------------------------------------------

func _client_net_over_fake(local_slot: int) -> MatchNetScript:
	_build_world()
	_fake_net = FakeNet.client(local_slot)
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(FakeSessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	return node


func test_a_replay_opening_start_raises_the_replay_span_before_its_own_state_events() -> void:
	var net: MatchNetScript = _client_net_over_fake(1)
	var order: Array[String] = []
	var span: Callable = func(on: bool) -> void: order.append("span_on" if on else "span_off")
	var state: Callable = func(_from: int, _to: int) -> void: order.append("state")
	Events.world_replay_changed.connect(span)
	Events.match_state_changed.connect(state)

	net.net_match_start(_config().to_dict(), [], REPLAY_ID)
	var first_state: int = order.find("state")
	assert_eq(order[0], "span_on", "the span opens first, so the start's own state events are inside it")
	assert_gt(first_state, 0, "and the start still ran its state changes")

	order.clear()
	net.net_match_start(_config().to_dict(), [], REPLAY_ID + 1)
	assert_eq(order.slice(0, 2), ["span_off", "span_on"], "a new start ends the old span, then opens its own")

	order.clear()
	net.net_match_start(_config().to_dict(), [], 0)
	assert_eq(order[0], "span_off", "a plain start ends the span before it runs")
	assert_false(order.has("span_on"), "and opens none")
	Events.world_replay_changed.disconnect(span)
	Events.match_state_changed.disconnect(state)


func test_a_start_gives_the_client_a_clean_slate_for_remote_cursors() -> void:
	var net: MatchNetScript = _client_net_over_fake(1)
	net.net_match_start(_config().to_dict(), [], 0)
	net.net_cursor(2, Vector3(1.0, 2.0, 3.0), 0, Quaternion.IDENTITY)
	assert_false(net.cursor_for_slot(2).is_empty(), "fixture: a remote pose is held")

	net.net_match_start(_config().to_dict(), [], 0)

	assert_true(net.cursor_for_slot(2).is_empty(), "the next match starts without it")


func test_a_cursor_relay_updates_remote_ghosts_but_never_the_clients_own_seat() -> void:
	var net: MatchNetScript = _client_net_over_fake(1)
	watch_signals(Events)

	net.net_cursor(1, Vector3.ONE, 0, Quaternion.IDENTITY)
	assert_signal_not_emitted(Events, "remote_cursor_updated", "the local seat is drawn by its own controller")
	assert_true(net.cursor_for_slot(1).is_empty(), "and its pose is not stored from the wire")

	net.net_cursor(2, Vector3(1.0, 2.0, 3.0), 3, Quaternion.IDENTITY)
	assert_signal_emit_count(Events, "remote_cursor_updated", 1, "another seat's ghost moves")
	assert_eq(get_signal_parameters(Events, "remote_cursor_updated", 0)[0], 2)
	var stored: Dictionary = net.cursor_for_slot(2)
	assert_eq(stored["origin"], Vector3(1.0, 2.0, 3.0))
	assert_eq(stored["orientation_index"], 3)


func test_a_client_still_waiting_for_its_world_ignores_the_cursor_relay_and_impact_batches() -> void:
	var net: MatchNetScript = _client_net_over_fake(1)
	Events.net_mode_changed.emit(Net.Mode.CLIENT)
	watch_signals(Events)
	var packet: PackedByteArray = ImpactWire.encode([{
		ImpactWire.KEY_SPEED: IMPACT_SPEED, ImpactWire.KEY_POSITION: IMPACT_AT, ImpactWire.KEY_AGE_MS: 0,
	}])

	net.net_cursor(2, Vector3.ONE, 0, Quaternion.IDENTITY)
	net.net_block_impacts(packet)
	assert_signal_not_emitted(Events, "remote_cursor_updated")
	assert_signal_not_emitted(Events, "block_impacted_at")

	net.net_match_start(_config().to_dict(), [], 0)
	net.net_block_impacts(packet)
	assert_signal_emit_count(Events, "block_impacted_at", 1, "after its start the same batch plays")


func test_a_client_plays_a_received_impact_batch_through_the_impact_signals() -> void:
	var net: MatchNetScript = _client_net_over_fake(1)
	watch_signals(Events)
	var packet: PackedByteArray = ImpactWire.encode([{
		ImpactWire.KEY_SPEED: IMPACT_SPEED, ImpactWire.KEY_POSITION: IMPACT_AT, ImpactWire.KEY_AGE_MS: 0,
	}])

	net.net_block_impacts(packet)

	assert_signal_emit_count(Events, "block_impacted", 1)
	assert_signal_emit_count(Events, "block_impacted_at", 1)
	var params: Array = get_signal_parameters(Events, "block_impacted_at", 0)
	assert_almost_eq(float(params[0]), IMPACT_SPEED, ImpactWire.SPEED_QUANTUM * 2.0)
	assert_lt((params[1] as Vector3).distance_to(IMPACT_AT), WIRE_POSITION_TOLERANCE_M)


func test_a_client_throws_away_a_malformed_impact_batch() -> void:
	var net: MatchNetScript = _client_net_over_fake(1)
	watch_signals(Events)
	net.net_block_impacts(PackedByteArray([ImpactWire.VERSION + 9, 1, 0, 0]))
	assert_signal_not_emitted(Events, "block_impacted_at")


func test_the_host_ignores_an_impact_batch_sent_to_it() -> void:
	_build_world()
	_fake_net = FakeNet.host({1: 0, 2: 1}, [0])
	Match._net_provider = _fake_net
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	assert_true(net.bind_ports(FakeSessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	watch_signals(Events)
	var packet: PackedByteArray = ImpactWire.encode([{
		ImpactWire.KEY_SPEED: IMPACT_SPEED, ImpactWire.KEY_POSITION: IMPACT_AT, ImpactWire.KEY_AGE_MS: 0,
	}])

	net.net_block_impacts(packet)

	assert_signal_not_emitted(Events, "block_impacted_at", "the host hears its own impacts directly, never from the wire")
