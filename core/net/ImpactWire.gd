class_name ImpactWire
extends RefCounted
## Wire packing and host-side selection for replicated block impacts
## (Bontago-1pi.55). Only the host runs physics, so only the host's
## game/Block.gd ever detects a real landing; net/MatchNet.gd collects those
## detections, coalesces and caps them, and ships them to clients as one small
## unreliable batch per NetConfig.impact_batch_hz, where they are re-emitted on
## the same Events.block_impacted / block_impacted_at pair the host's own
## consumers (Sfx thud, camera shake, rumble, landing dust, birds) already use.
## Pure functions over PackedByteArray, no nodes, no signals (CLAUDE.md: core/
## holds pure logic) -- the same style as core/net/CircleWire.gd.
##
## **Layout**, little-endian throughout:
##
## | offset | size | field |
## |---|---|---|
## | 0 | 1 | version (VERSION) |
## | 1 | 1 | event_count, u8 (1..MAX_EVENTS) |
## | 2 | event_count * 9 | event records |
##
## **One event record** (EVENT_BYTES = 9): x, y, z as s16 in POSITION_QUANTUM_M
## steps (+-327 m, 1 cm), speed as u16 in SPEED_QUANTUM steps (m/s), age_ms as
## u8 -- how long before the send the host detected it, so the client can line
## the sound up with its interpolated view (MatchNet.receive_impacts()).
##
## DECISION (core/net/ImpactWire.gd): events carry a world position, not a
## block net_id. Every consumer only needs speed and position, and a
## position-keyed event has no ordering dependency on the reliable
## net_block_spawned / net_block_despawned stream: an impact that outruns its
## block's spawn RPC, or trails its despawn, still plays where it happened
## instead of being dropped as "unknown id".
##
## The quanta and field widths are architecture (both ends must agree for the
## bytes to mean anything), so they are consts here like Quantize's and
## CircleWire's; the caps and rates that are tunables live in NetConfig.

const VERSION: int = 1
const HEADER_BYTES: int = 2
const EVENT_BYTES: int = 9
## event_count is a u8.
const MAX_EVENTS: int = 255
const MAX_PACKET_BYTES: int = HEADER_BYTES + MAX_EVENTS * EVENT_BYTES
const POSITION_QUANTUM_M: float = 0.01
const SPEED_QUANTUM: float = 0.01
const AXIS_RAW_LIMIT: int = 32767
const SPEED_RAW_MAX: int = 65535
const AGE_MAX_MS: int = 255

## Event dictionary keys shared by encode(), decode() and MatchNet.
const KEY_SPEED: String = "speed"
const KEY_POSITION: String = "position"
const KEY_AGE_MS: String = "age_ms"
## Host-side only (never encoded): when the impact was detected, in
## Time.get_ticks_msec(), so flush_impacts() can turn it into KEY_AGE_MS.
const KEY_TIME_MS: String = "time_ms"


## True when `position` survives the s16 axis encoding without clamping.
static func position_fits(position: Vector3) -> bool:
	if not position.is_finite():
		return false
	var limit: float = float(AXIS_RAW_LIMIT) * POSITION_QUANTUM_M
	return absf(position.x) <= limit and absf(position.y) <= limit and absf(position.z) <= limit


## The coalescing bucket an impact at `position` falls into: impacts landing in
## the same `cell_m` cube within one batch window collapse to the strongest.
## A non-positive cell size disables spatial merging (every distinct position
## is its own bucket).
static func coalesce_key(position: Vector3, cell_m: float) -> Vector3i:
	if cell_m <= 0.0:
		return Vector3i(
			roundi(position.x / POSITION_QUANTUM_M),
			roundi(position.y / POSITION_QUANTUM_M),
			roundi(position.z / POSITION_QUANTUM_M)
		)
	return Vector3i(
		floori(position.x / cell_m), floori(position.y / cell_m), floori(position.z / cell_m)
	)


## Most events that fit in one packet of `payload_bytes` (the NetConfig
## max_packet_bytes snapshot budget, which already leaves room under the
## ~1500 B Ethernet MTU for the RPC, ENet and UDP/IP headers): the count whose
## HEADER_BYTES + n * EVENT_BYTES stays inside it, at least 1 and at most
## MAX_EVENTS. Both host (batch cap) and client (accept cap) derive their
## MTU-safe bound from this one function, so an oversized batch can never be
## built or believed.
static func max_events_for_payload(payload_bytes: int) -> int:
	return clampi((payload_bytes - HEADER_BYTES) / EVENT_BYTES, 1, MAX_EVENTS)


