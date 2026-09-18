class_name NetConfig
extends Resource
## Every tunable number the M3a network stack uses (spec 3.4, docs/M3a_PLAN.md).
##
## CLAUDE.md: "No magic numbers. Every tunable value belongs in a Resource
## under res://config/." Nothing in autoload/Net.gd, net/*.gd or core/net/*.gd
## may write a literal that appears here. Loaded once as
## config/net_config.tres; callers that mutate it (the debug overlay's lag
## sliders) must duplicate() first, exactly as Match does with MatchConfig.

# --- Ports and session (spec 3.4 "LAN discovery") ---------------------------

## UDP port the host broadcasts its game advert on, and clients listen on.
@export var discovery_port: int = 47777
## Default ENet game port. --port= overrides it so several hosts can share a PC.
@export var game_port: int = 47778
## Spec 2.8: 2-8 players, so at most 7 remote peers plus the listen-server host.
@export var max_peers: int = 8
## How often the host sends its LAN advert, in Hz (spec 3.4: "once per second").
@export var discovery_broadcast_hz: float = 1.0
## Seconds a discovered game stays in the browser list after its last advert.
@export var discovery_entry_ttl: float = 3.0
## Seconds a join attempt waits for CONNECTION_CONNECTED before giving up.
@export var connect_timeout: float = 8.0
## Seconds the host waits for a joining peer's version handshake before
## disconnecting it. Guards against a peer that connects and then says nothing.
@export var handshake_timeout: float = 5.0
## ENetPacketPeer.set_timeout() triple, in milliseconds: a peer that stops
## acknowledging is dropped after peer_timeout_ms, bounded by min/max.
@export var peer_timeout_ms: int = 5000
@export var peer_timeout_min_ms: int = 2500
@export var peer_timeout_max_ms: int = 10000
## How often each peer round-trips a ping RPC with the host, in Hz. Our own
## ping rather than ENetPacketPeer statistics, so the number is identical over
## Steam in M3b (CLAUDE.md: never assume a transport).
@export var ping_hz: float = 1.0
## Round-trip samples averaged into the reported ping.
@export var ping_history: int = 8
## Seconds a slot whose peer vanished keeps its territory before Match
## eliminates it. See docs/M3a_PLAN.md "Questions for the owner" 3.
@export var disconnect_grace: float = 10.0

# --- Channels (spec 3.4 "Channels") -----------------------------------------
#
# Reliable gameplay RPCs (lobby, spawn/despawn, raster diffs, win) ride the
# default channel 0. Snapshots and cursors get their own so a burst of either
# cannot head-of-line block the reliable stream. The numbers are NOT here:
# @rpc takes a compile-time constant, so they live as
# SnapshotSync.SNAPSHOT_CHANNEL = 1 and MatchNet.CURSOR_CHANNEL = 2. They are
# architecture, not tunables — the same reason Match.COUNTDOWN_SECONDS is a
# const (CLAUDE.md's "no magic numbers" targets tunables).

# --- Rates (spec 3.4, 3.7) --------------------------------------------------

## Body snapshots per second (spec 3.4: "Rate: 30 Hz").
@export var snapshot_hz: float = 30.0
## Territory raster diffs per second (spec 3.7: "Territory diffs are sent to
## clients at 5 Hz").
@export var raster_diff_hz: float = 5.0
## Cursor updates per second, client -> host and host -> clients (spec 3.4:
## "update_cursor(pos): unreliable, 15 Hz").
@export var cursor_hz: float = 15.0

# --- Snapshot packing (spec 3.4 "Snapshots") --------------------------------

## Hard cap on one snapshot fragment, in bytes (spec 3.4: "Split into several
## packets if needed to stay under ~1200 bytes each").
@export var max_packet_bytes: int = 1200
## Position quantization bounds in X/Z, as a multiple of MapDef.field_radius.
## 1.5 x 45 m gives +-67.5 m, so an int16 axis step is 135/65536 = 2.1 mm —
## inside spec 3.4's "≈1-2 mm precision". Raising this coarsens every axis.
@export var pos_xz_margin: float = 1.5
## Absolute Y bounds of the quantized volume, in meters. Must bracket
## PhysicsTuning.kill_plane_y (-40) below and the tallest reachable tower
## above; 120 m over an int16 is a 1.8 mm step.
@export var pos_min_y: float = -48.0
@export var pos_max_y: float = 72.0
## Spec 3.4: "Every 2 s, send a full keyframe for sleeping bodies at a low
## rate." Sleepers are sent round-robin so each one is refreshed this often.
@export var keyframe_interval: float = 2.0
## A sleeping body is re-sent early if it drifted further than this since the
## last time it was sent, in meters. Two quantization steps, so a body that
## only wobbled inside its own quantization bucket never costs a packet.
@export var resend_position_epsilon: float = 0.005
## Same, for rotation, in degrees.
@export var resend_angle_epsilon: float = 0.5

# --- Client interpolation (spec 3.4 "Client interpolation") -----------------

