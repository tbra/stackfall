class_name SunContrast
extends RefCounted
## Bontago-mp0.127: how much stronger the direct sun and how much weaker the sky ambient
## are as the sun climbs, so lit and shadowed block faces read clearly at midday and soften
## at dusk (identity at the horizon and at night). Pure; Skybox applies it in the cycle.


## Weight 0 (horizon / night) .. 1 (sun at or above `full_sin`).
static func height_weight(sun_sin: float, full_sin: float) -> float:
	return smoothstep(0.0, maxf(full_sin, 0.001), sun_sin)


## Multiplier on the direct sun energy: 1 at the horizon, `gain` with the sun high.
static func light_scale(sun_sin: float, gain: float, full_sin: float) -> float:
	return lerpf(1.0, gain, height_weight(sun_sin, full_sin))


## Multiplier on the ambient energy: 1 at the horizon / night, `day_scale` with the sun high.
static func ambient_scale(sun_sin: float, day_scale: float, full_sin: float) -> float:
	return lerpf(1.0, day_scale, height_weight(sun_sin, full_sin))
