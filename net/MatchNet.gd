extends Node
## Every gameplay RPC in the game (spec 2.6 "Client -> host intents" and the
## reliable channel's list), and nothing else.
##
## Registered as the `MatchNet` autoload, so the RPC node path is
## /root/MatchNet on every instance. **No `class_name`** — it would collide
## with the singleton name.
##
## The RPC membrane: every RPC stub lives here and forwards to a collaborator in net/match/.
## Registered as the `MatchNet` autoload, so the RPC node path is /root/MatchNet on every
## instance. **No `class_name`** -- it would collide with the singleton name. Match keeps every
## rule; nothing here decides one and nothing in core/ or Match calls rpc() directly. The host's
## outcomes reach clients by mirroring the Events bus (MatchEventMirror); a client re-emits them
## so every consumer works with no idea it is networked. The host's own local intents run inline;
## there is no client-side placement prediction.

## Reliable gameplay traffic uses channel 0 (the MultiplayerAPI default).
## Cursors get their own so a 15 Hz stream cannot delay a spawn. The number
## must be a compile-time constant for @rpc, so it lives here rather than in
## NetConfig; NetConfig documents the pairing.
const CURSOR_CHANNEL: int = 2

## The territory wire version (net/match/TerritoryReplicator.gd owns the layout); the RPC contract
## test reads it here.
const RASTER_VERSION: int = TerritoryReplicator.VERSION

@export var config: NetConfig = preload("res://config/net/net_config.tres"):
	set(value):
		config = value
		# The gateway and the replay collaborator read the flood limits from this resource.
		_intent_gateway = null
		_world_replay_host = null
		_bind_modules()

## Clients build their replicated bodies with the same factory and the same
## tuning the host built the originals with, so a frozen copy has the same
## collision shape and mass even though it never simulates.
var _physics_tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
## Client-side block spawns/despawns and the seat roster (net/match/ClientBlockMirror.gd), built on first use.
var _block_mirror: ClientBlockMirror = null

## Every instrumentation counter (the per-slot intent identities and the match-start
## records); net/NetCounters.gd.
var counters: NetCounters = NetCounters.new()
## DECISION (net/MatchNet.gd): GUT cannot double the Net and Match autoloads, so this node reaches
## them through the three ports (bind_ports). Unbound, they are built over the autoloads on first
## use (every shipped build); tests bind ports over doubles.

## True while the session port is the real Net autoload (the snapshot stream only exists there).
var _session_is_autoload: bool = true

## The intent door (net/match/MatchIntentGateway.gd): local submit_*, host handle_* with the
## per-peer flood gate. Built on first use so bind_ports() can rebind it.
var _intent_gateway: MatchIntentGateway = null
## The gateway, built on first read (a typed receiver, so the call graph resolves it).
var _gateway: MatchIntentGateway:
	get:
		return _intents()

## Territory, impacts and match start, both directions (net/match/MatchReplication.gd), built on first use.
var _replication_module: MatchReplication = null

## -- Mid-match join / reconnect replay -----------------------
## Host only: the join/replay/ack/timeout collaborator (net/match/MatchWorldReplay.gd), built on first use.
var _world_replay_host: MatchWorldReplay = null
var _world_replay: MatchWorldReplay:
	get:
		return _replays()
## Client-side world gate and replay span (net/match/ClientReplayGate.gd), built on first use.
var _replay_gate: ClientReplayGate = null

## The weather RPC child (net/WeatherNet.gd).
var _weather_net: Node = null
## Client gift wire phases and special-id checks (net/match/GiftWireGuard.gd), built on first use.
var _gift_guard: GiftWireGuard = null
## Last ghost per slot and the host auto-drop pose (net/match/SlotCursors.gd), built on first use.
var _slot_cursors: SlotCursors = null
## The client-side event applier child (net/MatchEventApplier.gd); net_match_event stays the RPC entry point.
var _applier: Node = null
## The typed Match reads the mirror and the state handler make; rebuilt when the providers change.
var _host_port_cache: MatchHostPort = null
var _session_port_cache: SessionPort = null
var _replica_port_cache: MatchReplicaPort = null
## The host Events subscribers (net/match/MatchEventMirror.gd), built on first use.
var _mirror: MatchEventMirror = null
## true once late_activate() has built the WeatherNet child.
var _late_active: bool = false


