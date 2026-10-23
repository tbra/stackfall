extends Node
## Every gameplay RPC in the game (spec 2.6 "Client -> host intents" and the
## reliable channel's list), and nothing else.
##
## Registered as the `MatchNet` autoload, so the RPC node path is
## /root/MatchNet on every instance. **No `class_name`** — it would collide
## with the singleton name.
##
## **Why a separate node from Match.** autoload/Match.gd stays the authority
## and keeps every rule; it gains only host gates. MatchNet is the membrane:
## it turns a local action into either a direct Match call (host) or an RPC
## (client), and turns the host's outcomes into replication. Nothing in
## core/ or Match may call rpc() directly, and nothing here may decide a rule.
## Swapping the transport changes nothing in this file.
##
## **The host's local player is latency-free.** submit_place() on the host
## calls Match.request_place() inline, in the same frame as the click. Only a
## client pays a round trip, and it pays it once — there is no client-side
## prediction of a placement, because a mispredicted block in a physics stack
## is worse than a 50 ms wait.
##
## **How the host's outcomes get out.** Match emits on the Events bus and
## never knows this file exists beyond a replicate_spawn() hook it installs
## here in _ready(). Everything else — state changes, the countdown, feed
## issues, rejections, eliminations, the win, kill-plane despawns — this node
## mirrors by listening to the same bus the rest of the game listens to
## (CLAUDE.md's "use a global signal bus to decouple systems"). A client
## re-emits them locally, so every consumer (the HUD, the ghost, Field)
## works on a client with no idea it is networked.

## Reliable gameplay traffic uses channel 0 (the MultiplayerAPI default).
## Cursors get their own so a 15 Hz stream cannot delay a spawn. The number
## must be a compile-time constant for @rpc, so it lives here rather than in
## NetConfig; NetConfig documents the pairing.
const CURSOR_CHANNEL: int = 2

## The MatchReplicaPort writes MatchNet makes itself (cat state, territory, slot replay).
const _REPLICA_PORT_METHODS: PackedStringArray = ["apply_replicated_cat_state", "apply_replicated_territory", "apply_replicated_gift_claimed", "apply_replicated_feed"]

## What the default ports (over the Net and Match autoloads) must answer: the union of what MatchNet
## and its collaborators (intent gateway, world replay, event mirror, event applier, territory
## replicator) call, so one bound port serves them all.
const _SESSION_PORT_METHODS: PackedStringArray = ["is_host", "is_offline", "local_slot", "slot_of_peer", "peer_of_slot", "is_local_slot", "peer_ids", "peer_info", "kick_peer"]
const _HOST_PORT_METHODS: PackedStringArray = [
	"config", "state", "slot_count", "slot", "request_place", "request_throw", "request_use_gift_slot", "set_cat_target",
	"is_pose_well_formed", "feed_seq", "feed_time_left", "is_release_locked", "eliminated_by", "on_peer_rejoined",
	"abort_match", "start_match", "active_cat", "active_slot", "blocks_parent", "registry", "stats", "raster",
	"circle_render_arrays", "circle_wire_xz_bound", "circle_wire_radius_max", "territory_share", "countdown_remaining",
	"match_timer_left", "mode_state_snapshot", "qol_backlog_count", "qol_timer_paused", "gift_slot_contents",
	"gift_states", "gift_state", "gift_slot_enabled", "glue_drops_left", "glue_revision",
]

## The territory wire version (net/match/TerritoryReplicator.gd owns the layout); the RPC contract
## test reads it here.
const RASTER_VERSION: int = TerritoryReplicator.VERSION

## Names for the match-flow events mirrored over net_match_event. StringNames
## rather than an enum so a packet capture reads as itself.
const EVENT_STATE_CHANGED: StringName = &"state_changed"
const EVENT_COUNTDOWN: StringName = &"countdown"
const EVENT_TURN_CHANGED: StringName = &"turn_changed"
const EVENT_FEED_ISSUED: StringName = &"feed_issued"
const EVENT_FEED_EXPIRED: StringName = &"feed_expired"
## [slot_id, backlog_count, timer_paused] for the QoL experiments.
const EVENT_QOL_FEED: StringName = &"qol_feed"
## [slot_id, contents, activated_special, carrier_shape_id] for the QoL gift slot.
const EVENT_GIFT_SLOT: StringName = &"gift_slot"
const EVENT_PLACEMENT_REJECTED: StringName = &"placement_rejected"
## longest refusal reason a client will show. The real ones
## (PlacementRules/ThrowRules REASON_*) are all well under this; a longer one is
## not from this build's host.
const REJECT_REASON_MAX_LENGTH: int = 48
const EVENT_PLACEMENT_RELOCATED: StringName = &"placement_relocated"
const EVENT_PLAYER_ELIMINATED: StringName = &"player_eliminated"
const EVENT_MATCH_WON: StringName = &"match_won"
## the active mode objective's score/state, host -> clients.
const EVENT_MODE_STATE: StringName = &"mode_state"
## mirrors Events.match_results_ready (autoload/match/
## MatchStats.gd's own header documents the payload shape). See
## _on_match_results_ready() below and net_match_event's own dispatch case.
const EVENT_MATCH_RESULTS: StringName = &"match_results"
const EVENT_GIFT_FLIGHT: StringName = &"gift_flight_spawned"
const EVENT_GIFT_LANDED: StringName = &"gift_landed"

