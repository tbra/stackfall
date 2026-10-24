extends GutTest
## net/match/MatchReplication.gd: the host side sends spawns, despawns, territory, match events,
## match start and impact batches through its Seams; the client side applies a territory packet
## and plays queued impacts once the view time (now minus the snapshot delay) reaches them. Driven
## only through the module's public methods over Seams spies, FakeSessionPort and a FakeHostPort
## subclass; two modules wired back to back carry a packet from a host to a client.

const GRID_SIZE_M: float = 20.0
const GRID_CELL_M: float = 1.0
const XZ_BOUND: float = 67.5
const RADIUS_MAX: float = 27.0
const TEAMS: int = 3
const HZ: float = 10.0
## Two ticks of this length cross one 1/HZ period; one does not.
const HALF_STEP_S: float = 0.06
const NOW_MS: int = 2000
const VIEW_DELAY_MS: int = 100
const PEER_A: int = 2
const PEER_B: int = 3


## The Seams the module is built with: every send is recorded, every answer is a field.
class SeamSpy extends RefCounted:
	var can: bool = true
	var peers: Array[int] = []
	var pending: Dictionary = {}
	var now: int = 0
	var delay: int = 0
	var broadcasts: Array[Dictionary] = []
	var sent: Array[Dictionary] = []

	func seams() -> MatchReplication.Seams:
		var seams: MatchReplication.Seams = MatchReplication.Seams.new()
		seams.can_send = func() -> bool: return can
		seams.broadcast = func(method: StringName, args: Array) -> void:
			broadcasts.append({"method": method, "args": args})
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			sent.append({"peer": peer_id, "method": method, "args": args})
			return true
		seams.peer_ids = func() -> Array[int]: return peers
		seams.is_replay_pending = func(peer_id: int) -> bool: return pending.has(peer_id)
		seams.now_ms = func() -> int: return now
		seams.view_delay_ms = func() -> int: return delay
		return seams

	func broadcasts_of(method: StringName) -> Array[Array]:
		var found: Array[Array] = []
		for entry: Dictionary in broadcasts:
			if entry["method"] == method:
				found.append(entry["args"] as Array)
		return found

	func sends_of(method: StringName) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for entry: Dictionary in sent:
			if entry["method"] == method:
				found.append(entry)
		return found


class StatsSpy extends RefCounted:
	func build_live_payload() -> Dictionary:
		return {"scores": [1, 2]}


class RasterSide extends RefCounted:
	var raster_value: TerritoryRaster = null
	var applied: int = 0


class HostSpy extends FakeHostPort:
	var side: RasterSide = null
	var config_value: MatchConfig = null
	var state_value: int = MatchPhase.State.LOBBY
	var cat_value: RigidBody3D = null
	var stats_value: RefCounted = StatsSpy.new()
	var circles: Dictionary = {
		"xs": PackedFloat32Array([0.0, -10.5]),
		"zs": PackedFloat32Array([0.0, 3.0]),
		"radii": PackedFloat32Array([6.0, 2.5]),
		"teams": PackedInt32Array([0, 1]),
		"goal_positions": PackedVector2Array(),
		"goal_radii": PackedFloat32Array(),
		"argmax_mode": false,
	}

	func raster() -> TerritoryRaster:
		return side.raster_value

	func config() -> MatchConfig:
		return config_value

	func state() -> int:
		return state_value

	func active_cat() -> RigidBody3D:
		return cat_value

	func stats() -> RefCounted:
		return stats_value

	func circle_render_arrays() -> Dictionary:
		return circles

	func circle_wire_xz_bound() -> float:
		return XZ_BOUND

	func circle_wire_radius_max() -> float:
		return RADIUS_MAX

	func territory_share(_team_id: int) -> float:
		return 0.25