func _ready() -> void:
	var host: MatchHostPort = _host_port()
	host.set_replicator(self)
	var mirror: MatchEventMirror = _event_mirror()
	mirror.bind(Events)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	Events.block_removed.connect(_on_block_removed)
	Events.block_dissolve_started.connect(_on_block_dissolve_started)
	_replication()
	Events.block_impacted_at.connect(_on_block_impacted_at)
	Events.net_peer_left.connect(_on_net_peer_left)
	Events.net_peer_joined.connect(_on_net_peer_joined)
	Events.net_mode_changed.connect(_on_net_mode_changed)
	multiplayer.peer_disconnected.connect(_forget_peer)
	# the WeatherNet child is built by late_activate(); headless
	# and non-Boot runs activate right here, a windowed Boot run lets Boot prewarm first.
	if LateScripts.boot_defers_activation(get_tree()):
		# _process reads Match state, which does not exist until
		# Match.late_activate(); stay idle until our own late_activate() re-enables it.
		set_process(false)
	else:
		late_activate()


func is_late_active() -> bool:
	return _late_active


## Builds the WeatherNet child (RPC path /root/MatchNet/WeatherNet is unchanged).
## Idempotent; LateScripts.activate_autoloads() calls it once Boot has prewarmed.
func late_activate() -> void:
	if _late_active:
		return
	_late_active = true
	set_process(true)
	# weather replication lives in its own child node.
	_weather_net = LateScripts.script(LateScripts.WEATHER_NET).new() as Node
	_weather_net.name = "WeatherNet"
	add_child(_weather_net)
	_bind_weather_ports()
	# weather/snow/breeze broadcasts before net_match_start
	# are dropped on the same gate as match events.
	_weather_net.awaiting_world = _gate().awaiting_world
	_event_applier()


## The event applier child; built on first use so a test that skips
## late_activate() still works. Not an RPC node, so no path is peer-visible.
func _event_applier() -> Node:
	if _applier == null:
		_applier = LateScripts.script(LateScripts.MATCH_EVENT_APPLIER).new() as Node
		_applier.name = "MatchEventApplier"
		_bind_applier()
		add_child(_applier)
	return _applier


## The client gift wire state, bound to the current Match provider and config.
func _gift_wire() -> GiftWireGuard:
	if _gift_guard == null:
		_gift_guard = GiftWireGuard.new()
		_gift_guard.bind(_host_port(), config)
	return _gift_guard


## The cursor store; its cursors survive a rebind.
func _cursors() -> SlotCursors:
	if _slot_cursors == null:
		_slot_cursors = SlotCursors.new(_now, preload("res://config/blocks/tuning/ghost_tuning.tres"), preload("res://config/territory/beacon_visual_tuning.tres"), _physics_tuning)
		_slot_cursors.bind(_host_port())
	return _slot_cursors


func _bind_applier() -> void:
	_applier.call(&"bind", _session_port(), _host_port(), _replica_port(), config, _gift_wire())


## Rebinds the modules already built onto the current ports and config (the config setter and
## bind_ports call it); it never builds one early. Their state survives, see GiftWireGuard.bind.
func _bind_modules() -> void:
	if _session_port_cache == null:
		return
	if _gift_guard != null:
		_gift_guard.bind(_host_port(), config)
	if _replay_gate != null:
		_replay_gate.bind(_session_port(), config)
	if _slot_cursors != null:
		_slot_cursors.bind(_host_port())
	if _replication_module != null:
		_replication_module.bind(_session_port(), _host_port(), _replica_port(), config)
	if _applier != null:
		_bind_applier()


