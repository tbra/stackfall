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
## component step is 2*0.7071/32767 = 4.3e-5, i.e. a worst-case angular error
## under **0.005 degrees** — far below anything visible on a 1 m cube.
##
## Every function takes and returns plain values so a test can assert a
## round-trip without touching a RigidBody3D.

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

@warning_ignore_start("unused_parameter")


## `value` mapped linearly onto 0..AXIS_MAX over [min_value, max_value] and
## clamped. Pure; the whole position format is three of these.
static func quantize_axis(value: float, min_value: float, max_value: float) -> int:
	return 0


## Inverse of quantize_axis(). The result lands within one step of the input.
static func dequantize_axis(raw: int, min_value: float, max_value: float) -> float:
	return 0.0


## Writes POSITION_BYTES at `offset` in `out`, which the caller has already
## sized. Returns the offset just past what it wrote.
static func pack_position(out: PackedByteArray, offset: int, world: Vector3, bounds: AABB) -> int:
	return offset + POSITION_BYTES


## Reads a position written by pack_position(). `bounds` must be the same AABB
## the packer used, or the body lands somewhere else entirely.
static func unpack_position(data: PackedByteArray, offset: int, bounds: AABB) -> Vector3:
	return Vector3.ZERO


## Writes ROTATION_BYTES at `offset`: the smallest-three encoding of `rotation`
## (normalized first; the sign is canonicalized so q and -q pack identically)
## with `sleeping` in the spare bit. Returns the offset just past what it wrote.
static func pack_quat(out: PackedByteArray, offset: int, rotation: Quaternion, sleeping: bool) -> int:
	return offset + ROTATION_BYTES


## Reads a rotation written by pack_quat(). Always returns a normalized
## quaternion.
static func unpack_quat(data: PackedByteArray, offset: int) -> Quaternion:
	return Quaternion.IDENTITY


## The sleeping flag from the same six bytes unpack_quat() reads.
static func unpack_sleeping(data: PackedByteArray, offset: int) -> bool:
	return false


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
	return offset + BODY_RECORD_BYTES


## Reads one record into {"net_id": int, "position": Vector3,
## "rotation": Quaternion, "sleeping": bool}. A Dictionary rather than a class
## so net/Interpolator.gd can store it without core/ knowing about it.
static func unpack_body(data: PackedByteArray, offset: int, bounds: AABB) -> Dictionary:
	return {}


@warning_ignore_restore("unused_parameter")
