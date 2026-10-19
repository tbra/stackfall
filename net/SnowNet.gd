class_name SnowNet
extends Node
## Snow replication and client rendering, a child of
## WeatherNet so its RPC path (/root/MatchNet/WeatherNet/SnowNet) is the same
## on every instance.
##
## Host -> clients only. The host's SnowEffect publishes its compact patch
## list (SnowGeometry wire format: per block net_id, face axis and
## (cell, level) pairs; per disc cell a level) through SnowRelay; this node
## sends it, throttled to SnowTuning.send_min_interval_s, and resends the
## latest one to a peer that joins late. An empty state (snow melted or the
## event restored) is sent at once, so it always precedes the weather's own
## stop message on the same reliable channel.
##
## A client validates the payload, then draws the caps with SnowCaps without
## colliders: it never creates a snow collider and never decides anything.
## There is no client -> host message.

var states_sent: int = 0
var states_applied: int = 0
var states_refused: int = 0
var last_sent_state: Dictionary = {}

## The session methods and the Match reads this node calls; a port is bound with
## exactly this subset, so a narrow test double stays valid.
const SESSION_METHODS: PackedStringArray = ["is_host", "is_offline"]
const AUTHORITY_METHODS: PackedStringArray = ["weather", "state", "field", "registry"]

var _tuning: SnowTuning = preload("res://config/weather/snow.tres") as SnowTuning
var _session_port: SessionPort = null
var _authority_port: MatchHostPort = null
var _pending: Dictionary = {}
var _has_pending: bool = false
var _since_send: float = INF
var _render_queued: bool = false
## Client drawing (built on first use, after the tuning is final).
var _renderer: SnowClientRenderer = null


func _ready() -> void:
	SnowRelay.instance().state_published.connect(_on_published)
	Events.net_peer_joined.connect(_on_net_peer_joined)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.weather_stopped.connect(_on_weather_stopped)
	Events.block_placed.connect(_on_block_placed)


func _exit_tree() -> void:
	# The relay is process-wide; a freed SnowNet must not stay subscribed.
	var relay: SnowRelay = SnowRelay.instance()
	if relay.state_published.is_connected(_on_published):
		relay.state_published.disconnect(_on_published)


## Same gate as WeatherNet.awaiting_world (set by WeatherNet).
var awaiting_world: Callable = Callable()


## Typed seam: the session and the Match this node reads. Returns false (and
## binds nothing) when a port is invalid. Build the ports with SESSION_METHODS /
## AUTHORITY_METHODS (default_session() / default_authority()).
func bind(session: SessionPort, authority: MatchHostPort) -> bool:
	if session == null or authority == null or not session.is_valid() or not authority.is_valid():
		return false
	_session_port = session
	_authority_port = authority
	return true


## The port over the real Net autoload (or `session_node`).
static func default_session(session_node: Object = null) -> SessionPort:
	return SessionPort.new(session_node if session_node != null else Net, SESSION_METHODS)


## The port over the real Match autoload (or `match_node`).
static func default_authority(match_node: Object = null) -> MatchHostPort:
	return MatchHostPort.new(match_node if match_node != null else Match, AUTHORITY_METHODS)


## TRANSITIONAL shim for callers that still inject providers; null keeps the
## real autoload.
func set_providers(net_provider: Variant, match_provider: Variant) -> void:
	bind(default_session(net_provider as Object), default_authority(match_provider as Object))


func _session() -> SessionPort:
	if _session_port == null:
		_session_port = default_session()
	return _session_port


func _authority() -> MatchHostPort:
	if _authority_port == null:
		_authority_port = default_authority()
	return _authority_port


func _process(delta: float) -> void:
	step_client(_tuning.rebuild_patches_per_frame)
	_since_send += delta
	if _has_pending and _since_send >= _tuning.send_min_interval_s:
		_send(_pending)


# --- Host -> clients ------------------------------------------------------------------

func _on_published(state: Dictionary) -> void:
	if not _session().is_host():
		return
	if SnowRelay.is_empty_state(state) or _since_send >= _tuning.send_min_interval_s:
		_send(state)
	else:
		_pending = state
		_has_pending = true


func _send(state: Dictionary) -> void:
	_has_pending = false
	_pending = {}
	_since_send = 0.0
	last_sent_state = state
	states_sent += 1
	if NetFanout.can_send(multiplayer, _session()):
		NetFanout.broadcast(self, _session(), &"net_snow_state", [state])


func _on_net_peer_joined(peer_id: int, _slot_id: int, _player_name: String) -> void:
	if not _session().is_host():
		return
	if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
		return
	var state: Dictionary = SnowRelay.instance().last_state
	if SnowRelay.is_empty_state(state):
		return
	states_sent += 1
	NetFanout.send_to(self, _session(), peer_id, &"net_snow_state", [state])


@rpc("authority", "call_remote", "reliable")
func net_snow_state(state: Dictionary) -> void:
	if _session().is_host():
		states_refused += 1
		return
	if awaiting_world.is_valid() and bool(awaiting_world.call()):
		states_refused += 1
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != MultiplayerPeer.TARGET_PEER_SERVER:
		states_refused += 1
		return
	apply_state(state)


# --- Client --------------------------------------------------------------------------------

## Client: validates and draws a replicated state. Returns false (and changes
## nothing) on the host, for a malformed payload, or for snow arriving while
## no snow event is live (an empty state is always accepted: it clears).
func apply_state(raw: Variant) -> bool:
	if _session().is_host():
		states_refused += 1
		return false
	var authority: MatchHostPort = _authority()
	var field: Field = authority.field() as Field
	var max_cell: int = field.grid().cell_count() - 1 if field != null else -1
	var data: Dictionary = SnowGeometry.sanitize_state(raw, _tuning, max_cell)
	if data.is_empty():
		states_refused += 1
		return false
	var has_snow: bool = int(data["cover"]) > 0 or not (data["blocks"] as Dictionary).is_empty() or not (data["disc"] as Dictionary).is_empty()
	if has_snow and not _snow_live(authority):
		states_refused += 1
		return false
	_client_renderer().apply(data)
	states_applied += 1
	return true


func _snow_live(authority: MatchHostPort) -> bool:
	if not MatchAutoload.is_replicating(authority.state()):
		return false
	var weather: MatchWeather = authority.weather() as MatchWeather
	return weather != null and weather.active_id() == WeatherIds.SNOW


## Client: removes every drawn cap.
func clear_client() -> void:
	_client_renderer().clear()


## Client: steps the geometry builder (budgeted like the host's).
func step_client(budget: int) -> void:
	if _renderer != null:
		_renderer.step(budget)


func _client_renderer() -> SnowClientRenderer:
	if _renderer == null:
		_renderer = SnowClientRenderer.new(_tuning, _client_field, _client_registry)
	return _renderer


func _client_field() -> Field:
	return _authority().field() as Field


func _client_registry() -> BlockRegistry:
	return _authority().registry() as BlockRegistry


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if _session().is_host():
		return
	if MatchAutoload.is_resetting(to_state):
		clear_client()


func _on_weather_stopped(weather_id: StringName) -> void:
	if weather_id == WeatherIds.SNOW and not _session().is_host():
		clear_client()


## A block spawned on a client after the state that names it: draw it once
## its net_id is bound (MatchNet binds right after emitting block_placed).
func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	if _renderer != null and _renderer.is_unresolved() and not _render_queued and not _session().is_host():
		_render_queued = true
		_render_again.call_deferred()


func _render_again() -> void:
	_render_queued = false
	if _renderer != null:
		_renderer.render()
