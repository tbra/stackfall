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

## Territory payload layout (see _encode_raster / _decode_raster), bumped
## whenever it changes. Like SnapshotSync.PACKET_VERSION this is architecture,
## not a tunable, so it is a const rather than a NetConfig field.
const RASTER_VERSION: int = 1
## version u8, flags u8, uncompressed byte count u32.
const RASTER_HEADER_BYTES: int = 6
const RASTER_FLAG_COMPRESSED: int = 1 << 0
## One diff entry: cell index u32, slot byte, state byte.
const RASTER_ENTRY_BYTES: int = 6

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
## release_locked, held_special_id, next_special_id]. See
## _apply_slot_replay().
const EVENT_SLOT_REPLAY: StringName = &"slot_replay"
## EVENT_SLOT_REPLAY arity: 8 args before the current payload adds the
## after-next gift id and its carrier shape id. Indices of the id-typed args for each.
const SLOT_REPLAY_ARGS_BASE: int = 8
const SLOT_REPLAY_ARGS: int = SLOT_REPLAY_ARGS_BASE + 2
const SLOT_REPLAY_ID_ARGS_BASE: Array[int] = [1, 2, 6, 7]
const SLOT_REPLAY_ID_ARGS: Array[int] = [1, 2, 6, 7, 8, 9]
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
## Lazily built id -> BlockShape index; BlockShape.load_all_shapes() scans a
## directory, so it happens once and only where a spawn needs it.
var _shapes_by_id: Dictionary = {}

## EVENT_SPECIAL_TRIGGERED's chain_depth wire bound
## (SpecialTuning.max_chain_depth). A separate preload rather than reading
## through _authority() -- the config is architecture-fixed for the build,
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
## Every instrumentation counter (intent identities, replay and impact tallies, the test-only
## "what would have gone on the wire" records); net/NetCounters.gd. The old public/private
## names below are TRANSITIONAL read forwarders for tests outside this file.
var counters: NetCounters = NetCounters.new()
## Test seam (net/MatchNetTap.gd): null in every shipped build. A test installs one to force the
## deferred activation path and to capture impact batches and replay messages.
var tap: MatchNetTap = null
## TRANSITIONAL: net_ids _on_block_dissolve_started() decided to replicate (NetCounters).
var replicated_dissolve_starts: Array[int]:
	get:
		return counters.replicated_dissolve_starts
## Host: net ids of blocks currently fused into a FusedBody.
var _fused_ids: Dictionary = {}
## net ids of charged glue drops coated at spawn (cleared when their
## last bond ends, as that is when the coat is removed).
var _glue_charged_ids: Dictionary = {}
## TRANSITIONAL read forwarders (NetCounters): how many times each event name reached
## replicate_match_event() on the host, and the refusal / relocation replies addressed to a peer.
var replicated_event_counts: Dictionary:
	get:
		return counters.replicated_event_counts
var reject_replies_by_peer: Dictionary:
	get:
		return counters.reject_replies_by_peer
var last_reject_reply: Array:
	get:
		return counters.last_reject_reply
var relocate_replies_by_peer: Dictionary:
	get:
		return counters.relocate_replies_by_peer
var last_relocate_reply: Array:
	get:
		return counters.last_relocate_reply

## replicated block impacts (core/net/ImpactWire.gd).
## Host: coalesce bucket (ImpactWire.coalesce_key) -> strongest event this
## batch window, as {speed, position, time_ms}. Cleared on every flush, so it
## never holds more than one window and is never replayed to a late joiner.
var _impact_pending: Dictionary = {}
var _impact_send_accum: float = 0.0
## Token bucket behind NetConfig.impact_max_per_second; starts full.
var _impact_tokens: float = -1.0
var _impact_refill_ms: int = -1
## Client: [due_ms, speed, position] rows waiting for the interpolated view to
## reach the moment they happened (receive_impacts()).
var _impact_queue: Array[Array] = []
## Test-only: >= 0 replaces SnapshotSync's interpolation delay as the client's
## impact playback delay.
var impact_delay_override_ms: float = -1.0
## The "per second" of impact_client_max_per_second, in milliseconds.
const IMPACT_RATE_WINDOW_MS: int = 1000
## Client: Time.get_ticks_msec() of each event played within the last second,
## the sliding window behind NetConfig.impact_client_max_per_second.
var _impact_accept_ms: Array[int] = []

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
## through seams. null means "the real autoload", which is what every shipped
## build uses; tests inject doubles with set_providers().
var _net_provider: Variant = null
var _match_provider: Variant = null

## slot_id -> {"origin": Vector3, "orientation_index": int,
## "free_quat": Quaternion, "time": float}. On the host this is what spec
## 2.5's auto-drop [ORIGINAL] fires from; on every instance it is what
## game/player/RemoteCursors.gd draws.
var _cursors: Dictionary = {}

## TRANSITIONAL read forwarders (NetCounters): the per-slot identities the ENet harnesses and
## MatchFingerprint read by private name. The public intents_*() accessors below stay.
var _intents_sent: Dictionary:
	get:
		return counters.sent
var _intents_accepted: Dictionary:
	get:
		return counters.accepted
var _intents_refused: Dictionary:
	get:
		return counters.refused
## The intent door (net/match/MatchIntentGateway.gd): local submit_*, host handle_* with the
## per-peer flood gate. Built on first use so set_providers() can rebind it.
var _intent_gateway: MatchIntentGateway = null
## The gateway, built on first read (a typed receiver, so the call graph resolves it).
var _gateway: MatchIntentGateway:
	get:
		return _intents()

var _raster_send_accum: float = 0.0

## The last slot/state bytes the host sent, to diff this tick's against.
var _last_owner_bytes: PackedByteArray = PackedByteArray()
var _last_state_bytes: PackedByteArray = PackedByteArray()
## Forces the next territory packet to be a full keyframe: set at match start
## and whenever a peer joins, since a fresh client has nothing to diff against.
var _force_full_raster: bool = true

## Cached from Events.goal_capture_progress so the territory packet can carry
## the HUD's numbers without a second RPC.
var _capture_team: int = -1
var _capture_progress: float = 0.0
## The capture values the last territory packet carried, and whether the last
## one was a falling value.
var _sent_capture_team: int = -1
var _sent_capture_progress: float = 0.0
var _capture_fading: bool = false

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
## true once late_activate() has built the WeatherNet child.
var _late_active: bool = false
var _cat_send_accum: float = 0.0
var _scores_send_accum: float = 0.0


