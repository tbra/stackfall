class_name QualityGovernorConfig
extends Resource
## Bontago-1pi.11.37: tunables of the opt-in adaptive quality governor
## (core/QualityGovernor.gd, game/QualityGovernorDriver.gd). Defaults live in
## config/quality_governor.tres.

## Seconds between governor evaluations (the driver only accumulates frame time in between).
@export_range(0.1, 5.0, 0.1) var sample_interval_s: float = 0.5
## Mean frame time (ms) above which the scene counts as stressed (16.7 = 60 fps).
@export_range(5.0, 100.0, 0.5) var target_frame_ms: float = 18.0
## Awake block count at or above which the scene counts as stressed.
@export_range(1, 500) var awake_high: int = 80
## Frame time counts as recovered below target_frame_ms times this ratio (hysteresis band).
@export_range(0.3, 1.0, 0.01) var recover_frame_ratio: float = 0.75
## The pile counts as settled at or below this many awake blocks (keep below awake_high).
@export_range(0, 500) var awake_settled: int = 30
## Seconds of continuous stress before each further step is shed.
@export_range(0.1, 60.0, 0.1) var shed_delay_s: float = 2.0
## Seconds of continuous recovery before each step is restored (longer than shed_delay_s).
@export_range(0.1, 120.0, 0.1) var restore_delay_s: float = 8.0
## Frames longer than this (s) are ignored (loading hitches, window drags).
@export_range(0.05, 5.0, 0.05) var ignore_delta_above_s: float = 0.5
## Step 1: particle_budget_scale while shed.
@export_range(0.0, 1.0) var shed_particle_budget_scale: float = 0.4
## Step 2: weather_density_scale while shed.
@export_range(0.0, 1.0) var shed_weather_density_scale: float = 0.4
## Step 4: sun shadow cascade mode while shed (0 = one split, 1 = 2 splits); never raises a lower preset.
@export_range(0, 2) var shed_shadow_mode: int = 0
## Step 4: sun shadow max distance (m) while shed; never raises a lower preset.
@export_range(10.0, 300.0, 1.0) var shed_shadow_max_distance_m: float = 50.0
## Step 6 (optional): enables the 3D render scale step.
@export var render_scale_step_enabled: bool = true
## Step 6: Viewport.scaling_3d_scale while shed.
@export_range(0.25, 1.0, 0.01) var shed_render_scale: float = 0.75
