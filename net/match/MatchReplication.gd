class_name MatchReplication
extends RefCounted
## Territory, impacts and match-start, both directions, and the host tick feeds that carry them.
## Owns the TerritoryReplicator and ImpactReplicator.

## Floor for a send rate, so a zero hz never divides by zero (it just sends very rarely).
const MIN_HZ: float = 0.001

const NET_BLOCK_SPAWNED: StringName = &"net_block_spawned"
const NET_BLOCK_DESPAWNED: StringName = &"net_block_despawned"
const NET_TERRITORY: StringName = &"net_territory"
const NET_MATCH_EVENT: StringName = &"net_match_event"
const NET_MATCH_START: StringName = &"net_match_start"
const NET_MATCH_LOADING: StringName = &"net_match_loading"
const NET_BLOCK_IMPACTS: StringName = &"net_block_impacts"
const NET_CAT_STATE: StringName = &"net_cat_state"

class Seams extends RefCounted:
	## () -> bool
	var can_send: Callable = Callable()
	## (method: StringName, args: Array) -> void
	var broadcast: Callable = Callable()
	## (peer_id: int, method: StringName, args: Array) -> bool
	var send_to_peer: Callable = Callable()
	## () -> Array[int]
	var peer_ids: Callable = Callable()
	## (peer_id: int) -> bool
	var is_replay_pending: Callable = Callable()
	## () -> int
	var now_ms: Callable = Callable()
	## () -> int : the snapshot interpolation delay while SnapshotSync runs, else 0.
	var view_delay_ms: Callable = Callable()


## Seams are bound by MatchNet; the module touches no autoload.
var _seams: Seams
var _mirror: MatchEventMirror
var _session: SessionPort
var _host: MatchHostPort
var _replica: MatchReplicaPort
var _config: NetConfig
var _territory: TerritoryReplicator = null
var _impacts: ImpactReplicator = null
## True once send_match_start() has gone out for the running match, so a lobby that calls it
## explicitly and the automatic send on LOADING cannot both fire.
var _match_start_sent: bool = false
var _impact_send_accum: float = 0.0
var _raster_send_accum: float = 0.0
var _cat_send_accum: float = 0.0
var _scores_send_accum: float = 0.0


func _init(seams: Seams, mirror: MatchEventMirror) -> void:
	_seams = seams
	_mirror = mirror


## First build and every rebind: swaps refs and rebuilds the territory replicator; KEEPS the
## start-sent flag and, while the config object is the same, the impact queue and accumulators.
## A different config rebuilds the impact replicator too (it reads its limits from it).
func bind(session: SessionPort, host: MatchHostPort, replica: MatchReplicaPort, config: NetConfig) -> void:
	_session = session
	_host = host
	_replica = replica
	if config != _config:
		_impacts = null
	_config = config
	_territory = TerritoryReplicator.new(_host, _replica, _config)


## Host -> clients.
## Announces a block the host just spawned, reliably, before any snapshot can reference it. A body
## without a wire id (net_id allocation failed) lives on the host only: sending it would build a
## phantom client copy no despawn could address.
func send_spawn(block: BlockBody, net_id: int) -> void:
	if not _session.is_host() or block == null or not Quantize.is_wire_id(net_id) or not _seams.can_send.call():
		return
	_seams.broadcast.call(NET_BLOCK_SPAWNED, spawn_args(block, net_id))


func send_despawn(net_id: int, reason: String) -> void:
	if not _session.is_host() or net_id < 0 or not _seams.can_send.call():
		return
	_seams.broadcast.call(NET_BLOCK_DESPAWNED, [net_id, reason])


## Sends TerritoryReplicator's packet (changed raster cells or a keyframe, shares, capture ring,
## circles). Nothing goes out when nothing changed.
func send_territory() -> void:
	if not _session.is_host() or not _seams.can_send.call():
		return
	var packet: PackedByteArray = _territory.encode_diff()
	if not packet.is_empty():
		_seams.broadcast.call(NET_TERRITORY, _territory_rpc_args(packet))


## Mirrors a match-flow event to every client.
func send_match_event(event: StringName, args: Array) -> void:
	if not _session.is_host() or not _seams.can_send.call():
		return
	_seams.broadcast.call(NET_MATCH_EVENT, [event, args])


## Ships the whole match start (sanitized MatchConfig, roster, seed 0). Idempotent for one match.
## The flag is consumed even when nothing can be sent, as it was before the cut.
func send_match_start(match_config: MatchConfig) -> void:
	if not _session.is_host() or match_config == null or _match_start_sent:
		return
	_match_start_sent = true
	_territory.force_full()
	if not _seams.can_send.call():
		return
	_seams.broadcast.call(NET_MATCH_START, [match_config.to_dict(), _session.roster(), 0])


## One reliable message ahead of net_match_start so a client can raise its loading overlay.
func send_match_loading() -> void:
	if not _session.is_host() or not _seams.can_send.call():
		return
	_seams.broadcast.call(NET_MATCH_LOADING, [])