## True when `position` is an impact the client would accept: it survives the
## s16 axis encoding (position_fits) and its height lies in [min_y, max_y]
## (the quantized volume, NetConfig.pos_min_y/pos_max_y). The host filters with
## this before encoding so an out-of-volume impact (a block launched past the
## tallest tower, one falling below the kill plane) is skipped on its own
## instead of reaching a client that would have to drop it.
static func position_in_range(position: Vector3, min_y: float, max_y: float) -> bool:
	return position_fits(position) and position.y >= min_y and position.y <= max_y


## The `count` strongest events of `events` (Dictionaries with KEY_SPEED),
## strongest first. The order of equal-speed events is unspecified (Godot's
## sort_custom is not stable).
static func strongest(events: Array[Dictionary], count: int) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = events.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a[KEY_SPEED]) > float(b[KEY_SPEED])
	)
	if count < sorted.size():
		sorted.resize(maxi(count, 0))
	return sorted


## Packs `events` (KEY_SPEED float m/s, KEY_POSITION Vector3, KEY_AGE_MS int).
## Callers pass at most MAX_EVENTS events that already passed position_in_range();
## speed and age are clamped into their fields here. Empty input -> empty
## packet (nothing to send).
static func encode(events: Array[Dictionary]) -> PackedByteArray:
	var count: int = mini(events.size(), MAX_EVENTS)
	var out: PackedByteArray = PackedByteArray()
	if count == 0:
		return out
	out.resize(HEADER_BYTES + count * EVENT_BYTES)
	out.encode_u8(0, VERSION)
	out.encode_u8(1, count)
	var offset: int = HEADER_BYTES
	for i: int in range(count):
		var event: Dictionary = events[i]
		var position: Vector3 = event[KEY_POSITION] as Vector3
		out.encode_s16(offset, _axis_raw(position.x))
		out.encode_s16(offset + 2, _axis_raw(position.y))
		out.encode_s16(offset + 4, _axis_raw(position.z))
		var speed_raw: int = clampi(roundi(float(event[KEY_SPEED]) / SPEED_QUANTUM), 0, SPEED_RAW_MAX)
		out.encode_u16(offset + 6, speed_raw)
		out.encode_u8(offset + 8, clampi(int(event[KEY_AGE_MS]), 0, AGE_MAX_MS))
		offset += EVENT_BYTES
	return out


## Unpacks a batch. A malformed *packet* -- wrong version, a count that does
## not match the byte length, a zero count -- yields an empty array. A bad
## *event* inside an otherwise well-formed packet -- a speed outside
## (0, speed_max], a height outside [min_y, max_y] -- is skipped on its own and
## the rest of the batch survives (one legitimate out-of-volume impact must not
## silence its neighbours). At most `max_events` valid events are returned
## (strongest-first on the wire, so the tail is what is dropped).
##
## `speed_max` is compared with one SPEED_QUANTUM of slack: encode() rounds to
## the nearest SPEED_QUANTUM, so a host clamp that is not a multiple of it can
## round a hair above itself and must still decode.
static func decode(
	packet: PackedByteArray, speed_max: float, min_y: float, max_y: float, max_events: int = MAX_EVENTS
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if packet.size() < HEADER_BYTES or packet.size() > MAX_PACKET_BYTES:
		return events
	if packet.decode_u8(0) != VERSION:
		return events
	var count: int = packet.decode_u8(1)
	if count == 0 or packet.size() != HEADER_BYTES + count * EVENT_BYTES:
		return events
	var event_cap: int = clampi(max_events, 1, MAX_EVENTS)
	var offset: int = HEADER_BYTES
	for _i: int in range(count):
		if events.size() >= event_cap:
			break
		var position: Vector3 = Vector3(
			float(packet.decode_s16(offset)) * POSITION_QUANTUM_M,
			float(packet.decode_s16(offset + 2)) * POSITION_QUANTUM_M,
			float(packet.decode_s16(offset + 4)) * POSITION_QUANTUM_M
		)
		var speed: float = float(packet.decode_u16(offset + 6)) * SPEED_QUANTUM
		var age_ms: int = packet.decode_u8(offset + 8)
		offset += EVENT_BYTES
		if speed <= 0.0 or speed > speed_max + SPEED_QUANTUM:
			continue
		if position.y < min_y or position.y > max_y:
			continue
		events.append({KEY_SPEED: speed, KEY_POSITION: position, KEY_AGE_MS: age_ms})
	return events


static func _axis_raw(value: float) -> int:
	return clampi(roundi(value / POSITION_QUANTUM_M), -AXIS_RAW_LIMIT, AXIS_RAW_LIMIT)
