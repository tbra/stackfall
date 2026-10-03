class_name BreezeTuning
extends StormTuning
## Breeze's tunables (Bontago-470.2): an always-on, weak wind layered on top of
## whatever weather is active. It is NOT a weather type (it lives at
## config/breeze.tres, not under config/weather/), so the schedule and the
## lobby never see it. It reuses Storm's rules (core/WindField.gd) through
## StormTuning: max_accel, threshold_height_m, cap_height_m, height_exponent,
## max_speed_ms, max_dv_per_tick, wake_accel and sleeper_stride_ticks mean the
## same thing here, only much smaller. The WeatherTuning fields (id, ramps,
## presentation_scene, effect_script) and Storm's continuous gust/veer/streak
## numbers are unused by Breeze, except fade_far_m and streak_near_fade_start_m /
## streak_near_fade_end_m, which the gust wisps share.
##
## Breeze spawns transient GUST volumes (autoload/match/BreezeEffect.gd): a
## sphere that pushes only the blocks inside it along one heading for a few
## seconds. Gusts are rare near the disc and common high up.

## Master switch (the F4 Physics-area toggle flips the runtime copy).
@export var enabled: bool = true
## Global multiplier on every gust's push (1.0 = as tuned).
@export_range(0.0, 3.0, 0.05) var strength: float = 1.0

@export_group("Gusts")
## Seconds between spawn attempts (host, seeded).
@export var spawn_interval_s: float = 1.2
## At most this many gusts exist at once.
@export var max_active_gusts: int = 6
## Chance an attempt succeeds for a block at/below threshold_height_m; rises
## to 1.0 at cap_height_m (WindField.height_factor).
@export_range(0.0, 1.0, 0.01) var low_spawn_probability: float = 0.04
## Gust strength factor at/below threshold height; rises to 1.0 at cap height.
@export_range(0.0, 1.0, 0.01) var low_strength_factor: float = 0.15
@export var radius_min_m: float = 7.0
@export var radius_max_m: float = 12.0
@export var duration_min_s: float = 3.0
@export var duration_max_s: float = 5.0
## A gust is centred on a live block plus a random offset of up to this
## fraction of its radius (per axis).
@export_range(0.0, 1.0, 0.05) var center_jitter: float = 0.5
## Blocks on one side of the gust axis are pushed this many degrees off the
## heading (opposite on the other side), so a stack wobbles instead of sliding.
@export var swirl_deg: float = 10.0

@export_group("Wire and presentation")
## A client refuses a gust claiming more than these (malformed/hostile).
@export var wire_max_radius_m: float = 30.0
@export var wire_max_duration_s: float = 20.0
@export var wire_max_coord_m: float = 1000.0
## Most gust visuals alive at once on a client.
@export var max_presented_gusts: int = 12
## Wisp strokes per gust. Bontago-mp0.81: a gust draws the soft wisp look (bowed,
## feathered, banded ribbons that draw on, drift along the gust heading and erase);
## the curled swoosh look moved to the ambient Storm wind (StormTuning swoosh_*).
@export var gust_streak_count: int = 24
## Longest wisp in meters (each wisp is a hashed length between the shortest and this).
@export var gust_streak_length_m: float = 12.0
## Shortest wisp in meters.
@export var gust_streak_length_min_m: float = 4.0
## Peak ribbon width in meters (the thickest part, mid-wisp).
@export var gust_streak_width_m: float = 0.3
## Drift speed in meters per second of a wisp along the gust heading.
@export var gust_streak_speed_ms: float = 45.0
## Seconds one wisp takes to draw on, hold and erase before it respawns elsewhere.
@export var gust_stroke_cycle_s: float = 1.0
## Fraction of the wisp cycle spent drawing the wisp on (tail to head).
@export var gust_draw_on_frac: float = 0.35
## Fraction of the wisp cycle spent erasing it from the tail.
@export var gust_erase_frac: float = 0.4
## Fraction of the wisp over which the ribbon tapers to a point at each visible end.
@export var gust_tip_taper_frac: float = 0.3
## Sideways bow in meters at the middle of a wisp.
@export var gust_bow_m: float = 0.6
## Amplitude in meters of the gentle waver along a wisp.
@export var gust_wobble_m: float = 0.25
## Dimmest wisp's opacity as a fraction of the full colour alpha.
@export_range(0.0, 1.0, 0.01) var gust_opacity_min: float = 0.6
## Fraction of the gust radius a wisp may start ahead or behind the centre along the heading.
@export var gust_spread_along_frac: float = 1.0
## Fraction of the gust radius wisps scatter sideways across the heading.
@export var gust_spread_side_frac: float = 1.0
## Fraction of the gust radius wisps scatter vertically.
@export var gust_spread_up_frac: float = 1.0
## Pushes wisps toward the top of the gust volume (1 = even, above 1 = more high up), matching the height-weighted force.
@export var gust_height_bias: float = 1.8
## How much longer high wisps run than low ones (0.8 = top is 0.8 of the base length longer than the bottom is shorter).
@export var gust_height_length_gain: float = 0.8
@export var gust_color: Color = Color(0.9, 0.95, 1.0, 0.85)
## A narrow, flat inner band gives the wisps their cel look.
@export var gust_band_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var gust_band_width: float = 0.28
@export_range(0.0, 0.5, 0.01) var gust_edge_softness: float = 0.14
## Fraction of wisps on the Low graphics preset.
@export_range(0.0, 1.0, 0.05) var gust_low_preset_density: float = 0.4
