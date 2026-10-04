class_name CloudShadowConfig
extends Resource
## Bontago-mp0.127: tunables of the cloud shadows sweeping the arena (vfx/CloudShadows.gd)
## and of the sun dimming when a cloud covers the sun direction. Loaded from
## config/cloud_shadows.tres; hints in config/tuning_panel_hints.tres.

@export_group("Shadow on the arena")
## Darkest the shadow gets (alpha of the decal at full strength, 0 = no shadows).
@export_range(0.0, 1.0, 0.01) var max_strength: float = 0.6
## Tint multiplied into the shadowed surfaces (cool, so shadows stay colourful).
@export var shadow_color: Color = Color(0.02, 0.025, 0.07, 1.0)
## Share of the sky covered by shadow-casting cloud (0 = none, 1 = overcast).
@export_range(0.0, 1.0, 0.01) var coverage: float = 0.45
## Width of the soft edge of a shadow in noise value (higher = blurrier).
@export_range(0.01, 0.6, 0.01) var edge_softness: float = 0.22
## Typical size of a cloud shadow on the ground, metres.
@export_range(10.0, 300.0, 1.0) var feature_size_m: float = 40.0
## Direction the shadows travel on the ground, degrees from +X toward +Z (the cloud wind).
@export_range(0.0, 360.0, 1.0) var wind_heading_deg: float = 35.0
## Multiplier on the mean cloud drift speed (SkyThemeDef.cloud_drift_speed_*) to get the
## shadow ground speed, so the sweep reads at the arena's scale.
@export_range(0.5, 30.0, 0.5) var speed_scale: float = 5.0
## Seconds one of the two cross-fading shadow layers takes to sweep its travel distance.
@export_range(5.0, 120.0, 1.0) var layer_period_s: float = 30.0
## Sun elevation (sine) below which shadows are gone, and above which they are full.
@export_range(0.0, 1.0, 0.01) var min_sun_sin: float = 0.12
@export_range(0.0, 1.0, 0.01) var full_sun_sin: float = 0.5
## Shadow volume margin over the field radius, and its height reference (m above the disc).
@export_range(1.0, 3.0, 0.05) var field_margin: float = 1.35
## Ground span (m) one shadow layer's noise covers; a layer sweeps at most span - field diameter.
@export_range(100.0, 1200.0, 10.0) var span_m: float = 360.0
@export_range(0.0, 100.0, 1.0) var volume_height_m: float = 72.0
## Side (px) of the generated shadow noise textures.
@export_range(64, 1024, 1) var noise_texture_size: int = 256
@export_range(0, 1000000, 1) var noise_seed: int = 4127

@export_group("Sun dimming")
## How much of the direct sun is lost when the sun direction is fully covered by clouds.
@export_range(0.0, 1.0, 0.01) var sun_dim_max: float = 0.55
## Per-second rate the dimming follows the cloud occlusion (higher = snappier).
@export_range(0.1, 20.0, 0.1) var sun_dim_rate: float = 2.5
## Seconds between cloud occlusion queries (0 = every frame).
@export_range(0.0, 2.0, 0.01) var occlusion_refresh_s: float = 0.1
## Height above the disc origin (m) the sun ray is cast from.
@export_range(0.0, 100.0, 1.0) var sun_ray_origin_height_m: float = 30.0
