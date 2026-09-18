class_name Quantize
extends RefCounted
## Wire packing for snapshot body records (spec 3.4 "Snapshots"). Pure static
## functions over PackedByteArray — no nodes, no signals, no engine state — so
## the whole wire format is unit-testable without a peer (CLAUDE.md: core/
## holds pure logic with no scene-tree dependence).
##
## **One body record is exactly BODY_RECORD_BYTES = 14 bytes:**
##
## | offset | size | field |
## |---|---|---|
## | 0 | 2 | `net_id`, u16 little-endian. 0 is reserved as "no body". |
## | 2 | 6 | position, three u16 axes over the match's position AABB |
## | 8 | 6 | rotation, 48-bit smallest-three quaternion + sleeping flag |
##
## Spec 3.4 quotes "~13 bytes"; 14 is what an honest u16 id plus 6+6 costs
## once the sleeping flag is folded into the rotation's spare bit. At 300
## awake bodies that is 4200 B, still spec 3.4's "≈4 KB per packet" before
## fragmentation.
##
## **Position precision.** Each axis maps its NetConfig.position_bounds()
## span linearly onto 0..65535. On map M (field_radius 45) with
## pos_xz_margin 1.5 the X/Z span is 135 m, so one step is 135/65535 =
## **2.06 mm**; the Y span of 120 m gives **1.83 mm**. Spec 3.4 asks for
## "≈1-2 mm precision", which those bracket. Map L (radius 60) widens X/Z to
## 180 m and 2.75 mm — acceptable, and the way to tighten it is
## NetConfig.pos_xz_margin, never a literal here. Values outside the AABB are
## clamped to the nearest face, which only happens to a block already falling
## past the kill plane.
##
## **Rotation precision.** Smallest-three drops the largest-magnitude
## component (recovered as sqrt(1 - sum of squares)) and stores the other
## three over [-SQRT_HALF, +SQRT_HALF] in 15 bits each, plus 2 bits naming the
## dropped index: 47 bits. One spare bit carries the sleeping flag. A 15-bit
## component step is 2*0.7071/32767 = 4.3e-5.
##
## The stub's "under 0.005 degrees" was the *typical* figure, not the bound.
## Measured over 300000 uniformly random quaternions the worst round trip is
## **0.0074 deg**, and the adversarial case — all four components near 0.5,
## where the reconstructed component's sensitivity d(w)/d(x) = x/w reaches 1
## on all three at once — reaches **0.0084 deg**. The honest ceiling is
## therefore **0.009 deg**, which tests/unit/test_quantize.gd asserts. That is
## 0.15 mm of displacement at a 1 m lever arm, an order of magnitude below the
## 2.06 mm position step this same record carries, so rotation is not the
## limiting term and the 48-bit layout stands as specified. Note that
## acos(q.dot(other)) cannot measure this at all: Quaternion holds float32, so
## near dot = 1 that form bottoms out around 0.02 deg. Use the 4D chord,
## theta = 4*asin(|a - b| / 2), as the test does.
##
## Every function takes and returns plain values so a test can assert a
## round-trip without touching a RigidBody3D.
##
## **The 48-bit rotation word**, little-endian across its six bytes:
##
## | bits | field |
## |---|---|
## | 0..14 | first kept component, 15 bits |
## | 15..29 | second kept component |
## | 30..44 | third kept component |
## | 45..46 | index of the dropped (largest) component: 0=x 1=y 2=z 3=w |
## | 47 | sleeping flag |
##
## The kept components are written in ascending component order with the
## dropped one skipped, so the decoder needs nothing but the 2-bit index to
## put them back.

## Bytes in one packed body record.
const BODY_RECORD_BYTES: int = 14
## Bytes in the packed position (three u16 axes).
const POSITION_BYTES: int = 6
## Bytes in the packed rotation + sleeping flag.
const ROTATION_BYTES: int = 6
## Largest value a quantized axis can take.
const AXIS_MAX: int = 65535
## Bits per smallest-three component.
const COMPONENT_BITS: int = 15
## Largest value a quantized quaternion component can take.
const COMPONENT_MAX: int = 32767
## 1/sqrt(2): the largest magnitude the three kept components can have, since
## the dropped one is the largest.
const SQRT_HALF: float = 0.70710678118654752

## Offset of the net_id inside a body record.
const NET_ID_OFFSET: int = 0
## Offset of the packed position inside a body record.
const POSITION_OFFSET: int = 2
## Offset of the packed rotation inside a body record.
const ROTATION_OFFSET: int = 8

## Bit position of the 2-bit dropped-component index in the rotation word.
const DROPPED_INDEX_SHIFT: int = 45
## Bit position of the sleeping flag in the rotation word.
const SLEEPING_SHIFT: int = 47
## Mask for one 15-bit component.
const COMPONENT_MASK: int = 0x7FFF
## Mask for the 2-bit dropped-component index.
const DROPPED_INDEX_MASK: int = 0x3


