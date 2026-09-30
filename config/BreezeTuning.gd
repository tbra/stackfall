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
@export_range(0.0, 1.0, 0.01) var low_strength_factor: float = 0.35
@export var radius_min_m: float = 2.5
@export var radius_max_m: float = 5.0
@export var duration_min_s: float = 2.0
@export var duration_max_s: float = 4.5
## A gust is centred on a live block plus a random offset of up to this
## fraction of its radius (per axis).
@export_range(0.0, 1.0, 0.05) var center_jitter: float = 0.5
## Blocks on one side of the gust axis are pushed this many degrees off the
## heading (opposite on the other side), so a stack wobbles instead of sliding.
@export var swirl_deg: float = 35.0

@export_group("Wire and presentation")
## A client refuses a gust claiming more than these (malformed/hostile).
@export var wire_max_radius_m: float = 30.0
@export var wire_max_duration_s: float = 20.0
@export var wire_max_coord_m: float = 1000.0
## Most gust visuals alive at once on a client.
@export var max_presented_gusts: int = 12
@export var gust_streak_count: int = 26
@export var gust_streak_length_m: float = 2.2
@export var gust_streak_width_m: float = 0.09
@export var gust_streak_speed_ms: float = 7.0
@export var gust_color: Color = Color(1.0, 1.0, 1.0, 0.6)
## Fraction of streaks on the Low graphics preset.
@export_range(0.0, 1.0, 0.05) var gust_low_preset_density: float = 0.4