# DECISION: reliable channel order plus per-match tombstones prevents a late
# spawn/flight from resurrecting a claimed gift. A spawn-only gift can upgrade once.
# DECISION: the enum below shadows the global GiftWirePhase
# class inside this file, so the pure numbering module is reached through this alias.
const _WIRE_PHASE_OWNER: GDScript = preload("res://core/gifts/GiftWirePhase.gd")
enum GiftWirePhase {
	FALLING = _WIRE_PHASE_OWNER.FALLING,
	LANDED = _WIRE_PHASE_OWNER.LANDED,
	SPAWN_ONLY = _WIRE_PHASE_OWNER.WIRE_LEGACY,
	REMOVED = _WIRE_PHASE_OWNER.WIRE_REMOVED,
}
var _gift_wire_phases: Dictionary = {}
var _gift_spawn_notified: Dictionary = {}

const EVENT_GIFT_SPAWNED: StringName = &"gift_spawned"
const EVENT_GIFT_CLAIMED: StringName = &"gift_claimed"
const EVENT_GIFT_EXPIRED: StringName = &"gift_expired"
## mirrors game/gifts/specials/SpecialBehavior.gd's own trigger, via
## autoload/match/MatchPlacement._on_special_behavior_triggered() ->
## Events.special_triggered (host only). See _on_special_triggered() below.
const EVENT_SPECIAL_TRIGGERED: StringName = &"special_triggered"
## mirrors autoload/match/MatchGifts.gd's pop_pending_special()
## own emit (Events.special_consumed, host-only) -- see _on_special_consumed()
## below.
const EVENT_SPECIAL_CONSUMED: StringName = &"special_consumed"
const EVENT_GLUE_CHARGES: StringName = &"glue_charges_changed"
## [net_id, glued] -- a placed block gained its first / lost its last glue bond.
const EVENT_BLOCK_GLUED: StringName = &"block_glued_changed"
const EVENT_BLOCK_OWNER_CHANGED: StringName = &"block_owner_changed"
const EVENT_BLOCK_FROZEN: StringName = &"block_frozen_changed"
const EVENT_CAT_STARTED: StringName = &"cat_started"
const EVENT_CAT_ENDED: StringName = &"cat_ended"
## [net_id] of a block the host started dissolving on a
## hole. Its removal follows through the ordinary net_block_despawned.
const EVENT_BLOCK_DISSOLVE_STARTED: StringName = &"block_dissolve_started"
## mid-match join replay only: one slot's absolute feed and
## gift state -- [slot_id, held_shape_id, next_shape_id, feed_seq, time_left,
## release_locked, held_special_id, next_special_id, after_next_special_id, after_next_carrier_id]. See
## _apply_slot_replay().
const EVENT_SLOT_REPLAY: StringName = &"slot_replay"
## EVENT_SLOT_REPLAY arity, and the indices of its id-typed args (after-next gift and carrier last).
const SLOT_REPLAY_AFTER_SPECIAL: int = 8
const SLOT_REPLAY_AFTER_CARRIER: int = SLOT_REPLAY_AFTER_SPECIAL + 1
const SLOT_REPLAY_ARGS: int = SLOT_REPLAY_AFTER_CARRIER + 1
const SLOT_REPLAY_ID_ARGS: Array[int] = [1, 2, 6, 7, SLOT_REPLAY_AFTER_SPECIAL, SLOT_REPLAY_AFTER_CARRIER]
## mid-match join replay only: [match_timer_left].
const EVENT_MATCH_CLOCK: StringName = &"match_clock"
## mid-match join replay only, COUNTDOWN: the loading-screen ready
## gate as the host sees it now -- [ready_peer_ids, required_peer_ids, open].
const EVENT_LOADING_GATE: StringName = &"loading_gate"
## the live scoreboard snapshot (MatchStats.build_live_payload()),
## sent at NetConfig.scoreboard_hz while the round is live; clients show it in the
## hold-to-show scoreboard (ui/hud/ScoreboardOverlay.gd). Display only.
const EVENT_LIVE_SCORES: StringName = &"live_scores"

@export var config: NetConfig = preload("res://config/net/net_config.tres"):
	set(value):
		config = value
		# The gateway and the replay collaborator read the flood limits from this resource.
		_intent_gateway = null
		_world_replay_host = null

## Clients build their replicated bodies with the same factory and the same
## tuning the host built the originals with, so a frozen copy has the same
## collision shape and mass even though it never simulates.
var _physics_tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
## Client-side block spawns/despawns and the seat roster (net/match/ClientBlockMirror.gd), built on first use.
var _block_mirror: ClientBlockMirror = null

## EVENT_SPECIAL_TRIGGERED's chain_depth wire bound
## (SpecialTuning.max_chain_depth). A separate preload rather than reading
## through _host_port() -- the config is architecture-fixed for the build,
## the same reason _physics_tuning above is preloaded rather than read from
## Match's own running MatchConfig.
var _special_tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")
## the fade length a client reports with a replicated
## dissolve start (same shipped resource the host's HoleDissolver reads).
var _hole_dissolve_tuning: HoleDissolveTuning = preload("res://config/blocks/tuning/hole_dissolve_tuning.tres")
## the same shipped resources PlayerController reads for the
## player's first-block hover, so the AFK auto-drop's no-cursor fallback origin
## clears the home beacon by the identical rule (_afk_fallback_origin()).
var _ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
var _beacon_visuals: BeaconVisualTuning = preload("res://config/territory/beacon_visual_tuning.tres")
## Every instrumentation counter (the per-slot intent identities and the match-start
## records); net/NetCounters.gd.
var counters: NetCounters = NetCounters.new()
## Replicated block impacts (net/match/ImpactReplicator.gd), built on first use and dropped on a
## reset or a provider change.
var _impacts: ImpactReplicator = null
var _impact_send_accum: float = 0.0

