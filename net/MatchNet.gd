extends Node
## Every gameplay RPC in the game (spec 3.4 "Client -> host intents" and the
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
## When M3b swaps the peer, not a line of this file changes.
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
## re-emits them locally, so every M2 consumer (the HUD, the ghost, Field)
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
## One diff entry: cell index u32, owner byte, state byte.
const RASTER_ENTRY_BYTES: int = 6

## Names for the match-flow events mirrored over net_match_event. StringNames
## rather than an enum so a packet capture reads as itself.
const EVENT_STATE_CHANGED: StringName = &"state_changed"
const EVENT_COUNTDOWN: StringName = &"countdown"
const EVENT_TURN_CHANGED: StringName = &"turn_changed"
const EVENT_FEED_ISSUED: StringName = &"feed_issued"
const EVENT_FEED_EXPIRED: StringName = &"feed_expired"
## Bontago-1pi.18.1: [slot_id, backlog_count, timer_paused] for the QoL experiments.
const EVENT_QOL_FEED: StringName = &"qol_feed"
## Bontago-1pi.18.2: [slot_id, contents, activated_special, carrier_shape_id] for the QoL gift slot.
const EVENT_GIFT_SLOT: StringName = &"gift_slot"
const EVENT_PLACEMENT_REJECTED: StringName = &"placement_rejected"
## Bontago-1pi.52: longest refusal reason a client will show. The real ones
## (PlacementRules/ThrowRules REASON_*) are all well under this; a longer one is
## not from this build's host.
const REJECT_REASON_MAX_LENGTH: int = 48
const EVENT_PLACEMENT_RELOCATED: StringName = &"placement_relocated"
const EVENT_PLAYER_ELIMINATED: StringName = &"player_eliminated"
const EVENT_MATCH_WON: StringName = &"match_won"
## Bontago-22y.11: the active mode objective's score/state, host -> clients.
const EVENT_MODE_STATE: StringName = &"mode_state"
## Bontago-1pi.13: mirrors Events.match_results_ready (autoload/match/
## MatchStats.gd's own header documents the payload shape). See
## _on_match_results_ready() below and net_match_event's own dispatch case.
const EVENT_MATCH_RESULTS: StringName = &"match_results"
const EVENT_GIFT_FLIGHT: StringName = &"gift_flight_spawned"
const EVENT_GIFT_LANDED: StringName = &"gift_landed"

# DECISION: reliable channel order plus per-match tombstones prevents a late
# spawn/flight from resurrecting a claimed gift. Legacy spawn can upgrade once.
enum GiftWirePhase {
	FALLING = MatchGifts.FALLING,
	LANDED = MatchGifts.LANDED,
	LEGACY = MatchGifts.WIRE_LEGACY,
	REMOVED = MatchGifts.WIRE_REMOVED,
}
var _gift_wire_phases: Dictionary = {}
var _gift_spawn_notified: Dictionary = {}

const EVENT_GIFT_SPAWNED: StringName = &"gift_spawned"
const EVENT_GIFT_CLAIMED: StringName = &"gift_claimed"
const EVENT_GIFT_EXPIRED: StringName = &"gift_expired"
## M4 P2c-ii: mirrors game/specials/SpecialBehavior.gd's own trigger, via
## autoload/match/MatchPlacement._on_special_behavior_triggered() ->
## Events.special_triggered (host only). See _on_special_triggered() below.
const EVENT_SPECIAL_TRIGGERED: StringName = &"special_triggered"
## Bontago-1en.21: mirrors autoload/match/MatchGifts.gd's pop_pending_special()
## own emit (Events.special_consumed, host-only) -- see _on_special_consumed()
## below.
const EVENT_SPECIAL_CONSUMED: StringName = &"special_consumed"
const EVENT_GLUE_CHARGES: StringName = &"glue_charges_changed"
## Bontago-1pi.85.52: [net_id, glued] -- a placed block gained its first / lost its last glue bond.
const EVENT_BLOCK_GLUED: StringName = &"block_glued_changed"
const EVENT_BLOCK_OWNER_CHANGED: StringName = &"block_owner_changed"
const EVENT_BLOCK_FROZEN: StringName = &"block_frozen_changed"
const EVENT_CAT_STARTED: StringName = &"cat_started"
const EVENT_CAT_ENDED: StringName = &"cat_ended"
## Bontago-1pi.11.41: [net_id] of a block the host started dissolving on a
## hole. Its removal follows through the ordinary net_block_despawned.
const EVENT_BLOCK_DISSOLVE_STARTED: StringName = &"block_dissolve_started"
## Bontago-8or.11 (mid-match join replay only): one slot's absolute feed and
## gift state -- [slot_id, held_shape_id, next_shape_id, feed_seq, time_left,
## release_locked, held_special_id, next_special_id]. See
## _apply_slot_replay().
const EVENT_SLOT_REPLAY: StringName = &"slot_replay"
## Bontago-8or.11 (mid-match join replay only): [match_timer_left].
const EVENT_MATCH_CLOCK: StringName = &"match_clock"
## Bontago-1pi.42 (mid-match join replay only, COUNTDOWN): the loading-screen ready
## gate as the host sees it now -- [ready_peer_ids, required_peer_ids, open].
const EVENT_LOADING_GATE: StringName = &"loading_gate"
## Bontago-1pi.69: the live scoreboard snapshot (MatchStats.build_live_payload()),
## sent at NetConfig.scoreboard_hz while the round is live; clients show it in the
## hold-to-show scoreboard (ui/ScoreboardOverlay.gd). Display only.
const EVENT_LIVE_SCORES: StringName = &"live_scores"

@export var config: NetConfig = preload("res://config/net_config.tres")

## Clients build their replicated bodies with the same factory and the same
## tuning the host built the originals with, so a frozen copy has the same
## collision shape and mass even though it never simulates.
var _physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Lazily built id -> BlockShape index; BlockShape.load_all_shapes() scans a
## directory, so it happens once and only where a spawn needs it.
var _shapes_by_id: Dictionary = {}

## M4 P2c-ii: EVENT_SPECIAL_TRIGGERED's chain_depth wire bound
## (SpecialTuning.max_chain_depth). A separate preload rather than reading
## through _authority() -- the config is architecture-fixed for the build,
## the same reason _physics_tuning above is preloaded rather than read from
## Match's own running MatchConfig.
var _special_tuning: SpecialTuning = preload("res://config/special_tuning.tres")
## Bontago-1pi.11.41: the fade length a client reports with a replicated
## dissolve start (same shipped resource the host's HoleDissolver reads).
var _hole_dissolve_tuning: HoleDissolveTuning = preload("res://config/hole_dissolve_tuning.tres")
## Bontago-1pi.40: the same shipped resources PlayerController reads for the
## player's first-block hover, so the AFK auto-drop's no-cursor fallback origin
## clears the home beacon by the identical rule (_afk_fallback_origin()).
var _ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
var _beacon_visuals: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")
## Test-only (Bontago-1pi.11.41): net_ids _on_block_dissolve_started() decided
## to replicate, in order -- NetFanout.can_send() is false without a live peer, so this
## is what proves the host would have sent them. Game code never reads it.
var replicated_dissolve_starts: Array[int] = []
## Host: live glue bond count per block net_id (only blocks with a bond are present).
var _glue_bond_counts: Dictionary = {}
## Test-only (Bontago-1pi.52): how many times each event name reached
## replicate_match_event() on the host, counted before its NetFanout.can_send() gate
## (false in a unit test). Proves a refusal was never broadcast to every peer.
## Bounded by the number of event names. Game code never reads it.
var replicated_event_counts: Dictionary = {}
## Test-only (Bontago-1pi.52): peer_id -> placement_rejected replies addressed
## to it by _reject_to_peer(), and the most recent one as [peer_id, slot_id,
## reason]. Game code never reads either.
var reject_replies_by_peer: Dictionary = {}
var last_reject_reply: Array = []
## Test-only (Bontago-1pi.52): the same pair for placement_relocated, the other
## per-player cursor message. Game code never reads either.
var relocate_replies_by_peer: Dictionary = {}
var last_relocate_reply: Array = []

## Bontago-1pi.55: replicated block impacts (core/net/ImpactWire.gd).
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
## Test-only (Bontago-1pi.55): when true the host collects impacts and records
## every batch flush_impacts() builds even without a live peer (NetFanout.can_send() is
## false in a unit test). Game code never sets it.
var capture_impacts: bool = false
var impact_batches: Array[PackedByteArray] = []
## Test-only: >= 0 replaces SnapshotSync's interpolation delay as the client's
## impact playback delay.
var impact_delay_override_ms: float = -1.0
## Diagnostics: batches a client dropped as malformed, events it re-emitted.
var impact_batches_rejected: int = 0
var impacts_emitted: int = 0
## Client: events a well-formed batch carried that were not played (a bad event
## skipped by ImpactWire.decode, or past the per-batch / per-second cap).
var impact_events_dropped: int = 0
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
## Test seam (mirrors set_providers()): overrides the roster
## _known_special_ids() reads. res://config/specials/ is deliberately empty
## until P3-P5 land a concrete special, so a test proving real
## roster-membership gating (as opposed to "empty roster, only the
## placeholder passes") needs a way to fake "some ids exist" without writing
## a .tres resource under a directory this package does not own. null
## (default) reads the real SpecialDef.load_all_specials().
var _special_ids_override: Variant = null

## DECISION (net/MatchNet.gd): Net and Match are plain autoloads and GUT
## cannot double one (see game/PlayerController.gd's DECISION for the whole
## story), so the two collaborators this node cannot work without are reached
## through seams. null means "the real autoload", which is what every shipped
## build uses; tests inject doubles with set_providers().
var _net_provider: Variant = null
var _match_provider: Variant = null

## slot_id -> {"origin": Vector3, "orientation_index": int,
## "free_quat": Quaternion, "time": float}. On the host this is what spec
## 2.5's auto-drop [ORIGINAL] fires from; on every instance it is what
## game/RemoteCursors.gd draws.
var _cursors: Dictionary = {}

var _intents_sent: Dictionary = {}
var _intents_accepted: Dictionary = {}
var _intents_refused: Dictionary = {}
## Bontago-1pi.52: the slot whose refusal _on_placement_rejected() already sent
## to its owning peer while the current intent was being applied, so the intent
## handler's own tail reply (for refusals Match never announces: a stale
## feed_seq, a held-block lock, NOT_A_SPECIAL) is not a second copy. -1 = none.
var _reject_replied_slot: int = -1
var _auto_drops: Dictionary = {}
## Cursor updates from a client that the host dropped as malformed (see
## _handle_cursor_update). Not an intent, so not part of the sent/accepted/
## refused identity; counted so the debug overlay can show a misbehaving peer.
var _cursors_refused: Dictionary = {}

## net_id -> true for every spawn this instance has seen. A net_id arriving
## twice is a hard failure of the "never duplicated" criterion, so it is
## counted rather than quietly overwritten.
var _spawned_net_ids: Dictionary = {}
var _duplicate_net_ids: int = 0

## Test-only (Bontago-mv0.1.7): counts every replicate_spawn() call this host
## refused to put on the wire because BlockRegistry's allocator left the block
## with an id the wire cannot carry (net_id == -1 past Quantize.NET_ID_MAX).
## NetFanout.can_send() is already false in a unit test with no live peer, so that gate
## alone cannot prove a refused spawn was never even handed to the rpc(); this
## counter is the seam that does. Game code never reads it.
var _invalid_spawn_refusals: int = 0

## Test-only (Bontago-mv0.1.13): to_state values _on_match_state_changed
## actually decided to replicate as EVENT_STATE_CHANGED, in order. Needed for
## the same reason as _invalid_spawn_refusals above: NetFanout.can_send() is already
## false in a unit test with no live peer, so it alone cannot prove the
## transient LOBBY/LOADING/COUNTDOWN states a start_match() call produces
## internally were suppressed rather than merely handed to a no-op rpc().
## Game code never reads it.
var replicated_state_changes: Array[int] = []

## Test-only (Bontago-mv0.1.13): how many times replicate_match_start()
## actually queued net_match_start for the running match. Must be exactly 1
## per start, including a restart from PLAYING/END with a client connected.
var match_starts_replicated: int = 0