## net_block_spawned's argument list: the one wire shape a live spawn and a join replay share.
## owner_slot is the block's current slot, so a Paintball conversion replays as the new colour.
func spawn_args(block: BlockBody, net_id: int) -> Array:
	var basis: Basis = block.global_transform.basis.orthonormalized()
	return [
		net_id,
		block.shape_id,
		block.owner_slot,
		block.global_position,
		basis.get_rotation_quaternion(),
		block.gift_id,
	]


## net_territory's arguments for one full keyframe, or [] with no raster.
func territory_replay_args() -> Array:
	var packet: PackedByteArray = _territory.encode_full()
	return [] if packet.is_empty() else _territory_rpc_args(packet)


## True = a new match is LOADING (caller runs reset_counters then send_match_start).
## DECISION: impacts clear on LOBBY|LOADING only; END is excluded so impacts already queued still
## play into the results screen.
func on_match_state_changed(to_state: int) -> bool:
	if MatchPhase.is_resetting(to_state) and to_state != MatchPhase.State.END:
		clear_impacts()
	if not _session.is_host():
		return false
	if to_state == MatchPhase.State.LOADING:
		_match_start_sent = false
		return true
	if to_state == MatchPhase.State.LOBBY:
		_match_start_sent = false
	return false


## Host: one detected impact. Only collected while someone can hear it.
func on_block_impacted_at(speed: float, position: Vector3) -> void:
	if not _session.is_host() or not _impact_audience():
		return
	_impact_replicator().collect(speed, position, _seams.now_ms.call())


## Host timers: impact batches, the cat state, live scores and the territory diff.
func tick_host_feeds(delta: float) -> void:
	if not _session.is_host():
		return
	_impact_send_accum += delta
	if _impact_send_accum >= 1.0 / maxf(_config.impact_batch_hz, MIN_HZ):
		_impact_send_accum = 0.0
		_send_impacts()
	var cat: RigidBody3D = _host.active_cat()
	if cat != null and _seams.can_send.call():
		_cat_send_accum += delta
		if _cat_send_accum >= 1.0 / maxf(_config.cursor_hz, MIN_HZ):
			_cat_send_accum = 0.0
			_seams.broadcast.call(NET_CAT_STATE, [cat.activation_id, cat.global_position,
				cat.linear_velocity, cat.target, cat.time_left])
	if MatchPhase.is_live(_host.state()):
		_scores_send_accum += delta
		if _scores_send_accum >= 1.0 / maxf(_config.scoreboard_hz, MIN_HZ):
			_scores_send_accum = 0.0
			var stats: RefCounted = _host.stats()
			_mirror.on_live_scores(stats.call(&"build_live_payload") as Dictionary)
	_raster_send_accum += delta
	if _raster_send_accum >= 1.0 / maxf(_config.raster_diff_hz, MIN_HZ):
		_raster_send_accum = 0.0
		send_territory()


## Client side.
## A malformed packet is dropped whole (false).
func receive_territory(packet: PackedByteArray) -> bool:
	return _territory.apply(packet)


func receive_impacts(packet: PackedByteArray) -> void:
	if _impact_replicator().receive(packet, _seams.now_ms.call()):
		play_due_impacts()


## Plays every queued impact the interpolated view (the snapshot delay behind now) has reached.
func play_due_impacts() -> void:
	var view_ms: float = float(_seams.now_ms.call()) - float(_seams.view_delay_ms.call())
	for row: Array in _impact_replicator().drain(view_ms):
		_emit_impact(float(row[0]), row[1] as Vector3)


func clear_impacts() -> void:
	_impacts = null
	_impact_send_accum = 0.0


## Zeroes the cat accumulator and rebuilds the territory replicator; keeps impacts and the flag.
func reset() -> void:
	_cat_send_accum = 0.0
	_territory = TerritoryReplicator.new(_host, _replica, _config)


func _impact_audience() -> bool:
	return _seams.can_send.call() and not (_seams.peer_ids.call() as Array).is_empty()


## Sends the current impact window as one batch to every peer that has its world. A mid-match
## joiner still loading its replay hears nothing yet; impacts are never part of it.
func _send_impacts() -> void:
	var packet: PackedByteArray = _impact_replicator().flush(_seams.now_ms.call())
	if packet.is_empty() or not _seams.can_send.call():
		return
	for peer_id: int in _seams.peer_ids.call():
		if not _seams.is_replay_pending.call(peer_id):
			_seams.send_to_peer.call(peer_id, NET_BLOCK_IMPACTS, [packet])


## The same pair game/blocks/Block.gd emits on the host, so Sfx, CameraRig, Rumble and dust need
## nothing network-aware.
func _emit_impact(speed: float, position: Vector3) -> void:
	Events.block_impacted.emit(speed)
	Events.block_impacted_at.emit(speed, position)


func _impact_replicator() -> ImpactReplicator:
	if _impacts == null:
		_impacts = ImpactReplicator.new(_config, TokenBucket.new())
	return _impacts


## net_territory's arguments: the packet, then neutral values for the slots the packet now carries.
func _territory_rpc_args(packet: PackedByteArray) -> Array:
	return [packet, false, PackedFloat32Array(), -1, 0.0]
