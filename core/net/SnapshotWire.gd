class_name SnapshotWire
extends RefCounted
## The snapshot packet format (spec 2.6 "Snapshots"): pure static encode and
## decode over PackedByteArray, so the whole wire can be asserted without a
## peer, a registry or a scene tree. net/SnapshotSync.gd owns the RPC and the
## selection and interpolation around it; the bytes live here.
##
## **Wire layout** — one fragment, little-endian throughout. Bodies are packed
## by core/net/Quantize.gd, 15 bytes each (u24 net_id; see its DECISION).
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
## | 12 | 12 | disk state, only when FLAG_DISK_STATE: 6 B quantized offset + 6 B tilt quaternion (spec 2.6 "Disk state: tilt quaternion and position offset, sent every snapshot") |
## | .. | 15 x body_count | body records |
##
## The header is HEADER_BYTES (12) or HEADER_BYTES + DISK_STATE_BYTES (24);
## NetConfig.bodies_per_fragment() turns that into the per-fragment body cap,
## which at 1200 bytes is 78 bodies, so spec 2.6's 300 awake bodies take four
## fragments.
##
## Every fragment is independently decodable — it carries the whole header and
## whole body records — so an unreliable channel losing one costs only those
## bodies for one interval, never the snapshot. The disk state rides fragment 0
## alone (that is "every snapshot", not "every packet"): repeating 12 bytes on
## all four fragments would buy nothing an unreliable link can use, and
## bodies_per_fragment() already sizes every fragment against the larger
## header so the cap is uniform.

## Bumped whenever the layout above changes. A mismatched version is dropped
## rather than misread; the build-version handshake in Net should already have
## refused the peer, so this is a belt-and-braces check.
## 2: the body record's net_id grew from u16 to u24.
const PACKET_VERSION: int = 2

const HEADER_BYTES: int = 12
const DISK_STATE_BYTES: int = 12

const FLAG_DISK_STATE: int = 1 << 0
const FLAG_KEYFRAME: int = 1 << 1

## Snapshots ride their own channel so a burst of them cannot head-of-line
## block the reliable stream (spec 2.6 "Channels"). @rpc needs a compile-time
## constant, so the number lives with the wire rather than in NetConfig, which
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
		var origin: Vector3 = Quantize.unpack_position(packet, offset, bounds)
		offset += Quantize.POSITION_BYTES
		var tilt: Quaternion = Quantize.unpack_quat(packet, offset)
		offset += Quantize.ROTATION_BYTES
		disk_transform = Transform3D(Basis(tilt), origin)

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
