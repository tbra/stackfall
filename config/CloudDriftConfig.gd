class_name CloudDriftConfig
extends Resource
## Bontago-mp0.92: tunables of the shared cloud drift (core/CloudDriftMath.gd, core/CloudDriftState.gd).
## One wind drives every cloud layer (3D puffs, sun-occlusion bounds, cloud shadows): a calm
## per-match heading, swung to the storm wind heading and sped up as the storm fades in.
## Loaded from config/cloud_drift.tres; hints in config/tuning_panel_hints.tres.

@export_group("Calm wind")
## Mean heading of the calm cloud wind, degrees from +X toward +Z; each match varies it by
## up to +- calm_heading_jitter_deg from the sky variation seed.
@export_range(0.0, 360.0, 1.0) var calm_heading_deg: float = 35.0
@export_range(0.0, 180.0, 1.0) var calm_heading_jitter_deg: float = 60.0

@export_group("Parallax")
## Multipliers on each clump's own drift speed (SkyThemeDef.cloud_drift_speed_*) by layer
## depth: the nearer the layer, the faster it slides, so the motion reads as depth.
@export_range(0.0, 4.0, 0.05) var upper_rate: float = 1.6
@export_range(0.0, 4.0, 0.05) var sea_rate: float = 1.0
@export_range(0.0, 4.0, 0.05) var bank_rate: float = 0.65
@export_range(0.0, 4.0, 0.05) var far_rate: float = 0.35

@export_group("Storm wind")
## Cloud speed multiplier at full storm (1 = no change).
@export_range(1.0, 10.0, 0.1) var storm_speed_mult: float = 3.5
## Per-second rate the drift heading eases toward the target wind (higher = snappier turns).
@export_range(0.05, 5.0, 0.05) var heading_follow_rate: float = 0.5
## Per-second rate the speed multiplier eases toward its target.
@export_range(0.05, 5.0, 0.05) var speed_follow_rate: float = 0.5

@export_group("Wrap and fade")
## Width (m) of the dissolve band at the edge of the cloud domain, where a clump leaves one
## side and re-enters on the other (invisible as it is fully dissolved at the wrap).
@export_range(10.0, 400.0, 1.0) var edge_fade_m: float = 120.0
## Width (m) of the dissolve band outside the disc exclusion radius: sea clumps drifting
## across the disc fade out instead of entering the play volume.
@export_range(5.0, 200.0, 1.0) var exclusion_fade_m: float = 60.0