func _ready() -> void:
	_authority().set_replicator(self)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.countdown_tick.connect(_on_countdown_tick)
	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)
	Events.qol_feed_changed.connect(_on_qol_feed_changed)
	Events.gift_slot_changed.connect(_on_gift_slot_changed)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.match_won.connect(_on_match_won)
	Events.mode_state_changed.connect(_on_mode_state_changed)
	Events.match_results_ready.connect(_on_match_results_ready)
	Events.gift_flight_spawned.connect(_on_gift_flight)
	Events.gift_landed.connect(_on_gift_landed)
	Events.gift_spawned.connect(_on_gift_spawned)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.gift_expired.connect(_on_gift_expired)
	Events.special_triggered.connect(_on_special_triggered)
	Events.special_consumed.connect(_on_special_consumed)
	Events.glue_charges_changed.connect(_on_glue_charges_changed)
	Events.blocks_fused.connect(_on_blocks_fused)
	Events.fused_member_released.connect(_on_fused_member_released)
	Events.glue_drop_charged.connect(_on_glue_drop_charged)
	Events.block_owner_changed.connect(_on_block_owner_changed)
	Events.block_frozen_changed.connect(_on_block_frozen_changed)
	Events.cat_started.connect(_on_cat_started)
	Events.cat_ended.connect(_on_cat_ended)
	Events.block_removed.connect(_on_block_removed)
	Events.block_dissolve_started.connect(_on_block_dissolve_started)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.block_impacted_at.connect(_on_block_impacted_at)
	Events.net_peer_left.connect(_on_net_peer_left)
	Events.net_peer_joined.connect(_on_net_peer_joined)
	Events.net_mode_changed.connect(_on_net_mode_changed)
	multiplayer.peer_disconnected.connect(_forget_peer)
	# the WeatherNet child is built by late_activate(); headless
	# and non-Boot runs activate right here, a windowed Boot run lets Boot prewarm first.
	if LateScripts.boot_defers_activation(get_tree()) or (tap != null and tap.defer_activation):
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
	_weather_net.set_providers(_net_provider, _match_provider)
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
		add_child(_applier)
	return _applier


func _block_factory() -> GDScript:
	return LateScripts.script(LateScripts.BLOCK_FACTORY)


func _set_block_coated(block: BlockBody, coated: bool) -> void:
	LateScripts.script(LateScripts.HONEY_COAT).call(&"set_coated", block, coated)


func _exit_tree() -> void:
	_end_world_replay()
	var authority: Variant = _authority()
	if authority != null and authority.get("_replicator") == self:
		authority.set_replicator(null)


## Test seam; see _net_provider. Either argument may be null to keep the real
## autoload.
func set_providers(net_provider: Variant, match_provider: Variant) -> void:
	_net_provider = net_provider
	_match_provider = match_provider
	_intent_gateway = null
	_world_replay_host = null
	if _weather_net != null:
		_weather_net.set_providers(net_provider, match_provider)
	if _match_provider != null:
		_match_provider.set_replicator(self)


func _session() -> Variant:
	return _net_provider if _net_provider != null else Net


func _authority() -> Variant:
	return _match_provider if _match_provider != null else Match


## The intent gateway, bound to the current session and Match providers. The seams are the only
## transport it sees; the sender id of an RPC is read by the stubs below, never by the gateway.
func _intents() -> MatchIntentGateway:
	if _intent_gateway == null:
		var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
		seams.can_send = func() -> bool: return NetFanout.can_send(multiplayer, _session())
		seams.send_to_host = func(method: StringName, args: Array) -> void: callv(&"rpc_id", [Net.HOST_PEER_ID, method] + args)
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			return NetFanout.send_to(self, _session(), peer_id, method, args)
		seams.broadcast = func(method: StringName, args: Array) -> void: _broadcast(method, args)
		seams.now_s = _now
		seams.is_replay_pending = _world_replay.is_pending
		seams.store_cursor = _store_cursor
		_intent_gateway = MatchIntentGateway.new(_session(), _authority(), config, counters, seams)
	return _intent_gateway


## The world replay collaborator, bound to the current session and Match providers. Its pending
## state survives only until a provider or config change rebuilds it.
func _replays() -> MatchWorldReplay:
	if _world_replay_host == null:
		var seams: MatchWorldReplay.Seams = MatchWorldReplay.Seams.new()
		seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
			return NetFanout.send_to(self, _session(), peer_id, method, args)
		seams.now_s = _now
		seams.clear_cursor = func(slot_id: int) -> void: _cursors.erase(slot_id)
		seams.spawn_args = _spawn_args
		seams.glued_ids = _glued_ids
		seams.territory_args = _territory_replay_args
		seams.slot_replay_args = _slot_replay_args
		seams.replay_acknowledged = _on_replay_acknowledged
		_world_replay_host = MatchWorldReplay.new(_session(), _authority(), config, seams)
	return _world_replay_host


## Net ids of blocks fused into a FusedBody or coated by a glue drop, ascending.
func _glued_ids() -> Array:
	var ids: Array = _fused_ids.keys()
	for charged_id: int in _glue_charged_ids:
		if not ids.has(charged_id):
			ids.append(charged_id)
	ids.sort()
	return ids


## Spec 2.6's snapshots resume: the next one carries every body, so the joiner's interpolator
## starts from fresh samples for sleepers too.
func _on_replay_acknowledged() -> void:
	if _net_provider == null:
		SnapshotSync.request_full_snapshot()


## every host -> clients broadcast goes through here, so a peer the
## host is kicking (still listed by the transport until its disconnect completes)
## is never addressed. See net/NetFanout.gd.
func _broadcast(method: StringName, args: Array = []) -> void:
	NetFanout.broadcast(self, _session(), method, args)


func _process(delta: float) -> void:
	if not _session().is_host():
		_tick_world_replay_expiry()
		if not _impact_queue.is_empty():
			drain_impacts(Time.get_ticks_msec())
		return
	_world_replay.tick_timeouts(_now())
	if not _impact_pending.is_empty():
		_impact_send_accum += delta
		if _impact_send_accum >= 1.0 / maxf(config.impact_batch_hz, 0.001):
			_impact_send_accum = 0.0
			flush_impacts(Time.get_ticks_msec())
	var cat: RigidBody3D = _authority().active_cat()
	if cat != null and NetFanout.can_send(multiplayer, _session()):
		_cat_send_accum += delta
		if _cat_send_accum >= 1.0 / maxf(config.cursor_hz, 0.001):
			_cat_send_accum = 0.0
			_broadcast(&"net_cat_state", [cat.activation_id, cat.global_position,
				cat.linear_velocity, cat.target, cat.time_left])
	if MatchPhase.is_live(_authority().state()):
		_scores_send_accum += delta
		if _scores_send_accum >= 1.0 / maxf(config.scoreboard_hz, 0.001):
			_scores_send_accum = 0.0
			replicate_match_event(EVENT_LIVE_SCORES, [_authority().stats().build_live_payload()])
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
## sender-owns-slot gate) -- a call arriving offline (hot-seat, sandbox) would
## otherwise be refused, since Net's `_peers` map (slot_of_peer()'s backing
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


## TRANSITIONAL: host side of net_request_replay (MatchIntentGateway), kept under
## its old private name for tests outside this file.
func _handle_replay_request(sender_peer_id: int) -> void:
	_gateway.handle_replay_request(sender_peer_id)


@rpc("any_peer", "call_remote", "reliable")
func net_request_replay() -> void:
	_handle_replay_request(multiplayer.get_remote_sender_id())


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
	if not _session().is_host() or block == null:
		return
	if not Quantize.is_wire_id(net_id):
		return
	if not NetFanout.can_send(multiplayer, _session()):
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
	if not _session().is_host() or net_id < 0:
		return
	if not NetFanout.can_send(multiplayer, _session()):
		return
	_broadcast(&"net_block_despawned", [net_id, reason])


