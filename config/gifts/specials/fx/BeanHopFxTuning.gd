class_name BeanHopFxTuning
extends Resource
## Presentation tunables for the Jumping Bean hop effects (game/gifts/specials/fx/BeanHopFx.gd,
## ): a spring ring and dust kick at every take-off and a dust puff at every
## landing. Client-derived on every peer from the bean's own motion (no RPC). Loaded
## from config/gifts/specials/fx/bean_hop_fx_tuning.tres. Visual-only: not in the F4 panel.

## Upward speed (m/s) that counts as a take-off, after the bean rested (below
## rest_speed_mps vertically) for at least rest_ticks physics ticks. A throw or a
## bounce never rests first, so it never reads as a hop.
@export var takeoff_speed_mps: float = 5.0
@export var rest_speed_mps: float = 1.5
@export var rest_ticks: int = 2
## Downward speed (m/s) the bean must have been falling at for a stop to read as a landing.
@export var land_speed_mps: float = 4.0

## Take-off ring: final radius (m), band width (m), lifetime and colour.
@export var ring_radius_m: float = 2.2
@export var ring_width_m: float = 0.35
@export var ring_s: float = 0.35
@export var ring_color: Color = Color(1.0, 0.88, 0.45, 1.0)
## Height of the rings and puffs above the bean's lowest point.
@export var ground_lift_m: float = 0.06

## Dust flipbook (the impact puff atlas): take-off and landing sizes (m), opacity, tint, timing.
@export var takeoff_dust_size_m: float = 2.6
@export var landing_dust_size_m: float = 1.8
@export_range(0.0, 1.0, 0.01) var dust_alpha: float = 0.85
@export var dust_tint: Color = Color(0.92, 0.84, 0.7, 1.0)
@export var dust_fps: float = 30.0
@export var dust_frame_count: int = 16