class ReplicaSpy extends FakeReplicaPort:
	var side: RasterSide = null

	func apply_replicated_territory(
		cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray, full: bool,
		_xs: PackedFloat32Array = PackedFloat32Array(), _zs: PackedFloat32Array = PackedFloat32Array(),
		_radii: PackedFloat32Array = PackedFloat32Array(), _teams: PackedInt32Array = PackedInt32Array(),
		_goal_positions: PackedVector2Array = PackedVector2Array(),
		_goal_radii: PackedFloat32Array = PackedFloat32Array(), _argmax_mode: bool = false
	) -> void:
		side.applied += 1
		if full:
			side.raster_value.apply_replicated_state(owners, states)
		else:
			side.raster_value.apply_replicated_diff(cells, owners, states)


## One module with everything it touches: the seam spy, the ports and the raster behind them.
class Rig extends RefCounted:
	var spy: SeamSpy = SeamSpy.new()
	var side: RasterSide = RasterSide.new()
	var host: HostSpy = HostSpy.new()
	var replica: ReplicaSpy = ReplicaSpy.new()
	var session: FakeSessionPort = null
	var config: NetConfig = NetConfig.new()
	var module: MatchReplication = null


var _tuning: TerritoryTuning = TerritoryTuning.new()
var _speed_events: Array[float] = []
var _at_events: Array[Array] = []
var _speed_listener: Callable
var _at_listener: Callable


func before_each() -> void:
	_speed_events = []
	_at_events = []
	_speed_listener = func(speed: float) -> void:
		_speed_events.append(speed)
	_at_listener = func(speed: float, position: Vector3) -> void:
		_at_events.append([speed, position])
	Events.block_impacted.connect(_speed_listener)
	Events.block_impacted_at.connect(_at_listener)


func after_each() -> void:
	Events.block_impacted.disconnect(_speed_listener)
	Events.block_impacted_at.disconnect(_at_listener)


## net_territory's arguments after the packet: neutral values for the slots the packet carries.
func _tail() -> Array:
	return [false, PackedFloat32Array(), -1, 0.0]


## The packet of the first net_territory broadcast, empty (and the assert fails) when none went out.
func _first_packet(rig: Rig) -> PackedByteArray:
	var sent: Array[Array] = rig.spy.broadcasts_of(&"net_territory")
	assert_gt(sent.size(), 0, "a net_territory broadcast went out")
	return PackedByteArray() if sent.is_empty() else sent[0][0] as PackedByteArray


func _raster() -> TerritoryRaster:
	return TerritoryRaster.new(CellGrid.new(GRID_SIZE_M, GRID_CELL_M), _tuning)


## A bound module. `with_raster` gives the host a raster to replicate; cadences are all HZ.
func _rig(fake: FakeNet = null, with_raster: bool = false) -> Rig:
	var rig: Rig = Rig.new()
	var net: FakeNet = fake if fake != null else FakeNet.host({PEER_A: 0, PEER_B: 1}, [0] as Array[int])
	rig.session = FakeSessionPort.new(net)
	rig.config.raster_diff_hz = HZ
	rig.config.cursor_hz = HZ
	rig.config.scoreboard_hz = HZ
	rig.config.impact_batch_hz = HZ
	rig.host.side = rig.side
	rig.replica.side = rig.side
	rig.host.config_value = MatchConfig.new()
	rig.host.config_value.player_count = TEAMS
	if with_raster:
		rig.side.raster_value = _raster()
	rig.spy.peers = [PEER_A, PEER_B] as Array[int]
	rig.spy.now = NOW_MS
	var mirror_seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	mirror_seams.broadcast = func(method: StringName, args: Array) -> void:
		rig.spy.broadcasts.append({"method": method, "args": args})
	mirror_seams.send_to_peer = func(_p: int, _m: StringName, _a: Array) -> bool: return true
	var mirror: MatchEventMirror = MatchEventMirror.new(mirror_seams)
	mirror.bind_ports(rig.session, rig.host)
	rig.module = MatchReplication.new(rig.spy.seams(), mirror)
	rig.module.bind(rig.session, rig.host, rig.replica, rig.config)
	return rig


func _set_cell(rig: Rig, index: int, owner: int) -> void:
	var raster: TerritoryRaster = rig.side.raster_value
	var owners: PackedByteArray = raster.owner_bytes()
	var states: PackedByteArray = raster.state_bytes()
	owners[index] = owner
	raster.apply_replicated_state(owners, states)