## Host only, at NetConfig.raster_diff_hz. Sends the cells whose slot or
## state byte changed since the last diff, or a full compressed raster when
## more than NetConfig.raster_full_threshold_fraction of them changed or a
## client has just joined. Territory shares and capture progress ride along so
## the HUD costs no extra packet.
##
## the analytic circle list rides along too, one
## core/net/CircleWire.gd payload per packet — always the *current* full
## list, never diffed like the raster, because it is already small (≤ 400
## circles, ~2.8 KB) and a circle that vanished (a tower toppled) has no
## "unchanged" cell to skip the way a raster byte does.
# DECISION: a decaying home claim changes no raster cell, so
# territory packets (raster-change only) would freeze the client ring. Rather
# than a new RPC or a replicated decay flag, the existing raster_diff_hz tick
# sends an empty diff carrying the capture values while a previously-sent claim
# is falling, changed team, or (once falling) moving at all -- until it clears
# (0 / no team). That bounds extra traffic to raster_diff_hz, adds no knob, and
# a late joiner already gets the current value in the replay's full packet.
# Rising holds on a static board are unchanged (client extrapolates).
func _capture_update_due() -> bool:
	if _sent_capture_progress <= 0.0:
		return false
	if _capture_team != _sent_capture_team:
		return true
	if is_equal_approx(_capture_progress, _sent_capture_progress):
		return false
	return _capture_progress < _sent_capture_progress or _capture_fading


func _note_capture_sent() -> void:
	_capture_fading = (
		_capture_team == _sent_capture_team and _capture_progress < _sent_capture_progress
	)
	_sent_capture_team = _capture_team
	_sent_capture_progress = _capture_progress


func replicate_territory() -> void:
	if not _session().is_host() or not NetFanout.can_send(multiplayer, _session()):
		return
	var raster: TerritoryRaster = _authority().raster()
	if raster == null:
		return
	var raw_owners: PackedByteArray = raster.owner_bytes()
	var raw_states: PackedByteArray = raster.state_bytes()
	# unchanged bytes are exactly the changed.size() == 0
	# return below, reached without the per-cell loop or the copies.
	if (
		not _force_full_raster
		and raw_owners.size() == _last_owner_bytes.size()
		and raw_owners == _last_owner_bytes
		and raw_states == _last_state_bytes
		and not _capture_update_due()
	):
		return
	var owners: PackedByteArray = raw_owners.duplicate()
	var states: PackedByteArray = raw_states.duplicate()
	var count: int = owners.size()
	if count == 0:
		return

	var changed: PackedInt32Array = PackedInt32Array()
	var full: bool = _force_full_raster or _last_owner_bytes.size() != count
	if not full:
		for index: int in range(count):
			if owners[index] != _last_owner_bytes[index] or states[index] != _last_state_bytes[index]:
				changed.append(index)
		if changed.size() == 0 and not _capture_update_due():
			return
		full = float(changed.size()) / float(count) > config.raster_full_threshold_fraction

	var payload: PackedByteArray = (
		_encode_raster_full(owners, states) if full else _encode_raster_diff(changed, owners, states)
	)
	_last_owner_bytes = owners
	_last_state_bytes = states
	_force_full_raster = false
	_note_capture_sent()

	_broadcast(&"net_territory", [
		payload,
		full,
		_team_shares(),
		_capture_team,
		_capture_progress,
		_encode_circles(),
	])


## The host's last-built circle list (autoload/Match.gd's
## _update_circle_render()), packed with the map's own quantization bounds so
## a client's decode uses the identical numbers the host encoded with.
func _encode_circles() -> PackedByteArray:
	var arrays: Dictionary = _authority().circle_render_arrays()
	return CircleWire.encode(
		arrays["xs"],
		arrays["zs"],
		arrays["radii"],
		arrays["teams"],
		arrays["goal_positions"],
		arrays["goal_radii"],
		bool(arrays["argmax_mode"]),
		_authority().circle_wire_xz_bound(),
		_authority().circle_wire_radius_max()
	)


## Host only. Mirrors a match-flow event to every client: state changes, the
## countdown, feed issues, eliminations and the win. A per-player cue (a
## refusal, a relocation) is not one of these: it goes to its owning peer alone
## (_on_placement_rejected, _on_placement_relocated).
func replicate_match_event(event: StringName, args: Array) -> void:
	if not _session().is_host():
		return
	counters.count_event(event)
	if not NetFanout.can_send(multiplayer, _session()):
		return
	_broadcast(&"net_match_event", [event, args])


## Host only. Ships the whole match start: the sanitized MatchConfig, the slot
## roster and the seed, so a client builds the identical world before the
## first snapshot. Idempotent for one match, so an explicit call from the
## lobby and the automatic one below cannot both go out.
func replicate_match_start(match_config: MatchConfig) -> void:
	if not _session().is_host() or match_config == null or _match_start_sent:
		return
	_match_start_sent = true
	counters.match_starts_replicated += 1
	_force_full_raster = true
	if not NetFanout.can_send(multiplayer, _session()):
		return
	_broadcast(&"net_match_start", [match_config.to_dict(), _roster(), 0])


## Host only. Tells every client the host just pressed Start,
## one reliable message ahead of net_match_start, so a client can raise its
## loading overlay and have it drawn before the synchronous world build that
## net_match_start triggers. Reliable RPCs are ordered, so it always lands first.
func replicate_match_loading() -> void:
	if not _session().is_host() or not NetFanout.can_send(multiplayer, _session()):
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
	_last_owner_bytes = PackedByteArray()
	_last_state_bytes = PackedByteArray()
	_force_full_raster = true
	_capture_team = -1
	_capture_progress = 0.0
	_sent_capture_team = -1
	_sent_capture_progress = 0.0
	_capture_fading = false
	# a (re)start is itself a full sync for every peer (the
	# broadcast net_match_start), so no replay is still owed an ack.
	_world_replay.reset()
	_fused_ids.clear()
	_glue_charged_ids.clear()


# --- Host-side intent handling ----------------------------------------------

## TRANSITIONAL: the one place an intent becomes a placement (MatchIntentGateway.apply_place);
## the host's feed-timer auto-drop still enters here.
func _apply_intent(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> StringName:
	return _gateway.apply_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)


## the use_gift_slot intent, host or client. The client only
## sends the request; the host validates it (sender owns the slot, slot holds a
## gift, state, no gift already in hand) and the result arrives as the normal
## feed event. Returns whether the request was applied (host) or sent (client).
func submit_use_gift_slot(slot_id: int) -> bool:
	return _gateway.submit_use_gift_slot(slot_id)


## TRANSITIONAL (MatchIntentGateway): host side of net_request_place, under its
## old private name for tests outside this file.
func _handle_place_intent(
	sender_peer_id: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	feed_seq: int
) -> void:
	_gateway.handle_place(sender_peer_id, slot_id, origin, orientation_index, free_quat, feed_seq)


