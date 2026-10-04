class_name WeatherSkyGrade
extends RefCounted
## Bontago-mp0.128: pure model of how a weather changes the sky's brightness, so the
## rain / storm / snow ordering is testable without a scene. Mirrors Skybox: the sky
## colour is lerped toward the storm theme by the storm blend, then the background
## exposure is scaled by the rain overcast and the snow brightening.


## Sky luminance for a weather: `base` and `storm` are the sky colours of the match theme
## and the storm theme, `blend` the storm sky blend, `overcast_exposure` the exposure
## factor at full overcast, `overcast` its amount, `snow_gain` / `snow` the snow brightening.
static func sky_luminance(base: Color, storm: Color, blend: float, overcast_exposure: float,
		overcast: float, snow_gain: float, snow: float) -> float:
	var mixed: Color = base.lerp(storm, clampf(blend, 0.0, 1.0))
	var exposure: float = lerpf(1.0, overcast_exposure, clampf(overcast, 0.0, 1.0)) \
		* lerpf(1.0, snow_gain, clampf(snow, 0.0, 1.0))
	return mixed.get_luminance() * exposure
