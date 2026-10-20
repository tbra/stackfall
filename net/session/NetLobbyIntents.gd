class_name NetLobbyIntents
extends RefCounted
## Host-side lobby intents of the Net autoload: set-ready, the loading-ready gate
## relay and seat preferences. Each is refused unless the sender is a seated peer
## (a spectator, an unknown id or a peer still in the handshake is not). The
## set-ready and loading-ready intents pass the shared flood gate; seat prefs have
## their own TokenBucket per peer. The roster broadcast stays synchronous and
## ordered: one per accepted set-ready.


class Seams extends RefCounted:
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()
	## () -> bool : this instance is the host.
	var is_host: Callable = Callable()
	## () -> void : the synchronous roster broadcast.
	var broadcast_roster: Callable = Callable()
	## (peer_id: int) -> void : a loading-ready from a seated peer reached the host.
	var loading_ready: Callable = Callable()
	## (peer_id: int, color_index: int, team_pick: int) -> void : a valid seat pref.
	var seat_pref: Callable = Callable()


var _roster: NetRoster = null
var _config: NetConfig = null
var _flood: PeerFloodGate = null
var _seams: NetLobbyIntents.Seams = null
## peer_id -> TokenBucket of its seat prefs.
var _seat_pref_buckets: Dictionary = {}


func _init(roster: NetRoster, config: NetConfig, flood: PeerFloodGate, seams: NetLobbyIntents.Seams) -> void:
	_roster = roster
	_config = config
	_flood = flood
	_seams = seams


## Host: a set-ready from a seated peer in the lobby, flood-gated; then
## NetRoster.set_ready and one roster broadcast (changed or not).
func on_set_ready(sender: int, ready: bool) -> void:
	if not _hosting() or _roster.match_in_progress or not _seated(sender):
		return
	if not _flood.allow(sender, FloodLimits.INTENT_SET_READY, _now()):
		return
	_roster.set_ready(sender, ready)
	if _seams.broadcast_roster.is_valid():
		_seams.broadcast_roster.call()


## Host: a seated peer finished loading; flood-gated, then handed to the lifecycle.
func on_loading_ready(sender: int) -> void:
	if not _hosting() or not _seated(sender):
		return
	if not _flood.allow(sender, FloodLimits.INTENT_LOADING_READY, _now()):
		return
	if _seams.loading_ready.is_valid():
		_seams.loading_ready.call(sender)


## Host: a seat preference from a seated peer in the lobby; both values are
## untrusted Variants and nothing is clamped. Every request from a seated peer
## drains its bucket, valid or not.
func on_seat_pref(sender: int, color_index: Variant, team_pick: Variant) -> void:
	if not _hosting() or not _seated(sender) or _roster.match_in_progress:
		return
	var bucket: TokenBucket = _seat_pref_buckets.get(sender) as TokenBucket
	if bucket == null:
		bucket = TokenBucket.new()
		_seat_pref_buckets[sender] = bucket
	if not bucket.take(_now(), _config.seat_pref_burst, _config.seat_pref_refill_per_s):
		return
	_emit_seat_pref(sender, color_index, team_pick)


## The host's own (or offline) seat pref: same checks, no seat or flood gate.
func on_local_seat_pref(sender: int, color_index: Variant, team_pick: Variant) -> void:
	if _roster.match_in_progress:
		return
	_emit_seat_pref(sender, color_index, team_pick)


## Wire sanity, not lobby rules: each field is UNCHANGED or inside the largest range
## it can ever take, and at least one field asks for something.
static func seat_pref_in_range(color_index: int, team_pick: int) -> bool:
	if color_index == LobbySeats.UNCHANGED and team_pick == LobbySeats.UNCHANGED:
		return false
	if color_index != LobbySeats.UNCHANGED and (color_index < 0 or color_index >= LobbySeats.palette_size()):
		return false
	if team_pick != LobbySeats.UNCHANGED and (team_pick < MatchConfig.TEAM_PICK_RANDOM or team_pick > MatchConfig.TEAM_PICK_MAX):
		return false
	return true


## A peer left: its seat-pref bucket goes with it (a rejoin starts full).
func forget_peer(peer_id: int) -> void:
	_seat_pref_buckets.erase(peer_id)


## Session start/end.
func reset() -> void:
	_seat_pref_buckets.clear()


func _emit_seat_pref(sender: int, color_index: Variant, team_pick: Variant) -> void:
	if typeof(color_index) != TYPE_INT or typeof(team_pick) != TYPE_INT:
		return
	if not seat_pref_in_range(int(color_index), int(team_pick)):
		return
	if _seams.seat_pref.is_valid():
		_seams.seat_pref.call(sender, int(color_index), int(team_pick))


func _seated(peer_id: int) -> bool:
	return _roster.slot_of_peer(peer_id) >= 0


func _hosting() -> bool:
	return _seams.is_host.is_valid() and bool(_seams.is_host.call())


func _now() -> float:
	return float(_seams.now_s.call()) if _seams.now_s.is_valid() else 0.0
