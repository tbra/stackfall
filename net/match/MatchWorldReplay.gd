class_name MatchWorldReplay
extends RefCounted
## Mid-match join for the host: seats a peer who arrives after the match started, builds the world
## replay it is sent, tracks its acknowledgement and kicks a peer that never acknowledges.
##
## One replay per peer at a time. The rows are built synchronously, so every broadcast the joiner
## dropped before its net_match_start is already folded in, and every broadcast after it applies on
## top in order. The end marker is deferred to the end of the frame; the joiner answers it with
## net_replay_ack, which lifts the gateway's replay-pending gate (`is_pending`).
##
## This is a RefCounted collaborator owned by the MatchNet node. It never reads the remote sender id
## (the RPC stub passes it in), never touches a transport (everything that leaves goes through
## `Seams`), and reaches the session and Match only through SessionPort / MatchHostPort.

const RPC_MATCH_START: StringName = &"net_match_start"
const RPC_SPAWNED: StringName = &"net_block_spawned"
const RPC_TERRITORY: StringName = &"net_territory"
const RPC_MATCH_EVENT: StringName = &"net_match_event"
const RPC_REPLAY_END: StringName = &"net_replay_end"

## [ready_peer_ids, required_peer_ids, open], the shape of the loading_gate event.
const LOADING_GATE_ARGS: int = 3

const _SESSION_METHODS: PackedStringArray = ["is_host", "is_offline", "peer_ids", "peer_info", "kick_peer"]
const _HOST_METHODS: PackedStringArray = [
	"config", "state", "slot_count", "slot", "on_peer_rejoined", "registry", "active_cat", "active_slot",
	"countdown_remaining", "match_timer_left", "mode_state_snapshot", "eliminated_by", "qol_backlog_count",
	"qol_timer_paused", "gift_slot_contents", "gift_states", "glue_drops_left", "glue_revision",
]


## Everything the replay needs from the facade that is not session or Match state. All Callables are
## bound by MatchNet; a test binds spies.
class Seams extends RefCounted:
	## (peer_id: int, method: StringName, args: Array) -> bool : one addressed send.
	var send_to_peer: Callable = Callable()
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()
	## (slot_id: int) -> void : forget the slot's last cursor pose (a joiner has none).
	var clear_cursor: Callable = Callable()
	## (block: BlockBody, net_id: int) -> Array : the net_block_spawned arguments.
	var spawn_args: Callable = Callable()
	## () -> Array : net ids of glued or glue-coated blocks.
	var glued_ids: Callable = Callable()
	## () -> Array : net_territory arguments for one full keyframe, or [].
	var territory_args: Callable = Callable()
	## (slot_id: int) -> Array : the slot_replay payload, or [].
	var slot_replay_args: Callable = Callable()
	## () -> void : the world is replayed, so the snapshot stream owes this peer a full snapshot.
	var replay_acknowledged: Callable = Callable()


var _session: SessionPort = null
var _host: MatchHostPort = null
var _config: NetConfig = null
var _seams: Seams = null
var _flood: PeerFloodGate = null
var _valid: bool = false

## peer_id -> replay id sent and not yet acknowledged.
var _pending: Dictionary = {}
## peer_id -> now_s the replay went out.
var _sent_at_s: Dictionary = {}
var _next_replay_id: int = 1


## `session_node` / `match_node` are the ports MatchNet shares, or the Net and Match autoloads (or test
## doubles), which are bound with exactly the subset of the ports this class calls.
func _init(session_node: Object, match_node: Object, config: NetConfig, seams: Seams) -> void:
	_session = session_node as SessionPort if session_node is SessionPort else SessionPort.new(session_node, _SESSION_METHODS)
	_host = match_node as MatchHostPort if match_node is MatchHostPort else MatchHostPort.new(match_node, _HOST_METHODS)
	_config = config
	_seams = seams
	if config != null:
		_flood = PeerFloodGate.new(FloodLimits.from_config(config))
	_valid = _session.is_valid() and _host.is_valid() and config != null and seams != null


## A peer was seated on `slot_id`. Inside a disconnect grace the slot's feed resumes; mid-match the
## peer is owed the whole world as one ordered replay (in the lobby the broadcast match start
## carries it). Host only.
func on_peer_joined(peer_id: int, slot_id: int, _name: String) -> void:
	if not _valid or not _session.is_host():
		return
	if slot_id >= 0:
		_host.on_peer_rejoined(slot_id)
		# Whoever sat here before left a ghost the host would auto-drop from.
		_seams.clear_cursor.call(slot_id)
	if _session.is_offline() or not MatchPhase.is_replicating(_host.state()) or _pending.has(peer_id):
		return
	_send_replay(peer_id, slot_id)


