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
## Every fragment is independently decodable — it carries the whole header and
## whole body records — so an unreliable channel losing one costs only those
## bodies for one interval, never the snapshot. The disk state rides fragment 0
## alone (that is "every snapshot", not "every packet"): repeating 12 bytes on
## all four fragments would buy nothing an unreliable link can use, and
## bodies_per_fragment() already sizes every fragment against the larger
## header so the cap is uniform.
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

## Field offsets inside the fragment header.
const OFFSET_VERSION: int = 0
const OFFSET_SEQUENCE: int = 1
const OFFSET_FRAGMENT_INDEX: int = 3
const OFFSET_FRAGMENT_COUNT: int = 4
const OFFSET_HOST_TIME: int = 5
const OFFSET_FLAGS: int = 9
const OFFSET_BODY_COUNT: int = 10

## Sequence numbers are u16 on the wire.
const SEQUENCE_MODULUS: int = 65536
## A fragment_count of 0 is meaningless and 255 is the u8 ceiling.
const MAX_FRAGMENTS: int = 255

@export var config: NetConfig = preload("res://config/net_config.tres")

# --- Shared state -----------------------------------------------------------

var _registry: BlockRegistry = null
var _bounds: AABB = AABB()
var _running: bool = false

# --- Host state -------------------------------------------------------------

## instance id (int) -> Block, every body this instance has seen spawn.
##
## DECISION (net/SnapshotSync.gd): BlockRegistry exposes block_for_net_id() but
## no "every live body" accessor, and P2 does not own that file (docs/M3a_PLAN.md
## file ownership). Mirroring the set from Events.block_placed /
## Events.block_removed — the same bus BlockRegistry itself listens on — costs
## one Dictionary and keeps the package boundary intact. net_id is read at
## snapshot time, not at signal time, so the two handlers' order does not
## matter.
var _bodies: Dictionary = {}

## net_id (int) -> [position: Vector3, rotation: Quaternion], what each body
## looked like the last time it went out, for the resend epsilon test.
var _last_sent: Dictionary = {}

var _send_accumulator: float = 0.0
var _sequence: int = 0
var _host_clock_ms: float = 0.0
var _last_snapshot_bytes: int = 0
var _keyframe_cursor: int = 0
var _disk: Node3D = null

# --- Client state -----------------------------------------------------------

var _interpolator: Interpolator = null
var _last_noted_sequence: int = -1
var _disk_position: Vector3 = Vector3.ZERO
var _disk_rotation: Quaternion = Quaternion.IDENTITY
var _stats_accumulator: float = 0.0

## Seconds since begin_match(): the one time base the NetSim queue and the
## Interpolator's jitter estimate share. It has to be read at *arrival*, not
## accumulated from _physics_process's delta, or every packet in a tick would
## be stamped with the same time and the jitter estimate would measure the
## 60 Hz tick grid instead of the link.
var _clock_base_usec: int = 0
## Test seam: a Callable returning that same "seconds since begin_match",
## so a unit test can script arrival times instead of waiting for them.
var _clock_source: Callable = Callable()


# --- Lifecycle --------------------------------------------------------------

## Called by Match when a match starts, on both host and client. `registry` is
## the BlockRegistry that resolves net_id -> Block; `map_def` fixes the
## quantization bounds, so both ends must be handed the same one.
func begin_match(registry: BlockRegistry, map_def: MapDef) -> void:
	end_match()
	_registry = registry
	_bounds = config.position_bounds(map_def)
	_running = true
	_sequence = 0
	_host_clock_ms = 0.0
	_send_accumulator = 0.0
	_clock_base_usec = Time.get_ticks_usec()
	_stats_accumulator = 0.0
	_last_noted_sequence = -1
	_last_snapshot_bytes = 0
	_keyframe_cursor = 0

	_interpolator = Interpolator.new(config)
	_interpolator.set_known_id_filter(_is_spawned)

	if not Events.block_placed.is_connected(_on_block_placed):
		Events.block_placed.connect(_on_block_placed)
	if not Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.connect(_on_block_removed)
	if not Events.block_replicated.is_connected(_on_block_replicated):
		Events.block_replicated.connect(_on_block_replicated)