## The client gate, bound to the current session and config on first use; its state survives a rebind.
func _gate() -> ClientReplayGate:
	if _replay_gate == null:
		_replay_gate = ClientReplayGate.new()
		_replay_gate.bind(_session_port(), config)
	return _replay_gate


## The replication module, built on first use over the current ports; a rebind keeps it (state
## that survives a rebind is listed on MatchReplication.bind).
func _replication() -> MatchReplication:
	if _replication_module == null:
		var seams: MatchReplication.Seams = MatchReplication.Seams.new()
		seams.can_send = func() -> bool: return NetFanout.can_send(multiplayer, _session_port())
		seams.broadcast = func(method: StringName, args: Array) -> void: _broadcast(method, args)
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			return NetFanout.send_to(self, _session_port(), peer_id, method, args)
		seams.peer_ids = func() -> Array[int]:
			var ids: Array[int] = []
			ids.assign(multiplayer.get_peers())
			return ids
		seams.is_replay_pending = func(peer_id: int) -> bool: return _world_replay.is_pending(peer_id)
		seams.now_ms = Time.get_ticks_msec
		seams.view_delay_ms = func() -> int:
			return int(SnapshotSync.interpolation_delay_ms()) if SnapshotSync.is_running() else 0
		_replication_module = MatchReplication.new(seams, _event_mirror())
		_replication_module.bind(_session_port(), _host_port(), _replica_port(), config)
	return _replication_module


func _host_port() -> MatchHostPort:
	_ensure_ports()
	return _host_port_cache


func _replica_port() -> MatchReplicaPort:
	_ensure_ports()
	return _replica_port_cache


func _session_port() -> SessionPort:
	_ensure_ports()
	return _session_port_cache


## Unbound, the ports go over the Net and Match autoloads (the shipped build).
func _ensure_ports() -> void:
	if _session_port_cache != null:
		return
	if bind_ports(
			SessionPort.new(Net),
			MatchHostPort.new(Match),
			MatchReplicaPort.new(Match)):
		_session_is_autoload = true


## Binds the three ports every path of this node and its collaborators share, drops the collaborators
## built on the old ones (the gateway, the world replay) so they rebuild on
## these, and rebinds the ones that hold ports. Installing this node as the host's replicator stays
## with the caller (_ready).
## Returns false (and binds nothing) when any port is missing or invalid.
func bind_ports(session: SessionPort, host: MatchHostPort, replica: MatchReplicaPort) -> bool:
	if session == null or host == null or replica == null or not (session.is_valid() and host.is_valid() and replica.is_valid()):
		push_error("MatchNet.bind_ports: a port is missing or invalid")
		return false
	_session_port_cache = session
	_host_port_cache = host
	_replica_port_cache = replica
	_session_is_autoload = false
	_intent_gateway = null
	_world_replay_host = null
	_block_mirror = null
	if _mirror != null:
		_mirror.bind_ports(session, host)
	_bind_modules()
	_bind_weather_ports()
	return true


## Hands the bound ports to the weather child (its snow and breeze children read the autoloads).
## Nothing to do while the ports are the autoloads: the child builds those itself.
func _bind_weather_ports() -> void:
	var weather: PortBoundNode = _weather_net as PortBoundNode
	if weather != null and not _session_is_autoload:
		weather.bind(_session_port(), _host_port())


## The host Events subscribers, sending through the same seams shape the intent gateway uses. The
## ports are rebound whenever bind_ports() runs, so the Events connections the mirror holds never go stale.
func _event_mirror() -> MatchEventMirror:
	if _mirror == null:
		var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			return NetFanout.send_to(self, _session_port(), peer_id, method, args)
		seams.broadcast = func(_method: StringName, args: Array) -> void: replicate_match_event(args[0], args[1])
		_mirror = MatchEventMirror.new(seams)
		_mirror.bind_ports(_session_port(), _host_port())
	return _mirror


