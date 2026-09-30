class_name BreezeNet
extends Node
## Breeze gust replication (Bontago-470.2), a child of WeatherNet so its RPC
## path (/root/MatchNet/WeatherNet/BreezeNet) is the same on every instance.
## Uses only MultiplayerAPI.
##
## Host -> clients only. Each gust the host's BreezeEffect spawns is announced
## once (Events.breeze_gust_started) and sent as one small reliable dictionary
## (8 numbers). A client validates every field against BreezeTuning's wire
## limits, drops duplicates and stale ids, then re-emits the event locally so
## BreezePresenter can draw it; it never simulates anything. There is no
## client -> host message, and gusts are transient, so a late joiner is not
## sent history.

const WIRE_KEYS: PackedStringArray = ["id", "x", "y", "z", "a", "r", "d", "s"]

var gusts_sent: int = 0
var gusts_applied: int = 0
var gusts_refused: int = 0
var last_sent_gust: Dictionary = {}

var _tuning: BreezeTuning = preload("res://config/breeze.tres")
var _net_provider: Variant = null
var _match_provider: Variant = null
var _last_id: int = 0


func _ready() -> void:
	var presenter: BreezePresenter = BreezePresenter.new()
	presenter.name = "BreezePresenter"
	add_child(presenter)
	Events.breeze_gust_started.connect(_on_gust_started)
	Events.match_state_changed.connect(_on_match_state_changed)


## Same seam as WeatherNet.set_providers(); null keeps the real autoload.
func set_providers(net_provider: Variant, match_provider: Variant) -> void:
	_net_provider = net_provider
	_match_provider = match_provider


func set_tuning(tuning: BreezeTuning) -> void:
	_tuning = tuning


func _session() -> Variant:
	return _net_provider if _net_provider != null else Net


func _authority() -> Variant:
	return _match_provider if _match_provider != null else Match


func _is_host() -> bool:
	return bool(_session().is_host())


func _can_send() -> bool:
	if bool(_session().is_offline()):
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if to_state == MatchAutoload.State.LOADING or to_state == MatchAutoload.State.LOBBY or to_state == MatchAutoload.State.END:
		_last_id = 0


func _on_gust_started(gust: Dictionary) -> void:
	# On a client this fires for gusts this node re-emitted itself: never resend.
	if not _is_host():
		return
	last_sent_gust = gust.duplicate()
	gusts_sent += 1
	if _can_send():
		rpc(&"net_breeze_gust", gust)


@rpc("authority", "call_remote", "reliable")
func net_breeze_gust(gust: Dictionary) -> void:
	if _is_host():
		gusts_refused += 1
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != MultiplayerPeer.TARGET_PEER_SERVER:
		gusts_refused += 1
		return
	if not MatchWeather.accepts_replication_in(int(_authority().state())):
		gusts_refused += 1
		return
	apply_gust(gust)


## Validates `raw` and, when good and newer than the last accepted id, emits it
## for the presenter. Returns whether it was accepted. Public for tests.
func apply_gust(raw: Variant) -> bool:
	var gust: Dictionary = sanitize_gust(raw, _tuning)
	if gust.is_empty() or int(gust["id"]) <= _last_id:
		gusts_refused += 1
		return false
	_last_id = int(gust["id"])
	gusts_applied += 1
	Events.breeze_gust_started.emit(gust)
	return true


## The sanitized gust or {} when `raw` is malformed: wrong type, missing or
## extra key, non-number or non-finite value, or a coordinate, radius, duration
## or strength outside the tuning's wire limits.
static func sanitize_gust(raw: Variant, tuning: BreezeTuning) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	if data.size() != WIRE_KEYS.size():
		return {}
	for key: String in WIRE_KEYS:
		if not data.has(key):
			return {}
		var value: Variant = data[key]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return {}
		if not is_finite(float(value)):
			return {}
	if typeof(data["id"]) != TYPE_INT or int(data["id"]) < 1:
		return {}
	var limit: float = tuning.wire_max_coord_m
	for axis: String in ["x", "y", "z"]:
		if absf(float(data[axis])) > limit:
			return {}
	if absf(float(data["a"])) > TAU * 4.0:
		return {}
	var radius: float = float(data["r"])
	var duration: float = float(data["d"])
	var strength: float = float(data["s"])
	if radius <= 0.0 or radius > tuning.wire_max_radius_m:
		return {}
	if duration <= 0.0 or duration > tuning.wire_max_duration_s:
		return {}
	if strength < 0.0 or strength > 1.0:
		return {}
	return {
		"id": int(data["id"]), "x": float(data["x"]), "y": float(data["y"]), "z": float(data["z"]),
		"a": float(data["a"]), "r": radius, "d": duration, "s": strength,
	}