## Stops sending and drops every buffer. Called when a match ends or the
## session closes.
func end_match() -> void:
	if Events.block_placed.is_connected(_on_block_placed):
		Events.block_placed.disconnect(_on_block_placed)
	if Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.disconnect(_on_block_removed)
	if Events.block_replicated.is_connected(_on_block_replicated):
		Events.block_replicated.disconnect(_on_block_replicated)
	_running = false
	_registry = null
	_bodies.clear()
	_last_sent.clear()
	if _interpolator != null:
		_interpolator.clear()
	_interpolator = null


func is_running() -> bool:
	return _running


## The disk, so its tilt can ride every snapshot (spec 3.4 "Disk state"). Main
## hands it over when it builds the world; until M4 the disk never moves, which
## is exactly why sending it now costs nothing and changes no wire format later.
func set_disk(disk: Node3D) -> void:
	_disk = disk


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
	if not _running or not Net.is_host() or Net.is_offline():
		return
	_host_clock_ms += delta * 1000.0
	_send_accumulator += delta
	var interval: float = 1.0 / maxf(config.snapshot_hz, 1.0)
	if _send_accumulator < interval:
		return
	# One snapshot per tick even after a long frame: catching up by sending two
	# at once would only make the client's jitter estimate worse.
	_send_accumulator = fmod(_send_accumulator, interval)

	var selection: Dictionary = _select_bodies()
	var bodies: Array = selection["bodies"] as Array
	var flags: int = FLAG_DISK_STATE
	if bool(selection["keyframe"]):
		flags |= FLAG_KEYFRAME

	_sequence = (_sequence + 1) % SEQUENCE_MODULUS
	var packets: Array[PackedByteArray] = build_snapshot(
		_sequence, int(_host_clock_ms), flags, bodies, _disk_transform(), _bounds, config
	)
	_last_snapshot_bytes = 0
	for packet: PackedByteArray in packets:
		_last_snapshot_bytes += packet.size()
	_remember_sent(bodies)

	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		for packet: PackedByteArray in packets:
			net_snapshot.rpc(packet)

	Net.report_stats(&"snapshot", {
		"snapshot_last_bytes": _last_snapshot_bytes,
		"snapshot_bodies": bodies.size(),
		"snapshot_fragments": packets.size(),
		"snapshot_sequence": _sequence,
	})


## Sleeping bodies refreshed per snapshot so every sleeper is re-sent once per
## config.keyframe_interval (spec 3.4's 2 s keyframe), round-robin.
func keyframe_slice_size() -> int:
	return keyframe_slice_for(_count_sleeping(), config)


## Sleepers per snapshot needed to refresh `sleeping_count` of them once per
## config.keyframe_interval. Static so the benchmark and the tests can ask
## without a live match.
static func keyframe_slice_for(sleeping_count: int, net_config: NetConfig) -> int:
	if sleeping_count <= 0:
		return 0
	var ticks: float = maxf(net_config.keyframe_interval, 0.001) * maxf(net_config.snapshot_hz, 1.0)
	return maxi(1, int(ceil(float(sleeping_count) / maxf(ticks, 1.0))))


## Bytes the last snapshot cost, summed over its fragments — the debug
## overlay's "snapshot size".
func last_snapshot_bytes() -> int:
	return _last_snapshot_bytes


func last_sequence() -> int:
	return _sequence


# --- Client side ------------------------------------------------------------

## Advances every synced body to the current render time. **Call from
## _physics_process only.** Client only.
func client_tick(delta: float) -> void:
	if not _running or not Net.is_client() or _interpolator == null:
		return

	var sim: NetSim = Net.simulation()
	if sim != null and not sim.is_idle():
		for payload: Variant in sim.drain(now()):
			_apply_packet(payload as PackedByteArray)

	_interpolator.advance(delta)

	for net_id: int in _interpolator.tracked_ids():
		var block: Block = _registry.block_for_net_id(net_id) if _registry != null else null
		if block == null or not is_instance_valid(block):
			continue
		freeze_body(block)
		var pose: Dictionary = _interpolator.sample_at_render_time(net_id)
		if not bool(pose["ok"]):
			continue
		# Writing global_transform here and nowhere else is the whole trick:
		# physics_interpolation smooths this 30 Hz stream up to the display rate
		# by itself, and a write from _process would fight it (docs/M3a_PLAN.md
		# "Frozen bodies").
		block.global_transform = Transform3D(
			Basis(pose["rotation"] as Quaternion), pose["position"] as Vector3
		)

	_stats_accumulator += delta
	var stats_interval: float = 1.0 / maxf(config.stats_hz, 0.1)
	if _stats_accumulator >= stats_interval:
		_stats_accumulator = 0.0
		Net.report_stats(&"snapshot", {
			"snapshot_last_bytes": _last_snapshot_bytes,
			"interp_delay_ms": interpolation_delay_ms(),
			"loss_pct": measured_loss() * 100.0,
			"dropped_unknown": _interpolator.dropped_unknown_count(),
		})


