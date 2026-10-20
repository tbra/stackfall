class_name MatchIntentGateway
extends RefCounted
## The door every gameplay intent goes through (spec 2.6): the local `submit_*` half that turns
## a player action into a direct Match call (host) or an RPC to the host (client), and the host
## `handle_*` half that checks a remote intent before Match ever sees it: peer identity, slot
## ownership, replay-pending gate, replay protection, numeric validation, then the mutation.
##
## Every host `handle_*` first asks the per-peer PeerFloodGate (limits from FloodLimits /
## NetConfig). A flooded call is dropped silently: no refusal reply (a reply is itself
## an amplification), no rebroadcast, no Match call, and never a kick (a client on a bad link must
## never be removed for bursting). Ordinary refusals (wrong slot, stale feed_seq, bad pose) still
## answer the sender so its ghost unlocks.
##
## This is a RefCounted collaborator owned by the MatchNet node. It never reads the remote sender
## id (the RPC stub does and passes it in), never touches a transport (everything that leaves goes
## through `Seams` callables the facade binds), and reaches the session and Match only through
## SessionPort / MatchHostPort.

const _SESSION_METHODS: PackedStringArray = ["is_host", "slot_of_peer"]
const _HOST_METHODS: PackedStringArray = [
	"state", "request_place", "request_throw", "request_use_gift_slot", "set_cat_target", "is_pose_well_formed",
]

## Floor for cursor_hz so a zeroed config cannot divide by zero (the same guard MatchNet used).
const MIN_SEND_HZ: float = 0.001
const RPC_PLACE: StringName = &"net_request_place"
const RPC_THROW: StringName = &"net_request_throw"
const RPC_GIFT_SLOT: StringName = &"net_request_use_gift_slot"
const RPC_CURSOR: StringName = &"net_update_cursor"
const RPC_CAT_TARGET: StringName = &"net_cat_target"
const RPC_REPLAY: StringName = &"net_request_replay"
const RPC_RETURN: StringName = &"net_request_return_to_lobby"
const BROADCAST_CURSOR: StringName = &"net_cursor"


## Everything the gateway needs from the facade that is not session or Match state. All Callables
## are bound by MatchNet; a test binds spies.
class Seams extends RefCounted:
	## () -> bool : a live transport that may be addressed (NetFanout.can_send).
	var can_send: Callable = Callable()
	## (method: StringName, args: Array) -> void : rpc_id to the host.
	var send_to_host: Callable = Callable()
	## (peer_id: int, method: StringName, args: Array) -> bool : one addressed send.
	var send_to_peer: Callable = Callable()
	## (method: StringName, args: Array) -> void : the host broadcast.
	var broadcast: Callable = Callable()
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()
	## (peer_id: int) -> bool : the peer has been sent a world replay it has not acknowledged.
	var is_replay_pending: Callable = Callable()
	## (slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void.
	var store_cursor: Callable = Callable()


var _session: SessionPort = null
var _host: MatchHostPort = null
var _config: NetConfig = null
var _counters: NetCounters = null
var _seams: Seams = null
var _flood: PeerFloodGate = null
var _valid: bool = false

## Client: when the last cursor / cat target went out (the send throttle).
var _cursor_last_send_s: float = 0.0
var _cat_target_last_send_s: float = -1.0
## The slot whose refusal the placement_rejected listener already sent to its owning peer while the
## current intent was being applied, so the handler's own tail reply is not a second copy. -1 = none.
var _reject_replied_slot: int = -1


## `session_node` / `match_node` are the Net and Match autoloads (or test doubles); they are bound
## with exactly the subset of the ports this class calls.
func _init(
	session_node: Object, match_node: Object, config: NetConfig, counters: NetCounters, seams: Seams
) -> void:
	_session = SessionPort.new(session_node, _SESSION_METHODS)
	_host = MatchHostPort.new(match_node, _HOST_METHODS)
	_config = config
	_counters = counters
	_seams = seams
	_flood = PeerFloodGate.new(FloodLimits.from_config(config))
	_valid = _session.is_valid() and _host.is_valid() and config != null and counters != null and seams != null


