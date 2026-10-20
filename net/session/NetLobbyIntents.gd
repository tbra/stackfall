class_name NetLobbyIntents
extends RefCounted
## Host-side lobby intents of the Net autoload: set-ready, the loading-ready gate
## relay and seat preferences, each behind its flood bucket. STUB: default bodies
## log and change nothing; Net does not call it yet.


class Seams extends RefCounted:
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()
	## () -> bool : this instance is the host.
	var is_host: Callable = Callable()
	## () -> void : the synchronous roster broadcast.
	var broadcast_roster: Callable = Callable()
	## (peer_id: int) -> void : a loading-ready from a seated peer reached the host.
	var loading_ready: Callable = Callable()


func _init(_roster: NetRoster, _config: NetConfig, _flood: PeerFloodGate, _seams: NetLobbyIntents.Seams) -> void:
	pass


## Host: lobby phase, seated sender, flood gate, then NetRoster.set_ready and one broadcast.
func on_set_ready(_sender: int, _ready: bool) -> void:
	push_error("NetLobbyIntents.on_set_ready: not implemented")


## Host: a seated peer finished loading.
func on_loading_ready(_sender: int) -> void:
	push_error("NetLobbyIntents.on_loading_ready: not implemented")


## Host: a seat preference; both values are untrusted Variants.
func on_seat_pref(_sender: int, _color_index: Variant, _team_pick: Variant) -> void:
	push_error("NetLobbyIntents.on_seat_pref: not implemented")
