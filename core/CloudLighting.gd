class_name CloudLighting
extends RefCounted
## Bontago-mp0.29: the one lighting/weather/cycle state every cloud layer reads
## (the sea below the disc, the puffs, the weather ceiling above it). game/Skybox.gd
## owns the single instance and publishes it whenever the theme, the day/night
## cycle phase, the overcast or the storm blend change; layers never derive their
## own copy. Pure data, no scene tree.

## Emitted by publish() when any value changed.
signal changed

## Cel colours of the cloud palette in effect (theme, cycle-mixed, storm-tinted).
var shadow_color: Color = Color(0.27, 0.32, 0.48)
var mid_color: Color = Color(0.57, 0.41, 0.49)
var lit_color: Color = Color(1.0, 0.6, 0.3)
var rim_color: Color = Color(1.0, 0.78, 0.42)
## Sun by day, the moon's key light by night (unit vector toward the light).
var light_direction: Vector3 = Vector3(0.963087, 0.069011, -0.260192)
var light_color: Color = Color.WHITE
## Day/night cycle: 0 = day, 1 = night (0 outside CYCLE).
var night_mix: float = 0.0
## Weather: overcast amount 0..1 and the storm sky blend 0..1.
var overcast: float = 0.0
var storm: float = 0.0
## Weather grade derived once from overcast/storm (see Skybox): every layer
## darkens by `dim` and moves toward grey by `desaturate`.
var dim: float = 0.0
var desaturate: float = 0.0
## Bontago-mp0.34: brightness floor of the graded puff tones (a deep slate
## colour scaled to `min_brightness` luminance; the shadow and mid tones sit at
## the given ratios of it) and the sun-effect scale (flare, rays, sun glow).
var floor_color: Color = Color(0.0, 0.0, 0.0)
var floor_shadow_ratio: float = 0.55
var floor_mid_ratio: float = 0.8
var sun_scale: float = 1.0
var version: int = 0


## Writes the inputs; emits `changed` only if something differs. Returns true then.
func publish(shadow: Color, mid: Color, lit: Color, rim: Color, direction: Vector3, light: Color,
		night: float, overcast_amount: float, storm_amount: float, dim_amount: float, desaturate_amount: float) -> bool:
	if shadow == shadow_color and mid == mid_color and lit == lit_color and rim == rim_color \
			and direction == light_direction and light == light_color and night == night_mix \
			and overcast_amount == overcast and storm_amount == storm and dim_amount == dim \
			and desaturate_amount == desaturate:
		return false
	shadow_color = shadow
	mid_color = mid
	lit_color = lit
	rim_color = rim
	light_direction = direction
	light_color = light
	night_mix = night
	overcast = overcast_amount
	storm = storm_amount
	dim = dim_amount
	desaturate = desaturate_amount
	version += 1
	changed.emit()
	return true


## Bontago-mp0.34: floor colour (lit tone), its shadow/mid ratios and the sun
## scale. Emits `changed` and returns true only if something differs.
func publish_floor(floor: Color, shadow_ratio: float, mid_ratio: float, sun_effects: float) -> bool:
	if floor == floor_color and shadow_ratio == floor_shadow_ratio and mid_ratio == floor_mid_ratio 			and sun_effects == sun_scale:
		return false
	floor_color = floor
	floor_shadow_ratio = shadow_ratio
	floor_mid_ratio = mid_ratio
	sun_scale = sun_effects
	version += 1
	changed.emit()
	return true


## The weather grade shared by every layer (the puff shader mirrors it):
## desaturate toward luminance, then darken.
static func grade(color: Color, dim_amount: float, desaturate_amount: float) -> Color:
	var luma: float = color.get_luminance()
	var greyed: Color = color.lerp(Color(luma, luma, luma, color.a), clampf(desaturate_amount, 0.0, 1.0))
	return Color(greyed.r * (1.0 - dim_amount), greyed.g * (1.0 - dim_amount), greyed.b * (1.0 - dim_amount), color.a)


## Bontago-mp0.34: the brightest the combined weather darkening may get, with the
## night palette already dark: weather dim is relieved by `night_relief` * night
## so storm and night never stack into black, then capped at `max_dim`.
static func combined_dim(overcast_dim: float, storm_add: float, overcast_amount: float, storm_amount: float,
		night: float, night_relief: float, max_dim: float) -> float:
	var weather: float = overcast_dim * overcast_amount + storm_add * storm_amount
	weather *= 1.0 - clampf(night_relief, 0.0, 1.0) * clampf(night, 0.0, 1.0)
	return clampf(weather, 0.0, clampf(max_dim, 0.0, 1.0))


## Floor colour: `tint` rescaled to luminance `min_brightness * ratio`.
static func floor_for_tone(tint: Color, min_brightness: float, ratio: float) -> Color:
	var luma: float = maxf(tint.get_luminance(), 0.0001)
	var scale: float = min_brightness * ratio / luma
	return Color(tint.r * scale, tint.g * scale, tint.b * scale, 1.0)


## Weather grade followed by the per-channel brightness floor (the puff shader
## mirrors it): the result never drops below `floor` in any channel.
static func graded_floored(color: Color, dim_amount: float, desaturate_amount: float, floor: Color) -> Color:
	var graded: Color = grade(color, dim_amount, desaturate_amount)
	return Color(maxf(graded.r, floor.r), maxf(graded.g, floor.g), maxf(graded.b, floor.b), color.a)


## Share of the sun's effects (flare, god rays, sun glow) that survives the
## weather and the day/night cycle: 1 in clear daylight, 0 at night (moon has
## none), reduced by overcast and almost gone in a heavy storm.
static func sun_effect_scale(night: float, night_fade_end: float, overcast_amount: float, overcast_attenuation: float,
		storm_amount: float, storm_attenuation: float) -> float:
	var day: float = 1.0 - smoothstep(0.0, maxf(night_fade_end, 0.0001), clampf(night, 0.0, 1.0))
	var overcast_keep: float = 1.0 - clampf(overcast_attenuation, 0.0, 1.0) * clampf(overcast_amount, 0.0, 1.0)
	var storm_keep: float = 1.0 - clampf(storm_attenuation, 0.0, 1.0) * clampf(storm_amount, 0.0, 1.0)
	return day * overcast_keep * storm_keep
