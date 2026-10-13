class_name FxEase
extends RefCounted
## Bontago-a3z: shared timing curves for the cartoon gift effects (CartoonBlast,
## FreezeBurst). Pure functions.


## Cartoon pop: 0 before `local_s` reaches 0, eases out to `overshoot` over `pop_s`,
## settles back to 1 over the next `pop_s`, then stays at 1.
static func pop(local_s: float, pop_s: float, overshoot: float) -> float:
	if local_s <= 0.0:
		return 0.0
	if pop_s <= 0.0:
		return 1.0
	if local_s < pop_s:
		return overshoot * out_quad(local_s / pop_s)
	if local_s < pop_s * 2.0:
		return lerpf(overshoot, 1.0, (local_s - pop_s) / pop_s)
	return 1.0


## 1 until `age_s` passes `start_fraction` of `duration_s`, then eases down to 0 at the end.
static func shrink(age_s: float, duration_s: float, start_fraction: float) -> float:
	var start_s: float = duration_s * start_fraction
	if age_s <= start_s:
		return 1.0
	var span: float = duration_s - start_s
	if span <= 0.0:
		return 0.0
	var k: float = clampf((age_s - start_s) / span, 0.0, 1.0)
	return 1.0 - k * k


## Quadratic ease-out of a 0..1 progress.
static func out_quad(k: float) -> float:
	var c: float = clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)