## `value` mapped linearly onto 0..AXIS_MAX over [min_value, max_value] and
## clamped. Pure; the whole position format is three of these.
static func quantize_axis(value: float, min_value: float, max_value: float) -> int:
	# DECISION (core/net/Quantize.gd): a non-finite axis (a body Jolt pushed to
	# NaN, which a long explosion chain can still do) packs as the low end
	# rather than propagating garbage into the packet. The body is below the
	# kill plane on the host by then and is about to be despawned anyway, and
	# silently sending a plausible number beats an unreadable snapshot.
	if not is_finite(value):
		return 0
	var span: float = max_value - min_value
	if span <= 0.0:
		return 0
	var normalized: float = clampf((value - min_value) / span, 0.0, 1.0)
	return int(roundf(normalized * float(AXIS_MAX)))


## Inverse of quantize_axis(). The result lands within one step of the input.
static func dequantize_axis(raw: int, min_value: float, max_value: float) -> float:
	var span: float = max_value - min_value
	return min_value + float(clampi(raw, 0, AXIS_MAX)) / float(AXIS_MAX) * span


## Writes POSITION_BYTES at `offset` in `out`, which the caller has already
## sized. Returns the offset just past what it wrote.
## The three axes are normalized with Vector3 arithmetic rather than three
## quantize_axis() calls: at 300 bodies and 30 Hz those calls are a measurable
## share of the whole snapshot (tests/bench/bench_snapshot.gd grades it), and
## the component-wise divide and clamp run in the engine. quantize_axis()
## stays the readable statement of the mapping and
## test_quantize.gd asserts the two agree. The one behavioural difference is
## that a non-finite or degenerate *axis* zeroes the whole vector instead of
## just itself — a body with a NaN coordinate is already past the kill plane.
static func pack_position(out: PackedByteArray, offset: int, world: Vector3, bounds: AABB) -> int:
	var normalized: Vector3 = (world - bounds.position) / bounds.size
	if not normalized.is_finite():
		normalized = Vector3.ZERO
	normalized = normalized.clamp(Vector3.ZERO, Vector3.ONE) * float(AXIS_MAX)
	out.encode_u16(offset, int(roundf(normalized.x)))
	out.encode_u16(offset + 2, int(roundf(normalized.y)))
	out.encode_u16(offset + 4, int(roundf(normalized.z)))
	return offset + POSITION_BYTES


## Reads a position written by pack_position(). `bounds` must be the same AABB
## the packer used, or the body lands somewhere else entirely.
static func unpack_position(data: PackedByteArray, offset: int, bounds: AABB) -> Vector3:
	var raw: Vector3 = Vector3(
		float(data.decode_u16(offset)),
		float(data.decode_u16(offset + 2)),
		float(data.decode_u16(offset + 4))
	)
	return bounds.position + raw / float(AXIS_MAX) * bounds.size


## Writes ROTATION_BYTES at `offset`: the smallest-three encoding of `rotation`
## (normalized first; the sign is canonicalized so q and -q pack identically)
## with `sleeping` in the spare bit. Returns the offset just past what it wrote.
static func pack_quat(out: PackedByteArray, offset: int, rotation: Quaternion, sleeping: bool) -> int:
	var q: Quaternion = rotation
	if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
		q = Quaternion.IDENTITY
	elif q.length_squared() < 1e-12:
		# A zero quaternion is not a rotation and Basis() would refuse it.
		q = Quaternion.IDENTITY
	else:
		q = q.normalized()

	# Unrolled on purpose: this runs 300 times per snapshot at 30 Hz, and in
	# GDScript every `for i in range(4)` allocates an Array and every helper
	# call costs more than the arithmetic inside it. See tests/bench/
	# bench_snapshot.gd, which is what grades this.
	var dropped: int = 0
	var largest: float = absf(q.x)
	if absf(q.y) > largest:
		largest = absf(q.y)
		dropped = 1
	if absf(q.z) > largest:
		largest = absf(q.z)
		dropped = 2
	if absf(q.w) > largest:
		largest = absf(q.w)
		dropped = 3

	# The three kept components in ascending order with the dropped one gone.
	var a: float = q.y
	var b: float = q.z
	var c: float = q.w
	var keep_sign: bool = q.x >= 0.0
	match dropped:
		1:
			a = q.x
			b = q.z
			c = q.w
			keep_sign = q.y >= 0.0
		2:
			a = q.x
			b = q.y
			c = q.w
			keep_sign = q.z >= 0.0
		3:
			a = q.x
			b = q.y
			c = q.z
			keep_sign = q.w >= 0.0

	# q and -q are the same rotation, so force the dropped (largest) component
	# positive: the decoder always reconstructs it as a positive square root,
	# and both signs then pack to identical bytes.
	if not keep_sign:
		a = -a
		b = -b
		c = -c

	var scale: float = float(COMPONENT_MAX) / (SQRT_HALF * 2.0)
	var bias: float = SQRT_HALF
	var word: int = (
		int(roundf(clampf((a + bias) * scale, 0.0, float(COMPONENT_MAX))))
		| (int(roundf(clampf((b + bias) * scale, 0.0, float(COMPONENT_MAX)))) << COMPONENT_BITS)
		| (int(roundf(clampf((c + bias) * scale, 0.0, float(COMPONENT_MAX)))) << (COMPONENT_BITS * 2))
		| (dropped << DROPPED_INDEX_SHIFT)
	)
	if sleeping:
		word |= 1 << SLEEPING_SHIFT
	out.encode_u32(offset, word & 0xFFFFFFFF)
	out.encode_u16(offset + 4, (word >> 32) & 0xFFFF)
	return offset + ROTATION_BYTES