var _cursor_send_accum: float = 0.0
var _raster_send_accum: float = 0.0

## The last owner/state bytes the host sent, to diff this tick's against.
var _last_owner_bytes: PackedByteArray = PackedByteArray()
var _last_state_bytes: PackedByteArray = PackedByteArray()
## Forces the next territory packet to be a full keyframe: set at match start
## and whenever a peer joins, since a fresh client has nothing to diff against.
var _force_full_raster: bool = true

## Cached from Events.goal_capture_progress so the territory packet can carry
## the HUD's numbers without a second RPC.
var _capture_team: int = -1
var _capture_progress: float = 0.0

## True once replicate_match_start() has gone out for the running match, so a
## lobby that calls it explicitly and the automatic send below cannot both
## fire.
var _match_start_sent: bool = false

## -- Mid-match join / reconnect replay (Bontago-8or.11) -----------------------
## Host only: peer_id -> replay id of a world replay sent to that peer and not
## yet acknowledged. Gameplay intents from a peer in here are refused (spec
## 3.4: the host checks every intent; a peer with no world yet cannot have
## formed a legitimate one), its cursors and cat targets are dropped.
var _replay_pending: Dictionary = {}
## peer_id -> seconds its replay has gone unacknowledged (LOW4 timeout).
var _replay_age: Dictionary = {}
var _next_replay_id: int = 1
## Client only: true from the moment this instance becomes a CLIENT until the
## first net_match_start lands. Every host -> client gameplay RPC that arrives
## in that window was broadcast before this peer's replay was built, so the
## replay already contains its effect; applying it to a world that does not
## exist yet could only corrupt the mirror (a stray LOBBY -> PLAYING emit, a
## feed event for slots that are not built).
var _awaiting_match_start: bool = false
## Test seam: when true, replay messages are appended to `replay_capture` as
## [peer_id, method, args] instead of going out by rpc_id(). There is no peer
## in a unit test, and this is what lets a test apply the exact ordered
## replay to a client-mode MatchNet.
var capture_replay: bool = false
var replay_capture: Array[Array] = []
## Test-only counters. Game code never reads them.
var replays_started: int = 0
var replays_timed_out: int = 0
var replays_acknowledged: int = 0
var intents_refused_before_replay_ack: int = 0
## Client only: the replay id this instance last acknowledged (0 = none).
var last_replay_acknowledged: int = 0
## Client only (Bontago-1pi.56): the id of the late-join world replay being
## applied right now (0 = none). Set by the net_match_start that carries it,
## cleared by the matching net_replay_end -- or by anything that ends the replay
## early (a new match start, leaving the session, teardown, the ack timeout), so
## a replay that never completes cannot mute live feedback for the rest of a match.
var _replaying_id: int = 0
var _replaying_since_ms: int = 0

## Bontago-22y.10: the weather RPC surface (net/WeatherNet.gd), a child node.
var _weather_net: WeatherNet = null
var _cat_send_accum: float = 0.0
var _scores_send_accum: float = 0.0
var _cat_target_last_send: float = -1.0


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
	Events.glue_bond_changed.connect(_on_glue_bond_changed)
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
	# Bontago-22y.10: weather replication lives in its own child node.
	_weather_net = WeatherNet.new()
	_weather_net.name = "WeatherNet"
	add_child(_weather_net)
	_weather_net.set_providers(_net_provider, _match_provider)
	# Bontago-8or.11: weather/snow/breeze broadcasts before net_match_start
	# are dropped on the same gate as match events.
	_weather_net.awaiting_world = _client_awaiting_world


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
	if _weather_net != null:
		_weather_net.set_providers(net_provider, match_provider)
	if _match_provider != null:
		_match_provider.set_replicator(self)


## Test seam; see _special_ids_override. `ids` is an Array of String/
## StringName, or null to go back to the real SpecialDef.load_all_specials()
## loader.
func set_special_roster_for_test(ids: Variant) -> void:
	_special_ids_override = ids
	_special_ids_cached = false
	_special_ids_by_id = {}


func _session() -> Variant:
	return _net_provider if _net_provider != null else Net


func _authority() -> Variant:
	return _match_provider if _match_provider != null else Match


## Bontago-1pi.59: every host -> clients broadcast goes through here, so a peer the
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
	_tick_replay_timeouts(delta)
	if not _impact_pending.is_empty():
		_impact_send_accum += delta
		if _impact_send_accum >= 1.0 / maxf(config.impact_batch_hz, 0.001):
			_impact_send_accum = 0.0
			flush_impacts(Time.get_ticks_msec())
	var cat: CatController = _authority().active_cat()
	if cat != null and NetFanout.can_send(multiplayer, _session()):
		_cat_send_accum += delta
		if _cat_send_accum >= 1.0 / maxf(config.cursor_hz, 0.001):
			_cat_send_accum = 0.0
			_broadcast(&"net_cat_state", [cat.activation_id, cat.global_position,
				cat.linear_velocity, cat.target, cat.time_left])
	if MatchAutoload.is_live(_authority().state()):
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

## The single call site for a placement, host or client, local or remote.
## On the host it is Match.request_place() inline; on a client it is the
## reliable intent RPC below and the return value is REASON_OK optimistically
## (the real outcome arrives as Events.placement_rejected or the next
## feed_block_issued).
##
## `feed_seq` is Match.feed_seq(slot_id) as the caller last saw it. The host
## refuses an intent whose feed_seq is not current, which is what makes a
## replayed or doubled intent a no-op instead of spending the next block.
func submit_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> StringName:
	if _session().is_host():
		if not auto_drop:
			_bump(_intents_sent, slot_id)
		return _apply_intent(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)

	# A client never auto-drops: spec 2.5's auto-drop is [ORIGINAL] and must
	# not be able to go missing in a round trip, so the host fires it from the
	# last cursor it received (see _on_feed_timer_expired).
	if auto_drop:
		return PlacementRules.REASON_NO_BLOCK
	if not NetFanout.can_send(multiplayer, _session()):
		# Nothing went on the wire, so nothing is counted: the harness proves
		# "never lost" by comparing this client's intents_sent with the host's
		# count for the same slot, and a phantom here would break that.
		return PlacementRules.REASON_NO_BLOCK
	_bump(_intents_sent, slot_id)
	rpc_id(
		Net.HOST_PEER_ID,
		&"net_request_place",
		slot_id,
		origin,
		orientation_index,
		free_quat,
		false,
		feed_seq
	)
	return PlacementRules.REASON_OK


## The single call site for a throw, host or client, local or remote --
## submit_place()'s own twin (spec 3.4: "request_throw(slot_id, pos, orient,
## velocity): the host clamps velocity to throw_max_speed"). A throw has no
## auto_drop equivalent at all (MatchPlacement.request_throw()'s own doc
## comment), so unlike submit_place() there is no bool to gate the host-side
## _bump() on -- every call here is a deliberate release.
func submit_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> StringName:
	if _session().is_host():
		_bump(_intents_sent, slot_id)
		return _apply_throw_intent(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)

	if not NetFanout.can_send(multiplayer, _session()):
		# See submit_place()'s matching comment: nothing went on the wire, so
		# nothing is counted.
		return PlacementRules.REASON_NO_BLOCK
	_bump(_intents_sent, slot_id)
	rpc_id(
		Net.HOST_PEER_ID,
		&"net_request_throw",
		slot_id,
		origin,
		orientation_index,
		free_quat,
		velocity,
		feed_seq
	)
	return PlacementRules.REASON_OK


## The local player's ghost pose, at NetConfig.cursor_hz. Unreliable: a lost
## one costs one frame of someone else's ghost. On the host this only
## broadcasts; on a client it also goes to the host, which stores it as the
## slot's last known ghost — **that is what the host auto-drops from when the
## feed timer expires**, so no round trip can lose an auto-drop.
##
## Callers may call this every frame: the local record is always refreshed and
## the send is throttled to config.cursor_hz here, so no caller has to own a
## rate accumulator of its own.
func submit_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	_store_cursor(slot_id, origin, orientation_index, free_quat)
	if not NetFanout.can_send(multiplayer, _session()):
		return
	var step: float = 1.0 / maxf(config.cursor_hz, 0.001)
	var now: float = _now()
	if now - _cursor_send_accum < step:
		return
	_cursor_send_accum = now
	if _session().is_host():
		_broadcast(&"net_cursor", [slot_id, origin, orientation_index, free_quat])
	else:
		rpc_id(Net.HOST_PEER_ID, &"net_update_cursor", slot_id, origin, orientation_index, free_quat)


func submit_cat_target(slot_id: int, point: Vector3) -> void:
	if not point.is_finite():
		return
	if _session().is_host():
		_authority().set_cat_target(slot_id, point)
	elif NetFanout.can_send(multiplayer, _session()):
		var now: float = _now()
		if now - _cat_target_last_send >= 1.0 / maxf(config.cursor_hz, 0.001):
			_cat_target_last_send = now
			rpc_id(Net.HOST_PEER_ID, &"net_cat_target", slot_id, point)


func _handle_cat_target(sender_peer_id: int, slot_id: int, point: Vector3) -> void:
	if not _session().is_host() or int(_session().slot_of_peer(sender_peer_id)) != slot_id:
		return
	if _replay_pending.has(sender_peer_id):
		return
	_authority().set_cat_target(slot_id, point)


## Bontago-1pi.13 (results screen "Play again"): restarts the match that just
## ended with the same MatchConfig, for every peer. Mirrors submit_place()'s
## own single-door shape: **the host's own local call acts inline, with no
## sender check** (exactly submit_place()'s host branch calling
## _apply_intent() directly, never through _handle_place_intent()'s
## sender-owns-slot gate) -- a call arriving offline (hot-seat, sandbox) would
## otherwise be refused, since Net's `_peers` map (slot_of_peer()'s backing
## store) is only ever populated by host_game()/join_game(), never in pure
## offline play. A **remote** request goes through the reliable RPC below,
## which _is_ validated (spec 3.4 "the host checks every intent before acting
## on it") -- a global restart/return affects every connected peer, so unlike
## a placement there is no per-sender outcome to report back, only "the host
## did it or it didn't".
##
## DECISION (net/MatchNet.gd, Bontago-1pi.13): any seated slot (not only the
## host's own player) may request a replay/return over the wire -- spec 3.4
## does not name a narrower "only the host's own local player" rule the way
## it names "the host checks ... that the slot matches" for a placement, and
## the results screen's own Replay/Return buttons are a natural thing for any
## player to click. _remote_may_request_match_flow() below is what actually
## authorizes a remote sender: unseated (no slot) and mid-match (not
## State.END) requests are both dropped on the host's floor. The host's own
## local call skips only the sender-slot check (see _match_flow_state_allows()
## below and its review-fix doc) -- it is validated on State.END exactly like
## a remote request, since a stray local call mid-match must not restart or
## abandon every other player's match either (Bontago-1pi.13 review fix).
func request_replay() -> void:
	if _session().is_host():
		if _match_flow_state_allows():
			_replay_current_match()
		return
	if NetFanout.can_send(multiplayer, _session()):
		rpc_id(Net.HOST_PEER_ID, &"net_request_replay")


## Results screen "Return to lobby": sends every peer back to State.LOBBY.
## Mirrors request_replay() above exactly.
func request_return_to_lobby() -> void:
	if _session().is_host():
		if _match_flow_state_allows():
			_authority().abort_match()
		return
	if NetFanout.can_send(multiplayer, _session()):
		rpc_id(Net.HOST_PEER_ID, &"net_request_return_to_lobby")


## The actual restart, shared by request_replay()'s trusted host-local branch
## and _handle_replay_request()'s validated remote branch below. Reads
## `_authority().config` (still the just-ended match's own sanitized
## duplicate -- MatchLifecycle only clears it on the *next* start_match()/
## abort_match()) rather than requiring a caller to have kept its own copy.
func _replay_current_match() -> void:
	var current: MatchConfig = _authority().config
	if current == null:
		return
	_authority().start_match(current)


