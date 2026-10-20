class_name NetRoster
extends RefCounted
## The session roster of the Net autoload: who is seated where, their ready flags,
## the rejoin tokens and reservations, lobby slot compaction, and the handshake
## gate that decides whether a newcomer is seated (HandshakePolicy holds the pure
## rules). It sends nothing and holds no MultiplayerAPI: Net asks, applies the
## answer (refusal RPC, roster broadcast, Events) and passes in the clock and the
## sender id, so unit tests drive it with synthetic ones.
##
## Host: the source of truth. Client: a mirror Net overwrites from the roster RPC.

## Peer id of the listen-server host. Godot fixes this at 1; Net aliases it.
const HOST_PEER_ID: int = 1
## Size of a rejoin token (random bytes; hex doubles it) and the longest token
## string the handshake will even look at. Architecture, not tunables.
const REJOIN_TOKEN_BYTES: int = 16
const REJOIN_TOKEN_MAX_CHARS: int = 64

## NetConfig of the owning Net. Assigning it rebuilds the handshake flood buckets
## from the new limits on their next use.
var config: NetConfig:
	set(value):
		config = value
		_flood = null

## peer_id -> {"peer_id", "slot_id", "name", "name_auto", "ready", "ping_ms", "build"}.
var peers: Dictionary = {}
## Host only: peer_id -> the rejoin token issued to it. Never part of the roster
## (that is broadcast to every client): a token is a bearer credential for its slot.
var tokens: Dictionary = {}
## Host only: rejoin token -> slot_id held by a peer that dropped while a match was
## running. Cleared whenever a match (re)starts or ends.
var reservations: Dictionary = {}
## Host only: next monotonic slot id, used for mid-match seating.
var next_slot_id: int = 1
## Host only: whether the handshake may still seat a new peer (lobby, or a match that
## allows mid-match joins).
var accepting_joins: bool = true
## Host only: true while the match flow is past the lobby.
var match_in_progress: bool = false
## True while this instance hosts a session (the roster accepts handshakes then).
var hosting: bool = false
## The build string a joiner must present.
var host_build: String = ""
## Host only: () -> int, the open human seat a mid-match joiner may take, or -1.
var pick_open_seat: Callable = Callable()
## Host only: (slot_id: int) -> bool, whether a returning peer may reclaim `slot_id`.
var can_reclaim_seat: Callable = Callable()
## Client only: the host answered the handshake with a seat.
var joined_accepted: bool = false
## Client only: the cleaned name the handshake sends.
var pending_join_name: String = ""

var _flood: PeerFloodGate = null


func _init(net_config: NetConfig) -> void:
	config = net_config


# --- Session boundaries ---------------------------------------------------------

## Starts a hosted roster holding only the host (peer id 1, slot 0). `host_name` is
## already checked by the caller.
func add_host(host_name: String, build: String, joins_open: bool) -> void:
	peers.clear()
	peers[HOST_PEER_ID] = LobbySeats.entry_to_wire(HOST_PEER_ID, 0, host_name, false, 0.0, build)
	next_slot_id = 1
	accepting_joins = joins_open
	hosting = true
	host_build = build


## A client session begins: an empty mirror, the name the handshake will send.
func begin_client(cleaned_name: String) -> void:
	peers.clear()
	hosting = false
	pending_join_name = cleaned_name
	joined_accepted = false


## The session ended.
func end_session() -> void:
	peers.clear()
	hosting = false
	joined_accepted = false
	accepting_joins = true


## Drops the per-session host state that must not outlive its peers.
func reset_rejoin_state() -> void:
	match_in_progress = false
	tokens.clear()
	reservations.clear()
	_flood = null


## The match flow flipped phase. Every call drops the rejoin reservations, so a slot
## reserved in one match can never be reclaimed in the next.
func set_match_phase(active: bool) -> void:
	reservations.clear()
	match_in_progress = active


## Back in the lobby: spectators get a real lobby slot again, holes left by players
## who left for good close up, and nobody is ready. True when anything changed (the
## caller then broadcasts the roster).
func return_to_lobby() -> bool:
	var reseated: bool = false
	for peer_id: int in peer_ids():
		if slot_of_peer(peer_id) < 0:
			set_peer_slot(peer_id, take_next_lobby_slot())
			reseated = true
	var compacted: bool = compact() > 0
	var cleared: bool = clear_ready_flags()
	return reseated or compacted or cleared


## Forget a peer's handshake bucket (leave, kick, disconnect), so a rejoin starts full.
func forget_flood(peer_id: int) -> void:
	if _flood != null:
		_flood.forget_peer(peer_id)


# --- Handshake -------------------------------------------------------------------