## TRANSITIONAL (MatchIntentGateway): host side of net_request_throw.
func _handle_throw_intent(
	sender_peer_id: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> void:
	_gateway.handle_throw(sender_peer_id, slot_id, origin, orientation_index, free_quat, velocity, feed_seq)


## TRANSITIONAL (MatchIntentGateway): host side of net_update_cursor.
func _handle_cursor_update(
	sender_peer_id: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	aim: Vector3 = Vector3.ZERO
) -> void:
	_gateway.handle_cursor(sender_peer_id, slot_id, origin, orientation_index, free_quat, aim)


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
	var running: MatchConfig = _authority().config
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


## TRANSITIONAL (MatchIntentGateway.reject_to_peer): the placement_rejected reply
## to one peer, under its old private name for tests outside this file.
func _reject_to_peer(peer_id: int, slot_id: int, reason: StringName) -> void:
	_gateway.reject_to_peer(peer_id, slot_id, reason)


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


func _shape_for_id(shape_id: StringName) -> BlockShape:
	if _shapes_by_id.is_empty():
		for shape: BlockShape in BlockShape.load_all_shapes():
			_shapes_by_id[shape.id] = shape
	return _shapes_by_id.get(shape_id) as BlockShape


func _team_shares() -> PackedFloat32Array:
	var shares: PackedFloat32Array = PackedFloat32Array()
	var match_config: MatchConfig = _authority().config
	if match_config == null:
		return shares
	for team: int in range(match_config.team_count()):
		shares.append(_authority().territory_share(team))
	return shares


func _roster() -> Array:
	var roster: Array = []
	for peer_id: int in _session().peer_ids():
		roster.append(_session().peer_info(peer_id))
	return roster


# --- Events the host mirrors to its clients ---------------------------------

func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	# DECISION: impacts clear on LOBBY|LOADING only; END is excluded from
	# is_resetting so impacts already queued still play into the results screen.
	if MatchPhase.is_resetting(to_state) and to_state != MatchPhase.State.END:
		# World teardown / rebuild: nothing still waiting may play into it.
		_reset_impacts()
	if not _session().is_host():
		return
	if to_state == MatchPhase.State.LOADING:
		# The lobby may call replicate_match_start() itself; this is the
		# belt-and-braces path, and the flag makes the pair idempotent.
		_match_start_sent = false
		reset_counters()
		replicate_match_start(_authority().config)
	elif to_state == MatchPhase.State.LOBBY:
		_match_start_sent = false
	# the LOBBY/LOADING/COUNTDOWN start_match() produces
	# internally (see MatchLifecycle._starting's own doc) is fully replayed on
	# a client by net_match_start alone; replicating them again here would
	# race that local replay and turn into spurious re-emits on the other
	# side. Every OTHER state change -- reached outside a start_match() call,
	# such as PLAYING->END from a win -- still replicates normally.
	#
	# DECISION (net/MatchNet.gd): reaches _authority()'s own
	# _lifecycle directly rather than through a new Match.is_starting_match()
	# forward -- autoload/Match.gd is not one of this package's owned files.
	# _authority() is always either the real Match (which always has a
	# _lifecycle by the time any match flow can run, built in Match._ready())
	# or a test double; nothing in the current test suite ever hands MatchNet
	# a _match_provider without one.
	if _authority()._lifecycle.is_starting_match():
		return
	counters.replicated_state_changes.append(to_state)
	replicate_match_event(EVENT_STATE_CHANGED, [to_state])


func _on_countdown_tick(seconds_left: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_COUNTDOWN, [seconds_left])


func _on_turn_changed(slot_id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_TURN_CHANGED, [slot_id])


## The host's feed sequence rides along with the block it belongs to, so a
## client always quotes the number the host will actually check against
## (Match.apply_replicated_feed explains why it cannot count its own).
## Events.feed_block_issued's own signature is untouched; this is the RPC
## payload, not the signal.
##
## Also rides feed_time_left()/is_release_locked()
## for this slot, read at this exact moment -- Match's own _consume_and_
## refeed()/_begin_playing() update both before calling _issue_next_block(),
## which is what emits Events.feed_block_issued and triggers this handler
## synchronously, so "this exact moment" already reflects the placement that
## just happened. Without them a client's mirror always assumed a fresh
## config.block_timer-length interval, which is wrong on an early release
## (spec 1.4 "does not restart the interval") and never showed the ghost
## locked on a client's own screen either.
func _on_feed_block_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName) -> void:
	if _session().is_host():
		var authority: Variant = _authority()
		replicate_match_event(
			EVENT_FEED_ISSUED,
			[
				slot_id, shape_id, next_shape_id, int(authority.feed_seq(slot_id)),
				float(authority.feed_time_left(slot_id)), bool(authority.is_release_locked(slot_id)),
			]
		)


## Spec 1.4's auto-drop is [ORIGINAL] and must keep dropping "from its current
## ghost position", so it must never make a round trip: a request sent to a
## remote player and back on timer expiry could be lost or arrive twice. The
## host therefore drops for every slot it does not itself control, from the
## last update_cursor it received for that slot — at NetConfig.cursor_hz that
## is at worst 67 ms stale, and closest_valid_point() relocates from there
## anyway. A slot this instance controls locally (every slot offline, which is
## all of hot-seat) is left to its own PlayerController, whose ghost is
## exact and costs nothing.
func _on_feed_timer_expired(slot_id: int) -> void:
	if not _session().is_host():
		return
	# The ghost flash is feedback, not a rule, so every instance gets it.
	replicate_match_event(EVENT_FEED_EXPIRED, [slot_id])
	if bool(_session().is_local_slot(slot_id)):
		return
	var cursor: Dictionary = cursor_for_slot(slot_id)
	var origin: Vector3 = cursor["origin"] if cursor.has("origin") else _afk_fallback_origin(slot_id)
	var orientation_index: int = int(cursor.get("orientation_index", 0))
	var free_quat: Quaternion = cursor.get("free_quat", Quaternion.IDENTITY)
	_apply_intent(slot_id, origin, orientation_index, free_quat, true, _authority().feed_seq(slot_id))


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
	var home: Vector3 = _authority().default_ghost_origin(slot_id)
	return home + Vector3.UP * _ghost_tuning.home_spawn_pivot_height(_beacon_visuals, _physics_tuning)


func _on_qol_feed_changed(slot_id: int, backlog: int, paused: bool) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_QOL_FEED, [slot_id, backlog, paused])


func _on_gift_slot_changed(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_SLOT, [slot_id, contents, activated, carrier_id])


## A refusal is feedback for the refused player alone, so it goes only to the
## peer that holds the slot -- never the host's own seat, a bot's or a vacated
## one, which have no remote peer to tell. The host's own seat reacts to
## Match's local emit directly.
func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	if not _session().is_host():
		return
	var owner_peer: int = _remote_peer_of_slot(slot_id)
	if owner_peer < 0:
		return
	_reject_to_peer(owner_peer, slot_id, reason)
	# The intent handler that is applying this refusal must not send it again.
	_gateway.note_rejection_sent(slot_id)


## The remote peer that holds `slot_id`, or -1 when nobody remote does: the
## listen-server's own seat, a bot, an empty or vacated seat, a bad slot.
func _remote_peer_of_slot(slot_id: int) -> int:
	if slot_id < 0 or bool(_session().is_local_slot(slot_id)):
		return -1
	var peer_id: int = int(_session().peer_of_slot(slot_id))
	if peer_id <= 0 or peer_id == Net.HOST_PEER_ID:
		return -1
	return peer_id


## Mirrors an auto-drop's relocation to the owning client so its
## cursor and camera can jump to where the block landed.
##
## That jump is the owning seat's own feedback, so it goes to that peer alone,
## like a refusal, instead of to every client that would only ignore it
## (PlayerController and the HUD drop a slot that is not theirs). Never the
## host's own seat (it reacts to Match's local emit), a bot's, or a vacated
## one: no remote peer to tell.
func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	if not _session().is_host():
		return
	var owner_peer: int = _remote_peer_of_slot(slot_id)
	if owner_peer < 0:
		return
	counters.note_relocate_reply(owner_peer, slot_id, point)
	NetFanout.send_to(self, _session(), owner_peer, &"net_match_event", [EVENT_PLACEMENT_RELOCATED, [slot_id, point]])


func _on_player_eliminated(slot_id: int, team_id: int) -> void:
	if _session().is_host():
		# the third argument is the eliminator slot (-1 unknown).
		replicate_match_event(EVENT_PLAYER_ELIMINATED, [slot_id, team_id, int(_authority().eliminated_by(slot_id))])


## Host only: the objective's state changed. A client's own apply re-emits the
## same signal, hence the host guard (no echo, and a client never replicates).
func _on_mode_state_changed(state: Dictionary) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_MODE_STATE, [state])