## Bontago-1pi.13 review fix: the state half of both request_replay()'s and
## request_return_to_lobby()'s authorization, shared by their trusted
## host-local branch above (request_replay()'s own doc explains why a local
## call is still checked against this) and _remote_may_request_match_flow()
## below (a remote request's other check, sender-holds-a-slot, has no local
## equivalent -- the host's own process always "holds a slot" in the sense
## that matters here). A replay/return mid-PLAYING would restart or abandon
## every other player's match out from under them with no confirmation,
## which nothing in this package's brief asks for.
func _match_flow_state_allows() -> bool:
	return int(_authority().state()) == int(Match.State.END)


## Gate for a REMOTE net_request_* RPC only (see request_replay()'s own doc
## for why the host's local call above checks _match_flow_state_allows()
## directly instead): the sender must additionally hold a live slot -- an
## unseated peer (mid-handshake, a spectator) gets no say, exactly
## _handle_place_intent's own "no slot to count against" gate.
func _remote_may_request_match_flow(sender_peer_id: int) -> bool:
	if int(_session().slot_of_peer(sender_peer_id)) < 0:
		return false
	if _replay_pending.has(sender_peer_id):
		return false
	return _match_flow_state_allows()


## Host side of net_request_replay, split out (like _handle_place_intent) so
## a test can drive it with a manufactured sender id and no peer at all.
func _handle_replay_request(sender_peer_id: int) -> void:
	if not _session().is_host():
		return
	if not _remote_may_request_match_flow(sender_peer_id):
		return
	_replay_current_match()


## Host side of net_request_return_to_lobby, split out the same way.
func _handle_return_to_lobby_request(sender_peer_id: int) -> void:
	if not _session().is_host():
		return
	if not _remote_may_request_match_flow(sender_peer_id):
		return
	_authority().abort_match()