func _exit_tree() -> void:
	if _replay_gate != null:
		_replay_gate.end_replay()
	_host_port().release_replicator(self)


## The intent gateway, bound to the current session and Match providers. The seams are the only
## transport it sees; the sender id of an RPC is read by the stubs below, never by the gateway.
func _intents() -> MatchIntentGateway:
	if _intent_gateway == null:
		var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
		seams.can_send = func() -> bool: return NetFanout.can_send(multiplayer, _session_port())
		seams.send_to_host = func(method: StringName, args: Array) -> void: callv(&"rpc_id", [Net.HOST_PEER_ID, method] + args)
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			return NetFanout.send_to(self, _session_port(), peer_id, method, args)
		seams.broadcast = func(method: StringName, args: Array) -> void: _broadcast(method, args)
		seams.now_s = _now
		seams.is_replay_pending = _world_replay.is_pending
		seams.store_cursor = _cursors().store
		_intent_gateway = MatchIntentGateway.new(_session_port(), _host_port(), config, counters, seams)
	return _intent_gateway


## The world replay collaborator, bound to the current session and Match providers. Its pending
## state survives only until a provider or config change rebuilds it.
func _replays() -> MatchWorldReplay:
	if _world_replay_host == null:
		var seams: MatchWorldReplay.Seams = MatchWorldReplay.Seams.new()
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			return NetFanout.send_to(self, _session_port(), peer_id, method, args)
		seams.now_s = _now
		seams.clear_cursor = func(slot_id: int) -> void: _cursors().clear(slot_id)
		seams.spawn_args = _replication().spawn_args
		seams.glued_ids = func() -> Array: return _event_mirror().glued_ids()
		seams.territory_args = func() -> Array: return _replication().territory_replay_args()
		seams.replay_acknowledged = _on_replay_acknowledged
		_world_replay_host = MatchWorldReplay.new(_session_port(), _host_port(), config, seams)
	return _world_replay_host


## Spec 2.6's snapshots resume: the next one carries every body, so the joiner's interpolator
## starts from fresh samples for sleepers too.
func _on_replay_acknowledged() -> void:
	if _session_is_autoload:
		SnapshotSync.request_full_snapshot()


## every host -> clients broadcast goes through here, so a peer the
## host is kicking (still listed by the transport until its disconnect completes)
## is never addressed. See net/NetFanout.gd.
func _broadcast(method: StringName, args: Array = []) -> void:
	NetFanout.broadcast(self, _session_port(), method, args)


func _process(delta: float) -> void:
	if not _session_port().is_host():
		_gate().tick(Time.get_ticks_msec())
		_replication().play_due_impacts()
		return
	_world_replay.tick_timeouts(_now())
	_replication().tick_host_feeds(delta)


# --- Local -> authority (the one door every intent goes through) ------------

## The single call site for a placement, host or client, local or remote
## (net/match/MatchIntentGateway.gd). On the host it is Match.request_place()
## inline; on a client it is the reliable intent RPC and the return value is
## REASON_OK optimistically (the real outcome arrives as Events.placement_rejected
## or the next feed_block_issued). `feed_seq` is Match.feed_seq(slot_id) as the
## caller last saw it; the host refuses an intent whose feed_seq is not current.
func submit_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> StringName:
	return _gateway.submit_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)


## submit_place()'s twin for a throw (spec 2.6: the host clamps velocity to throw_max_speed).
func submit_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> StringName:
	return _gateway.submit_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)


## The local player's ghost pose, at NetConfig.cursor_hz. Unreliable: a lost
## one costs one frame of someone else's ghost. On the host this only
## broadcasts; on a client it also goes to the host, which stores it as the
## slot's last known ghost — **that is what the host auto-drops from when the
## feed timer expires**, so no round trip can lose an auto-drop.
##
## Callers may call this every frame: the local record is always refreshed and
## the send is throttled to config.cursor_hz here, so no caller has to own a
## rate accumulator of its own.
##
## `aim` is the player's unit camera forward. It rides only the client->host
## packet (other clients never see it); the host keeps it as the slot's expiry-throw aim.
func submit_cursor(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, aim: Vector3 = Vector3.ZERO
) -> void:
	_gateway.submit_cursor(slot_id, origin, orientation_index, free_quat, aim)