## The adaptive interpolation delay in force right now, in milliseconds —
## config.base_interp_delay_ms plus jitter_multiplier x measured jitter,
## clamped. The debug overlay shows this.
func interpolation_delay_ms() -> float:
	return _interpolator.delay_ms() if _interpolator != null else config.base_interp_delay_ms


## Snapshots the client noticed were missing, as a fraction of those expected,
## measured from gaps in the sequence numbers. The overlay's "packet loss".
func measured_loss() -> float:
	return _interpolator.loss_fraction() if _interpolator != null else 0.0


func interpolator() -> Interpolator:
	return _interpolator


## The disk pose the last snapshot carried, in world space. Until M4 the disk
## is static, so this only proves the channel works; Field reads it from M4 on.
func disk_position() -> Vector3:
	return _disk_position


func disk_rotation() -> Quaternion:
	return _disk_rotation


## Puts one body into the state a client keeps every synced body in: kinematic
## freeze, so Jolt never integrates it and only the interpolator's writes move
## it (spec 3.4: "Clients set every synced RigidBody3D to freeze = true").
static func freeze_body(body: RigidBody3D) -> void:
	if body.freeze and body.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC:
		return
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


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
	var has_disk: bool = (flags & FLAG_DISK_STATE) != 0
	var header_bytes: int = HEADER_BYTES + (DISK_STATE_BYTES if has_disk else 0)
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(header_bytes + bodies.size() * Quantize.BODY_RECORD_BYTES)

	packet[OFFSET_VERSION] = PACKET_VERSION
	packet.encode_u16(OFFSET_SEQUENCE, posmod(sequence, SEQUENCE_MODULUS))
	packet[OFFSET_FRAGMENT_INDEX] = fragment_index & 0xFF
	packet[OFFSET_FRAGMENT_COUNT] = fragment_count & 0xFF
	packet.encode_u32(OFFSET_HOST_TIME, host_time_ms & 0xFFFFFFFF)
	packet[OFFSET_FLAGS] = flags & 0xFF
	packet.encode_u16(OFFSET_BODY_COUNT, bodies.size() & 0xFFFF)

	var offset: int = HEADER_BYTES
	if has_disk:
		offset = Quantize.pack_position(packet, offset, disk_transform.origin, bounds)
		offset = Quantize.pack_quat(packet, offset, disk_transform.basis.get_rotation_quaternion(), false)

	for entry: Variant in bodies:
		var body: Dictionary = entry as Dictionary
		offset = Quantize.pack_body(
			packet,
			offset,
			int(body["net_id"]),
			body["position"] as Vector3,
			body["rotation"] as Quaternion,
			bool(body["sleeping"]),
			bounds
		)
	return packet