@rpc("any_peer", "call_remote", "reliable")
func net_request_replay() -> void:
	_handle_replay_request(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func net_request_return_to_lobby() -> void:
	_handle_return_to_lobby_request(multiplayer.get_remote_sender_id())


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
## `net_id` may be -1 (Bontago-mv0.1.7: BlockRegistry.debug_set_next_net_id /
## the allocator refusing past Quantize.NET_ID_MAX) when the body's own
## net_id allocation failed; that body lives and simulates on the host only,
## exactly as the allocator's own error says, so nothing goes out for it here
## either -- sending it anyway would build a permanent phantom client copy no
## despawn could ever address (bind_net_id() below also refuses it, but the
## body would already be parented under blocks_parent by then).
func replicate_spawn(block: Block, net_id: int) -> void:
	if not _session().is_host() or block == null:
		return
	if not Quantize.is_wire_id(net_id):
		_invalid_spawn_refusals += 1
		return
	_note_spawn(net_id)
	if not NetFanout.can_send(multiplayer, _session()):
		return
	var args: Array = _spawn_args(block, net_id)
	_broadcast(&"net_block_spawned", args)


## net_block_spawned's argument list for `block`: the one wire shape both a
## live spawn and a mid-match join replay use (Bontago-8or.11). owner_slot is
## the block's *current* owner, so a Paintball conversion (Bontago-22y.2)
## replays as the converted colour.
func _spawn_args(block: Block, net_id: int) -> Array:
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
	_spawned_net_ids.erase(net_id)
	if not NetFanout.can_send(multiplayer, _session()):
		return
	_broadcast(&"net_block_despawned", [net_id, reason])


## Host only, at NetConfig.raster_diff_hz. Sends the cells whose owner or
## state byte changed since the last diff, or a full compressed raster when
## more than NetConfig.raster_full_threshold_fraction of them changed or a
## client has just joined. Territory shares and capture progress ride along so
## the HUD costs no extra packet.
##
## Bontago-cmc.5: the analytic circle list rides along too, one
## core/net/CircleWire.gd payload per packet — always the *current* full
## list, never diffed like the raster, because it is already small (≤ 400
## circles, ~2.8 KB) and a circle that vanished (a tower toppled) has no
## "unchanged" cell to skip the way a raster byte does.
func replicate_territory() -> void:
	if not _session().is_host() or not NetFanout.can_send(multiplayer, _session()):
		return
	var raster: TerritoryRaster = _authority().raster()
	if raster == null:
		return
	var raw_owners: PackedByteArray = raster.owner_bytes()
	var raw_states: PackedByteArray = raster.state_bytes()
	# Bontago-1pi.11.23: unchanged bytes are exactly the changed.size() == 0
	# return below, reached without the per-cell loop or the copies.
	if (
		not _force_full_raster
		and raw_owners.size() == _last_owner_bytes.size()
		and raw_owners == _last_owner_bytes
		and raw_states == _last_state_bytes
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
		if changed.size() == 0:
			return
		full = float(changed.size()) / float(count) > config.raster_full_threshold_fraction

	var payload: PackedByteArray = (
		_encode_raster_full(owners, states) if full else _encode_raster_diff(changed, owners, states)
	)
	_last_owner_bytes = owners
	_last_state_bytes = states
	_force_full_raster = false

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
## (_on_placement_rejected, _on_placement_relocated; Bontago-1pi.52).
func replicate_match_event(event: StringName, args: Array) -> void:
	if not _session().is_host():
		return
	replicated_event_counts[event] = int(replicated_event_counts.get(event, 0)) + 1
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
	match_starts_replicated += 1
	_force_full_raster = true
	if not NetFanout.can_send(multiplayer, _session()):
		return
	_broadcast(&"net_match_start", [match_config.to_dict(), _roster(), 0])


## Host only (Bontago-t8x.4). Tells every client the host just pressed Start,
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
	return int(_intents_sent.get(slot_id, 0))


func intents_accepted(slot_id: int) -> int:
	return int(_intents_accepted.get(slot_id, 0))


func intents_refused(slot_id: int) -> int:
	return int(_intents_refused.get(slot_id, 0))


## Blocks the host dropped for `slot_id` because its feed timer ran out
## (spec 2.5). Never an intent: no client sends one.
func auto_drops(slot_id: int) -> int:
	return int(_auto_drops.get(slot_id, 0))


## Cursor updates from `slot_id`'s peer the host dropped as malformed.
func cursors_refused(slot_id: int) -> int:
	return int(_cursors_refused.get(slot_id, 0))


## net_ids this instance has seen spawned. A duplicate id is a hard failure.
func replicated_block_count() -> int:
	return _spawned_net_ids.size()


## net_ids that arrived twice. Must be 0; the harness asserts it.
func duplicate_net_id_count() -> int:
	return _duplicate_net_ids


## Test-only; see _invalid_spawn_refusals.
func invalid_spawn_refusal_count() -> int:
	return _invalid_spawn_refusals


## Drops every counter and cursor. Called when a match starts or ends.
func reset_counters() -> void:
	_cat_send_accum = 0.0
	_cat_target_last_send = -1.0
	_gift_wire_phases.clear()
	_gift_spawn_notified.clear()
	_intents_sent.clear()
	_intents_accepted.clear()
	_intents_refused.clear()
	_auto_drops.clear()
	_cursors_refused.clear()
	_spawned_net_ids.clear()
	_duplicate_net_ids = 0
	_invalid_spawn_refusals = 0
	_cursors.clear()
	_last_owner_bytes = PackedByteArray()
	_last_state_bytes = PackedByteArray()
	_force_full_raster = true
	_capture_team = -1
	_capture_progress = 0.0
	# Bontago-8or.11: a (re)start is itself a full sync for every peer (the
	# broadcast net_match_start), so no replay is still owed an ack.
	_replay_pending.clear()
	_replay_age.clear()
	# Test-only instrumentation; bounded per match (review mv0.1.13).
	replicated_state_changes.clear()
	match_starts_replicated = 0
	replicated_dissolve_starts.clear()
	_glue_bond_counts.clear()


# --- Host-side intent handling ----------------------------------------------

## The one place an intent becomes a placement, whether it arrived inline from
## the host's own player or over the wire. Host only.
func _apply_intent(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> StringName:
	var reason: StringName = _authority().request_place(
		slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq
	)
	var consumed: bool = _consumed_a_block(reason, auto_drop)
	if auto_drop:
		if consumed:
			_bump(_auto_drops, slot_id)
	elif consumed:
		_bump(_intents_accepted, slot_id)
	else:
		_bump(_intents_refused, slot_id)
	return reason


## _apply_intent()'s own twin for a throw, whether it arrived inline from the
## host's own player or over the wire. Host only. A throw is never an
## auto-drop (see submit_throw()'s own comment), so _consumed_a_block() is
## always called with auto_drop == false -- only REASON_OK ever spends the
## block (MatchPlacement.request_throw() never burns a refused throw).
func _apply_throw_intent(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> StringName:
	var reason: StringName = _authority().request_throw(
		slot_id, origin, orientation_index, free_quat, velocity, feed_seq
	)
	if _consumed_a_block(reason, false):
		_bump(_intents_accepted, slot_id)
	else:
		_bump(_intents_refused, slot_id)
	return reason


## Whether an outcome spent the slot's held block. Two reasons always mean the
## intent never reached the field: the slot had nothing to place (an empty
## feed, an eliminated slot, a stale feed_seq — all REASON_NO_BLOCK) and it
## was not its turn in hot-seat.
##
## Bontago-mv0.24 (owner test 2026-09-22): every other reason used to mean the
## block was consumed regardless, because spec 2.2 threw a rejected block off
## the map rather than handing it back. That is still true for an auto-drop
## (a forced release always lands somewhere, relocated or burned), but a
## manual (auto_drop == false) refusal now spends nothing at all
## (MatchPlacement.request_place()'s own DECISION) — only REASON_OK consumes
## for a manual release, so `auto_drop` has to be part of this decision now,
## not just the reason.
static func _consumed_a_block(reason: StringName, auto_drop: bool) -> bool:
	if reason == PlacementRules.REASON_NO_BLOCK or reason == PlacementRules.REASON_NOT_YOUR_TURN:
		return false
	return auto_drop or reason == PlacementRules.REASON_OK


## Bontago-1pi.18.2: the use_gift_slot intent, host or client. The client only
## sends the request; the host validates it (sender owns the slot, slot holds a
## gift, state, no gift already in hand) and the result arrives as the normal
## feed event. Returns whether the request was applied (host) or sent (client).
func submit_use_gift_slot(slot_id: int) -> bool:
	if _session().is_host():
		return bool(_authority().request_use_gift_slot(slot_id))
	if not NetFanout.can_send(multiplayer, _session()):
		return false
	rpc_id(Net.HOST_PEER_ID, &"net_request_use_gift_slot", slot_id)
	return true


## Host side of net_request_use_gift_slot, split out so a test can drive it
## with a manufactured sender id.
func _handle_use_gift_slot_intent(sender_peer_id: int, slot_id: int) -> bool:
	if not _session().is_host():
		return false
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0 or sender_slot != slot_id or _replay_pending.has(sender_peer_id):
		return false
	return bool(_authority().request_use_gift_slot(slot_id))


## Host side of net_request_place, split out so a test can drive it with a
## manufactured sender id and no peer at all.
func _handle_place_intent(
	sender_peer_id: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	feed_seq: int
) -> void:
	if not _session().is_host():
		return
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0:
		# A peer with no slot — mid-handshake, a spectator, or one that has
		# already gone — gets no say at all, and is not counted: it has no
		# slot to count against.
		return
	_bump(_intents_sent, sender_slot)
	if _replay_pending.has(sender_peer_id):
		# Bontago-8or.11: a mid-match joiner's world is not built until it has
		# acknowledged its replay. Refused (counted and echoed, like every
		# other refusal, so the harness identities hold and its ghost unlocks)
		# rather than acted on.
		intents_refused_before_replay_ack += 1
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return
	if sender_slot != slot_id:
		# Spec 3.4: the host checks "that the slot matches". A peer may only
		# ever act for its own slot; the claimed slot_id is never trusted.
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NOT_YOUR_TURN)
		return
	if feed_seq < 0:
		# Match.request_place() reads a negative feed_seq as "don't check" —
		# the sentinel M2's local call sites and the host's own timer rely on.
		# From the wire it would switch off docs/M3a_PLAN.md's "never
		# duplicated" defence (1) for whoever sends it, so a remote intent has
		# to quote the sequence it was actually issued.
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return
	if not _pose_is_acceptable(origin, orientation_index, free_quat):
		# Not a rule violation — a real ghost cannot produce such a pose — so
		# the block is neither burned (spec 2.2 is for releases on a spot) nor
		# consumed; the sender is told so its ghost unlocks and it may retry.
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return
	# auto_drop is never taken from the wire: it grants the relocation
	# privilege of spec 2.5, so only the host's own timer may set it.
	_reject_replied_slot = -1
	var reason: StringName = _apply_intent(slot_id, origin, orientation_index, free_quat, false, feed_seq)
	if not _consumed_a_block(reason, false):
		# Nothing was burned. Match announces most refusals itself (and
		# _on_placement_rejected already told the sender); for the rest,
		# tell the sender anyway so its ghost unlocks now instead of
		# waiting out NetConfig.intent_ack_timeout.
		_reply_reject_once(sender_peer_id, slot_id, reason)


## Host side of net_request_throw, split out (like _handle_place_intent) so a
## test can drive it with a manufactured sender id and no peer at all. Mirrors
## _handle_place_intent() check-for-check (sender-owns-slot, feed_seq, pose)
## with one addition: `velocity.is_finite()`. The host does not also bound
## its length here -- MatchPlacement.request_throw() always clamps to
## SpecialTuning.throw_max_speed rather than ever refusing on speed (spec 3.4:
## "the host clamps velocity to throw_max_speed"), so a second length check at
## this boundary would only reject a pose the authority is happy to clamp and
## use anyway.
func _handle_throw_intent(
	sender_peer_id: int,
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int
) -> void:
	if not _session().is_host():
		return
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0:
		return
	_bump(_intents_sent, sender_slot)
	if _replay_pending.has(sender_peer_id):
		intents_refused_before_replay_ack += 1
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return
	if sender_slot != slot_id:
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NOT_YOUR_TURN)
		return
	if feed_seq < 0:
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return
	if not _pose_is_acceptable(origin, orientation_index, free_quat) or not velocity.is_finite():
		# A non-finite velocity is this function's own wire-boundary check, on
		# top of _pose_is_acceptable()'s existing origin/orientation/free_quat
		# gate -- neither is a rule violation, so nothing is burned or
		# consumed; the sender is told so its ghost unlocks and it may retry,
		# exactly like a malformed placement pose.
		_refuse_intent(sender_peer_id, sender_slot, PlacementRules.REASON_NO_BLOCK)
		return
	_reject_replied_slot = -1
	var reason: StringName = _apply_throw_intent(
		slot_id, origin, orientation_index, free_quat, velocity, feed_seq
	)
	if not _consumed_a_block(reason, false):
		# MatchPlacement.request_throw() emits Events.placement_rejected for
		# an off-disk/hole/goal-zone refusal, which _on_placement_rejected
		# already sent to the sender alone; the refusals it does not announce
		# (a stale feed_seq, a lock, no held special) still need this targeted
		# reply so the *sender's own* ghost unlocks now instead of waiting out
		# NetConfig.intent_ack_timeout, exactly like _handle_place_intent's own
		# tail.
		_reply_reject_once(sender_peer_id, slot_id, reason)


## Host side of net_update_cursor, split out (like _handle_place_intent) so a
## test can drive it with a manufactured sender id and no peer at all. What is
## stored here is what spec 2.5's auto-drop fires from when the slot's timer
## expires (_on_feed_timer_expired), so it is an input boundary too.
func _handle_cursor_update(
	sender_peer_id: int, slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> void:
	if not _session().is_host():
		return
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0 or sender_slot != slot_id:
		return
	if _replay_pending.has(sender_peer_id):
		# Bontago-8or.11: a cursor is what the host auto-drops from, so an
		# unreplayed peer's pose (formed against no world) is not stored.
		return
	if not _pose_is_acceptable(origin, orientation_index, free_quat):
		# DECISION (net/MatchNet.gd): a malformed cursor is dropped, not
		# clamped. Clamping would invent a pose the player never had and then
		# auto-drop from it; dropping keeps the last well-formed cursor (or,
		# if there never was one, Match.default_ghost_origin's home flag), and
		# the next honest update at NetConfig.cursor_hz replaces it anyway.
		# Nothing is rebroadcast, so other clients' RemoteCursors never see it.
		_bump(_cursors_refused, sender_slot)
		return
	_store_cursor(slot_id, origin, orientation_index, free_quat)
	Events.remote_cursor_updated.emit(slot_id, origin, orientation_index, free_quat)
	if NetFanout.can_send(multiplayer, _session()):
		_broadcast(&"net_cursor", [slot_id, origin, orientation_index, free_quat])


## Every check the wire gets that Match does not: the pose must be one the
## authority can evaluate (Match.is_pose_well_formed: finite origin, finite
## unit free quaternion, orientation index inside BlockOrientations' table) and
## its height must lie inside the volume snapshots quantize positions into.
##
## DECISION (net/MatchNet.gd): the height band is NetConfig.pos_min_y ..
## pos_max_y, the same numbers core/net/Quantize.gd packs `global_position.y`
## with, judged on the world-space origin exactly as SnapshotSync does. A
## block spawned outside it could not be replicated to anyone, so refusing it
## changes nothing a legitimate client can do: the ghost sits at most
## PhysicsTuning.hover_height + GhostTuning.hover_manual_max (3.3 m) above the
## disk or a tower, and pos_max_y is documented as bracketing the tallest
## reachable tower. No new tunable; X/Z are left to territory validation,
## which already burns an off-disk release (spec 2.2).
func _pose_is_acceptable(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	if not bool(_authority().is_pose_well_formed(origin, orientation_index, free_quat)):
		return false
	return origin.y >= config.pos_min_y and origin.y <= config.pos_max_y


## M4 P1b wire safety for EVENT_GIFT_SPAWNED, following _pose_is_acceptable's
## own pattern: a malformed or out-of-disk position from a bad or ancient build
## is dropped rather than trusted, since a client only ever uses this position
## to place a visual and to compute the cell it later frees for.
## Records a gift's wire phase; refuses an out-of-range value (returns false).
func _set_gift_wire_phase(gift_id: int, phase: int) -> bool:
	if gift_id < 0 or not MatchGifts.is_valid_wire_phase(phase):
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


## M4 P2b wire safety, reused by EVENT_SPECIAL_TRIGGERED's def_id (M4 P2c-ii)
## as well as EVENT_GIFT_CLAIMED's third argument: the id is trusted only if
## it is shaped like one of ours -- non-empty, at most 32 characters,
## [A-Za-z0-9_] only -- following _gift_wire_ok's own "a malformed or ancient
## payload is dropped, not trusted" pattern. This is a syntactic check only;
## _gift_special_id_wire_ok() below layers real roster membership on top of it
## for EVENT_GIFT_CLAIMED specifically (a client only ever queues this id and,
## later, hands it to SpecialBehavior.bind(), so an unchecked string could
## otherwise reach either unfiltered) -- EVENT_SPECIAL_TRIGGERED does not need
## the same layer (see _known_special_ids()'s own doc comment for why). No
## RegEx dependency (none exists elsewhere in this codebase) -- a plain
## character scan is enough for an id this short.
func _special_id_wire_ok(special_id: String) -> bool:
	if special_id.is_empty() or special_id.length() > 32:
		return false
	for i: int in range(special_id.length()):
		var c: int = special_id.unicode_at(i)
		var is_upper: bool = c >= 65 and c <= 90
		var is_lower: bool = c >= 97 and c <= 122
		var is_digit: bool = c >= 48 and c <= 57
		var is_underscore: bool = c == 95
		if not (is_upper or is_lower or is_digit or is_underscore):
			return false
	return true


## String(SpecialDef.id) -> true for every SpecialDef in SpecialDef.
## load_all_specials(), built once per instance and cached (see
## _special_ids_by_id's own field comment). Read by _gift_special_id_wire_ok()
## below; not by EVENT_SPECIAL_TRIGGERED's dispatch, which only re-checks
## _special_id_wire_ok()'s syntactic shape (docs/M4_P2_PACKAGES.md P2c-ii
## brief) -- a special already bound and triggered on the host is by
## construction a real roster id, so nothing here needs to reject one a
## client's own (possibly stale) roster cache does not recognise.
func _known_special_ids() -> Dictionary:
	if not _special_ids_cached:
		_special_ids_by_id = {}
		if _special_ids_override != null:
			for raw_id: Variant in (_special_ids_override as Array):
				_special_ids_by_id[String(raw_id)] = true
		else:
			for def: SpecialDef in SpecialDef.load_all_specials():
				_special_ids_by_id[String(def.id)] = true
		_special_ids_cached = true
	return _special_ids_by_id


## M4 P2c-ii tightening of _special_id_wire_ok() for EVENT_GIFT_CLAIMED only
## (orchestrator amendment 1's "P2c tightens it to roster membership"): a
## claimed special id is trusted only if it is shaped like one of ours AND is
## either MatchGifts.PENDING_SPECIAL_ID (the default drawer's placeholder,
## always valid regardless of roster -- see MatchPlacement._attach_pending_
## special()'s own "safe default" handling of it) or actually a member of the
## running roster. An empty res://config/specials/ (P3-P5 not landed yet)
## therefore lets only the placeholder through, exactly as it should: there is
## no real special for any other id to name yet.
func _gift_special_id_wire_ok(special_id: String) -> bool:
	if not _special_id_wire_ok(special_id):
		return false
	if special_id == String(MatchGifts.PENDING_SPECIAL_ID):
		return true
	return _known_special_ids().has(special_id)


## A remote intent the host will not act on: counted against the sender's own
## slot so the harness identity accepted + refused == sent still holds, and
## echoed back so the sender's ghost unlocks now instead of waiting out
## NetConfig.intent_ack_timeout.
func _refuse_intent(sender_peer_id: int, sender_slot: int, reason: StringName) -> void:
	_bump(_intents_refused, sender_slot)
	_reject_to_peer(sender_peer_id, sender_slot, reason)


func _reject_to_peer(peer_id: int, slot_id: int, reason: StringName) -> void:
	reject_replies_by_peer[peer_id] = int(reject_replies_by_peer.get(peer_id, 0)) + 1
	last_reject_reply = [peer_id, slot_id, reason]
	if not NetFanout.can_send(multiplayer, _session()) or not multiplayer.get_peers().has(peer_id):
		return
	rpc_id(peer_id, &"net_match_event", EVENT_PLACEMENT_REJECTED, [slot_id, reason])


## _reject_to_peer() unless _on_placement_rejected() already sent this slot's
## refusal while the intent was being applied (one reply per refused intent).
func _reply_reject_once(peer_id: int, slot_id: int, reason: StringName) -> void:
	if _reject_replied_slot == slot_id:
		_reject_replied_slot = -1
		return
	_reject_to_peer(peer_id, slot_id, reason)


func _bump(counter: Dictionary, slot_id: int) -> void:
	counter[slot_id] = int(counter.get(slot_id, 0)) + 1


func _note_spawn(net_id: int) -> void:
	if net_id < 0:
		return
	if _spawned_net_ids.has(net_id):
		_duplicate_net_ids += 1
		return
	_spawned_net_ids[net_id] = true


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
	# DECISION (fca.36.3): impacts clear on LOBBY|LOADING only; END is excluded from
	# is_resetting so impacts already queued still play into the results screen.
	if MatchAutoload.is_resetting(to_state) and to_state != Match.State.END:
		# World teardown / rebuild: nothing still waiting may play into it.
		_reset_impacts()
	if not _session().is_host():
		return
	if to_state == Match.State.LOADING:
		# The lobby may call replicate_match_start() itself; this is the
		# belt-and-braces path, and the flag makes the pair idempotent.
		_match_start_sent = false
		reset_counters()
		replicate_match_start(_authority().config)
	elif to_state == Match.State.LOBBY:
		_match_start_sent = false
	# Bontago-mv0.1.13: the LOBBY/LOADING/COUNTDOWN start_match() produces
	# internally (see MatchLifecycle._starting's own doc) is fully replayed on
	# a client by net_match_start alone; replicating them again here would
	# race that local replay and turn into spurious re-emits on the other
	# side. Every OTHER state change -- reached outside a start_match() call,
	# such as PLAYING->END from a win -- still replicates normally.
	#
	# DECISION (net/MatchNet.gd, Bontago-mv0.1.13): reaches _authority()'s own
	# _lifecycle directly rather than through a new Match.is_starting_match()
	# forward -- autoload/Match.gd is not one of this package's owned files.
	# _authority() is always either the real Match (which always has a
	# _lifecycle by the time any match flow can run, built in Match._ready())
	# or a test double; nothing in the current test suite ever hands MatchNet
	# a _match_provider without one.
	if _authority()._lifecycle.is_starting_match():
		return
	replicated_state_changes.append(to_state)
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
## Bontago-mv0.10 follow-up: also rides feed_time_left()/is_release_locked()
## for this slot, read at this exact moment -- Match's own _consume_and_
## refeed()/_begin_playing() update both before calling _issue_next_block(),
## which is what emits Events.feed_block_issued and triggers this handler
## synchronously, so "this exact moment" already reflects the placement that
## just happened. Without them a client's mirror always assumed a fresh
## config.block_timer-length interval, which is wrong on an early release
## (spec 2.4 "does not restart the interval") and never showed the ghost
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


## Spec 2.5's auto-drop is [ORIGINAL] and must keep dropping "from its current
## ghost position", so it must never make a round trip: a request sent to a
## remote player and back on timer expiry could be lost or arrive twice. The
## host therefore drops for every slot it does not itself control, from the
## last update_cursor it received for that slot — at NetConfig.cursor_hz that
## is at worst 67 ms stale, and closest_valid_origin() relocates from there
## anyway. A slot this instance controls locally (every slot offline, which is
## all of M2's hot-seat) is left to its own PlayerController, whose ghost is
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


## Bontago-1pi.40 (follow-up to 1pi.33, owner playtest 2026-10-03: the first
## block "loads inside the home beacon"): where the host auto-drops a slot it
## has never heard a cursor from. Match.default_ghost_origin() is the home flag
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
## clear of the beacon (review 1pi.40).
func _afk_fallback_origin(slot_id: int) -> Vector3:
	var home: Vector3 = _authority().default_ghost_origin(slot_id)
	return home + Vector3.UP * _ghost_tuning.home_spawn_pivot_height(_beacon_visuals, _physics_tuning)


func _on_qol_feed_changed(slot_id: int, backlog: int, paused: bool) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_QOL_FEED, [slot_id, backlog, paused])


func _on_gift_slot_changed(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_SLOT, [slot_id, contents, activated, carrier_id])


## Bontago-1pi.52 (owner playtest: "the host could hear my block rejected
## sound"): a refusal is feedback for the refused player alone. It used to be
## broadcast to every peer, so the host's own bus (and every other client's)
## saw each client's refusals; now it goes only to the peer that holds the slot
## -- never the host's own seat, a bot's or a vacated one, which have no remote
## peer to tell. The host's own seat reacts to Match's local emit directly.
func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	if not _session().is_host():
		return
	var owner_peer: int = _remote_peer_of_slot(slot_id)
	if owner_peer < 0:
		return
	_reject_to_peer(owner_peer, slot_id, reason)
	# The intent handler that is applying this refusal must not send it again.
	_reject_replied_slot = slot_id


## The remote peer that holds `slot_id`, or -1 when nobody remote does: the
## listen-server's own seat, a bot, an empty or vacated seat, a bad slot.
func _remote_peer_of_slot(slot_id: int) -> int:
	if slot_id < 0 or bool(_session().is_local_slot(slot_id)):
		return -1
	var peer_id: int = int(_session().peer_of_slot(slot_id))
	if peer_id <= 0 or peer_id == Net.HOST_PEER_ID:
		return -1
	return peer_id


## Bontago-mv0.24: mirrors an auto-drop's relocation to the owning client so its
## cursor and camera can jump to where the block landed.
##
## Bontago-1pi.52 (audit after the refusal fix): that jump is the owning seat's
## own feedback, so it goes to that peer alone, exactly like a refusal, instead
## of to every client that would only ignore it (PlayerController and the HUD
## drop a slot that is not theirs). Never the host's own seat (it reacts to
## Match's local emit), a bot's, or a vacated one: no remote peer to tell.
func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	if not _session().is_host():
		return
	var owner_peer: int = _remote_peer_of_slot(slot_id)
	if owner_peer < 0:
		return
	relocate_replies_by_peer[owner_peer] = int(relocate_replies_by_peer.get(owner_peer, 0)) + 1
	last_relocate_reply = [owner_peer, slot_id, point]
	if not NetFanout.can_send(multiplayer, _session()) or not multiplayer.get_peers().has(owner_peer):
		return
	rpc_id(owner_peer, &"net_match_event", EVENT_PLACEMENT_RELOCATED, [slot_id, point])


func _on_player_eliminated(slot_id: int, team_id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_PLAYER_ELIMINATED, [slot_id, team_id])


## Host only: the objective's state changed. A client's own apply re-emits the
## same signal, hence the host guard (no echo, and a client never replicates).
func _on_mode_state_changed(state: Dictionary) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_MODE_STATE, [state])


func _on_match_won(team_id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_MATCH_WON, [team_id])


## Bontago-1pi.13: mirrors MatchLifecycle._finish_match()'s own
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
		var next_shape: BlockShape = _authority().next_shape(slot_id)
		replicate_match_event(EVENT_GIFT_CLAIMED, [gift_id, slot_id, special_id, next_shape.id if next_shape != null else &""])


func _on_gift_expired(gift_id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GIFT_EXPIRED, [gift_id])


## M4 P2c-ii: autoload/match/MatchPlacement._on_special_behavior_triggered()
## emits Events.special_triggered only on the host (game/specials/
## SpecialBehavior.gd only ever attaches there -- see that file's own header
## and orchestrator amendment 2), so this mirrors it to every client exactly
## like _on_gift_spawned above.
func _on_special_triggered(net_id: int, def_id: StringName, position: Vector3, chain_depth: int) -> void:
	if _session().is_host():
		# Bontago-1pi.18.1 (QoL 1): a special freezes block timers for a while.
		var feed: Variant = _authority().get("_feed")
		if feed != null:
			feed.note_special_triggered()
		replicate_match_event(EVENT_SPECIAL_TRIGGERED, [net_id, def_id, position, chain_depth])


## Bontago-1en.21: mirrors autoload/match/MatchGifts.gd's pop_pending_special()
## emit to every client -- a client never pops its own queue (it only ever
## mirrors the host's, via apply_replicated_special_consumed() below), so this
## dispatch is the only place a client ever learns a special was spent.
func _on_special_consumed(slot_id: int, special_id: StringName) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_SPECIAL_CONSUMED, [slot_id, special_id])


func _on_glue_charges_changed(slot_id: int, charges: int, revision: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_GLUE_CHARGES, [slot_id, charges, revision])


## Host: counts bonds per block and replicates only the 0 <-> 1 transitions.
func _on_glue_bond_changed(body_a: Node, body_b: Node, formed: bool) -> void:
	if not _session().is_host():
		return
	for body: Node in [body_a, body_b]:
		var block: Block = body as Block
		if block == null or not Quantize.is_wire_id(block.net_id):
			continue
		var before: int = int(_glue_bond_counts.get(block.net_id, 0))
		var after: int = maxi(before + (1 if formed else -1), 0)
		if after > 0:
			_glue_bond_counts[block.net_id] = after
		else:
			_glue_bond_counts.erase(block.net_id)
		if (before > 0) != (after > 0):
			HoneyCoat.set_coated(block, after > 0)
			replicate_match_event(EVENT_BLOCK_GLUED, [block.net_id, after > 0])


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
	var typed: Block = block as Block
	if typed != null:
		_glue_bond_counts.erase(typed.net_id)
		replicate_despawn(typed.net_id, reason)


## Host: mirrors a dissolve start so clients can play the same fade. A body
## without a wire id (net_id allocation failed) never reached a client.
func _on_block_dissolve_started(_block: RigidBody3D, net_id: int, _duration_s: float) -> void:
	if not _session().is_host() or not Quantize.is_wire_id(net_id):
		return
	replicated_dissolve_starts.append(net_id)
	replicate_match_event(EVENT_BLOCK_DISSOLVE_STARTED, [net_id])


func _on_cat_started(id: int, slot_id: int, position: Vector3, duration: float) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_CAT_STARTED, [id, slot_id, position, duration])