## Reads a rotation written by pack_quat(). Always returns a normalized
## quaternion.
static func unpack_quat(data: PackedByteArray, offset: int) -> Quaternion:
	var word: int = data.decode_u32(offset) | (data.decode_u16(offset + 4) << 32)
	var scale: float = (SQRT_HALF * 2.0) / float(COMPONENT_MAX)
	var a: float = float(word & COMPONENT_MASK) * scale - SQRT_HALF
	var b: float = float((word >> COMPONENT_BITS) & COMPONENT_MASK) * scale - SQRT_HALF
	var c: float = float((word >> (COMPONENT_BITS * 2)) & COMPONENT_MASK) * scale - SQRT_HALF
	var sum_of_squares: float = a * a + b * b + c * c
	# Unit by construction whenever the three kept components still fit inside
	# the sphere, which rounding only breaks by an ulp, so the normalize below
	# is a guard rather than a step.
	var d: float = sqrt(maxf(0.0, 1.0 - sum_of_squares))

	var result: Quaternion = Quaternion(a, b, c, d)
	match (word >> DROPPED_INDEX_SHIFT) & DROPPED_INDEX_MASK:
		0:
			result = Quaternion(d, a, b, c)
		1:
			result = Quaternion(a, d, b, c)
		2:
			result = Quaternion(a, b, d, c)
	if sum_of_squares > 1.0:
		return result.normalized()
	return result


## The sleeping flag from the same six bytes unpack_quat() reads.
static func unpack_sleeping(data: PackedByteArray, offset: int) -> bool:
	return (data[offset + ROTATION_BYTES - 1] >> 7) & 1 == 1


## One quaternion component in [-SQRT_HALF, SQRT_HALF] as a 15-bit integer.
static func quantize_component(value: float) -> int:
	if not is_finite(value):
		return COMPONENT_MAX / 2
	var normalized: float = clampf((value + SQRT_HALF) / (SQRT_HALF * 2.0), 0.0, 1.0)
	return int(roundf(normalized * float(COMPONENT_MAX)))


## Inverse of quantize_component().
static func dequantize_component(raw: int) -> float:
	return (
		float(clampi(raw, 0, COMPONENT_MAX)) / float(COMPONENT_MAX) * (SQRT_HALF * 2.0)
		- SQRT_HALF
	)


## Writes one whole BODY_RECORD_BYTES record. Returns the offset just past it.
static func pack_body(
	out: PackedByteArray,
	offset: int,
	net_id: int,
	world: Vector3,
	rotation: Quaternion,
	sleeping: bool,
	bounds: AABB
) -> int:
	out.encode_u16(offset + NET_ID_OFFSET, net_id & 0xFFFF)
	pack_position(out, offset + POSITION_OFFSET, world, bounds)
	pack_quat(out, offset + ROTATION_OFFSET, rotation, sleeping)
	return offset + BODY_RECORD_BYTES


## Reads one record into {"net_id": int, "position": Vector3,
## "rotation": Quaternion, "sleeping": bool}. A Dictionary rather than a class
## so net/Interpolator.gd can store it without core/ knowing about it.
static func unpack_body(data: PackedByteArray, offset: int, bounds: AABB) -> Dictionary:
	if offset < 0 or offset + BODY_RECORD_BYTES > data.size():
		return {}
	return {
		"net_id": data.decode_u16(offset + NET_ID_OFFSET),
		"position": unpack_position(data, offset + POSITION_OFFSET, bounds),
		"rotation": unpack_quat(data, offset + ROTATION_OFFSET),
		"sleeping": unpack_sleeping(data, offset + ROTATION_OFFSET),
	}


