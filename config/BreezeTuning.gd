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
## numbers are unused by Breeze.
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
## Swoosh strokes per gust (Bontago-59o.6): each is a tapered white ribbon that
## draws on, drifts along the gust heading, then erases from its tail.
@export var gust_streak_count: int = 10
## Arc length in meters of one swoosh stroke, tail to curl tip.
@export var gust_streak_length_m: float = 11.0
## Peak ribbon width in meters (the thickest part, just before the curl).
@export var gust_streak_width_m: float = 0.75
## Drift speed in meters per second of a stroke along the gust heading.
@export var gust_streak_speed_ms: float = 24.0
## Largest number of parallel strokes drawn together as one cluster (1 = singles only).
@export var gust_group_max: int = 3
## Sideways spacing in meters between parallel strokes of one cluster.
@export var gust_parallel_spacing_m: float = 1.1
## Seconds one stroke takes to draw on, hold and erase before it respawns elsewhere.
@export var gust_stroke_cycle_s: float = 1.3
## Fraction of the stroke cycle spent drawing the stroke on (tail to head).
@export var gust_draw_on_frac: float = 0.4
## Fraction of the stroke cycle spent erasing it from the tail.
@export var gust_erase_frac: float = 0.35
## Curl radius at the start of the hook, as a fraction of the stroke arc length; the rest of the arc is the lead-in.
@export var gust_curl_radius_frac: float = 0.09
## How many full turns the head curls through (0.75 is a hook, 1.0 a loop).
@export var gust_curl_turns: float = 0.7
## How much the curl tightens towards its tip (0 = constant radius, 1 = closes to a point).
@export var gust_curl_tighten: float = 0.55
## Peak heading swing in radians of the lead-in's S wave.
@export var gust_body_swing_rad: float = 0.22
## Ribbon mesh vertex pairs along the stroke; more is smoother.
@export var gust_ribbon_segments: int = 56
## Fraction of the stroke over which the ribbon tapers to a point at each visible end.
@export var gust_tip_taper_frac: float = 0.12
## Exponent shaping the width profile: above 1 pushes the thickest part toward the curl.
@export var gust_width_peak_bias: float = 0.8
## Fraction of the gust radius a stroke may start ahead or behind the centre along the heading.
@export var gust_spread_along_frac: float = 1.0
## Fraction of the gust radius strokes scatter sideways across the heading.
@export var gust_spread_side_frac: float = 1.0
## Fraction of the gust radius strokes scatter vertically.
@export var gust_spread_up_frac: float = 0.8
## Smallest on-screen length share kept when a gust points straight at the camera (stops strokes collapsing).
@export var gust_min_foreshorten: float = 0.25
## Random stroke length variation (0.4 = each stroke is 0.8x to 1.2x the base length).
@export var gust_length_variation: float = 0.4
## How much shorter each outer parallel stroke is than the cluster centre (0.2 = 20 percent per step).
@export var gust_parallel_shrink: float = 0.2
## Backward lag of each parallel stroke along the heading, as a fraction of stroke length.
@export var gust_parallel_lag_frac: float = 0.15
## Where the stroke's tail sits relative to its anchor, as a fraction of stroke length behind the lead-in start.
@export var gust_anchor_frac: float = 0.4
@export var gust_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Fraction of streaks on the Low graphics preset.
@export_range(0.0, 1.0, 0.05) var gust_low_preset_density: float = 0.4