func _on_match_won(team_id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_MATCH_WON, [team_id])


## mirrors MatchLifecycle._finish_match()'s own
## Events.match_results_ready emit (fired right after match_won above) to
## every client, in one reliable packet. The dictionary rides as a single
## net_match_event argument -- Godot's high-level RPC marshalling already
## carries a Dictionary/Array of built-in Variant types (this file's own
## MatchConfig.to_dict()/net_match_start precedent), so no separate encoding
## is needed the way the territory raster's binary payload requires.
func _on_match_results_ready(results: Dictionary) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_MATCH_RESULTS, [results])


func _on_gift_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_FLIGHT, [gift_id, origin, landing])


func _on_gift_landed(gift_id: int, landing: Vector3) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_LANDED, [gift_id, landing])


func _on_gift_spawned(gift_id: int, position: Vector2) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_SPAWNED, [gift_id, position])


func _on_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	if _session().is_host():
		# in the after-next trial the carrier is the staged shape, not the next piece.
		replicate_match_event(EVENT_GIFT_CLAIMED, [gift_id, slot_id, special_id, _authority()._feed.claim_carrier_shape_id(slot_id)])


func _on_gift_expired(gift_id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_EXPIRED, [gift_id])


## autoload/match/MatchPlacement._on_special_behavior_triggered()
## emits Events.special_triggered only on the host (game/gifts/specials/
## SpecialBehavior.gd only ever attaches there), so this mirrors it to every
## client exactly like _on_gift_spawned above.
func _on_special_triggered(net_id: int, def_id: StringName, position: Vector3, chain_depth: int) -> void:
	if _session().is_host():
		# QoL 1: a special freezes block timers for a while.
		var feed: Variant = _authority().get("_feed")
		if feed != null:
			feed.note_special_triggered()
		replicate_match_event(EVENT_SPECIAL_TRIGGERED, [net_id, def_id, position, chain_depth])


## mirrors autoload/match/MatchGifts.gd's pop_pending_special()
## emit to every client -- a client never pops its own queue (it only ever
## mirrors the host's, via apply_replicated_special_consumed() below), so this
## dispatch is the only place a client ever learns a special was spent.
func _on_special_consumed(slot_id: int, special_id: StringName) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_SPECIAL_CONSUMED, [slot_id, special_id])


func _on_glue_charges_changed(slot_id: int, charges: int, revision: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GLUE_CHARGES, [slot_id, charges, revision])


## Host: members newly fused into a FusedBody join the glued set; the coat event
## fires only for ids that were not already coated (a charged drop is coated at spawn).
func _on_blocks_fused(_carrier: Node, members: Array) -> void:
	if not _session().is_host():
		return
	for member: Variant in members:
		var block: BlockBody = member as BlockBody
		if block == null or not Quantize.is_wire_id(block.net_id):
			continue
		var was_coated: bool = _fused_ids.has(block.net_id) or _glue_charged_ids.has(block.net_id)
		_fused_ids[block.net_id] = true
		if not was_coated:
			_set_block_coated(block, true)
			replicate_match_event(EVENT_BLOCK_GLUED, [block.net_id, true])


## Host: a member left its group alive (the survivor of a collapse); it uncoats.
## Members that were removed (hole, kill plane) are handled by _on_block_removed.
func _on_fused_member_released(member: Node) -> void:
	var block: BlockBody = member as BlockBody
	if not _session().is_host() or block == null or not Quantize.is_wire_id(block.net_id):
		return
	var was_fused: bool = _fused_ids.erase(block.net_id)
	var was_charged: bool = _glue_charged_ids.erase(block.net_id)
	if was_fused or was_charged:
		_set_block_coated(block, false)
		replicate_match_event(EVENT_BLOCK_GLUED, [block.net_id, false])


## Host: a charged glue drop is coated (and the coat replicated) at spawn, so it
## wears the jelly while falling. DECISION: a never-bonded charged block stays coated;
## the existing 1 -> 0 bond transition already only fires for blocks that bonded.
func _on_glue_drop_charged(body: Node) -> void:
	var block: BlockBody = body as BlockBody
	if not _session().is_host() or block == null or not Quantize.is_wire_id(block.net_id):
		return
	_glue_charged_ids[block.net_id] = true
	_set_block_coated(block, true)
	replicate_match_event(EVENT_BLOCK_GLUED, [block.net_id, true])


func _on_block_owner_changed(net_id: int, owner_slot: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_BLOCK_OWNER_CHANGED, [net_id, owner_slot])


func _on_block_frozen_changed(net_id: int, frozen: bool) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_BLOCK_FROZEN, [net_id, frozen])


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	_capture_team = team_id
	_capture_progress = progress


## Field's kill plane removes a body by emitting on the bus, so the despawn is
## replicated from here rather than from Field — which then needs no idea that
## multiplayer exists.
func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	var typed: BlockBody = block as BlockBody
	if typed != null:
		_fused_ids.erase(typed.net_id)
		_glue_charged_ids.erase(typed.net_id)
		replicate_despawn(typed.net_id, reason)


## Host: mirrors a dissolve start so clients can play the same fade. A body
## without a wire id (net_id allocation failed) never reached a client.
func _on_block_dissolve_started(_block: RigidBody3D, net_id: int, _duration_s: float) -> void:
	if not _session().is_host() or not Quantize.is_wire_id(net_id):
		return
	counters.replicated_dissolve_starts.append(net_id)
	replicate_match_event(EVENT_BLOCK_DISSOLVE_STARTED, [net_id])


func _on_cat_started(id: int, slot_id: int, position: Vector3, duration: float) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_CAT_STARTED, [id, slot_id, position, duration])


func _on_cat_ended(id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_CAT_ENDED, [id])


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
	if not _session().is_host():
		return
	if not (tap != null and tap.capture_impacts) and not _impact_audience():
		return
	collect_impact(speed, position, Time.get_ticks_msec())


func _impact_audience() -> bool:
	return NetFanout.can_send(multiplayer, _session()) and not multiplayer.get_peers().is_empty()


## Host: folds one impact into the current batch window -- same
## NetConfig.impact_coalesce_cell_m cell keeps only the strongest. Game/Block
## already throttles each body to one impact per IMPACT_EMIT_INTERVAL_MS, so
## one body never contributes twice to a window either.
func collect_impact(speed: float, position: Vector3, now_ms: int) -> void:
	if not is_finite(speed) or speed <= 0.0:
		return
	# An impact outside the quantized volume (a block launched past the tallest
	# tower, one falling below the kill plane) is skipped here, on its own: the
	# client would reject it, and it must not cost its neighbours anything.
	if not ImpactWire.position_in_range(position, config.pos_min_y, config.pos_max_y):
		return
	var clamped: float = minf(speed, config.impact_speed_max)
	var key: Vector3i = ImpactWire.coalesce_key(position, config.impact_coalesce_cell_m)
	var existing: Variant = _impact_pending.get(key)
	if existing != null:
		if float((existing as Dictionary)[ImpactWire.KEY_SPEED]) >= clamped:
			return
	elif _impact_pending.size() >= ImpactWire.MAX_EVENTS:
		# A pathological window; the cap below would drop these anyway.
		return
	_impact_pending[key] = {
		ImpactWire.KEY_SPEED: clamped, ImpactWire.KEY_POSITION: position,
		ImpactWire.KEY_TIME_MS: now_ms,
	}