## _known_special_ids()'s cache: String(SpecialDef.id) -> true, built once
## from SpecialDef.load_all_specials() (a directory scan). This node is
## recreated per match/session (a fresh autoload on every process start; a
## fresh instance per test via MatchNetScript.new()), so "once per instance"
## already means "once per match" in the shipped build and "once per test"
## in a unit test -- no reset hook of its own is needed.
var _special_ids_by_id: Dictionary = {}
var _special_ids_cached: bool = false

## DECISION (net/MatchNet.gd): Net and Match are plain autoloads and GUT
## cannot double one (see game/player/PlayerController.gd's DECISION for the whole
## story), so the two collaborators this node cannot work without are reached
## through the three ports (bind_ports). Unbound, the ports are built over the autoloads on first
## use, which is what every shipped build uses; tests bind ports over doubles.

## True while the session port is the real Net autoload (the snapshot stream only exists there).
var _session_is_autoload: bool = true

## slot_id -> {"origin": Vector3, "orientation_index": int,
## "free_quat": Quaternion, "time": float}. On the host this is what spec
## 2.5's auto-drop [ORIGINAL] fires from; on every instance it is what
## game/player/RemoteCursors.gd draws.
var _cursors: Dictionary = {}

## The intent door (net/match/MatchIntentGateway.gd): local submit_*, host handle_* with the
## per-peer flood gate. Built on first use so bind_ports() can rebind it.
var _intent_gateway: MatchIntentGateway = null
## The gateway, built on first read (a typed receiver, so the call graph resolves it).
var _gateway: MatchIntentGateway:
	get:
		return _intents()

var _raster_send_accum: float = 0.0
## Territory raster, shares, capture ring and circles (net/match/TerritoryReplicator.gd); holds
## the diff baseline and the capture cache, so it is rebuilt (not reset) at a match boundary.
var _territory: TerritoryReplicator = null

## True once replicate_match_start() has gone out for the running match, so a
## lobby that calls it explicitly and the automatic send below cannot both
## fire.
var _match_start_sent: bool = false

## -- Mid-match join / reconnect replay -----------------------
## Host only: the join/replay/ack/timeout collaborator (net/match/MatchWorldReplay.gd), built on first use.
var _world_replay_host: MatchWorldReplay = null
var _world_replay: MatchWorldReplay:
	get:
		return _replays()
## Client only: true from the moment this instance becomes a CLIENT until the
## first net_match_start lands. Every host -> client gameplay RPC that arrives
## in that window was broadcast before this peer's replay was built, so the
## replay already contains its effect; applying it to a world that does not
## exist yet could only corrupt the mirror (a stray LOBBY -> PLAYING emit, a
## feed event for slots that are not built).
var _awaiting_match_start: bool = false
## Client only: the id of the late-join world replay being
## applied right now (0 = none). Set by the net_match_start that carries it,
## cleared by the matching net_replay_end -- or by anything that ends the replay
## early (a new match start, leaving the session, teardown, the ack timeout), so
## a replay that never completes cannot mute live feedback for the rest of a match.
var _replaying_id: int = 0
var _replaying_since_ms: int = 0

## the weather RPC surface (net/WeatherNet.gd), a child node.
var _weather_net: Node = null
## the client-side event applier child (net/MatchEventApplier.gd).
## net_match_event stays the RPC entry point; this child holds the apply bulk.
var _applier: Node = null
## The typed Match reads the mirror and the state handler make; rebuilt when the providers change.
var _host_port_cache: MatchHostPort = null
var _session_port_cache: SessionPort = null
var _replica_port_cache: MatchReplicaPort = null
## The host Events subscribers (net/match/MatchEventMirror.gd), built on first use.
var _mirror: MatchEventMirror = null
## true once late_activate() has built the WeatherNet child.
var _late_active: bool = false
var _cat_send_accum: float = 0.0
var _scores_send_accum: float = 0.0


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
	_territory_replicator()
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
	_weather_net.awaiting_world = _client_awaiting_world
	_event_applier()


## The event applier child; built on first use so a test that skips
## late_activate() still works. Not an RPC node, so no path is peer-visible.
func _event_applier() -> Node:
	if _applier == null:
		_applier = LateScripts.script(LateScripts.MATCH_EVENT_APPLIER).new() as Node
		_applier.name = "MatchEventApplier"
		_applier.set("_net", self)
		_applier.call(&"bind_replica", _replica_port())
		add_child(_applier)
	return _applier


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
			SessionPort.new(Net, _SESSION_PORT_METHODS),
			MatchHostPort.new(Match, _HOST_PORT_METHODS),
			MatchReplicaPort.new(Match, _REPLICA_PORT_METHODS)):
		_session_is_autoload = true


