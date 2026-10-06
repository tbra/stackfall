class_name GiftAim
extends RefCounted
## Bontago-1pi.85.35 (docs/GIFT_PLAYTEST2_PLAN.md, P0 contract): pure camera-aimed gift
## launch maths, no scene tree. SIGNATURES ARE THE CONTRACT; the bodies are safe stubs until
## package PA2 (camera-aimed throw) fills them in. Host and client preview must both call these
## functions so the previewed arc equals the host's launch.


## World spawn point of a camera-aimed gift: the cursor surface point moved back along the unit
## `forward` by SpecialTuning.gift_aim_back_m, clamped to at least gift_aim_min_height_m above
## `surface_y`, so the aim line passes through the cursor. Stub: returns `cursor`.
static func spawn_point(cursor: Vector3, _forward: Vector3, _surface_y: float, _t: SpecialTuning) -> Vector3:
	return cursor


## Straight (gravity-free) launch velocity: unit `forward` * `speed`. A non-finite or zero
## forward gives Vector3.ZERO. Stub: returns Vector3.ZERO.
static func straight_velocity(_forward: Vector3, _speed: float) -> Vector3:
	return Vector3.ZERO


## Ballistic THROW launch velocity: unit `forward` with SpecialTuning.gift_throw_up_ratio added
## on Y, renormalised, times SpecialTuning.gift_throw_speed_mps. Non-finite or zero forward gives
## Vector3.ZERO. The client's own speed is never an input. Stub: returns Vector3.ZERO.
static func throw_velocity(_forward: Vector3, _t: SpecialTuning) -> Vector3:
	return Vector3.ZERO