func _on_cat_ended(id: int) -> void:
	if _session().is_host():
		replicate_match_event(EVENT_CAT_ENDED, [id])


# --- Replicated block impacts (Bontago-1pi.55) ------------------------------
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
	if not capture_impacts and not _impact_audience():
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
	if capture_impacts:
		impact_batches.append(packet)
	if NetFanout.can_send(multiplayer, _session()):
		for peer_id: int in multiplayer.get_peers():
			# A mid-match joiner still loading its world replay hears nothing
			# yet; impacts are never part of that replay either.
			if not _replay_pending.has(peer_id) and not _peer_is_disconnecting(peer_id):
				rpc_id(peer_id, &"net_block_impacts", packet)
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
		impact_batches_rejected += 1
		return
	# The wire's event_count byte: how many the host claimed, so events decode
	# skipped (bad speed/height, past the per-batch cap) show up in the counter.
	impact_events_dropped += maxi(packet.decode_u8(1) - events.size(), 0)
	var delay_ms: float = _impact_playback_delay_ms()
	var queue_cap: int = config.impact_max_per_second + config.impact_max_per_batch
	var budget: int = _impact_client_budget(now_ms)
	if events.size() > budget:
		impact_events_dropped += events.size() - budget
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


func pending_impact_count() -> int:
	return _impact_queue.size()


func _impact_playback_delay_ms() -> float:
	if impact_delay_override_ms >= 0.0:
		return impact_delay_override_ms
	if SnapshotSync.is_running():
		return SnapshotSync.interpolation_delay_ms()
	return 0.0


## The same pair game/Block.gd emits on the host, so Sfx (thud), CameraRig
## (shake), Rumble, BlockEffectsManager (dust) and PerchingBirds need nothing
## network-aware.
func _emit_impact(speed: float, position: Vector3) -> void:
	impacts_emitted += 1
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
	_replay_pending.erase(peer_id)
	_replay_age.erase(peer_id)
	if slot_id >= 0:
		_authority().on_peer_left(slot_id)


## Bontago-8or.11: a peer was seated (Net emits this after it has already sent
## the joiner its join-accepted and the roster). In the lobby that is all:
## the broadcast net_match_start will carry the world. Mid-match the host
## owes this peer the whole world, as one ordered replay -- see
## _replay_world_to().
func _on_net_peer_joined(peer_id: int, slot_id: int, _player_name: String) -> void:
	if not _session().is_host():
		return
	if slot_id >= 0:
		# Inside the disconnect grace: resume the slot's feed with a full
		# timer (MatchLifecycle.on_peer_rejoined; a no-op otherwise).
		_authority().on_peer_rejoined(slot_id)
		# Whoever sat here before (or this peer's own old connection) left a
		# ghost the host would auto-drop from; the joiner has no pose yet.
		_cursors.erase(slot_id)
	if bool(_session().is_offline()) or not is_match_live() or _replay_pending.has(peer_id):
		return
	_replay_world_to(peer_id)


## Whether a late-join world replay is being applied here (client only). While
## true, Events.world_replay_changed(true) has been emitted and not yet undone.
func is_replaying_world() -> bool:
	return _replaying_id > 0


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
## joiner is admitted into and gets a replay for (spec 3.7).
func is_match_live() -> bool:
	var state: int = int(_authority().state())
	return MatchAutoload.is_replicating(state)


# --- Mid-match join and reconnect (Bontago-8or.11, spec 3.4) -----------------

## Host only, installed into Net's seat policy by game/Main.gd: the lowest open
## human seat for a new mid-match joiner, or -1 (spectate). Open means a human
## (not bot) slot that is still alive, held by no peer, and not reserved by a
## departed peer inside its disconnect grace.
##
## DECISION (Bontago-8or.11): a joiner never takes over a bot seat -- the bot
## would have to be torn down mid-match and spec 2.9 does not ask for it;
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