## Binds the three ports every path of this node and its collaborators share, drops the collaborators
## built on the old ones (the gateway, the world replay, the territory replicator) so they rebuild on
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
	if _territory != null:
		_territory = null
		_territory_replicator()
	if _mirror != null:
		_mirror.bind_ports(session, host)
	if _applier != null:
		_applier.call(&"bind_replica", replica)
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
	_end_world_replay()
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
		seams.store_cursor = _store_cursor
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
		seams.clear_cursor = func(slot_id: int) -> void: _cursors.erase(slot_id)
		seams.spawn_args = _spawn_args
		seams.glued_ids = func() -> Array: return _event_mirror().glued_ids()
		seams.territory_args = _territory_replay_args
		seams.slot_replay_args = _slot_replay_args
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
		_tick_world_replay_expiry()
		_play_due_impacts()
		return
	_world_replay.tick_timeouts(_now())
	_impact_send_accum += delta
	if _impact_send_accum >= 1.0 / maxf(config.impact_batch_hz, 0.001):
		_impact_send_accum = 0.0
		_send_impacts(Time.get_ticks_msec())
	var cat: RigidBody3D = _host_port().active_cat()
	if cat != null and NetFanout.can_send(multiplayer, _session_port()):
		_cat_send_accum += delta
		if _cat_send_accum >= 1.0 / maxf(config.cursor_hz, 0.001):
			_cat_send_accum = 0.0
			_broadcast(&"net_cat_state", [cat.activation_id, cat.global_position,
				cat.linear_velocity, cat.target, cat.time_left])
	if MatchPhase.is_live(_host_port().state()):
		_scores_send_accum += delta
		if _scores_send_accum >= 1.0 / maxf(config.scoreboard_hz, 0.001):
			_scores_send_accum = 0.0
			var stats: RefCounted = _host_port().stats()
			_event_mirror().on_live_scores(stats.call(&"build_live_payload") as Dictionary)
	_raster_send_accum += delta
	var step: float = 1.0 / maxf(config.raster_diff_hz, 0.001)
	if _raster_send_accum >= step:
		_raster_send_accum = 0.0
		replicate_territory()


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


## results screen "Play again": restarts the match that just
## ended with the same MatchConfig, for every peer. Mirrors submit_place()'s
## own single-door shape: **the host's own local call acts inline, with no
## sender check** (exactly submit_place()'s host branch calling
## apply_place() directly, never through handle_place()'s
## sender-owns-slot gate) -- a call arriving offline (local play, sandbox) would
## otherwise be refused, since the roster's peer map (slot_of_peer()'s backing
## store) is only ever populated by host_game()/join_game(), never in pure
## offline play. A **remote** request goes through the reliable RPC below,
## which _is_ validated (spec 2.6 "the host checks every intent before acting
## on it") -- a global restart/return affects every connected peer, so unlike
## a placement there is no per-sender outcome to report back, only "the host
## did it or it didn't".
##
## DECISION (net/MatchNet.gd): any seated slot (not only the
## host's own player) may request a replay/return over the wire -- spec 2.6
## does not name a narrower "only the host's own local player" rule the way
## it names "the host checks ... that the slot matches" for a placement, and
## the results screen's own Replay/Return buttons are a natural thing for any
## player to click. MatchIntentGateway's remote gate is what actually
## authorizes a remote sender: unseated (no slot) and mid-match (not
## State.END) requests are both dropped on the host's floor. The host's own
## local call skips only the sender-slot check -- it is validated on State.END exactly like
## a remote request, since a stray local call mid-match must not restart or
## abandon every other player's match either.
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
	var stored: Dictionary = _cursors.get(slot_id, {})
	if stored.is_empty():
		return {}
	return {
		"origin": stored["origin"],
		"orientation_index": stored["orientation_index"],
		"free_quat": stored["free_quat"],
		"age": _now() - float(stored["time"]),
	}


# --- Host -> clients: replication hooks Match calls -------------------------

## Host only. Announces a block the host just spawned, reliably, before any
## snapshot can reference it. Clients build a frozen copy and bind `net_id`.
##
## `net_id` may be -1 (BlockRegistry.debug_set_next_net_id /
## the allocator refusing past Quantize.NET_ID_MAX) when the body's own
## net_id allocation failed; that body lives and simulates on the host only,
## exactly as the allocator's own error says, so nothing goes out for it here
## either -- sending it anyway would build a permanent phantom client copy no
## despawn could ever address (bind_net_id() below also refuses it, but the
## body would already be parented under blocks_parent by then).
func replicate_spawn(block: BlockBody, net_id: int) -> void:
	if not _session_port().is_host() or block == null:
		return
	if not Quantize.is_wire_id(net_id):
		return
	if not NetFanout.can_send(multiplayer, _session_port()):
		return
	var args: Array = _spawn_args(block, net_id)
	_broadcast(&"net_block_spawned", args)


## net_block_spawned's argument list for `block`: the one wire shape both a
## live spawn and a mid-match join replay use. owner_slot is
## the block's *current* slot, so a Paintball conversion
## replays as the converted colour.
func _spawn_args(block: BlockBody, net_id: int) -> Array:
	var basis: Basis = block.global_transform.basis.orthonormalized()
	return [
		net_id,
		block.shape_id,
		block.owner_slot,
		block.global_position,
		basis.get_rotation_quaternion(),
		block.gift_id,
	]


func replicate_despawn(net_id: int, reason: String) -> void:
	if not _session_port().is_host() or net_id < 0:
		return
	if not NetFanout.can_send(multiplayer, _session_port()):
		return
	_broadcast(&"net_block_despawned", [net_id, reason])


## Host only, at NetConfig.raster_diff_hz. Sends TerritoryReplicator's packet: the changed raster
## cells (or a full keyframe), the team shares, the capture ring values and the analytic circle
## list, so the HUD costs no extra packet. Nothing goes out when nothing changed.
func replicate_territory() -> void:
	if not _session_port().is_host() or not NetFanout.can_send(multiplayer, _session_port()):
		return
	var territory: TerritoryReplicator = _territory_replicator()
	var packet: PackedByteArray = territory.encode_diff()
	if not packet.is_empty():
		_broadcast(&"net_territory", _territory_rpc_args(packet))