func _impact_packet(speed: float, position: Vector3) -> PackedByteArray:
	var impacts: ImpactReplicator = ImpactReplicator.new(NetConfig.new(), TokenBucket.new())
	impacts.collect(speed, position, NOW_MS)
	return impacts.flush(NOW_MS)


func _block(net_id: int) -> BlockBody:
	var block: BlockBody = BlockBody.new()
	block.shape_id = &"cube"
	block.owner_slot = 2
	block.gift_id = &"rocket"
	block.net_id = net_id
	add_child_autofree(block)
	block.global_position = Vector3(1.0, 2.0, 3.0)
	return block


# --- Spawn / despawn ------------------------------------------------------------

func test_spawn_goes_out_with_the_wire_shape() -> void:
	var rig: Rig = _rig()
	var block: BlockBody = _block(7)
	rig.module.send_spawn(block, 7)
	var spawns: Array[Array] = rig.spy.broadcasts_of(&"net_block_spawned")
	assert_eq(spawns.size(), 1)
	if spawns.size() == 1:
		assert_eq(spawns[0], rig.module.spawn_args(block, 7))
		var args: Array = spawns[0]
		assert_eq(args.size(), 6)
		assert_eq(args[0], 7)
		assert_eq(args[1], &"cube")
		assert_eq(args[2], 2)
		assert_eq(args[3], Vector3(1.0, 2.0, 3.0))
		assert_eq(args[5], &"rocket")


func test_spawn_is_never_sent_for_a_block_without_a_wire_id() -> void:
	var rig: Rig = _rig()
	rig.module.send_spawn(_block(-1), -1)
	rig.module.send_spawn(_block(0), 0)
	rig.module.send_spawn(_block(Quantize.NET_ID_MAX + 1), Quantize.NET_ID_MAX + 1)
	rig.module.send_spawn(null, 5)
	assert_eq(rig.spy.broadcasts.size(), 0)
	rig.module.send_spawn(_block(Quantize.NET_ID_MAX), Quantize.NET_ID_MAX)
	assert_eq(rig.spy.broadcasts_of(&"net_block_spawned").size(), 1, "the last valid id still goes out")


func test_despawn_carries_id_and_reason_and_refuses_a_negative_id() -> void:
	var rig: Rig = _rig()
	rig.module.send_despawn(-1, "fell")
	assert_eq(rig.spy.broadcasts.size(), 0)
	rig.module.send_despawn(9, "fell")
	assert_eq(rig.spy.broadcasts, [{"method": &"net_block_despawned", "args": [9, "fell"]}])


# --- Host / can_send gates ----------------------------------------------------------

func test_a_client_sends_nothing() -> void:
	var rig: Rig = _rig(FakeNet.client(1), true)
	rig.host.state_value = MatchPhase.State.PLAYING
	rig.module.send_spawn(_block(7), 7)
	rig.module.send_despawn(7, "x")
	rig.module.send_territory()
	rig.module.send_match_event(&"countdown", [3])
	rig.module.send_match_start(rig.host.config_value)
	rig.module.send_match_loading()
	rig.module.on_block_impacted_at(5.0, Vector3.ONE)
	rig.module.tick_host_feeds(10.0)
	assert_eq(rig.spy.broadcasts.size(), 0)
	assert_eq(rig.spy.sent.size(), 0)


func test_nothing_is_sent_while_the_transport_cannot_send() -> void:
	var rig: Rig = _rig(null, true)
	rig.spy.can = false
	rig.module.send_spawn(_block(7), 7)
	rig.module.send_despawn(7, "x")
	rig.module.send_territory()
	rig.module.send_match_event(&"countdown", [3])
	rig.module.send_match_loading()
	rig.module.on_block_impacted_at(5.0, Vector3.ONE)
	rig.module.tick_host_feeds(10.0)
	rig.spy.can = true
	rig.module.tick_host_feeds(10.0)
	assert_eq(rig.spy.sends_of(&"net_block_impacts").size(), 0, "an impact seen while muted was never queued")
	assert_eq(rig.spy.broadcasts_of(&"net_block_spawned").size(), 0)
	assert_eq(rig.spy.broadcasts_of(&"net_block_despawned").size(), 0)
	assert_eq(rig.spy.broadcasts_of(&"net_match_event").size(), 0)
	assert_eq(rig.spy.broadcasts_of(&"net_match_loading").size(), 0)