## A peer left, was kicked or dropped before it finished the handshake: its pending replay and its
## flood bucket go, so a rejoin starts clean.
func on_peer_left(peer_id: int) -> void:
	_pending.erase(peer_id)
	_sent_at_s.erase(peer_id)
	if _flood != null:
		_flood.forget_peer(peer_id)


## A match (re)start is itself a full sync for every peer, so no replay is still owed an ack.
func reset() -> void:
	_pending.clear()
	_sent_at_s.clear()


## The ordered `[method: StringName, args: Array]` rows that rebuild the world for `peer_id`; the
## production sender `rpc_id`s each row. The opening net_match_start carries the pending replay id
## (when `peer_id` has one) so the joiner mutes one-shot feedback until net_replay_end.
func build_replay(peer_id: int, _slot_id: int) -> Array[Array]:
	var rows: Array[Array] = []
	if not _valid:
		push_error("MatchWorldReplay.build_replay on an unbound instance")
		return rows
	var running: MatchConfig = _host.config()
	if running == null:
		return rows
	var start_args: Array = [running.to_dict(), _roster()]
	var replay_id: int = int(_pending.get(peer_id, 0))
	if replay_id > 0:
		start_args.append(replay_id)
	rows.append([RPC_MATCH_START, start_args])
	_append_world(rows)
	var territory: Array = _seams.territory_args.call() as Array
	if not territory.is_empty():
		rows.append([RPC_TERRITORY, territory])
	_append_derived_state(rows)
	return rows


## The peer reports its replay applied. Only the id the host actually sent this peer counts: a stale
## or forged ack is ignored, and a flood of acks is dropped silently by the replay-ack bucket.
func handle_replay_ack(sender: int, replay_id: int) -> void:
	if not _valid or not _session.is_host():
		return
	if not _flood.allow(sender, FloodLimits.INTENT_REPLAY_ACK, _seams.now_s.call() as float):
		return
	if int(_pending.get(sender, -1)) != replay_id:
		return
	_pending.erase(sender)
	_sent_at_s.erase(sender)
	_seams.replay_acknowledged.call()


## True while `peer_id` has been sent a replay it has not acknowledged. Bound to the gateway's
## `Seams.is_replay_pending`.
func is_pending(peer_id: int) -> bool:
	return _pending.has(peer_id)


## Kicks (through SessionPort.kick_peer) every peer whose replay has gone unacknowledged for
## `NetConfig.replay_ack_timeout`.
## DECISION: drop, not retry. A second replay would re-send spawns for bodies the first one may
## already have created; a peer that cannot ack within the timeout is not going to play, and it can
## rejoin (its reservation applies).
func tick_timeouts(now_s: float) -> void:
	if _pending.is_empty():
		return
	var expired: Array[int] = []
	for peer_id: int in _pending:
		if now_s - float(_sent_at_s.get(peer_id, now_s)) >= _config.replay_ack_timeout:
			expired.append(peer_id)
	for peer_id: int in expired:
		_pending.erase(peer_id)
		_sent_at_s.erase(peer_id)
		_session.kick_peer(peer_id, _session.timeout_leave_reason())


func _send_replay(peer_id: int, slot_id: int) -> void:
	var replay_id: int = _next_replay_id
	_next_replay_id += 1
	_pending[peer_id] = replay_id
	_sent_at_s[peer_id] = _seams.now_s.call() as float
	for row: Array in build_replay(peer_id, slot_id):
		_seams.send_to_peer.call(peer_id, StringName(row[0]), row[1] as Array)
	_finish_replay.call_deferred(peer_id, replay_id)


## Sends the end marker unless the peer left (or a restart cleared the pending replay) meanwhile.
func _finish_replay(peer_id: int, replay_id: int) -> void:
	if int(_pending.get(peer_id, -1)) != replay_id:
		return
	_seams.send_to_peer.call(peer_id, RPC_REPLAY_END, [replay_id])


func _roster() -> Array:
	var roster: Array = []
	for peer_id: int in _session.peer_ids():
		roster.append(_session.peer_info(peer_id))
	return roster


func _event(event: StringName, args: Array) -> Array:
	return [RPC_MATCH_EVENT, [event, args]]