## The decision for a handshake `sender` sent at `now_s`. Raw string lengths are
## capped first, then the sender's HANDSHAKE bucket is charged; a capped or flooded
## handshake is a DROP the caller answers with nothing.
func handle_handshake(sender: int, build: String, player_name: String, token: String, now_s: float) -> HandshakePolicy.Decision:
	var request: Dictionary = {
		"sender": sender, "build": build, "name": player_name, "token": token,
		"already_seated": peers.has(sender),
	}
	var state: Dictionary = host_state()
	if not hosting:
		return HandshakePolicy.decide(request, state)
	if not HandshakePolicy.within_caps(request, state):
		return HandshakePolicy.decide(request, state)
	if not _flood_gate().allow(sender, FloodLimits.INTENT_HANDSHAKE, now_s):
		var flooded: HandshakePolicy.Decision = HandshakePolicy.Decision.new()
		flooded.kind = HandshakePolicy.Decision.Kind.DROP
		flooded.drop_reason = HandshakePolicy.DROP_FLOOD
		return flooded
	return HandshakePolicy.decide(request, state)


## The roster snapshot HandshakePolicy.decide reads.
func host_state() -> Dictionary:
	return {
		"is_host": hosting,
		"host_build": host_build,
		"joins_open": accepting_joins,
		"match_in_progress": match_in_progress,
		"free_capacity": config.max_peers - peers.size(),
		"reservations": reservations,
		"held_slots": held_slots(),
		"can_reclaim_seat": can_reclaim_seat,
		"pick_open_seat": pick_open_seat,
		"max_build_len": config.handshake_build_max_length,
		"max_name_len": config.handshake_name_max_length,
		"max_token_len": REJOIN_TOKEN_MAX_CHARS,
	}


## Seats `peer_id` in `slot_id` (-1 = spectator). `token` is a reconnecting peer's
## existing rejoin token (its reservation is consumed and the token reused so a
## second drop also works); a new peer gets a fresh one. The host owns the roster,
## so it validates the name a peer claims before anyone else sees it. Returns the
## slot seated.
func accept(peer_id: int, build: String, player_name: String, slot_id: int, token: String = "") -> int:
	if slot_id >= next_slot_id:
		next_slot_id = slot_id + 1
	if token != "":
		reservations.erase(token)
	tokens[peer_id] = token if token != "" else new_rejoin_token()
	var typed_name: String = PlayerNames.clean(player_name, config.max_player_name_length)
	# name_auto: the joiner sent no usable name and the name is the host's "Player N"
	# for the seat (see set_peer_slot).
	var name_auto: bool = typed_name == ""
	var checked_name: String = PlayerNames.fallback_for_slot(slot_id) if name_auto else typed_name
	peers[peer_id] = LobbySeats.entry_to_wire(peer_id, slot_id, checked_name, false, 0.0, build, true, name_auto)
	return slot_id


## Host: drops `peer_id`. With `reserve_seat` a seated peer holding a token keeps a
## reservation on its slot so quoting the token on the next handshake gets it back;
## a kicked peer forfeits it. Returns the slot it held (-1 when unknown).
func remove(peer_id: int, reserve_seat: bool) -> int:
	if not peers.has(peer_id):
		return -1
	var slot_id: int = slot_of_peer(peer_id)
	peers.erase(peer_id)
	var token: String = String(tokens.get(peer_id, ""))
	tokens.erase(peer_id)
	if reserve_seat and slot_id >= 0 and token != "":
		reservations[token] = slot_id
	return slot_id


## Unguessable, so a token is worth exactly one slot.
func new_rejoin_token() -> String:
	return Crypto.new().generate_random_bytes(REJOIN_TOKEN_BYTES).hex_encode()


func token_of(peer_id: int) -> String:
	return String(tokens.get(peer_id, ""))


# --- Registry ----------------------------------------------------------------------

func has_peer(peer_id: int) -> bool:
	return peers.has(peer_id)


## Every peer id including the host, in slot order.
func peer_ids() -> PackedInt32Array:
	var ids: Array = peers.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return int(peers[a].get(LobbySeats.FIELD_SLOT_ID, -1)) < int(peers[b].get(LobbySeats.FIELD_SLOT_ID, -1))
	)
	var result: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		result.append(id)
	return result


## A copy of the roster entry. Empty for an unknown peer.
func peer_info(peer_id: int) -> Dictionary:
	if not peers.has(peer_id):
		return {}
	return (peers[peer_id] as Dictionary).duplicate()


## Which PlayerSlot a peer holds, or -1.
func slot_of_peer(peer_id: int) -> int:
	if not peers.has(peer_id):
		return -1
	return int(peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1))