func is_valid() -> bool:
	return _valid


## A leave or kick: the peer's buckets go, so a rejoin starts full.
func forget_peer(peer_id: int) -> void:
	_flood.forget_peer(peer_id)


## A match (re)start or end: the client's cat-target send throttle starts over.
func reset_throttles() -> void:
	_cat_target_last_send_s = -1.0


# --- Local door: the single call site for each intent ---------------------------------------

## Host: Match.request_place() inline. Client: the reliable intent RPC and REASON_OK optimistically
## (the real outcome arrives as placement_rejected or the next feed_block_issued). A client never
## auto-drops: spec 1.4's auto-drop is [ORIGINAL] and the host fires it from the last cursor.
func submit_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> StringName:
	if _session.is_host():
		if not auto_drop:
			_counters.count_sent(slot_id)
		return apply_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)
	if auto_drop:
		return PlacementRules.REASON_NO_BLOCK
	if not bool(_seams.can_send.call()):
		# Nothing went on the wire, so nothing is counted: the harness proves "never lost" by
		# comparing this client's intents_sent with the host's count for the same slot.
		return PlacementRules.REASON_NO_BLOCK
	_counters.count_sent(slot_id)
	_seams.send_to_host.call(RPC_PLACE, [slot_id, origin, orientation_index, free_quat, false, feed_seq])
	return PlacementRules.REASON_OK


## submit_place()'s twin for a throw (a throw has no auto-drop equivalent).
func submit_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> StringName:
	if _session.is_host():
		_counters.count_sent(slot_id)
		return apply_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)
	if not bool(_seams.can_send.call()):
		return PlacementRules.REASON_NO_BLOCK
	_counters.count_sent(slot_id)
	_seams.send_to_host.call(RPC_THROW, [slot_id, origin, orientation_index, free_quat, velocity, feed_seq])
	return PlacementRules.REASON_OK


## The use_gift_slot intent. Returns whether the request was applied (host) or sent (client).
func submit_use_gift_slot(slot_id: int) -> bool:
	if _session.is_host():
		return _host.request_use_gift_slot(slot_id)
	if not bool(_seams.can_send.call()):
		return false
	_seams.send_to_host.call(RPC_GIFT_SLOT, [slot_id])
	return true


## The local player's ghost pose, at NetConfig.cursor_hz. The local record is always refreshed and
## the send is throttled here, so no caller owns a rate accumulator. On the host it only
## broadcasts; on a client it goes to the host (what the host auto-drops from on expiry).
func submit_cursor(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, aim: Vector3 = Vector3.ZERO
) -> void:
	_seams.store_cursor.call(slot_id, origin, orientation_index, free_quat)
	if not bool(_seams.can_send.call()):
		return
	var now: float = _now()
	if now - _cursor_last_send_s < _send_step_s():
		return
	_cursor_last_send_s = now
	if _session.is_host():
		_seams.broadcast.call(BROADCAST_CURSOR, [slot_id, origin, orientation_index, free_quat])
	else:
		_seams.send_to_host.call(RPC_CURSOR, [slot_id, origin, orientation_index, free_quat, aim])


## The cat's laser target: finite points only, throttled to the cursor cadence on a client.
func submit_cat_target(slot_id: int, point: Vector3) -> void:
	if not point.is_finite():
		return
	if _session.is_host():
		_host.set_cat_target(slot_id, point)
	elif bool(_seams.can_send.call()):
		var now: float = _now()
		if now - _cat_target_last_send_s >= _send_step_s():
			_cat_target_last_send_s = now
			_seams.send_to_host.call(RPC_CAT_TARGET, [slot_id, point])