## Host only, installed into Net's seat policy by game/Main.gd: whether a
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


## Bontago-8or.11 (review LOW4): a joiner that never acks its replay would stay
## intent-gated with its cursors dropped forever. Past
## config.replay_ack_timeout the host drops it cleanly.
## DECISION: drop, not retry. A second replay would re-send spawns for bodies
## the first one may already have created; a peer that cannot ack within the
## timeout is not going to play, and it can rejoin (its reservation applies).
func _tick_replay_timeouts(delta: float) -> void:
	if _replay_pending.is_empty():
		return
	var expired: Array[int] = []
	for peer_id: int in _replay_pending.keys():
		var age: float = float(_replay_age.get(peer_id, 0.0)) + delta
		_replay_age[peer_id] = age
		if age >= config.replay_ack_timeout:
			expired.append(peer_id)
	for peer_id: int in expired:
		replays_timed_out += 1
		_replay_pending.erase(peer_id)
		_replay_age.erase(peer_id)
		var session: Variant = _session()
		if session != null and session.has_method(&"kick_peer"):
			session.kick_peer(peer_id, Net.LeaveReason.TIMEOUT)


## Whether `peer_id` still owes the host an ack for its world replay.
func replay_pending_for(peer_id: int) -> bool:
	return _replay_pending.has(peer_id)


## Bontago-1pi.57: a peer the host is kicking stays in get_peers() until its
## disconnect completes, and a send to it logs an engine error (see
## Net._disconnecting_peers). A test session without the query never has one.
func _peer_is_disconnecting(peer_id: int) -> bool:
	var session: Variant = _session()
	return session.has_method(&"is_peer_disconnecting") and bool(session.is_peer_disconnecting(peer_id))


## Host only. Spec 3.4 "Late join / reconnect: Send the full world state in
## chunks: all bodies, the territory raster, and match state." Every message
## is a reliable rpc_id() on the default channel, so the joiner receives them
## in exactly this order, after the join-accepted and roster Net already
## sent, and before any later broadcast:
##
##   1. config + roster      net_match_start (the joiner builds its world)
##   2. world                one net_block_spawned per body -- the same wire
##                           shape as replicate_spawn() -- then any hole
##                           dissolves in progress
##   3. territory            one full keyframe (see _territory_replay_args())
##   4. derived state        match state, clock, mode objective, eliminations,
##                           turn, every slot's feed and gifts, glue charges,
##                           gift crates, the cat
##   (WeatherNet/SnowNet answer the same Events.net_peer_joined after this
##   node, so the weather state follows.)
##   5. net_replay_end       deferred to the end of the frame; the joiner
##                           answers net_replay_ack, which lifts the intent
##                           gate and asks SnapshotSync for a full snapshot.
##
## Each piece is the state *at this instant*, built synchronously, so every
## broadcast the joiner dropped before net_match_start (see
## _awaiting_match_start) is already folded in, and every broadcast after it
## applies on top in order.
##
## DECISION (Bontago-8or.11, owner decision Bontago-ahr.3 still open): the
## match clock does NOT pause while a player joins mid-match. Spec 3.4 only
## pauses it for lobby-mode joins; the open decision can add a pause later in
## MatchLifecycle without changing this protocol.
func _replay_world_to(peer_id: int) -> void:
	var replay_id: int = _next_replay_id
	_next_replay_id += 1
	_replay_pending[peer_id] = replay_id
	_replay_age[peer_id] = 0.0
	replays_started += 1
	for message: Array in build_world_replay(replay_id):
		_send_replay(peer_id, StringName(message[0]), message[1] as Array)
	call_deferred(&"_finish_replay", peer_id, replay_id)


## Sends the end marker unless the peer left (or a restart cleared the
## pending replay) in the meantime.
func _finish_replay(peer_id: int, replay_id: int) -> void:
	if int(_replay_pending.get(peer_id, -1)) != replay_id:
		return
	_send_replay(peer_id, &"net_replay_end", [replay_id])


func _send_replay(peer_id: int, method: StringName, args: Array) -> void:
	if capture_replay:
		replay_capture.append([peer_id, method, args])
		return
	if not NetFanout.can_send(multiplayer, _session()) or not multiplayer.get_peers().has(peer_id) or _peer_is_disconnecting(peer_id):
		return
	callv(&"rpc_id", [peer_id, method] + args)


## The ordered replay body (steps 1-4 of _replay_world_to()), as
## [method: StringName, args: Array] pairs. Public so a test can apply it to
## a client mirror without a peer.
##
## `replay_id` > 0 (the real send) marks the opening net_match_start as a replay
## so the joiner mutes one-shot feedback until the matching net_replay_end; 0
## builds the body without the marker.
func build_world_replay(replay_id: int = 0) -> Array[Array]:
	var authority: Variant = _authority()
	var messages: Array[Array] = []
	var running: MatchConfig = authority.config
	if running == null:
		return messages
	var start_args: Array = [running.to_dict(), _roster()]
	if replay_id > 0:
		start_args.append(replay_id)
	messages.append([&"net_match_start", start_args])

	var registry: BlockRegistry = authority.registry()
	if registry != null:
		var blocks: Array[Block] = registry.all_blocks()
		blocks.sort_custom(func(a: Block, b: Block) -> bool: return a.net_id < b.net_id)
		var dissolving: Array[int] = []
		for block: Block in blocks:
			if not Quantize.is_wire_id(block.net_id):
				continue
			messages.append([&"net_block_spawned", _spawn_args(block, block.net_id)])
			if registry.hole_dissolver().is_dissolving(block):
				dissolving.append(block.net_id)
		for net_id: int in dissolving:
			messages.append(_event(EVENT_BLOCK_DISSOLVE_STARTED, [net_id]))
		# Freeze gift (Bontago-8or.2): the icy overlay is an event, not part of
		# the spawn args, so a joiner needs it after the block exists.
		for frozen_payload: Array in _frozen_overlay_snapshot():
			messages.append(_event(EVENT_BLOCK_FROZEN, frozen_payload))
		# Bontago-1pi.85.52: honey coat of currently glued blocks.
		var glued_ids: Array = _glue_bond_counts.keys()
		glued_ids.sort()
		for glued_id: int in glued_ids:
			messages.append(_event(EVENT_BLOCK_GLUED, [glued_id, true]))

	var territory: Array = _territory_replay_args()
	if not territory.is_empty():
		messages.append([&"net_territory", territory])

	var state: int = int(authority.state())
	if state == Match.State.COUNTDOWN:
		messages.append(_event(EVENT_COUNTDOWN, [int(ceil(float(authority.countdown_remaining())))]))
		# Bontago-1pi.42: the ready gate lives only through the countdown; sent after
		# net_match_start (whose start_match() resets the joiner's mirror), so the
		# joiner holds the host's current sets whatever it heard before.
		var gate_args: Array = authority._lifecycle.loading_gate_replay_args()
		if gate_args.size() == 3:
			messages.append(_event(EVENT_LOADING_GATE, gate_args))
	elif MatchAutoload.is_live(state):
		# A client's own start_match() leaves it in COUNTDOWN; PLAYING is
		# replayed before SUDDEN_DEATH so its consumers see the order a
		# seated client saw.
		messages.append(_event(EVENT_STATE_CHANGED, [Match.State.PLAYING]))
		if state == Match.State.SUDDEN_DEATH:
			messages.append(_event(EVENT_STATE_CHANGED, [Match.State.SUDDEN_DEATH]))
	messages.append(_event(EVENT_MATCH_CLOCK, [float(authority.match_timer_left())]))

	var mode_snapshot: Dictionary = authority.mode_state_snapshot()
	if not mode_snapshot.is_empty():
		messages.append(_event(EVENT_MODE_STATE, [mode_snapshot]))

	var slot_count: int = int(authority.slot_count())
	for slot_id: int in range(slot_count):
		var seat: PlayerSlot = authority.slot(slot_id)
		if seat != null and not seat.home_flag_alive:
			messages.append(_event(EVENT_PLAYER_ELIMINATED, [slot_id, seat.team_id]))
	if int(authority.active_slot()) >= 0:
		messages.append(_event(EVENT_TURN_CHANGED, [int(authority.active_slot())]))
	for slot_id: int in range(slot_count):
		var slot_args: Array = _slot_replay_args(slot_id)
		if not slot_args.is_empty():
			messages.append(_event(EVENT_SLOT_REPLAY, slot_args))
	for payload: Array in _glue_rejoin_snapshot():
		messages.append(_event(EVENT_GLUE_CHARGES, payload))
	# Bontago-1pi.18.1: a late joiner's HUD mirror starts at zero/unpaused, so
	# replay each slot's non-default QoL state (nothing is sent with the toggles off).
	for slot_id: int in range(slot_count):
		var backlog: int = int(authority.qol_backlog_count(slot_id))
		var paused: bool = bool(authority.qol_timer_paused(slot_id))
		if backlog > 0 or paused:
			messages.append(_event(EVENT_QOL_FEED, [slot_id, backlog, paused]))

	for slot_id: int in range(slot_count):
		var slotted: Array[StringName] = authority.gift_slot_contents(slot_id)
		if not slotted.is_empty():
			messages.append(_event(EVENT_GIFT_SLOT, [slot_id, slotted, &"", &""]))

	for gift: Dictionary in authority.gift_states():
		var gift_id: int = int(gift["id"])
		if int(gift["phase"]) == MatchGifts.FALLING:
			messages.append(_event(EVENT_GIFT_FLIGHT, [gift_id, gift["origin"], gift["landing"]]))
		else:
			messages.append(_event(EVENT_GIFT_SPAWNED, [gift_id, gift["position"]]))

	var cat: CatController = authority.active_cat()
	if cat != null:
		messages.append(_event(EVENT_CAT_STARTED,
			[cat.activation_id, cat.owner_slot, cat.global_position, cat.time_left]))
	return messages


func _event(event: StringName, args: Array) -> Array:
	return [&"net_match_event", [event, args]]


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
	if args.size() != 8 or not args[0] is int or not args[3] is int or not args[5] is bool:
		return
	for index: int in [1, 2, 6, 7]:
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
	if held_special != &"":
		authority.apply_replicated_gift_claimed(-1, slot_id, held_special)
		authority._feed.apply_replicated_next_gift(slot_id, held_id)
	authority.apply_replicated_feed(slot_id, held_id, next_id, feed_seq, time_left, locked)
	if next_special != &"":
		authority.apply_replicated_gift_claimed(-1, slot_id, next_special)
		authority._feed.apply_replicated_next_gift(slot_id, next_id)
	Events.feed_block_issued.emit(slot_id, held_id, next_id)


## Host side of net_replay_ack, split out (like _handle_place_intent) so a
## test can drive it with a manufactured sender id. Only the id the host
## actually sent this peer counts; a stale or forged ack is ignored.
func _handle_replay_ack(sender_peer_id: int, replay_id: int) -> void:
	if not _session().is_host():
		return
	if int(_replay_pending.get(sender_peer_id, -1)) != replay_id:
		return
	_replay_pending.erase(sender_peer_id)
	_replay_age.erase(sender_peer_id)
	replays_acknowledged += 1
	# Spec 3.4's snapshots resume: the next one carries every body, so the
	# joiner's interpolator starts from fresh samples for sleepers too.
	if _net_provider == null:
		SnapshotSync.request_full_snapshot()


## Bontago-8or.2: a rejoining peer missed the icy overlay events of an active Freeze.
func _frozen_overlay_snapshot() -> Array[Array]:
	var snapshot: Array[Array] = []
	var registry: BlockRegistry = _authority().registry()
	if registry == null:
		return snapshot
	for block: Block in registry.all_blocks():
		if block.is_frozen_visual() and block.net_id > 0:
			snapshot.append([block.net_id, true])
	return snapshot


func _glue_rejoin_snapshot() -> Array[Array]:
	var snapshot: Array[Array] = []
	for glue_slot: int in range(_authority().slot_count()):
		var revision: int = _authority().glue_revision(glue_slot)
		if revision > 0:
			snapshot.append([glue_slot, _authority().glue_drops_left(glue_slot), revision])
	return snapshot


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


