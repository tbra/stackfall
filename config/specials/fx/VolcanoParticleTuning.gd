class_name VolcanoParticleTuning
extends Resource
## Presentation tunables for the Volcano's eruption particles (Bontago-1pi.85.30,
## docs/GIFT_PLAYTEST2_PLAN.md PF). Loaded from config/specials/fx/volcano_particle_tuning.tres
## through VolcanoEffect.particles. Visual-only (client and host build the same cosmetic node), so
## it is not part of the F4 tuning panel and needs no config/tuning_panel_hints.tres entries.

## Ember count of the one-shot burst emitted with every block shot.
@export_range(0, 512, 1) var burst_count: int = 32

## Seconds one ember lives.
@export_range(0.1, 5.0, 0.05) var lifetime_s: float = 1.4

## Initial speed of a burst ember in m/s.
@export_range(0.0, 30.0, 0.1) var speed_mps: float = 9.0

## Hard cap on the live particles of one volcano (burst + plume), before the preset scale.
@export_range(0, 1024, 1) var max_particles: int = 160

## Continuous plume: embers per second between bursts.
@export_range(0.0, 200.0, 0.5) var ember_rate_per_s: float = 20.0

## Initial speed of a plume ember as a share of speed_mps.
@export_range(0.0, 1.0, 0.01) var plume_speed_ratio: float = 0.45

## Half-angle in degrees of the emission cone around up.
@export_range(0.0, 90.0, 0.5) var spread_deg: float = 28.0

## Downward pull on embers in m/s^2.
@export_range(0.0, 40.0, 0.1) var gravity_mps2: float = 9.0

## Ember edge length range in metres.
@export_range(0.01, 1.0, 0.01) var size_min_m: float = 0.12
@export_range(0.01, 1.0, 0.01) var size_max_m: float = 0.28

## Multiplier on the particle counts when the graphics preset turns ambient life off (Low).
@export_range(0.0, 1.0, 0.05) var low_preset_scale: float = 0.4

## Lava colour at birth; the ember cools to cool_color and fades out.
@export var color: Color = Color(1.0, 0.45, 0.1)
@export var cool_color: Color = Color(0.45, 0.08, 0.04)