## Unpacks a fragment into {"sequence", "fragment_index", "fragment_count",
## "host_time_ms", "flags", "bodies", "disk_transform"}. Returns an empty
## Dictionary for a truncated, foreign or wrong-version packet — never an
## error, because an unreliable channel will eventually deliver garbage.
static func decode_fragment(packet: PackedByteArray, bounds: AABB) -> Dictionary:
	if packet.size() < HEADER_BYTES:
		return {}
	if packet[OFFSET_VERSION] != PACKET_VERSION:
		return {}

	var fragment_count: int = packet[OFFSET_FRAGMENT_COUNT]
	var fragment_index: int = packet[OFFSET_FRAGMENT_INDEX]
	if fragment_count < 1 or fragment_count > MAX_FRAGMENTS or fragment_index >= fragment_count:
		return {}

	var flags: int = packet[OFFSET_FLAGS]
	var has_disk: bool = (flags & FLAG_DISK_STATE) != 0
	var body_count: int = packet.decode_u16(OFFSET_BODY_COUNT)
	var header_bytes: int = HEADER_BYTES + (DISK_STATE_BYTES if has_disk else 0)
	# Exact, not "at least": a random payload that happens to start with the
	# right version byte is far likelier to be the wrong length than the right
	# one, and a truncated fragment must not decode to half a body list.
	if packet.size() != header_bytes + body_count * Quantize.BODY_RECORD_BYTES:
		return {}

	var offset: int = HEADER_BYTES
	var disk_transform: Transform3D = Transform3D.IDENTITY
	if has_disk:
		var disk_origin: Vector3 = Quantize.unpack_position(packet, offset, bounds)
		offset += Quantize.POSITION_BYTES
		var disk_rotation: Quaternion = Quantize.unpack_quat(packet, offset)
		offset += Quantize.ROTATION_BYTES
		disk_transform = Transform3D(Basis(disk_rotation), disk_origin)

	var bodies: Array = []
	bodies.resize(body_count)
	for index: int in range(body_count):
		bodies[index] = Quantize.unpack_body(packet, offset, bounds)
		offset += Quantize.BODY_RECORD_BYTES

	return {
		"sequence": packet.decode_u16(OFFSET_SEQUENCE),
		"fragment_index": fragment_index,
		"fragment_count": fragment_count,
		"host_time_ms": packet.decode_u32(OFFSET_HOST_TIME),
		"flags": flags,
		"bodies": bodies,
		"disk_transform": disk_transform,
	}


## Splits `bodies` across as few fragments as config.max_packet_bytes allows
## and encodes each. Always returns at least one fragment, so an empty snapshot
## still carries the disk state and keeps the sequence advancing.
static func build_snapshot(
	sequence: int,
	host_time_ms: int,
	flags: int,
	bodies: Array,
	disk_transform: Transform3D,
	bounds: AABB,
	net_config: NetConfig
) -> Array[PackedByteArray]:
	var per_fragment: int = net_config.bodies_per_fragment(
		HEADER_BYTES + DISK_STATE_BYTES, Quantize.BODY_RECORD_BYTES
	)
	var fragment_count: int = maxi(
		1, int(ceil(float(bodies.size()) / float(maxi(per_fragment, 1))))
	)
	fragment_count = mini(fragment_count, MAX_FRAGMENTS)

	var packets: Array[PackedByteArray] = []
	for index: int in range(fragment_count):
		var first: int = index * per_fragment
		var slice: Array = bodies.slice(first, mini(first + per_fragment, bodies.size()))
		# Only fragment 0 carries the disk; see the class docs.
		var fragment_flags: int = flags if index == 0 else flags & ~FLAG_DISK_STATE
		packets.append(encode_fragment(
			sequence, index, fragment_count, host_time_ms, fragment_flags,
			slice, disk_transform, bounds
		))
	return packets


# --- RPC --------------------------------------------------------------------

## Host -> clients. Unreliable on config.snapshot_channel; the sequence number
## in the payload is what makes late and duplicate delivery detectable.
@rpc("authority", "call_remote", "unreliable", SNAPSHOT_CHANNEL)
func net_snapshot(packet: PackedByteArray) -> void:
	receive_packet(packet)


## The RPC's body, reachable without a peer so a test can drive the whole
## client path. Unreliable traffic is droppable, which is what makes
## --sim-loss simulate a lossy link rather than break reliability.
func receive_packet(packet: PackedByteArray) -> void:
	if not _running or _interpolator == null:
		return
	var sim: NetSim = Net.simulation()
	if sim != null and not sim.is_idle():
		sim.submit(packet, now(), true)
		return
	_apply_packet(packet)


## Seconds since begin_match(), on the client's arrival clock. See
## _clock_source; tests replace it with set_clock_source().
func now() -> float:
	if _clock_source.is_valid():
		return float(_clock_source.call())
	return float(Time.get_ticks_usec() - _clock_base_usec) / 1000000.0


## Injects the arrival clock. Pass an invalid Callable to go back to real time.
func set_clock_source(source: Callable) -> void:
	_clock_source = source


# --- Internals --------------------------------------------------------------

