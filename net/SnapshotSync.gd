extends Node
## Host -> client rigid body state (spec 3.4 "Snapshots"), at
## NetConfig.snapshot_hz (30 Hz), as unreliable RPCs carrying a packed
## PackedByteArray on NetConfig.snapshot_channel.
##
## Registered as the `SnapshotSync` autoload, so the RPC's node path is
## /root/SnapshotSync on every instance and no scene structure has to match.
## **No `class_name`** — it would collide with the singleton name.
##
## An unreliable RPC on its own channel is how spec 3.4's "custom packets on
## their own channel ... tag each with a sequence number" is met while staying
## inside MultiplayerAPI (CLAUDE.md: gameplay code must never assume a
## transport). Steam's peer in M3b carries it unchanged.
##
## **Wire layout** — one fragment, little-endian throughout. Bodies are packed
## by core/net/Quantize.gd, 14 bytes each.
##
## | offset | size | field |
## |---|---|---|
## | 0 | 1 | packet version, PACKET_VERSION |
## | 1 | 2 | `sequence`, u16, wraps; the same value on every fragment of one snapshot |
## | 3 | 1 | `fragment_index` |
## | 4 | 1 | `fragment_count` |
## | 5 | 4 | `host_time_ms`, u32 — the host's snapshot clock, the only time base the client interpolates against |
## | 9 | 1 | flags: bit0 FLAG_DISK_STATE, bit1 FLAG_KEYFRAME |
## | 10 | 2 | `body_count`, u16 |
## | 12 | 12 | disk state, only when FLAG_DISK_STATE: 6 B quantized offset + 6 B tilt quaternion (spec 3.4 "Disk state: tilt quaternion and position offset, sent every snapshot") |
## | .. | 14 x body_count | body records |
##
## The header is HEADER_BYTES (12) or HEADER_BYTES + DISK_STATE_BYTES (24);
## NetConfig.bodies_per_fragment() turns that into the per-fragment body cap,
## which at 1200 bytes is 84 bodies, so spec 3.4's 300 awake bodies take four
## fragments.
##
## **Client side** it owns net/Interpolator.gd: buffer, render 100 ms behind
## with a jitter-adaptive delay, extrapolate at most 100 ms, and write every
## synced body's transform in `_physics_process` — never `_process`, or the
## writes fight Godot's own physics interpolation (project.godot has
## physics_interpolation on).

## Bumped whenever the layout above changes. A mismatched version is dropped
## rather than misread; the build-version handshake in Net should already have
## refused the peer, so this is a belt-and-braces check.
const PACKET_VERSION: int = 1

const HEADER_BYTES: int = 12
const DISK_STATE_BYTES: int = 12

const FLAG_DISK_STATE: int = 1 << 0
const FLAG_KEYFRAME: int = 1 << 1

## Snapshots ride their own channel so a burst of them cannot head-of-line
## block the reliable stream (spec 3.4 "Channels"). @rpc needs a compile-time
## constant, so the number lives here rather than in NetConfig, which
## documents the pairing; it is architecture, not a tunable.
const SNAPSHOT_CHANNEL: int = 1

@export var config: NetConfig = preload("res://config/net_config.tres")

@warning_ignore_start("unused_parameter")


# --- Lifecycle --------------------------------------------------------------

## Called by Match when a match starts, on both host and client. `registry` is
## the BlockRegistry that resolves net_id -> Block; `map_def` fixes the
## quantization bounds, so both ends must be handed the same one.
func begin_match(registry: BlockRegistry, map_def: MapDef) -> void:
	pass


## Stops sending and drops every buffer. Called when a match ends or the
## session closes.
func end_match() -> void:
	pass


func is_running() -> bool:
	return false


# --- Host side --------------------------------------------------------------

## Builds and sends this tick's snapshot, if 1/config.snapshot_hz has elapsed.
## Host only; a no-op on a client and offline. Selects bodies that are awake
## (`RigidBody3D.sleeping` is false), that moved past
## config.resend_position_epsilon / resend_angle_epsilon since they were last
## sent, or that are in this tick's slice of the keyframe rotation.
##
## **Awake here means the physics engine's sleep state, not M2's settled rule**
## (PhysicsTuning.sleep_* and BlockRegistry.is_settled). Those thresholds are
## deliberately looser and feed territory influence; confusing the two makes
## towers stutter or influence flicker.
func host_tick(delta: float) -> void:
	pass


## Sleeping bodies refreshed per snapshot so every sleeper is re-sent once per
## config.keyframe_interval (spec 3.4's 2 s keyframe), round-robin.
func keyframe_slice_size() -> int:
	return 0


## Bytes the last snapshot cost, summed over its fragments — the debug
## overlay's "snapshot size".
func last_snapshot_bytes() -> int:
	return 0


func last_sequence() -> int:
	return 0


# --- Client side ------------------------------------------------------------

## Advances every synced body to the current render time. **Call from
## _physics_process only.** Client only.
func client_tick(delta: float) -> void:
	pass


## The adaptive interpolation delay in force right now, in milliseconds —
## config.base_interp_delay_ms plus jitter_multiplier x measured jitter,
## clamped. The debug overlay shows this.
func interpolation_delay_ms() -> float:
	return 0.0


## Snapshots the client noticed were missing, as a fraction of those expected,
## measured from gaps in the sequence numbers. The overlay's "packet loss".
func measured_loss() -> float:
	return 0.0


func interpolator() -> Interpolator:
	return null


# --- Wire (pure, so a test can round-trip a packet with no peer) ------------

## Packs one fragment. `bodies` is an Array of
## {"net_id", "position", "rotation", "sleeping"}.
static func encode_fragment(
	sequence: int,
	fragment_index: int,
	fragment_count: int,
	host_time_ms: int,
	flags: int,
	bodies: Array,
	disk_transform: Transform3D,
	bounds: AABB
) -> PackedByteArray:
	return PackedByteArray()


## Unpacks a fragment into {"sequence", "fragment_index", "fragment_count",
## "host_time_ms", "flags", "bodies", "disk_transform"}. Returns an empty
## Dictionary for a truncated, foreign or wrong-version packet — never an
## error, because an unreliable channel will eventually deliver garbage.
static func decode_fragment(packet: PackedByteArray, bounds: AABB) -> Dictionary:
	return {}


# --- RPC --------------------------------------------------------------------

## Host -> clients. Unreliable on config.snapshot_channel; the sequence number
## in the payload is what makes late and duplicate delivery detectable.
@rpc("authority", "call_remote", "unreliable", SNAPSHOT_CHANNEL)
func net_snapshot(packet: PackedByteArray) -> void:
	pass


@warning_ignore_restore("unused_parameter")
