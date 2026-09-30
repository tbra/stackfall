class_name FogTuning
extends WeatherTuning
## Fog's tunables (Bontago-470.3). Fog is presentation only: the host sets
## nothing physical (no effect_script), every peer draws it from the replicated
## weather state through vfx/weather/FogPresentation.gd, which asks the Skybox
## (game/Skybox.gd set_weather_fog) and the disc overlay
## (game/TerritoryOverlay.gd set_weather_fog) to fade things with DISTANCE from
## the camera. One instance: config/weather/fog.tres. Every strength scales
## with the ramped intensity.
##
## DECISION (what stays visible): fog does not start until depth_begin_m from
## the camera, so blocks and the disc within about that range keep their full
## colour (the local play area stays readable). It then grows linearly to
## max_opacity at depth_end_m: distant towers, the far half of the disc, the
## far beacons and the sky fade, but never to nothing (max_opacity < 1), so a
## far beacon and the territory contours on the disc stay faintly visible. The
## disc shader opts out of Environment fog, so it applies this same fog itself.

## Fog starts this far from the camera (metres) and is at full max_opacity at
## depth_end_m.
@export var depth_begin_m: float = 25.0
@export var depth_end_m: float = 110.0
## Opacity reached at depth_end_m and beyond (0..1); below 1 so far things stay
## faintly visible.
@export_range(0.0, 1.0, 0.01) var max_opacity: float = 0.75
## Fog tint (cool, milky) and how far the theme's fog colour moves toward it at
## full intensity.
@export var fog_color: Color = Color(0.72, 0.8, 0.88, 1.0)
@export_range(0.0, 1.0, 0.01) var fog_tint_strength: float = 0.85
## How much further the fog washes the sky and horizon at full intensity
## (added to the theme's own fog_sky_affect).
@export_range(0.0, 1.0, 0.01) var sky_affect: float = 0.35
## Fraction of max_opacity used on the Low graphics preset (ambient life off).
@export_range(0.0, 1.0, 0.05) var low_preset_opacity: float = 0.7
## Visibility targets the tests pin (fraction of colour kept at full
## intensity): anything within clear_radius_m keeps full colour; an object at
## far_reference_distance_m (a beacon, a contour) keeps at least
## far_min_visibility.
@export var clear_radius_m: float = 22.0
@export var far_reference_distance_m: float = 100.0
@export_range(0.0, 1.0, 0.01) var far_min_visibility: float = 0.1