func submit_cat_target(slot_id: int, point: Vector3) -> void:
	_gateway.submit_cat_target(slot_id, point)


## Results screen "Play again": restarts the match that just ended with the same MatchConfig, for
## every peer. The host's own call acts inline (a call offline has no roster peer map to check
## against); a remote one goes through the reliable RPC below and is validated.
##
## DECISION (net/MatchNet.gd): any seated slot may request a replay/return, not only the host's
## player (spec 2.6 names no narrower rule). MatchIntentGateway authorizes a remote sender and
## drops unseated and non-State.END requests; the host's local call is also State.END-gated.
func request_replay() -> void:
	_gateway.request_replay()


## Results screen "Return to lobby": sends every peer back to State.LOBBY.
## Mirrors request_replay() above exactly.
func request_return_to_lobby() -> void:
	_gateway.request_return_to_lobby()


@rpc("any_peer", "call_remote", "reliable")
func net_request_replay() -> void:
	_gateway.handle_replay_request(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func net_request_return_to_lobby() -> void:
	_gateway.handle_return_request(multiplayer.get_remote_sender_id())


## The last cursor the host received for `slot_id`, or an empty Dictionary.
## {"origin": Vector3, "orientation_index": int, "free_quat": Quaternion,
## "age": float}. Match reads this for auto-drop; RemoteCursors draws it.
func cursor_for_slot(slot_id: int) -> Dictionary:
	return _cursors().for_slot(slot_id)


# --- Host -> clients: replication hooks Match calls -------------------------

## Host only. Announces a block the host just spawned, reliably, before any snapshot can reference
## it (MatchReplication.send_spawn).
func replicate_spawn(block: BlockBody, net_id: int) -> void:
	_replication().send_spawn(block, net_id)


func replicate_despawn(net_id: int, reason: String) -> void:
	_replication().send_despawn(net_id, reason)


## Host only. Mirrors a match-flow event to every client. A per-player cue (a refusal, a
## relocation) is not one of these: it goes to its owning peer alone.
func replicate_match_event(event: StringName, args: Array) -> void:
	_replication().send_match_event(event, args)


## Host only. Ships the whole match start; idempotent for one match, so an explicit call from the
## lobby and the automatic one on LOADING cannot both go out.
func replicate_match_start(match_config: MatchConfig) -> void:
	_replication().send_match_start(match_config)


## Host only. One reliable message ahead of net_match_start, so a client can raise its loading
## overlay before the synchronous world build that net_match_start triggers.
func replicate_match_loading() -> void:
	_replication().send_match_loading()


# --- Counters the acceptance harness asserts on -----------------------------

## Deliberate placement intents this instance sent (as a client, for its own slot) or received
## (as the host, for any slot); auto-drops never cross the wire and are counted separately. The
## harness asserts accepted + refused == sent per slot on the host, and a client's sent equals
## the host's.
func intents_sent(slot_id: int) -> int:
	return counters.sent_count(slot_id)


func intents_accepted(slot_id: int) -> int:
	return counters.accepted_count(slot_id)


func intents_refused(slot_id: int) -> int:
	return counters.refused_count(slot_id)


## Cursor updates from `slot_id`'s peer the host dropped as malformed.
func cursors_refused(slot_id: int) -> int:
	return counters.cursors_refused_count(slot_id)


## Drops every counter and cursor. Called when a match starts or ends.
func reset_counters() -> void:
	if _intent_gateway != null:
		_intent_gateway.reset_throttles()
	if _gift_guard != null:
		_gift_guard.reset()
	counters.reset()
	if _slot_cursors != null:
		_slot_cursors.reset()
	_replication().reset()
	# a (re)start is itself a full sync for every peer (the
	# broadcast net_match_start), so no replay is still owed an ack.
	_world_replay.reset()
	_event_mirror().reset_glue()


# --- Host-side intent handling ----------------------------------------------

## the use_gift_slot intent, host or client. The client only
## sends the request; the host validates it (sender owns the slot, slot holds a
## gift, state, no gift already in hand) and the result arrives as the normal
## feed event. Returns whether the request was applied (host) or sent (client).
func submit_use_gift_slot(slot_id: int) -> bool:
	return _gateway.submit_use_gift_slot(slot_id)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _client_blocks() -> ClientBlockMirror:
	if _block_mirror == null:
		_block_mirror = ClientBlockMirror.new(_session_port(), _host_port(), _gift_wire().special_id_ok, _physics_tuning)
	return _block_mirror


# --- Events the host mirrors to its clients ---------------------------------

func _on_match_state_changed(from_state: int, to_state: int) -> void:
	var replication: MatchReplication = _replication()
	var new_match: bool = replication.on_match_state_changed(to_state)
	if not _session_port().is_host():
		return
	if new_match:
		# The lobby may call replicate_match_start() itself; this is the belt-and-braces path.
		reset_counters()
		replicate_match_start(_host_port().config())
	# The LOBBY/LOADING/COUNTDOWN start_match() produces internally is replayed on a client by
	# net_match_start alone (the mirror skips it); every other state change replicates normally.
	_event_mirror().on_state_changed(from_state, to_state)


## Spec 1.4's auto-drop is [ORIGINAL] and must keep dropping "from its current
## ghost position", so it must never make a round trip: a request sent to a
## remote player and back on timer expiry could be lost or arrive twice. The
## host therefore drops for every slot it does not itself control, from the
## last update_cursor it received for that slot — at NetConfig.cursor_hz that
## is at worst 67 ms stale, and closest_valid_point() relocates from there
## anyway. A slot this instance controls locally (every slot offline, which is
## all of local play) is left to its own PlayerController, whose ghost is
## exact and costs nothing.
func _on_feed_timer_expired(slot_id: int) -> void:
	if not _session_port().is_host():
		return
	# The ghost flash is feedback, not a rule, so every instance gets it.
	_event_mirror().on_feed_expired(slot_id)
	if bool(_session_port().is_local_slot(slot_id)):
		return
	var pose: Dictionary = _cursors().auto_drop_pose(slot_id)
	_gateway.apply_place(slot_id, pose["origin"], pose["orientation_index"], pose["free_quat"], true, _host_port().feed_seq(slot_id))


## A refusal is feedback for the refused player alone, so it goes only to the
## peer that holds the slot -- never the host's own seat, a bot's or a vacated
## one, which have no remote peer to tell. The host's own seat reacts to
## Match's local emit directly.
func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	if not _session_port().is_host():
		return
	# The intent handler that is applying this refusal must not send it again.
	if _event_mirror().on_placement_rejected(slot_id, reason):
		_gateway.note_rejection_sent(slot_id)


## Mirrors an auto-drop's relocation to the owning client so its
## cursor and camera can jump to where the block landed.
##
## That jump is the owning seat's own feedback, so it goes to that peer alone,
## like a refusal, instead of to every client that would only ignore it
## (PlayerController and the HUD drop a slot that is not theirs). Never the
## host's own seat (it reacts to Match's local emit), a bot's, or a vacated
## one: no remote peer to tell.
func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	if not _session_port().is_host():
		return
	_event_mirror().on_placement_relocated(slot_id, point)


## Field's kill plane removes a body by emitting on the bus, so the despawn is
## replicated from here rather than from Field — which then needs no idea that
## multiplayer exists.
func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	var typed: BlockBody = block as BlockBody
	if typed != null:
		_event_mirror().forget_glued(typed.net_id)
		replicate_despawn(typed.net_id, reason)


## Host: mirrors a dissolve start so clients can play the same fade. A body
## without a wire id (net_id allocation failed) never reached a client.
func _on_block_dissolve_started(block: RigidBody3D, net_id: int, duration_s: float) -> void:
	if not _session_port().is_host() or not Quantize.is_wire_id(net_id):
		return
	_event_mirror().on_block_dissolve_started(block, net_id, duration_s)


## Host: one detected impact, queued for clients while someone can hear it.
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	_replication().on_block_impacted_at(speed, position)


func _on_net_peer_left(peer_id: int, slot_id: int, _reason: int) -> void:
	_forget_peer(peer_id)
	if slot_id >= 0:
		var host: MatchHostPort = _host_port()
		host.on_peer_left(slot_id)


## Any transport disconnect, including a peer that never finished the handshake (Net emits
## net_peer_left only for seated ones): its replay and flood buckets go, so a rejoin starts full.
func _forget_peer(peer_id: int) -> void:
	_world_replay.on_peer_left(peer_id)
	_gateway.forget_peer(peer_id)


## A peer was seated (Net emits this after it has already sent the joiner its join-accepted and
## the roster). In the lobby that is all: the broadcast net_match_start carries the world.
## Mid-match the host owes this peer the whole world as one ordered replay (MatchWorldReplay).
func _on_net_peer_joined(peer_id: int, slot_id: int, player_name: String) -> void:
	_world_replay.on_peer_joined(peer_id, slot_id, player_name)


func _on_net_mode_changed(mode: int) -> void:
	_gate().on_mode_changed(mode == Net.Mode.CLIENT)
	_replication().clear_impacts()


## Host only, installed into Net's seat policy by game/main/Main.gd (MatchWorldReplay.pick_open_seat).
func pick_open_seat() -> int:
	return _world_replay.pick_open_seat()


## Host only, installed into Net's seat policy by game/main/Main.gd (MatchWorldReplay.seat_reclaimable).
func seat_reclaimable(slot_id: int) -> bool:
	return _world_replay.seat_reclaimable(slot_id)


# --- RPCs -------------------------------------------------------------------
# Client -> host. The host checks the caller's peer id against `slot_id`
# (spec 2.6: "The host checks territory, the timer, and that the slot
# matches") and drops anything else on the floor; it never trusts slot_id.

# auto_drop is part of the wire contract but deliberately never read: spec
# 2.5's relocation privilege belongs to the host's own timer, not to whoever
# is on the other end of a socket. See MatchIntentGateway.handle_place().
@warning_ignore("unused_parameter")
@rpc("any_peer", "call_remote", "reliable")
func net_request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> void:
	_gateway.handle_place(multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat, feed_seq)


## Spec 2.6: "request_throw(slot_id, pos, orient, velocity): the host clamps
## velocity to throw_max_speed." Mirrors net_request_place above exactly.
@rpc("any_peer", "call_remote", "reliable")
func net_request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> void:
	_gateway.handle_throw(
		multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat, velocity, feed_seq
	)


@rpc("any_peer", "call_remote", "reliable")
func net_request_use_gift_slot(slot_id: int) -> void:
	_gateway.handle_gift_slot(multiplayer.get_remote_sender_id(), slot_id)


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_update_cursor(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, aim: Vector3 = Vector3.ZERO
) -> void:
	_gateway.handle_cursor(multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat, aim)


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cat_target(slot_id: int, point: Vector3) -> void:
	_gateway.handle_cat_target(multiplayer.get_remote_sender_id(), slot_id, point)


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	if _client_awaiting_world():
		return
	var replica: MatchReplicaPort = _replica_port()
	replica.apply_replicated_cat_state(id, position, velocity, point, remaining)


# Host -> clients.

## one batch of host-detected block impacts. Unreliable on the
## cosmetic CURSOR_CHANNEL: a lost batch is a missed thud, never worth a
## retransmit or head-of-line blocking a spawn on channel 0. Events are
## position-keyed (ImpactWire's DECISION), so arrival order relative to the
## reliable spawn/despawn stream does not matter.
@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_block_impacts(packet: PackedByteArray) -> void:
	if _session_port().is_host() or _client_awaiting_world():
		return
	_replication().receive_impacts(packet)


@rpc("authority", "call_remote", "reliable")
func net_match_loading() -> void:
	Events.match_loading_announced.emit()


## `replay_id` is 0 for the broadcast every client gets at match start, and the
## replay's own id (> 0) when this is the first message of a late-join /
## reconnect world replay (see MatchWorldReplay). The replay span is silent for
## one-shot feedback: see Events.world_replay_changed.
@rpc("authority", "call_remote", "reliable")
func net_match_start(config_data: Dictionary, roster: Array, replay_id: int = 0) -> void:
	var match_config: MatchConfig = MatchConfig.from_dict(config_data)
	match_config.sanitize()
	reset_counters()
	# Before start_match(): its own state events belong to the replay too.
	_gate().on_match_start(replay_id, Time.get_ticks_msec())
	_host_port().start_match(match_config)
	_client_blocks().apply_roster(roster)


## the client half of the replay handshake. Lands after every
## replay message (reliable, ordered), so the world is built by now.
@rpc("authority", "call_remote", "reliable")
func net_replay_end(replay_id: int) -> void:
	# The replay's last message: live events from here on are news again.
	if not _gate().on_replay_end(replay_id):
		return
	if NetFanout.can_send(multiplayer, _session_port()):
		rpc_id(Net.HOST_PEER_ID, &"net_replay_ack", replay_id)


@rpc("any_peer", "call_remote", "reliable")
func net_replay_ack(replay_id: int) -> void:
	_world_replay.handle_replay_ack(multiplayer.get_remote_sender_id(), replay_id)


## True on a client that has not received net_match_start since it joined (ClientReplayGate).
func _client_awaiting_world() -> bool:
	return _gate().awaiting_world()


@rpc("authority", "call_remote", "reliable")
func net_match_event(event: StringName, args: Array) -> void:
	if _client_awaiting_world():
		return
	_event_applier().call(&"apply_event", event, args)


@rpc("authority", "call_remote", "reliable")
func net_block_spawned(
	net_id: int,
	shape_id: StringName,
	owner_slot: int,
	origin: Vector3,
	rotation: Quaternion,
	gift_id: StringName = &""
) -> void:
	if _client_awaiting_world():
		return
	_client_blocks().on_spawned(net_id, shape_id, owner_slot, origin, rotation, gift_id)


@rpc("authority", "call_remote", "reliable")
func net_block_despawned(net_id: int, reason: String) -> void:
	if _client_awaiting_world():
		return
	_client_blocks().on_despawned(net_id, reason)


## `payload` is one TerritoryReplicator packet (raster diff or keyframe, shares, capture ring,
## circles); a client applies it to its mirror raster and re-emits the territory signals, so Field
## opens the same holes without a second RPC. A malformed packet is dropped whole.
# SHORTCUT: the trailing arguments after payload are neutral and ignored, drop them with the next wire version bump.
# They stay so the RPC surface and its history entry do not change.
@warning_ignore("unused_parameter")
@rpc("authority", "call_remote", "reliable")
func net_territory(
	payload: PackedByteArray,
	full: bool,
	shares: PackedFloat32Array,
	capture_team: int,
	capture_progress: float,
	circle_payload: PackedByteArray = PackedByteArray()
) -> void:
	if _client_awaiting_world():
		return
	_replication().receive_territory(payload)


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	if _client_awaiting_world() or bool(_session_port().is_local_slot(slot_id)):
		return
	_cursors().store(slot_id, origin, orientation_index, free_quat)
	Events.remote_cursor_updated.emit(slot_id, origin, orientation_index, free_quat)