## Inverse of slot_of_peer(). -1 for an unclaimed slot. A negative slot_id is never a
## seat: spectators all hold -1, so it must not match the first of them.
func peer_of_slot(slot_id: int) -> int:
	if slot_id < 0:
		return -1
	for peer_id: int in peers.keys():
		if int(peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1)) == slot_id:
			return peer_id
	return -1


## The replicated name of the peer in `peer_id`'s entry, or "".
func name_of_peer(peer_id: int) -> String:
	if not peers.has(peer_id):
		return ""
	return String(peers[peer_id].get(LobbySeats.FIELD_NAME, ""))


## The replicated name of the human seated at `slot_id`, or "" when nobody holds it.
func name_at_slot(slot_id: int) -> String:
	return name_of_peer(peer_of_slot(slot_id))


func ping_of(peer_id: int) -> float:
	if not peers.has(peer_id):
		return 0.0
	return float(peers[peer_id].get(LobbySeats.FIELD_PING_MS, 0.0))


## Marks a peer ready or not. True when the flag changed; false for an unknown peer.
func set_ready(peer_id: int, ready: bool) -> bool:
	if not peers.has(peer_id):
		return false
	var changed: bool = bool(peers[peer_id].get(LobbySeats.FIELD_READY, false)) != ready
	peers[peer_id][LobbySeats.FIELD_READY] = ready
	return changed


## Clears every peer's ready flag (host included); whether any flag changed.
func clear_ready_flags() -> bool:
	var changed: bool = false
	for peer_id: int in peers.keys():
		if bool(peers[peer_id].get(LobbySeats.FIELD_READY, false)):
			peers[peer_id][LobbySeats.FIELD_READY] = false
			changed = true
	return changed


## True when every OTHER seated human is ready: the host's own flag mirrors its Ready
## toggle, but pressing Start is the host's consent.
func all_ready() -> bool:
	if peers.is_empty():
		return false
	for peer_id: int in peers.keys():
		if peer_id == HOST_PEER_ID:
			continue
		if not bool(peers[peer_id].get(LobbySeats.FIELD_READY, false)):
			return false
	return true


## slot -> true for every slot a live peer holds.
func held_slots() -> Dictionary:
	var held: Dictionary = {}
	for peer_id: int in peers.keys():
		var slot_id: int = int(peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1))
		if slot_id >= 0:
			held[slot_id] = true
	return held


## The slot a lobby joiner (or a spectator returning to the lobby) is seated in: the
## LOWEST free slot, so a joiner never lands above a hole. Free = no roster entry
## holds it and no rejoin reservation names it. Mid-match the monotonic counter
## applies instead (a slot a dropped player may reclaim, or one the match already
## built a PlayerSlot for, is never handed to someone else).
func take_next_lobby_slot() -> int:
	if match_in_progress:
		var next_id: int = next_slot_id
		next_slot_id += 1
		return next_id
	return HandshakePolicy.lowest_free_slot(held_slots(), reservations.values())


## Lobby phase, host only: moves every seated peer down so the slot ids run 0..n-1
## with no hole, keeping their order (ascending old slot, peer id as the tie-break, so
## every run agrees). Spectators (slot -1) are left alone and the host (slot 0) never
## moves. Returns how many peers changed slot; the CALLER publishes the roster.
## Never during a match: there a slot id is a PlayerSlot index the match already
## built, and a dropped player's token reserves it.
func compact() -> int:
	if not hosting or match_in_progress:
		return 0
	var seated: Array[Vector2i] = []
	for peer_id: int in peers.keys():
		var held: int = slot_of_peer(peer_id)
		if held >= 0:
			seated.append(Vector2i(held, peer_id))
	seated.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	var moved: int = 0
	for index: int in range(seated.size()):
		if seated[index].x != index:
			set_peer_slot(seated[index].y, index)
			moved += 1
	return moved


## Moves `peer_id` to `slot_id` (-1 = spectator). A name the host derived itself (the
## joiner sent none: "name_auto") is derived again for the new slot, so the label never
## goes stale. A name the player chose is never touched.
func set_peer_slot(peer_id: int, slot_id: int) -> void:
	var entry: Dictionary = peers[peer_id]
	entry[LobbySeats.FIELD_SLOT_ID] = slot_id
	if bool(entry.get(LobbySeats.FIELD_NAME_AUTO, false)):
		entry[LobbySeats.FIELD_NAME] = PlayerNames.fallback_for_slot(slot_id)


# --- Internals -----------------------------------------------------------------------

func _flood_gate() -> PeerFloodGate:
	if _flood == null:
		_flood = PeerFloodGate.new(FloodLimits.from_config(config))
	return _flood
