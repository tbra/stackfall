class_name WindTuning
extends WeatherTuning
## Wind's tunables (Bontago-22y.4): the height-weighted push the host applies
## to live blocks (autoload/match/WindEffect.gd) and the client-side streak
## look (vfx/weather/WindPresentation.gd). config/weather/wind.tres is the
## shipped instance. Rules live in core/WindField.gd.

@export_group("Force")
## Horizontal acceleration (m/s^2, mass-proportional) at full intensity, full
## gust and cap height. Gravity is about 9.8, so a 1 m wide tower topples once
## the push at its top out-torques g * width / 2.
@export var max_accel: float = 5.0
## Blocks whose centre is at or below this height above the disc top feel no
## wind at all: low piles are never swept.
@export var threshold_height_m: float = 3.0
## From this height up the push is at its maximum.
@export var cap_height_m: float = 10.0
## Shape of the ramp between threshold and cap (1 = linear, above 1 = gentler
## low down, sharper near the top).
@export var height_exponent: float = 1.0
## Length of one full gust cycle, seconds.
@export var gust_period_s: float = 6.0
## 0..1: how deep gusts dip below the peak (0 = steady wind, 0.6 = the push
## swings between 40% and 100%).
@export_range(0.0, 1.0, 0.01) var gust_amplitude: float = 0.6
## The wind direction wanders +/- this many degrees around its seeded base.
@export var veer_amplitude_deg: float = 20.0
## Seconds for one full veer cycle.
@export var veer_period_s: float = 40.0
## Never push a block faster than this along the wind (m/s).
@export var max_speed_ms: float = 6.0
## Never change a block's velocity by more than this per physics tick (m/s).
@export var max_dv_per_tick: float = 0.1
## A sleeping block is only woken when the push on it is at least this
## (m/s^2); gentler pushes leave settled piles asleep.
@export var wake_accel: float = 1.5
## Sleeping blocks are evaluated one tick in this many (rotating subset), so a
## big settled field costs a fraction of a scan per tick. Awake blocks are
## pushed every tick.
@export var sleeper_stride_ticks: int = 8

@export_group("Presentation")
## Half-width of the square of sky the streaks and motes fill, centred on the
## disc (metres).
@export var area_half_extent_m: float = 55.0
@export var area_min_height_m: float = -6.0
@export var area_max_height_m: float = 34.0
@export var streak_count: int = 170
@export var streak_length_m: float = 6.0
@export var streak_width_m: float = 0.13
@export var streak_speed_ms: float = 16.0
@export var streak_color: Color = Color(1.0, 1.0, 1.0, 0.7)
@export var mote_count: int = 36
@export var mote_size_m: float = 0.4
@export var mote_speed_ms: float = 10.0
@export var mote_color: Color = Color(1.0, 0.66, 0.24, 1.0)
## Scales both counts on the Low graphics preset.
@export_range(0.0, 1.0, 0.05) var low_preset_density: float = 0.4
## Distance (m) beyond which streaks fade out.
@export var fade_far_m: float = 120.0
## Seed offset so streak scatter differs from other seeded visuals.
## Motes fade out between these camera distances (m): none right at the lens.
@export var mote_near_fade_start_m: float = 8.0
@export var mote_near_fade_end_m: float = 26.0
@export var scatter_seed: int = 4404