## Host only. Mirrors a match-flow event to every client: state changes, the
## countdown, feed issues, eliminations and the win. A per-player cue (a
## refusal, a relocation) is not one of these: it goes to its owning peer alone
## (_on_placement_rejected, _on_placement_relocated).
func replicate_match_event(event: StringName, args: Array) -> void:
	if not _session_port().is_host():
		return
	if not NetFanout.can_send(multiplayer, _session_port()):
		return
	_broadcast(&"net_match_event", [event, args])


## Host only. Ships the whole match start: the sanitized MatchConfig, the slot
## roster and the seed, so a client builds the identical world before the
## first snapshot. Idempotent for one match, so an explicit call from the
## lobby and the automatic one below cannot both go out.
func replicate_match_start(match_config: MatchConfig) -> void:
	if not _session_port().is_host() or match_config == null or _match_start_sent:
		return
	_match_start_sent = true
	var territory: TerritoryReplicator = _territory_replicator()
	territory.force_full()
	if not NetFanout.can_send(multiplayer, _session_port()):
		return
	_broadcast(&"net_match_start", [match_config.to_dict(), _roster(), 0])


## Host only. Tells every client the host just pressed Start,
## one reliable message ahead of net_match_start, so a client can raise its
## loading overlay and have it drawn before the synchronous world build that
## net_match_start triggers. Reliable RPCs are ordered, so it always lands first.
func replicate_match_loading() -> void:
	if not _session_port().is_host() or not NetFanout.can_send(multiplayer, _session_port()):
		return
	_broadcast(&"net_match_loading")


# --- Counters the acceptance harness asserts on -----------------------------

## Deliberate placement intents this instance sent (as a client, for its own
## slot) or received (as the host, for any slot, including its own local
## player's). Auto-drops are not intents and are counted separately, because
## they never cross the wire.
##
## The harness proves "placements are never duplicated or lost" with two
## identities: on the host, for every slot, intents_accepted + intents_refused
## == intents_sent and blocks_spawned == sum(intents_accepted) + sum
## (auto_drops); and across instances, a client's intents_sent for its own
## slot equals the host's.
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
	_cat_send_accum = 0.0
	if _intent_gateway != null:
		_intent_gateway.reset_throttles()
	_gift_wire_phases.clear()
	_gift_spawn_notified.clear()
	counters.reset()
	_cursors.clear()
	_territory = null
	_territory_replicator()
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


## Wire safety for EVENT_GIFT_SPAWNED, following MatchIntentGateway.pose_is_acceptable()'s
## own pattern: a malformed or out-of-disk position from a bad or ancient build
## is dropped rather than trusted, since a client only ever uses this position
## to place a visual and to compute the cell it later frees for.
## Records a gift's wire phase; refuses an out-of-range value (returns false).
func _set_gift_wire_phase(gift_id: int, phase: int) -> bool:
	if gift_id < 0 or not _WIRE_PHASE_OWNER.is_valid_wire_phase(phase):
		return false
	_gift_wire_phases[gift_id] = phase
	return true


func _gift_wire_ok(gift_id: int, position: Vector2) -> bool:
	if gift_id < 0:
		return false
	if not (is_finite(position.x) and is_finite(position.y)):
		return false
	var running: MatchConfig = _host_port().config()
	if running == null:
		return false
	var radius: float = running.map_def().field_radius
	return position.length() <= radius + 0.01


## Wire safety, reused by EVENT_SPECIAL_TRIGGERED's def_id
## as well as EVENT_GIFT_CLAIMED's third argument: the id is trusted only if
## it is shaped like one of ours -- non-empty, at most NetConfig.special_id_max_length
## characters, [A-Za-z0-9_] only (core/net/WireLimits.gd) -- following _gift_wire_ok's own "a malformed or ancient
## payload is dropped, not trusted" pattern. This is a syntactic check only;
## _gift_special_id_wire_ok() below layers real roster membership on top of it
## for EVENT_GIFT_CLAIMED specifically (a client only ever queues this id and,
## later, hands it to SpecialBehavior.bind(), so an unchecked string could
## otherwise reach either unfiltered) -- EVENT_SPECIAL_TRIGGERED does not need
## the same layer (see _known_special_ids()'s own doc comment for why). No
## RegEx dependency (none exists elsewhere in this codebase) -- a plain
## character scan is enough for an id this short.
func _special_id_wire_ok(special_id: String) -> bool:
	return WireLimits.special_id_ok(StringName(special_id), config)


## String(SpecialDef.id) -> true for every SpecialDef in SpecialDef.
## load_all_specials(), built once per instance and cached (see
## _special_ids_by_id's own field comment). Read by _gift_special_id_wire_ok()
## below; not by EVENT_SPECIAL_TRIGGERED's dispatch, which only re-checks
## _special_id_wire_ok()'s syntactic shape -- a special already bound and triggered on the host is by
## construction a real roster id, so nothing here needs to reject one a
## client's own (possibly stale) roster cache does not recognise.
func _known_special_ids() -> Dictionary:
	if not _special_ids_cached:
		_special_ids_by_id = {}
		# The typed Array[SpecialDef] result stays in an untyped Array (D8).
		var defs: Array = LateScripts.script(LateScripts.SPECIAL_DEF).call(&"load_all_specials")
		for def: Resource in defs:
			_special_ids_by_id[String(def.get(&"id"))] = true
		_special_ids_cached = true
	return _special_ids_by_id


