class_name RainTuning
extends WeatherTuning
## Rain's tunables (Bontago-22y.5): the wet-friction physics numbers the host
## effect (autoload/match/weather/RainEffect.gd) reads and the streak look the
## client presentation (vfx/weather/RainPresentation.gd) reads. One instance:
## config/weather/rain.tres. Every strength is scaled by the ramped intensity.

@export_group("Physics")
## Friction multiplier on every block at full intensity (1.0 = no change).
## friction = baseline * lerp(1, wet_block_friction_factor, intensity).
@export_range(0.0, 1.0, 0.01) var wet_block_friction_factor: float = 0.18
## Same for the disc's top surface.
@export_range(0.0, 1.0, 0.01) var wet_disc_friction_factor: float = 0.22
## Friction never drops below this (a body must never become a perfect ice).
@export_range(0.0, 1.0, 0.01) var min_friction: float = 0.03
## Skip a friction rewrite when the intensity moved less than this since the
## last write (the framework also gates by weather_schedule.intensity_epsilon).
@export_range(0.0, 0.2, 0.001) var apply_epsilon: float = 0.01
## Seconds between scans for blocks spawned while it rains (they get wet
## within this delay; no per-block signal or contact monitor is used).
@export_range(0.05, 5.0, 0.05) var rescan_interval_s: float = 0.25

## DECISION (Bontago-mp0.21): Jolt cannot do negative friction, so while it
## rains every awake block already sliding also gets a force along its own
## horizontal velocity (never radial, so RING/TWIN maps are not biased).
## Acceleration in m/s^2 at full intensity; 0 turns it off.
@export_range(0.0, 4.0, 0.05) var wet_slide_accel_mps2: float = 0.5
## Horizontal speed (m/s) a block must exceed to be boosted: resting and
## settling blocks stay put.
@export_range(0.0, 2.0, 0.05) var wet_slide_min_speed_mps: float = 0.4
## No boost once the horizontal speed reaches this (m/s): the cap.
@export_range(0.5, 20.0, 0.1) var wet_slide_max_speed_mps: float = 6.0

@export_group("Puddles (client presentation only)")
## Puddle patches on the disc top at full wetness (High/Medium preset).
@export var puddle_count: int = 70
## Fraction of the patches drawn when ambient life is off (Low preset).
@export_range(0.0, 1.0, 0.05) var puddle_low_preset_scale: float = 0.4
## Patch radius range (m).
@export var puddle_radius_min_m: float = 0.7
@export var puddle_radius_max_m: float = 2.2
## Seconds of full-strength rain until the disc is fully wet, and seconds to
## dry completely once the rain stops.
@export var puddle_fill_time_s: float = 80.0
@export var puddle_dry_time_s: float = 150.0
## Height of the patches above the disc top (m), against z-fighting.
@export var puddle_lift_m: float = 0.03
## Dark water colour, lighter rim and the cel sky-glint colour.
@export var puddle_color: Color = Color(0.14, 0.26, 0.42, 1.0)
@export var puddle_rim_color: Color = Color(0.5, 0.68, 0.85, 1.0)
@export var puddle_glint_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var puddle_alpha: float = 0.4
## Small, sparse raindrop rings drawn on the patches.
@export var puddle_ripples_enabled: bool = true
## Shortest/longest seconds between drops on one puddle (per-puddle seeded), and the
## ring's largest radius as a fraction of the puddle.
@export var puddle_ripple_period_min_s: float = 3.0
@export var puddle_ripple_period_max_s: float = 7.0
@export_range(0.02, 0.5, 0.01) var puddle_ripple_radius: float = 0.16
## Narrowest z/x squash of a puddle (1 = round; lower = more elongated).
@export_range(0.2, 1.0, 0.05) var puddle_aspect_min: float = 0.45
## Outline irregularity (0 = smooth oval) and per-puddle darkness spread (0 = uniform).
@export_range(0.0, 0.5, 0.01) var puddle_outline_irregularity: float = 0.18
@export_range(0.0, 0.5, 0.01) var puddle_tint_variation: float = 0.18
## Seeded collection spots (low points): share of puddles drawn around them, how
## many spots, and the spread around a spot (m).
@export_range(0.0, 1.0, 0.05) var puddle_cluster_share: float = 0.6
@export var puddle_cluster_count: int = 6
@export var puddle_cluster_spread_m: float = 5.0

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