func _apply_packet(packet: PackedByteArray) -> void:
	var fragment: Dictionary = decode_fragment(packet, _bounds)
	if fragment.is_empty():
		return

	var sequence: int = int(fragment["sequence"])
	var host_time_ms: int = int(fragment["host_time_ms"])
	# One note per snapshot, not per fragment (Interpolator.note_snapshot).
	if sequence != _last_noted_sequence:
		_last_noted_sequence = sequence
		_interpolator.note_snapshot(sequence, host_time_ms, now())

	if (int(fragment["flags"]) & FLAG_DISK_STATE) != 0:
		var disk_transform: Transform3D = fragment["disk_transform"] as Transform3D
		_disk_position = disk_transform.origin
		_disk_rotation = disk_transform.basis.get_rotation_quaternion()

	for entry: Variant in fragment["bodies"] as Array:
		var body: Dictionary = entry as Dictionary
		_interpolator.push_sample(
			int(body["net_id"]),
			host_time_ms,
			body["position"] as Vector3,
			body["rotation"] as Quaternion,
			bool(body["sleeping"])
		)


## The predicate Interpolator asks before buffering a sample: a net_id whose
## reliable spawn RPC has not landed yet is unknown, and its sample is dropped
## and counted (docs/M3a_PLAN.md "net_id allocation and the spawn/snapshot
## race").
func _is_spawned(net_id: int) -> bool:
	if _registry == null:
		return true
	return _registry.block_for_net_id(net_id) != null


## {"bodies": Array, "keyframe": bool} for this tick.
func _select_bodies() -> Dictionary:
	var awake_or_moved: Array = []
	var sleepers: Array[Block] = []

	for key: Variant in _bodies.keys():
		var block: Block = _bodies[key] as Block
		if block == null or not is_instance_valid(block):
			_bodies.erase(key)
			continue
		if block.net_id <= 0:
			continue
		if not block.sleeping or _moved_since_sent(block):
			awake_or_moved.append(_record(block))
		else:
			sleepers.append(block)

	var slice: int = mini(keyframe_slice_for(sleepers.size(), config), sleepers.size())
	var keyframe: bool = slice > 0
	for step: int in range(slice):
		var block: Block = sleepers[(_keyframe_cursor + step) % sleepers.size()]
		awake_or_moved.append(_record(block))
	if not sleepers.is_empty():
		_keyframe_cursor = (_keyframe_cursor + slice) % sleepers.size()

	return {"bodies": awake_or_moved, "keyframe": keyframe}


func _record(block: Block) -> Dictionary:
	return {
		"net_id": block.net_id,
		"position": block.global_position,
		"rotation": block.global_basis.get_rotation_quaternion(),
		"sleeping": block.sleeping,
	}


## True when a sleeping body drifted past config.resend_position_epsilon or
## resend_angle_epsilon since it was last sent, so a body that only wobbled
## inside its own quantization bucket never costs a packet.
func _moved_since_sent(block: Block) -> bool:
	var previous: Variant = _last_sent.get(block.net_id)
	if previous == null:
		return true
	var state: Array = previous as Array
	var last_position: Vector3 = state[0] as Vector3
	if block.global_position.distance_to(last_position) > config.resend_position_epsilon:
		return true
	var last_rotation: Quaternion = state[1] as Quaternion
	var current: Quaternion = block.global_basis.get_rotation_quaternion()
	return rad_to_deg(current.angle_to(last_rotation)) > config.resend_angle_epsilon


func _remember_sent(bodies: Array) -> void:
	for entry: Variant in bodies:
		var body: Dictionary = entry as Dictionary
		_last_sent[int(body["net_id"])] = [body["position"], body["rotation"]]


func _count_sleeping() -> int:
	var count: int = 0
	for key: Variant in _bodies.keys():
		var block: Block = _bodies[key] as Block
		if block != null and is_instance_valid(block) and block.net_id > 0 and block.sleeping:
			count += 1
	return count


func _disk_transform() -> Transform3D:
	if _disk != null and is_instance_valid(_disk):
		return _disk.global_transform
	return Transform3D.IDENTITY


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	_track(block)


func _on_block_replicated(block: RigidBody3D, _net_id: int) -> void:
	_track(block)
	if Net.is_client():
		freeze_body(block)


func _track(block: RigidBody3D) -> void:
	var typed: Block = block as Block
	if typed == null:
		return
	_bodies[typed.get_instance_id()] = typed


func _on_block_removed(block: RigidBody3D, _reason: String) -> void:
	_bodies.erase(block.get_instance_id())
	var typed: Block = block as Block
	if typed == null:
		return
	_last_sent.erase(typed.net_id)
	if _interpolator != null:
		_interpolator.forget(typed.net_id)
