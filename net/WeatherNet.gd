class_name WeatherNet
extends Node
## The weather replication surface (Bontago-22y.10), a child of the MatchNet
## autoload so its RPC path (/root/MatchNet/WeatherNet) is identical on every
## instance.
##
## DECISION (net/WeatherNet.gd): a child node with its own one RPC rather than
## another net_match_event case, so MatchNet.gd, which other packages edit
## heavily, gains only a few lines (build this node, forward set_providers).
## Uses only MultiplayerAPI; nothing here assumes a transport.
##
## Host -> clients only. The host sends the full MatchWeather.state_dict()
## whenever the schedule phase changes and again to any peer that joins or
## rejoins (late-join/reconnect). A client never simulates weather physics; it
## validates the payload, then MatchWeather.apply_replicated_state() drives
## presentation from it. There is no client -> host weather message at all:
## the RPC is `authority`-only, and a host that somehow receives one ignores it.

## Counters for tests and the net debug overlay.
var states_sent: int = 0
var states_applied: int = 0
var states_refused: int = 0
var last_sent_state: Dictionary = {}

var _net_provider: Variant = null
var _match_provider: Variant = null


func _ready() -> void:
	# DECISION: the presenter lives here so weather visuals exist on the host
	# and on clients with no edit to Main; it draws in the root world and
	# reacts only to Events.
	var presenter: WeatherPresenter = WeatherPresenter.new()
	presenter.name = "WeatherPresenter"
	add_child(presenter)
	Events.weather_state_changed.connect(_on_weather_state_changed)
	Events.net_peer_joined.connect(_on_net_peer_joined)


## Same seam as MatchNet.set_providers(); null keeps the real autoload.
func set_providers(net_provider: Variant, match_provider: Variant) -> void:
	_net_provider = net_provider
	_match_provider = match_provider


func _session() -> Variant:
	return _net_provider if _net_provider != null else Net


func _authority() -> Variant:
	return _match_provider if _match_provider != null else Match


func _is_host() -> bool:
	return bool(_session().is_host())


## True only with a live peer (see MatchNet._can_send() for why offline and
## the engine's OfflineMultiplayerPeer must be excluded).
func _can_send() -> bool:
	if bool(_session().is_offline()):
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# --- Host -> clients ----------------------------------------------------------------

func _on_weather_state_changed(state: Dictionary) -> void:
	if not _is_host():
		return
	last_sent_state = state.duplicate()
	states_sent += 1
	if _can_send():
		rpc(&"net_weather_state", state)


## A peer joined or rejoined: hand it the current state so it does not wait for
## the next phase change.
func _on_net_peer_joined(peer_id: int, _slot_id: int, _player_name: String) -> void:
	# Net emits net_peer_joined for sessions that may use their own
	# MultiplayerAPI; with no peer on this node's API there is nothing to send
	# (and get_unique_id() would raise an engine error).
	if not _is_host():
		return
	if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
		return
	var weather: MatchWeather = _authority().weather()
	if weather == null or not weather.is_running():
		return
	states_sent += 1
	last_sent_state = weather.state_dict()
	if _can_send():
		rpc_id(peer_id, &"net_weather_state", last_sent_state)


@rpc("authority", "call_remote", "reliable")
func net_weather_state(state: Dictionary) -> void:
	# The engine already drops this RPC from any non-authority sender; the
	# checks below are the second line: never on the host, never from a peer
	# other than the server.
	if _is_host():
		states_refused += 1
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != MultiplayerPeer.TARGET_PEER_SERVER:
		states_refused += 1
		return
	var authority: Variant = _authority()
	var weather: MatchWeather = authority.weather()
	if weather == null:
		states_refused += 1
		return
	# A late packet from a finished match must not resurrect weather: only a
	# started match (countdown onward, not END) accepts one.
	var live: bool = MatchWeather.accepts_replication_in(int(authority.state()))
	if weather.apply_replicated_state(state, live):
		states_applied += 1
	else:
		states_refused += 1
