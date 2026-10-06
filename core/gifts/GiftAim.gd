class_name GiftAim
extends RefCounted
## Bontago-1pi.85.29 / 85.35 (docs/GIFT_PLAYTEST2_PLAN.md): pure camera-aimed gift launch maths,
## no scene tree. Host and client preview both call these functions so the previewed arc equals
## the host's launch. The client's own speed is never an input; only a unit `forward`.


## The unit vector of `forward`, or Vector3.ZERO when it is non-finite or zero length.
static func unit_forward(forward: Vector3) -> Vector3:
	if not forward.is_finite() or forward.length() < GiftAim.MIN_FORWARD_LENGTH:
		return Vector3.ZERO
	return forward.normalized()


## Shortest forward length treated as a direction at all.
const MIN_FORWARD_LENGTH: float = 0.001


## World spawn point of a camera-aimed gift: the cursor surface point moved back along the unit
## `forward` by SpecialTuning.gift_aim_back_m, clamped to at least gift_aim_min_height_m above
## `surface_y`, so the aim line passes through the cursor. An unusable forward returns `cursor`.
static func spawn_point(cursor: Vector3, forward: Vector3, surface_y: float, t: SpecialTuning) -> Vector3:
	var direction: Vector3 = unit_forward(forward)
	if direction == Vector3.ZERO:
		return cursor
	var point: Vector3 = cursor - direction * t.gift_aim_back_m
	point.y = maxf(point.y, surface_y + t.gift_aim_min_height_m)
	return point


## Straight (gravity-free) launch velocity: unit `forward` * `speed`. A non-finite or zero
## forward gives Vector3.ZERO.
static func straight_velocity(forward: Vector3, speed: float) -> Vector3:
	return unit_forward(forward) * speed


## Ballistic THROW launch velocity: unit `forward` with SpecialTuning.gift_throw_up_ratio added
## on Y, renormalised, times SpecialTuning.gift_throw_speed_mps. Non-finite or zero forward gives
## Vector3.ZERO. The client's own speed is never an input.
static func throw_velocity(forward: Vector3, t: SpecialTuning) -> Vector3:
	var direction: Vector3 = unit_forward(forward)
	if direction == Vector3.ZERO:
		return Vector3.ZERO
	var lifted: Vector3 = direction + Vector3.UP * t.gift_throw_up_ratio
	if lifted.length() < MIN_FORWARD_LENGTH:
		return Vector3.ZERO
	return lifted.normalized() * t.gift_throw_speed_mps