## One net_block_spawned per body, then hole dissolves, icy overlays and glue coats.
func _append_world(rows: Array[Array]) -> void:
	# DECISION (D8): the registry is held as a Node and called dynamically; the typed
	# Array[Block] result is kept in an untyped Array so this file names no Block.
	var registry: Node = _host.registry()
	if registry == null:
		return
	var blocks: Array = registry.all_blocks()
	blocks.sort_custom(func(a: BlockBody, b: BlockBody) -> bool: return a.net_id < b.net_id)
	var dissolving: Array[int] = []
	for block: BlockBody in blocks:
		if not Quantize.is_wire_id(block.net_id):
			continue
		rows.append([RPC_SPAWNED, _seams.spawn_args.call(block, block.net_id) as Array])
		if registry.hole_dissolver().is_dissolving(block):
			dissolving.append(block.net_id)
	for net_id: int in dissolving:
		rows.append(_event(MatchWireEvents.BLOCK_DISSOLVE_STARTED, [net_id]))
	# Freeze gift: the icy overlay is an event, not part of the spawn args.
	for block: BlockBody in blocks:
		if block.is_frozen_visual() and block.net_id > 0:
			rows.append(_event(MatchWireEvents.BLOCK_FROZEN, [block.net_id, true]))
	for glued_id: int in _seams.glued_ids.call() as Array:
		rows.append(_event(MatchWireEvents.BLOCK_GLUED, [glued_id, true]))


## Match state, clock, mode objective, eliminations, turn, every slot's feed and gifts, glue charges,
## QoL, gift crates and the cat.
func _append_derived_state(rows: Array[Array]) -> void:
	var state: int = _host.state()
	if state == MatchPhase.State.COUNTDOWN:
		rows.append(_event(MatchWireEvents.COUNTDOWN, [int(ceil(_host.countdown_remaining()))]))
		# The ready gate lives only through the countdown; sent after net_match_start (whose
		# start_match() resets the joiner's mirror), so the joiner holds the host's current sets.
		var gate_args: Array = _host.loading_gate_replay_args()
		if gate_args.size() == LOADING_GATE_ARGS:
			rows.append(_event(MatchWireEvents.LOADING_GATE, gate_args))
	elif MatchPhase.is_live(state):
		# A client's own start_match() leaves it in COUNTDOWN; PLAYING is replayed before
		# SUDDEN_DEATH so its consumers see the order a seated client saw.
		rows.append(_event(MatchWireEvents.STATE_CHANGED, [MatchPhase.State.PLAYING]))
		if state == MatchPhase.State.SUDDEN_DEATH:
			rows.append(_event(MatchWireEvents.STATE_CHANGED, [MatchPhase.State.SUDDEN_DEATH]))
	rows.append(_event(MatchWireEvents.MATCH_CLOCK, [_host.match_timer_left()]))

	var mode_snapshot: Dictionary = _host.mode_state_snapshot()
	if not mode_snapshot.is_empty():
		rows.append(_event(MatchWireEvents.MODE_STATE, [mode_snapshot]))

	var slot_count: int = _host.slot_count()
	for slot_id: int in range(slot_count):
		var seat: PlayerSlot = _host.slot(slot_id)
		if seat != null and not seat.home_flag_alive:
			rows.append(_event(MatchWireEvents.PLAYER_ELIMINATED, [slot_id, seat.team_id, _host.eliminated_by(slot_id)]))
	if _host.active_slot() >= 0:
		rows.append(_event(MatchWireEvents.TURN_CHANGED, [_host.active_slot()]))
	for slot_id: int in range(slot_count):
		var slot_args: Array = _seams.slot_replay_args.call(slot_id) as Array
		if not slot_args.is_empty():
			rows.append(_event(MatchWireEvents.SLOT_REPLAY, slot_args))
	for slot_id: int in range(slot_count):
		var revision: int = _host.glue_revision(slot_id)
		if revision > 0:
			rows.append(_event(MatchWireEvents.GLUE_CHARGES, [slot_id, _host.glue_drops_left(slot_id), revision]))
	# A late joiner's HUD mirror starts at zero/unpaused, so replay each slot's non-default QoL state.
	for slot_id: int in range(slot_count):
		var backlog: int = _host.qol_backlog_count(slot_id)
		var paused: bool = _host.qol_timer_paused(slot_id)
		if backlog > 0 or paused:
			rows.append(_event(MatchWireEvents.QOL_FEED, [slot_id, backlog, paused]))
	for slot_id: int in range(slot_count):
		var slotted: Array[StringName] = _host.gift_slot_contents(slot_id)
		if not slotted.is_empty():
			rows.append(_event(MatchWireEvents.GIFT_SLOT, [slot_id, slotted, &"", &""]))
	for gift: Dictionary in _host.gift_states():
		var gift_id: int = int(gift["id"])
		if int(gift["phase"]) == GiftWirePhase.FALLING:
			rows.append(_event(MatchWireEvents.GIFT_FLIGHT, [gift_id, gift["origin"], gift["landing"]]))
		else:
			rows.append(_event(MatchWireEvents.GIFT_SPAWNED, [gift_id, gift["position"]]))
	var cat: RigidBody3D = _host.active_cat()
	if cat != null:
		rows.append(_event(MatchWireEvents.CAT_STARTED, [cat.activation_id, cat.owner_slot, cat.global_position, cat.time_left]))