func test_match_event_and_loading_are_broadcast() -> void:
	var rig: Rig = _rig()
	rig.module.send_match_event(&"countdown", [3])
	rig.module.send_match_loading()
	assert_eq(rig.spy.broadcasts, [
		{"method": &"net_match_event", "args": [&"countdown", [3]]},
		{"method": &"net_match_loading", "args": []},
	])


# --- Match start --------------------------------------------------------------------

func test_match_start_ships_config_roster_and_seed_once() -> void:
	var rig: Rig = _rig()
	var match_config: MatchConfig = rig.host.config_value
	rig.module.send_match_start(match_config)
	var starts: Array[Array] = rig.spy.broadcasts_of(&"net_match_start")
	assert_eq(starts.size(), 1)
	if starts.size() == 1:
		assert_eq(starts[0], [match_config.to_dict(), rig.session.roster(), 0])
		assert_eq((starts[0][1] as Array).size(), 2, "the roster is the real peer list")
	rig.module.send_match_start(match_config)
	assert_eq(rig.spy.broadcasts_of(&"net_match_start").size(), 1, "idempotent for one match")


func test_match_start_with_no_config_sends_nothing_and_does_not_use_up_the_match() -> void:
	var rig: Rig = _rig()
	rig.module.send_match_start(null)
	assert_eq(rig.spy.broadcasts.size(), 0)
	rig.module.send_match_start(rig.host.config_value)
	assert_eq(rig.spy.broadcasts_of(&"net_match_start").size(), 1)


func test_match_start_is_sent_again_after_loading_and_after_lobby() -> void:
	var rig: Rig = _rig()
	var match_config: MatchConfig = rig.host.config_value
	rig.module.send_match_start(match_config)
	assert_true(rig.module.on_match_state_changed(MatchPhase.State.LOADING))
	rig.module.send_match_start(match_config)
	assert_eq(rig.spy.broadcasts_of(&"net_match_start").size(), 2, "LOADING reopens the match")
	assert_false(rig.module.on_match_state_changed(MatchPhase.State.LOBBY))
	rig.module.send_match_start(match_config)
	assert_eq(rig.spy.broadcasts_of(&"net_match_start").size(), 3, "LOBBY reopens it too")


func test_other_states_keep_the_start_flag_and_do_not_ask_for_a_new_match() -> void:
	var rig: Rig = _rig()
	var match_config: MatchConfig = rig.host.config_value
	rig.module.send_match_start(match_config)
	for state: int in [
		MatchPhase.State.COUNTDOWN, MatchPhase.State.PLAYING,
		MatchPhase.State.SUDDEN_DEATH, MatchPhase.State.END,
	]:
		assert_false(rig.module.on_match_state_changed(state), "state %d" % state)
	rig.module.send_match_start(match_config)
	assert_eq(rig.spy.broadcasts_of(&"net_match_start").size(), 1)


func test_a_client_never_reports_a_new_match() -> void:
	var rig: Rig = _rig(FakeNet.client(1))
	assert_false(rig.module.on_match_state_changed(MatchPhase.State.LOADING))
	assert_false(rig.module.on_match_state_changed(MatchPhase.State.LOBBY))


func test_the_start_flag_survives_a_rebind() -> void:
	var rig: Rig = _rig()
	rig.module.send_match_start(rig.host.config_value)
	rig.module.bind(rig.session, rig.host, rig.replica, NetConfig.new())
	rig.module.send_match_start(rig.host.config_value)
	assert_eq(rig.spy.broadcasts_of(&"net_match_start").size(), 1)


func test_match_start_forces_the_next_territory_packet_to_be_a_keyframe() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 4, 1)
	rig.module.send_territory()
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 1, "an unchanged raster adds no packet")
	rig.module.send_match_start(rig.host.config_value)
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 2, "a new match resyncs everyone")