## results screen "Play again". The host's own call acts inline with no sender check (offline there
## is no peer table) but is still checked against State.END; a client asks over the wire.
func request_replay() -> void:
	if _session.is_host():
		if _match_flow_state_allows():
			_replay_current_match()
		return
	if bool(_seams.can_send.call()):
		_seams.send_to_host.call(RPC_REPLAY, [])


## results screen "Return to lobby"; mirrors request_replay().
func request_return_to_lobby() -> void:
	if _session.is_host():
		if _match_flow_state_allows():
			_host.abort_match()
		return
	if bool(_seams.can_send.call()):
		_seams.send_to_host.call(RPC_RETURN, [])


# --- Host: the one place an intent becomes a mutation ---------------------------------------

## A placement, whether it arrived inline from the host's own player or over the wire. Host only.
func apply_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> StringName:
	var reason: StringName = _host.request_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)
	var consumed: bool = consumed_a_block(reason, auto_drop)
	if auto_drop:
		if consumed:
			_counters.count_auto_drop(slot_id)
	elif consumed:
		_counters.count_accepted(slot_id)
	else:
		_counters.count_refused(slot_id)
	return reason


## apply_place()'s twin for a throw. A throw is never an auto-drop, so only REASON_OK spends a block.
func apply_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> StringName:
	var reason: StringName = _host.request_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)
	if consumed_a_block(reason, false):
		_counters.count_accepted(slot_id)
	else:
		_counters.count_refused(slot_id)
	return reason


## Whether an outcome spent the slot's held block. Two reasons always mean the intent never reached
## the field (nothing to place, or not its turn in hot-seat). An auto-drop always lands somewhere
## (relocated or burned), so it consumes for any other reason; a manual refusal spends nothing.
static func consumed_a_block(reason: StringName, auto_drop: bool) -> bool:
	if reason == PlacementRules.REASON_NO_BLOCK or reason == PlacementRules.REASON_NOT_YOUR_TURN:
		return false
	return auto_drop or reason == PlacementRules.REASON_OK


# --- Host: remote intents -------------------------------------------------------------------

## net_request_place, split out so a test can drive it with a manufactured sender id.
func handle_place(
	sender: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	feed_seq: int
) -> void:
	if not _host_may_handle(sender, FloodLimits.INTENT_PLACE):
		return
	if _remote_release_slot(sender, slot_id, feed_seq, origin, orientation_index, free_quat) < 0:
		return
	# auto_drop is never taken from the wire: it grants the relocation privilege of spec 1.4.
	_reject_replied_slot = -1
	var reason: StringName = apply_place(slot_id, origin, orientation_index, free_quat, false, feed_seq)
	if not consumed_a_block(reason, false):
		# Match announces most refusals itself (the listener already told the sender); for the
		# rest, tell the sender anyway so its ghost unlocks now instead of after intent_ack_timeout.
		_reply_reject_once(sender, slot_id, reason)


## net_request_throw; mirrors handle_place() check for check, plus `velocity.is_finite()`. The host
## does not bound the length here: Match always clamps to throw_max_speed (spec 2.6).
func handle_throw(
	sender: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> void:
	if not _host_may_handle(sender, FloodLimits.INTENT_THROW):
		return
	if _remote_release_slot(sender, slot_id, feed_seq, origin, orientation_index, free_quat, velocity) < 0:
		return
	_reject_replied_slot = -1
	var reason: StringName = apply_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)
	if not consumed_a_block(reason, false):
		_reply_reject_once(sender, slot_id, reason)


## net_request_use_gift_slot. Returns whether Match applied it.
func handle_gift_slot(sender: int, slot_id: int) -> bool:
	if not _host_may_handle(sender, FloodLimits.INTENT_GIFT_SLOT):
		return false
	if not _seat_owns_slot(sender, slot_id):
		return false
	return _host.request_use_gift_slot(slot_id)


