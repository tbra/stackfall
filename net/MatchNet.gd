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
const EVENT_PLACEMENT_REJECTED: StringName = &"placement_rejected"
const EVENT_PLACEMENT_RELOCATED: StringName = &"placement_relocated"
const EVENT_PLAYER_ELIMINATED: StringName = &"player_eliminated"
const EVENT_MATCH_WON: StringName = &"match_won"
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
## _can_send() is already false in a unit test with no live peer, so that gate
## alone cannot prove a refused spawn was never even handed to the rpc(); this
## counter is the seam that does. Game code never reads it.
var _invalid_spawn_refusals: int = 0

## Test-only (Bontago-mv0.1.13): to_state values _on_match_state_changed
## actually decided to replicate as EVENT_STATE_CHANGED, in order. Needed for
## the same reason as _invalid_spawn_refusals above: _can_send() is already
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


func _ready() -> void:
	_authority().set_replicator(self)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.countdown_tick.connect(_on_countdown_tick)
	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.match_won.connect(_on_match_won)
	Events.gift_spawned.connect(_on_gift_spawned)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.gift_expired.connect(_on_gift_expired)
	Events.special_triggered.connect(_on_special_triggered)
	Events.special_consumed.connect(_on_special_consumed)
	Events.block_removed.connect(_on_block_removed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.net_peer_left.connect(_on_net_peer_left)
	Events.net_peer_joined.connect(_on_net_peer_joined)


func _exit_tree() -> void:
	var authority: Variant = _authority()
	if authority != null and authority.get("_replicator") == self:
		authority.set_replicator(null)


## Test seam; see _net_provider. Either argument may be null to keep the real
## autoload.
func set_providers(net_provider: Variant, match_provider: Variant) -> void:
	_net_provider = net_provider
	_match_provider = match_provider
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


func _is_host() -> bool:
	return bool(_session().is_host())


## True only when there is a live peer to talk to. Offline — M2's hot-seat,
## the sandbox, a unit test — every rpc() below would error, so the whole
## replication layer becomes a no-op and Match runs exactly as it did in M2.
##
## Godot installs an OfflineMultiplayerPeer by default, so has_multiplayer_peer()
## is true and the connection reads CONNECTED even with no session at all;
## rpc_id() onto it then fails with "p_peer_id == caller_id". Excluding that
## one class is not a transport assumption (CLAUDE.md) — it is the engine's
## own stand-in for "no transport", and ENet and Steam are both equally
## unaffected.
func _can_send() -> bool:
	if bool(_session().is_offline()):
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	if not _is_host():
		return
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
	if _is_host():
		if not auto_drop:
			_bump(_intents_sent, slot_id)
		return _apply_intent(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)

	# A client never auto-drops: spec 2.5's auto-drop is [ORIGINAL] and must
	# not be able to go missing in a round trip, so the host fires it from the
	# last cursor it received (see _on_feed_timer_expired).
	if auto_drop:
		return PlacementRules.REASON_NO_BLOCK
	if not _can_send():
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
	if _is_host():
		_bump(_intents_sent, slot_id)
		return _apply_throw_intent(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)

	if not _can_send():
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
	if not _can_send():
		return
	var step: float = 1.0 / maxf(config.cursor_hz, 0.001)
	var now: float = _now()
	if now - _cursor_send_accum < step:
		return
	_cursor_send_accum = now
	if _is_host():
		rpc(&"net_cursor", slot_id, origin, orientation_index, free_quat)
	else:
		rpc_id(Net.HOST_PEER_ID, &"net_update_cursor", slot_id, origin, orientation_index, free_quat)


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
	if not _is_host() or block == null:
		return
	if not Quantize.is_wire_id(net_id):
		_invalid_spawn_refusals += 1
		return
	_note_spawn(net_id)
	if not _can_send():
		return
	var basis: Basis = block.global_transform.basis.orthonormalized()
	rpc(
		&"net_block_spawned",
		net_id,
		block.shape_id,
		block.owner_slot,
		block.global_position,
		basis.get_rotation_quaternion()
	)


func replicate_despawn(net_id: int, reason: String) -> void:
	if not _is_host() or net_id < 0:
		return
	_spawned_net_ids.erase(net_id)
	if not _can_send():
		return
	rpc(&"net_block_despawned", net_id, reason)


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
	if not _is_host() or not _can_send():
		return
	var raster: TerritoryRaster = _authority().raster()
	if raster == null:
		return
	var owners: PackedByteArray = raster.owner_bytes().duplicate()
	var states: PackedByteArray = raster.state_bytes().duplicate()
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

	rpc(
		&"net_territory",
		payload,
		full,
		_team_shares(),
		_capture_team,
		_capture_progress,
		_encode_circles()
	)


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
## countdown, feed issues, rejections, eliminations and the win.
func replicate_match_event(event: StringName, args: Array) -> void:
	if not _is_host() or not _can_send():
		return
	rpc(&"net_match_event", event, args)


## Host only. Ships the whole match start: the sanitized MatchConfig, the slot
## roster and the seed, so a client builds the identical world before the
## first snapshot. Idempotent for one match, so an explicit call from the
## lobby and the automatic one below cannot both go out.
func replicate_match_start(match_config: MatchConfig) -> void:
	if not _is_host() or match_config == null or _match_start_sent:
		return
	_match_start_sent = true
	match_starts_replicated += 1
	_force_full_raster = true
	if not _can_send():
		return
	rpc(&"net_match_start", match_config.to_dict(), _roster())


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
	# Test-only instrumentation; bounded per match (review mv0.1.13).
	replicated_state_changes.clear()
	match_starts_replicated = 0


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
	if not _is_host():
		return
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0:
		# A peer with no slot — mid-handshake, a spectator, or one that has
		# already gone — gets no say at all, and is not counted: it has no
		# slot to count against.
		return
	_bump(_intents_sent, sender_slot)
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
	var reason: StringName = _apply_intent(slot_id, origin, orientation_index, free_quat, false, feed_seq)
	if not _consumed_a_block(reason, false):
		# Nothing was burned, so Match emitted no placement_rejected of its
		# own; tell the sender anyway so its ghost unlocks now instead of
		# waiting out NetConfig.intent_ack_timeout.
		_reject_to_peer(sender_peer_id, slot_id, reason)


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
	if not _is_host():
		return
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0:
		return
	_bump(_intents_sent, sender_slot)
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
	var reason: StringName = _apply_throw_intent(
		slot_id, origin, orientation_index, free_quat, velocity, feed_seq
	)
	if not _consumed_a_block(reason, false):
		# MatchPlacement.request_throw() already emits Events.placement_rejected
		# for an outside-territory/not-a-special refusal, which
		# _on_placement_rejected below already mirrors to every client -- but
		# this targeted reply is still needed so the *sender's own* ghost
		# unlocks now instead of waiting out NetConfig.intent_ack_timeout,
		# exactly like _handle_place_intent's own tail.
		_reject_to_peer(sender_peer_id, slot_id, reason)


## Host side of net_update_cursor, split out (like _handle_place_intent) so a
## test can drive it with a manufactured sender id and no peer at all. What is
## stored here is what spec 2.5's auto-drop fires from when the slot's timer
## expires (_on_feed_timer_expired), so it is an input boundary too.
func _handle_cursor_update(
	sender_peer_id: int, slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> void:
	if not _is_host():
		return
	var sender_slot: int = int(_session().slot_of_peer(sender_peer_id))
	if sender_slot < 0 or sender_slot != slot_id:
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
	if _can_send():
		rpc(&"net_cursor", slot_id, origin, orientation_index, free_quat)


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
	if not _can_send():
		return
	rpc_id(peer_id, &"net_match_event", EVENT_PLACEMENT_REJECTED, [slot_id, reason])


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
	if not _is_host():
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
	if _is_host():
		replicate_match_event(EVENT_COUNTDOWN, [seconds_left])


func _on_turn_changed(slot_id: int) -> void:
	if _is_host():
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
	if _is_host():
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
	if not _is_host():
		return
	# The ghost flash is feedback, not a rule, so every instance gets it.
	replicate_match_event(EVENT_FEED_EXPIRED, [slot_id])
	if bool(_session().is_local_slot(slot_id)):
		return
	var cursor: Dictionary = cursor_for_slot(slot_id)
	var origin: Vector3 = cursor.get("origin", _authority().default_ghost_origin(slot_id))
	var orientation_index: int = int(cursor.get("orientation_index", 0))
	var free_quat: Quaternion = cursor.get("free_quat", Quaternion.IDENTITY)
	_apply_intent(slot_id, origin, orientation_index, free_quat, true, _authority().feed_seq(slot_id))


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	if _is_host():
		replicate_match_event(EVENT_PLACEMENT_REJECTED, [slot_id, reason])


## Bontago-mv0.24: mirrors an auto-drop's relocation the same way
## _on_placement_rejected mirrors a refusal -- every instance gets it over the
## reliable match-event channel, and PlayerController._on_placement_relocated
## already ignores any slot that isn't its own, so nothing further needs to be
## targeted at just the owning peer here.
func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	if _is_host():
		replicate_match_event(EVENT_PLACEMENT_RELOCATED, [slot_id, point])


func _on_player_eliminated(slot_id: int, team_id: int) -> void:
	if _is_host():
		replicate_match_event(EVENT_PLAYER_ELIMINATED, [slot_id, team_id])


func _on_match_won(team_id: int) -> void:
	if _is_host():
		replicate_match_event(EVENT_MATCH_WON, [team_id])


func _on_gift_spawned(gift_id: int, position: Vector2) -> void:
	if _is_host():
		replicate_match_event(EVENT_GIFT_SPAWNED, [gift_id, position])


func _on_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	if _is_host():
		replicate_match_event(EVENT_GIFT_CLAIMED, [gift_id, slot_id, special_id])


func _on_gift_expired(gift_id: int) -> void:
	if _is_host():
		replicate_match_event(EVENT_GIFT_EXPIRED, [gift_id])


## M4 P2c-ii: autoload/match/MatchPlacement._on_special_behavior_triggered()
## emits Events.special_triggered only on the host (game/specials/
## SpecialBehavior.gd only ever attaches there -- see that file's own header
## and orchestrator amendment 2), so this mirrors it to every client exactly
## like _on_gift_spawned above.
func _on_special_triggered(net_id: int, def_id: StringName, position: Vector3, chain_depth: int) -> void:
	if _is_host():
		replicate_match_event(EVENT_SPECIAL_TRIGGERED, [net_id, def_id, position, chain_depth])


## Bontago-1en.21: mirrors autoload/match/MatchGifts.gd's pop_pending_special()
## emit to every client -- a client never pops its own queue (it only ever
## mirrors the host's, via apply_replicated_special_consumed() below), so this
## dispatch is the only place a client ever learns a special was spent.
func _on_special_consumed(slot_id: int, special_id: StringName) -> void:
	if _is_host():
		replicate_match_event(EVENT_SPECIAL_CONSUMED, [slot_id, special_id])


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	_capture_team = team_id
	_capture_progress = progress


## Field's kill plane removes a body by emitting on the bus, so the despawn is
## replicated from here rather than from Field — which then needs no idea that
## multiplayer exists.
func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	var typed: Block = block as Block
	if typed != null:
		replicate_despawn(typed.net_id, reason)


func _on_net_peer_left(_peer_id: int, slot_id: int, _reason: int) -> void:
	if slot_id >= 0:
		_authority().on_peer_left(slot_id)


func _on_net_peer_joined(_peer_id: int, slot_id: int, _player_name: String) -> void:
	# A fresh client has nothing to diff a territory packet against.
	_force_full_raster = true
	if slot_id >= 0:
		_authority().on_peer_rejoined(slot_id)


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


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_update_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	_handle_cursor_update(multiplayer.get_remote_sender_id(), slot_id, origin, orientation_index, free_quat)


# Host -> clients.

@rpc("authority", "call_remote", "reliable")
func net_match_start(config_data: Dictionary, roster: Array) -> void:
	var match_config: MatchConfig = MatchConfig.from_dict(config_data)
	match_config.sanitize()
	reset_counters()
	_authority().start_match(match_config)
	_apply_roster(roster)


func _apply_roster(roster: Array) -> void:
	for entry: Variant in roster:
		if not (entry is Dictionary):
			continue
		var info: Dictionary = entry
		if not info.has("slot_id"):
			continue
		var target: PlayerSlot = _authority().slot(int(info["slot_id"]))
		if target == null:
			continue
		target.peer_id = int(info.get("peer_id", 0))
		target.display_name = String(info.get("name", target.display_name))
		target.is_local = bool(_session().is_local_slot(target.slot_id))


@rpc("authority", "call_remote", "reliable")
func net_match_event(event: StringName, args: Array) -> void:
	match event:
		EVENT_STATE_CHANGED:
			_authority().apply_replicated_state_change(int(args[0]))
		EVENT_COUNTDOWN:
			_authority().apply_replicated_countdown(int(args[0]))
			Events.countdown_tick.emit(int(args[0]))
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
			if running != null and not running.hot_seat and not running.turn_based:
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
		EVENT_PLACEMENT_REJECTED:
			Events.placement_rejected.emit(int(args[0]), StringName(args[1]))
		EVENT_PLACEMENT_RELOCATED:
			Events.placement_relocated.emit(int(args[0]), args[1] as Vector2)
		EVENT_PLAYER_ELIMINATED:
			_authority().apply_replicated_elimination(int(args[0]))
			Events.player_eliminated.emit(int(args[0]), int(args[1]))
		EVENT_MATCH_WON:
			Events.match_won.emit(int(args[0]))
		EVENT_GIFT_SPAWNED:
			var gift_id: int = int(args[0])
			var position: Vector2 = args[1] as Vector2
			if not _gift_wire_ok(gift_id, position):
				return
			_authority().apply_replicated_gift_spawned(gift_id, position)
			Events.gift_spawned.emit(gift_id, position)
		EVENT_GIFT_CLAIMED:
			var claimed_gift_id: int = int(args[0])
			if claimed_gift_id < 0:
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
			_authority().apply_replicated_gift_claimed(claimed_gift_id, slot_id, special_id)
			Events.gift_claimed.emit(claimed_gift_id, slot_id, special_id)
		EVENT_GIFT_EXPIRED:
			var expired_gift_id: int = int(args[0])
			if expired_gift_id < 0:
				return
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
			# other cases, this one guards `_is_host()` itself rather than
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
			if _is_host():
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
		_:
			pass


@rpc("authority", "call_remote", "reliable")
func net_block_spawned(
	net_id: int, shape_id: StringName, owner_slot: int, origin: Vector3, rotation: Quaternion
) -> void:
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

	# block_placed is what BlockRegistry tracks bodies on; with
	# set_host_authority(false) it allocates no id of its own, so the host's
	# is bound straight after and the two ends address the same body.
	Events.block_placed.emit(block, shape.id)
	registry.bind_net_id(block, net_id)
	Events.block_replicated.emit(block, net_id)


@rpc("authority", "call_remote", "reliable")
func net_block_despawned(net_id: int, reason: String) -> void:
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
	if bool(_session().is_local_slot(slot_id)):
		return
	_store_cursor(slot_id, origin, orientation_index, free_quat)
	Events.remote_cursor_updated.emit(slot_id, origin, orientation_index, free_quat)
