class_name FreezeFxTuning
extends Resource
## Presentation tunables for the Freeze activation burst (game/gifts/specials/fx/FreezeBurst.gd,
## Bontago-a3z), drawn by GiftFxPresenter on every peer. Loaded from
## config/gifts/specials/fx/freeze_fx_tuning.tres. Visual-only: not in the F4 tuning panel.
## The frost ring grows to the special's own FreezeEffect.freeze_radius_m.

## Seconds from activation until the whole burst is gone.
@export var duration_s: float = 1.3

## Frost ring: grow time, band width (m), inner fill (0..1), colour and lift above the trigger.
@export var ring_s: float = 0.85
@export var ring_width_m: float = 0.45
@export_range(0.0, 1.0, 0.01) var ring_fill: float = 0.22
@export var ring_color: Color = Color(0.72, 0.93, 1.0, 1.0)
@export var ring_lift_m: float = 0.08

## Ice shards bursting out of the trigger point: count, height and width (m).
@export var shard_count: int = 12
@export var shard_height_m: float = 1.5
@export var shard_width_m: float = 0.42
## +/- fraction applied to each shard's height.
@export_range(0.0, 1.0, 0.01) var shard_height_jitter: float = 0.35
## Shards sit between these distances (m) from the trigger point.
@export var shard_min_distance_m: float = 0.3
@export var shard_max_distance_m: float = 1.6
## Outward lean of each shard from vertical (degrees).
@export var shard_lean_deg: float = 32.0
## Seconds to pop to full size, the overshoot peak, and the random stagger between shards.
@export var shard_pop_s: float = 0.18
@export var shard_overshoot: float = 1.3
@export var shard_stagger_s: float = 0.12
## Fraction of duration_s at which shards start shrinking away.
@export_range(0.0, 1.0, 0.01) var shard_shrink_start: float = 0.55

## Ice colours fed to the cel puff shader (bright face, mid face, shadow) and the outline.
@export var ice_light: Color = Color(0.95, 1.0, 1.0, 1.0)
@export var ice_mid: Color = Color(0.55, 0.85, 1.0, 1.0)
@export var ice_shadow: Color = Color(0.25, 0.5, 0.85, 1.0)
@export var ice_outline: Color = Color(0.08, 0.18, 0.36, 1.0)
@export_range(0.0, 1.0, 0.01) var ice_outline_width: float = 0.2
## Extra brightness on the lightest shards (a cold glint).
@export var ice_glow: float = 0.35
## Per-shard "heat" range for the cel shader (picks between ice_shadow..ice_light).
@export_range(0.0, 1.0, 0.01) var shard_tone_min: float = 0.55
@export_range(0.0, 1.0, 0.01) var shard_tone_max: float = 0.95

## Snowflake flash at the trigger point: size (m), lifetime, spikes and colour.
@export var flash_size_m: float = 3.2
@export var flash_s: float = 0.22
@export var flash_points: int = 6
@export var flash_color: Color = Color(0.85, 0.97, 1.0, 1.0)