## net_update_cursor. What is stored here is what spec 1.4's auto-drop fires from on expiry, so it
## is an input boundary too. A malformed cursor is dropped, not clamped (a clamped pose would be one
## the player never had); nothing is rebroadcast for it.
func handle_cursor(
	sender: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	aim: Vector3 = Vector3.ZERO
) -> void:
	if not _host_may_handle(sender, FloodLimits.INTENT_CURSOR):
		return
	var sender_slot: int = _session.slot_of_peer(sender)
	if sender_slot < 0 or sender_slot != slot_id:
		return
	if _is_replay_pending(sender):
		# A cursor is what the host auto-drops from, so an unreplayed peer's pose is not stored.
		return
	if not pose_is_acceptable(origin, orientation_index, free_quat):
		_counters.count_cursor_refused(sender_slot)
		return
	_seams.store_cursor.call(slot_id, origin, orientation_index, free_quat)
	# The aim is validated again by the throw itself (GiftThrow.sanitize_aim); a non-finite one
	# just forgets the slot's aim.
	_host.note_aim(slot_id, aim)
	Events.remote_cursor_updated.emit(slot_id, origin, orientation_index, free_quat)
	if bool(_seams.can_send.call()):
		_seams.broadcast.call(BROADCAST_CURSOR, [slot_id, origin, orientation_index, free_quat])


## net_cat_target: the sender must own the slot and have a world; the point must be finite. Match
## checks the live match and cat ownership and CatController clamps the range.
# DECISION: the finite check also runs here, at the wire boundary, instead of only in
# CatController.set_target(), so a non-finite point never reaches an authority call.
func handle_cat_target(sender: int, slot_id: int, point: Vector3) -> void:
	if not _host_may_handle(sender, FloodLimits.INTENT_CAT_TARGET):
		return
	if not _seat_owns_slot(sender, slot_id) or not point.is_finite():
		return
	_host.set_cat_target(slot_id, point)


## net_request_replay: the sender must hold a slot, have a world, and the match must have ended.
func handle_replay_request(sender: int) -> void:
	if not _host_may_handle(sender, FloodLimits.INTENT_REPLAY_REQUEST):
		return
	if not _remote_may_request_match_flow(sender):
		return
	_replay_current_match()


## net_request_return_to_lobby; the same gate as handle_replay_request().
func handle_return_request(sender: int) -> void:
	if not _host_may_handle(sender, FloodLimits.INTENT_RETURN_LOBBY):
		return
	if not _remote_may_request_match_flow(sender):
		return
	_host.abort_match()


# --- Refusals ---------------------------------------------------------------------------------

## A remote intent the host will not act on: counted against the sender's own slot so the harness
## identity accepted + refused == sent still holds, and echoed back so the sender's ghost unlocks.
func refuse_intent(sender: int, sender_slot: int, reason: StringName) -> void:
	_counters.count_refused(sender_slot)
	reject_to_peer(sender, sender_slot, reason)


## The placement_rejected reply to one peer (net_match_event). Never sent for a flooded call.
func reject_to_peer(peer_id: int, slot_id: int, reason: StringName) -> void:
	_counters.note_reject_reply(peer_id, slot_id, reason)
	_seams.send_to_peer.call(peer_id, &"net_match_event", [MatchWireEvents.PLACEMENT_REJECTED, [slot_id, reason]])


## The placement_rejected listener sent this slot's refusal to its owner while the current intent
## was being applied: the handler's own tail reply for the same intent is suppressed.
func note_rejection_sent(slot_id: int) -> void:
	_reject_replied_slot = slot_id