# --- RPCs -------------------------------------------------------------------
# Client -> host. The host checks the caller's peer id against `slot_id`
# (spec 3.4: "The host checks territory, the timer, and that the slot
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


## Spec 3.4: "request_throw(slot_id, pos, orient, velocity): the host clamps
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
	_handle_use_gift_slot_intent(multiplayer.get_remote_sender_id(), slot_id)


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_update_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	_handle_cursor_update(multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat)


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cat_target(slot_id: int, point: Vector3) -> void:
	_handle_cat_target(multiplayer.get_remote_sender_id(), slot_id, point)


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	if _client_awaiting_world():
		return
	_authority().apply_replicated_cat_state(id, position, velocity, point, remaining)


# Host -> clients.

## Bontago-1pi.55: one batch of host-detected block impacts. Unreliable on the
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
## reconnect world replay (see _replay_world_to). The replay span is silent for
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


## Bontago-1pi.42, client: the replayed loading-gate snapshot [ready_ids,
## required_ids, open], applied through the same Events a live broadcast uses (the
## lifecycle's mirror and the loading screen listen to those). Host-authored only;
## every field is validated like Net._rpc_loading_ready_state (wire limit, ids).
func _apply_loading_gate_snapshot(args: Array) -> void:
	if _session().is_host() or args.size() != 3:
		return
	if not args[0] is PackedInt32Array or not args[1] is PackedInt32Array or not args[2] is bool:
		return
	var ready_ids: PackedInt32Array = args[0]
	var required_ids: PackedInt32Array = args[1]
	if ready_ids.size() > config.max_peers or required_ids.size() > config.max_peers:
		return
	for peer_id: int in ready_ids:
		if peer_id < Net.HOST_PEER_ID:
			return
	for peer_id: int in required_ids:
		if peer_id < Net.HOST_PEER_ID:
			return
	Events.loading_ready_changed.emit(ready_ids, required_ids)
	if bool(args[2]):
		Events.loading_gate_opened.emit()


## Bontago-8or.11: the client half of the replay handshake. Lands after every
## replay message (reliable, ordered), so the world is built by now.
@rpc("authority", "call_remote", "reliable")
func net_replay_end(replay_id: int) -> void:
	if _session().is_host() or _client_awaiting_world() or replay_id <= 0:
		return
	last_replay_acknowledged = replay_id
	# The replay's last message: live events from here on are news again.
	if replay_id == _replaying_id:
		_end_world_replay()
	if NetFanout.can_send(multiplayer, _session()):
		rpc_id(Net.HOST_PEER_ID, &"net_replay_ack", replay_id)


@rpc("any_peer", "call_remote", "reliable")
func net_replay_ack(replay_id: int) -> void:
	_handle_replay_ack(multiplayer.get_remote_sender_id(), replay_id)


## True on a client that has not received net_match_start since it joined
## (see _awaiting_match_start).
func _client_awaiting_world() -> bool:
	return _awaiting_match_start and not _session().is_host()