## Host: turns the current window into one batch (strongest first, at most
## impact_max_per_batch and whatever the per-second token bucket allows),
## sends it and clears the window. Events over the cap are dropped, not
## carried: a late thud is worse than a missing one. Returns the packet (empty
## when nothing went out).
func flush_impacts(now_ms: int) -> PackedByteArray:
	var rate: float = float(maxi(config.impact_max_per_second, 1))
	var batch_cap: int = _impact_batch_cap()
	var capacity: float = float(batch_cap)
	if _impact_tokens < 0.0 or _impact_refill_ms < 0:
		_impact_tokens = capacity
	else:
		var elapsed_s: float = float(maxi(now_ms - _impact_refill_ms, 0)) / 1000.0
		_impact_tokens = minf(capacity, _impact_tokens + elapsed_s * rate)
	_impact_refill_ms = now_ms
	var empty: PackedByteArray = PackedByteArray()
	if _impact_pending.is_empty():
		return empty
	var pending: Array[Dictionary] = []
	for event: Variant in _impact_pending.values():
		pending.append(event as Dictionary)
	_impact_pending.clear()
	var allowed: int = mini(int(floor(_impact_tokens)), batch_cap)
	if allowed <= 0:
		return empty
	var chosen: Array[Dictionary] = ImpactWire.strongest(pending, allowed)
	for event: Dictionary in chosen:
		event[ImpactWire.KEY_AGE_MS] = now_ms - int(event[ImpactWire.KEY_TIME_MS])
	_impact_tokens -= float(chosen.size())
	var packet: PackedByteArray = ImpactWire.encode(chosen)
	if tap != null and tap.capture_impacts:
		tap.on_impacts(packet)
	if NetFanout.can_send(multiplayer, _session()):
		for peer_id: int in multiplayer.get_peers():
			# A mid-match joiner still loading its world replay hears nothing
			# yet; impacts are never part of that replay either.
			if not _world_replay.is_pending(peer_id):
				NetFanout.send_to(self, _session(), peer_id, &"net_block_impacts", [packet])
	return packet


## Client: validates a batch and schedules each event for when the
## interpolated view (SnapshotSync renders interpolation_delay_ms behind the
## host) shows it: due = arrival + delay - age. A malformed batch is dropped
## whole.
func receive_impacts(packet: PackedByteArray, now_ms: int) -> void:
	if _session().is_host() or _client_awaiting_world():
		return
	var events: Array[Dictionary] = ImpactWire.decode(
		packet, config.impact_speed_max, config.pos_min_y, config.pos_max_y, _impact_batch_cap()
	)
	if events.is_empty():
		counters.impact_batches_rejected += 1
		return
	# The wire's event_count byte: how many the host claimed, so events decode
	# skipped (bad speed/height, past the per-batch cap) show up in the counter.
	counters.impact_events_dropped += maxi(packet.decode_u8(1) - events.size(), 0)
	var delay_ms: float = _impact_playback_delay_ms()
	var queue_cap: int = config.impact_max_per_second + config.impact_max_per_batch
	var budget: int = _impact_client_budget(now_ms)
	if events.size() > budget:
		counters.impact_events_dropped += events.size() - budget
		events.resize(budget)
	for _i: int in range(events.size()):
		_impact_accept_ms.append(now_ms)
	for event: Dictionary in events:
		var due_ms: float = float(now_ms) + delay_ms - float(event[ImpactWire.KEY_AGE_MS])
		if due_ms <= float(now_ms):
			_emit_impact(float(event[ImpactWire.KEY_SPEED]), event[ImpactWire.KEY_POSITION] as Vector3)
		elif _impact_queue.size() < queue_cap:
			_impact_queue.append([due_ms, event[ImpactWire.KEY_SPEED], event[ImpactWire.KEY_POSITION]])


## Client: plays every queued impact whose moment has come, in arrival order.
func drain_impacts(now_ms: int) -> void:
	if _impact_queue.is_empty():
		return
	var keep: Array[Array] = []
	var due: Array[Array] = []
	for row: Array in _impact_queue:
		if float(row[0]) <= float(now_ms):
			due.append(row)
		else:
			keep.append(row)
	_impact_queue = keep
	for row: Array in due:
		_emit_impact(float(row[1]), row[2] as Vector3)


## The per-batch event bound both ends share: NetConfig.impact_max_per_batch,
## held to what one max_packet_bytes packet carries (sanitize() does the same,
## this guards a config that skipped it).
func _impact_batch_cap() -> int:
	return mini(
		maxi(config.impact_max_per_batch, 1), ImpactWire.max_events_for_payload(config.max_packet_bytes)
	)


## Client: how many more events the sliding one-second window
## (NetConfig.impact_client_max_per_second) lets through at `now_ms`. Entries
## older than a second fall out of the window first.
func _impact_client_budget(now_ms: int) -> int:
	while not _impact_accept_ms.is_empty() and now_ms - _impact_accept_ms[0] >= IMPACT_RATE_WINDOW_MS:
		_impact_accept_ms.pop_front()
	return maxi(config.impact_client_max_per_second - _impact_accept_ms.size(), 0)


func _impact_playback_delay_ms() -> float:
	if impact_delay_override_ms >= 0.0:
		return impact_delay_override_ms
	if SnapshotSync.is_running():
		return SnapshotSync.interpolation_delay_ms()
	return 0.0


## The same pair game/blocks/Block.gd emits on the host, so Sfx (thud), CameraRig
## (shake), Rumble, BlockEffectsManager (dust) and PerchingBirds need nothing
## network-aware.
func _emit_impact(speed: float, position: Vector3) -> void:
	counters.impacts_emitted += 1
	Events.block_impacted.emit(speed)
	Events.block_impacted_at.emit(speed, position)


func _reset_impacts() -> void:
	_impact_pending.clear()
	_impact_queue.clear()
	_impact_accept_ms.clear()
	_impact_send_accum = 0.0
	_impact_tokens = -1.0
	_impact_refill_ms = -1


func _on_net_peer_left(peer_id: int, slot_id: int, _reason: int) -> void:
	_forget_peer(peer_id)
	if slot_id >= 0:
		_authority().on_peer_left(slot_id)


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
	var state: int = int(_authority().state())
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
	if not _session().is_host() or not is_match_live():
		return -1
	var authority: Variant = _authority()
	for slot_id: int in range(int(authority.slot_count())):
		var seat: PlayerSlot = authority.slot(slot_id)
		if seat == null or seat.is_bot or not seat.home_flag_alive:
			continue
		if int(_session().peer_of_slot(slot_id)) != -1:
			continue
		if float(authority.disconnect_grace_left(slot_id)) >= 0.0:
			continue
		return slot_id
	return -1


## Host only, installed into Net's seat policy by game/main/Main.gd: whether a
## returning peer may have `slot_id` back -- the match is live, the slot is
## alive and its disconnect grace is still running.
func seat_reclaimable(slot_id: int) -> bool:
	if not _session().is_host() or not is_match_live():
		return false
	var authority: Variant = _authority()
	if slot_id < 0 or slot_id >= int(authority.slot_count()):
		return false
	var seat: PlayerSlot = authority.slot(slot_id)
	if seat == null or not seat.home_flag_alive:
		return false
	return float(authority.disconnect_grace_left(slot_id)) >= 0.0