# --- Territory ---------------------------------------------------------------------

func test_territory_goes_out_in_the_rpc_shape_only_when_something_changed() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 4, 1)
	rig.module.send_territory()
	var packets: Array[Array] = rig.spy.broadcasts_of(&"net_territory")
	assert_eq(packets.size(), 1)
	if packets.size() == 1:
		var args: Array = packets[0]
		assert_eq(args.size(), 5)
		assert_true(args[0] is PackedByteArray and not (args[0] as PackedByteArray).is_empty())
		assert_eq(args.slice(1), _tail())
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 1)
	_set_cell(rig, 9, 2)
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 2)


func test_territory_sends_nothing_without_a_raster() -> void:
	var rig: Rig = _rig()
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts.size(), 0)
	assert_eq(rig.module.territory_replay_args(), [])


func test_the_replay_args_are_a_full_keyframe_a_fresh_client_can_apply() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 4, 1)
	rig.module.send_territory()
	var args: Array = rig.module.territory_replay_args()
	assert_eq(args.size(), 5)
	assert_eq(args.slice(1), _tail())
	var client: Rig = _rig(FakeNet.client(1), true)
	assert_true(args.size() == 5 and client.module.receive_territory(args[0] as PackedByteArray))
	assert_true(client.side.raster_value.owner_bytes() == rig.side.raster_value.owner_bytes(), "same raster")


func test_a_host_packet_reaches_a_client_module() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 4, 1)
	_set_cell(rig, 77, 2)
	rig.module.send_territory()
	var client: Rig = _rig(FakeNet.client(1), true)
	watch_signals(Events)
	var packet: PackedByteArray = _first_packet(rig)
	assert_true(client.module.receive_territory(packet))
	assert_true(client.side.raster_value.owner_bytes() == rig.side.raster_value.owner_bytes(), "same raster")
	assert_eq(client.side.applied, 1)
	assert_signal_emitted(Events, "territory_replicated")


func test_a_malformed_territory_packet_is_dropped_whole() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 4, 1)
	rig.module.send_territory()
	var good: PackedByteArray = _first_packet(rig)
	if good.is_empty():
		return
	var wrong_version: PackedByteArray = good.duplicate()
	wrong_version[0] = 99
	var cut_in_header: PackedByteArray = good.slice(0, 5)
	var raster_start: int = (
		TerritoryReplicator.PACKET_HEADER_BYTES + TEAMS * TerritoryReplicator.SHARE_BYTES
		+ TerritoryReplicator.RASTER_LEN_BYTES
	)
	var cut_in_body: PackedByteArray = good.slice(0, raster_start + 3)
	var lying_length: PackedByteArray = good.duplicate()
	lying_length.encode_u32(TerritoryReplicator.PACKET_HEADER_BYTES + TEAMS * TerritoryReplicator.SHARE_BYTES, 0x7FFFFFFF)
	var bad_progress: PackedByteArray = good.duplicate()
	bad_progress.encode_float(TerritoryReplicator.PROGRESS_OFFSET, 5.0)
	var client: Rig = _rig(FakeNet.client(1), true)
	var before: PackedByteArray = client.side.raster_value.owner_bytes().duplicate()
	watch_signals(Events)
	for bad: PackedByteArray in [
		PackedByteArray(), wrong_version, cut_in_header, cut_in_body, lying_length, bad_progress,
	]:
		assert_false(client.module.receive_territory(bad))
	assert_eq(client.side.applied, 0, "nothing reached the replica")
	assert_true(client.side.raster_value.owner_bytes() == before, "the raster is untouched")
	assert_signal_not_emitted(Events, "territory_replicated")
	assert_true(client.module.receive_territory(good), "the intact packet still applies afterwards")


# --- Host tick cadences ---------------------------------------------------------------

func test_territory_ticks_at_raster_diff_hz() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 1, 1)
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 0, "half a period")
	_set_cell(rig, 2, 1)
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 1, "a full period")
	_set_cell(rig, 3, 1)
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 1, "the period restarted")
	_set_cell(rig, 4, 1)
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 2)