## Tightening of _special_id_wire_ok() for EVENT_GIFT_CLAIMED only: a
## claimed special id is trusted only if it is shaped like one of ours AND is
## either MatchGifts.PENDING_SPECIAL_ID (the default drawer's placeholder,
## always valid regardless of roster -- see MatchPlacement._attach_pending_
## special()'s own "safe default" handling of it) or actually a member of the
## running roster. An empty res://config/gifts/specials/ therefore lets only
## the placeholder through: there is no real special for any other id to name.
func _gift_special_id_wire_ok(special_id: String) -> bool:
	if not _special_id_wire_ok(special_id):
		return false
	if special_id == String(SpecialIds.PENDING):
		return true
	return _known_special_ids().has(special_id)


func _store_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	if slot_id < 0:
		return
	_cursors[slot_id] = {
		"origin": origin,
		"orientation_index": orientation_index,
		"free_quat": free_quat,
		"time": _now(),
	}


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _client_blocks() -> ClientBlockMirror:
	if _block_mirror == null:
		_block_mirror = ClientBlockMirror.new(_session_port(), _host_port(), _gift_special_id_wire_ok, _physics_tuning)
	return _block_mirror


func _roster() -> Array:
	var roster: Array = []
	for peer_id: int in _session_port().peer_ids():
		roster.append(_session_port().peer_info(peer_id))
	return roster


# --- Events the host mirrors to its clients ---------------------------------

func _on_match_state_changed(from_state: int, to_state: int) -> void:
	# DECISION: impacts clear on LOBBY|LOADING only; END is excluded from
	# is_resetting so impacts already queued still play into the results screen.
	if MatchPhase.is_resetting(to_state) and to_state != MatchPhase.State.END:
		# World teardown / rebuild: nothing still waiting may play into it.
		_reset_impacts()
	if not _session_port().is_host():
		return
	if to_state == MatchPhase.State.LOADING:
		# The lobby may call replicate_match_start() itself; this is the
		# belt-and-braces path, and the flag makes the pair idempotent.
		_match_start_sent = false
		reset_counters()
		replicate_match_start(_host_port().config())
	elif to_state == MatchPhase.State.LOBBY:
		_match_start_sent = false
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
	var cursor: Dictionary = cursor_for_slot(slot_id)
	var origin: Vector3 = cursor["origin"] if cursor.has("origin") else _afk_fallback_origin(slot_id)
	var orientation_index: int = int(cursor.get("orientation_index", 0))
	var free_quat: Quaternion = cursor.get("free_quat", Quaternion.IDENTITY)
	_gateway.apply_place(slot_id, origin, orientation_index, free_quat, true, _host_port().feed_seq(slot_id))


## The origin the host auto-drops from for a slot it has never heard a cursor
## from, so the first block does not load inside the home beacon.
## Match.default_ghost_origin() is the home flag
## at disc level, which is inside the beacon's socket and crystal (the beacon is
## invisible to the placement ray and the spawn-clearance query), so the origin
## is raised until the unrotated block's lowest point clears the beacon top by
## GhostTuning.home_spawn_beacon_margin -- GhostTuning.home_spawn_pivot_height(),
## built on the same home_spawn_clear_hover() PlayerController raises the
## player's first block with. Only this no-cursor fallback is raised: a stored
## cursor is already a pose the peer's own ghost produced, and a client intent
## is never touched. Orientation 0 / identity (the fallback's) is what the
## pivot height assumes.
## DECISION: world UP, not field-local up, matching PlayerController's own
## hover and Match.default_ghost_origin()'s own world-space result. Tilt modes
## rotate the Field by at most a few degrees, which still leaves the block well
## clear of the beacon.
func _afk_fallback_origin(slot_id: int) -> Vector3:
	var host: MatchHostPort = _host_port()
	var home: Vector3 = host.default_ghost_origin(slot_id)
	return home + Vector3.UP * _ghost_tuning.home_spawn_pivot_height(_beacon_visuals, _physics_tuning)


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


# --- Replicated block impacts ------------------------------
#
# Host: Block._physics_process emits Events.block_impacted_at for a real
# landing (host physics only; frozen client replicas emit nothing). The host's
# own Sfx/camera/rumble/dust react to that emit directly, exactly as before;
# this node only queues a copy for clients. Clients re-emit both impact
# signals from the wire, so every consumer works unchanged (the host never
# receives its own call_remote batch, so nothing plays twice there).

## Host: one detected impact. Only collected while someone can hear it.
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	if not _session_port().is_host() or not _impact_audience():
		return
	var impacts: ImpactReplicator = _impact_replicator()
	impacts.collect(speed, position, Time.get_ticks_msec())


func _impact_audience() -> bool:
	return NetFanout.can_send(multiplayer, _session_port()) and not multiplayer.get_peers().is_empty()


## Host: sends the current impact window as one batch to every peer that has its world. A
## mid-match joiner still loading its replay hears nothing yet; impacts are never part of it.
func _send_impacts(now_ms: int) -> void:
	var impacts: ImpactReplicator = _impact_replicator()
	var packet: PackedByteArray = impacts.flush(now_ms)
	if packet.is_empty() or not NetFanout.can_send(multiplayer, _session_port()):
		return
	for peer_id: int in multiplayer.get_peers():
		if not _world_replay.is_pending(peer_id):
			NetFanout.send_to(self, _session_port(), peer_id, &"net_block_impacts", [packet])


