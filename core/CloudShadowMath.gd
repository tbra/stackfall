class_name CloudShadowMath
extends RefCounted
## Bontago-mp0.127: pure math of the arena cloud shadows (no scene tree). The sweep uses two
## shadow layers (different noise) that cross-fade as each travels `travel` metres, so a
## finite decal never shows its edge: weights sin^2 and cos^2 of the phase add up to 1.


## Shadow strength 0..max for a sun at elevation sine `sun_sin` and daylight 0..1.
static func strength(sun_sin: float, daylight: float, config: CloudShadowConfig) -> float:
	var ramp: float = smoothstep(config.min_sun_sin, maxf(config.full_sun_sin, config.min_sun_sin + 0.001), sun_sin)
	return clampf(config.max_strength, 0.0, 1.0) * ramp * clampf(daylight, 0.0, 1.0)


## Phase 0..1 of cross-fading layer `index` (0 or 1) at time `time_s`; layer 1 runs half a
## period behind layer 0.
static func layer_phase(time_s: float, period_s: float, index: int) -> float:
	return fposmod(time_s / maxf(period_s, 0.001) + 0.5 * float(index), 1.0)


## Opacity weight of a layer at `phase` (0 at both ends of its sweep, 1 mid-way).
static func layer_weight(phase: float) -> float:
	var s: float = sin(PI * clampf(phase, 0.0, 1.0))
	return s * s


## Signed offset (m) along the wind of a layer at `phase`, centred on 0, over `travel`.
static func layer_offset(phase: float, travel: float) -> float:
	return (phase - 0.5) * travel


## Unit ground-plane wind vector (x, z) for a heading in degrees.
static func wind_dir(heading_deg: float) -> Vector2:
	var angle: float = deg_to_rad(heading_deg)
	return Vector2(cos(angle), sin(angle))


## Direct-sun scale (0..1) for a cloud `occlusion` 0..1 of the sun direction.
static func sun_scale(occlusion: float, config: CloudShadowConfig) -> float:
	return 1.0 - clampf(occlusion, 0.0, 1.0) * clampf(config.sun_dim_max, 0.0, 1.0)


## Frame-rate independent follow of `current` toward `target` at `rate` per second.
static func follow(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-maxf(rate, 0.0) * maxf(delta, 0.0)))


## Side (m) of the square shadow volume that always covers a field of `field_radius` after
## the layer sweeps +-travel/2.
static func volume_size(field_radius: float, travel: float, config: CloudShadowConfig) -> float:
	return 2.0 * field_radius * config.field_margin + travel


## Side (m) of the shadow volume: the configured span, never less than the field needs.
static func span(field_radius: float, config: CloudShadowConfig) -> float:
	return maxf(config.span_m, volume_size(field_radius, 0.0, config))


## Travel (m) a layer can sweep without its box edge reaching the field.
static func max_travel(field_radius: float, config: CloudShadowConfig) -> float:
	return maxf(span(field_radius, config) - 2.0 * field_radius * config.field_margin, 0.0)
