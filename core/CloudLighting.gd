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


## The weather grade shared by every layer (the puff shader mirrors it):
## desaturate toward luminance, then darken.
static func grade(color: Color, dim_amount: float, desaturate_amount: float) -> Color:
	var luma: float = color.get_luminance()
	var greyed: Color = color.lerp(Color(luma, luma, luma, color.a), clampf(desaturate_amount, 0.0, 1.0))
	return Color(greyed.r * (1.0 - dim_amount), greyed.g * (1.0 - dim_amount), greyed.b * (1.0 - dim_amount), color.a)