## Client: plays every queued impact the interpolated view (SnapshotSync renders
## interpolation_delay_ms behind the host) has reached.
func _play_due_impacts() -> void:
	var view_ms: float = float(Time.get_ticks_msec())
	if SnapshotSync.is_running():
		view_ms -= SnapshotSync.interpolation_delay_ms()
	var impacts: ImpactReplicator = _impact_replicator()
	for row: Array in impacts.drain(view_ms):
		_emit_impact(float(row[0]), row[1] as Vector3)


## The same pair game/blocks/Block.gd emits on the host, so Sfx (thud), CameraRig
## (shake), Rumble, BlockEffectsManager (dust) and PerchingBirds need nothing
## network-aware.
func _emit_impact(speed: float, position: Vector3) -> void:
	Events.block_impacted.emit(speed)
	Events.block_impacted_at.emit(speed, position)


func _reset_impacts() -> void:
	_impacts = null
	_impact_send_accum = 0.0


func _impact_replicator() -> ImpactReplicator:
	if _impacts == null:
		_impacts = ImpactReplicator.new(config, TokenBucket.new())
	return _impacts


func _territory_replicator() -> TerritoryReplicator:
	if _territory == null:
		_territory = TerritoryReplicator.new(_host_port(), _replica_port(), config)
	return _territory


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


func _begin_world_replay(replay_id: int) -> void:
	_replaying_id = replay_id
	_replaying_since_ms = Time.get_ticks_msec()
	Events.world_replay_changed.emit(true)


## Idempotent; emits only on a real true -> false transition.
func _end_world_replay() -> void:
	if _replaying_id == 0:
		return
	_replaying_id = 0
	Events.world_replay_changed.emit(false)


## A replay's messages all land in one network poll, so one that has not
## finished by the host's own ack timeout never will (the host drops the peer at
## that point): stop muting.
func _tick_world_replay_expiry() -> void:
	if _replaying_id == 0:
		return
	var elapsed_s: float = float(Time.get_ticks_msec() - _replaying_since_ms) / 1000.0
	if elapsed_s >= config.replay_ack_timeout:
		_end_world_replay()


func _on_net_mode_changed(mode: int) -> void:
	_awaiting_match_start = mode == Net.Mode.CLIENT
	_end_world_replay()
	_reset_impacts()


## True while a match is past its start and not over: the states a mid-match
## joiner is admitted into and gets a replay for (spec 2.4).
func is_match_live() -> bool:
	var state: int = int(_host_port().state())
	return MatchPhase.is_replicating(state)


# --- Mid-match join and reconnect (spec 2.6) -----------------

## Host only, installed into Net's seat policy by game/main/Main.gd: the lowest open
## human seat for a new mid-match joiner, or -1 (spectate). Open means a human
## (not bot) slot that is still alive, held by no peer, and not reserved by a
## departed peer inside its disconnect grace.
##
## DECISION: a joiner never takes over a bot seat -- the bot
## would have to be torn down mid-match and spec 1.8 does not ask for it;
## with every human seat filled or reserved the joiner spectates.
func pick_open_seat() -> int:
	if not _session_port().is_host() or not is_match_live():
		return -1
	var authority: MatchHostPort = _host_port()
	for slot_id: int in range(int(authority.slot_count())):
		var seat: PlayerSlot = authority.slot(slot_id)
		if seat == null or seat.is_bot or not seat.home_flag_alive:
			continue
		if int(_session_port().peer_of_slot(slot_id)) != -1:
			continue
		if float(authority.disconnect_grace_left(slot_id)) >= 0.0:
			continue
		return slot_id
	return -1


## Host only, installed into Net's seat policy by game/main/Main.gd: whether a
## returning peer may have `slot_id` back -- the match is live, the slot is
## alive and its disconnect grace is still running.
func seat_reclaimable(slot_id: int) -> bool:
	if not _session_port().is_host() or not is_match_live():
		return false
	var authority: MatchHostPort = _host_port()
	if slot_id < 0 or slot_id >= int(authority.slot_count()):
		return false
	var seat: PlayerSlot = authority.slot(slot_id)
	if seat == null or not seat.home_flag_alive:
		return false
	return float(authority.disconnect_grace_left(slot_id)) >= 0.0


## net_territory's arguments for one full keyframe, or [] with no raster.
func _territory_replay_args() -> Array:
	var territory: TerritoryReplicator = _territory_replicator()
	var packet: PackedByteArray = territory.encode_full()
	return [] if packet.is_empty() else _territory_rpc_args(packet)


## net_territory's arguments: the packet, then neutral values for the slots the packet now carries.
func _territory_rpc_args(packet: PackedByteArray) -> Array:
	return [packet, false, PackedFloat32Array(), -1, 0.0]


## EVENT_SLOT_REPLAY's payload for `slot_id`, or [] for a slot with nothing
## held (eliminated, or between blocks).
func _slot_replay_args(slot_id: int) -> Array:
	var authority: MatchHostPort = _host_port()
	var held: BlockShape = authority.held_shape(slot_id)
	if held == null:
		return []
	var next: BlockShape = authority.next_shape(slot_id)
	return [
		slot_id,
		held.id,
		next.id if next != null else &"",
		int(authority.feed_seq(slot_id)),
		float(authority.feed_time_left(slot_id)),
		bool(authority.is_release_locked(slot_id)),
		StringName(authority.held_special(slot_id)),
		StringName(authority.next_special(slot_id)),
		StringName(authority.after_next_special(slot_id)),
		_host_port().feed_staged_gift_shape_id(slot_id),
	]