## Spec 3.4: "Render 100 ms behind the host". This is the floor the adaptive
## delay starts from, in milliseconds.
@export var base_interp_delay_ms: float = 100.0
@export var min_interp_delay_ms: float = 50.0
@export var max_interp_delay_ms: float = 300.0
## Measured jitter is multiplied by this and added to base_interp_delay_ms
## ("the delay adjusts to measured jitter").
@export var jitter_multiplier: float = 2.0
## EMA weight for both the jitter estimate and the delay itself, per snapshot.
## Small means slow, stable adaptation; 1.0 means snap to the newest reading.
@export var interp_delay_smoothing: float = 0.1
## Spec 3.4: "If snapshots are late, extrapolate for at most 100 ms."
@export var max_extrapolation_ms: float = 100.0
## Samples kept per body. At 30 Hz this is half a second of history, enough for
## max_interp_delay_ms plus a late packet.
@export var interp_buffer_samples: int = 16
## How fast the client's render clock may be nudged toward the host's, as a
## fraction of real time per second. Above ~0.2 the correction is visible.
@export var clock_correction_rate: float = 0.15

# --- Intents (spec 3.4 "Client -> host intents") ----------------------------

## Seconds a client keeps its ghost locked after sending a place intent, if no
## feed_block_issued for its slot arrives. Stops a double click from spending
## two blocks; see docs/M3a_PLAN.md "Never duplicated, never lost".
@export var intent_ack_timeout: float = 1.0

# --- Territory replication --------------------------------------------------

## When more than this fraction of cells changed since the last diff, send a
## full compressed raster instead of a cell-by-cell diff.
@export var raster_full_threshold_fraction: float = 0.35
## Compress raster payloads with PackedByteArray.compress (spec 3.4: "territory
## raster diffs (sent compressed at 5 Hz)").
@export var raster_compress: bool = true

# --- Lag / loss simulation (no netem in ENetConnection; see docs/M3a_PLAN.md)

## Extra one-way delay applied to simulated traffic, in milliseconds. 0 is off.
@export var sim_lag_ms: float = 0.0
## Random +-jitter added to sim_lag_ms per packet, in milliseconds.
@export var sim_jitter_ms: float = 0.0
## Fraction of *unreliable* packets dropped, 0..1. Reliable traffic is never
## dropped — that is what reliable means, and dropping it would test nothing.
@export var sim_loss: float = 0.0
## The one-key debug preset, which is exactly spec Part 4 M3's acceptance
## condition: "a client with 100 ms of simulated lag and 2% packet loss".
@export var sim_preset_lag_ms: float = 100.0
@export var sim_preset_loss: float = 0.02

# --- Debug overlay ----------------------------------------------------------

## How often the overlay's numbers refresh, in Hz. Decoupled from snapshot_hz
## so the text is readable.
@export var stats_hz: float = 2.0
## Seconds of history the overlay averages snapshot bytes and loss over.
@export var stats_window: float = 2.0


## The world-space AABB positions are quantized into, for `map_def`. Both ends
## must derive it from the same MapDef, which the host ships in MatchConfig, or
## every body lands in the wrong place.
func position_bounds(map_def: MapDef) -> AABB:
	var half: float = map_def.field_radius * pos_xz_margin
	return AABB(
		Vector3(-half, pos_min_y, -half),
		Vector3(half * 2.0, pos_max_y - pos_min_y, half * 2.0)
	)


## Bodies that fit in one snapshot fragment, given the largest header.
func bodies_per_fragment(header_bytes: int, record_bytes: int) -> int:
	return maxi(1, (max_packet_bytes - header_bytes) / maxi(record_bytes, 1))


## Clamps every field into a sane range. Called on any NetConfig that came from
## a slider or the command line, exactly as MatchConfig.sanitize() is.
func sanitize() -> void:
	discovery_port = clampi(discovery_port, 1024, 65535)
	game_port = clampi(game_port, 1024, 65535)
	max_peers = clampi(max_peers, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	snapshot_hz = clampf(snapshot_hz, 1.0, 60.0)
	raster_diff_hz = clampf(raster_diff_hz, 1.0, 30.0)
	cursor_hz = clampf(cursor_hz, 1.0, 60.0)
	max_packet_bytes = clampi(max_packet_bytes, 256, 1400)
	pos_xz_margin = maxf(pos_xz_margin, 1.0)
	base_interp_delay_ms = clampf(base_interp_delay_ms, min_interp_delay_ms, max_interp_delay_ms)
	interp_delay_smoothing = clampf(interp_delay_smoothing, 0.001, 1.0)
	interp_buffer_samples = maxi(interp_buffer_samples, 4)
	sim_lag_ms = maxf(sim_lag_ms, 0.0)
	sim_jitter_ms = maxf(sim_jitter_ms, 0.0)
	sim_loss = clampf(sim_loss, 0.0, 1.0)
	raster_full_threshold_fraction = clampf(raster_full_threshold_fraction, 0.0, 1.0)
