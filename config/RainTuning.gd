class_name RainTuning
extends WeatherTuning
## Rain's tunables (Bontago-22y.5): the wet-friction physics numbers the host
## effect (autoload/match/weather/RainEffect.gd) reads and the streak look the
## client presentation (vfx/weather/RainPresentation.gd) reads. One instance:
## config/weather/rain.tres. Every strength is scaled by the ramped intensity.

@export_group("Physics")
## Friction multiplier on every block at full intensity (1.0 = no change).
## friction = baseline * lerp(1, wet_block_friction_factor, intensity).
@export_range(0.0, 1.0, 0.01) var wet_block_friction_factor: float = 0.35
## Same for the disc's top surface.
@export_range(0.0, 1.0, 0.01) var wet_disc_friction_factor: float = 0.4
## Friction never drops below this (a body must never become a perfect ice).
@export_range(0.0, 1.0, 0.01) var min_friction: float = 0.05
## Skip a friction rewrite when the intensity moved less than this since the
## last write (the framework also gates by weather_schedule.intensity_epsilon).
@export_range(0.0, 0.2, 0.001) var apply_epsilon: float = 0.01
## Seconds between scans for blocks spawned while it rains (they get wet
## within this delay; no per-block signal or contact monitor is used).
@export_range(0.05, 5.0, 0.05) var rescan_interval_s: float = 0.25

@export_group("Presentation")
## Streak instances at full density on a High/Medium preset.
@export var streak_count: int = 2400
## Radius of the rain volume around the camera (horizontal, m) and its height.
@export var area_radius_m: float = 32.0
@export var area_height_m: float = 40.0
@export var fall_speed_mps: float = 38.0
@export var streak_length_m: float = 1.6
@export var streak_width_m: float = 0.06
## Sideways drift (m/s) so streaks slant slightly.
@export var slant_mps: float = 3.0
@export var streak_color: Color = Color(0.78, 0.88, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var streak_alpha: float = 0.75
## Camera-distance fade (m): streaks vanish smoothly toward the volume edge.
@export var fade_far_m: float = 30.0
## Fraction of streaks drawn when the graphics preset has ambient life off (Low).
@export_range(0.0, 1.0, 0.05) var low_preset_density: float = 0.3
## Streaks closer than this to the camera fade out (no end-on dots).
@export var near_fade_m: float = 5.0
## Streaks whose on-screen length (fraction of view height-ish, in tan units)
## is below this collapse instead of drawing as dots.
@export var min_screen_length: float = 0.02

@export_group("Overcast (client presentation only)")
## Factors reached at full intensity (1.0 = no change).
@export_range(0.0, 1.0, 0.01) var overcast_light_scale: float = 0.4
@export_range(0.0, 1.0, 0.01) var overcast_ambient_scale: float = 0.8
@export_range(0.0, 1.0, 0.01) var overcast_sky_exposure_scale: float = 0.4
## Fog tint toward this cool grey-blue, and how far at full intensity.
@export var overcast_fog_color: Color = Color(0.5, 0.58, 0.68, 1.0)
@export_range(0.0, 1.0, 0.01) var overcast_fog_strength: float = 0.6
## Wet disc: extra sheen strength and a roughness factor at full intensity.
@export_range(0.0, 2.0, 0.01) var wet_sheen_add: float = 0.0
@export_range(0.0, 1.0, 0.01) var wet_roughness_scale: float = 0.6