## net_territory's arguments for one full keyframe, or [] with no raster.
## Diffs to every other peer are computed against _last_owner_bytes/
## _last_state_bytes, so that baseline is what the joiner must hold; when no
## baseline exists yet (nothing sent this match) the current raster goes out
## and the next broadcast is forced to a full keyframe for everyone, so all
## peers converge on the same baseline either way.
func _territory_replay_args() -> Array:
	var raster: TerritoryRaster = _authority().raster()
	if raster == null:
		return []
	var owners: PackedByteArray = _last_owner_bytes
	var states: PackedByteArray = _last_state_bytes
	if _force_full_raster or owners.is_empty() or owners.size() != raster.owner_bytes().size():
		owners = raster.owner_bytes().duplicate()
		states = raster.state_bytes().duplicate()
		_force_full_raster = true
	if owners.is_empty():
		return []
	return [
		_encode_raster_full(owners, states),
		true,
		_team_shares(),
		_capture_team,
		_capture_progress,
		_encode_circles(),
	]


## EVENT_SLOT_REPLAY's payload for `slot_id`, or [] for a slot with nothing
## held (eliminated, or between blocks).
func _slot_replay_args(slot_id: int) -> Array:
	var authority: Variant = _authority()
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
		authority._feed.staged_gift_shape_id(slot_id),
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
	# 8 args before 10 adds the after-next gift and its carrier.
	var has_after: bool = args.size() == SLOT_REPLAY_ARGS
	if (args.size() != SLOT_REPLAY_ARGS_BASE and not has_after) or not args[0] is int or not args[3] is int or not args[5] is bool:
		return
	for index: int in (SLOT_REPLAY_ID_ARGS_BASE if not has_after else SLOT_REPLAY_ID_ARGS):
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
	var after_special: StringName = StringName(args[SLOT_REPLAY_ARGS_BASE]) if has_after else &""
	var after_carrier: StringName = StringName(args[SLOT_REPLAY_ARGS_BASE + 1]) if has_after else &""
	var authority: Variant = _authority()
	var running: MatchConfig = authority.config
	if running == null or slot_id < 0 or slot_id >= int(authority.slot_count()):
		return
	if feed_seq < 0 or not is_finite(time_left) or time_left < 0.0 or time_left > MatchConfig.BLOCK_TIMER_MAX:
		return
	if authority._feed._shape_by_id(held_id) == null:
		return
	if next_id != &"" and authority._feed._shape_by_id(next_id) == null:
		return
	if held_special != &"" and not _gift_special_id_wire_ok(String(held_special)):
		return
	if next_special != &"" and (next_id == &"" or not _gift_special_id_wire_ok(String(next_special))):
		return
	if after_special != &"" and (not _gift_special_id_wire_ok(String(after_special)) or authority._feed._shape_by_id(after_carrier) == null):
		return
	if held_special != &"":
		authority.apply_replicated_gift_claimed(-1, slot_id, held_special)
		authority._feed.apply_replicated_next_gift(slot_id, held_id)
	authority.apply_replicated_feed(slot_id, held_id, next_id, feed_seq, time_left, locked)
	if next_special != &"":
		authority.apply_replicated_gift_claimed(-1, slot_id, next_special)
		authority._feed.apply_replicated_next_gift(slot_id, next_id)
	if after_special != &"":
		authority.apply_replicated_gift_claimed(-1, slot_id, after_special)
		authority._feed.apply_replicated_staged_gift(slot_id, after_carrier)
	Events.feed_block_issued.emit(slot_id, held_id, next_id)


# --- Territory payload ------------------------------------------------------

func _encode_raster_full(owners: PackedByteArray, states: PackedByteArray) -> PackedByteArray:
	var body: PackedByteArray = PackedByteArray()
	body.append_array(owners)
	body.append_array(states)
	return _finish_raster_payload(body)


func _encode_raster_diff(
	cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray
) -> PackedByteArray:
	var body: PackedByteArray = PackedByteArray()
	body.resize(cells.size() * RASTER_ENTRY_BYTES)
	var offset: int = 0
	for index: int in cells:
		body.encode_u32(offset, index)
		body.encode_u8(offset + 4, owners[index])
		body.encode_u8(offset + 5, states[index])
		offset += RASTER_ENTRY_BYTES
	return _finish_raster_payload(body)


## Prefixes the version, the compression flag and the uncompressed size, then
## compresses the body when NetConfig.raster_compress is on. The size has to
## travel: PackedByteArray.decompress() needs the output length, and a
## territory packet is reliable, so an honest 4 bytes is cheaper than guessing.
func _finish_raster_payload(body: PackedByteArray) -> PackedByteArray:
	var flags: int = 0
	var payload_body: PackedByteArray = body
	if config.raster_compress and body.size() > 0:
		var compressed: PackedByteArray = body.compress(FileAccess.COMPRESSION_ZSTD)
		if compressed.size() < body.size():
			payload_body = compressed
			flags |= RASTER_FLAG_COMPRESSED
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(RASTER_HEADER_BYTES)
	packet.encode_u8(0, RASTER_VERSION)
	packet.encode_u8(1, flags)
	packet.encode_u32(2, body.size())
	packet.append_array(payload_body)
	return packet


## Inverse of the two encoders, returning {"cells", "owners", "states"} or an
## empty Dictionary for a truncated, foreign or wrong-version payload. `full`
## says which layout the body holds; a full payload leaves "cells" empty
## because it names every cell.
static func decode_raster_payload(packet: PackedByteArray, full: bool) -> Dictionary:
	if packet.size() < RASTER_HEADER_BYTES:
		return {}
	if packet.decode_u8(0) != RASTER_VERSION:
		return {}
	var flags: int = packet.decode_u8(1)
	var raw_size: int = packet.decode_u32(2)
	if raw_size < 0:
		return {}
	var body: PackedByteArray = packet.slice(RASTER_HEADER_BYTES)
	if (flags & RASTER_FLAG_COMPRESSED) != 0:
		body = body.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if body.size() != raw_size:
		return {}

	if full:
		if raw_size % 2 != 0:
			return {}
		var half: int = raw_size / 2
		return {
			"cells": PackedInt32Array(),
			"owners": body.slice(0, half),
			"states": body.slice(half),
		}

	if raw_size % RASTER_ENTRY_BYTES != 0:
		return {}
	var cells: PackedInt32Array = PackedInt32Array()
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()
	var entries: int = raw_size / RASTER_ENTRY_BYTES
	for i: int in range(entries):
		var offset: int = i * RASTER_ENTRY_BYTES
		cells.append(body.decode_u32(offset))
		owners.append(body.decode_u8(offset + 4))
		states.append(body.decode_u8(offset + 5))
	return {"cells": cells, "owners": owners, "states": states}


static func _capture_wire_ok(team_id: int, progress: float, team_count: int) -> bool:
	if is_nan(progress) or is_inf(progress) or progress < 0.0 or progress > 1.0:
		return false
	return team_id >= -1 and team_id < team_count


# --- RPCs -------------------------------------------------------------------
# Client -> host. The host checks the caller's peer id against `slot_id`
# (spec 2.6: "The host checks territory, the timer, and that the slot
# matches") and drops anything else on the floor; it never trusts slot_id.

# auto_drop is part of the wire contract but deliberately never read: spec
# 2.5's relocation privilege belongs to the host's own timer, not to whoever
# is on the other end of a socket. See _handle_place_intent.
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
	_handle_place_intent(
		multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat, feed_seq
	)


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
	_handle_throw_intent(
		multiplayer.get_remote_sender_id(),
		slot_id,
		origin,
		orientation_index,
		free_quat,
		velocity,
		feed_seq
	)