func test_the_cat_state_ticks_at_cursor_hz() -> void:
	var rig: Rig = _rig()
	var cat: CatController = CatController.new()
	cat.activation_id = 4
	cat.time_left = 2.5
	add_child_autofree(cat)
	cat.global_position = Vector3(1.0, 0.0, 2.0)
	rig.host.cat_value = cat
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_cat_state").size(), 0)
	rig.module.tick_host_feeds(HALF_STEP_S)
	var states: Array[Array] = rig.spy.broadcasts_of(&"net_cat_state")
	assert_eq(states.size(), 1)
	if states.size() == 1:
		assert_eq(states[0], [4, Vector3(1.0, 0.0, 2.0), cat.linear_velocity, cat.target, 2.5])
	rig.host.cat_value = null
	rig.module.tick_host_feeds(1.0)
	assert_eq(rig.spy.broadcasts_of(&"net_cat_state").size(), 1, "no cat, no state")


func test_live_scores_tick_at_scoreboard_hz_and_only_while_live() -> void:
	var rig: Rig = _rig()
	rig.host.state_value = MatchPhase.State.COUNTDOWN
	rig.module.tick_host_feeds(1.0)
	assert_eq(rig.spy.broadcasts_of(&"net_match_event").size(), 0, "not live")
	rig.host.state_value = MatchPhase.State.PLAYING
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_match_event").size(), 0)
	rig.module.tick_host_feeds(HALF_STEP_S)
	var events: Array[Array] = rig.spy.broadcasts_of(&"net_match_event")
	assert_eq(events.size(), 1)
	if events.size() == 1:
		assert_eq(events[0], [MatchWireEvents.LIVE_SCORES, [StatsSpy.new().build_live_payload()]])


func test_impacts_batch_at_impact_batch_hz_to_every_ready_peer() -> void:
	var rig: Rig = _rig()
	rig.module.on_block_impacted_at(6.0, Vector3(1.0, 1.0, 1.0))
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.sent.size(), 0)
	rig.module.tick_host_feeds(HALF_STEP_S)
	var batches: Array[Dictionary] = rig.spy.sends_of(&"net_block_impacts")
	assert_eq(batches.size(), 2)
	var peers: Array[int] = []
	for batch: Dictionary in batches:
		peers.append(int(batch["peer"]))
		assert_false(((batch["args"] as Array)[0] as PackedByteArray).is_empty())
	peers.sort()
	assert_eq(peers, [PEER_A, PEER_B] as Array[int])
	rig.module.tick_host_feeds(1.0)
	assert_eq(rig.spy.sends_of(&"net_block_impacts").size(), 2, "a sent window is not sent again")


func test_impacts_are_withheld_from_a_peer_with_a_pending_replay() -> void:
	var rig: Rig = _rig()
	rig.spy.pending = {PEER_B: true}
	rig.module.on_block_impacted_at(6.0, Vector3(1.0, 1.0, 1.0))
	rig.module.tick_host_feeds(1.0)
	var batches: Array[Dictionary] = rig.spy.sends_of(&"net_block_impacts")
	assert_eq(batches.size(), 1)
	if batches.size() == 1:
		assert_eq(int(batches[0]["peer"]), PEER_A)


func test_an_impact_with_nobody_to_hear_it_is_not_queued() -> void:
	var rig: Rig = _rig()
	rig.spy.peers = [] as Array[int]
	rig.module.on_block_impacted_at(6.0, Vector3(1.0, 1.0, 1.0))
	rig.spy.peers = [PEER_A] as Array[int]
	rig.module.tick_host_feeds(1.0)
	assert_eq(rig.spy.sent.size(), 0)


