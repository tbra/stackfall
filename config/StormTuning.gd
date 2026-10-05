class_name StormTuning
extends WeatherTuning
## Wind's tunables (Bontago-22y.4): the height-weighted push the host applies
## to live blocks (autoload/match/StormEffect.gd) and the client-side streak
## look (vfx/weather/StormPresentation.gd). config/weather/storm.tres is the
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
## At most this many stable-frozen blocks are woken per physics tick, so a
## storm over a huge settled field cannot wake thousands at once.
@export var max_wakes_per_tick: int = 4
## A frozen block only wakes when it is exposed: a probe of this length (m)
## along some world axis from its centre reaches open air. Buried and
## leeward blocks of a big structure stay frozen.
@export var exposure_probe_m: float = 1.5

@export_group("Presentation")
## Bontago-mp0.81: the ambient wind draws curled swoosh strokes (swoosh_* below);
## the soft bowed wisp look belongs to a Breeze gust now (BreezeTuning gust_*).
## Half-width of the square of sky the streaks and motes fill, centred on the
## disc (metres).
@export var area_half_extent_m: float = 55.0
@export var area_min_height_m: float = -6.0
@export var area_max_height_m: float = 34.0
## Swoosh strokes alive at once at full intensity.
@export var streak_count: int = 36
## Arc length (m, world space) of a swoosh stroke before the per-stroke length variation.
@export var streak_length_m: float = 12.0
## Ribbon width at its thickest (m).
@export var streak_width_m: float = 0.16
## Bontago-mp0.131: strokes are brush strokes. Seconds the head sweeps along the wind drawing the stroke on.
@export_range(0.1, 5.0, 0.05) var streak_draw_on_s: float = 0.9
## Seconds the finished stroke holds before it is wiped away.
@export_range(0.0, 5.0, 0.05) var streak_hold_s: float = 0.6
## Seconds the tail sweeps along the wind erasing the stroke.
@export_range(0.1, 5.0, 0.05) var streak_draw_off_s: float = 0.9
## Feather of the sweeping head and tail edge, as a fraction of the stroke length.
@export_range(0.0, 1.0, 0.01) var streak_reveal_softness: float = 0.25
## Fraction of the length over which each end tapers to a point.
@export_range(0.01, 0.5, 0.01) var streak_tip_taper: float = 0.3
## Streaks fully vanish closer than this to the camera (m) and fade in by
## the end distance: a near streak would otherwise span the whole screen.
@export var streak_near_fade_start_m: float = 14.0
@export var streak_near_fade_end_m: float = 32.0
## Drift (m/s) of a stroke along the wind (Bontago-mp0.134: raised from 3 so the trails travel faster).
@export var streak_speed_ms: float = 7.0
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

@export_group("Swoosh look")
## Largest number of parallel strokes drawn together as one cluster (1 = singles only).
@export var swoosh_group_max: int = 2
## Sideways spacing in meters between parallel strokes of one cluster.
@export var swoosh_parallel_spacing_m: float = 0.6
## Curl radius at the start of the hook, as a fraction of the stroke arc length; the rest of the arc is the lead-in.
@export var swoosh_curl_radius_frac: float = 0.06
## How many full turns the head curls through (0.75 is a hook, 1.0 a loop).
@export var swoosh_curl_turns: float = 0.7
## How much the curl tightens towards its tip (0 = constant radius, 1 = closes to a point).
@export var swoosh_curl_tighten: float = 0.55
## Peak heading swing in radians of the lead-in's S wave.
@export var swoosh_body_swing_rad: float = 0.1
## Ribbon mesh vertex pairs along the stroke; more is smoother.
@export var swoosh_ribbon_segments: int = 56
## Exponent shaping the width profile: above 1 pushes the thickest part toward the curl.
@export var swoosh_width_peak_bias: float = 0.8
## Smallest on-screen length share kept when the wind points straight at the camera (stops strokes collapsing).
@export var swoosh_min_foreshorten: float = 0.25
## Random stroke length variation (0.6 = each stroke is 0.7x to 1.3x the base length).
@export var swoosh_length_variation: float = 0.6
## How much shorter each outer parallel stroke is than the cluster centre (0.2 = 20 percent per step).
@export var swoosh_parallel_shrink: float = 0.2
## Backward lag of each parallel stroke along the wind, as a fraction of stroke length.
@export var swoosh_parallel_lag_frac: float = 0.15
## Where the stroke's tail sits relative to its anchor, as a fraction of stroke length behind the lead-in start.
@export var swoosh_anchor_frac: float = 0.4
## Share of the strokes that are leaders: only these carry the curl at the head, the rest are straight or gently curved lines.
@export_range(0.0, 1.0, 0.05) var swoosh_curl_lead_frac: float = 0.2