@rpc("any_peer", "call_remote", "reliable")
func net_request_use_gift_slot(slot_id: int) -> void:
	_gateway.handle_gift_slot(multiplayer.get_remote_sender_id(), slot_id)


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_update_cursor(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, aim: Vector3 = Vector3.ZERO
) -> void:
	_handle_cursor_update(multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat, aim)


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cat_target(slot_id: int, point: Vector3) -> void:
	_gateway.handle_cat_target(multiplayer.get_remote_sender_id(), slot_id, point)


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	if _client_awaiting_world():
		return
	_authority().apply_replicated_cat_state(id, position, velocity, point, remaining)


# Host -> clients.

## one batch of host-detected block impacts. Unreliable on the
## cosmetic CURSOR_CHANNEL: a lost batch is a missed thud, never worth a
## retransmit or head-of-line blocking a spawn on channel 0. Events are
## position-keyed (ImpactWire's DECISION), so arrival order relative to the
## reliable spawn/despawn stream does not matter.
@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_block_impacts(packet: PackedByteArray) -> void:
	receive_impacts(packet, Time.get_ticks_msec())


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
	if replay_id > 0 and not _session().is_host():
		_begin_world_replay(replay_id)
	_authority().start_match(match_config)
	_apply_roster(roster)


func _apply_roster(roster: Array) -> void:
	for entry: Variant in roster:
		if not (entry is Dictionary):
			continue
		var info: Dictionary = entry
		if not info.has(LobbySeats.FIELD_SLOT_ID):
			continue
		var target: PlayerSlot = _authority().slot(int(info[LobbySeats.FIELD_SLOT_ID]))
		if target == null:
			continue
		target.peer_id = int(info.get(LobbySeats.FIELD_PEER_ID, 0))
		target.display_name = String(info.get(LobbySeats.FIELD_NAME, target.display_name))
		target.is_local = bool(_session().is_local_slot(target.slot_id))


## the client half of the replay handshake. Lands after every
## replay message (reliable, ordered), so the world is built by now.
@rpc("authority", "call_remote", "reliable")
func net_replay_end(replay_id: int) -> void:
	if _session().is_host() or _client_awaiting_world() or replay_id <= 0:
		return
	# The replay's last message: live events from here on are news again.
	if replay_id == _replaying_id:
		_end_world_replay()
	if NetFanout.can_send(multiplayer, _session()):
		rpc_id(Net.HOST_PEER_ID, &"net_replay_ack", replay_id)


@rpc("any_peer", "call_remote", "reliable")
func net_replay_ack(replay_id: int) -> void:
	_world_replay.handle_replay_ack(multiplayer.get_remote_sender_id(), replay_id)


## True on a client that has not received net_match_start since it joined
## (see _awaiting_match_start).
func _client_awaiting_world() -> bool:
	return _awaiting_match_start and not _session().is_host()


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
	if not Quantize.is_wire_id(net_id):
		# Defensive: a well-behaved host never sends this (replicate_spawn()'s
		# own guard above), but this is the client's own boundary and must not
		# trust the wire either -- a body built for an id the wire cannot
		# carry would sit under blocks_parent forever with nothing able to
		# address it for a despawn.
		return
	var registry: Node = _authority().registry()
	var parent: Node3D = _authority().blocks_parent()
	if registry == null or parent == null:
		return
	if registry.block_for_net_id(net_id) != null:
		return
	var shape: BlockShape = _shape_for_id(shape_id)
	if shape == null:
		return

	# the same slot-colour tint as the host's own block (see
	# autoload/Match.gd's _spawn_block DECISION on using the slot's own colour
	# rather than a separate team lookup). `origin` below is already the
	# host's exact spawned transform -- the bottom-centre pivot needs no extra
	# conversion here either, since BlockFactory.build() offsets this shape's
	# cells by the same shape.bottom_center() on every instance.
	var owner_slot_ref: PlayerSlot = _authority().slot(owner_slot)
	var color: Color = owner_slot_ref.color if owner_slot_ref != null else Color.WHITE
	var block: BlockBody = _block_factory().call(&"build", shape, _physics_tuning, owner_slot, color) as BlockBody
	# Spec 2.6: "Clients set every synced RigidBody3D to freeze = true
	# (kinematic) and move them by interpolating snapshots." Freezing before
	# the body enters the tree means it never simulates a single step here.
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	block.freeze = true
	parent.add_child(block)
	block.global_transform = Transform3D(Basis(rotation), origin)
	# untrusted wire id; only a known roster gift swaps the look.
	if gift_id != &"" and _gift_special_id_wire_ok(String(gift_id)):
		_block_factory().call(&"apply_gift_visual", block, shape, _physics_tuning, gift_id)

	# block_placed is what BlockRegistry tracks bodies on; with
	# set_host_authority(false) it allocates no id of its own, so the host's
	# is bound straight after and the two ends address the same body.
	Events.block_placed.emit(block, shape.id)
	registry.bind_net_id(block, net_id)
	Events.block_replicated.emit(block, net_id)


@rpc("authority", "call_remote", "reliable")
func net_block_despawned(net_id: int, reason: String) -> void:
	if _client_awaiting_world():
		return
	var registry: Node = _authority().registry()
	if registry == null:
		return
	var block: BlockBody = registry.block_for_net_id(net_id)
	if block == null or not is_instance_valid(block):
		return
	Events.block_removed.emit(block, reason)
	block.queue_free()


## `payload` is a raster diff or a full raster, compressed when
## NetConfig.raster_compress is on; `full` says which. Clients apply it to
## their mirror raster and re-emit Events.hole_cells_changed for the cells
## whose hole bit flipped, so Field opens the same holes without a second RPC.
##
## `circle_payload` is core/net/CircleWire.gd's encoding of the same host
## tick's analytic circle list; a default empty value keeps a
## direct local call from an older test/caller compiling (CircleWire.decode()
## on an empty array returns {} for a truncated payload, which the branch
## below already treats as "no circle update this packet", not an error).
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
	# Untrusted wire values: a finite 0..1 progress and a known team (or none).
	if not _capture_wire_ok(capture_team, capture_progress, shares.size()):
		return
	var decoded: Dictionary = decode_raster_payload(payload, full)
	if decoded.is_empty():
		return
	var circles: Dictionary = CircleWire.decode(
		circle_payload, _authority().circle_wire_xz_bound(), _authority().circle_wire_radius_max()
	)
	_authority().apply_replicated_territory(
		decoded["cells"],
		decoded["owners"],
		decoded["states"],
		full,
		circles.get("xs", PackedFloat32Array()),
		circles.get("zs", PackedFloat32Array()),
		circles.get("radii", PackedFloat32Array()),
		circles.get("teams", PackedInt32Array()),
		circles.get("goal_positions", PackedVector2Array()),
		circles.get("goal_radii", PackedFloat32Array()),
		bool(circles.get("argmax_mode", false))
	)
	var raster: TerritoryRaster = _authority().raster()
	if raster == null:
		return
	var opened: PackedInt32Array = raster.holes_opened()
	var closed: PackedInt32Array = raster.holes_closed()
	if opened.size() > 0 or closed.size() > 0:
		Events.hole_cells_changed.emit(opened, closed)
	Events.territory_replicated.emit(raster)
	Events.territory_share_changed.emit(shares)
	Events.goal_capture_progress.emit(capture_team, capture_progress)


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	if _client_awaiting_world() or bool(_session().is_local_slot(slot_id)):
		return
	_store_cursor(slot_id, origin, orientation_index, free_quat)
	Events.remote_cursor_updated.emit(slot_id, origin, orientation_index, free_quat)