## Client side of EVENT_SLOT_REPLAY. The wire is validated in full before any
## of it is applied (the same "drop, never default" rule as every other
## dispatch case): a malformed slot replay changes nothing.
##
## Gifts are rebuilt through the same client mirror calls a live claim uses,
## in the order a seated client would have seen them: the held gift is queued
## and marked as the next carrier, the feed event activates it, then the
## queued next gift is queued behind it.
func _apply_slot_replay(args: Array) -> void:
	if args.size() != SLOT_REPLAY_ARGS or not args[0] is int or not args[3] is int or not args[5] is bool:
		return
	for index: int in SLOT_REPLAY_ID_ARGS:
		if not (args[index] is StringName or args[index] is String):
			return
	if not (args[4] is float or args[4] is int):
		return
	var slot_id: int = args[0]
	var held_id: StringName = StringName(args[1])
	var next_id: StringName = StringName(args[2])
	var feed_seq: int = args[3]
	var time_left: float = float(args[4])
	var locked: bool = args[5]
	var held_special: StringName = StringName(args[6])
	var next_special: StringName = StringName(args[7])
	var after_special: StringName = StringName(args[SLOT_REPLAY_AFTER_SPECIAL])
	var after_carrier: StringName = StringName(args[SLOT_REPLAY_AFTER_CARRIER])
	var host: MatchHostPort = _host_port()
	var replica: MatchReplicaPort = _replica_port()
	if host.config() == null or slot_id < 0 or slot_id >= host.slot_count():
		return
	if feed_seq < 0 or not is_finite(time_left) or time_left < 0.0 or time_left > MatchConfig.BLOCK_TIMER_MAX:
		return
	if not host.feed_knows_shape(held_id):
		return
	if next_id != &"" and not host.feed_knows_shape(next_id):
		return
	if held_special != &"" and not _gift_special_id_wire_ok(String(held_special)):
		return
	if next_special != &"" and (next_id == &"" or not _gift_special_id_wire_ok(String(next_special))):
		return
	if after_special != &"" and (not _gift_special_id_wire_ok(String(after_special)) or not host.feed_knows_shape(after_carrier)):
		return
	if held_special != &"":
		replica.apply_replicated_gift_claimed(-1, slot_id, held_special)
		replica.apply_replicated_next_gift(slot_id, held_id)
	replica.apply_replicated_feed(slot_id, held_id, next_id, feed_seq, time_left, locked)
	if next_special != &"":
		replica.apply_replicated_gift_claimed(-1, slot_id, next_special)
		replica.apply_replicated_next_gift(slot_id, next_id)
	if after_special != &"":
		replica.apply_replicated_gift_claimed(-1, slot_id, after_special)
		replica.apply_replicated_staged_gift(slot_id, after_carrier)
	Events.feed_block_issued.emit(slot_id, held_id, next_id)


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
	var impacts: ImpactReplicator = _impact_replicator()
	if impacts.receive(packet, Time.get_ticks_msec()):
		_play_due_impacts()


@rpc("authority", "call_remote", "reliable")
func net_match_loading() -> void:
	Events.match_loading_announced.emit()


## `replay_id` is 0 for the broadcast every client gets at match start, and the
## replay's own id (> 0) when this is the first message of a late-join /
## reconnect world replay (see MatchWorldReplay). The replay span is silent for
## one-shot feedback: see Events.world_replay_changed.
@rpc("authority", "call_remote", "reliable")
func net_match_start(config_data: Dictionary, roster: Array, replay_id: int = 0) -> void:
	_awaiting_match_start = false
	var match_config: MatchConfig = MatchConfig.from_dict(config_data)
	match_config.sanitize()
	reset_counters()
	# Before start_match(): its own state events belong to the replay too.
	_end_world_replay()
	if replay_id > 0 and not _session_port().is_host():
		_begin_world_replay(replay_id)
	_host_port().start_match(match_config)
	_client_blocks().apply_roster(roster)


## the client half of the replay handshake. Lands after every
## replay message (reliable, ordered), so the world is built by now.
@rpc("authority", "call_remote", "reliable")
func net_replay_end(replay_id: int) -> void:
	if _session_port().is_host() or _client_awaiting_world() or replay_id <= 0:
		return
	# The replay's last message: live events from here on are news again.
	if replay_id == _replaying_id:
		_end_world_replay()
	if NetFanout.can_send(multiplayer, _session_port()):
		rpc_id(Net.HOST_PEER_ID, &"net_replay_ack", replay_id)


@rpc("any_peer", "call_remote", "reliable")
func net_replay_ack(replay_id: int) -> void:
	_world_replay.handle_replay_ack(multiplayer.get_remote_sender_id(), replay_id)


## True on a client that has not received net_match_start since it joined
## (see _awaiting_match_start).
func _client_awaiting_world() -> bool:
	return _awaiting_match_start and not _session_port().is_host()


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
	var territory: TerritoryReplicator = _territory_replicator()
	territory.apply(payload)


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	if _client_awaiting_world() or bool(_session_port().is_local_slot(slot_id)):
		return
	_store_cursor(slot_id, origin, orientation_index, free_quat)
	Events.remote_cursor_updated.emit(slot_id, origin, orientation_index, free_quat)