func test_zero_hz_never_sends_and_never_divides_by_zero() -> void:
	var rig: Rig = _rig(null, true)
	rig.host.state_value = MatchPhase.State.PLAYING
	var cat: CatController = CatController.new()
	add_child_autofree(cat)
	rig.host.cat_value = cat
	rig.config.raster_diff_hz = 0.0
	rig.config.cursor_hz = 0.0
	rig.config.scoreboard_hz = 0.0
	rig.config.impact_batch_hz = 0.0
	rig.module.on_block_impacted_at(6.0, Vector3(1.0, 1.0, 1.0))
	for i: int in range(10):
		_set_cell(rig, i, 1)
		rig.module.tick_host_feeds(1.0)
	assert_eq(rig.spy.broadcasts.size(), 0)
	assert_eq(rig.spy.sent.size(), 0)


# --- Client impacts -------------------------------------------------------------------

func test_a_received_impact_plays_at_once_without_a_view_delay() -> void:
	var rig: Rig = _rig(FakeNet.client(1))
	rig.module.receive_impacts(_impact_packet(6.5, Vector3(1.0, 2.0, 3.0)))
	assert_eq(_at_events.size(), 1)
	assert_eq(_speed_events.size(), 1, "both impact signals fire")
	if _at_events.size() == 1:
		assert_almost_eq(float(_at_events[0][0]), 6.5, ImpactWire.SPEED_QUANTUM)
		assert_almost_eq((_at_events[0][1] as Vector3).x, 1.0, ImpactWire.POSITION_QUANTUM_M)
	rig.module.play_due_impacts()
	assert_eq(_at_events.size(), 1, "an impact plays once")


func test_a_received_impact_waits_for_the_view_delay() -> void:
	var rig: Rig = _rig(FakeNet.client(1))
	rig.spy.delay = VIEW_DELAY_MS
	rig.module.receive_impacts(_impact_packet(6.5, Vector3(1.0, 2.0, 3.0)))
	assert_eq(_at_events.size(), 0, "the view is still %d ms behind it" % VIEW_DELAY_MS)
	rig.spy.now = NOW_MS + VIEW_DELAY_MS - 1
	rig.module.play_due_impacts()
	assert_eq(_at_events.size(), 0, "one millisecond short")
	rig.spy.now = NOW_MS + VIEW_DELAY_MS
	rig.module.play_due_impacts()
	assert_eq(_at_events.size(), 1)
	assert_eq(_speed_events.size(), 1)


func test_clear_impacts_drops_what_is_still_queued() -> void:
	var rig: Rig = _rig(FakeNet.client(1))
	rig.spy.delay = VIEW_DELAY_MS
	rig.module.receive_impacts(_impact_packet(6.5, Vector3.ONE))
	rig.module.clear_impacts()
	rig.spy.now = NOW_MS + 10 * VIEW_DELAY_MS
	rig.module.play_due_impacts()
	assert_eq(_at_events.size(), 0)


# --- reset() ----------------------------------------------------------------------------

func test_reset_keeps_queued_impacts_and_the_start_flag() -> void:
	var rig: Rig = _rig(FakeNet.client(1))
	rig.spy.delay = VIEW_DELAY_MS
	rig.module.receive_impacts(_impact_packet(6.5, Vector3.ONE))
	rig.module.reset()
	rig.spy.now = NOW_MS + VIEW_DELAY_MS
	rig.module.play_due_impacts()
	assert_eq(_at_events.size(), 1, "a queued impact survives the boundary reset")

	var host: Rig = _rig()
	host.module.send_match_start(host.host.config_value)
	host.module.reset()
	host.module.send_match_start(host.host.config_value)
	assert_eq(host.spy.broadcasts_of(&"net_match_start").size(), 1)


func test_reset_zeroes_the_cat_timer_but_keeps_the_impact_timer() -> void:
	var rig: Rig = _rig()
	var cat: CatController = CatController.new()
	add_child_autofree(cat)
	rig.host.cat_value = cat
	rig.module.on_block_impacted_at(6.0, Vector3.ONE)
	rig.module.tick_host_feeds(HALF_STEP_S)
	rig.module.reset()
	rig.module.tick_host_feeds(HALF_STEP_S)
	assert_eq(rig.spy.broadcasts_of(&"net_cat_state").size(), 0, "the cat period restarted")
	assert_eq(rig.spy.sends_of(&"net_block_impacts").size(), 2, "the impact period did not")