@rpc("authority", "call_remote", "reliable")
func net_match_event(event: StringName, args: Array) -> void:
	if _client_awaiting_world():
		return
	match event:
		EVENT_CAT_STARTED:
			if _session().is_host() or args.size() != 4 or not args[0] is int or not args[1] is int:
				return
			if not args[2] is Vector3 or (not args[3] is float and not args[3] is int):
				return
			var cat_id: int = args[0]
			var cat_slot: int = args[1]
			var cat_duration: float = float(args[3])
			if not Quantize.is_wire_id(cat_id) or cat_slot < 0 or cat_slot >= _authority().slot_count():
				return
			if not (args[2] as Vector3).is_finite() or not is_finite(cat_duration) or cat_duration <= 0.0 or cat_duration > 60.0:
				return
			_authority().apply_replicated_cat_start(cat_id, cat_slot, args[2], cat_duration)
		EVENT_CAT_ENDED:
			if _session().is_host() or args.size() != 1 or not args[0] is int:
				return
			if not Quantize.is_wire_id(args[0]):
				return
			_authority().end_cat(args[0])
		EVENT_STATE_CHANGED:
			_authority().apply_replicated_state_change(int(args[0]))
		EVENT_COUNTDOWN:
			_authority().apply_replicated_countdown(int(args[0]))
			Events.countdown_tick.emit(int(args[0]))
		EVENT_LOADING_GATE:
			_apply_loading_gate_snapshot(args)
		EVENT_TURN_CHANGED:
			# DECISION (net/MatchNet.gd): offline and in hot-seat,
			# Events.turn_changed means "it is this slot's turn". In real-time
			# networked play there are no turns — every slot plays at once
			# (owner decision, docs/M3a_PLAN.md question 1) — and what the
			# signal actually does on a receiving instance is point the HUD
			# and the ghost at the controls that are live here, which is
			# always your own slot. Mirroring the host's value verbatim would
			# aim this client's whole UI at another player, so outside
			# hot-seat a client substitutes its own slot. ui/HUD.gd and
			# game/PlayerController.gd therefore need no networking of their
			# own.
			var turn_slot: int = int(args[0])
			var running: MatchConfig = _authority().config
			# Turn-based (M6 B4) mirrors the host's slot verbatim like hot-seat:
			# the client-side active-slot gate and turn banner must agree with
			# the host on whose turn it is.
			if running != null and not running.is_sequential_play():
				turn_slot = int(_session().local_slot())
			if turn_slot < 0:
				return
			_authority().apply_replicated_turn(turn_slot)
			Events.turn_changed.emit(turn_slot)
		EVENT_FEED_ISSUED:
			_authority().apply_replicated_feed(
				int(args[0]),
				StringName(args[1]),
				StringName(args[2]),
				int(args[3]) if args.size() > 3 else -1,
				float(args[4]) if args.size() > 4 else -1.0,
				bool(args[5]) if args.size() > 5 else false
			)
			Events.feed_block_issued.emit(int(args[0]), StringName(args[1]), StringName(args[2]))
		EVENT_FEED_EXPIRED:
			Events.feed_timer_expired.emit(int(args[0]))
		EVENT_GIFT_SLOT:
			if _session().is_host() or args.size() != 4 or not args[0] is int or not args[1] is Array:
				return
			if not (args[2] is String or args[2] is StringName) or not (args[3] is String or args[3] is StringName):
				return
			if args[0] < 0 or args[0] >= _authority().slot_count() or (args[1] as Array).size() > QolExperiments.GIFT_SLOT_CAPACITY_CEILING:
				return
			var slot_contents: Array = []
			for entry: Variant in args[1]:
				if not (entry is String or entry is StringName) or not _gift_special_id_wire_ok(String(entry)):
					return
				slot_contents.append(StringName(entry))
			var activated_special: StringName = StringName(args[2])
			var carrier_id: StringName = StringName(args[3])
			if activated_special != &"" and (not _gift_special_id_wire_ok(String(activated_special)) or _authority()._feed._shape_by_id(carrier_id) == null):
				return
			_authority().apply_replicated_gift_slot(args[0], slot_contents, activated_special, carrier_id)
		EVENT_QOL_FEED:
			if _session().is_host() or args.size() != 3 or not args[0] is int or not args[1] is int or not args[2] is bool:
				return
			if args[0] < 0 or args[0] >= _authority().slot_count():
				return
			_authority().apply_replicated_qol(args[0], args[1], args[2])
			Events.qol_feed_changed.emit(args[0], args[1], args[2])
		EVENT_PLACEMENT_REJECTED:
			# Bontago-1pi.52: an input boundary like every other wire payload
			# here, and a refusal is the refused player's own feedback: the
			# host now sends it to the owning peer alone, so anything naming a
			# slot this instance does not drive (an older host's broadcast, the
			# host's own seat) is dropped rather than sounded.
			if _session().is_host() or args.size() != 2 or not args[0] is int:
				return
			if not (args[1] is String or args[1] is StringName):
				return
			var rejected_slot: int = args[0]
			if rejected_slot < 0 or rejected_slot >= _authority().slot_count():
				return
			if String(args[1]).length() > REJECT_REASON_MAX_LENGTH:
				return
			if not bool(_session().is_local_slot(rejected_slot)):
				return
			Events.placement_rejected.emit(rejected_slot, StringName(args[1]))
		EVENT_PLACEMENT_RELOCATED:
			# Bontago-1pi.52: an input boundary like the refusal above, with
			# the same own-seat-only rule: the host sends this to the owning
			# peer alone, so another seat's relocation (an older host's
			# broadcast) or a malformed or out-of-disk point never reaches
			# the cursor/camera jump.
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is Vector2:
				return
			var relocated_slot: int = args[0]
			var relocated_point: Vector2 = args[1]
			if _authority().config == null or relocated_slot < 0 or relocated_slot >= _authority().slot_count():
				return
			var point_bound: float = float(_authority().circle_wire_xz_bound())
			if not relocated_point.is_finite() or absf(relocated_point.x) > point_bound or absf(relocated_point.y) > point_bound:
				return
			if not bool(_session().is_local_slot(relocated_slot)):
				return
			Events.placement_relocated.emit(relocated_slot, relocated_point)
		EVENT_PLAYER_ELIMINATED:
			_authority().apply_replicated_elimination(int(args[0]))
			Events.player_eliminated.emit(int(args[0]), int(args[1]))
		EVENT_MATCH_WON:
			Events.match_won.emit(int(args[0]))
		EVENT_MODE_STATE:
			# Bontago-22y.11: display-only mirror; a client never derives an
			# outcome from it. Malformed payloads are dropped, not defaulted.
			if args.size() < 1:
				return
			var mode_state: Dictionary = ModeObjective.validate_state(args[0])
			if mode_state.is_empty():
				return
			_authority().apply_replicated_mode_state(mode_state)
		EVENT_MATCH_RESULTS:
			# Bontago-1pi.13: an input boundary exactly like every other wire
			# payload in this dispatch -- a malformed or truncated args array
			# (an older/ancient build) must not reach a results-screen
			# consumer half-typed. See MatchStats.validate_results_payload()'s
			# own doc comment for why this rejects rather than defaults.
			if args.size() < 1:
				return
			var validated: Dictionary = MatchStats.validate_results_payload(args[0])
			if validated.is_empty():
				return
			Events.match_results_ready.emit(validated)
		EVENT_LIVE_SCORES:
			if _session().is_host() or args.size() < 1:
				return
			var live: Dictionary = MatchStats.validate_results_payload(args[0])
			if live.is_empty():
				return
			_authority().stats().apply_live_snapshot(live)
		EVENT_GIFT_FLIGHT:
			if args.size() != 3 or not args[0] is int or not args[1] is Vector3 or not args[2] is Vector3:
				return
			var gift_id: int = args[0]
			var origin: Vector3 = args[1]
			var landing: Vector3 = args[2]
			if gift_id < 0 or not origin.is_finite() or not landing.is_finite():
				return
			if not is_finite(origin.distance_to(landing)) or origin.y < landing.y:
				return
			if _gift_wire_phases.has(gift_id) and int(_gift_wire_phases[gift_id]) != GiftWirePhase.LEGACY:
				return
			_authority().apply_replicated_gift_flight(gift_id, origin, landing)
			_set_gift_wire_phase(gift_id, GiftWirePhase.FALLING)
			Events.gift_flight_spawned.emit(gift_id, origin, landing)
		EVENT_GIFT_LANDED:
			if args.size() != 2 or not args[0] is int or not args[1] is Vector3:
				return
			var gift_id: int = args[0]
			var landing: Vector3 = args[1]
			if gift_id < 0 or not landing.is_finite() or _gift_wire_phases.get(gift_id, -1) != GiftWirePhase.FALLING:
				return
			var state: Dictionary = _authority().gift_state(gift_id)
			if state.is_empty() or not landing.is_equal_approx(state["landing"]):
				return
			_authority().apply_replicated_gift_landed(gift_id, landing)
			_set_gift_wire_phase(gift_id, GiftWirePhase.LANDED)
			Events.gift_landed.emit(gift_id, landing)
		EVENT_GIFT_SPAWNED:
			if args.size() != 2 or not args[0] is int or not args[1] is Vector2:
				return
			var gift_id: int = int(args[0])
			var position: Vector2 = args[1] as Vector2
			if _gift_spawn_notified.has(gift_id) or not _gift_wire_ok(gift_id, position) or _gift_wire_phases.get(gift_id, -1) in [GiftWirePhase.LEGACY, GiftWirePhase.LANDED, GiftWirePhase.REMOVED]:
				return
			if not _gift_wire_phases.has(gift_id):
				_set_gift_wire_phase(gift_id, GiftWirePhase.LEGACY)
			_authority().apply_replicated_gift_spawned(gift_id, position)
			_gift_spawn_notified[gift_id] = true
			Events.gift_spawned.emit(gift_id, position)
		EVENT_GIFT_CLAIMED:
			if args.size() != 4 or not args[0] is int or not args[1] is int or not (args[2] is String or args[2] is StringName) or not (args[3] is String or args[3] is StringName):
				return
			var claimed_gift_id: int = int(args[0])
			if claimed_gift_id < 0 or _gift_wire_phases.get(claimed_gift_id, -1) == GiftWirePhase.REMOVED:
				return
			var slot_id: int = int(args[1])
			# Review fix (Must #1): bounds-check slot_id here too, next to the
			# id<0 check above, so a garbage value never even reaches
			# MatchGifts.apply_replicated_claim() (which now also refuses it,
			# defense in depth) or the Events bus other listeners read.
			if slot_id < 0 or slot_id >= _authority().slot_count():
				return
			# Orchestrator amendment 1 (M4 P2b): the third argument is the
			# special id drawn for this claim. A short args array (an older
			# or malformed sender) is dropped rather than defaulted, unlike
			# EVENT_FEED_ISSUED's optional trailing fields -- there is no
			# safe "not sent" default for a special id the way there is for
			# an unset feed_time_left.
			if args.size() < 3:
				return
			var special_id: StringName = StringName(args[2])
			if not _gift_special_id_wire_ok(String(special_id)):
				return
			var gift_shape_id: StringName = StringName(args[3])
			if _authority()._feed._shape_by_id(gift_shape_id) == null:
				return
			_set_gift_wire_phase(claimed_gift_id, GiftWirePhase.REMOVED)
			if _authority().gift_slot_enabled():
				# Bontago-1pi.18.2: the gift went to the slot (EVENT_GIFT_SLOT),
				# not the block queue; only the crate visual is retired here.
				_authority().apply_replicated_gift_expired(claimed_gift_id)
			else:
				_authority().apply_replicated_gift_claimed(claimed_gift_id, slot_id, special_id)
				_authority()._feed.apply_replicated_next_gift(slot_id, gift_shape_id)
			Events.gift_claimed.emit(claimed_gift_id, slot_id, special_id)
		EVENT_GIFT_EXPIRED:
			if args.size() != 1 or not args[0] is int:
				return
			var expired_gift_id: int = int(args[0])
			if expired_gift_id < 0 or _gift_wire_phases.get(expired_gift_id, -1) == GiftWirePhase.REMOVED:
				return
			_set_gift_wire_phase(expired_gift_id, GiftWirePhase.REMOVED)
			_authority().apply_replicated_gift_expired(expired_gift_id)
			Events.gift_expired.emit(expired_gift_id)
		EVENT_SPECIAL_TRIGGERED:
			# M4 P2c-ii: mirrors game/specials/SpecialBehavior.gd's own trigger
			# to every client -- a client runs no SpecialBehavior of its own
			# (Events.special_triggered is only ever emitted host-side, see
			# _on_special_triggered() above), so this dispatch is the only
			# place a client ever learns a special fired; it is a purely
			# read-model/effects signal (Known limitations: no remote arm/
			# trigger visuals yet), never fed back into Match.
			#
			# Review fix (Should #1): a short args array (an older or
			# malformed sender) is dropped before any args[1..3] read, exactly
			# EVENT_GIFT_CLAIMED's own args.size() guard above -- args[0]
			# alone is safe to read unconditionally (net_match_event's own
			# dispatch never calls with an empty array), but nothing past it
			# is, and no partial state (a queued net_id with no matching
			# emit) may result from a truncated payload.
			if args.size() < 4:
				return
			var triggered_net_id: int = int(args[0])
			if triggered_net_id < 0:
				return
			var triggered_def_id: StringName = StringName(args[1])
			if not _special_id_wire_ok(String(triggered_def_id)):
				return
			var triggered_position: Vector3 = args[2] as Vector3
			if not triggered_position.is_finite():
				return
			var chain_depth: int = int(args[3])
			if chain_depth < 0 or chain_depth > _special_tuning.max_chain_depth:
				return
			Events.special_triggered.emit(triggered_net_id, triggered_def_id, triggered_position, chain_depth)
		EVENT_SPECIAL_CONSUMED:
			# DECISION (net/MatchNet.gd, Bontago-1en.21): unlike this match's
			# other cases, this one guards `_session().is_host()` itself rather than
			# relying only on net_match_event's own @rpc("authority", ...)
			# annotation -- a well-behaved client never sends this RPC at all
			# (only the host ever fires Events.special_consumed for a real
			# pop; see MatchGifts.pop_pending_special()'s own doc comment),
			# so this dispatch has no legitimate host-side caller. Popping
			# the host's own authoritative queue a second time for an
			# already-spent special (a stale duplicate, or a spoofed direct
			# call) would silently desync it from every client's mirror with
			# no wire message able to undo it, so the host refuses to ever
			# apply one to itself, belt-and-braces on top of the RPC config.
			if _session().is_host():
				return
			# Bontago-1en.21: a short args array (an older or malformed
			# sender) is dropped before either arg is read, exactly
			# EVENT_GIFT_CLAIMED's/EVENT_SPECIAL_TRIGGERED's own guard.
			if args.size() < 2:
				return
			var consumed_slot_id: int = int(args[0])
			if consumed_slot_id < 0 or consumed_slot_id >= _authority().slot_count():
				return
			var consumed_special_id: StringName = StringName(args[1])
			# Only the syntactic shape check, not _gift_special_id_wire_ok()'s
			# roster-membership tightening: exactly EVENT_SPECIAL_TRIGGERED's
			# own reasoning (_known_special_ids()'s doc comment above) -- a
			# special already popped and consumed on the host is by
			# construction an id EVENT_GIFT_CLAIMED already roster-checked
			# when it was queued; nothing here needs to reject one a
			# client's own (possibly stale) roster cache does not recognise.
			if not _special_id_wire_ok(String(consumed_special_id)):
				return
			_authority().apply_replicated_special_consumed(consumed_slot_id, consumed_special_id)
			Events.special_consumed.emit(consumed_slot_id, consumed_special_id)
		EVENT_GLUE_CHARGES:
			if _session().is_host() or args.size() != 3:
				return
			if not args[0] is int or not args[1] is int or not args[2] is int:
				return
			var glue_slot: int = args[0]
			var charges: int = args[1]
			var revision: int = args[2]
			if glue_slot < 0 or glue_slot >= _authority().slot_count():
				return
			if charges < 0 or charges > 100 or revision <= 0:
				return
			_authority().apply_replicated_glue_charges(glue_slot, charges, revision)
		EVENT_BLOCK_DISSOLVE_STARTED:
			# Bontago-1pi.11.41: presentation only. An unknown id (a spawn the
			# client never built) or a malformed payload is dropped.
			if _session().is_host() or args.size() != 1 or not args[0] is int:
				return
			var dissolving_id: int = args[0]
			if not Quantize.is_wire_id(dissolving_id):
				return
			var dissolve_registry: BlockRegistry = _authority().registry()
			if dissolve_registry == null:
				return
			var dissolving: Block = dissolve_registry.block_for_net_id(dissolving_id)
			if dissolving == null or not is_instance_valid(dissolving):
				return
			Events.block_dissolve_started.emit(dissolving, dissolving_id, _hole_dissolve_tuning.dissolve_delay_s)
		EVENT_SLOT_REPLAY:
			if _session().is_host():
				return
			_apply_slot_replay(args)
		EVENT_MATCH_CLOCK:
			if _session().is_host() or args.size() != 1 or not (args[0] is float or args[0] is int):
				return
			var clock: float = float(args[0])
			if not is_finite(clock) or clock < 0.0:
				return
			# DECISION (Bontago-8or.11): the client's read model of the match
			# timer is written directly, the way this file already reaches
			# _lifecycle/_feed elsewhere -- autoload/Match.gd and
			# MatchLifecycle.gd are outside this package. A client never
			# ticks it; timed modes keep it current through EVENT_MODE_STATE.
			_authority()._lifecycle._match_timer_left = clock
		EVENT_BLOCK_OWNER_CHANGED:
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is int:
				return
			var painted_id: int = args[0]
			var painted_slot: int = args[1]
			if not Quantize.is_wire_id(painted_id) or painted_slot < 0 or painted_slot >= _authority().slot_count():
				return
			_authority().apply_replicated_block_owner(painted_id, painted_slot)
		EVENT_BLOCK_GLUED:
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is bool:
				return
			var glued_id: int = args[0]
			if not Quantize.is_wire_id(glued_id):
				return
			var glued_registry: BlockRegistry = _authority().registry()
			if glued_registry == null:
				return
			var glued_block: Block = glued_registry.block_for_net_id(glued_id)
			if glued_block != null and is_instance_valid(glued_block):
				HoneyCoat.set_coated(glued_block, args[1])
		EVENT_BLOCK_FROZEN:
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is bool:
				return
			var frozen_id: int = args[0]
			if not Quantize.is_wire_id(frozen_id):
				return
			var frozen_registry: BlockRegistry = _authority().registry()
			if frozen_registry == null:
				return
			var frozen_block: Block = frozen_registry.block_for_net_id(frozen_id)
			if frozen_block == null or not is_instance_valid(frozen_block):
				return
			if frozen_block.is_frozen_visual() != args[1]:
				frozen_block.set_frozen_visual(args[1])
				Events.block_frozen_changed.emit(frozen_id, args[1])
		_:
			pass


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
		# address it for a despawn (Bontago-mv0.1.7).
		return
	_note_spawn(net_id)
	var registry: BlockRegistry = _authority().registry()
	var parent: Node3D = _authority().blocks_parent()
	if registry == null or parent == null:
		return
	if registry.block_for_net_id(net_id) != null:
		return
	var shape: BlockShape = _shape_for_id(shape_id)
	if shape == null:
		return

	# Bontago-mv0.11: the same slot-colour tint as the host's own block (see
	# autoload/Match.gd's _spawn_block DECISION on using the slot's own colour
	# rather than a separate team lookup). `origin` below is already the
	# host's exact spawned transform -- the bottom-centre pivot (Bontago-
	# mv0.17 item 3, was Bontago-mv0.12's geometric centre) needs no extra
	# conversion here either, since BlockFactory.build() offsets this shape's
	# cells by the same shape.bottom_center() on every instance.
	var owner_slot_ref: PlayerSlot = _authority().slot(owner_slot)
	var color: Color = owner_slot_ref.color if owner_slot_ref != null else Color.WHITE
	var block: Block = BlockFactory.build(shape, _physics_tuning, owner_slot, color)
	# Spec 3.4: "Clients set every synced RigidBody3D to freeze = true
	# (kinematic) and move them by interpolating snapshots." Freezing before
	# the body enters the tree means it never simulates a single step here.
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	block.freeze = true
	parent.add_child(block)
	block.global_transform = Transform3D(Basis(rotation), origin)
	# Bontago-t8x.1: untrusted wire id; only a known roster gift swaps the look.
	if gift_id != &"" and _gift_special_id_wire_ok(String(gift_id)):
		BlockFactory.apply_gift_visual(block, shape, _physics_tuning, gift_id)

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
	_spawned_net_ids.erase(net_id)
	var registry: BlockRegistry = _authority().registry()
	if registry == null:
		return
	var block: Block = registry.block_for_net_id(net_id)
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
## tick's analytic circle list (Bontago-cmc.5); a default empty value keeps a
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
