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

## Reliable gameplay traffic uses channel 0 (the MultiplayerAPI default).
## Cursors get their own so a 15 Hz stream cannot delay a spawn. The number
## must be a compile-time constant for @rpc, so it lives here rather than in
## NetConfig; NetConfig documents the pairing.
const CURSOR_CHANNEL: int = 2

@export var config: NetConfig = preload("res://config/net_config.tres")

@warning_ignore_start("unused_parameter")


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
	return PlacementRules.REASON_OK


## The local player's ghost pose, at NetConfig.cursor_hz. Unreliable: a lost
## one costs one frame of someone else's ghost. On the host this only
## broadcasts; on a client it also goes to the host, which stores it as the
## slot's last known ghost — **that is what the host auto-drops from when the
## feed timer expires**, so no round trip can lose an auto-drop.
func submit_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	pass


## The last cursor the host received for `slot_id`, or an empty Dictionary.
## {"origin": Vector3, "orientation_index": int, "free_quat": Quaternion,
## "age": float}. Match reads this for auto-drop; RemoteCursors draws it.
func cursor_for_slot(slot_id: int) -> Dictionary:
	return {}


# --- Host -> clients: replication hooks Match calls -------------------------

## Host only. Announces a block the host just spawned, reliably, before any
## snapshot can reference it. Clients build a frozen copy and bind `net_id`.
func replicate_spawn(block: Block, net_id: int) -> void:
	pass


func replicate_despawn(net_id: int, reason: String) -> void:
	pass


## Host only, at NetConfig.raster_diff_hz. Sends the cells whose owner or
## state byte changed since the last diff, or a full compressed raster when
## more than NetConfig.raster_full_threshold_fraction of them changed or a
## client has just joined. Territory shares and capture progress ride along so
## the HUD costs no extra packet.
func replicate_territory() -> void:
	pass


## Host only. Mirrors a match-flow event to every client: state changes, the
## countdown, feed issues, rejections, eliminations and the win.
func replicate_match_event(event: StringName, args: Array) -> void:
	pass


## Host only. Ships the whole match start: the sanitized MatchConfig, the slot
## roster and the seed, so a client builds the identical world before the
## first snapshot.
func replicate_match_start(match_config: MatchConfig) -> void:
	pass


# --- Counters the acceptance harness asserts on -----------------------------

## Intents this instance sent (client) or accepted (host), per slot. The
## harness proves "placements are never duplicated or lost" by checking that
## the host's accepted count equals each client's sent count plus the host's
## own auto-drops, and that the spawn count matches exactly.
func intents_sent(slot_id: int) -> int:
	return 0


func intents_accepted(slot_id: int) -> int:
	return 0


func intents_refused(slot_id: int) -> int:
	return 0


## net_ids this instance has seen spawned. A duplicate id is a hard failure.
func replicated_block_count() -> int:
	return 0


# --- RPCs -------------------------------------------------------------------
# Client -> host. The host checks the caller's peer id against `slot_id`
# (spec 3.4: "The host checks territory, the timer, and that the slot
# matches") and drops anything else on the floor; it never trusts slot_id.

@rpc("any_peer", "call_remote", "reliable")
func net_request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int
) -> void:
	pass


@rpc("any_peer", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_update_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	pass


# Host -> clients.

@rpc("authority", "call_remote", "reliable")
func net_match_start(config_data: Dictionary, roster: Array) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func net_match_event(event: StringName, args: Array) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func net_block_spawned(
	net_id: int, shape_id: StringName, owner_slot: int, origin: Vector3, rotation: Quaternion
) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func net_block_despawned(net_id: int, reason: String) -> void:
	pass


## `payload` is a raster diff or a full raster, compressed when
## NetConfig.raster_compress is on; `full` says which. Clients apply it to
## their mirror raster and re-emit Events.hole_cells_changed for the cells
## whose hole bit flipped, so Field opens the same holes without a second RPC.
@rpc("authority", "call_remote", "reliable")
func net_territory(
	payload: PackedByteArray,
	full: bool,
	shares: PackedFloat32Array,
	capture_team: int,
	capture_progress: float
) -> void:
	pass


@rpc("authority", "call_remote", "unreliable", CURSOR_CHANNEL)
func net_cursor(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	pass


@warning_ignore_restore("unused_parameter")