func test_reset_rebuilds_the_territory_baseline() -> void:
	var rig: Rig = _rig(null, true)
	_set_cell(rig, 4, 1)
	rig.module.send_territory()
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 1)
	rig.module.reset()
	rig.module.send_territory()
	assert_eq(rig.spy.broadcasts_of(&"net_territory").size(), 2, "a fresh baseline sends a keyframe")


# --- Rebinding and match-state transitions ------------------------------------------------

## Impacts at well-separated cells, so none coalesce into another.
func _collect_spread(rig: Rig, count: int) -> void:
	for i: int in range(count):
		rig.module.on_block_impacted_at(6.0 + float(i), Vector3(10.0 * float(i), 1.0, 0.0))


## How many impact events the host's net_block_impacts batches carry to PEER_A, counted by playing
## them into a client module.
func _impacts_sent_to_peer_a(rig: Rig) -> int:
	var client: Rig = _rig(FakeNet.client(1))
	for batch: Dictionary in rig.spy.sends_of(&"net_block_impacts"):
		if int(batch["peer"]) == PEER_A:
			client.module.receive_impacts((batch["args"] as Array)[0] as PackedByteArray)
	return _at_events.size()


func test_binding_a_different_config_applies_its_batch_limit() -> void:
	var rig: Rig = _rig()
	_collect_spread(rig, 1)
	rig.module.tick_host_feeds(1.0)
	rig.spy.sent.clear()
	var tight: NetConfig = NetConfig.new()
	tight.impact_batch_hz = HZ
	tight.impact_max_per_batch = 1
	rig.module.bind(rig.session, rig.host, rig.replica, tight)
	_collect_spread(rig, 3)
	rig.module.tick_host_feeds(1.0)
	assert_eq(_impacts_sent_to_peer_a(rig), 1, "the new config caps a batch at one event")


func test_binding_a_different_config_drops_impacts_queued_under_the_old_one() -> void:
	var rig: Rig = _rig()
	_collect_spread(rig, 2)
	var other: NetConfig = NetConfig.new()
	other.impact_batch_hz = HZ
	rig.module.bind(rig.session, rig.host, rig.replica, other)
	rig.module.tick_host_feeds(1.0)
	assert_eq(rig.spy.sends_of(&"net_block_impacts").size(), 0, "nothing queued survives a new config")


func test_binding_the_same_config_keeps_queued_impacts() -> void:
	var rig: Rig = _rig()
	_collect_spread(rig, 2)
	rig.module.bind(rig.session, rig.host, rig.replica, rig.config)
	rig.module.tick_host_feeds(1.0)
	assert_eq(_impacts_sent_to_peer_a(rig), 2, "both impacts queued before the rebind go out")


func test_end_keeps_queued_impacts_and_lobby_or_loading_clear_them() -> void:
	for state: int in [
		MatchPhase.State.COUNTDOWN, MatchPhase.State.PLAYING,
		MatchPhase.State.SUDDEN_DEATH, MatchPhase.State.END,
	]:
		_at_events.clear()
		var kept: Rig = _rig(FakeNet.client(1))
		kept.spy.delay = VIEW_DELAY_MS
		kept.module.receive_impacts(_impact_packet(6.5, Vector3.ONE))
		kept.module.on_match_state_changed(state)
		kept.spy.now = NOW_MS + VIEW_DELAY_MS
		kept.module.play_due_impacts()
		assert_eq(_at_events.size(), 1, "state %d keeps the queue" % state)
	for state: int in [MatchPhase.State.LOBBY, MatchPhase.State.LOADING]:
		_at_events.clear()
		var cleared: Rig = _rig(FakeNet.client(1))
		cleared.spy.delay = VIEW_DELAY_MS
		cleared.module.receive_impacts(_impact_packet(6.5, Vector3.ONE))
		cleared.module.on_match_state_changed(state)
		cleared.spy.now = NOW_MS + 10 * VIEW_DELAY_MS
		cleared.module.play_due_impacts()
		assert_eq(_at_events.size(), 0, "state %d clears the queue" % state)