## Every check the wire gets that Match does not: the pose must be one the authority can evaluate
## (finite origin, finite unit free quaternion, orientation index in BlockOrientations' table) and
## its height must lie inside the volume snapshots quantize positions into
## (NetConfig.pos_min_y .. pos_max_y, the same numbers core/net/Quantize.gd packs y with). X/Z are
## left to territory validation, which already burns an off-disk release (spec 1.5).
func pose_is_acceptable(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	if not _host.is_pose_well_formed(origin, orientation_index, free_quat):
		return false
	return origin.y >= _config.pos_min_y and origin.y <= _config.pos_max_y


# --- Internals --------------------------------------------------------------------------------

## The host-only preamble of every remote handler: a valid gateway on the host, then the flood gate.
func _host_may_handle(sender: int, intent: StringName) -> bool:
	if not _valid or not _session.is_host():
		return false
	return _flood.allow(sender, intent, _now())


## The shared gate of a remote place / throw, in the refusal order the wire contract fixes: seated
## (an unseated peer gets no say and is not counted), counted, world replayed, slot owned, feed_seq
## quoted, pose (and `velocity`, for a throw) acceptable. Returns the sender's slot, or -1 after
## refusing.
func _remote_release_slot(
	sender: int,
	slot_id: int,
	feed_seq: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3 = Vector3.ZERO
) -> int:
	var sender_slot: int = _session.slot_of_peer(sender)
	if sender_slot < 0:
		return -1
	_counters.count_sent(sender_slot)
	if _refuse_if_unreplayed(sender, sender_slot):
		return -1
	if sender_slot != slot_id:
		# Spec 2.6: the host checks "that the slot matches"; the claimed slot_id is never trusted.
		refuse_intent(sender, sender_slot, PlacementRules.REASON_NOT_YOUR_TURN)
		return -1
	if feed_seq < 0:
		# Match reads a negative feed_seq as "don't check"; from the wire it would switch off the
		# "never duplicated" defence, so a remote intent has to quote the sequence it was issued.
		refuse_intent(sender, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return -1
	if not pose_is_acceptable(origin, orientation_index, free_quat) or not velocity.is_finite():
		# Not a rule violation (a real ghost cannot produce such a pose): the block is neither
		# burned nor consumed; the sender is told so its ghost unlocks.
		refuse_intent(sender, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return -1
	return sender_slot


## The sender holds a slot, it is `slot_id`, and its world is built.
func _seat_owns_slot(sender: int, slot_id: int) -> bool:
	var sender_slot: int = _session.slot_of_peer(sender)
	return sender_slot >= 0 and sender_slot == slot_id and not _is_replay_pending(sender)


## A mid-match joiner's world is not built until it acknowledged its replay: refused (counted and
## echoed, like every other refusal) rather than acted on. True when it refused.
func _refuse_if_unreplayed(sender: int, sender_slot: int) -> bool:
	if not _is_replay_pending(sender):
		return false
	_counters.intents_refused_before_replay_ack += 1
	refuse_intent(sender, sender_slot, PlacementRules.REASON_NO_BLOCK)
	return true


func _reply_reject_once(peer_id: int, slot_id: int, reason: StringName) -> void:
	if _reject_replied_slot == slot_id:
		_reject_replied_slot = -1
		return
	reject_to_peer(peer_id, slot_id, reason)


func _is_replay_pending(peer_id: int) -> bool:
	return bool(_seams.is_replay_pending.call(peer_id))


func _match_flow_state_allows() -> bool:
	return _host.state() == int(MatchPhase.State.END)


## Gate for a REMOTE replay / return request: the sender must hold a live slot (an unseated peer
## gets no say), have its world, and the match must be over.
func _remote_may_request_match_flow(sender: int) -> bool:
	if _session.slot_of_peer(sender) < 0 or _is_replay_pending(sender):
		return false
	return _match_flow_state_allows()


## Restarts the match that just ended with its own sanitized config.
func _replay_current_match() -> void:
	var current: MatchConfig = _host.config()
	if current == null:
		return
	_host.start_match(current)


func _send_step_s() -> float:
	return 1.0 / maxf(_config.cursor_hz, MIN_SEND_HZ)


func _now() -> float:
	return float(_seams.now_s.call())
